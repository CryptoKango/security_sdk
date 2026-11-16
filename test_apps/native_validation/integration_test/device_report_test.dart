import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:security_flutter/security_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('unified device report on native platform', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text('统一设备信息接口验证')),
      ),
    );
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 1));
    final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 10));
    addTearDown(sdk.dispose);
    final result = await sdk.collectDeviceReport(
      contextId: 'native-device-report',
    );
    final info = result.device.info;
    expect(result.device.status, DeviceInfoStatus.available);
    expect(info, isNotNull);
    expect(
      info!.platform,
      defaultTargetPlatform == TargetPlatform.android
          ? DevicePlatform.android
          : DevicePlatform.ios,
    );
    expect(info.model, isNotEmpty);
    expect(info.systemVersion, isNotEmpty);
    expect(
      result.security.findings.map((f) => f.detectorId),
      SecurityDetectors.all,
    );
    expect(result.capabilities.length, 16);
    expect(
      result.security.findings
          .singleWhere((f) => f.detectorId == 'screenshot')
          .reason,
      FindingReason.observationRequired,
    );
    expect(
      result.security.findings
          .singleWhere((f) => f.detectorId == 'timeAnomaly')
          .reason,
      FindingReason.timeReferenceRequired,
    );
    expect(
      result.security.findings
          .singleWhere((f) => f.detectorId == 'mockLocation')
          .reason,
      FindingReason.locationSampleRequired,
    );
    final single = await sdk.deviceInfo();
    expect(single.info!.model, info.model);
    binding.reportData = {
      'completed': true,
      'device': {
        'platform': info.platform.name,
        'manufacturer': info.manufacturer,
        'brand': info.brand,
        'model': info.model,
        'systemVersion': info.systemVersion,
        'apiLevel': info.apiLevel,
      },
      'capabilityCount': result.capabilities.length,
      'findings': [
        for (final f in result.security.findings)
          {
            'id': f.detectorId,
            'status': f.status.name,
            'reason': f.reason?.name,
            'values': f.values,
          },
      ],
    };
    await sdk.dispose();
  }, semanticsEnabled: false);
}
