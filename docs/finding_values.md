# 检测结果与实际读数

示例页每一项展示具体中文结论和 SDK 字段：`detectorId`、`status`、`reason`、
`detectorVersion`、`values`。不再在每一项重复“未发现已知信号（不等于安全）”。
结论只描述本次检查覆盖的事实；由接入方决定业务处理。

- VPN `noActiveNetwork`：当前无活动网络，无法判断 VPN 状态。保留原有 SDK 状态兼容性，不把该原因解释为 VPN 已关闭。
- 截图 `noKnownSignal`：本次观察期间未收到截图事件；不表示过去没有截图。
- 录屏 `noKnownSignal`：系统未报告当前窗口被录屏或镜像。
- 时间 `timeReferenceRequired`：缺少可信时间基准，尚未进行比较。
- 位置 `locationSampleRequired`：未提供位置样本，尚未检查。
- 开发者设置 `settingReadRestricted`：读取值为 0，系统可能隐藏真实状态，无法确认关闭。

## values 契约

`SecurityFinding.values` 是防御性复制的不可变 Map，值仅允许有限数字、布尔值和 null。
旧 `const SecurityFinding(...)` 保持源码兼容、返回空 Map；有读数时使用 `SecurityFinding.withValues(...)`。
原生 schemaVersion 1 添加可选 `values`；旧原生实现省略此字段时 Dart 返回 `{}`。
Dart 通道按检测项校验字段白名单、类型和关键状态一致性；拒绝未知字段及矛盾的检测布尔值/设置值。
上限 16 个字段，不承载路径、地址、用户标识、原始设置字符串或原始异常。

空 Map 表示本次未返回读数，不表示 0、false 或检查通过。读数属于当次采样，不是持续状态订阅。
部分检测可提前返回，未执行的后续探针不会补值；错误或不支持结果也不会伪造阴性读数。

| 来源 | 当前可用字段 | 含义 |
| --- | --- | --- |
| 原生条件判断 | `signalDetected` | 实际执行的检测条件是否命中；为计算结果，不是系统原始开关，也不是设备整体安全判断；部分直接构造的结果不提供此字段 |
| Android 开发者选项 / USB 调试 | `settingValue`, `settingPresent`, `settingValueValid` | 规范读数 0/1；缺失或非规范字符串变为 null；后两个值区分缺失与无效；不会暴露非法原始字符串 |
| Android 无障碍 | `accessibilityEnabled` | AccessibilityManager 的启用读数 |
| iOS 无障碍 | `voiceOverEnabled`, `switchControlEnabled` | 本次 VoiceOver / Switch Control 读数，仅覆盖这两项 |
| Android VPN | `activeNetworkAvailable`, `vpnTransport` | 活动网络存在与 VPN 传输标记；没有活动网络时只返回前者 false |
| Android 代理 | `hostProxyConfigured`, `pacProxyConfigured` | 主机/端口及 PAC 配置存在条件，不返回地址 |
| iOS 代理 | `httpProxyEnabled`, `pacProxyConfigured` | HTTP / PAC 开关读数；接口未提供相应字段时为 null |
| Android Debugger | `javaDebuggerConnected`, `waitingForDebugger`, `processTraced` | 已执行探针的布尔结果；提前命中时后续探针未执行，不返回 PID |
| 时间 | `deviationUs`, `allowedSkewUs`, `referenceAgeUs`, `referenceValidForUs` | 绝对时间偏差、阈值、单调时钟基准年龄及有效期，单位微秒；基准过期时只返回年龄/有效期 |
| 合法业务位置样本 | `businessUseAuthorized`, `permissionGranted`, `isMocked`, `sampleAgeUs`, `sampleMaxAgeUs` | 授权/权限、模拟标记、样本年龄/阈值（微秒）；无合法用途或无权限时不暴露样本元数据；不返回坐标 |

示例（确实读取到 0）：

```dart
finding.status == DetectionStatus.unsupported;
finding.reason == FindingReason.settingReadRestricted;
finding.values['settingValue'] == 0;
finding.values['settingPresent'] == true;
finding.values['settingValueValid'] == true;
```

读数用于解释检测输出，不增加新的系统权限、采集路径或第三方指纹。

## 验证与真机验收

自动化覆盖值的不可变性、兼容旧响应、非法字段拒绝、0/1/null 精确保留、
缺值不补零、时间阈值边界、定位授权前置条件、中文结论及 Android/iOS 原生值编码。
`example/integration_test/developer_settings_device_test.dart` 可在指定模拟器验证原生 → Dart 的读数传递。

真机单独验收：不同厂商开发者设置脱敏行为、真实无障碍开关、VPN/代理开关、
录屏/截图及窗口切换、合法定位样本的模拟标记。隐藏 Root/Hook 与分身的实际检测覆盖继续按
已有审查文档验收；新增展示和读数不扩大检测有效性承诺。第三方指纹仍不实现。

本次已执行的检查及模拟器原始结果见 [2026-11-15 验证记录](validation_runs/2026-11-15/finding_values.md)。
