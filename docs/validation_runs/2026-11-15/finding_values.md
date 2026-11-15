# 输出字段与实际读数验收 — 2026-11-15

本次使用 Flutter 3.38.10 / Dart 3.10.9。

- `sh tool/check.sh`：格式及静态分析通过；core 20、Flutter plugin 53、example 21，共 94 项 Dart/Flutter 测试通过；Python 工具测试 43 项通过。
- Android `:security_flutter:testDebugUnitTest`：120 项通过，无失败。
- `sh tool/check_swift_policy.sh`：102 项通过（含 Debug/Release process trace 与 macOS dyld 并发装卸）。
- `sh tool/check_ios_minimum.sh <flutter-3.38.10>`：iOS 13 arm64 类型与可用性检查通过。
- Android 正常 example Debug APK、iOS simulator example 构建通过。
- `example/integration_test/developer_settings_device_test.dart`：Android API 35 与 iOS 26.5 模拟器均通过，覆盖原生到 Dart 的实际 values 传递；结构化结果见同目录 JSON。
- Android 验证设置缺失为 null、USB 调试读数为 1，无障碍/代理/VPN 布尔值精确保留；本次没有修改系统设置。0 的受限语义另由 JVM 和 Dart 回归覆盖。
- iOS 验证开发者设置 unsupported + 空读数，VoiceOver / Switch Control 布尔值及代理缺失字段 null 保留。隧道接口命中不解释为特定 VPN 应用或恶意行为。
- 正常 Android example 手动执行全部 16 项并滚动查看结果：中文结论、SDK 字段、实际读数显示完整。最终文案细化由纯逻辑回归覆盖。

本次没有执行真机验收，也没有重跑完整截图录屏/前后台/Scene/PiP 的设备流程；相关原生生命周期回归已随上述测试运行。真机范围见 [输出值契约与验收清单](../../finding_values.md)。第三方指纹未实现。
