import 'package:security_core/security_core.dart';

void main() {
  final request = ScanRequest(
    contextId: 'example-operation',
    detectorIds: ['root'],
    timeout: const Duration(seconds: 5),
  );
  // Contains no provider/network dependency or device identity.
  print(request);
}
