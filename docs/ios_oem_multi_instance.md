# iOS 多开与 Android 厂商分身：可用信号和边界

本批规则首次使用 `local-v3`（当前 Android `local-v7` / iOS `local-v8`），沿用 `SecurityDetectors.multiInstance`，无需新增权限、网络或设备指纹。
`capabilities.supported == true` 代表存在局部探针，不代表能确认所有多开产品。SDK 只返回具体信号，
不把工作资料、私密空间、合法沙箱或改签应用直接判为恶意，不自动封禁。

## 1. 公开 API 能做什么

| 环境 | 可用方案 | 不能据此推断的结论 |
| --- | --- | --- |
| iOS 容器加载的客体 App | 检查自身 App Bundle、主执行文件身份与有界 Mach-O 头 | 不枚举已安装 App；不证明同时存在/运行多个副本；不能覆盖完全改写探针的容器 |
| iOS 改 Bundle ID 后独立安装 | 现有 App Integrity 与宿主可信 Bundle ID 基准比较 | 改 ID 是身份基准不匹配，不是多开证明；多个获授权渠道可有不同 ID |
| iPad 多窗口 / 多 Scene | 不作为多开证据 | 同一 App 的正常多窗口不等于克隆 |
| Android 工作资料 | API 30+ `UserManager.isManagedProfile()` | 只说明工作资料，不说明克隆或恶意 |
| Android 非工作资料的 profile | API 33+ `isProfile()`；API 35+ 查询当前用户 `LauncherUserInfo.userType` | 仅精确 CLONE 返回 `cloneProfile`；PRIVATE/未知类型/null 仍无法判断 |
| Android 厂商双开 | 复用已知容器目录或 UID + 框架类交叉证据；没有这些证据时保留未知/未见已知痕迹 | API 35+ 可识别系统公开的 CLONE 类型，但不覆盖所有厂商实现；品牌、user 999、非主用户都不是充分证据 |

依据：[Android UserManager 公共接口与版本](https://developer.android.com/reference/android/os/UserManager)、
[AOSP 多用户和厂商自定义类型](https://source.android.com/docs/devices/admin/multi-user)。
AOSP 中 `isCloneProfile`、`isPrivateProfile` 带 `@SystemApi` / `@hide`，`getProfileType` 为内部实现；
SDK 不反射调用这些接口。API 35 起采用公开的
[LauncherApps.getLauncherUserInfo](https://developer.android.com/reference/android/content/pm/LauncherApps#getLauncherUserInfo(android.os.UserHandle)) 与
[LauncherUserInfo.getUserType](https://developer.android.com/reference/android/content/pm/LauncherUserInfo#getUserType())。
仅传 `Process.myUserHandle()`；不枚举用户、不读取序列号、不申请隐藏资料/跨用户权限或 Launcher 角色。
[AOSP LauncherAppsService](https://github.com/aosp-mirror/platform_frameworks_base/blob/master/services/core/java/com/android/server/pm/LauncherAppsService.java)
允许调用者访问自身用户；OEM 返回 null 或拒绝时保留未知，不尝试越权回退。
见 [UserManager 上游源码](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/os/UserManager.java)。
iOS 的隔离边界见 [Apple App 安全与沙箱](https://support.apple.com/en-in/guide/security/sec15bfe098e/web)，
多窗口语义见 [Apple 多窗口文档](https://developer.apple.com/documentation/uikit/supporting-multiple-windows-on-ipad)。

## 2. iOS：只检查本 App 声明的执行身份

探针在后台串行队列运行：读取 `Bundle.main` 的 Bundle/可执行文件 URL、`CFBundlePackageType`、
`_NSGetExecutablePath` 和 `NSHomeDirectory`。只接受 APPL 的 `.app`，主可执行文件必须直接属于该 Bundle；
扩展、framework 和非 App 宿主返回 `unsupported/unsupportedProcess`。

对路径规范化并解析符号链接后，打开本进程声明的两个执行文件，确认是普通文件并比较 device/inode。
`O_NONBLOCK` 防止 FIFO 阻塞，`O_NOFOLLOW` 拒绝解析后的末端符号链接竞争。路径缓存最多 4096 字节；
不扫描其他应用或目录、不读取代码段、不写沙箱外文件、不读取 Keychain 或持久设备标识。
文件元数据用于自身 Bundle/容器检查，沿用隐私清单 C617.1；路径、inode、头部字节都不返回 Dart 或日志。

| status / reason | 条件和解释 |
| --- | --- |
| `detected/appExecutableIsLibrary` | APPL 主可执行文件的匹配 CPU Mach-O 头为 `MH_DYLIB`；这是客体被改为动态库的结构信号，不检查 App 内其他 dylib |
| `detected/embeddedAppBundle` | 主文件为 `MH_EXECUTE`；Bundle 位于自身报告的数据目录 Documents/Library/tmp 内；与进程主执行文件不是同一文件，且后者在该数据目录之外的另一 `.app` |
| `notDetected/noKnownSignal` | 正常 `MH_EXECUTE`，两个执行文件身份一致；仅表示未见上述痕迹 |
| `error/processIdentityMismatch` | Bundle/主文件关系异常，或文件身份不同但缺少完整宿主/客体布局证据；不猜测多开 |
| `unsupported/executableFormatUnavailable` | 非受支持 Mach-O 类型、没有匹配 CPU、多个同 CPU 切片无法安全选择或 fat 切片超过 16 |
| `error/processIdentityUnavailable` | 文件缺失、非普通文件、头损坏/截断或身份不可读取；不降为正常 |
| `error/probeAccessRestricted` / `scanLimitExceeded` | 文件权限受限 / 可执行路径缓冲区不足 |

Mach-O 解析支持 32/64 位、两种字节序和 fat32/fat64；只读取 fat 表及选中切片头，最多 560 字节，
校验文件边界、切片长度和声明的 load-command 大小，不扫描 load commands/代码内容或验证签名。
未知格式和不确定切片不作阳性。不同路径的硬链接、符号链接正常解析后仍按文件身份比较。
普通 App 中的 `*.debug.dylib`、framework、动态库和多 Scene 不触发主可执行文件类型规则。
`_NSGetExecutablePath` 的公开语义与路径别名限制见 [Apple dyld 手册](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/dyld.3.html)。

**不能只比较两个路径字符串。** [LiveContainer 上游设计说明](https://github.com/LiveContainer/LiveContainer/blob/main/README.md)
明确描述改写 `NSBundle.mainBundle`、`_NSGetExecutablePath`，并把客体 `MH_EXECUTE` 改成 `MH_DYLIB`。
据此推导并增加了文件类型规则；这不是该产品任何版本的实机检出承诺。若文件头、路径、文件 API 或 SDK
本身也被伪造，仍可能漏检。合法开发容器也可能产生同类阳性，业务应看具体 reason，不能直接认定攻击。
普通重签/企业/TestFlight/其他分发、安装 UUID 和 Team ID 不参与本探针判定。

## 3. Android：修复公共 API 版本与未知状态

先运行 [既有容器交叉检查](hidden_environment.md#4-android-多开结构与身份交叉检查)，已观察到的明确容器信号
不受后续 profile API 缺失影响。只有没有这些证据时，按下表检查自身 profile：

| 系统/结果 | 输出 |
| --- | --- |
| API 24–29 | `unsupported/profileTypeUnavailable`；不调用尚未公开的 isManagedProfile |
| API 30+ 且 managed == true | `detected/managedProfile`，保留合法工作资料语义 |
| API 30–32 且 managed == false | `unsupported/profileTypeUnavailable`，不能推导没有 clone/private profile |
| API 33–34，managed == false 且 profile == true | `unsupported/profileTypeUnavailable`；不调用 API 35 接口 |
| API 35+ 非工作 profile，userType 精确为 `android.os.usertype.profile.CLONE` | `detected/cloneProfile`，仅说明 OS 标记为克隆资料 |
| API 35+ 非工作 profile，类型为 PRIVATE、未知值或 null | `unsupported/profileTypeUnavailable`，不把私密空间当分身 |
| API 33+，managed == false 且 profile == false | `notDetected/noKnownSignal`，不是不存在厂商分身的证明 |
| 查询抛异常 | 按原生错误处理返回 error，不以默认 false 掩盖失败 |

API 30 前的工作资料识别因此明确降为未知；这比调用隐藏接口或误报正常更保守。不使用跨用户权限、
`QUERY_ALL_PACKAGES`、其他 App 枚举、固定 user ID、品牌黑名单或多个安装目录数量作为判据。
OEM 未通过标准 profile 暴露的克隆、未知容器和 API 伪造仍是缺口。

## 4. 接入、测试和实施顺序

调用方式不变；core 和 Flutter 插件一起升级以识别新增 reason。`unsupported/error` 既不是阳性，也不是安全。
宿主应保留具体 reason 和规则版本；本地检测不能代替服务端授权或硬件证明。

自动化覆盖 API 版本门禁、未知/私密 profile、异常不回落正常、iOS 正常与客体文件布局、路径别名、
缺文件/目录/FIFO、主文件动态库、普通附属 dylib、Mach-O 截断/越界/超预算及桥接语义。
这些 fixture 不运行第三方容器产品；正常模拟器集成和未签名 Release 构建记录见 [roadmap](roadmap.md)。

后续按以下顺序推进：

1. 授权真机校准：各厂商普通用户、工作资料、私密空间和双开逐项记录 OS/产品版本、status/reason；
   同时测正常 iPhone/iPad 多 Scene、Debug/Release、企业/TestFlight/商店分发。当前没有这些实测证据。
2. 授权容器矩阵：记录真实 iOS/Android 容器版本和上述两类信号是否仍可见；正常开发容器也加入误报样本。
3. 只有厂商提供普通 App 可用、稳定且有明确语义的公开接口时，才新增可选适配；不先加反射/UID 猜测。
4. 按结果决定是否扩展平台证明及后端验证；本轮不实现平台证明、第三方指纹或业务封禁。

本轮新增规则的自动化范围与真机待验收清单见 [隐藏环境验收](hidden_environment_acceptance.md)。

2026-11-14 iOS 来源补强、有界采集与真机待验收见 [ios_hidden_review.md](ios_hidden_review.md)。

当前 dyld 安全复制与代际校验、独立真机矩阵见 [ios_dyld_snapshot.md](ios_dyld_snapshot.md)。
