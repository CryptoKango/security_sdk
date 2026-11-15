import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

// Host prepares only an explicit test emulator. This test never changes settings.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const expected = String.fromEnvironment('EXPECTED_DEVELOPER_SETTING');
  testWidgets('explicit developer-setting observation', (tester) async {
    final report = <String, Object?>{'completed': false, 'expected': expected};
    binding.reportData = report;
    await tester.pumpWidget(const SizedBox.shrink());
    final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
    addTearDown(sdk.dispose);
    const ids = [
      SecurityDetectors.developerMode,
      SecurityDetectors.usbDebugging,
    ];
    final capabilities = await sdk.capabilities();
    final snapshot = await sdk.scan(
      ScanRequest(
        contextId: 'developer-setting-fixture',
        detectorIds: ids,
        timeout: const Duration(seconds: 5),
      ),
    );
    report['findings'] = [
      for (final f in snapshot.findings)
        {
          'id': f.detectorId,
          'status': f.status.name,
          'reason': f.reason?.name,
          'version': f.detectorVersion,
          'values': f.values,
        },
    ];
    expect(snapshot.findings.map((f) => f.detectorId), ids);
    expect(
      snapshot.findings.map((f) => f.detectorVersion),
      everyElement('local-v1'),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      expect(expected, isIn(['enabled', 'restricted', 'missing']));
      for (final id in ids) {
        expect(capabilities.singleWhere((c) => c.id == id).supported, isTrue);
      }
      final finding = snapshot.findings.first;
      expect(finding.status, switch (expected) {
        'enabled' => DetectionStatus.detected,
        'restricted' => DetectionStatus.unsupported,
        _ => DetectionStatus.error,
      });
      expect(finding.reason, switch (expected) {
        'enabled' => FindingReason.developerModeEnabled,
        'restricted' => FindingReason.settingReadRestricted,
        _ => FindingReason.settingValueUnavailable,
      });
      expect(finding.values['settingValue'], switch (expected) {
        'enabled' => 1,
        'restricted' => 0,
        _ => null,
      });
      expect(finding.values['settingPresent'], expected != 'missing');
      expect(finding.values['settingValueValid'], expected != 'missing');
      expect(snapshot.findings.last.status, isNot(DetectionStatus.notDetected));
    } else {
      expect(defaultTargetPlatform, TargetPlatform.iOS);
      for (final id in ids) {
        expect(capabilities.singleWhere((c) => c.id == id).supported, isFalse);
      }
      expect(
        snapshot.findings.map((f) => f.reason),
        everyElement(FindingReason.unsupportedPlatform),
      );
    }
    final measured = await sdk.scan(
      ScanRequest(
        contextId: 'measured-values-fixture',
        detectorIds: const ['accessibility', 'proxy', 'emulator', 'vpn'],
        timeout: const Duration(seconds: 5),
      ),
    );
    report['measuredFindings'] = [
      for (final f in measured.findings)
        {
          'id': f.detectorId,
          'status': f.status.name,
          'reason': f.reason?.name,
          'values': f.values,
        },
    ];
    final accessibility = measured.findings.singleWhere(
      (f) => f.detectorId == 'accessibility',
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      expect(accessibility.values['accessibilityEnabled'], isA<bool>());
    } else {
      expect(accessibility.values['voiceOverEnabled'], isA<bool>());
      expect(accessibility.values['switchControlEnabled'], isA<bool>());
    }
    final proxy = measured.findings.singleWhere((f) => f.detectorId == 'proxy');
    expect(proxy.values, contains('pacProxyConfigured'));
    for (final finding in measured.findings) {
      if (finding.values.containsKey('signalDetected')) {
        expect(
          finding.values['signalDetected'],
          finding.status == DetectionStatus.detected,
        );
      }
    }
    await sdk.dispose();
    report['completed'] = true;
  }, semanticsEnabled: false);
}
