import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixture = MethodChannel('security_sdk/lifecycle_test');
  testWidgets(
    'selected app versus whole display projection scope',
    (tester) async {
      final report = <String, Object?>{
        'schemaVersion': 1,
        'completed': false,
        'phases': <Object?>[],
      };
      binding.reportData = report;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SafeArea(child: Text('单应用 / 整屏投影范围回归\n画面仅进入测试端后丢弃，不保存、不录音。')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(sdk.dispose);
      Future<void> foreground() async {
        for (var i = 0; i < 100; i++) {
          final s = await fixture.invokeMapMethod<String, Object?>('uiState');
          if (s?['focus'] == true && s?['resumed'] == true) {
            await Future<void>.delayed(const Duration(seconds: 1));
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        fail('Foreground not restored');
      }

      Future<Map<String, Object?>> scan() async {
        // Include asynchronous runtime work to exercise the reply-time recording query.
        final result = await sdk.scan(
          ScanRequest(
            contextId: 'projection-scope',
            detectorIds: const [
              'appIntegrity',
              'screenRecording',
              'screenshot',
            ],
            timeout: const Duration(seconds: 5),
          ),
        );
        return {
          for (final f in result.findings.where(
            (f) => f.detectorId != 'appIntegrity',
          ))
            f.detectorId: {
              'status': f.status.name,
              'reason': f.reason?.name,
              'values': f.values,
            },
        };
      }

      await foreground();
      await sdk.startScreenshotObservation();
      report['baseline'] = await scan();
      expect(
        ((report['baseline']! as Map)['screenRecording'] as Map)['status'],
        'notDetected',
      );
      for (final name in ['other_app', 'own_app', 'full_display', 'stopped']) {
        final client = HttpClient();
        Map<String, Object?> host;
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
          host = Map<String, Object?>.from(
            jsonDecode(await utf8.decoder.bind(response).join()) as Map,
          );
        } finally {
          client.close(force: true);
        }
        expect(host['confirmed'], true);
        await foreground();
        final before = await scan();
        expect(
          (before['screenshot']! as Map)['reason'],
          'observationInterrupted',
        );
        await sdk.startScreenshotObservation();
        final after = await scan();
        (report['phases']! as List).add({
          'name': name,
          'host': host,
          'beforeRestart': before,
          'afterRestart': after,
        });
        final positive = name == 'own_app' || name == 'full_display';
        expect(
          (after['screenRecording']! as Map)['status'],
          positive ? 'detected' : 'notDetected',
        );
        expect((after['screenRecording']! as Map)['values'], {
          'signalDetected': positive,
        });
        expect((after['screenshot']! as Map)['values'], {
          'signalDetected': false,
          'screenshotObserved': false,
          'observationActive': true,
        });
      }
      await sdk.dispose();
      report['cleanupCompleted'] = true;
      report['completed'] = true;
    },
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
