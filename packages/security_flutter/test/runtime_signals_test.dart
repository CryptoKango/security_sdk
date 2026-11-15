import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/runtime_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final policy = AppIntegrityPolicy(
    expectedApplicationId: 'example.app',
    androidSignerSha256Sets: [
      ['a' * 64],
    ],
  );
  SecuritySdk client() => SecuritySdk(
    operationTimeout: const Duration(seconds: 2),
    platform: MethodChannelSecurityPlatform(channel: channel),
  );
  test(
    'SDK forwards immutable integrity baseline only for requested integrity check',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map;
        final ids = args['detectorIds'] as List;
        if (ids.contains('appIntegrity')) {
          expect(args['integrityPolicy'], {
            'expectedApplicationId': 'example.app',
            'androidSignerSha256Sets': [
              ['a' * 64],
            ],
            'iosBundleFileSha256': <String, String>{},
          });
        } else {
          expect(args.containsKey('integrityPolicy'), isFalse);
        }
        return {
          'schemaVersion': 1,
          'contextId': 'test',
          'findings': [
            for (final id in ids)
              {
                'detectorId': id,
                'detectorVersion': 'local-v1',
                'status': 'error',
                'reason': 'integrityBaselineRequired',
              },
          ],
        };
      });
      final sdk = client();
      for (final ids in [
        ['appIntegrity'],
        ['hook'],
      ]) {
        await sdk.scan(
          ScanRequest(
            contextId: 'test',
            detectorIds: ids,
            integrityPolicy: policy,
            timeout: const Duration(seconds: 2),
          ),
        );
      }
      await sdk.dispose();
    },
  );
  test(
    'integrity mismatch, missing baseline and unsupported release stay distinct',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'schemaVersion': 1,
          'contextId': 'test',
          'findings': [
            {
              'detectorId': 'appIntegrity',
              'detectorVersion': 'local-v1',
              'status': 'detected',
              'reason': 'signingCertificateMismatch',
            },
            {
              'detectorId': 'debugger',
              'detectorVersion': 'local-v1',
              'status': 'unsupported',
              'reason': 'unsupportedBuildMode',
            },
            {
              'detectorId': 'root',
              'detectorVersion': 'local-v1',
              'status': 'error',
              'reason': 'probeAccessRestricted',
            },
            {
              'detectorId': 'hook',
              'detectorVersion': 'local-v1',
              'status': 'detected',
              'reason': 'hookModule',
            },
          ],
        },
      );
      final sdk = client();
      final result = await sdk.scan(
        ScanRequest(
          contextId: 'test',
          detectorIds: ['appIntegrity', 'debugger', 'root', 'hook'],
          timeout: const Duration(seconds: 2),
        ),
      );
      expect(result.findings.map((f) => f.status), [
        DetectionStatus.detected,
        DetectionStatus.unsupported,
        DetectionStatus.error,
        DetectionStatus.detected,
      ]);
      expect(
        result.findings.first.reason,
        FindingReason.signingCertificateMismatch,
      );
      await sdk.dispose();
    },
  );
  test(
    'default scan does not synthesize a trusted integrity baseline',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect((call.arguments as Map).containsKey('integrityPolicy'), isFalse);
        return {
          'schemaVersion': 1,
          'contextId': 'test',
          'findings': [
            {
              'detectorId': 'appIntegrity',
              'detectorVersion': 'local-v1',
              'status': 'error',
              'reason': 'integrityBaselineRequired',
            },
          ],
        };
      });
      final sdk = client();
      final result = await sdk.scan(
        ScanRequest(
          contextId: 'test',
          detectorIds: ['appIntegrity'],
          timeout: const Duration(seconds: 2),
        ),
      );
      expect(result.findings.single.status, DetectionStatus.error);
      expect(
        result.findings.single.reason,
        FindingReason.integrityBaselineRequired,
      );
      await sdk.dispose();
    },
  );
}
