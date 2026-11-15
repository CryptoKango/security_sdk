import 'package:security_core/security_core.dart';
import 'package:test/test.dart';

void main() {
  final time = DateTime.utc(2026);
  SecurityFinding clock(int delta, {int elapsed = 5, int valid = 10}) =>
      assessTimeAnomaly(
        localTime: time.add(Duration(seconds: elapsed + delta)),
        serverTimeAtReceipt: time,
        elapsed: Duration(seconds: elapsed),
        validFor: Duration(seconds: valid),
        allowedSkew: const Duration(seconds: 2),
      );
  test(
    'clock deviation is symmetric, includes boundary and advances reference',
    () {
      expect(clock(2).status, DetectionStatus.notDetected);
      expect(clock(-2).status, DetectionStatus.notDetected);
      expect(clock(3).reason, FindingReason.timeDeviation);
      expect(clock(-3).status, DetectionStatus.detected);
      expect(clock(0, elapsed: 11).reason, FindingReason.timeReferenceExpired);
      expect(clock(0, elapsed: 10).status, DetectionStatus.notDetected);
    },
  );
  test('invalid clock inputs fail instead of yielding a clean signal', () {
    expect(() => clock(0, elapsed: -1), throwsA(isA<SecurityFailure>()));
    expect(
      () => TrustedTimeReference(
        serverTimeAtReceipt: time,
        allowedSkew: const Duration(seconds: -1),
        validFor: const Duration(seconds: 1),
      ),
      throwsA(isA<SecurityFailure>()),
    );
  });
  SecurityFinding location({
    bool authorized = true,
    bool permitted = true,
    bool? mock = true,
    int age = 1,
  }) => assessLocationRisk(
    businessUseAuthorized: authorized,
    permissionGranted: permitted,
    isMocked: mock,
    age: Duration(seconds: age),
    maxAge: const Duration(seconds: 5),
  );
  test(
    'location consent and permission are prerequisites even for positive metadata',
    () {
      expect(
        location(authorized: false).reason,
        FindingReason.locationConsentRequired,
      );
      expect(
        location(permitted: false).reason,
        FindingReason.locationPermissionRequired,
      );
      expect(location(authorized: false).status, DetectionStatus.error);
    },
  );
  test(
    'location metadata distinguishes absent, stale, negative and positive',
    () {
      expect(location(mock: null).status, DetectionStatus.unsupported);
      expect(location(mock: false).status, DetectionStatus.notDetected);
      expect(location(age: 5).status, DetectionStatus.detected);
      expect(location(age: 6).reason, FindingReason.locationSampleStale);
      expect(() => location(age: -1), throwsA(isA<SecurityFailure>()));
    },
  );
  test('samples include original fix age and redact details', () {
    final sample = LocationRiskSample(
      businessUseAuthorized: true,
      permissionGranted: true,
      isMocked: false,
      ageAtReceipt: const Duration(minutes: 1),
      maxAge: const Duration(seconds: 5),
    );
    expect(sample.evaluate().reason, FindingReason.locationSampleStale);
    expect(sample.toString(), 'LocationRiskSample(redacted)');
  });
  test('reference expires with monotonic elapsed time', () async {
    final reference = TrustedTimeReference(
      serverTimeAtReceipt: time,
      allowedSkew: const Duration(seconds: 2),
      validFor: const Duration(milliseconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reference.evaluate(time).reason, FindingReason.timeReferenceExpired);
    expect(reference.toString(), 'TrustedTimeReference(redacted)');
  });
}
