import 'package:security_core/security_core.dart';
import 'package:test/test.dart';

void main() {
  SecurityFinding make(Map<String, Object?> values) =>
      SecurityFinding.withValues(
        detectorId: 'test',
        detectorVersion: 'test',
        status: DetectionStatus.error,
        values: values,
      );
  test('readings are copied, immutable, and optional for existing callers', () {
    final values = <String, Object?>{
      'settingValue': 0,
      'known': false,
      'missing': null,
    };
    final finding = make(values);
    values['settingValue'] = 1;
    expect(finding.values['settingValue'], 0);
    expect(() => finding.values.clear(), throwsUnsupportedError);
    expect(
      const SecurityFinding(
        detectorId: 'test',
        detectorVersion: 'test',
        status: DetectionStatus.error,
      ).values,
      isEmpty,
    );
  });
  test('readings reject unbounded, personal-text and nonfinite payloads', () {
    for (final values in <Map<String, Object?>>[
      {'raw': 'private'},
      {'value': double.nan},
      {'value': double.infinity},
      {'nested': <String, Object?>{}},
      {'/private/path': true},
      {for (var i = 0; i < 17; i++) 'v$i': i},
    ]) {
      expect(
        () => make(values),
        throwsA(
          isA<SecurityFailure>().having(
            (e) => e.code,
            'code',
            SecurityErrorCode.invalidConfiguration,
          ),
        ),
      );
    }
  });
  test('time readings match the exact monotonic-adjusted comparison', () {
    final anchor = DateTime.utc(2026);
    final finding = assessTimeAnomaly(
      localTime: anchor.add(const Duration(seconds: 5)),
      serverTimeAtReceipt: anchor,
      elapsed: const Duration(seconds: 2),
      validFor: const Duration(seconds: 10),
      allowedSkew: const Duration(seconds: 3),
    );
    expect(finding.status, DetectionStatus.notDetected);
    expect(finding.values, {
      'deviationUs': 3000000,
      'allowedSkewUs': 3000000,
      'referenceAgeUs': 2000000,
      'referenceValidForUs': 10000000,
    });
    final expired = assessTimeAnomaly(
      localTime: anchor,
      serverTimeAtReceipt: anchor,
      elapsed: const Duration(seconds: 11),
      validFor: const Duration(seconds: 10),
      allowedSkew: Duration.zero,
    );
    expect(expired.reason, FindingReason.timeReferenceExpired);
    expect(expired.values.containsKey('deviationUs'), isFalse);
  });
  test(
    'location values respect consent and preserve unknown source metadata',
    () {
      SecurityFinding assess(bool consent, bool permission, bool? mocked) =>
          assessLocationRisk(
            businessUseAuthorized: consent,
            permissionGranted: permission,
            isMocked: mocked,
            age: const Duration(milliseconds: 1),
            maxAge: const Duration(seconds: 1),
          );
      expect(assess(false, true, true).values, {
        'businessUseAuthorized': false,
      });
      expect(assess(true, false, true).values, {
        'businessUseAuthorized': true,
        'permissionGranted': false,
      });
      final unknown = assess(true, true, null);
      expect(unknown.status, DetectionStatus.unsupported);
      expect(unknown.values['isMocked'], isNull);
      expect(unknown.values['sampleAgeUs'], 1000);
      expect(assess(true, true, false).values['isMocked'], false);
      expect(assess(true, true, true).values['isMocked'], true);
    },
  );
}
