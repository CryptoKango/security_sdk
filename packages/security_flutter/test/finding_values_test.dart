import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/finding_values_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<SecurityFinding> scan(
    String id,
    String status,
    String reason,
    Object? values,
  ) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': 1,
        'contextId': 'test',
        'findings': [
          {
            'detectorId': id,
            'detectorVersion': 'test',
            'status': status,
            'reason': reason,
            'values': ?values,
          },
        ],
      },
    );
    final result = await MethodChannelSecurityPlatform(channel: channel).scan(
      ScanRequest(
        contextId: 'test',
        detectorIds: [id],
        timeout: const Duration(seconds: 1),
      ),
    );
    return result.findings.single;
  }

  test(
    'channel retains actual 0, 1 and missing settings without coercing status',
    () async {
      for (final sample in [
        (1, 'detected', 'developerModeEnabled'),
        (0, 'unsupported', 'settingReadRestricted'),
        (null, 'error', 'settingValueUnavailable'),
      ]) {
        final values = {
          'settingValue': sample.$1,
          'settingPresent': sample.$1 != null,
          'settingValueValid': sample.$1 != null,
          if (sample.$1 == 1) 'signalDetected': true,
        };
        final finding = await scan(
          'developerMode',
          sample.$2,
          sample.$3,
          values,
        );
        expect(finding.values, values);
        expect(() => finding.values.clear(), throwsUnsupportedError);
      }
    },
  );
  test(
    'screenshot history survives interruption without promoting error to detected',
    () async {
      for (final seen in [false, true]) {
        final values = {'screenshotObserved': seen, 'observationActive': false};
        final finding = await scan(
          'screenshot',
          'error',
          'observationInterrupted',
          values,
        );
        expect(finding.status, DetectionStatus.error);
        expect(finding.values, values);
      }
      final active = await scan(
        'screenshot',
        'detected',
        'screenshotObserved',
        {
          'signalDetected': true,
          'screenshotObserved': true,
          'observationActive': true,
        },
      );
      expect(active.values['observationActive'], isTrue);
    },
  );
  test(
    'screenshot history rejects contradictory scope, status and detector',
    () async {
      for (final sample in <(String, String, String, Map<String, Object?>)>[
        (
          'screenshot',
          'notDetected',
          'noKnownSignal',
          {'screenshotObserved': true, 'observationActive': true},
        ),
        (
          'screenshot',
          'detected',
          'screenshotObserved',
          {'screenshotObserved': true, 'observationActive': false},
        ),
        (
          'screenshot',
          'error',
          'observationRequired',
          {'screenshotObserved': true, 'observationActive': false},
        ),
        (
          'screenshot',
          'error',
          'observationInterrupted',
          {'screenshotObserved': true, 'observationActive': true},
        ),
        (
          'screenshot',
          'error',
          'observationInterrupted',
          {'screenshotObserved': true},
        ),
        (
          'screenRecording',
          'error',
          'observationInterrupted',
          {'screenshotObserved': true, 'observationActive': false},
        ),
      ]) {
        await expectLater(
          scan(sample.$1, sample.$2, sample.$3, sample.$4),
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
  test(
    'legacy findings have empty values, never fabricated false or zero',
    () async {
      expect(
        (await scan('root', 'notDetected', 'noKnownSignal', null)).values,
        isEmpty,
      );
    },
  );
  test('readings and nullable proxy flags survive channel decoding', () async {
    for (final sample in [
      (
        'accessibility',
        'notDetected',
        'noKnownSignal',
        {'signalDetected': false, 'accessibilityEnabled': false},
      ),
      (
        'proxy',
        'notDetected',
        'noKnownSignal',
        {'httpProxyEnabled': null, 'pacProxyConfigured': false},
      ),
      (
        'vpn',
        'notDetected',
        'noActiveNetwork',
        {'activeNetworkAvailable': false},
      ),
      (
        'debugger',
        'detected',
        'debuggerAttached',
        {'signalDetected': true, 'processTraced': true},
      ),
    ]) {
      expect(
        (await scan(sample.$1, sample.$2, sample.$3, sample.$4)).values,
        sample.$4,
      );
    }
  });
  test(
    'malformed, unexpected or contradictory readings reject the response',
    () async {
      for (final sample in <(String, String, String, Object)>[
        ('root', 'notDetected', 'noKnownSignal', {'signalDetected': true}),
        ('root', 'error', 'nativeFailure', {'signalDetected': false}),
        ('root', 'notDetected', 'noKnownSignal', {'rawPath': '/private'}),
        ('root', 'notDetected', 'noKnownSignal', {'signalDetected': 0}),
        ('root', 'notDetected', 'noKnownSignal', ['unexpected']),
        (
          'developerMode',
          'detected',
          'developerModeEnabled',
          {
            'settingValue': 0,
            'settingPresent': true,
            'settingValueValid': true,
          },
        ),
        (
          'developerMode',
          'detected',
          'developerModeEnabled',
          {
            'settingValue': 1.0,
            'settingPresent': true,
            'settingValueValid': true,
          },
        ),
        (
          'developerMode',
          'detected',
          'developerModeEnabled',
          {'settingValue': 1},
        ),
        (
          'developerMode',
          'detected',
          'developerModeEnabled',
          {
            'settingValue': 1,
            'settingPresent': false,
            'settingValueValid': true,
          },
        ),
        (
          'vpn',
          'notDetected',
          'noActiveNetwork',
          {'activeNetworkAvailable': false, 'vpnTransport': false},
        ),
      ]) {
        await expectLater(
          scan(sample.$1, sample.$2, sample.$3, sample.$4),
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
}
