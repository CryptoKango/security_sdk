/// Explicit test utilities. Never selected through remotely supplied settings.
library;

import 'security_core.dart';

final class FakeSecurityScanner implements SecurityScanner {
  FakeSecurityScanner({required this.onCapabilities, required this.onScan});
  final Future<List<DetectorCapability>> Function() onCapabilities;
  final Future<SecuritySnapshot> Function(ScanRequest) onScan;
  bool _disposed = false;

  void _ensureOpen() {
    if (_disposed) throw const SecurityFailure(SecurityErrorCode.disposed);
  }

  @override
  Future<List<DetectorCapability>> capabilities() async {
    _ensureOpen();
    return onCapabilities();
  }

  @override
  Future<SecuritySnapshot> scan(ScanRequest request) async {
    _ensureOpen();
    return onScan(request);
  }

  @override
  Future<void> dispose() async => _disposed = true;
}
