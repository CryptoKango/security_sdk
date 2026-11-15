import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_sdk_demo/main.dart';
import 'package:security_sdk_demo/src/demo_controller.dart';

class LifecycleLog extends WidgetsBindingObserver {
  final states = <String>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      states.add(state.name);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Let the native engine's initial semantics request settle before flutter_test
  // records its handle baseline. Do not suppress leak checks or OS callbacks.
  setUpAll(() async {
    runApp(const SecurityDemoApp());
    await Future<void>.delayed(const Duration(seconds: 2));
  });
  testWidgets('example real device controls and lifecycle', (tester) async {
    final evidence = <String, Object?>{};
    binding.reportData = evidence;
    final lifecycle = LifecycleLog();
    binding.addObserver(lifecycle);
    addTearDown(() => binding.removeObserver(lifecycle));
    await tester.pumpWidget(const SecurityDemoApp());
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 1));
    final controller =
        (tester.state(find.byType(DemoPage)) as dynamic).controller
            as DemoController;
    Future<void> tap(String text) async {
      final button = find.text(text);
      await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expect(controller.busy, isFalse);
    }

    List<Map<String, String?>> result() => controller.findings
        .map(
          (f) => {
            'id': f.detectorId,
            'status': f.status.name,
            'reason': f.reason?.name,
            'version': f.detectorVersion,
          },
        )
        .toList();
    SecurityFinding finding(String id) =>
        controller.findings.singleWhere((f) => f.detectorId == id);
    Future<void> phase(String name) async {
      final client = HttpClient();
      try {
        final port = int.parse(const String.fromEnvironment('DEMO_TEST_PORT'));
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/$name'),
        );
        request.headers.set(
          'X-Test-Token',
          const String.fromEnvironment('DEMO_TEST_TOKEN'),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 40),
        );
        final data = jsonDecode(await utf8.decoder.bind(response).join());
        expect(response.statusCode, 200, reason: '$name host action failed');
        evidence['host_$name'] = data;
      } finally {
        client.close(force: true);
      }
    }

    expect(controller.findings, isEmpty);
    await tap('查询能力');
    expect(controller.capabilities, isNotEmpty);
    evidence['capabilities'] = controller.capabilities
        .map((c) => {'id': c.id, 'supported': c.supported})
        .toList();
    await tap('扫描本地信号');
    evidence['local'] = result();
    expect(finding('emulator').status, DetectionStatus.detected);
    expect(finding('hook').status, DetectionStatus.notDetected);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      expect(finding('root').status, DetectionStatus.unsupported);
    }
    await tap('演示缺少配置的结果');
    evidence['missingInputs'] = result();
    expect(
      controller.findings.map((f) => f.status),
      everyElement(DetectionStatus.error),
    );
    await tap('扫描全部 ${DemoController.detectorIds.length} 项');
    evidence['allDetectors'] = result();
    expect(controller.findings.length, DemoController.detectorIds.length);
    await tap('扫描所选项');
    expect(controller.findings.single.detectorId, SecurityDetectors.root);
    await tap('读取截图 / 录屏');
    expect(finding('screenshot').reason, FindingReason.observationRequired);
    await tap('开始 / 重开观察（清空旧事件）');
    await tap('读取截图 / 录屏');
    evidence['captureInitial'] = result();
    expect(finding('screenshot').status, DetectionStatus.notDetected);
    expect(finding('screenRecording').status, DetectionStatus.notDetected);
    await phase('screenshot');
    await Future<void>.delayed(const Duration(seconds: 1));
    await tap('读取截图 / 录屏');
    evidence['afterScreenshot'] = result();
    expect(
      finding('screenshot').status,
      isIn([DetectionStatus.detected, DetectionStatus.notDetected]),
    );
    await phase('record_start');
    await Future<void>.delayed(const Duration(seconds: 2));
    // System recording consent temporarily removes app focus. Start a new window.
    await tap('开始 / 重开观察（清空旧事件）');
    await tap('读取截图 / 录屏');
    evidence['duringRecording'] = result();
    expect(
      finding('screenRecording').status,
      defaultTargetPlatform == TargetPlatform.android
          ? DetectionStatus.detected
          : DetectionStatus.notDetected,
    );
    await phase('record_stop');
    await tap('读取截图 / 录屏');
    evidence['afterRecording'] = result();
    expect(finding('screenRecording').status, DetectionStatus.notDetected);
    await tap('开始 / 重开观察（清空旧事件）');
    lifecycle.states.clear();
    await phase('background');
    await tester.pumpAndSettle();
    await tap('读取截图 / 录屏');
    evidence['lifecycle'] = List<String>.of(lifecycle.states);
    evidence['afterBackground'] = result();
    expect(lifecycle.states, contains('paused'));
    expect(lifecycle.states.last, 'resumed');
    expect(finding('screenshot').reason, FindingReason.observationInterrupted);
    await tap('开始观察（有效窗口不重置）');
    await tap('读取截图 / 录屏');
    evidence['explicitStartAfterInterruption'] = result();
    expect(finding('screenshot').status, DetectionStatus.notDetected);
    await tap('开始 / 重开观察（清空旧事件）');
    await tap('读取截图 / 录屏');
    evidence['restarted'] = result();
    expect(finding('screenshot').status, DetectionStatus.notDetected);
    await tap('停止观察');
    await tap('读取截图 / 录屏');
    evidence['stopped'] = result();
    expect(finding('screenshot').reason, FindingReason.observationRequired);
    await phase('final_view');
    await tap('释放 SDK');
    expect(controller.released, isTrue);
    await tap('查询能力');
    expect(controller.message, contains('disposed'));
    evidence['disposed'] = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    evidence['completed'] = true;
  }, semanticsEnabled: false);
}
