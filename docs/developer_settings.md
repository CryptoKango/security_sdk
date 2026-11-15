# 开发者选项与 USB 调试

新增两个独立 detector，Android 仅在显式 scan 时读取公开 Settings.Global，
规则版本均为 `local-v1`；原有 Android local-v7 / iOS local-v8 检测规则版本不变。

| ID | Android 来源 | 明确开启时 reason | iOS |
| --- | --- | --- | --- |
| `developerMode` | `DEVELOPMENT_SETTINGS_ENABLED` | `developerModeEnabled` | unsupported / unsupportedPlatform |
| `usbDebugging` | `ADB_ENABLED`（USB） | `usbDebuggingEnabled` | unsupported / unsupportedPlatform |

```dart
final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
try {
  final snapshot = await sdk.scan(ScanRequest(
    contextId: 'explicit-developer-settings-check',
    detectorIds: const [
      SecurityDetectors.developerMode,
      SecurityDetectors.usbDebugging,
    ],
    timeout: const Duration(seconds: 5),
  ));
  // Consume each finding's status/reason; do not turn unknown into disabled.
} finally {
  await sdk.dispose();
}
```

两项都已加入 `SecurityDetectors.environment`；通用 example 的本地扫描、单项选择、
全量扫描及能力查询均覆盖。不会在 SDK 构造时读取设置，不新增权限、后台监听、设备标识或上报。

## 为什么不能把 0 当作关闭

Android 官方参考说明，第三方应用读取这两个值可能始终得到 0，无法区分关闭与平台隐藏。
因此本库采用保守的、仅确认开启证据的契约，并对所有支持的 Android 版本保持一致：

| 公开 API 返回 | SDK 结果 |
| --- | --- |
| 精确字符串 `1` | detected / 对应 enabled reason |
| 精确字符串 `0` | unsupported / settingReadRestricted |
| null、空串、非 0/1、非规范格式 | error / settingValueUnavailable |
| SecurityException | error / missingPermission |
| 其他读取异常 | error / nativeFailure |

`settingReadRestricted` 表示无法证明该值未被隐藏，不是确认设备开启，也不是确认权限被拒绝。
两项的 v1 契约不产生 notDetected；Dart 边界也拒绝把这两项的 noKnownSignal 当作已完成的负向结果。
不能用其中一个设置推断另一个。`capabilities.supported=true` 只表示 Android 实现存在，
不保证当前系统向普通应用开放真实值；iOS 两项 capability 为 false。

依据：[Android 开发者选项设置](https://developer.android.com/reference/android/provider/Settings.Global#DEVELOPMENT_SETTINGS_ENABLED)、
[USB 调试设置](https://developer.android.com/reference/android/provider/Settings.Global#ADB_ENABLED)。

## 误报与覆盖边界

- 开发者选项/USB 调试开启有正常开发、测试和设备管理用途，不证明攻击、Root、Hook 或已有调试器连接。
- 已有 `debugger` 仍单独检查实际调试状态；不会因 App 为 debug 构建或模拟器而推断开发者开关开启。
- 不探测隐藏的无线 ADB 字段、端口、系统属性，不执行 shell。USB 开关不代表无线调试或已连接计算机。
- iOS 当前没有采用可公开支持的 App 内查询来源，明确 unsupported；不从签名渠道、Xcode 连接、模拟器或 Debug 标志推断开关。
- 系统隐藏/伪造 Settings 响应仍可能漏检；不能以模拟器或受控 JVM 测试宣称所有厂商系统均可读取。
- 第三方指纹仍未实现。

## 独立真机验收

1. 普通第三方签名 App，分别在最低支持 Android、主流新版本和厂商系统验证开启、关闭、USB 单独开关。
2. 开启且系统真实返回 1 才允许 detected；关闭或被隐藏返回 0 必须保留 unsupported，记录是否存在隐藏行为。
3. 工作资料/受管设备的限制及设置读取拒绝，不得转成 notDetected；不申请额外特权作为前提。
4. 改变设置后再次显式扫描，旧阳性不能缓存；切换设置不自动开始扫描。
5. iOS 真机、模拟器、Debug/Release 均应保持 unsupported；无线调试不计入本轮覆盖。

测试仅输出闭合 status/reason/version。不得记录原始设置值、异常消息或设备标识。

## 本轮验证（2026-11-14）

- 最低 Flutter 3.38.10：分析、81 项 Dart/Flutter、43 项 Python 回归通过；Android 119 项 JVM 回归通过，含 API 24/28/30/31/33/34/35 框架测试。
- Android API 35 模拟器专用用例通过：设置为 1 得到 detected，0 保留 unsupported，缺值保留 error；USB 设置独立返回。完成后已恢复原始设置。
- iOS 26.5 的 6 项 XCTest、根 example 16 项完整流程通过；iOS 13 arm64 类型/可用性检查通过。
- Flutter 3.50.0 的分析、单元测试及 Android 构建通过。
- **Android 完整 example 的录屏流程未通过**：快捷入口缺失，另一次测试环境准备中断了截图观察。没有放宽 SDK 或把失败计作成功；新增设置检测用独立用例验收。
- 真机未执行，仍按上面的独立清单验收。

[结构化验证摘要](validation_runs/2026-11-14/developer_settings_validation.json)、
[Android 完整流程失败记录](validation_runs/2026-11-14/developer_settings_android_full_demo_failures.json)。

可自动化的设备用例为 `example/integration_test/developer_settings_device_test.dart`。
宿主仅在明确指定的测试模拟器上准备设置，并先保存原值、完成后恢复；SDK 与 Dart 用例均不写设置。
从 `example/` 运行（EXPECTED_DEVELOPER_SETTING 可为 enabled / restricted / missing）：

```sh
flutter build apk --debug --target=integration_test/developer_settings_device_test.dart \
  --dart-define=EXPECTED_DEVELOPER_SETTING=enabled
DEMO_REPORT=/tmp/developer-settings-new.json flutter drive \
  --driver=test_driver/device_driver.dart \
  --target=integration_test/developer_settings_device_test.dart \
  --dart-define=EXPECTED_DEVELOPER_SETTING=enabled \
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk \
  --no-start-paused -d <explicit-emulator-id>
```

构建失败不得继续使用旧安装产物；报告必须有 completed=true 且 driver 退出成功。
仅有 SDK 阳性/未知的观察不代表截图录屏流程也已通过。
