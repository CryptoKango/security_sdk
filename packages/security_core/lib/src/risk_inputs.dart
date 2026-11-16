import 'models.dart';

/// Stable IDs. Detection is an observation, never an authorization verdict.
abstract final class SecurityDetectors {
  static const root = 'root';
  static const hook = 'hook';
  static const debugger = 'debugger';
  static const appIntegrity = 'appIntegrity';
  static const runtime = [root, hook, debugger, appIntegrity];
  static const emulator = 'emulator';
  static const multiInstance = 'multiInstance';
  static const automation = 'automation';

  /// Positive public setting only; a redacted zero is not proof of disabled mode.
  static const developerMode = 'developerMode';

  /// USB debugging setting, not a connected debugger or wireless debugging.
  static const usbDebugging = 'usbDebugging';
  static const accessibility = 'accessibility';
  static const vpn = 'vpn';
  static const proxy = 'proxy';
  static const timeAnomaly = 'timeAnomaly';
  static const screenshot = 'screenshot';
  static const screenRecording = 'screenRecording';
  static const mockLocation = 'mockLocation';
  static const all = [
    ...runtime,
    ...environment,
    screenshot,
    timeAnomaly,
    mockLocation,
  ];
  static const environment = [
    emulator,
    multiInstance,
    automation,
    developerMode,
    usbDebugging,
    accessibility,
    vpn,
    proxy,
    screenRecording,
  ];
}

/// A host-authenticated server time adjusted to its receipt instant. The host
/// accounts for network uncertainty in [allowedSkew]. No request is made here.
/// The monotonic lifetime starts at construction; do not persist/recreate an old
/// anchor as a new one. Device wall-clock changes cannot extend its lifetime.
final class TrustedTimeReference {
  TrustedTimeReference({
    required DateTime serverTimeAtReceipt,
    required this.allowedSkew,
    required this.validFor,
  }) : serverTimeAtReceipt = serverTimeAtReceipt.toUtc() {
    if (allowedSkew < Duration.zero || validFor <= Duration.zero) {
      throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
    }
  }
  final DateTime serverTimeAtReceipt;
  final Duration allowedSkew;
  final Duration validFor;
  final Stopwatch _age = Stopwatch()..start();
  SecurityFinding evaluate(DateTime localTime) => assessTimeAnomaly(
    localTime: localTime,
    serverTimeAtReceipt: serverTimeAtReceipt,
    elapsed: _age.elapsed,
    validFor: validFor,
    allowedSkew: allowedSkew,
  );
  @override
  String toString() => 'TrustedTimeReference(redacted)';
}

/// Only source metadata from an existing, authorized business location flow.
/// No latitude/longitude, identifiers or permission request is accepted here.
/// [ageAtReceipt] must include the source fix's age, not merely channel latency.
final class LocationRiskSample {
  LocationRiskSample({
    required this.businessUseAuthorized,
    required this.permissionGranted,
    required this.isMocked,
    required this.ageAtReceipt,
    required this.maxAge,
  }) {
    if (ageAtReceipt < Duration.zero || maxAge <= Duration.zero) {
      throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
    }
  }
  final bool businessUseAuthorized;
  final bool permissionGranted;

  /// Null means the source API did not provide a simulation indicator.
  final bool? isMocked;
  final Duration ageAtReceipt;
  final Duration maxAge;
  final Stopwatch _age = Stopwatch()..start();
  SecurityFinding evaluate() => assessLocationRisk(
    businessUseAuthorized: businessUseAuthorized,
    permissionGranted: permissionGranted,
    isMocked: isMocked,
    age: ageAtReceipt + _age.elapsed,
    maxAge: maxAge,
  );
  @override
  String toString() => 'LocationRiskSample(redacted)';
}

/// Deterministic policy-free signal evaluation; useful for cross-platform hosts.
SecurityFinding assessTimeAnomaly({
  required DateTime localTime,
  required DateTime serverTimeAtReceipt,
  required Duration elapsed,
  required Duration validFor,
  required Duration allowedSkew,
}) {
  if (elapsed < Duration.zero ||
      validFor <= Duration.zero ||
      allowedSkew < Duration.zero) {
    throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
  }
  if (elapsed > validFor) {
    return _finding(
      SecurityDetectors.timeAnomaly,
      DetectionStatus.error,
      FindingReason.timeReferenceExpired,
      values: {
        'referenceAgeUs': elapsed.inMicroseconds,
        'referenceValidForUs': validFor.inMicroseconds,
      },
    );
  }
  final deviation = localTime
      .difference(serverTimeAtReceipt.add(elapsed))
      .abs();
  return _finding(
    SecurityDetectors.timeAnomaly,
    deviation > allowedSkew
        ? DetectionStatus.detected
        : DetectionStatus.notDetected,
    deviation > allowedSkew
        ? FindingReason.timeDeviation
        : FindingReason.noKnownSignal,
    values: {
      'deviationUs': deviation.inMicroseconds,
      'allowedSkewUs': allowedSkew.inMicroseconds,
      'referenceAgeUs': elapsed.inMicroseconds,
      'referenceValidForUs': validFor.inMicroseconds,
    },
  );
}

SecurityFinding assessLocationRisk({
  required bool businessUseAuthorized,
  required bool permissionGranted,
  required bool? isMocked,
  required Duration age,
  required Duration maxAge,
}) {
  if (age < Duration.zero || maxAge <= Duration.zero) {
    throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
  }
  if (!businessUseAuthorized) {
    return _finding(
      SecurityDetectors.mockLocation,
      DetectionStatus.error,
      FindingReason.locationConsentRequired,
      values: {'businessUseAuthorized': false},
    );
  }
  if (!permissionGranted) {
    return _finding(
      SecurityDetectors.mockLocation,
      DetectionStatus.error,
      FindingReason.locationPermissionRequired,
      values: {'businessUseAuthorized': true, 'permissionGranted': false},
    );
  }
  final values = <String, Object?>{
    'businessUseAuthorized': true,
    'permissionGranted': true,
    'isMocked': isMocked,
    'sampleAgeUs': age.inMicroseconds,
    'sampleMaxAgeUs': maxAge.inMicroseconds,
  };
  if (age > maxAge) {
    return _finding(
      SecurityDetectors.mockLocation,
      DetectionStatus.error,
      FindingReason.locationSampleStale,
      values: values,
    );
  }
  if (isMocked == null) {
    return _finding(
      SecurityDetectors.mockLocation,
      DetectionStatus.unsupported,
      FindingReason.locationSourceUnavailable,
      values: values,
    );
  }
  return _finding(
    SecurityDetectors.mockLocation,
    isMocked ? DetectionStatus.detected : DetectionStatus.notDetected,
    isMocked ? FindingReason.mockLocation : FindingReason.noKnownSignal,
    values: values,
  );
}

SecurityFinding _finding(
  String id,
  DetectionStatus status,
  FindingReason reason, {
  Map<String, Object?> values = const {},
}) => SecurityFinding.withValues(
  detectorId: id,
  detectorVersion: 'local-v1',
  status: status,
  reason: reason,
  values: values,
);
