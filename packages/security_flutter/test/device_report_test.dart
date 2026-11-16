import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

DeviceInfo info([DevicePlatform platform = DevicePlatform.android]) =>
    DeviceInfo(
      platform: platform,
      manufacturer: 'maker',
      brand: 'brand',
      model: 'model',
      systemVersion: '16',
      apiLevel: platform == DevicePlatform.android ? 36 : null,
    );
Matcher fails(SecurityErrorCode code) =>
    throwsA(isA<SecurityFailure>().having((e) => e.code, 'code', code));

class ProfilePlatform
    implements
        SecurityPlatform,
        DeviceInfoPlatform,
        ScreenshotObservationPlatform {
  int infos = 0, scans = 0, starts = 0;
  Object? failure;
  Completer<DeviceInfo>? pending;
  ScanRequest? last;
  DevicePlatform os = DevicePlatform.android;
  @override
  Future<DeviceInfo> deviceInfo() async {
    infos++;
    if (failure != null) throw failure!;
    return pending == null ? info(os) : await pending!.future;
  }

  @override
  Future<List<DetectorCapability>> capabilities() async => [
    for (final id in SecurityDetectors.all)
      DetectorCapability(id: id, supported: false),
  ];
  @override
  Future<SecuritySnapshot> scan(ScanRequest request) async {
    scans++;
    last = request;
    return SecuritySnapshot(
      contextId: request.contextId,
      observedAt: DateTime.now(),
      findings: request.detectorIds.map(
        (id) => SecurityFinding(
          detectorId: id,
          detectorVersion: 'fixture',
          status: id == 'screenshot'
              ? DetectionStatus.error
              : DetectionStatus.unsupported,
          reason: id == 'screenshot'
              ? FindingReason.observationRequired
              : FindingReason.unsupportedPlatform,
        ),
      ),
    );
  }

  @override
  Future<void> startScreenshotObservation() async {
    starts++;
  }

  @override
  Future<void> stopScreenshotObservation() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'one explicit call returns basic info, capabilities and all 16 findings',
    () async {
      final p = ProfilePlatform();
      final sdk = SecuritySdk(
        operationTimeout: const Duration(seconds: 2),
        platform: p,
      );
      addTearDown(sdk.dispose);
      expect(p.infos, 0);
      expect(p.scans, 0);
      final r = await sdk.collectDeviceReport(contextId: 'report');
      expect(r.device.info!.platform, DevicePlatform.android);
      expect(
        r.security.findings.map((f) => f.detectorId),
        SecurityDetectors.all,
      );
      expect(r.capabilities.length, 16);
      expect(r.security.findings.length, 16);
      expect(p.starts, 0);
      expect(
        r.security.findings
            .singleWhere((f) => f.detectorId == 'screenshot')
            .reason,
        FindingReason.observationRequired,
      );
      expect(
        r.security.findings
            .singleWhere((f) => f.detectorId == 'timeAnomaly')
            .reason,
        FindingReason.timeReferenceRequired,
      );
      expect(
        r.security.findings
            .singleWhere((f) => f.detectorId == 'mockLocation')
            .reason,
        FindingReason.locationSampleRequired,
      );
      expect(() => r.capabilities.clear(), throwsUnsupportedError);
    },
  );
  test(
    'iOS provider uses the same report contract and no Android API level',
    () async {
      final p = ProfilePlatform()..os = DevicePlatform.ios;
      final sdk = SecuritySdk(
        operationTimeout: const Duration(seconds: 2),
        platform: p,
      );
      addTearDown(sdk.dispose);
      final r = await sdk.collectDeviceReport(
        contextId: 'ios',
        detectorIds: ['developerMode'],
      );
      expect(r.device.info!.platform, DevicePlatform.ios);
      expect(r.device.info!.apiLevel, isNull);
      expect(r.security.findings.single.status, DetectionStatus.unsupported);
    },
  );
  test(
    'unsupported or legacy providers need no new interface implementation',
    () async {
      final sdk = SecuritySdk(
        operationTimeout: const Duration(seconds: 2),
        platform: const UnsupportedSecurityPlatform(),
      );
      addTearDown(sdk.dispose);
      final r = await sdk.collectDeviceReport(contextId: 'other');
      expect(r.device.status, DeviceInfoStatus.unsupported);
      expect(r.security.findings.first.status, DetectionStatus.unsupported);
    },
  );
  test(
    'basic info failure stays explicit while security observations survive',
    () async {
      final p = ProfilePlatform()
        ..failure = const SecurityFailure(
          SecurityErrorCode.platformUnavailable,
        );
      final sdk = SecuritySdk(
        operationTimeout: const Duration(seconds: 2),
        platform: p,
      );
      addTearDown(sdk.dispose);
      final r = await sdk.collectDeviceReport(contextId: 'report');
      expect(r.device.status, DeviceInfoStatus.error);
      expect(r.device.info, isNull);
      expect(r.device.code, SecurityErrorCode.platformUnavailable);
      expect(r.security.findings.length, 16);
    },
  );
  test('raw provider errors are not forwarded', () async {
    final p = ProfilePlatform()..failure = StateError('private native text');
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 2),
      platform: p,
    );
    addTearDown(sdk.dispose);
    final r = await sdk.deviceInfo();
    expect(r.code, SecurityErrorCode.internalError);
    expect(r.toString(), isNot(contains('private')));
  });
  test('host inputs and Release opt-in are preserved', () async {
    final p = ProfilePlatform();
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 2),
      platform: p,
    );
    addTearDown(sdk.dispose);
    final r = await sdk.collectDeviceReport(
      contextId: 'host',
      detectorIds: ['debugger', 'mockLocation'],
      iosDebuggerMode: IosDebuggerMode.allowReleaseProcessTrace,
      locationSample: LocationRiskSample(
        businessUseAuthorized: true,
        permissionGranted: true,
        isMocked: true,
        ageAtReceipt: Duration.zero,
        maxAge: const Duration(seconds: 30),
      ),
    );
    expect(p.last!.iosDebuggerMode, IosDebuggerMode.allowReleaseProcessTrace);
    expect(r.security.findings.last.status, DetectionStatus.detected);
  });
  test('cancelled and disposed reports do not start collection', () async {
    final p = ProfilePlatform();
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 2),
      platform: p,
    );
    final cancel = CancellationToken()..cancel();
    await expectLater(
      sdk.collectDeviceReport(contextId: 'cancel', cancellation: cancel),
      fails(SecurityErrorCode.cancelled),
    );
    expect(p.infos, 0);
    expect(p.scans, 0);
    await sdk.dispose();
    await expectLater(
      sdk.collectDeviceReport(contextId: 'disposed'),
      fails(SecurityErrorCode.disposed),
    );
    expect(p.infos, 0);
  });
  test(
    'report timeout covers a stalled info read without a fabricated result',
    () async {
      final p = ProfilePlatform()..pending = Completer<DeviceInfo>();
      final sdk = SecuritySdk(
        operationTimeout: const Duration(seconds: 2),
        platform: p,
      );
      addTearDown(sdk.dispose);
      await expectLater(
        sdk.collectDeviceReport(
          contextId: 'timeout',
          timeout: const Duration(milliseconds: 10),
        ),
        fails(SecurityErrorCode.timeout),
      );
      p.pending!.complete(info());
      await Future<void>.delayed(Duration.zero);
    },
  );
  const channel = MethodChannel('device-info-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Map<String, Object?> wire() => {
    'schemaVersion': 1,
    'device': {
      'platform': 'android',
      'manufacturer': 'maker',
      'brand': 'brand',
      'model': 'model',
      'systemVersion': '16',
      'apiLevel': 36,
    },
  };
  test(
    'native parser accepts Android and iOS and rejects personal extra fields',
    () async {
      final platform = MethodChannelSecurityPlatform(channel: channel);
      var response = wire();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'deviceInfo');
        return response;
      });
      expect((await platform.deviceInfo()).apiLevel, 36);
      response = {
        'schemaVersion': 1,
        'device': {
          'platform': 'ios',
          'manufacturer': 'Apple',
          'brand': 'Apple',
          'model': 'iPhone17,1',
          'systemVersion': '18.0',
          'apiLevel': null,
        },
      };
      expect((await platform.deviceInfo()).platform, DevicePlatform.ios);
      for (final key in ['serial', 'identifierForVendor', 'deviceName']) {
        response = wire();
        (response['device'] as Map)[key] = 'forbidden';
        await expectLater(
          platform.deviceInfo(),
          fails(SecurityErrorCode.invalidResponse),
        );
      }
    },
  );
  test('malformed native metadata cannot become available', () async {
    final platform = MethodChannelSecurityPlatform(channel: channel);
    var response = wire();
    messenger.setMockMethodCallHandler(channel, (_) async => response);
    for (final entry in [
      const MapEntry('model', ''),
      const MapEntry('brand', 'a\nb'),
      const MapEntry('apiLevel', true),
      const MapEntry('apiLevel', null),
      const MapEntry('platform', 'linux'),
      MapEntry('model', 'x' * 257),
    ]) {
      response = wire();
      (response['device'] as Map)[entry.key] = entry.value;
      await expectLater(
        platform.deviceInfo(),
        fails(SecurityErrorCode.invalidResponse),
      );
    }
  });
}
