import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'reclaim_test.dart' as peer;

@pragma('vm:entry-point')
Future<void> reclaimMain() => peer.reclaimMain();

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixture = MethodChannel('security_sdk/lifecycle_test');
  testWidgets(
    'cached engine survives three distinct hosts without stale observation',
    (tester) async {
      final report = <String, Object?>{
        'schemaVersion': 1,
        'completed': false,
        'cycles': <Object?>[],
      };
      binding.reportData = report;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('缓存 engine 生命周期回归'))),
      );
      await tester.pumpAndSettle();
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(sdk.dispose);
      Future<Map<String, Object?>> state() async =>
          (await fixture.invokeMapMethod<String, Object?>('reclaimState'))!;
      Future<Map<String, Object?>> wait(
        bool Function(Map<String, Object?>) ready,
      ) async {
        for (var n = 0; n < 120; n++) {
          final s = await state();
          if (ready(s)) return s;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        fail('Cached host lifecycle did not complete');
      }

      Future<void> mainReady() async {
        for (var n = 0; n < 120; n++) {
          final s = await fixture.invokeMapMethod<String, Object?>('uiState');
          if (s?['focus'] == true && s?['resumed'] == true) {
            await Future<void>.delayed(const Duration(seconds: 1));
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        fail('Main host unavailable');
      }

      Future<Map<String, Object?>> child() async => Map<String, Object?>.from(
        (await fixture.invokeMethod<Map>('reclaimCommand', 'scan'))!,
      );
      void clean(Map result) {
        expect((result['screenshot'] as Map)['values'], {
          'signalDetected': false,
          'screenshotObserved': false,
          'observationActive': true,
        });
        expect((result['screenRecording'] as Map)['status'], 'notDetected');
      }

      await mainReady();
      await sdk.startScreenshotObservation();
      await fixture.invokeMethod<void>('cachedStart');
      await wait((s) => s['ready'] == true && s['focused'] == true);
      report['freshBefore'] = await child();
      expect(
        ((report['freshBefore'] as Map)['screenshot'] as Map)['reason'],
        'observationRequired',
      );
      for (var cycle = 1; cycle <= 3; cycle++) {
        final item = <String, Object?>{'cycle': cycle};
        (report['cycles']! as List).add(item);
        item['attached'] = await state();
        expect((item['attached'] as Map)['cacheMatchesEngine'], true);
        expect((item['attached'] as Map)['engineCreated'], 1);
        await fixture.invokeMethod<void>('reclaimCommand', 'start');
        item['started'] = await child();
        clean(item['started'] as Map);
        item['cacheDropped'] = await fixture.invokeMapMethod<String, Object?>(
          'cachedDrop',
        );
        expect((item['cacheDropped'] as Map)['cachePresent'], false);
        expect((item['cacheDropped'] as Map)['enginePresent'], true);
        item['afterCacheDrop'] = await child();
        clean(item['afterCacheDrop'] as Map);
        await fixture.invokeMethod<void>('cachedRestore');
        final beforeTrim = await state();
        item['trimBefore'] = beforeTrim['trimCallbacks'];
        item['trimState'] = await fixture.invokeMapMethod<String, Object?>(
          'reclaimTrim',
        );
        expect(
          (item['trimState'] as Map)['trimCallbacks'] as int,
          greaterThan(beforeTrim['trimCallbacks']! as int),
        );
        item['afterInjectedTrim'] = await child();
        clean(item['afterInjectedTrim'] as Map);
        await fixture.invokeMethod<void>('reclaimClose');
        item['closed'] = await wait(
          (s) =>
              s['activityPresent'] == false && s['activityDestroyed'] == cycle,
        );
        item['headless'] = await child();
        expect(
          ((item['headless'] as Map)['screenRecording'] as Map)['reason'],
          'noActivity',
        );
        expect(
          ((item['headless'] as Map)['screenshot'] as Map)['reason'],
          'observationInterrupted',
        );
        if (cycle < 3) {
          await fixture.invokeMethod<void>('cachedDrop');
          await expectLater(
            fixture.invokeMethod<void>('cachedReopen'),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'fixture_cache_missing',
              ),
            ),
          );
          item['cacheMissRejected'] = true;
          item['headlessAfterCacheMiss'] = await child();
          expect(
            ((item['headlessAfterCacheMiss'] as Map)['screenshot']
                as Map)['reason'],
            'observationInterrupted',
          );
          expect((await state())['engineCreated'], 1);
          await fixture.invokeMethod<void>('cachedRestore');
          await fixture.invokeMethod<void>('cachedReopen');
          item['reopened'] = await wait(
            (s) => s['focused'] == true && s['activityCreated'] == cycle + 1,
          );
          item['beforeExplicitRestart'] = await child();
          expect(
            ((item['beforeExplicitRestart'] as Map)['screenshot']
                as Map)['reason'],
            'observationInterrupted',
          );
        }
      }
      report['destroyed'] = await fixture.invokeMapMethod<String, Object?>(
        'reclaimDestroy',
      );
      expect((report['destroyed'] as Map)['engineDestroyed'], 1);
      expect((report['destroyed'] as Map)['cachePresent'], false);
      await mainReady();
      await fixture.invokeMethod<void>('cachedStart');
      await wait((s) => s['ready'] == true && s['focused'] == true);
      report['newEngine'] = await child();
      expect(
        ((report['newEngine'] as Map)['screenshot'] as Map)['reason'],
        'observationRequired',
      );
      await fixture.invokeMethod<void>('reclaimClose');
      await wait(
        (s) => s['activityPresent'] == false && s['activityDestroyed'] == 4,
      );
      report['finalState'] = await fixture.invokeMapMethod<String, Object?>(
        'reclaimDestroy',
      );
      expect((report['finalState'] as Map)['engineCreated'], 2);
      expect((report['finalState'] as Map)['engineDestroyed'], 2);
      expect((report['finalState'] as Map)['cachePresent'], false);
      await mainReady();
      await sdk.startScreenshotObservation();
      final result = await sdk.scan(
        ScanRequest(
          contextId: 'main',
          detectorIds: const ['screenshot'],
          timeout: const Duration(seconds: 5),
        ),
      );
      expect(result.findings.single.status, DetectionStatus.notDetected);
      await sdk.dispose();
      report['completed'] = true;
    },
    semanticsEnabled: false,
  );
}
