import 'package:security_core/security_core.dart';
import 'package:test/test.dart';

void main() {
  test('all detector IDs are stable and unique', () {
    expect(SecurityDetectors.all.length, 16);
    expect(SecurityDetectors.all.toSet().length, 16);
  });
  test('platform-specific API level cannot contradict device platform', () {
    for (final os in DevicePlatform.values) {
      expect(
        () => DeviceInfo(
          platform: os,
          manufacturer: 'a',
          brand: 'b',
          model: 'c',
          systemVersion: '1',
          apiLevel: os == DevicePlatform.ios ? 36 : null,
        ),
        throwsA(isA<SecurityFailure>()),
      );
    }
  });
  test('device descriptions are not implicitly logged', () {
    final d = DeviceInfo(
      platform: DevicePlatform.android,
      manufacturer: 'privateBrand',
      brand: 'brand',
      model: 'privateModel',
      systemVersion: '16',
      apiLevel: 36,
    );
    expect(d.toString(), isNot(contains('private')));
  });
}
