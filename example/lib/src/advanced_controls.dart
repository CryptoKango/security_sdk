// Flutter 3.38 still ships Material here; 3.50 retains this compatibility export.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'demo_controller.dart';

/// Every shipped detector uses the same public scan API.
class AdvancedControls extends StatelessWidget {
  const AdvancedControls({super.key, required this.controller});
  final DemoController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('全部方法与单项检测', style: TextStyle(fontWeight: FontWeight.bold)),
      const Text('完整性、时间和位置使用宿主注入的真实输入；默认未配置时返回明确错误。'),
      DropdownButton<String>(
        value: controller.selectedDetector,
        isExpanded: true,
        items: [
          for (final id in DemoController.detectorIds)
            DropdownMenuItem(value: id, child: Text(id)),
        ],
        onChanged: controller.busy ? null : controller.selectDetector,
      ),
      DropdownButton<int>(
        value: controller.scanTimeout.inSeconds,
        items: const [
          DropdownMenuItem(value: 1, child: Text('扫描超时：1 秒')),
          DropdownMenuItem(value: 5, child: Text('扫描超时：5 秒')),
          DropdownMenuItem(value: 10, child: Text('扫描超时：10 秒')),
        ],
        onChanged: controller.busy ? null : controller.setTimeoutSeconds,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: controller.busy ? null : controller.scanSelected,
            child: const Text('扫描所选项'),
          ),
          OutlinedButton(
            onPressed: controller.busy ? null : controller.scanAll,
            child: Text('扫描全部 ${DemoController.detectorIds.length} 项'),
          ),
          TextButton(
            onPressed: controller.canCancel ? controller.cancelScan : null,
            child: const Text('取消当前扫描'),
          ),
          OutlinedButton(
            onPressed: controller.busy ? null : controller.startObservation,
            child: const Text('开始观察（有效窗口不重置）'),
          ),
          TextButton(
            onPressed: controller.busy || controller.released
                ? null
                : controller.releaseSdk,
            child: const Text('释放 SDK'),
          ),
        ],
      ),
      const Text('取消仅停止等待，不保证中止原生任务。释放后调用会返回 disposed；重新运行应用创建新实例。'),
      if (controller.released) const Text('SDK 已进入释放状态。'),
    ],
  );
}
