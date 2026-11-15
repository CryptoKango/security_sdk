import 'models.dart';

abstract interface class SecurityScanner {
  Future<List<DetectorCapability>> capabilities();
  Future<SecuritySnapshot> scan(ScanRequest request);
  Future<void> dispose();
}

/// Optional monitoring contract. The initial Flutter facade does not implement it.
abstract interface class SecurityMonitor implements SecurityScanner {
  Stream<SecuritySnapshot> get signals;
  Future<void> start();
  Future<void> stop();
}

/// The initial contract supports references; proof bytes need a future adapter API.
abstract interface class EvidenceProvider {
  Future<EvidenceReference> collect(EvidenceRequest request);
  Future<void> dispose();
}
