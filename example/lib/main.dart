// Flutter 3.38 still ships Material here; 3.50 retains this compatibility export.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:security_flutter/security_flutter.dart';

import 'host_input_example.dart';
import 'src/advanced_controls.dart';
import 'src/demo_controller.dart';
import 'src/device_info_panel.dart';
import 'src/finding_presentation.dart';

void main() => runApp(const SecurityDemoApp());

class SecurityDemoApp extends StatelessWidget {
  const SecurityDemoApp({super.key, this.hostInputs = const DemoHostInputs()});
  final DemoHostInputs hostInputs;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Security SDK 示例',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF315B89)),
    home: DemoPage(hostInputs: hostInputs),
  );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key, this.hostInputs = const DemoHostInputs()});
  final DemoHostInputs hostInputs;
  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  late final controller = DemoController(hostInputs: widget.hostInputs);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设备环境检查')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverToBoxAdapter(
                child: _Controls(controller: controller),
              ),
            ),
            if (controller.device case final device?)
              SliverToBoxAdapter(child: DeviceInfoPanel(result: device)),
            SliverList.builder(
              itemCount: controller.capabilities.length,
              itemBuilder: (context, index) {
                final item = controller.capabilities[index];
                return ListTile(
                  key: ValueKey(item.id),
                  title: Text('${detectorName(item.id)} · ${item.id}'),
                  subtitle: Text(
                    '${item.supported ? "存在实现" : "无平台实现"}'
                    '${item.requiresExplicitOptIn ? " · 需要显式启用" : ""}',
                  ),
                );
              },
            ),
            SliverList.builder(
              itemCount: controller.findings.length,
              itemBuilder: (context, index) => _FindingTile(
                key: ValueKey(controller.findings[index].detectorId),
                finding: controller.findings[index],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});
  final DemoController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('仅在点击后检查；不联网、不采集指纹、不自动拦截。\n逐项结论仅覆盖本次采样的系统接口与已知特征；由接入方决定业务处理。'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: controller.busy ? null : controller.collectDeviceReport,
            child: const Text('统一获取设备信息与检测'),
          ),
          OutlinedButton(
            onPressed: controller.busy ? null : controller.queryDeviceInfo,
            child: const Text('读取设备基础信息'),
          ),
          FilledButton(
            onPressed: controller.busy ? null : controller.scanLocal,
            child: const Text('扫描本地信号'),
          ),
          OutlinedButton(
            onPressed: controller.busy ? null : controller.queryCapabilities,
            child: const Text('查询能力'),
          ),
          OutlinedButton(
            onPressed: controller.busy ? null : controller.showMissingInputs,
            child: const Text('演示缺少配置的结果'),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('显式启用 iOS Release Debugger 检测'),
        subtitle: const Text('默认关闭；依赖进程信息 ABI，可能返回不支持或错误。'),
        value: controller.allowReleaseDebugger,
        onChanged: controller.busy ? null : controller.setReleaseDebugger,
      ),
      const Divider(),
      const Text('截图 / 录屏', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text(
        '截图是观察开始后的事件，不能预防截图。离开前台或切换窗口可能中断观察；'
        '恢复后请手动重新开始。录屏是系统提供的当前捕获信号，不保证区分镜像来源。',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: controller.busy ? null : controller.restartObservation,
            child: const Text('开始 / 重开观察（清空旧事件）'),
          ),
          OutlinedButton(
            onPressed: controller.busy ? null : controller.readCapture,
            child: const Text('读取截图 / 录屏'),
          ),
          TextButton(
            onPressed: controller.busy ? null : controller.stopObservation,
            child: const Text('停止观察'),
          ),
        ],
      ),
      const Divider(),
      if (controller.busy) const LinearProgressIndicator(),
      const SizedBox(height: 12),
      Semantics(liveRegion: true, child: Text(controller.message)),
      const Divider(),
      AdvancedControls(controller: controller),
    ],
  );
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({super.key, required this.finding});
  final SecurityFinding finding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detectorName(finding.detectorId),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(findingConclusion(finding)),
        const SizedBox(height: 8),
        SelectableText(findingOutput(finding)),
        const Divider(),
      ],
    ),
  );
}
