# 低版本兼容性与误报复核（local-v4）

本轮保持 Android minSdk 24、iOS deployment target 13；没有下调 Flutter/Dart 工具链约束，
也没有新增设备指纹、定位采集、网络请求或业务拦截。原生扫描规则版本为 `local-v4`；纯 Dart
时间/位置评估仍为 `local-v1`。第三方指纹继续暂不实现。

## 1. API 边界复核

| 能力 | 旧版本路径 | 新版本路径 / 失败处理 |
| --- | --- | --- |
| Android 签名基准 | API 24–27 GET_SIGNATURES | API 28+ SigningInfo；缺证书返回 signingInfoUnavailable；不自动信任历史签名 |
| Android 自动化 | API 24–28 不调用 isRunningInUserTestHarness | API 29+ 才调用；Monkey/手势服务只表示具体能力，不证明恶意自动化 |
| Android profile | API 24–29 返回 profileTypeUnavailable | API 30+ 工作资料；API 33+ profile；不能区分类型仍 unsupported |
| Android 位置来源 | API 24–30 isFromMockProvider | API 31+ isMock；非法样本不读取/返回来源结论 |
| Android 截图 / 录屏 | API <34 / <35 返回 unsupportedOsVersion | 版本可用还要满足宿主权限、前台视图等前提；缺权限不是未检测到 |
| iOS 位置来源 | iOS 13–14 返回未知来源 null | iOS 15+ sourceInformation；没有来源仍为 null |
| iOS 捕获状态 | iOS 13–16 使用所属 window.screen.isCaptured | iOS 17+ Scene 宿主用 sceneCaptureState；旧式 UIKit 仍走所属屏幕；未知 Scene 状态不回落 false |
| iOS 文件 / 哈希 / 调试 | 现有文件 API、CryptoKit、Darwin 查询均按 iOS 13 最低目标编译检查 | Release 调试探针仍需显式 opt-in；编译不证明旧系统 kinfo_proc ABI 或设备实际行为 |

版本依据：[Android Location](https://developer.android.com/reference/android/location/Location)、
[SigningInfo](https://developer.android.com/reference/android/content/pm/SigningInfo)、
[UserManager](https://developer.android.com/reference/android/os/UserManager)、
[Apple sceneCaptureState](https://developer.apple.com/documentation/uikit/uitraitcollection/scenecapturestate)。

签名基准必须来自该渠道、版本和系统范围实际交付的 APK；签名轮换可能让不同系统收到/识别不同
签名版本，不能把新系统的单一基准无条件套给旧系统，也不能因兼容性而放宽为任意历史签名命中。
本轮保留现有精确签名集合策略，补测 API 24/27 的匹配、不匹配、缺签名路径。

## 2. 已修复的误报与不可靠降级

### 定位元数据

Android 原先只验证 elapsed 时间，可把未设置精度的默认 Location 或非有限精度样本传成
`isMocked=false`。现在要求 hasAccuracy、有限且非负的精度、正数样本时刻且不晚于当前单调时刻，
否则抛 IllegalArgumentException。仅在检查通过后读取版本对应的来源字段。纳秒转毫秒向上取整，
避免跨通道后丢掉不足 1 ms 的年龄，让临界样本显得更年轻。

iOS 原先 `horizontalAccuracy >= 0` 会放过正无穷。现在统一校验有限、非负精度与年龄，
以及乘成毫秒后仍为有限值；失败返回 nil，不读取来源字段。iOS 13–14 / 缺来源继续返回 null，
不伪造 false。无效样本应被宿主丢弃；SDK 不采集坐标、不发起定位、不因无效样本判位置伪造。
精度无效语义依据 [Apple horizontalAccuracy](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy)。

### iOS 隧道启发式

原先 `tun*` 等宽泛前缀会把类似 tunnel0 的名称当作隧道，且只检查 IFF_UP。现在要求：

- 精确前缀 utun/tun/ppp/ipsec 后有非空数字后缀。
- 同一接口条目同时具备 IFF_UP、IFF_RUNNING 和 IPv4/IPv6 地址族；不读取地址值。
- 最多检查 1024 个 getifaddrs 条目，名称按 IFNAMSIZ 有界读取；空快照、非法名称和超预算返回 error。
- 不返回接口名称/地址、不探测网络或端口、不把“有隧道”改称“恶意 VPN”。

这缩小了宽前缀、停用接口和纯链路条目的误报范围；系统服务、合法 VPN 仍可产生同样信号，
而未知命名/隐藏接口可能漏检。`notDetected` 只表示本规则没有找到活动 IP 隧道痕迹。

### 集成测试的低版本假设

普通 Flutter 集成用例原先固定要求截图可用、多开结果必为 notDetected；这会误判旧 Android
的正确 unsupported 降级。现在根据截图 capability 验证旧版本扫描与 start 的失败，普通 Android
profile 允许明确的 `unsupported/profileTypeUnavailable`。SDK 的生产版本门禁没有被放宽。
更严格的 API 边界断言由各 SDK 的框架测试负责，不能把集成测试可运行等同全版本已经执行。

## 3. 回归验证和运行方式

```sh
sh tool/check.sh
sh tool/check_swift_policy.sh
sh tool/check_ios_minimum.sh /absolute/path/to/flutter_sdk
cd test_apps/native_validation/android
./gradlew :security_flutter:testDebugUnitTest :security_flutter:lintDebug
# 可选：只复现指定版本；默认执行完整声明矩阵
./gradlew :security_flutter:testDebugUnitTest -PsecurityTestSdks=24,27,28
```

- Android 框架回归使用仅 testImplementation 的 Robolectric 4.16.1：API 24/28/30/31/33/34/35
  覆盖插件能力/截图录屏降级、缺网络权限、正常/模拟来源、缺精度/无效精度/未来和缺失时间；
  API 24/27 另测旧签名读取。不会启动 FlutterEngine，不是厂商 ROM、驱动或真机验证。
- 初次执行需要下载 Robolectric 依赖和对应 instrumented Android framework jars；不进入发布包运行时依赖。
  版本范围依据 [Robolectric compatibility table](https://robolectric.org/compatibility_table/)。
- Swift 原生规则回归新增未知位置来源、布尔保留、非法精度/年龄，以及接口名称、flags、地址族、空/超预算快照。
- iOS 最低目标脚本对**所有**插件 Swift 源码执行 arm64 / iOS 13 availability/type check；使用开发机当前
  SDK 和 Flutter framework。它不安装或模拟 iOS 13，也不能验证旧 OS 的运行时布局或 UI 生命周期。
- 当前模拟器集成、Release 构建及实际执行数量见 [roadmap](roadmap.md)，不以测试声明代替执行结果。

## 4. 尚需实机验收

仍需 Android 24/27/28/30/31/33 的实际运行、各厂商分身/私密空间/工作资料，以及 iOS 13–16
真机和旧式 UIKit 宿主；补测系统服务隧道、VPN/PAC、真实录屏/截图、定位权限撤销及分发签名轮换。
真机缺口不能通过把 error/unsupported 改成正常、放宽签名集合或提高业务风险分来掩盖。
