# 隐藏 Root/Hook 与厂商分身：自动化结果与真机待验收

本轮日期：2026-11-13。Android 原生规则 `local-v7`，iOS 保持 `local-v6`，schemaVersion 仍为 1。
新增 `cloneProfile` 是系统类型观察，不代表恶意或同时运行多个副本。core/Flutter 插件一起升级；
未知 reason 仍拒绝解析。没有新增权限、用户/应用枚举、后台采集、网络或第三方指纹。

## 已实现及误报控制

| 范围 | 新增证据 | 保守边界 |
| --- | --- | --- |
| 隐藏 Root | 系统分区 overlay 的 lowerdir/upperdir/workdir 指向已知框架路径；补充 metamodule 路径 | 普通 overlay、KSU 字样、SELinux context、目录名子串不判 Root；只读自身 mountinfo |
| Hook | `liblspatch.so` 的可执行映射；maps 增加 65,536 条预算 | 非执行映射、相似名字、普通 APK/JIT/匿名页不判 Hook；损坏/超限返回 error |
| 厂商 profile | API 35+，当前非工作 profile 的公开 userType 精确为 CLONE | 不枚举其他用户；PRIVATE/null/未知类型保持 unsupported，权限失败 error；不推断所有 OEM 分身 |

overlay 解析保留 2 MiB/16,384 条挂载限制，新增 256 选项/128 lower 层预算。
先分隔、后解码，支持空格及八进制逗号/冒号转义；不支持或有歧义的转义返回 error，
不宣称覆盖所有内核编码。单个可疑条目后仍有损坏数据时，不返回已完成的阳性/阴性扫描。
普通工作资料保持 `managedProfile`，普通次用户不按数字 UID 判 clone；合法插桩/Root 本身不等于攻击。

API 与信号来源见 [多开接口说明](ios_oem_multi_instance.md) 和 [隐藏环境规则](hidden_environment.md)。
[AOSP LauncherAppsService](https://github.com/aosp-mirror/platform_frameworks_base/blob/master/services/core/java/com/android/server/pm/LauncherAppsService.java)
的访问检查允许调用者查询自身用户；这是选择当前用户查询的依据，不是所有 OEM ROM 的实测保证。

## 已执行自动化

| 检查 | 本轮结果 | 范围 |
| --- | --- | --- |
| `sh tool/check.sh` | 通过 | 格式、静态分析；16 core + 44 Flutter + 25 Python 回归 |
| `:security_flutter:testDebugUnitTest` | 105 项通过，0 failed / skipped | 38 策略 + 37 框架兼容/接线 + 30 capture 生命周期 |
| `:security_flutter:lintDebug` | 0 errors，2 warnings | AGP/Robolectric 依赖新版本提示；未更改依赖或关闭检查 |

新增策略回归覆盖：overlay 来源目录、相似/穿越/普通 scratch 路径、转义分隔符、data-only 层、
重复/空/损坏选项、预算和命中后的损坏行；LSPatch 执行权限、精确名称、普通 JIT/APK 与条目预算。
Profile 回归覆盖 API 24–36 策略门槛、PRIVATE/null/OEM 类型、工作资料、次用户和异常传播。
Robolectric 使用受控系统响应，在 API 24/30/33/34/35 验证生产入口，只在 API 35 查询当前 user handle，
权限拒绝保持 error；现有兼容回归还覆盖 27/28/31。桥接拒绝跨 detector 或错误 status 的 clone reason。
这些测试验证代码行为，不能证明真实 ROM 的可见性、抗隐藏能力或误报率。

复现 Android 命令：在 `test_apps/native_validation/android` 下，用 JDK 21 执行
`./gradlew :security_flutter:testDebugUnitTest :security_flutter:lintDebug`。
模拟器集成用例已适配 Android v7 / iOS v6 的版本断言；本轮未重跑设备集成或 iOS 原生测试。

## 需要真机验收：全部待执行

不使用模拟器、纯策略夹具或测试项数量替代以下验收。以下都是待验收项，没有已通过的真机记录。

| 编号 | 独立授权实验设备/模式 | 操作与对照 | 验收重点 |
| --- | --- | --- | --- |
| R1 | Magisk + Zygisk，各固定版本 | 无模块/有模块、隐藏关闭/开启，冷启目标 App | 无前置阳性时，可见框架路径应给 rootMountArtifact；完全过滤时如未检出，记录漏检，不写成设备安全 |
| R2 | KernelSU + meta-overlayfs / 其他挂载实现 | 固定模块与 mount 模式，隐藏切换前后 | 检查模块来源是否进入当前进程 mountinfo；标签 KSU 单独出现不能判 Root |
| R3 | 官方未 Root ROM、工程/GSI overlay、普通开发环境 | Release/Debug，重启和前后台后重复扫描 | 普通 scratch overlay 无 rootMountArtifact；test-keys 保留独立语义，不能误归因于新增规则 |
| H1 | Frida / LSPosed / LSPatch 授权测试宿主 | 注入关闭/开启；模块普通映射/直接 APK 映射 | 记录每种路径是否可见、具体 reason；APK 直接装载只见 APK 名时允许报告检测缺口 |
| H2 | 重命名/匿名化 Hook、隐藏 ClassLoader | 与未隐藏的同版本正例对照 | 记录残留来源能否检出；完全擦除来源、inline hook、伪造 maps 仍可能漏检 |
| H3 | 普通 Flutter/ART JIT、合法性能/测试 SDK | 同一构建分别启用/关闭工具 | 普通 JIT 不产生 hookModule；合法插桩命中不能认定恶意 |
| C1 | 小米/Redmi、OPPO/OnePlus、vivo、Samsung、Honor 等实际可用分身 | API 35+ 主空间与厂商双开使用同一测试 APK，分别启动 | OS 确实返回 CLONE 时为 cloneProfile；OEM 不暴露类型则记录未知/未见痕迹，不能用品牌补阳性 |
| C2 | 同品牌旧版本 API 24–34 | 同 APK、主空间/分身对照 | 无新 API 崩溃；旧版本按现有能力未知或局部检测，不宣称旧机全覆盖 |
| C3 | 工作资料、Android 私密空间、OEM 安全文件夹/次用户 | 每种合法隔离空间单独安装和启动 | 工作资料为 managedProfile；PRIVATE/未知 profile 不得成为 cloneProfile；普通次用户无 UID 猜测 |
| C4 | API 35+ OEM 返回 null / 拒绝访问的系统 | 使用可复现 ROM 行为；无法构造就记 blocked | null 为 unsupported，拒绝为 error；不可写成正常。JVM 故障注入已覆盖但不代替实机 |
| I1 | 既有 iOS 越狱/容器测试矩阵 | 授权真机与正常 App、多 Scene 对照 | 本轮 iOS 规则未变；沿用既有矩阵，不能因 Android 本轮通过而标成完成 |

各 detector 返回首个适用信号：Root 的 UID/su、Hook 的可见类、多开的容器证据可能先于本轮
新增规则命中。验收具体新增 reason 时应排除这些前置命中；不能把其他已知阳性误记为新增规则失败。

每个可执行组合至少记录一次冷启和一次前后台恢复后的显式扫描，Debug/Release 分开；重复运行用于
发现稳定性问题，不用少量样本宣称统计误报率。SDK 不自动开启实验、切换空间、注入或重启设备。
实验员维护受控工具版本与环境真值；SDK 仅返回闭合 reason，不上传路径/maps/用户编号/序列号。

验收记录字段：用例编号、人工设备代号、机型/OS/ROM 版本、受控工具版本、测试构建编号、规则版本、
预设模式、status/reason、重复次数、预期对照、passed/failed/blocked、问题说明。
无法建立正例真值或权限/设备不足时记 blocked；不把 `notDetected` 当作“环境绝对安全”。

## 剩余实施顺序

1. 先跑 R3/H3/C3 负例，校准正常 ROM、合法隔离空间与插桩的误报解释。
2. 再跑 R1/R2/H1/C1 正例与隐藏开关对照，记录明确 ROM/工具版本下的覆盖率和缺口。
3. 最后跑 H2/C2/C4 和既有 iOS 矩阵。只有新的稳定公开证据且有负例对照时才扩展规则。
4. 完整隐藏 Root、任意 inline Hook、非标准 OEM 分身仍是未解决范围；不引入第三方指纹或自动封禁填补。

后续 2026-11-14 iOS local-v7 变更及单独验收矩阵见 [ios_hidden_review.md](ios_hidden_review.md)；本页前述结果保留为 2026-11-13 批次记录。
