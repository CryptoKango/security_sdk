# 本地检测范围与接入约束

本库已实现环境信号及四项运行时检测，不接第三方设备指纹。SDK 只返回观察结果，宿主/后端负责风险判断。
`detected` 表示下述具体信号命中；`notDetected` 仅表示这些检查未命中；
`unsupported` 表示没有可用实现/来源；`error` 表示必要前提缺失或采集失败。
`reason` 是封闭枚举，不返回原始平台异常、服务包名、接口地址、代理地址或位置坐标。
`capabilities().supported` 表示实现存在，不保证当前授权、前台状态或输入已满足。

## 1. 平台能力矩阵

| ID | Android | iOS | 边界与前提 |
| --- | --- | --- | --- |
| `emulator` | 已知 model/product/manufacturer/hardware 模拟器特征；不使用通用 unknown/generic 字段 | 编译目标 `targetEnvironment(simulator)` | Android 为启发式，修改特征可能绕过；不输出 Build 原始值 |
| `multiInstance` | 公共 API 工作资料、API 35+ 当前 CLONE profile、已知宿主/客体目录、UID 与框架类交叉证据；不能区分的 profile 返回未知 | APPL 主文件 Mach-O 动态库信号，或自身数据目录内客体 Bundle 与独立宿主执行文件交叉证据 | 只表示具体环境信号，不证明恶意或同时多实例；不按 user ID、品牌、多 Scene、改签渠道判克隆；未知容器仍可能漏检 |
| `automation` | Monkey、用户测试框架、已启用的无障碍手势服务能力 | `unsupported` | 这些是测试/控制能力信号；手势能力不是正在自动点击的证明，普通 Appium/脚本未必可见 |
| `developerMode` | 公开开发者选项设置的正向证据；1 才 detected，0 为 unsupported | unsupported | 0 可能被平台隐藏，不能视作关闭；不代表恶意或调试器附加 |
| `usbDebugging` | 公开 USB 调试设置的正向证据；1 才 detected，0 为 unsupported | unsupported | 不覆盖无线 ADB，不代表已连接电脑；缺值/读取失败保留 error |
| `accessibility` | `AccessibilityManager.isEnabled` | VoiceOver / Switch Control 运行状态 | 不枚举/上传用户的辅助应用身份；不可仅凭此阻断无障碍用户 |
| `vpn` | 默认活动网络的 `TRANSPORT_VPN` | UP + RUNNING、带 IP 地址族的数字编号 utun/tun/ppp/ipsec 接口 | Android 只看本 App 默认活动网络，未覆盖所有分流；iOS 是隧道启发式，系统服务也可能触发，不等同 VPN 确证 |
| `proxy` | `ConnectivityManager.defaultProxy` 的主机端口或 PAC 配置 | 系统 HTTP/PAC 启用标记 | 不执行 PAC、不请求测试站点；不代表某个业务请求实际经过代理，不覆盖应用自建隧道或所有 SOCKS/透明代理 |
| `timeAnomaly` | 纯 Dart 可信参考时间比较 | 同左 | 必须由宿主提供可信时间；允许偏差、有效期由宿主明确设置，无默认业务阈值 |
| `screenshot` | Android 14 / API 34+，显式观察本 Activity 截图事件 | 显式观察系统截图通知 | 事件发生后可知，不是“正在截图”状态；不能查询观察前历史，不能预防截图 |
| `screenRecording` | Android 15 / API 35+，当前 UID 内容是否可见于录屏 | 采用 UIScene 的 iOS 17+ sceneCaptureState；其他宿主用 window.screen.isCaptured | 仅前台对应视图；包含录屏/镜像等捕获，不保证区分来源；不覆盖外部摄像机 |
| `mockLocation` | 评估宿主提供的 `Location.isMock`（API 31+）/ `isFromMockProvider` | 评估 `CLLocation.sourceInformation.isSimulatedBySoftware`（iOS 15+） | 不主动定位；未知来源返回 unsupported。无模拟标记不证明真实位置，外设定位本身不算伪造 |

桌面/Web 无原生环境检查；时间/位置来源评估仍可通过纯 Dart 输入工作。
Root/越狱、Hook、Debugger 与 App Integrity 已实现，范围如下；配置与限制详见
[runtime_security.md](runtime_security.md)。

| ID | Android | iOS |
| --- | --- | --- |
| `root` | 系统 su/管理器路径、UID、test-keys 与本进程 Root 框架挂载痕迹及系统 overlay 来源目录 | 真机越狱路径、rootless 镜像及已知 rootful 注入来源；模拟器 unsupported |
| `hook` | 当前进程已知模块（含 LSPatch）/可见类、已知 memfd agent、Zygisk 可执行映射来源 | 当前进程已知 dyld 模块（含 ElleKit）及注入来源；有界读取与身份复核 |
| `debugger` | Java 调试状态和本进程 TracerPid | P_TRACED；Release 需按请求显式启用，否则 unsupported |
| `appIntegrity` | 宿主基准包名 + 精确当前签名者集合 | 宿主基准 Bundle ID + 指定资源 SHA-256 |

无完整性基准、读取失败或受限时返回 error，不将未执行的检查视为正常。
iOS Release Debugger 的启用方式、能力前提与 ABI 限制见 [专门说明](ios_release_debugger.md)。

## 2. 宿主接入

```dart
final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
final snapshot = await sdk.scan(ScanRequest(
  contextId: 'opaque-operation-id',
  detectorIds: SecurityDetectors.environment,
  timeout: const Duration(seconds: 5),
));
// 逐项读取 status + reason；宿主决定如何展示/上报，不自动封禁。
await sdk.dispose();
```

Android 按使用功能在宿主 Manifest 中显式加入权限；插件 Manifest 不自动合并这些权限：

```xml
<!-- VPN / proxy -->
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<!-- 截图：API 34+，系统会向用户提示检测到了截图 -->
<uses-permission android:name="android.permission.DETECT_SCREEN_CAPTURE" />
<!-- 录屏状态：API 35+ -->
<uses-permission android:name="android.permission.DETECT_SCREEN_RECORDING" />
```

SDK 不调用运行时权限弹窗。缺少网络/录屏权限返回该项 error；开始截图观察失败抛出
`SecurityFailure(platformUnavailable)`，不会转换为未检测到。低版本截图/录屏返回 unsupported。
Android/iOS 截图与录屏检查需要有前台 Flutter Activity/View；后台 engine 不应请求这些能力。

## 3. 截图窗口与生命周期

```dart
await sdk.startScreenshotObservation(); // 在业务页面已显示、宿主已完成告知后调用
// ...用户交互；重复 start 不重置已有窗口...
final capture = await sdk.scan(ScanRequest(
  contextId: 'opaque-capture-window',
  detectorIds: [SecurityDetectors.screenshot, SecurityDetectors.screenRecording],
  timeout: const Duration(seconds: 5),
));
await sdk.stopScreenshotObservation(); // 页面离开时停止；下次 start 建立新窗口
```

- `screenshot` 是从本实例 start 至本次 scan 的累计事件标记，不消费/清零；需 stop/start 重开窗口。
- 未 start 返回 `error/observationRequired`。转后台、Android Activity 暂停/更换、iOS Scene 失活或绑定窗口更换
  会终止有效窗口，返回 `error/observationInterrupted`；宿主回前台后显式 start 重开。
- 未采用 UIScene 的 iOS 宿主使用 UIApplication 前台/失活状态，并绑定原 UIWindow。
- stop、dispose 和 engine detach 释放对应原生观察器；不同 SDK 实例的 owner 随机且仅在内存使用。
- SDK 构造、capabilities 调用和普通环境 scan 都不会开启截图监听。没有通用后台监控或自动上报。
- 截图通知只在用户已截图后到达。Android 不保证检测 ADB/测试框架截图；iOS 通知不包含图片或
  精确 Scene 归属，仅在本插件前台视图观察期间计数。窗口覆盖有中断时不能推断没有截图。
- `screenRecording` 是一次性读取；Android 临时注册回调读取初始状态后立即释放，不持续订阅。
- 宿主串行调用同一实例的 start/stop；多实例可独立使用。超时的 start 会尝试清理；dispose 再次清理
  尚未确认停止的资源。dispose 超过 operationTimeout 返回 timeout，实例保持 disposed；超时并非清理完成的确认。Flutter engine 关闭时原生侧也会尝试释放；注销失败不等于 OS 已清理。

- Android 失焦、iOS 窗口隐藏/Scene 断开也会中断观察；这不是恶意行为阳性。每 engine 最多保留
  64 个 owner，含中断记录，需 stop/dispose 释放。异步混合扫描遇到中断不返回旧 capture 成功结果。
- Android 录屏初始状态属于 UID 范围；iOS 截图通知没有精确 engine/Scene 归属。资源隔离不等于
  事件归属隔离。多 engine、迟到回调、清理失败与真机验收边界见 [capture_lifecycle.md](capture_lifecycle.md)。

local-v6 的多 Scene、旋转、分屏与 PiP 边界见 [scene_window_lifecycle.md](scene_window_lifecycle.md)。
同一有效窗口内的尺寸变化不清空证据；有 Scene 的 iOS 观察只跟随该 Scene。Android PiP 中返回不可
观察状态，不产生风险阳性；iOS 系统 PiP 视频层不在 Flutter 窗口观察的保证范围。

## 4. 时间异常

宿主从自己的可信后端获得时间并将网络延迟/不确定性纳入 `allowedSkew`：

```dart
final reference = TrustedTimeReference(
  serverTimeAtReceipt: authenticatedServerTimeAtReceipt,
  allowedSkew: hostAllowedSkew,
  validFor: hostReferenceLifetime,
);
final result = await sdk.scan(ScanRequest(
  contextId: 'opaque-time-check',
  detectorIds: [SecurityDetectors.timeAnomaly],
  timeReference: reference,
  timeout: const Duration(seconds: 5),
));
```

预期当前时间 = 接收时服务器时间 + 同一参考对象的单调经过时间。比较绝对偏差，支持时间向前/后跳。
缺参考 → `timeReferenceRequired`；参考过期 → `timeReferenceExpired`；偏差超过容忍值 → `timeDeviation`。
恰好在阈值内不算命中。不可把设备当前时间伪装成服务器时间，不可把旧锚点重新构造为“刚收到”。
SDK 不发 HTTP/NTP 请求、不修改系统时间、不读取“自动时间”开关；无可信参考时不猜测设备时间正确。
这是客户端自报信号，不代替后端 challenge 有效期、服务器时钟或抗篡改证明。

## 5. 位置伪造信号（已有合法定位业务才接）

SDK 不增加定位权限、不实例化定位服务、不采集坐标、不启动定位任务。宿主仍负责合法业务目的、
用户告知/授权、当前系统权限和已有定位流程，且每次扫描前重新确认，不长期复用权限断言。

```dart
final sample = LocationRiskSample(
  businessUseAuthorized: hostBusinessLocationAuthorized,
  permissionGranted: hostCurrentLocationPermissionGranted,
  isMocked: existingFixMockFlag, // bool?；未知必须 null，不能 ?? false
  ageAtReceipt: existingFixAgeIncludingBridgeLatency,
  maxAge: hostMaximumLocationAge,
);
final result = await sdk.scan(ScanRequest(
  contextId: 'opaque-location-check',
  detectorIds: [SecurityDetectors.mockLocation],
  locationSample: sample,
  timeout: const Duration(seconds: 5),
));
```

若现有 Flutter 定位插件未提供来源字段，可在宿主已有原生定位回调中调用：
- Android：`LocationRiskMetadata.fromLocation(location)`，使用 elapsedRealtimeNanos 计算原 fix 年龄。
- iOS：`LocationRiskMetadata.fromLocation(location)`，使用系统位置 timestamp 计算年龄，iOS 15+ 读取来源。

两个适配器仅返回 `isMocked`（未知为 null）和 `ageMilliseconds`。宿主自己的位置通道转发这些字段；
Dart 用向上取整的毫秒数并计入通道延迟构建 `ageAtReceipt`。SDK 不接收 Location/CLLocation 对象
或坐标。iOS helper 遇到未来时间戳/无效精度返回 nil；Android 缺精度、非有限/负精度或无效 elapsed 时间抛 IllegalArgumentException；宿主必须
丢弃该样本，不能转换成正常位置。来源由外设提供本身不作为伪造判据。

缺业务授权、缺当前权限、缺样本、样本过期分别返回不同 error 原因；未知模拟标记返回 unsupported。
样本年龄在 Dart 中继续按单调时间增加。iOS 初始 fix 年龄依赖本机墙钟，时间异常时宿主应使样本失效。
宿主提供的布尔值不是可验证凭证；系统被篡改/无线信号欺骗不保证能被系统模拟标记识别。

## 6. 验证与待测矩阵

自动化涵盖时间双向偏差/阈值/过期、位置授权与时效、封闭原因解析、实例隔离、超时清理和已有取消/销毁行为。
Android 原生单测覆盖模拟器标记、合法次用户路径、已知虚拟路径、错误/unsupported 状态保留。
原生模拟器集成覆盖真实环境扫描与截图 start/read/stop 和多实例隔离，不测试图片内容。

发布前仍需实机验证：

| 场景 | 验收 |
| --- | --- |
| Android 24–33、34、35+ | 不支持版本不崩溃；缺权限返回 error；截图只在观察窗口内命中 |
| Android 工作资料/厂商双开/未知容器 | 标明命中原因；记录漏报/误报，不能承诺全检 |
| Monkey、测试框架、手势辅助服务、普通读屏服务 | 正确信号区分，不据此单项封禁 |
| VPN/分流/PAC/离线/iOS 系统隧道 | 不输出地址；只声明已实际观察范围 |
| iOS 13–16、17+；真机截图/录屏/镜像 | 前台对应屏幕/Scene；中断后不可误报 notDetected |
| Activity 重建、Scene 失活、后台、双 engine | 无监听泄漏，旧窗口失效，显式重开恢复 |
| 位置授权撤销、缓存过期、无 sourceInformation、系统模拟/外设来源 | 前提缺失与未知不变成正常；不采集坐标 |

这份矩阵不表示所有实机组合已经测试；实际执行结果记录在 `docs/roadmap.md`。

## 7. 官方 API 依据

- [Android 截图检测与通知边界](https://developer.android.com/about/versions/14/features/screenshot-detection)
- [Android 15 录屏检测](https://developer.android.com/about/versions/15/features#screen-recording-detection)
- [Android AccessibilityManager](https://developer.android.com/reference/android/view/accessibility/AccessibilityManager)
- [Android ActivityManager](https://developer.android.com/reference/android/app/ActivityManager)
- [Android Location.isMock](https://developer.android.com/reference/android/location/Location#isMock())
- [Apple 屏幕捕获状态](https://developer.apple.com/documentation/uikit/uiscreen/iscaptured)
- [Apple 系统代理配置](https://developer.apple.com/documentation/cfnetwork/global-proxy-settings-constants)
- [Apple 位置软件模拟标记](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/issimulatedbysoftware)

误报审查、已修复问题及剩余实施顺序见 [review_findings.md](review_findings.md)。

新增隐藏痕迹、多开交叉证据与误报边界见 [hidden_environment.md](hidden_environment.md)。

原生规则现为 Android `local-v7` / iOS `local-v8`。iOS 局部容器探针、Android profile API 版本及未知状态见
[ios_oem_multi_instance.md](ios_oem_multi_instance.md)；不能用 supported 标志宣传全量多开覆盖。

低版本 API 矩阵、非法位置样本与隧道误报修复见 [compatibility_review.md](compatibility_review.md)。

本轮新增规则的自动化范围与真机待验收清单见 [隐藏环境验收](hidden_environment_acceptance.md)。

2026-11-14 iOS 来源补强、有界采集与真机待验收见 [ios_hidden_review.md](ios_hidden_review.md)。

当前 dyld 安全复制与代际校验、独立真机矩阵见 [ios_dyld_snapshot.md](ios_dyld_snapshot.md)。

开发者设置的保守返回契约、示例及真机矩阵见 [developer_settings.md](developer_settings.md)。
