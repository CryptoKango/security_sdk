import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/lifecycle_test');
  testWidgets('physical screenshot OS callback compared with SDK', (
    tester,
  ) async {
    final report = <String, Object?>{'schemaVersion': 3, 'completed': false};
    binding.reportData = report;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '截图回调对照测试\n等待助手通知注册完成。\n同时短按侧键＋音量减后松开。\n出现截图缩略图后，在对话中确认；不会在 90 秒时自动结束。',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 2));
    final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
    addTearDown(sdk.dispose);
    addTearDown(() => channel.invokeMethod<void>('stopCaptureProbe'));
    Future<Map<String, Object?>> sdkState() async {
      final snapshot = await sdk.scan(
        ScanRequest(
          contextId: 'capture-probe',
          detectorIds: const ['screenshot'],
          timeout: const Duration(seconds: 5),
        ),
      );
      final f = snapshot.findings.single;
      return {
        'status': f.status.name,
        'reason': f.reason?.name,
        'values': f.values,
      };
    }

    await sdk.startScreenshotObservation();
    report['nativeBefore'] = await channel.invokeMapMethod<String, Object?>(
      'startCaptureProbe',
    );
    report['sdkBefore'] = await sdkState();
    final client = HttpClient();
    try {
      final port = int.parse(const String.fromEnvironment('CAPTURE_TEST_PORT'));
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/ready'),
      );
      request.headers.set(
        'X-Test-Token',
        const String.fromEnvironment('CAPTURE_TEST_TOKEN'),
      );
      final response = await request.close().timeout(
        const Duration(minutes: 6),
      );
      expect(response.statusCode, 200);
      final input = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      report['captureInput'] = input['captureInput'];
    } finally {
      client.close(force: true);
    }
    // Allow the real callback to be delivered; absence is classified by the host
    // as no callback observed, not proof of a clean device or a platform defect.
    await Future<void>.delayed(const Duration(seconds: 2));
    report['sdk'] = await sdkState();
    report['nativeAfter'] = await channel.invokeMapMethod<String, Object?>(
      'captureProbeState',
    );
    await channel.invokeMethod<void>('stopCaptureProbe');
    await sdk.stopScreenshotObservation();
    report['afterStop'] = await sdkState();
    for (var i = 0; i < 20; i++) {
      final ui = await channel.invokeMapMethod<String, Object?>('uiState');
      if (ui?['focus'] == true && ui?['resumed'] == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await sdk.startScreenshotObservation();
    report['afterRestart'] = await sdkState();
    await sdk.stopScreenshotObservation();
    await sdk.dispose();
    report['cleanupCompleted'] = true;
    report['completed'] = true;
  }, semanticsEnabled: false);
}
