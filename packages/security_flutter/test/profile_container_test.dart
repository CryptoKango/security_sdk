import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/profile_container');
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
            'detectorVersion': 'local-v3',
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
    'ambiguous vendor or private profile remains unknown, not clean or clone',
    () async {
      final finding = await read(
        'multiInstance',
        'unsupported',
        'profileTypeUnavailable',
      );
      expect(finding.reason, FindingReason.profileTypeUnavailable);
      expect(finding.status, DetectionStatus.unsupported);
      for (final status in ['detected', 'notDetected']) {
        await expectLater(
          read('multiInstance', status, 'profileTypeUnavailable'),
          throwsA(isA<SecurityFailure>()),
        );
      }
    },
  );
  test(
    'embedded app identity is accepted only as a positive multiInstance observation',
    () async {
      final finding = await read(
        'multiInstance',
        'detected',
        'embeddedAppBundle',
      );
      expect(finding.reason, FindingReason.embeddedAppBundle);
      expect(finding.detectorVersion, 'local-v3');
      await expectLater(
        read('multiInstance', 'notDetected', 'embeddedAppBundle'),
        throwsA(isA<SecurityFailure>()),
      );
      await expectLater(
        read('hook', 'detected', 'embeddedAppBundle'),
        throwsA(isA<SecurityFailure>()),
      );
    },
  );
  test(
    'application executable type is a separate positive signal, unknown formats stay unknown',
    () async {
      expect(
        (await read(
          'multiInstance',
          'detected',
          'appExecutableIsLibrary',
        )).reason,
        FindingReason.appExecutableIsLibrary,
      );
      expect(
        (await read(
          'multiInstance',
          'unsupported',
          'executableFormatUnavailable',
        )).status,
        DetectionStatus.unsupported,
      );
      await expectLater(
        read('multiInstance', 'notDetected', 'appExecutableIsLibrary'),
        throwsA(isA<SecurityFailure>()),
      );
      await expectLater(
        read('multiInstance', 'detected', 'executableFormatUnavailable'),
        throwsA(isA<SecurityFailure>()),
      );
    },
  );
}
