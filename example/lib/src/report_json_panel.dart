import 'package:flutter/material.dart';

/// Shows the complete serialized report without logging or uploading it.
class ReportJsonPanel extends StatelessWidget {
  const ReportJsonPanel({super.key, required this.json});
  final String json;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('完整报告 JSON（展开后可选中复制）'),
    childrenPadding: const EdgeInsets.all(20),
    children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text('以下为原始 JSON，字段名和枚举值保留英文。中文说明可在下方展开。'),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: SelectableText(
          json,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
      const ExpansionTile(
        title: Text('中文字段与状态说明'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(_jsonGuide),
          ),
        ],
      ),
    ],
  );
}

const _jsonGuide = '''schemaVersion：报告格式版本，当前为 1。

device：设备基础信息的读取结果。
  status：available 已读取；unsupported 不支持；error 读取失败。
  code：读取失败或不支持的原因码；成功时为 null。
  info：基础信息对象；未取得信息时为 null。
    platform：系统平台，android / ios。
    manufacturer：设备厂商。
    brand：设备品牌。
    model：型号；iOS 为硬件代码，模拟器可能为 arm64。
    systemVersion：操作系统版本。
    apiLevel：Android API 级别；iOS 为 null（不适用）。

capabilities：检测能力列表。
  id：检测项标识。
  supported：是否有实现，不代表本次检查成功。
  requiresExplicitOptIn：是否需要宿主显式启用。

security：本次安全检测快照。
  contextId：宿主提供的本次请求关联标识。
  observedAt：快照时间，UTC 格式；末尾 Z 表示 UTC。
  findings：本次返回的全部检测结果。
    detectorId：检测项标识，如 root、hook、developerMode。
    detectorVersion：该检测项的规则版本。
    status：检测状态，含义见下文。
    reason：具体原因码；null 表示未提供原因。
    values：实际读数；{} 表示没有返回读数。

检测状态（findings[].status）：
  detected：本项检测条件命中，具体含义结合 reason 和 values。
  notDetected：本次未命中；仍需结合 reason，例如 noActiveNetwork 表示没有活动网络，无法判断 VPN。
  unsupported：当前平台或条件下无法判断。
  error：检查未完成，例如缺输入、缺权限或观察中断。

常见原因：
  noKnownSignal：本次未发现该项已知特征。
  developerModeEnabled：开发者模式已启用。
  observationRequired：尚未开始截图观察。
  timeReferenceRequired：缺少可信时间基准。
  locationSampleRequired：未提供位置样本。
  integrityBaselineRequired：缺少可信完整性基准。
  noActivity：没有可用的 Activity 窗口。

常见读数（values）：
  signalDetected：本项检测条件是否命中，并非整体安全值。
  settingValue：系统开关读数；1 表示启用，0 的解释需结合状态与原因，null 表示缺失或无效。
  screenshotObserved：本次观察是否记录过截图事件。
  observationActive：本次截图观察窗口是否仍有效。
  deviationUs / allowedSkewUs：时间偏差 / 允许偏差，单位为微秒。

true / false 为布尔值；null 的含义取决于字段，不能统一当作 false 或 0。
每项检测卡片还提供具体中文结论与读数说明。中文说明不写入 JSON 数据。''';
