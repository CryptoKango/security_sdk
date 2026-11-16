import 'package:flutter/material.dart';
import 'package:security_flutter/security_flutter.dart';

class DeviceInfoPanel extends StatelessWidget {
  const DeviceInfoPanel({super.key, required this.result});
  final DeviceInfoResult result;
  @override
  Widget build(BuildContext context) {
    final info = result.info;
    final text = info == null
        ? 'status: ${result.status.name}\ncode: ${result.code?.name}'
        : 'status: ${result.status.name}\n'
              'platform（系统）: ${info.platform.name}\n'
              'manufacturer（厂商）: ${info.manufacturer}\n'
              'brand（品牌）: ${info.brand}\n'
              'model（型号）: ${info.model}\n'
              'systemVersion（系统版本）: ${info.systemVersion}\n'
              'apiLevel: ${info.apiLevel ?? "不适用（iOS）"}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设备基础信息', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(text),
          const Divider(),
        ],
      ),
    );
  }
}
