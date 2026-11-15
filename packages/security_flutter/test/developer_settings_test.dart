import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/developer_settings_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const ids = [SecurityDetectors.developerMode, SecurityDetectors.usbDebugging];
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<SecuritySnapshot> scan(List<String> requested) =>
      MethodChannelSecurityPlatform(channel: channel).scan(
        ScanRequest(
          contextId: 'test',
          detectorIds: requested,
          timeout: const Duration(seconds: 1),
        ),
      );
  void reply(String status, String reason) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      return {
        'schemaVersion': 1,
        'contextId': 'test',
        'findings': [
          for (final id in args['detectorIds'] as List)
            {
              'detectorId': id,
              'detectorVersion': 'local-v1',
              'status': status,
              'reason': reason,
            },
        ],
      };
    });
  }

  test('independent developer signals are forwarded and mapped', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      expect(args['detectorIds'], ids);
      return {
        'schemaVersion': 1,
        'contextId': 'test',
        'findings': [
          {
            'detectorId': ids[0],
            'detectorVersion': 'local-v1',
            'status': 'detected',
            'reason': 'developerModeEnabled',
          },
          {
            'detectorId': ids[1],
            'detectorVersion': 'local-v1',
            'status': 'detected',
            'reason': 'usbDebuggingEnabled',
          },
        ],
      };
    });
    final findings = (await scan(ids)).findings;
    expect(findings.map((f) => f.reason), [
      FindingReason.developerModeEnabled,
      FindingReason.usbDebuggingEnabled,
    ]);
  });

  test('redacted zero and unsupported platforms stay unknown', () async {
    for (final reason in ['settingReadRestricted', 'unsupportedPlatform']) {
      reply('unsupported', reason);
      expect(
        (await scan(ids)).findings.map((f) => f.status),
        everyElement(DetectionStatus.unsupported),
      );
    }
  });

  test(
    'missing or malformed settings and read failures remain errors',
    () async {
      for (final reason in [
        'settingValueUnavailable',
        'missingPermission',
        'nativeFailure',
      ]) {
        reply('error', reason);
        expect(
          (await scan(ids)).findings.map((f) => f.status),
          everyElement(DetectionStatus.error),
        );
      }
    },
  );

  test(
    'developer settings cannot be promoted to clean or confused with debugger',
    () async {
      for (final sample in [
        ('developerMode', 'notDetected', 'noKnownSignal'),
        ('usbDebugging', 'notDetected', 'noKnownSignal'),
        ('developerMode', 'detected', 'debuggerAttached'),
        ('developerMode', 'detected', 'usbDebuggingEnabled'),
        ('usbDebugging', 'detected', 'developerModeEnabled'),
        ('debugger', 'detected', 'developerModeEnabled'),
        ('developerMode', 'detected', 'settingReadRestricted'),
      ]) {
        reply(sample.$2, sample.$3);
        await expectLater(
          scan([sample.$1]),
          throwsA(
            isA<SecurityFailure>().having(
              (e) => e.code,
              'code',
              SecurityErrorCode.invalidResponse,
            ),
          ),
        );
      }
    },
  );

  test('capabilities retain explicit unsupported status on iOS', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': 1,
        'capabilities': [
          for (final id in ids) {'id': id, 'supported': false},
        ],
      },
    );
    final caps = await MethodChannelSecurityPlatform(
      channel: channel,
    ).capabilities();
    expect(caps.map((c) => c.id), ids);
    expect(caps.map((c) => c.supported), everyElement(isFalse));
  });
}
