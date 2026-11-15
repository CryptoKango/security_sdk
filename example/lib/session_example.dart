import 'package:security_flutter/security_flutter.dart';

/// A short-lived owner must await cleanup, including when scan throws.
/// Pass a custom SecurityPlatform only when the host has its own adapter.
Future<SecuritySnapshot> scanInOwnedSession(
  ScanRequest request, {
  SecurityPlatform? platform,
  Duration operationTimeout = const Duration(seconds: 5),
}) async {
  final sdk = SecuritySdk(
    operationTimeout: operationTimeout,
    platform: platform,
  );
  try {
    return await sdk.scan(request);
  } finally {
    await sdk.dispose();
  }
}

/// The caller can call token.cancel() while awaiting this future. Cancellation
/// means "stop waiting", not "native work was terminated". Detach host listeners.
Future<SecuritySnapshot> scanWithCancellation(
  SecurityScanner scanner, {
  required CancellationToken token,
  required void Function() onCancelled,
  required String contextId,
  required Iterable<String> detectorIds,
  required Duration timeout,
}) async {
  final detach = token.addListener(onCancelled);
  try {
    if (token.isCancelled) {
      throw const SecurityFailure(SecurityErrorCode.cancelled);
    }
    return await scanner.scan(
      ScanRequest(
        contextId: contextId,
        detectorIds: detectorIds,
        timeout: timeout,
        cancellation: token,
      ),
    );
  } finally {
    detach();
  }
}

/// These evaluations use the age tracked by the actual received input objects.
List<SecurityFinding> evaluateReceivedInputs({
  required TrustedTimeReference timeReference,
  required DateTime localTime,
  required LocationRiskSample locationSample,
}) => [timeReference.evaluate(localTime), locationSample.evaluate()];

/// Only a syntax check; true does not establish that a file or digest is trusted.
bool isCandidateBundlePath(String path) =>
    AppIntegrityPolicy.isValidBundlePath(path);
