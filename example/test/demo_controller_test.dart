import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_sdk_demo/src/demo_controller.dart';
import 'package:security_sdk_demo/host_input_example.dart';
import 'package:security_sdk_demo/session_example.dart';

class FakePlatform implements SecurityPlatform, ScreenshotObservationPlatform {
  final requests = <ScanRequest>[];
  final events = <String>[];
  Completer<void>? pending;
  bool fail = false;
  int capabilityCalls = 0;
  int disposals = 0;

  @override
  Future<List<DetectorCapability>> capabilities() async {
    capabilityCalls++;
    return const [DetectorCapability(id: 'root', supported: false)];
  }

  @override
  Future<SecuritySnapshot> scan(ScanRequest request) async {
    requests.add(request);
    await pending?.future;
    if (fail) throw const SecurityFailure(SecurityErrorCode.timeout);
    return SecuritySnapshot(
      contextId: request.contextId,
      observedAt: DateTime.now(),
      findings: request.detectorIds.map(
        (id) => SecurityFinding(
          detectorId: id,
          detectorVersion: 'fixture',
          status: id == SecurityDetectors.appIntegrity
              ? DetectionStatus.error
              : DetectionStatus.notDetected,
          reason: id == SecurityDetectors.appIntegrity
              ? FindingReason.integrityBaselineRequired
              : FindingReason.noKnownSignal,
        ),
      ),
    );
  }

  @override
  Future<void> startScreenshotObservation() async => events.add('start');
  @override
  Future<void> stopScreenshotObservation() async => events.add('stop');
  @override
  Future<void> dispose() async => disposals++;
}

void main() {
  late FakePlatform platform;
  late DemoController controller;
  setUp(() {
    platform = FakePlatform();
    controller = DemoController(
      sdk: SecuritySdk(
        operationTimeout: const Duration(seconds: 5),
        platform: platform,
      ),
    );
  });
  tearDown(() => controller.dispose());

  test(
    'construction performs no collection and local scan omits host inputs',
    () async {
      expect(platform.requests, isEmpty);
      expect(platform.capabilityCalls, 0);
      await controller.scanLocal();
      final request = platform.requests.single;
      expect(request.detectorIds.toSet().length, request.detectorIds.length);
      expect(
        request.detectorIds,
        containsAll(['root', 'hook', 'multiInstance']),
      );
      expect(request.detectorIds, isNot(contains('appIntegrity')));
      expect(request.iosDebuggerMode, IosDebuggerMode.debugBuildOnly);
    },
  );

  test('release debugger requires explicit user choice', () async {
    controller.setReleaseDebugger(true);
    await controller.scanLocal();
    expect(
      platform.requests.single.iosDebuggerMode,
      IosDebuggerMode.allowReleaseProcessTrace,
    );
  });

  test(
    'overlapping actions are ignored until the current request completes',
    () async {
      platform.pending = Completer<void>();
      final scan = controller.scanLocal();
      await controller.queryCapabilities();
      await controller.restartObservation();
      expect(controller.busy, isTrue);
      expect(platform.capabilityCalls, 0);
      expect(platform.events, isEmpty);
      platform.pending!.complete();
      await scan;
      expect(controller.busy, isFalse);
    },
  );

  test(
    'failure clears previous findings instead of preserving stale success',
    () async {
      await controller.scanLocal();
      expect(controller.findings, isNotEmpty);
      platform.fail = true;
      await controller.scanLocal();
      expect(controller.findings, isEmpty);
      expect(controller.message, contains('timeout'));
      expect(controller.busy, isFalse);
    },
  );

  test('missing inputs remain explicit errors', () async {
    await controller.showMissingInputs();
    expect(
      controller.findings.map((f) => f.status),
      everyElement(DetectionStatus.error),
    );
    expect(controller.findings.map((f) => f.reason), [
      FindingReason.integrityBaselineRequired,
      FindingReason.timeReferenceRequired,
      FindingReason.locationSampleRequired,
    ]);
  });

  test(
    'restarting capture closes old window before starting a new one',
    () async {
      await controller.restartObservation();
      await controller.stopObservation();
      expect(platform.events, ['stop', 'start', 'stop']);
    },
  );

  test('dispose suppresses late state updates and releases SDK once', () async {
    platform.pending = Completer<void>();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final scan = controller.scanLocal();
    final before = notifications;
    controller.dispose();
    platform.pending!.complete();
    await scan;
    await Future<void>.delayed(Duration.zero);
    expect(notifications, before);
    expect(controller.findings, isEmpty);
    expect(platform.disposals, 1);
  });
  test('all detectors and single item use the shared scan contract', () async {
    await controller.scanAll();
    expect(
      controller.findings.map((f) => f.detectorId),
      DemoController.detectorIds,
    );
    expect(controller.findings.length, 16);
    expect(
      DemoController.detectorIds,
      containsAll([
        SecurityDetectors.developerMode,
        SecurityDetectors.usbDebugging,
      ]),
    );
    expect(DemoController.detectorIds.toSet().length, 16);
    controller.selectDetector(SecurityDetectors.hook);
    controller.setTimeoutSeconds(10);
    await controller.scanSelected();
    expect(platform.requests.last.detectorIds, [SecurityDetectors.hook]);
    expect(platform.requests.last.timeout, const Duration(seconds: 10));
  });

  test(
    'cancel rejects the result and ignores a late native completion',
    () async {
      platform.pending = Completer<void>();
      final pending = controller.scanLocal();
      expect(controller.canCancel, isTrue);
      controller.cancelScan();
      await pending;
      expect(controller.message, contains('cancelled'));
      expect(controller.findings, isEmpty);
      expect(controller.canCancel, isFalse);
      platform.pending!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.findings, isEmpty);
    },
  );

  test(
    'request timeout is surfaced without a fabricated clean result',
    () async {
      controller.setTimeoutSeconds(1);
      platform.pending = Completer<void>();
      await controller.scanLocal();
      expect(controller.message, contains('timeout'));
      expect(controller.findings, isEmpty);
      platform.pending!.complete();
    },
  );

  test('start preserves window, restart explicitly stops first', () async {
    await controller.startObservation();
    await controller.startObservation();
    await controller.restartObservation();
    expect(platform.events, ['start', 'start', 'stop', 'start']);
  });

  test(
    'explicit release is awaitable and later calls report disposed',
    () async {
      await controller.releaseSdk();
      expect(controller.released, isTrue);
      expect(platform.disposals, 1);
      await controller.queryCapabilities();
      expect(controller.message, contains('disposed'));
      expect(platform.capabilityCalls, 0);
      controller.dispose();
      expect(platform.disposals, 1);
    },
  );

  test(
    'host input injection forwards baseline and preserves unknown location',
    () async {
      controller.dispose();
      platform = FakePlatform();
      final policy = integrityFromReleaseManifest(
        applicationId: 'dev.fixture',
        androidSignerSets: [
          ['a' * 64],
        ],
      );
      controller = DemoController(
        sdk: SecuritySdk(
          operationTimeout: const Duration(seconds: 5),
          platform: platform,
        ),
        hostInputs: DemoHostInputs(
          integrityPolicy: policy,
          timeReference: timeAtAuthenticatedReceipt(
            serverTimeAtReceipt: DateTime.now(),
            allowedSkew: const Duration(minutes: 1),
            validFor: const Duration(minutes: 1),
          ),
          locationSample: locationFromAuthorizedFlow(
            businessUseAuthorized: true,
            permissionGranted: true,
            isMocked: null,
            ageAtReceipt: Duration.zero,
            maxAge: const Duration(minutes: 1),
          ),
        ),
      );
      expect(platform.requests, isEmpty);
      await controller.scanAll();
      expect(platform.requests.single.integrityPolicy, same(policy));
      expect(
        controller.findings
            .singleWhere((f) => f.detectorId == 'mockLocation')
            .reason,
        FindingReason.locationSourceUnavailable,
      );
      await controller.showMissingInputs();
      expect(platform.requests.last.integrityPolicy, isNull);
      expect(
        controller.findings.map((f) => f.status),
        everyElement(DetectionStatus.error),
      );
    },
  );
  test('owned session releases its platform even when scan fails', () async {
    platform.fail = true;
    await expectLater(
      scanInOwnedSession(
        ScanRequest(
          contextId: 'owned-session',
          detectorIds: [SecurityDetectors.hook],
          timeout: const Duration(seconds: 5),
        ),
        platform: platform,
      ),
      throwsA(isA<SecurityFailure>()),
    );
    expect(platform.disposals, 1);
  });

  test('cancellation example detaches its listener on success', () async {
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 5),
      platform: platform,
    );
    final token = CancellationToken();
    var callbacks = 0;
    await scanWithCancellation(
      sdk,
      token: token,
      onCancelled: () => callbacks++,
      contextId: 'cancel-example',
      detectorIds: [SecurityDetectors.hook],
      timeout: const Duration(seconds: 5),
    );
    token.cancel();
    expect(callbacks, 0);
    await sdk.dispose();
  });

  test('pre-cancelled example does not start native work', () async {
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 5),
      platform: platform,
    );
    final token = CancellationToken()..cancel();
    var callbacks = 0;
    await expectLater(
      scanWithCancellation(
        sdk,
        token: token,
        onCancelled: () => callbacks++,
        contextId: 'cancel-example',
        detectorIds: [SecurityDetectors.hook],
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<SecurityFailure>()),
    );
    expect(callbacks, 1);
    expect(platform.requests, isEmpty);
    await sdk.dispose();
  });
}
