import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/release_debugger_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  SecuritySdk client() => SecuritySdk(
    operationTimeout: const Duration(seconds: 1),
    platform: MethodChannelSecurityPlatform(channel: channel),
  );
  test(
    'Release mode is explicit, request-scoped and only sent for debugger scans',
    () async {
      final args = <Map>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final value = call.arguments as Map;
        args.add(value);
        return {
          'schemaVersion': 1,
          'contextId': 'test',
          'findings': [
            for (final id in value['detectorIds'] as List)
              {
                'detectorId': id,
                'detectorVersion': 'local-v1',
                'status': 'unsupported',
                'reason': 'releaseDebuggerOptInRequired',
              },
          ],
        };
      });
      final sdk = client();
      Future<void> scan(List<String> ids, IosDebuggerMode mode) async {
        await sdk.scan(
          ScanRequest(
            contextId: 'test',
            detectorIds: ids,
            timeout: const Duration(seconds: 1),
            iosDebuggerMode: mode,
          ),
        );
      }

      await scan(['debugger'], IosDebuggerMode.debugBuildOnly);
      await scan(['debugger'], IosDebuggerMode.allowReleaseProcessTrace);
      await scan(['hook'], IosDebuggerMode.allowReleaseProcessTrace);
      await scan(['debugger'], IosDebuggerMode.debugBuildOnly);
      expect(args[0].containsKey('iosDebuggerMode'), isFalse);
      expect(args[1]['iosDebuggerMode'], 'allowReleaseProcessTrace');
      expect(args[2].containsKey('iosDebuggerMode'), isFalse);
      expect(args[3].containsKey('iosDebuggerMode'), isFalse);
      await sdk.dispose();
    },
  );
  test(
    'capabilities expose opt-in requirement and support legacy plugin payloads',
    () async {
      final sdk = client();
      for (final capability in [
        {'id': 'debugger', 'supported': true, 'requiresExplicitOptIn': true},
        {'id': 'debugger', 'supported': true},
      ]) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
            'schemaVersion': 1,
            'capabilities': [capability],
          },
        );
        final result = (await sdk.capabilities()).singleWhere(
          (c) => c.id == 'debugger',
        );
        expect(
          result.requiresExplicitOptIn,
          capability['requiresExplicitOptIn'] ?? false,
        );
      }
      await sdk.dispose();
    },
  );
  test(
    'malformed opt-in capability is not silently treated as false',
    () async {
      final sdk = client();
      for (final flag in <Object?>[null, 'yes', 1]) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
            'schemaVersion': 1,
            'capabilities': [
              {
                'id': 'debugger',
                'supported': true,
                'requiresExplicitOptIn': flag,
              },
            ],
          },
        );
        await expectLater(
          sdk.capabilities(),
          throwsA(
            isA<SecurityFailure>().having(
              (f) => f.code,
              'code',
              SecurityErrorCode.invalidResponse,
            ),
          ),
        );
      }
      await sdk.dispose();
    },
  );
  test(
    'process ABI failure stays error while missing opt-in stays unsupported',
    () async {
      final sdk = client();
      for (final sample in [
        ('error', 'processInfoMismatch'),
        ('error', 'debuggerPolicyInvalid'),
        ('unsupported', 'releaseDebuggerOptInRequired'),
      ]) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
            'schemaVersion': 1,
            'contextId': 'test',
            'findings': [
              {
                'detectorId': 'debugger',
                'detectorVersion': 'local-v1',
                'status': sample.$1,
                'reason': sample.$2,
              },
            ],
          },
        );
        final result = await sdk.scan(
          ScanRequest(
            contextId: 'test',
            detectorIds: ['debugger'],
            timeout: const Duration(seconds: 1),
          ),
        );
        expect(result.findings.single.status.name, sample.$1);
        expect(result.findings.single.reason?.name, sample.$2);
      }
      await sdk.dispose();
    },
  );
}
