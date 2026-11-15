import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/signals_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  SecuritySdk sdk({Duration timeout = const Duration(seconds: 1)}) =>
      SecuritySdk(
        operationTimeout: timeout,
        platform: MethodChannelSecurityPlatform(channel: channel),
      );
  ScanRequest request(
    List<String> ids, {
    LocationRiskSample? sample,
    TrustedTimeReference? time,
  }) => ScanRequest(
    contextId: 'test',
    detectorIds: ids,
    timeout: const Duration(seconds: 1),
    locationSample: sample,
    timeReference: time,
  );
  test(
    'input-only scans do not touch native services or request permissions',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });
      final client = sdk();
      final result = await client.scan(
        request([
          SecurityDetectors.mockLocation,
          SecurityDetectors.timeAnomaly,
        ]),
      );
      expect(result.findings.map((f) => f.reason), [
        FindingReason.locationSampleRequired,
        FindingReason.timeReferenceRequired,
      ]);
      expect(
        result.findings.every((f) => f.status == DetectionStatus.error),
        isTrue,
      );
      await client.dispose();
      expect(calls, 0);
    },
  );
  test(
    'mixed scans preserve order and keep location/time input off native channel',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map;
        expect(args['detectorIds'], ['emulator']);
        expect(args.keys.toSet(), {'owner', 'contextId', 'detectorIds'});
        return {
          'schemaVersion': 1,
          'contextId': 'test',
          'findings': [
            {
              'detectorId': 'emulator',
              'detectorVersion': 'local-v1',
              'status': 'detected',
              'reason': 'emulatorBuild',
            },
          ],
        };
      });
      final client = sdk();
      final result = await client.scan(
        request(
          ['mockLocation', 'emulator', 'timeAnomaly'],
          sample: LocationRiskSample(
            businessUseAuthorized: true,
            permissionGranted: true,
            isMocked: true,
            ageAtReceipt: Duration.zero,
            maxAge: const Duration(minutes: 1),
          ),
          time: TrustedTimeReference(
            serverTimeAtReceipt: DateTime.now(),
            allowedSkew: const Duration(seconds: 5),
            validFor: const Duration(minutes: 1),
          ),
        ),
      );
      expect(result.findings.map((f) => f.detectorId), [
        'mockLocation',
        'emulator',
        'timeAnomaly',
      ]);
      expect(result.findings.map((f) => f.status), [
        DetectionStatus.detected,
        DetectionStatus.detected,
        DetectionStatus.notDetected,
      ]);
      await client.dispose();
    },
  );
  test('unknown reason strings are rejected and never exposed', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': 1,
        'contextId': 'test',
        'findings': [
          {
            'detectorId': 'vpn',
            'detectorVersion': 'v1',
            'status': 'error',
            'reason': 'private platform message',
          },
        ],
      },
    );
    final client = sdk();
    await expectLater(
      client.scan(request(['vpn'])),
      throwsA(
        isA<SecurityFailure>().having(
          (f) => f.code,
          'code',
          SecurityErrorCode.invalidResponse,
        ),
      ),
    );
    await client.dispose();
  });
  test(
    'screenshot windows use distinct owners; dispose only stops its own window',
    () async {
      final active = <String>{};
      messenger.setMockMethodCallHandler(channel, (call) async {
        final owner = (call.arguments as Map)['owner'] as String;
        if (call.method == 'startScreenshotObservation') active.add(owner);
        if (call.method == 'stopScreenshotObservation') active.remove(owner);
        return {'schemaVersion': 1};
      });
      final a = sdk();
      final b = sdk();
      await a.startScreenshotObservation();
      await a.startScreenshotObservation();
      await b.startScreenshotObservation();
      expect(active.length, 2);
      await a.dispose();
      expect(active.length, 1);
      await b.stopScreenshotObservation();
      expect(active, isEmpty);
      await b.dispose();
    },
  );
  test(
    'timed out screenshot start sends cleanup even when native reply is late',
    () async {
      final pending = Completer<Object?>();
      var stopped = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'startScreenshotObservation') return pending.future;
        stopped = true;
        return {'schemaVersion': 1};
      });
      final client = sdk(timeout: const Duration(milliseconds: 10));
      await expectLater(
        client.startScreenshotObservation(),
        throwsA(
          isA<SecurityFailure>().having(
            (f) => f.code,
            'code',
            SecurityErrorCode.timeout,
          ),
        ),
      );
      expect(stopped, isTrue);
      pending.complete({'schemaVersion': 1});
      await client.dispose();
    },
  );
  test('old OS observation errors stay unsupported', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startScreenshotObservation') {
        throw PlatformException(code: 'unsupported');
      }
      return {'schemaVersion': 1};
    });
    final client = sdk();
    await expectLater(
      client.startScreenshotObservation(),
      throwsA(
        isA<SecurityFailure>().having(
          (f) => f.code,
          'code',
          SecurityErrorCode.unsupported,
        ),
      ),
    );
    await client.dispose();
  });
  test('observation cannot start after disposal', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return {'schemaVersion': 1};
    });
    final client = sdk();
    await client.dispose();
    await expectLater(
      client.startScreenshotObservation(),
      throwsA(
        isA<SecurityFailure>().having(
          (f) => f.code,
          'code',
          SecurityErrorCode.disposed,
        ),
      ),
    );
    expect(calls, 0);
  });
}
