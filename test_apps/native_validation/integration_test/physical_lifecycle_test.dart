import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

const _channel = MethodChannel('security_sdk/lifecycle_test');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'physical capture lifecycle matrix',
    (tester) async {
      final report = <String, Object?>{
        'schemaVersion': 1,
        'completed': false,
        'checks': <String, Object?>{},
      };
      binding.reportData = report;
      final checks = report['checks']! as Map<String, Object?>;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('截图 / 录屏生命周期回归\n自动旋转与分屏测试中。\n请等待助手通知后再截图、折叠。'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(sdk.dispose);
      addTearDown(() => _channel.invokeMethod<void>('restoreOrientation'));
      addTearDown(() => _channel.invokeMethod<void>('stopSplit'));
      addTearDown(() => _channel.invokeMethod<void>('stopCaptureProbe'));
      Future<Map<String, Object?>> state(String name) async =>
          (await _channel.invokeMapMethod<String, Object?>(name))!;
      Future<Map<String, Object?>> foreground() async {
        var stable = 0;
        for (var i = 0; i < 120; i++) {
          final ui = await state('uiState');
          stable = ui['focus'] == true && ui['resumed'] == true
              ? stable + 1
              : 0;
          if (stable >= 5) return ui;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        fail('Fixture did not regain stable foreground');
      }

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
          final result = Map<String, Object?>.from(
            jsonDecode(await utf8.decoder.bind(response).join()) as Map,
          );
          checks[name] = result;
          expect(
            result['confirmed'],
            true,
            reason: 'Physical step must be confirmed',
          );
          return result;
        } finally {
          client.close(force: true);
        }
      }

      Future<Map<String, Object?>> scan(
        String name, {
        required bool history,
        required bool recording,
        bool focused = true,
      }) async {
        final snapshot = await sdk.scan(
          ScanRequest(
            contextId: name,
            detectorIds: const ['screenshot', 'screenRecording'],
            timeout: const Duration(seconds: 5),
          ),
        );
        final result = <String, Object?>{};
        for (final f in snapshot.findings) {
          result[f.detectorId] = {
            'status': f.status.name,
            'reason': f.reason?.name,
            'values': f.values,
          };
        }
        checks[name] = result;
        final shot = result['screenshot']! as Map;
        final values = shot['values']! as Map;
        expect(values['screenshotObserved'], history);
        if (shot['status'] == 'error') {
          expect(shot['reason'], 'observationInterrupted');
          expect(values['observationActive'], false);
        } else {
          expect(focused, true);
          expect(shot['status'], history ? 'detected' : 'notDetected');
          expect(values['observationActive'], true);
        }
        final record = result['screenRecording']! as Map;
        expect(
          record['status'],
          focused ? (recording ? 'detected' : 'notDetected') : 'error',
        );
        expect(
          record['reason'],
          focused
              ? (recording ? 'screenCaptured' : 'noKnownSignal')
              : 'noActivity',
        );
        return result;
      }

      Future<void> fresh(String name, bool recording) async {
        await foreground();
        await sdk.stopScreenshotObservation();
        final stopped = (await sdk.scan(
          ScanRequest(
            contextId: '$name-stopped',
            timeout: const Duration(seconds: 5),
            detectorIds: const ['screenshot'],
          ),
        )).findings.single;
        expect(stopped.reason, FindingReason.observationRequired);
        expect(stopped.values, isEmpty);
        await sdk.startScreenshotObservation();
        final result = await scan(name, history: false, recording: recording);
        expect((result['screenshot']! as Map)['status'], 'notDetected');
      }

      Future<void> rotations(
        String prefix,
        bool history,
        bool recording,
      ) async {
        for (var cycle = 1; cycle <= 2; cycle++) {
          final before = await state('uiState');
          final target = await _channel.invokeMethod<int>('rotate');
          Map<String, Object?>? after;
          for (var i = 0; i < 60; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            final ui = await state('uiState');
            if (ui['orientation'] == target &&
                ui['focus'] == true &&
                ui['resumed'] == true) {
              after = ui;
              break;
            }
          }
          expect(after, isNotNull, reason: 'Actual orientation must change');
          expect(after!['orientation'], isNot(before['orientation']));
          expect(
            after['configurationChanges'] as int,
            greaterThan(before['configurationChanges']! as int),
          );
          await foreground();
          checks['$prefix-rotation-$cycle-ui'] = {
            'before': before,
            'after': after,
          };
          await scan(
            '$prefix-rotation-$cycle',
            history: history,
            recording: recording,
          );
        }
      }

      Future<void> split(String prefix, bool recording) async {
        await fresh('$prefix-beforeSplit', recording);
        final supported = await state('startSplit');
        expect(
          supported['supported'],
          true,
          reason: 'Install the companion APK first',
        );
        Map<String, Object?> split = {};
        for (var i = 0; i < 60; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          split = await state('splitState');
          if (split['peerReceived'] == true && split['peerFocus'] == true) {
            break;
          }
        }
        // A full-screen companion is not evidence of two-app split-screen.
        checks['$prefix-split-ui'] = split;
        expect(split['peerReceived'], true);
        expect(split['mainFocus'], false);
        await scan(
          '$prefix-unfocused',
          history: false,
          recording: recording,
          focused: false,
        );
        await _channel.invokeMethod<void>('stopSplit');
        await foreground();
        final restored = await state('splitState');
        checks['$prefix-restored-ui'] = restored;
        expect(restored['peerClosed'], true);
        expect(restored['mainMultiWindow'], false);
        await scan('$prefix-returned', history: false, recording: recording);
        await fresh('$prefix-restarted', recording);
      }

      await foreground();
      await fresh('baseline', false);
      await rotations('negative', false, false);
      await split('negative', false);
      await fresh('beforeScreenshot', false);
      checks['probeBefore'] = await state('startCaptureProbe');
      await stage('screenshot');
      await foreground();
      checks['probeAfter'] = await state('captureProbeState');
      expect(
        (checks['probeAfter']! as Map)['callbacks'] as int,
        greaterThan(0),
      );
      await scan('afterScreenshot', history: true, recording: false);
      await rotations('history', true, false);
      await _channel.invokeMethod<void>('stopCaptureProbe');
      await fresh('historyCleared', false);
      await stage('record_start');
      await foreground();
      await fresh('recording', true);
      await rotations('recording', false, true);
      await split('recording', true);
      await fresh('beforeFold', true);
      checks['foldProbeBefore'] = await state('startCaptureProbe');
      final folded = await stage('fold');
      await foreground();
      checks['foldProbeAfter'] = await state('captureProbeState');
      await scan(
        'afterFold',
        history: false,
        recording: folded['projectionActive'] == true,
      );
      await fresh('foldRestarted', folded['projectionActive'] == true);
      await _channel.invokeMethod<void>('stopCaptureProbe');
      await stage('record_stop');
      await foreground();
      await fresh('recordingStopped', false);
      await rotations('stopped', false, false);
      await sdk.stopScreenshotObservation();
      await sdk.dispose();
      await _channel.invokeMethod<void>('restoreOrientation');
      report['cleanupCompleted'] = true;
      report['completed'] = true;
    },
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
