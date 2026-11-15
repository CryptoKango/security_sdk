import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

const fixture = MethodChannel('security_sdk/lifecycle_test');
const scenario = String.fromEnvironment('VALIDATION_SCENARIO');

@pragma('vm:entry-point')
Future<void> validationSceneMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
  const bridge = MethodChannel('security_sdk/scene_validation');
  bridge.setMethodCallHandler((call) async {
    try {
      if (call.method == 'start') {
        await sdk.startScreenshotObservation();
        return {'status': 'started'};
      }
      if (call.method == 'dispose') {
        await sdk.dispose();
        return {'status': 'disposed'};
      }
      if (call.method == 'scan') {
        return findingMap(await capture(sdk));
      }
      throw MissingPluginException();
    } on SecurityFailure catch (error) {
      return {'status': 'error', 'reason': error.code.name};
    }
  });
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Security SDK second Scene')),
    ),
  );
  await bridge.invokeMethod<void>('ready');
}

Future<SecurityFinding> capture(SecuritySdk sdk) async => (await sdk.scan(
  ScanRequest(
    contextId: 'window-validation',
    detectorIds: ['screenshot'],
    timeout: const Duration(seconds: 5),
  ),
)).findings.single;
Map<String, Object?> findingMap(SecurityFinding finding) => {
  'status': finding.status.name,
  'reason': finding.reason?.name,
};
Future<Map<String, dynamic>> state(String method) async =>
    (await fixture.invokeMapMethod<String, dynamic>(method))!;
Future<Map<String, dynamic>?> waitState(
  String method,
  bool Function(Map<String, dynamic>) ready, {
  int stableSamples = 1,
}) async {
  var matching = 0;
  for (var i = 0; i < 100; i++) {
    final value = await state(method);
    matching = ready(value) ? matching + 1 : 0;
    if (matching >= stableSamples) return value;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{
    'schemaVersion': 1,
    'scenario': scenario,
    'status': 'failed',
    'reason': 'notCompleted',
    'evidence': <String, Object?>{},
  };
  binding.reportData = report;
  final evidence = report['evidence']! as Map<String, Object?>;
  void blocked(String reason) {
    report['status'] = 'blocked';
    report['reason'] = reason;
  }

  Future<void> runSceneCycles() async {
    runApp(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(seconds: 1));
    final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
    final cycles = <Map<String, Object?>>[];
    evidence['requestedCycles'] = 3;
    evidence['cycles'] = cycles;
    try {
      for (var cycle = 1; cycle <= 3; cycle++) {
        final evidence = <String, Object?>{'cycle': cycle};
        cycles.add(evidence);
        await sdk.startScreenshotObservation();
        final supported = await fixture.invokeMapMethod<String, dynamic>(
          'createValidationScene',
        );
        if (supported?['supported'] != true) {
          blocked('multipleScenesUnavailable');
          return;
        }
        final connected = await waitState(
          'validationSceneState',
          (s) =>
              s['connected'] == true &&
              s['ready'] == true &&
              s['distinctScenes'] == true,
        );
        expect(connected, isNotNull, reason: 'Requested Scene must connect');
        evidence['connected'] = connected;
        expect(connected!['freshSession'], isTrue);
        expect(connected['configurationNamed'], isTrue);
        expect(connected['cyclesStarted'], cycle);
        expect(connected['registryCount'], 1);
        await fixture.invokeMethod<void>('activateValidationScene');
        final activePeer = await waitState(
          'validationSceneState',
          (s) => s['peerActive'] == true,
        );
        if (activePeer == null) {
          blocked('peerSceneDidNotActivate');
          return;
        }
        evidence['activePeer'] = activePeer;
        final unstarted = await fixture.invokeMapMethod<String, dynamic>(
          'validationSceneCommand',
          'scan',
        );
        expect(unstarted, {'status': 'error', 'reason': 'observationRequired'});
        evidence['peerBeforeStart'] = unstarted;
        expect(
          (await fixture.invokeMapMethod<String, dynamic>(
            'validationSceneCommand',
            'start',
          ))?['status'],
          'started',
        );
        final peer = await fixture.invokeMapMethod<String, dynamic>(
          'validationSceneCommand',
          'scan',
        );
        expect(peer?['status'], 'notDetected');
        evidence['peerCapture'] = peer;
        final first = await capture(sdk);
        evidence['mainDuringPeer'] = findingMap(first);
        expect(
          first.status,
          isIn([DetectionStatus.error, DetectionStatus.notDetected]),
        );
        if (activePeer['mainActive'] == false) {
          expect(first.status, DetectionStatus.error);
        }
        await fixture.invokeMethod<void>('activatePrimaryScene');
        expect(
          await waitState(
            'validationSceneState',
            (s) => s['mainActive'] == true,
            stableSamples: 6,
          ),
          isNotNull,
        );
        await sdk.startScreenshotObservation();
        final before = await state('validationSceneState');
        evidence['beforeClose'] = before;
        evidence['inactiveCloseRejected'] = false;
        if (before['peerActive'] == false) {
          await expectLater(
            fixture.invokeMethod<void>('destroyValidationScene'),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'fixture_scene_inactive',
              ),
            ),
          );
          expect((await state('validationSceneState'))['closeRequests'], 0);
          evidence['inactiveCloseRejected'] = true;
        }
        await fixture.invokeMethod<void>('activateValidationScene');
        final closingTarget = await waitState(
          'validationSceneState',
          (s) => s['peerActive'] == true,
          stableSamples: 2,
        );
        expect(closingTarget, isNotNull);
        evidence['closeTarget'] = closingTarget;
        await fixture.invokeMethod<void>('destroyValidationScene');
        var closed = await waitState(
          'validationSceneState',
          (s) =>
              s['detached'] == true &&
              s['connected'] == false &&
              s['systemConnected'] == false &&
              s['sessionRegistered'] == false &&
              s['sessionDiscarded'] == true &&
              s['resourcesReleased'] == true,
        );
        evidence['closeAttempt'] = await state('validationSceneState');
        expect(
          closed,
          isNotNull,
          reason: 'Actual disconnection state: ${evidence['closeAttempt']}',
        );
        await fixture.invokeMethod<void>('activatePrimaryScene');
        closed = await waitState(
          'validationSceneState',
          (s) => s['detached'] == true && s['mainActive'] == true,
        );
        expect(
          closed,
          isNotNull,
          reason: 'Primary Scene must reactivate after peer teardown',
        );
        final finalCapture = await capture(sdk);
        expect(
          finalCapture.status,
          before['mainInterruptions'] == closed!['mainInterruptions']
              ? DetectionStatus.notDetected
              : DetectionStatus.error,
        );
        expect(closed['disconnectCallbacks'], 1);
        expect(closed['teardownCount'], 1);
        expect(closed['sessionDiscarded'], isTrue);
        await fixture.invokeMethod<void>('destroyValidationScene');
        expect((await state('validationSceneState'))['teardownCount'], 1);
        await expectLater(
          fixture.invokeMethod<void>('validationSceneCommand', 'scan'),
          throwsA(isA<PlatformException>()),
        );
        evidence['closed'] = closed;
        evidence['mainAfterClose'] = findingMap(finalCapture);
        await sdk.startScreenshotObservation();
        final restarted = findingMap(await capture(sdk));
        expect(restarted, {'status': 'notDetected', 'reason': 'noKnownSignal'});
        evidence['mainRestarted'] = restarted;
      }
      await fixture.invokeMethod<void>('releaseValidationScene');
      evidence['finalRegistryCount'] = (await state(
        'validationSceneState',
      ))['registryCount'];
      expect(evidence['finalRegistryCount'], 0);
      report['status'] = 'passed';
      report['reason'] = 'assertionsCompleted';
    } finally {
      try {
        if ((await state('validationSceneState'))['connected'] == true) {
          await fixture.invokeMethod<void>('activateValidationScene');
          await waitState(
            'validationSceneState',
            (s) => s['peerActive'] == true,
          );
          await fixture.invokeMethod<void>('destroyValidationScene');
          await waitState(
            'validationSceneState',
            (s) => s['resourcesReleased'] == true,
          );
        }
      } finally {
        await sdk.dispose();
      }
    }
  }

  // System Scene/AVKit transitions change platform accessibility semantics. Exercise this native scenario
  // in test setup, before WidgetTester snapshots its widget-owned handles. All SDK
  // assertions and native stop/dispose evidence still run; no leak checks disabled.
  setUpAll(() async {
    try {
      if (scenario == 'ios_scenes') {
        await runSceneCycles();
        return;
      }
      if (scenario != 'ios_pip') return;
      runApp(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(seconds: 1));
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      try {
        await fixture.invokeMethod<void>('prepareIosPip');
        final prepared = await waitState(
          'iosPipState',
          (s) =>
              s['possible'] == true ||
              ['unsupported', 'prepareFailed'].contains(s['phase']),
        );
        expect(
          prepared?['phase'],
          isNot('prepareFailed'),
          reason: 'Fixture video/audio preparation must succeed',
        );
        if (prepared == null || prepared['possible'] != true) {
          blocked(prepared?['phase'] as String? ?? 'pipNotPossible');
          return;
        }
        evidence['prepared'] = prepared;
        await sdk.startScreenshotObservation();
        await fixture.invokeMethod<void>('startIosPip');
        final active = await waitState(
          'iosPipState',
          (s) =>
              (s['active'] == true && (s['starts'] as int) > 0) ||
              s['phase'] == 'startRejected',
        );
        if (active == null || active['active'] != true) {
          blocked(active?['phase'] as String? ?? 'pipDidNotStart');
          return;
        }
        evidence['active'] = active;
        final during = await capture(sdk);
        evidence['duringPip'] = findingMap(during);
        expect(
          during.status,
          active['mainActive'] == true &&
                  active['mainInterruptions'] == prepared['mainInterruptions']
              ? DetectionStatus.notDetected
              : DetectionStatus.error,
        );
        await fixture.invokeMethod<void>('stopIosPip');
        final stopped = await waitState(
          'iosPipState',
          (s) => s['active'] == false && (s['stops'] as int) > 0,
        );
        expect(stopped, isNotNull);
        evidence['stopped'] = stopped;
        await fixture.invokeMethod<void>('disposeIosPip');
        expect((await state('iosPipState'))['phase'], 'absent');
        report['status'] = 'passed';
        report['reason'] = 'assertionsCompleted';
      } finally {
        await fixture.invokeMethod<void>('disposeIosPip');
        await sdk.dispose();
      }
    } catch (_) {
      report['status'] = 'failed';
      report['reason'] = 'assertionOrCleanupFailed';
      rethrow;
    }
  });
  testWidgets('real OS window validation: $scenario', (tester) async {
    expect(scenario, isIn(['android_split', 'ios_scenes', 'ios_pip']));
    if (scenario == 'ios_pip' || scenario == 'ios_scenes') {
      expect(report['status'], isIn(['passed', 'blocked']));
      return;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 1));
    final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
    addTearDown(sdk.dispose);
    await sdk.startScreenshotObservation();
    if (scenario == 'android_split') {
      addTearDown(() => fixture.invokeMethod<void>('stopSplit'));
      final supported = await fixture.invokeMapMethod<String, dynamic>(
        'startSplit',
      );
      if (supported?['supported'] != true) {
        blocked(supported?['reason'] as String? ?? 'splitUnavailable');
        return;
      }
      final split = await waitState(
        'splitState',
        (s) =>
            s['mainMultiWindow'] == true &&
            s['peerMultiWindow'] == true &&
            s['peerFocus'] == true,
      );
      if (split == null) {
        evidence['lastSplitState'] = await state('splitState');
        expect(
          (evidence['lastSplitState']! as Map)['peerReceived'],
          isTrue,
          reason:
              'Companion must report; crash/IPC failure is not an unsupported mode',
        );
        blocked('osDidNotEnterDualAppSplit');
        return;
      }
      evidence['split'] = split;
      final lostFocus = await capture(sdk);
      evidence['unfocusedCapture'] = findingMap(lostFocus);
      expect(lostFocus.status, DetectionStatus.error);
      expect(lostFocus.reason, FindingReason.observationInterrupted);
      await expectLater(
        sdk.startScreenshotObservation(),
        throwsA(isA<SecurityFailure>()),
      );
      await fixture.invokeMethod<void>('stopSplit');
      final restored = await waitState(
        'splitState',
        (s) =>
            s['mainMultiWindow'] == false &&
            s['mainFocus'] == true &&
            s['mainResumed'] == true &&
            s['peerClosed'] == true,
      );
      expect(
        restored,
        isNotNull,
        reason: 'Companion must close and main regain fullscreen foreground',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await sdk.startScreenshotObservation();
      expect((await capture(sdk)).status, DetectionStatus.notDetected);
      evidence['restored'] = restored;
    }
    report['status'] = 'passed';
    report['reason'] = 'assertionsCompleted';
  }, semanticsEnabled: false);
}
