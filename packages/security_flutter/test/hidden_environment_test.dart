import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/hidden_environment');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<SecurityFinding> read(String id, String status, String reason) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': 1,
        'contextId': 'test',
        'findings': [
          {
            'detectorId': id,
            'detectorVersion': 'local-v2',
            'status': status,
            'reason': reason,
          },
        ],
      },
    );
    return (await MethodChannelSecurityPlatform(channel: channel).scan(
      ScanRequest(
        contextId: 'test',
        detectorIds: [id],
        timeout: const Duration(seconds: 1),
      ),
    )).findings.single;
  }

  test(
    'new observations remain distinct closed reasons with no raw evidence',
    () async {
      for (final sample in [
        ('root', 'rootMountArtifact'),
        ('root', 'jailbreakLoadedImage'),
        ('hook', 'hookMemfd'),
        ('hook', 'injectedModulePath'),
        ('multiInstance', 'virtualContainerIdentity'),
        ('multiInstance', 'virtualContainerPath'),
        ('multiInstance', 'cloneProfile'),
      ]) {
        final finding = await read(sample.$1, 'detected', sample.$2);
        expect(finding.reason?.name, sample.$2);
        expect(finding.status, DetectionStatus.detected);
        expect(finding.detectorVersion, 'local-v2');
      }
    },
  );
  test(
    'uncorroborated identity and unsupported processes do not become clean',
    () async {
      for (final reason in [
        'processIdentityMismatch',
        'processIdentityUnavailable',
      ]) {
        expect(
          (await read('multiInstance', 'error', reason)).status,
          DetectionStatus.error,
        );
        await expectLater(
          read('multiInstance', 'notDetected', reason),
          throwsA(isA<SecurityFailure>()),
        );
      }
      expect(
        (await read(
          'multiInstance',
          'unsupported',
          'unsupportedProcess',
        )).status,
        DetectionStatus.unsupported,
      );
    },
  );
  test(
    'hidden environment reasons cannot cross detectors or claim a negative result',
    () async {
      for (final sample in [
        ('root', 'hookMemfd'),
        ('hook', 'rootMountArtifact'),
        ('multiInstance', 'injectedModulePath'),
        ('root', 'virtualContainerIdentity'),
        ('root', 'cloneProfile'),
      ]) {
        await expectLater(
          read(sample.$1, 'detected', sample.$2),
          throwsA(isA<SecurityFailure>()),
        );
      }
      await expectLater(
        read('root', 'notDetected', 'rootMountArtifact'),
        throwsA(isA<SecurityFailure>()),
      );
    },
  );
  test(
    'clone profile is an observation, never a clean or unknown reason',
    () async {
      for (final status in ['notDetected', 'unsupported', 'error']) {
        await expectLater(
          read('multiInstance', status, 'cloneProfile'),
          throwsA(isA<SecurityFailure>()),
        );
      }
    },
  );
}
