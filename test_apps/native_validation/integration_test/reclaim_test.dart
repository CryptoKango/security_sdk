import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

Future<Map<String, Object?>> _scan(SecuritySdk sdk) async {
  final result = await sdk.scan(
    ScanRequest(
      contextId: 'reclaim',
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

@pragma('vm:entry-point')
Future<void> reclaimMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
  const bridge = MethodChannel('security_sdk/reclaim_peer');
  bridge.setMethodCallHandler((call) async {
    if (call.method == 'scan') return _scan(sdk);
    if (call.method == 'start') {
      await sdk.startScreenshotObservation();
      return true;
    }
    throw MissingPluginException();
  });
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Activity / engine 回收测试子窗口'))),
    ),
  );
  // Deliberately never dispose this SDK: engine detach must release native resources.
  await bridge.invokeMethod<void>('ready');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixture = MethodChannel('security_sdk/lifecycle_test');
  testWidgets(
    'three real Activity recreations and engine destruction cycles',
    (tester) async {
      final report = <String, Object?>{
        'completed': false,
        'cycles': <Object?>[],
      };
      binding.reportData = report;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('回收回归主窗口'))),
      );
      await tester.pumpAndSettle();
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(sdk.dispose);
      Future<Map<String, Object?>> state() async =>
          (await fixture.invokeMapMethod<String, Object?>('reclaimState'))!;
      Future<Map<String, Object?>> wait(
        bool Function(Map<String, Object?>) ready,
      ) async {
        for (var n = 0; n < 100; n++) {
          final s = await state();
          if (ready(s)) return s;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        fail('Real lifecycle transition did not complete');
      }

      Future<void> mainReady() async {
        for (var n = 0; n < 100; n++) {
          final s = await fixture.invokeMapMethod<String, Object?>('uiState');
          if (s?['focus'] == true && s?['resumed'] == true) {
            await Future<void>.delayed(const Duration(seconds: 1));
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        fail('Main window did not resume');
      }

      Future<Map<String, Object?>> childScan() async =>
          Map<String, Object?>.from(
            (await fixture.invokeMethod<Map>('reclaimCommand', 'scan'))!,
          );
      Map shot(Map value) => value['screenshot'] as Map;
      for (var cycle = 1; cycle <= 3; cycle++) {
        await mainReady();
        await sdk.startScreenshotObservation();
        await fixture.invokeMethod<void>('reclaimStart');
        final item = <String, Object?>{'cycle': cycle};
        (report['cycles']! as List).add(item);
        item['started'] = await wait(
          (s) => s['ready'] == true && s['focused'] == true,
        );
        item['newEngine'] = await childScan();
        expect(
          shot(item['newEngine']! as Map)['reason'],
          'observationRequired',
        );
        await fixture.invokeMethod<void>('reclaimCommand', 'start');
        item['active'] = await childScan();
        expect(shot(item['active']! as Map)['status'], 'notDetected');
        expect(
          ((item['active']! as Map)['screenRecording'] as Map)['status'],
          'notDetected',
        );
        await fixture.invokeMethod<void>('reclaimRecreate');
        item['recreated'] = await wait(
          (s) =>
              s['activityDestroyed'] == cycle * 2 - 1 &&
              s['activityCreated'] == cycle * 2 &&
              s['focused'] == true,
        );
        item['afterRecreate'] = await childScan();
        expect(
          shot(item['afterRecreate']! as Map)['reason'],
          'observationInterrupted',
        );
        await fixture.invokeMethod<void>('reclaimCommand', 'start');
        item['restarted'] = await childScan();
        expect(shot(item['restarted']! as Map)['values'], {
          'signalDetected': false,
          'screenshotObserved': false,
          'observationActive': true,
        });
        await fixture.invokeMethod<void>('reclaimClose');
        item['closed'] = await wait(
          (s) =>
              s['activityDestroyed'] == cycle * 2 &&
              s['activityPresent'] == false,
        );
        item['headless'] = await childScan();
        expect(
          ((item['headless']! as Map)['screenRecording'] as Map)['reason'],
          'noActivity',
        );
        expect(
          shot(item['headless']! as Map)['reason'],
          'observationInterrupted',
        );
        item['destroyed'] = await fixture.invokeMapMethod<String, Object?>(
          'reclaimDestroy',
        );
        expect((item['destroyed']! as Map)['enginePresent'], false);
        expect((item['destroyed']! as Map)['engineDestroyed'], cycle);
        await mainReady();
        item['mainAfter'] = await _scan(sdk);
        expect(
          shot(item['mainAfter']! as Map)['reason'],
          'observationInterrupted',
        );
        await sdk.startScreenshotObservation();
        item['mainRestarted'] = await _scan(sdk);
        expect(shot(item['mainRestarted']! as Map)['status'], 'notDetected');
      }
      await sdk.dispose();
      report['completed'] = true;
    },
    semanticsEnabled: false,
  );
}
