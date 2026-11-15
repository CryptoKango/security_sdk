import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

class HangingDisposePlatform implements SecurityPlatform {
  final pending = Completer<void>();
  int disposals = 0;
  @override
  Future<List<DetectorCapability>> capabilities() async => [];
  @override
  Future<SecuritySnapshot> scan(ScanRequest request) =>
      throw UnimplementedError();
  @override
  Future<void> dispose() {
    disposals++;
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/review_regression');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final invalid = throwsA(
    isA<SecurityFailure>().having(
      (e) => e.code,
      'code',
      SecurityErrorCode.invalidResponse,
    ),
  );
  Future<SecuritySnapshot> scan(String id) =>
      MethodChannelSecurityPlatform(channel: channel).scan(
        ScanRequest(
          contextId: 'test',
          detectorIds: [id],
          timeout: const Duration(seconds: 1),
        ),
      );
  void reply(String id, String status, String? reason, {Object schema = 1}) {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': schema,
        'contextId': 'test',
        'findings': [
          {
            'detectorId': id,
            'detectorVersion': 'local-v1',
            'status': status,
            'reason': ?reason,
          },
        ],
      },
    );
  }

  test(
    'contradictory native statuses cannot become clean or positive verdicts',
    () async {
      for (final sample in [
        ('root', 'notDetected', 'probeAccessRestricted'),
        ('hook', 'notDetected', 'hookModule'),
        ('root', 'detected', 'noKnownSignal'),
        ('root', 'detected', 'emulatorBuild'),
        ('debugger', 'notDetected', 'releaseDebuggerOptInRequired'),
        ('vpn', 'error', 'noKnownSignal'),
        ('root', 'unsupported', 'rootArtifact'),
      ]) {
        reply(sample.$1, sample.$2, sample.$3);
        await expectLater(scan(sample.$1), invalid);
      }
    },
  );
  test(
    'integrity requires a baseline match and successful verdicts require reasons',
    () async {
      for (final sample in [
        ('appIntegrity', 'noKnownSignal'),
        ('root', 'signingBaselineMatched'),
        ('root', 'noActiveNetwork'),
        ('unknown', 'noKnownSignal'),
      ]) {
        reply(sample.$1, 'notDetected', sample.$2);
        await expectLater(scan(sample.$1), invalid);
      }
      for (final status in ['detected', 'notDetected']) {
        reply('root', status, null);
        await expectLater(scan('root'), invalid);
      }
    },
  );
  test(
    'valid baseline matches and offline observations remain distinct',
    () async {
      for (final sample in [
        ('appIntegrity', 'signingBaselineMatched'),
        ('appIntegrity', 'bundleBaselineMatched'),
        ('vpn', 'noActiveNetwork'),
        ('root', 'noKnownSignal'),
      ]) {
        reply(sample.$1, 'notDetected', sample.$2);
        expect((await scan(sample.$1)).findings.single.reason?.name, sample.$2);
      }
      reply('unknown', 'unsupported', 'unimplemented');
      expect(
        (await scan('unknown')).findings.single.status,
        DetectionStatus.unsupported,
      );
    },
  );
  test('non-integer schema versions are rejected', () async {
    reply('root', 'notDetected', 'noKnownSignal', schema: 1.0);
    await expectLater(scan('root'), invalid);
  });
  test(
    'dispose has a deadline, rejects new work and consumes late errors',
    () async {
      final platform = HangingDisposePlatform();
      final sdk = SecuritySdk(
        operationTimeout: const Duration(milliseconds: 10),
        platform: platform,
      );
      final disposal = sdk.dispose();
      expect(identical(disposal, sdk.dispose()), isTrue);
      await expectLater(
        disposal,
        throwsA(
          isA<SecurityFailure>().having(
            (e) => e.code,
            'code',
            SecurityErrorCode.timeout,
          ),
        ),
      );
      await expectLater(
        sdk.capabilities(),
        throwsA(
          isA<SecurityFailure>().having(
            (e) => e.code,
            'code',
            SecurityErrorCode.disposed,
          ),
        ),
      );
      expect(platform.disposals, 1);
      platform.pending.completeError(StateError('private native failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );
}
