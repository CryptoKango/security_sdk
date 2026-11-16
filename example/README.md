# Security SDK 接入示例

可运行的 Android/iOS Flutter 应用。打开页面不会自动扫描；所有检查由按钮触发。
此目录用于学习公开 API；`../test_apps/native_validation` 保留原有 Scene/PiP/多 engine 原生验收夹具。
示例未接入第三方指纹、后端、自动封禁或真实定位流程。

## 运行

在仓库根目录：

```sh
python3 tool/configure_example_android.py --flutter /absolute/path/to/flutter
flutter pub get
cd example
flutter run -d <device-id>
```

要求：Flutter ≥3.38.10 / Dart ≥3.10.9 且 <4.0.0、Android API 24+（compileSdk 36），或满足所选 Flutter 引擎要求的 iOS（3.38/3.44 为 13+，3.50 为 15+）。
Android 需要本机安装 **JDK 17**；项目的 `android/gradle/gradle-daemon-jvm.properties` 会选择它运行 Gradle，避免继承 Android Studio 的 JDK 25。iOS 需要 macOS/Xcode/CocoaPods。
切换 Flutter 后重新运行上述配置命令，它仅更新示例 Gradle/AGP/Kotlin 版本、Kotlin 插件应用方式和 AGP 9 标志，
不修改应用功能、检测规则或全局 Flutter 配置。详细范围见 [Flutter 兼容性](../docs/flutter_compatibility.md)。
iOS 真机请在 `ios/Runner.xcworkspace` 选择自己的开发团队；工程不保存个人签名团队。
Android Release 默认使用脚手架调试签名，仅供示例运行，不作为发布签名基准。

通过 Dart workspace 使用本地 `security_flutter` 和 `security_core`，不是从 pub.dev 下载已发布包。
若单独复制示例到其他仓库，需移除 `resolution: workspace` 并配置可用的包来源；目前 SDK 未发布。

## 页面操作

| 操作 | 行为 |
| --- | --- |
| 统一获取设备信息与检测 | 自动适配 Android/iOS，一次展示基础信息、能力及全部 16 项检测；可展开完整 JSON 并选中复制，缺输入保留具体错误 |
| 读取设备基础信息 | 显示平台、厂商、品牌、型号、系统版本、Android API 级别；iOS API 级别不适用 |
| 扫描本地信号 | 模拟器、多开、自动化、开发者选项、USB 调试、无障碍、VPN、代理、录屏、Root/越狱、Hook、Debugger |
| 查询能力 | 显示平台是否有实现、是否需显式启用；不代表权限和运行条件均已满足 |
| 演示缺少配置的结果 | 主动请求 App Integrity、时间和位置检查，展示缺少宿主输入的错误；不是三个真实业务检查的实现 |
| iOS Release Debugger 开关 | 默认关闭；显式选中后仅影响后续请求，依然可能受系统/ABI 限制 |
| 开始 / 重开观察 | 先停止旧截图窗口再开始新窗口，清空之前事件 |
| 读取截图 / 录屏 | 读取当前截图观察与录屏快照；不是连续监听或观察前的历史查询 |
| 停止观察 | 释放本实例的截图监听；销毁页面也会清理 SDK |

截图观察流程：点击开始 → 手动截图 → 读取结果 → 停止。
前后台切换、窗口变化可能中断观察；恢复后先读取可看到中断状态，需要继续时显式重开。
示例不会自动重启观察，也不会将旧事件带入新窗口。SDK 仍负责原生生命周期失效判断。

显示规则：

- `detected`：发现具体环境信号，不等于恶意。无障碍、VPN、工作资料及合法插桩均有正常用途。
- `notDetected`：未发现已知信号，不证明设备安全或未被 Hook。
- `unsupported`：平台或能力无法判断。
- `error`：检查未完成，例如缺配置、权限、观察窗口中断或 dyld 正在装卸。

操作期间禁用其他按钮；失败时清空之前结果，避免误把旧结果作为本次结论。
每项显示具体中文结论和可选中复制的 `detectorId / status / reason / detectorVersion / values`。
`values` 展示实际返回的布尔值、数字和 `null`：例如设置 `0/1`、无障碍开关、VPN 网络标记、
时间偏差/阈值（微秒）、位置样本模拟标记。读数缺失显示 `{}`，不会从状态反推读数。
无活动网络明确提示无法判断 VPN；缺时间基准/位置样本明确提示尚未检查；截图结论限定本次观察期间。
`signalDetected` 是本项检测条件的计算结果，不是设备整体安全值。
字段范围见 [检测输出值](../docs/finding_values.md)。不打印路径、指针、令牌、设备标识或原始平台错误。

## 宿主必须提供的输入

`lib/host_input_example.dart` 展示了 `scanWithHostInputs()`，接收三个真实宿主输入并构造请求：

- `AppIntegrityPolicy`：可信构建/发布基准。Android 需要批准的当前签名者 SHA-256 集合；iOS 需要
  稳定 Bundle 文件的可信 SHA-256。不能读取当前安装包生成基准后再验证自己。
- `TrustedTimeReference`：宿主认证过的参考时间、有效期和偏差策略，不能用设备当前时间冒充可信来源。
- `LocationRiskSample`：在合法定位业务和当次权限基础上，由宿主从真实系统位置样本提取来源信息。
  示例不申请定位权限、不获取坐标，不使用虚构样本演示“正常”。

先从业务中取得这些输入，再调用该函数；生命周期结束仍由创建 SDK 的宿主负责 `dispose()`。
具体构造方式见 [时间/位置输入](../docs/detection_coverage.md) 和 [完整性配置](../docs/runtime_security.md)。

## 平台配置与边界

Android 宿主 Manifest 显式声明 `ACCESS_NETWORK_STATE`、`DETECT_SCREEN_CAPTURE` 和
`DETECT_SCREEN_RECORDING`；插件不会自动给其他宿主加这些权限。截图 API 需要 Android 14+，
录屏 API 需要 Android 15+；低版本应保留不支持。Debug/Profile Manifest 的 INTERNET 来自
Flutter 开发工具，示例不包含业务网络请求。

iOS 示例保留 Scene 生命周期，通过 CocoaPods 接入插件；pubspec 中明确关闭此示例的 SPM 自动迁移。
SDK 的 SPM 源码保留，专用 Scene 验收宿主仍使用原有接入路径。iOS 无新增权限弹窗。模拟器 Root 检查不支持；iOS Release Debugger 默认不启用。截图是事后事件，
录屏可能包含镜像来源，均不能阻止外部摄像机。未加入原生 Scene/PiP 测试通道或后台能力。

本地检测覆盖与真机限制见 [检测矩阵](../docs/detection_coverage.md) 和
[dyld 并发验收](../docs/ios_dyld_snapshot.md)。构建成功不代表真机安全检测已验收。

## 检查

```sh
# 仓库根目录，包含示例分析和控制器行为回归
sh tool/check.sh
# 仅示例
cd example
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build ios --release --no-codesign --no-pub
```

`test/demo_controller_test.dart` 覆盖无自动采集、显式 Release opt-in、并发操作互斥、失败清除旧结果、
缺输入错误、观察重开顺序和销毁后迟到结果。测试使用可注入平台，不代表原生设备检出率。

## 完整 API 演示索引

页面下方「全部方法与单项检测」可选择全部 16 个 detector 中的任一项，也可显式扫描全部。
默认请求 5 秒超时，可选 1/10 秒；扫描未完成时可取消。短扫描可能在点击取消前已完成，
不要把未发生取消当成 SDK 故障。取消、超时均只结束等待，不承诺终止原生工作。

| 公开能力 | 示例入口 |
| --- | --- |
| `SecuritySdk(operationTimeout:, platform:)` | `DemoController` 默认创建；`lib/session_example.dart` 演示自有平台注入 |
| `capabilities()` | 查询能力按钮，显示 `requiresExplicitOptIn` |
| `scan(ScanRequest)` | 本地扫描、单项选择、全部 16 项；保留各项 status/reason/version |
| Root、Hook、Debugger、App Integrity | 下拉框 `root/hook/debugger/appIntegrity`；Debugger 显式 opt-in 开关 |
| 模拟器、多开、自动化、无障碍、VPN、代理 | 下拉框 `emulator/multiInstance/automation/accessibility/vpn/proxy` |
| 时间、位置、截图、录屏 | 下拉框 `timeAnomaly/mockLocation/screenshot/screenRecording` |
| `startScreenshotObservation()` | 「开始观察（有效窗口不重置）」；有效窗口内重复调用不清空事件；中断后显式调用会创建新窗口 |
| `stopScreenshotObservation()` | 「停止观察」；「开始 / 重开」通过 stop → start 创建新窗口 |
| `dispose()` | 「释放 SDK」等待完成；后续调用显式报告 disposed；页面销毁也清理资源 |
| `CancellationToken` | 「取消当前扫描」；`session_example.dart` 展示 cancel 的接入点、isCancelled、addListener/取消订阅 |
| `ScanRequest.timeout / cancellation / iosDebuggerMode` | 页面超时选项、取消按钮、Release Debugger 开关 |
| `ScanRequest.integrityPolicy / timeReference / locationSample` | `DemoHostInputs` 注入，所有单项和全量扫描透传；缺配置演示仍故意省略输入 |
| `AppIntegrityPolicy`、`isValidBundlePath()` | `host_input_example.dart` 的可信发布清单构造；`session_example.dart` 的路径语法校验 |
| `TrustedTimeReference`、`LocationRiskSample`、各自 `evaluate()` | `host_input_example.dart` 构造；`session_example.dart` 直接评估接收时创建的样本 |
| `assessTimeAnomaly()`、`assessLocationRisk()` | `host_input_example.dart` 的纯 Dart 评估函数，宿主提供真实样本与已计入的年龄 |
| `SecurityScanner`、`SecurityPlatform`、`UnsupportedSecurityPlatform` | `session_example.dart` 使用扫描接口/可注入边界；SDK 在无原生实现的平台自动使用 unsupported 平台 |

宿主可以在自己的入口注入 `SecurityDemoApp(hostInputs: DemoHostInputs(...))`。
`integrityFromReleaseManifest()` 需要受信任的发布基准；`timeAtAuthenticatedReceipt()` 必须在认证参考时间
**实际接收时**调用；`locationFromAuthorizedFlow()` 需要合法业务、实际权限、真实来源标记与样本年龄。
不能为使示例显示正常而填假哈希、用本机时间充当服务器时间或把未知位置来源改成 false。
这些对象会自然过期；新鲜输入应来自新的真实接收事件，不能把旧样本重新包装续期。

`SecurityMonitor.signals/start/stop` 和 `EvidenceProvider.collect` 目前只有扩展契约，
`SecuritySdk` 未实现持续监控，仓库也没有第三方证据提供方；不把这些契约显示为可用功能。
本示例仍未实现第三方指纹。

## 模拟器自动化

先启动专用模拟器，执行根目录 `flutter pub get`。Android 验收配置为 API 35+、英文 SystemUI，
在快捷设置第一页手动加入 **Screen record**，保持屏幕方向和 tile 布局不变；开始前不得已有录屏。
脚本不改快捷设置布局，不启用麦克风。iOS 使用已启动的 Simulator UDID。
输出目录必须不存在，失败证据不可被下一轮覆盖。

```sh
python3 tool/run_demo_device.py --platform android --device emulator-5580 \
  --flutter /absolute/path/to/flutter --adb /absolute/path/to/adb \
  --output /tmp/security-demo-android-new-run
python3 tool/run_demo_device.py --platform ios --device <booted-simulator-uuid> \
  --flutter /absolute/path/to/flutter --output /tmp/security-demo-ios-new-run
```

脚本重新构建集成测试入口，点击示例真实按钮、调用原生 SDK，再由主机操作系统截图导出、录屏和
前后台切换。测试专用 loopback HTTP 仅存在于 `integration_test/`，不属于正常 `lib/main.dart` 入口；
不连接外部服务。Android 使用系统录屏 MediaProjection；iOS 的 simctl 视频导出不等同于系统录屏状态。
因此不能用导出文件证明截图事件或 iOS 录屏阳性检出。脚本失败退出非零，不吞掉框架断言。

`report.json` 和 `observations.json` 只保存闭合状态与测试步骤；`build.log/drive.log` 是本机诊断文件，
可能含本机路径、VM Service 地址，不应上传公开仓库。验收结论与真机清单见
[模拟器验收记录](../docs/example_device_validation.md)。

## Android 报错 `What went wrong: 25.0.2`

这通常表示 Flutter 选择了 Android Studio 自带的 Java 25，而最低版本示例使用 Gradle 8.14。
本项目已通过 `android/gradle/gradle-daemon-jvm.properties` 声明 `toolchainVersion=17`，
无需修改全局 Flutter JDK，也不写入个人 JDK 绝对路径。机器需已安装可被 Gradle 找到的 JDK 17。
如果提示找不到 Java 17，请安装/登记 JDK 17；非标准安装位置可用 Gradle 的
`org.gradle.java.installations.paths` 本地配置提供。仅设置 `JAVA_HOME` 可能仍被 Flutter 的 JBR 选择覆盖。
[Gradle Daemon JVM 选择规则](https://docs.gradle.org/current/userguide/gradle_daemon.html#sec:daemon_jvm_criteria)。

## 开发者设置

单项选择 `developerMode` / `usbDebugging`，或使用本地/全量扫描。Android 明确读到开启才
显示 detected；0 为 unsupported / settingReadRestricted，缺值/失败为 error。iOS 为
unsupported / unsupportedPlatform。界面不把未知当作关闭，也不把开发者选项当作恶意。
[完整能力边界与真机验收](../docs/developer_settings.md)。无线调试不在本轮实现范围。


## Android 真机回归

显式指定已授权的真机，API 35+：

```sh
python3 tool/run_android_physical.py --device <adb-device> --flutter /absolute/path/to/flutter --adb /absolute/path/to/adb --output /tmp/security-physical-run
```

从仓库根目录运行，输出目录必须尚不存在。驱动会安装测试版 example；在终端提示截图、录屏开始/停止时，
由操作人员完成对应系统操作后输入 `done`（无法完成输入 `fail`）。截图必须实际产生系统回调；
录屏需要 MediaProjection 激活，开始前不能有其他录屏。全程只操作测试应用，不导出手机主屏幕或通知内容。
`--skip-screenshot` 只运行剩余步骤，报告明确标记截图 notRun，不能作为完整通过。
测试会短暂切到 HOME 再回到应用；驱动结束后测试包可能被 Flutter 卸载，手动查看可重新 `flutter run`。

[本次 Samsung 真机结果与待验收项](../docs/android_physical_regression.md)。

Android 截图浮层可能中断观察：此时 SDK 保持 `error / observationInterrupted`，
但用 `values.screenshotObserved=true` 保留中断前已收到的事件，`observationActive=false`。
页面会显示“已收到截图事件；随后观察中断，请重新开始观察”。显式重开清空旧事件。
这两个字段不会把中断期变成正常观察；旧版本没有字段时保持缺值。

## 完整报告 JSON

点击“统一获取设备信息与检测”后，设备信息下方可展开“完整报告 JSON”。
文本由 `JsonEncoder.withIndent('  ').convert(report.toJson())` 一次生成，包含全部能力、
检测项、规则版本、时间戳、原因与实际读数，不截断、不自动打印日志或上传。
开始下一次操作时立即清除旧 JSON；失败、取消或页面销毁后的迟到响应不会恢复旧报告。
单独读取基础信息或普通扫描不会拼装成缺字段的统一报告。
JSON 展开区内附“中文字段与状态说明”，解释基础信息、检测状态、常见原因和读数；说明不写入原始 JSON。
格式见 [统一 JSON 协议](../packages/security_core/JSON_FORMAT.md)。
