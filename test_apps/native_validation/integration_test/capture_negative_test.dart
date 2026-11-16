import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/lifecycle_test');
  testWidgets(
    'real focus interruption cannot invent screenshots or cross owners',
    (tester) async {
      final report = <String, Object?>{'completed': false};
      binding.reportData = report;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('截图误报负对照：自动运行中\n本轮请不要截图。'))),
        ),
      );
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(seconds: 2));
      final first = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      final second = SecuritySdk(operationTimeout: const Duration(seconds: 5));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Future<SecurityFinding> scan(SecuritySdk sdk, String name) async {
        final result = await sdk.scan(
          ScanRequest(
            contextId: name,
            detectorIds: const ['screenshot'],
            timeout: const Duration(seconds: 5),
          ),
        );
        final finding = result.findings.single;
        report[name] = {
          'status': finding.status.name,
          'reason': finding.reason?.name,
          'values': finding.values,
        };
        return finding;
      }

      void expectActive(SecurityFinding finding) {
        expect(finding.status, DetectionStatus.notDetected);
        expect(finding.values, {
          'signalDetected': false,
          'screenshotObserved': false,
          'observationActive': true,
        });
      }

      void expectInterrupted(SecurityFinding finding) {
        expect(finding.status, DetectionStatus.error);
        expect(finding.reason, FindingReason.observationInterrupted);
        expect(finding.values, {
          'screenshotObserved': false,
          'observationActive': false,
        });
      }

      await first.startScreenshotObservation();
      await second.startScreenshotObservation();
      expectActive(await scan(first, 'firstBefore'));
      expectActive(await scan(second, 'secondBefore'));
      await channel.invokeMethod<void>('interruptCapture');
      expectInterrupted(await scan(first, 'firstInterrupted'));
      expectInterrupted(await scan(second, 'secondInterrupted'));
      await first.startScreenshotObservation();
      expectActive(await scan(first, 'firstRestarted'));
      expectInterrupted(await scan(second, 'secondStillInterrupted'));
      await first.dispose();
      expectInterrupted(await scan(second, 'secondAfterFirstDisposed'));
      await second.startScreenshotObservation();
      expectActive(await scan(second, 'secondRestarted'));
      await second.stopScreenshotObservation();
      final stopped = await scan(second, 'secondStopped');
      expect(stopped.reason, FindingReason.observationRequired);
      expect(stopped.values, isEmpty);
      await second.dispose();
      report['completed'] = true;
    },
    semanticsEnabled: false,
  );
}
