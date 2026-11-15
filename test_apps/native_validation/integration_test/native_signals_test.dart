import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

@pragma('vm:entry-point')
Future<void> lifecyclePeerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
  String start = 'unexpectedSuccess';
  try {
    await sdk.startScreenshotObservation();
  } on SecurityFailure catch (failure) {
    start = failure.code.name;
  }
  final snapshot = await sdk.scan(
    ScanRequest(
      contextId: 'headless',
      timeout: const Duration(seconds: 5),
      detectorIds: ['screenshot', 'screenRecording'],
    ),
  );
  await sdk.dispose();
  await const MethodChannel('security_sdk/lifecycle_peer').invokeMethod<void>(
    'ready',
    {
      'start': start,
      'statuses': snapshot.findings.map((f) => f.status.name).toList(),
    },
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Allow native view activation; the capture case also produces a first frame.
    // No widget presentation assertions are made by these plugin API tests.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  testWidgets(
    'native environment scan and screenshot session lifecycle',
    (tester) async {
      // Android keeps its launch surface until Flutter produces the first frame.
      // A minimal surface supplies the foreground prerequisite for capture APIs.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final a = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      final b = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final capabilities = await a.capabilities();
      expect(capabilities.map((c) => c.id).toSet().length, capabilities.length);
      Future<SecuritySnapshot> scan(SecuritySdk sdk, List<String> ids) =>
          sdk.scan(
            ScanRequest(
              contextId: 'native-test',
              detectorIds: ids,
              timeout: const Duration(seconds: 5),
            ),
          );
      final environment = await scan(a, SecurityDetectors.environment);
      expect(environment.findings.length, SecurityDetectors.environment.length);
      // Emulator marker: this test is intentionally run on a simulator/emulator.
      expect(environment.findings.first.status, DetectionStatus.detected);
      // Normal installed app on both platforms: no embedded executable or
      // Android profile/container identity discrepancy.
      final multi = environment.findings.singleWhere(
        (f) => f.detectorId == SecurityDetectors.multiInstance,
      );
      expect(
        capabilities
            .singleWhere((c) => c.id == SecurityDetectors.multiInstance)
            .supported,
        isTrue,
      );
      expect(
        (multi.status, multi.reason),
        isIn([
          (DetectionStatus.notDetected, FindingReason.noKnownSignal),
          if (defaultTargetPlatform == TargetPlatform.android)
            (DetectionStatus.unsupported, FindingReason.profileTypeUnavailable),
        ]),
      );
      expect(
        multi.detectorVersion,
        defaultTargetPlatform == TargetPlatform.iOS ? 'local-v8' : 'local-v7',
      );
      final screenshotSupported = capabilities
          .singleWhere((c) => c.id == 'screenshot')
          .supported;
      if (!screenshotSupported) {
        final finding = (await scan(a, ['screenshot'])).findings.single;
        expect(finding.status, DetectionStatus.unsupported);
        expect(finding.reason, FindingReason.unsupportedOsVersion);
        await expectLater(
          a.startScreenshotObservation(),
          throwsA(isA<SecurityFailure>()),
        );
        return;
      }
      final before = await scan(a, ['screenshot']);
      expect(before.findings.single.reason, FindingReason.observationRequired);
      await a.startScreenshotObservation();
      await b.startScreenshotObservation();
      expect(
        (await scan(a, ['screenshot'])).findings.single.status,
        DetectionStatus.notDetected,
      );
      await a.dispose();
      expect(
        (await scan(b, ['screenshot'])).findings.single.status,
        DetectionStatus.notDetected,
      );
      await b.stopScreenshotObservation();
      expect(
        (await scan(b, ['screenshot'])).findings.single.reason,
        FindingReason.observationRequired,
      );
    },
    semanticsEnabled: false,
  );
  testWidgets(
    'headless engine detach cannot affect the foreground engine',
    (tester) async {
      const fixture = MethodChannel('security_sdk/lifecycle_test');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(sdk.dispose);
      addTearDown(() => fixture.invokeMethod<void>('stopPeer'));
      final supported = (await sdk.capabilities())
          .singleWhere((c) => c.id == 'screenshot')
          .supported;
      if (!supported) return;
      await sdk.startScreenshotObservation();
      for (var cycle = 0; cycle < 2; cycle++) {
        final report = await fixture.invokeMapMethod<String, dynamic>(
          'startPeer',
        );
        expect(report!['start'], 'platformUnavailable');
        expect(
          report['statuses'],
          everyElement(isIn(['error', 'unsupported'])),
        );
        Future<void> verifyForeground() async {
          final snapshot = await sdk.scan(
            ScanRequest(
              contextId: 'foreground',
              timeout: const Duration(seconds: 5),
              detectorIds: ['screenshot'],
            ),
          );
          expect(snapshot.findings.single.status, DetectionStatus.notDetected);
        }

        await verifyForeground();
        await fixture.invokeMethod<void>('stopPeer');
        await verifyForeground();
      }
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'native capture notification interruption and explicit restart',
    (tester) async {
      const fixture = MethodChannel('security_sdk/lifecycle_test');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(sdk.dispose);
      if (!(await sdk.capabilities())
          .singleWhere((c) => c.id == 'screenshot')
          .supported) {
        return;
      }
      Future<SecurityFinding> screenshot() async => (await sdk.scan(
        ScanRequest(
          contextId: 'notifications',
          detectorIds: ['screenshot'],
          timeout: const Duration(seconds: 5),
        ),
      )).findings.single;
      await sdk.startScreenshotObservation();
      await fixture.invokeMethod<void>('interruptCapture');
      expect((await screenshot()).reason, FindingReason.observationInterrupted);
      await sdk.startScreenshotObservation();
      expect((await screenshot()).status, DetectionStatus.notDetected);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await fixture.invokeMethod<void>('screenshot');
        expect((await screenshot()).reason, FindingReason.screenshotObserved);
      }
      await sdk.stopScreenshotObservation();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await fixture.invokeMethod<void>('screenshot');
      }
      expect((await screenshot()).reason, FindingReason.observationRequired);
      await sdk.startScreenshotObservation();
      expect((await screenshot()).status, DetectionStatus.notDetected);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'Scene isolation and OS rotation preserve valid observation scope',
    (tester) async {
      const fixture = MethodChannel('security_sdk/lifecycle_test');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(sdk.dispose);
      addTearDown(() => fixture.invokeMethod<Object?>('restoreOrientation'));
      if (!(await sdk.capabilities())
          .singleWhere((c) => c.id == 'screenshot')
          .supported) {
        return;
      }
      Future<SecurityFinding> read() async => (await sdk.scan(
        ScanRequest(
          contextId: 'geometry',
          detectorIds: ['screenshot'],
          timeout: const Duration(seconds: 5),
        ),
      )).findings.single;
      await sdk.startScreenshotObservation();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        expect(await fixture.invokeMethod<bool>('applicationInactive'), isTrue);
        expect((await read()).status, DetectionStatus.notDetected);
        await fixture.invokeMethod<void>('screenshot');
        expect((await read()).reason, FindingReason.screenshotObserved);
      }
      final orientation = await fixture.invokeMethod<int>('rotate');
      if (orientation == 0) return; // No Scene geometry request before iOS 16.
      await waitForNativeUi(
        (state) =>
            state['orientation'] == orientation && state['focus'] == true,
      );
      final rotated = await read();
      // OS rotation may cause a genuine focus/activation gap. It must never manufacture
      // a positive or silently turn previously observed evidence into a clean window.
      expect(
        rotated.reason,
        isIn([
          FindingReason.observationInterrupted,
          defaultTargetPlatform == TargetPlatform.iOS
              ? FindingReason.screenshotObserved
              : FindingReason.noKnownSignal,
        ]),
      );
      if (rotated.reason == FindingReason.observationInterrupted) {
        await sdk.startScreenshotObservation();
        expect((await read()).status, DetectionStatus.notDetected);
      }
    },
    semanticsEnabled: false,
  );

  if (defaultTargetPlatform == TargetPlatform.android) {
    testWidgets(
      'actual PiP cannot reuse the foreground capture window',
      (tester) async {
        const fixture = MethodChannel('security_sdk/lifecycle_test');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
        addTearDown(sdk.dispose);
        addTearDown(() => fixture.invokeMethod<void>('leavePip'));
        if (!(await sdk.capabilities())
            .singleWhere((c) => c.id == 'screenshot')
            .supported) {
          return;
        }
        await waitForNativeUi(
          (state) => state['focus'] == true && state['pip'] == false,
        );
        try {
          await sdk.startScreenshotObservation();
        } on SecurityFailure {
          fail(
            'PiP fixture start failed at ${await fixture.invokeMapMethod<String, dynamic>('uiState')}',
          );
        }
        expect(await fixture.invokeMethod<bool>('enterPip'), isTrue);
        await waitForNativeUi((state) => state['pip'] == true);
        final snapshot = await sdk.scan(
          ScanRequest(
            contextId: 'pip',
            detectorIds: ['screenshot', 'screenRecording'],
            timeout: const Duration(seconds: 5),
          ),
        );
        expect(
          snapshot.findings.first.reason,
          FindingReason.observationInterrupted,
        );
        expect(
          snapshot.findings.last.status,
          isIn([DetectionStatus.error, DetectionStatus.unsupported]),
        );
        await expectLater(
          sdk.startScreenshotObservation(),
          throwsA(isA<SecurityFailure>()),
        );
        await fixture.invokeMethod<void>('leavePip');
        await waitForNativeUi(
          (state) =>
              state['pip'] == false &&
              state['focus'] == true &&
              state['resumed'] == true,
        );
        try {
          await sdk.startScreenshotObservation();
        } on SecurityFailure {
          fail(
            'PiP fixture start failed at ${await fixture.invokeMapMethod<String, dynamic>('uiState')}',
          );
        }
        final restored = await sdk.scan(
          ScanRequest(
            contextId: 'restored',
            detectorIds: ['screenshot'],
            timeout: const Duration(seconds: 5),
          ),
        );
        expect(restored.findings.single.status, DetectionStatus.notDetected);
      },
      semanticsEnabled: false,
    );
  }

  testWidgets('runtime signals and trusted bundle baseline', (_) async {
    final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 10));
    addTearDown(sdk.dispose);
    final capabilities = await sdk.capabilities();
    for (final id in [SecurityDetectors.hook, SecurityDetectors.appIntegrity]) {
      expect(capabilities.singleWhere((c) => c.id == id).supported, isTrue);
    }
    final runtime = await sdk.scan(
      ScanRequest(
        contextId: 'runtime-test',
        detectorIds: SecurityDetectors.runtime,
        timeout: const Duration(seconds: 10),
      ),
    );
    expect(
      runtime.findings.last.reason,
      FindingReason.integrityBaselineRequired,
    );
    expect(runtime.findings.last.status, DetectionStatus.error);
    expect(runtime.findings[1].status, isNot(DetectionStatus.unsupported));
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Exercise the actual proc maps reader, not only synthetic parser fixtures.
      expect(runtime.findings[1].status, DetectionStatus.notDetected);
      expect(runtime.findings[1].reason, FindingReason.noKnownSignal);
      // Stock sandbox may hide a root-probe path. A denied probe is unknown.
      expect(
        runtime.findings.first.reason,
        isIn([
          FindingReason.noKnownSignal,
          FindingReason.probeAccessRestricted,
          FindingReason.testKeysBuild,
        ]),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      expect(runtime.findings.first.reason, FindingReason.simulatorEnvironment);
      expect(runtime.findings.first.status, DetectionStatus.unsupported);
      final debuggerCapability = capabilities.singleWhere(
        (c) => c.id == 'debugger',
      );
      expect(debuggerCapability.supported, isTrue);
      expect(
        runtime.findings[2].status,
        debuggerCapability.requiresExplicitOptIn
            ? DetectionStatus.unsupported
            : isIn([DetectionStatus.detected, DetectionStatus.notDetected]),
      );
      final explicitTrace = await sdk.scan(
        ScanRequest(
          contextId: 'release-trace-test',
          detectorIds: ['debugger'],
          iosDebuggerMode: IosDebuggerMode.allowReleaseProcessTrace,
          timeout: const Duration(seconds: 10),
        ),
      );
      expect(
        explicitTrace.findings.single.status,
        isIn([DetectionStatus.detected, DetectionStatus.notDetected]),
      );
      const path =
          'Frameworks/App.framework/flutter_assets/assets/integrity_fixture.txt';
      const hash =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      Future<SecurityFinding> check(
        String id,
        Map<String, String> files,
      ) async => (await sdk.scan(
        ScanRequest(
          contextId: 'integrity-test',
          detectorIds: ['appIntegrity'],
          integrityPolicy: AppIntegrityPolicy(
            expectedApplicationId: id,
            iosBundleFileSha256: files,
          ),
          timeout: const Duration(seconds: 10),
        ),
      )).findings.single;
      final matched = await check('dev.securitysdk.securityFlutterExample', {
        path: hash,
      });
      expect(matched.status, DetectionStatus.notDetected);
      expect(matched.reason, FindingReason.bundleBaselineMatched);
      expect(
        (await check('dev.securitysdk.securityFlutterExample', {
          path: '0' * 64,
        })).reason,
        FindingReason.integrityFileMismatch,
      );
      expect(
        (await check('dev.securitysdk.securityFlutterExample', {
          'missing-fixture': hash,
        })).reason,
        FindingReason.integrityFileMissing,
      );
      expect(
        (await check('wrong.application', {path: hash})).reason,
        FindingReason.applicationIdMismatch,
      );
    }
  }, semanticsEnabled: false);
}

Future<void> waitForNativeUi(bool Function(Map<String, dynamic>) ready) async {
  const fixture = MethodChannel('security_sdk/lifecycle_test');
  Map<String, dynamic>? lastState;
  var consecutive = 0;
  for (var i = 0; i < 100; i++) {
    final state = await fixture.invokeMapMethod<String, dynamic>('uiState');
    lastState = state;
    consecutive = state != null && ready(state) ? consecutive + 1 : 0;
    if (consecutive >= 3) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Native UI did not reach the required test state: $lastState');
}
