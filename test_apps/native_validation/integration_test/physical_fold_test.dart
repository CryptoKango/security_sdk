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
  testWidgets(
    'physical fold held closed and reopened twice',
    (tester) async {
      final report = <String, Object?>{
        'schemaVersion': 1,
        'completed': false,
        'cycles': <Object?>[],
      };
      binding.reportData = report;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SafeArea(child: Text('真实折叠回归\n按助手提示合上并保持，待通知后再展开。\n请不要截图。')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(sdk.dispose);
      addTearDown(() => channel.invokeMethod<void>('stopCaptureProbe'));
      Future<Map<String, Object?>> stage(String name) async {
        final client = HttpClient();
        try {
          final port = int.parse(
            const String.fromEnvironment('LIFECYCLE_TEST_PORT'),
          );
          final request = await client.postUrl(
            Uri.parse('http://127.0.0.1:$port/$name'),
          );
          request.headers.set(
            'X-Test-Token',
            const String.fromEnvironment('LIFECYCLE_TEST_TOKEN'),
          );
          final response = await request.close().timeout(
            const Duration(minutes: 6),
          );
          expect(response.statusCode, 200);
          final value = Map<String, Object?>.from(
            jsonDecode(await utf8.decoder.bind(response).join()) as Map,
          );
          expect(value['confirmed'], true);
          return value;
        } finally {
          client.close(force: true);
        }
      }

      Future<void> foreground() async {
        for (var i = 0; i < 120; i++) {
          final ui = await channel.invokeMapMethod<String, Object?>('uiState');
          if (ui?['focus'] == true && ui?['resumed'] == true) {
            await Future<void>.delayed(const Duration(seconds: 1));
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        fail('Folded fixture did not return');
      }

      Future<Map<String, Object?>> scan() async {
        final result = await sdk.scan(
          ScanRequest(
            contextId: 'fold',
            detectorIds: const ['screenshot', 'screenRecording'],
            timeout: const Duration(seconds: 5),
          ),
        );
        return {
          for (final f in result.findings)
            f.detectorId: {
              'status': f.status.name,
              'reason': f.reason?.name,
              'values': f.values,
            },
        };
      }

      report['record_start'] = await stage('record_start');
      for (var cycle = 1; cycle <= 2; cycle++) {
        await foreground();
        await sdk.stopScreenshotObservation();
        await sdk.startScreenshotObservation();
        final item = <String, Object?>{
          'cycle': cycle,
          'before': await scan(),
          'nativeBefore': await channel.invokeMapMethod<String, Object?>(
            'startCaptureProbe',
          ),
        };
        (report['cycles']! as List).add(item);
        item['closed'] = await stage('fold_closed_$cycle');
        item['whileClosed'] = await scan();
        item['opened'] = await stage('fold_opened_$cycle');
        await foreground();
        item['after'] = await scan();
        item['nativeAfter'] = await channel.invokeMapMethod<String, Object?>(
          'captureProbeState',
        );
        await channel.invokeMethod<void>('stopCaptureProbe');
        await sdk.stopScreenshotObservation();
        await sdk.startScreenshotObservation();
        item['restarted'] = await scan();
      }
      report['record_stop'] = await stage('record_stop');
      await foreground();
      report['stopped'] = await scan();
      await sdk.dispose();
      report['cleanupCompleted'] = true;
      report['completed'] = true;
    },
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
