# 统一设备安全报告 JSON 格式（版本 1）

`DeviceSecurityReport.toJson()` 返回新的 `Map<String, Object?>`，其中只包含可用于 JSON
的对象、数组、字符串、布尔值、有限数值及 `null`。
`jsonEncode(report)` 与 `jsonEncode(report.toJson())` 得到相同的数据结构。
Android/iOS 共用同一套 Dart 序列化实现，序列化过程不会重新采集设备信息。
嵌套模型也各自支持 `toJson()`，但不会额外添加顶层报告结构。

中文说明用于文档和 example 展示；JSON 中的字段名、枚举字符串保持英文。
JSON 本身不支持注释，因此说明文字不会写入导出数据。

## 字段说明

| 字段路径 | 类型 | 中文含义 |
| --- | --- | --- |
| `schemaVersion` | 整数 | 固定为 `1`，表示公开报告格式版本，与原生通道协议版本独立 |
| `device` | 对象 | 设备基础信息的读取结果 |
| `device.status` | 字符串 | `available` 已读取；`unsupported` 不支持；`error` 读取失败 |
| `device.code` | 字符串或 null | SecurityErrorCode 原因码；成功取得信息时为 null |
| `device.info` | 对象或 null | 包含以下六个基础字段；未取得信息时为 null |
| `device.info.platform` | 字符串 | 系统平台：`android` 或 `ios` |
| `device.info.manufacturer` | 字符串 | 设备厂商，如 `samsung`、`Apple` |
| `device.info.brand` | 字符串 | 设备品牌；iOS 为 `Apple` |
| `device.info.model` | 字符串 | Android 型号或 iOS 硬件代码；iOS 模拟器可能返回宿主架构，如 `arm64` |
| `device.info.systemVersion` | 字符串 | 操作系统版本，如 `16`、`18.0` |
| `device.info.apiLevel` | 正整数或 null | Android API 级别；iOS 为 null，表示不适用 |
| `capabilities` | 数组 | 返回的全部检测能力，包括不支持的检测项 |
| `capabilities[].id` | 字符串 | 检测项标识 |
| `capabilities[].supported` | 布尔值 | 是否存在实现；不代表权限、输入条件满足，也不代表本次检查成功 |
| `capabilities[].requiresExplicitOptIn` | 布尔值 | 是否需要宿主显式启用；false 也会输出 |
| `security` | 对象 | 本次检测快照；聚合信息并非操作系统原子快照 |
| `security.contextId` | 字符串 | 宿主提供的请求关联标识，不应包含个人信息 |
| `security.observedAt` | 字符串 | UTC ISO-8601 时间，例如 `2026-11-16T10:20:30.123456Z`，Z 表示 UTC |
| `security.findings` | 数组 | 保留原始顺序的全部检测结果 |
| `security.findings[].detectorId` | 字符串 | 检测项标识，例如 `root`、`hook`、`developerMode` |
| `security.findings[].detectorVersion` | 字符串 | 检测规则版本，例如 `local-v1`；不是 SDK 版本或报告格式版本 |
| `security.findings[].status` | 字符串 | 检测状态，见下表 |
| `security.findings[].reason` | 字符串或 null | FindingReason 具体原因码；null 表示未提供原因 |
| `security.findings[].values` | 对象 | 实际读数，只包含有限数值、布尔值或 null；没有读数时为 `{}` |

## 检测状态与原因

以下状态用于 `security.findings[].status`，与 `device.status` 的读取状态不同。

| 值 | 中文说明 |
| --- | --- |
| `detected` | 本项检测条件命中，具体含义由 reason 和 values 说明 |
| `notDetected` | 本次未命中；仍须结合 reason，例如无活动网络时无法判断 VPN 状态 |
| `unsupported` | 当前平台或条件下无法判断 |
| `error` | 检查未完成，例如缺输入、缺权限、系统调用失败或观察中断 |

| 常见 reason | 中文说明 |
| --- | --- |
| `noKnownSignal` | 本次未发现该项已知特征 |
| `noActiveNetwork` | 没有活动网络，无法据此判断 VPN 是否启用 |
| `developerModeEnabled` | 开发者模式已启用 |
| `usbDebuggingEnabled` | USB 调试已启用 |
| `observationRequired` | 尚未开始截图观察 |
| `observationInterrupted` | 截图观察已中断，需要显式重新开始 |
| `timeReferenceRequired` | 缺少可信时间基准，尚未比较设备时间 |
| `locationSampleRequired` | 未提供位置样本，尚未检查位置来源 |
| `integrityBaselineRequired` | 未提供可信完整性基准，尚未进行比较 |
| `unsupportedPlatform` | 当前平台不支持该检测 |
| `noActivity` | 没有可用的 Activity 窗口 |

## 常见读数说明

| values 字段 | 中文含义 |
| --- | --- |
| `signalDetected` | 本项检测条件是否命中，并非设备整体安全值 |
| `settingValue` | 系统开关读数：1 表示启用；0 需结合状态和原因判断，不能单独认定关闭；null 表示缺失或无效 |
| `settingPresent` | 系统是否返回该设置 |
| `settingValueValid` | 设置读数是否为有效的 0/1 |
| `accessibilityEnabled` | 被检查的无障碍功能是否启用 |
| `activeNetworkAvailable` | 是否存在活动网络 |
| `vpnTransport` | 活动网络是否具有 VPN 传输标记 |
| `screenshotObserved` | 本次观察是否记录过截图事件；观察中断后可保留之前的事件 |
| `observationActive` | 当前截图观察窗口是否仍有效 |
| `javaDebuggerConnected` | Java 调试器是否已连接 |
| `processTraced` | 进程是否被跟踪 |
| `deviationUs` / `allowedSkewUs` | 时间绝对偏差 / 允许偏差，单位为微秒 |

这些是常见字段，不是每项检测都会返回。example 的各检测卡片还提供对应的中文结论和读数解释。
`{}` 表示未返回读数，不表示“全部为 false”；`null` 也不能统一转换为 false 或 0。

## 格式与兼容性约定

- 报告版本覆盖整个嵌套结构。版本 1 中字段名及枚举拼写保持稳定；不兼容变更需升级格式版本。
  使用方应允许新增字段和检测项标识。
- 数组保留原始顺序；JSON 对象的字段顺序不作为签名或规范化编码约定。
- 时间转为 UTC 并保留原始精度：始终包含毫秒，微秒非零时包含额外的微秒位。
- 数值保留 Dart 中的数值。大整数可能超出 JavaScript 安全整数范围，转发时不能静默舍入。
- 可空字段保留 null，不省略或转换为空字符串；空数组和空读数对象分别保留 `[]`、`{}`。
- iOS 的 API 级别不适用，用 null 表示，不用 0。iOS 型号为硬件代码，不是用户命名或营销名称。
- 基础信息读取失败不抹掉扫描结果。缺输入、缺权限、不支持和检查失败的状态与原因保持原样。
- 取消、操作超时和释放不生成成功报告。当前只提供导出接口，不提供 `fromJson()` 输入校验接口。

## 使用方式

```dart
import 'dart:convert';

// report 来自 sdk.collectDeviceReport(...)。
final Map<String, Object?> payload = report.toJson(); // 可用于宿主后续处理的对象
final String compact = jsonEncode(report); // 紧凑 JSON 字符串
final String display = const JsonEncoder.withIndent('  ').convert(payload); // 缩进展示
```

输出只包含定义好的设备描述与检测字段，不添加唯一设备标识、第三方指纹或原始平台异常。
序列化不会打印日志、持久化或上传数据；`toString()` 仍是简短的脱敏摘要。
每次导出都会复制全部嵌套对象和数组，修改导出结果不影响原报告或下一次导出。
正式格式与旧测试夹具的 `completed / capabilityCount / findings` 简化导出不同。
