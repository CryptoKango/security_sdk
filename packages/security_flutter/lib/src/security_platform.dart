import 'package:security_core/security_core.dart';

/// Injectable boundary. Implementations must not initialize services implicitly.
abstract interface class SecurityPlatform {
  Future<List<DetectorCapability>> capabilities();
  Future<SecuritySnapshot> scan(ScanRequest request);
  Future<void> dispose();
}

/// Explicit screenshot observation, separate from one-shot scans. Implementations
/// own a session per SDK instance; stop/dispose must release native observers.
abstract interface class ScreenshotObservationPlatform {
  Future<void> startScreenshotObservation();
  Future<void> stopScreenshotObservation();
}

/// Used only for OS targets with no native implementation.
final class UnsupportedSecurityPlatform implements SecurityPlatform {
  const UnsupportedSecurityPlatform();
  @override
  Future<List<DetectorCapability>> capabilities() async => const [];
  @override
  Future<SecuritySnapshot> scan(ScanRequest request) async => SecuritySnapshot(
    contextId: request.contextId,
    observedAt: DateTime.now(),
    findings: request.detectorIds.map(
      (id) => SecurityFinding(
        detectorId: id,
        detectorVersion: 'unimplemented',
        status: DetectionStatus.unsupported,
      ),
    ),
  );
  @override
  Future<void> dispose() async {}
}
