# 本地安全检测审查记录（2026-11-13）

本次审查覆盖 Dart 输入/桥接/销毁、Android 与 iOS 环境和运行时检测、截图生命周期，以及
完整性基准。第三方设备指纹不在实现范围。下列“已修复”指代码与对应回归覆盖；实机效果与
系统版本矩阵仍需单独验收。准确测试记录见 [roadmap](roadmap.md)。

## 已修复的问题

| 优先级 | 原行为与风险 | 本次修复 | 验证 |
| --- | --- | --- | --- |
| P1 | Android 模拟器检测把 fingerprint 的 unknown/generic 前缀或 generic 品牌/设备直接判为模拟器；model/hardware/product 任意子串也可误命中 | 不再使用这些通用构建字段；保留明确的模拟器型号/产品前缀、Genymotion 和精确 goldfish/ranchu 硬件名 | 正常/通用构建、偶然包含关键词的字段、已知模拟器原生单测 |
| P1 | Hook 的 maps 读取成功但不可解析时，可能返回 notDetected；同名文件只映射为数据也会被当作 Hook 模块 | 校验地址范围、权限、offset、device、inode；空白/损坏数据返回 error；已知文件名还需可执行映射 | 损坏/截断、无路径匿名映射、数据映射与可执行映射原生单测 |
| P1 | Android 仅在 stopped 时打断截图观察，paused 后恢复可能继续沿用覆盖不完整的旧窗口 | paused 即中断并释放回调；迟到事件不会恢复已中断窗口；返回前台需显式 start | 独立观察状态回归；Activity 回调接线编译检查，系统暂停/恢复仍需设备验收 |
| P1 | iOS 截图窗口没有绑定原 UIWindow；宿主更换视图时可能继续沿用旧窗口；未采用 UIScene 的宿主始终被当作非前台 | 绑定弱引用原窗口，变更后失效；按是否采用 UIScene 选择前台状态与失活通知；旧式宿主录屏读取对应 UIScreen | iOS 编译与现有模拟器集成；旧式 UIKit、Scene/窗口迁移需独立宿主验收 |
| P1 | 桥接层只检查枚举值，不拒绝 notDetected + probeAccessRestricted、detected + noKnownSignal 等矛盾结果 | 校验状态/原因，成功结果还校验检测项；完整性通过必须带 signingBaselineMatched 或 bundleBaselineMatched；无原因成功结果、非整数协议版本拒绝 | Dart 桥接反例与正确结果回归 |
| P2 | 原生 dispose 永不回复会导致调用方永久等待 | 受 operationTimeout 约束；超时后仍保持 disposed，迟到异常被消费，不重新收集 | 延迟销毁、重复销毁、新请求拒绝与迟到异常回归 |

Android `Build.UNKNOWN` 表示不可获得的构建属性，本身没有模拟器语义；收紧规则的代价是某些
仅暴露 generic 标记的未知模拟器可能不再命中，不能把结果解释为物理真机证明。
依据：[Build](https://developer.android.com/reference/android/os/Build#UNKNOWN)。
maps 的字段与可执行权限语义依据 [Linux proc_pid_maps 手册](https://man7.org/linux/man-pages/man5/proc_pid_maps.5.html)。

桥接校验不是抗篡改机制：被 Hook 的原生代码仍可构造语义正确的假数据。为兼容旧插件，仅
error/unsupported 可以省略 reason；不能将这种结果映射为安全。自定义 SecurityPlatform
实现仍需遵守自身协议，原生内建协议校验不会强加到第三方 provider 接口。

## 保留的误报风险与检测缺口

| 检测 | 合法场景/误报风险 | 尚未覆盖的情况与接入要求 |
| --- | --- | --- |
| Root / 越狱 | test-keys 只说明构建签名类型；自定义 ROM、残留工具文件不是正在获得 root 的证明；路径拒绝访问是未知 | 隐藏/重命名 su、Magisk/Zygisk 隐藏、rootless 布局变化、系统调用被 Hook；不做权限提升或破坏性写入探测 |
| Hook | 合法测试插桩、宿主自己集成的同名库/类也会命中 | 无已知来源痕迹的匿名或重命名模块、inline hook、Swift/ObjC swizzling、函数替换、ClassLoader 隔离；dyld 数量前后相同不保证绝对一致快照，动态装卸竞争仍需压力验收 |
| Debugger | 开发、QA 附加调试器属于正常用途；waitingForDebugger 表示等待而非已附加 | Dart VM 服务、隐藏追踪、被改写的内核查询；iOS Release 仍需显式启用且存在 ABI 限制；无物理设备分发验收 |
| App Integrity | upload key / app signing key 混淆、轮换或渠道基准过旧会报不匹配；iOS App Store thinning/加密/重签可改变非稳定文件 | Android 只比较 PackageManager 返回的身份/签名元数据；iOS 只检查所列资源，不检查 Apple 签名、全部可执行代码或内存；不是服务端证明 |
| 模拟器 / 多开 | 工作资料是合法隔离；合法沙箱/测试框架也可能具有容器结构或身份差异；已知 Build 字段仍是启发式 | 未知模拟器、厂商分身、私密空间、克隆容器伪装；iOS 仅覆盖特定自执行文件/客体布局痕迹，不能枚举副本；不增加包枚举或设备身份采集 |
| 自动化 / 无障碍 | 已启用手势服务只表示能力，可能是正常辅助用户；VoiceOver/Switch Control 不是攻击 | Appium、ADB 输入、外部控制、未暴露手势能力的自动化不保证可见；iOS 自动化仍 unsupported；不得单凭辅助功能封禁 |
| VPN / 代理 | 企业 VPN、系统 utun、合法 PAC 都可能命中；代理配置不证明业务请求实际走代理 | 分流、透明代理、自建隧道、请求级代理、隐藏接口；Android 无默认网络仅表示该观察范围没有活动网络，不能证明后续请求安全 |
| 时间 | 未计网络不确定性、错误服务器时钟、旧参考重新构造会造成偏差 | 没有可信参考不检测；主机休眠/恢复的计时行为需平台实测；重启/长期后台后宿主应刷新参考；后端自行验证 challenge 时效 |
| 截图 / 录屏 | 镜像也属于 screenCaptured；iOS 截图通知没有精确 Scene 归属；生命周期中断可能只得到 error | 观察开始前、ADB/工具抓屏、外部摄像机、OS 未发通知不覆盖；未注册通用监控流；宿主负责在业务页面离开时 stop |
| 位置 | 开发模拟位置可以是合法测试；外设提供坐标本身不算伪造 | 无标记不证明真实坐标；无线信号欺骗、来源字段被改写不覆盖；iOS fix 年龄依赖设备墙钟；只接已有合法定位流程 |

这些项目保留具体 reason，SDK 不汇总“危险设备”结论、不内置业务分数或自动拦截。
一批检测按不同时间点执行，`SecuritySnapshot.observedAt` 是组装结果的时间，不是每项信号的
独立采集时间，也不是原子设备快照；关键操作前由宿主发起新扫描，勿无限期复用旧结果。

## 后续实施顺序

1. **真机与合法环境校准**：Android 24–33/34/35+，iOS 13–16/17+；正常 ROM、GSI、工作资料、
   辅助功能、企业 VPN、分流/PAC，先记录 error/unsupported 与误报率。增加旧式 UIKit、多 Scene、
   双前台 engine/多 Scene（前台 + headless 已有集成回归）、Activity 暂停/恢复和真实录屏/截图正例。当前自动化不能代替此项。
2. **发布基准流程**：用真实渠道签名与最终稳定资源建立版本/渠道对应基准；验证 Android 多签与
   轮换、iOS 分发产物，再由宿主完成基准更新和过期处理。SDK 不内置任何项目的基准或网络地址。
3. **对抗覆盖**：在授权测试设备评估隐藏 Root、动态模块装卸、已知/重命名 Hook、JDWP/LLDB
   附加/解除，按实测证据决定是否增加探针；不以堆叠不稳定/高误报检查代替有效覆盖。
4. **可选平台证明**：确有联网业务时，再设计 Play Integrity / App Attest 与服务端 challenge、
   验签/重放防护；这部分目前未实现，离线项目不被强制依赖。第三方指纹继续暂不实现。

销毁超时只终止 Dart 等待，不保证已经中断所有原生工作或回调；资源最终还受 engine detach
清理。不要把销毁失败当作清理已确认，也不要反复调用 start 来规避失败。

## 第二轮：隐藏痕迹与多开交叉证据

已增加 Root 框架挂载关联、已知 memfd agent、Zygisk 可执行映射来源、iOS rootless/注入目录
已加载镜像，以及 Android 多开目录结构和 UID/框架类交叉检查。旧的任意容器路径子串判断已移除。
实现范围、误报排除、规则预算及新增 reason 详见 [hidden_environment.md](hidden_environment.md)。
上述剩余缺口仍成立；此次覆盖的是隐藏后仍保留已知痕迹的部分情况，不代表完全隐藏环境已解决。

## 第三轮：iOS 与厂商分身边界

- 修复 Android `isManagedProfile` 的公共 API 30 门禁；API 33 前非工作资料、API 33+ 无法区分的
  profile 均返回 `unsupported/profileTypeUnavailable`。不使用隐藏 clone API 或固定用户编号。
- 增加 iOS 自身 APPL 主文件的 Mach-O 类型与宿主/客体文件身份规则；单纯路径差异不是阳性，
  普通附属 dylib、扩展、符号链接、硬链接、多 Scene 不作为克隆证据。
- 复核上游容器同时改写 Bundle 与执行路径的行为，避免把二者一致解释为可靠身份认证；新增主文件
  `MH_DYLIB` 结构信号仍可能被隐藏。它不证明非法使用，也不证明产品级检出率。
- 原生规则提升为 `local-v3`，新增 reason 纳入桥接校验；未知格式/版本/查询失败不会回落安全。

详细条件、公开接口依据和未完成真机矩阵见 [ios_oem_multi_instance.md](ios_oem_multi_instance.md)。
第三方指纹、设备枚举、跨用户访问与业务自动封禁仍未实现。

Android library lint 复核同时补齐 VPN/录屏显式权限检查，截图检查改为显式分支并移除 TargetApi
抑制，注册/释放均受版本与权限防护。SDK 不自动声明宿主可选权限，因此仅在 vpn、startScreenshot、
screenRecording 三个已检查方法局部抑制 MissingPermission，保留原生 SecurityException 边界处理；
没有全局关闭 lint 或扩展权限。当前 lint 0 error、1 条 AGP 升级提示；缺权限实机组合仍需验收。

## 第四轮：低版本兼容与保守降级

修复 Android 无精度/非有限精度位置样本、iOS 正无穷精度及毫秒转换溢出；未知来源保持 null。
iOS 隧道检查收紧数字编号、UP/RUNNING 和 IP 地址族，增加有界名称读取与条目预算；仍不保证 VPN 确证。
集成用例不再把旧 Android 的截图/profile unsupported 当成失败，新增跨 SDK 框架回归与完整 iOS 13
最低目标编译检查。具体边界、测试层次与未验收事项见 [compatibility_review.md](compatibility_review.md)。
原生规则提升为 local-v4；第三方指纹仍不实现。

## 第五轮：多 engine 与截图/录屏生命周期

原生规则为 `local-v5`。修复 Dart start/stop/dispose 交错清理竞态、Android 暂停/失焦/重绑与注销
失败重试、iOS App/Scene/窗口观察失效和 token 释放，以及混合异步扫描跨生命周期返回旧 capture
结果的问题。中断保持 error，不产生新的风险阳性；不自动恢复窗口。新增回归覆盖独立 owner/engine、
迟到回调、清理异常与 headless engine。详细审查、宿主实施顺序、平台归属限制及未验收矩阵见
[capture_lifecycle.md](capture_lifecycle.md)。第三方指纹仍不实现。

## 第六轮：多 Scene、旋转、分屏与画中画

`local-v6` 修复 Scene 观察被 App 通知误中断、Window 的 Scene/Screen 身份缺失、Android decor
重新挂载监听续接及 PiP 前提漏检。异步返回发现缺口时也永久失效原观察。同一窗口的尺寸/方向变化
不主动清零截图证据；真实失焦、暂停和配置重建保持 error。分屏/PiP 不作为风险阳性。
新增原生策略与系统旋转/PiP 集成回归；真实双 Scene、物理设备/OEM 和分屏矩阵仍待验收。
实施顺序、平台边界与测试层次见 [scene_window_lifecycle.md](scene_window_lifecycle.md)。第三方指纹仍不实现。


## 第七轮：真实系统模式验证与报告可信度

补齐独立 UISceneSession + FlutterEngine、双 APK 分屏与离线 AVKit PiP 的 Debug 验证夹具，
以及显式设备运行器。规则仍为 `local-v6`，SDK 生产检测代码与协议未变更。重点是区分真实模式、
生命周期中断与风险阳性，防止以请求成功或普通前后台切换冒充目标模式验证。

实测发现并修复验证工具本身的两项问题：跨 APK 自定义 ResultReceiver 不能反序列化；Flutter
驱动在构建失败后可能运行已安装旧产物。现在用系统 Parcelable 类型传递回调、缺回报记失败；
先独立构建成功再指定产物运行，报告必须具有 OS 状态、回调与 SDK 断言证据。失败/blocked 不计通过。
AVKit 自动改变平台无障碍语义，PiP 原生流程放在测试 setup 中执行并保留清理检查，未关闭 SDK 的
无障碍检测或放宽前台判断。

完整命令、误报边界、M1–C1 真机矩阵及人工/自动化分工见
[real_window_validation.md](real_window_validation.md)，实际运行结果见 roadmap 最新一节。
iPad 双活、Scene 回收、Home/锁屏 PiP 与物理截图正例必须逐项验收，不以本轮夹具存在代替通过。
第三方指纹仍不实现。


## 第八轮：真实 Scene 关闭与 engine 回收

定位到 iPad 模拟器后台目标的销毁请求被 SpringBoard 否决，并非已经关闭而 SDK 漏回调。
修复 Debug 验证宿主：完整命名配置、Flutter Scene 生命周期转发、临时 Scene 不做状态恢复，
以及显式激活目标再关闭的流程。系统拒绝或缺少回调继续是失败，不将 API 请求返回当作成功。

三轮真实创建/关闭均要求系统会话移除、一次真实断开、一次清理及 engine/plugin/controller/window
弱引用释放；子 SDK 不预先 dispose，以验证 engine detach 清理。主 Scene 恢复不能清除旧观察的
中断，显式重开后才正常。报告拒绝部分轮次、重复轮次、无回调和残留资源；setup/清理异常明确失败。

[详细定位、原始失败边界和通过证据](real_window_validation.md)。原始后台直接关闭路径、双活
Scene 与物理设备矩阵仍不宣称通过。此轮不修改生产检测规则或第三方指纹。

## 第九轮：隐藏 Root/Hook 与厂商 profile 的明确证据

Android 规则提升为 `local-v7`，iOS 保持 `local-v6`。修复三项范围缺口：

- 系统 overlay 的 lowerdir/upperdir/workdir 暴露框架目录，但原规则未检查选项：增加受限目录
  解析与 metamodule 路径；普通 overlay、KSU 标签和 context 不作为阳性。
- LSPatch 的已知可执行库名缺失：增加精确模块匹配与 maps 条目预算，不扩大到任意 JIT/RWX。
- API 35 已有公开类型查询：仅查询自身用户的 CLONE，增加 `cloneProfile`；低版本跳过新 API，
  PRIVATE/null/OEM 类型和权限失败不变成正常或克隆。

105 项 Android JVM（含框架）回归、60 项 Dart/Flutter、25 项 Python 回归通过；Android lint
0 errors，2 条依赖版本更新提示。框架测试使用受控系统响应，不代表 OEM 真机检出率。
模拟器集成用例版本断言已按 Android/iOS 分开，本轮未重跑设备集成。

[独立真机验收矩阵与剩余缺口](hidden_environment_acceptance.md)。第三方指纹、跨用户查询、
平台证明和业务拦截仍未实现；完整隐藏、重命名/匿名化 Hook、非标准 OEM 分身仍可能漏检。


### iOS 隐藏环境复核（2026-11-14）

iOS local-v7 补齐 ElleKit 与 rootful 注入来源、统一路径校验、有界 UTF-8 复制与两轮镜像身份核对。
新增 10 项 Swift 回归；完整隐藏与 dyld 并发指针生命周期仍未解决。真机待验收独立记录于
[ios_hidden_review.md](ios_hidden_review.md)。


### iOS dyld 并发复核（2026-11-14，local-v8）

改用本进程内核复制和 dyld 代际校验，移除对 dyld 所有名称指针的直接解引用，保守拒绝 ABA、
忙碌发布数组、权限/短读/未知布局。修复合法系统镜像重复分隔符导致整体误降级。
新增 12 项回归，含真实 macOS dlopen/dlclose 和失效页复制；真机验收单列于
[ios_dyld_snapshot.md](ios_dyld_snapshot.md)。

### example 完整 API 与模拟器回归（2026-11-14）

补齐 14 项单项/全量扫描和全部已实现方法，澄清 start 仅对有效窗口幂等。
修复测试初始化、滚动点击及系统录屏授权时序；报告拒绝空执行和外部导出冒充阳性。
Android API 35 与 iOS 26.5 模拟器通过；Android 系统 MediaProjection 阳性通过。
[完整结果与真机待验收清单](example_device_validation.md)。第三方指纹仍未实现。

### Flutter 最低版本与最新 stable 兼容（2026-11-14）

公共 SDK 与根 example 支持范围调整为 Flutter ≥3.38.10 / Dart ≥3.10.9 且 <4.0.0。
移除插件对宿主 AGP/Kotlin 的版本强制，按 AGP 8/9 分别显式应用外部 Kotlin/委托 Flutter 迁移桥接；
根 example 保留 Scene 并使用 CocoaPods，专用高级夹具独立解析依赖、维持 3.44.9 下限。
兼容性 runner 每个 Flutter 使用隔离副本，工具链脚本对未知模板拒绝改写；新增 4 项回归。

3.38.10、3.44.9、3.50.0 均通过每版 76 项测试、分析及 Android/iOS 模拟器构建。
另通过 105 项 Android JVM 与 38 项 Python 回归；最低/最新版 iOS 模拟器示例运行通过。
Flutter 3.50 的 App 最低 iOS 为 15，不能继续宣称该组合支持 iOS 13/14。
滚动 stable CI 已配置但远端未执行；未来版本和真机阳性仍须独立验收。
[完整矩阵和边界](flutter_compatibility.md)。检测规则未变更，第三方指纹仍未实现。

### 开发者设置与受限零值（2026-11-14）

新增独立 developerMode / usbDebugging，使用公开 Settings.Global 按需采样。
修正不能默认把设置 0/缺值视作关闭的设计风险：仅 1 可 detected；0 为 settingReadRestricted，
缺值/异常保留 error；Dart 边界拒绝这两项伪造的 notDetected。iOS capability=false，scan 明确 unsupported。
新两项规则为 local-v1，旧检测规则保持原版本；示例扩为 16 项，第三方指纹未实现。
[测试证据、Android 录屏流程未通过项和独立真机清单](developer_settings.md)。
