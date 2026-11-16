import 'dart:typed_data';

import 'cancellation.dart';
import 'risk_inputs.dart';
import 'integrity_policy.dart';

enum DetectionStatus { detected, notDetected, unsupported, error }

/// iOS process tracing uses the SDK-declared kinfo_proc ABI. Apple QA1361
/// recommends Debug-only use; Release support is a deliberate host opt-in.
/// This option does not attach a debugger, grant entitlements or block debugging.
enum IosDebuggerMode { debugBuildOnly, allowReleaseProcessTrace }

/// Closed, non-personal reason codes. Native messages are never forwarded.
enum FindingReason {
  noKnownSignal,
  unimplemented,
  unsupportedPlatform,
  unsupportedOsVersion,
  emulatorBuild,
  managedProfile,
  cloneProfile,
  virtualContainerPath,
  virtualContainerIdentity,
  embeddedAppBundle,
  appExecutableIsLibrary,
  executableFormatUnavailable,
  profileTypeUnavailable,
  processIdentityMismatch,
  processIdentityUnavailable,
  unsupportedProcess,
  monkey,
  testHarness,
  gestureService,
  accessibilityEnabled,
  vpnTransport,
  tunnelInterface,
  proxyConfigured,
  noActiveNetwork,
  missingPermission,
  noActivity,
  observationRequired,
  observationInterrupted,
  screenshotObserved,
  screenCaptured,
  locationConsentRequired,
  locationPermissionRequired,
  locationSampleRequired,
  locationSampleStale,
  locationSourceUnavailable,
  mockLocation,
  timeReferenceRequired,
  timeReferenceExpired,
  timeDeviation,
  nativeFailure,
  rootArtifact,
  rootMountArtifact,
  jailbreakLoadedImage,
  rootUid,
  testKeysBuild,
  jailbreakArtifact,
  hookModule,
  hookMemfd,
  injectedModulePath,
  hookClass,
  debuggerAttached,
  debuggerWaiting,
  releaseDebuggerOptInRequired,
  debuggerPolicyInvalid,
  processInfoMismatch,
  probeAccessRestricted,
  scanLimitExceeded,
  simulatorEnvironment,
  unsupportedBuildMode,
  integrityBaselineRequired,
  integrityPolicyInvalid,
  applicationIdMismatch,
  signingCertificateMismatch,
  signingInfoUnavailable,
  signingBaselineMatched,
  bundleBaselineMatched,
  integrityFileMissing,
  integrityFileMismatch,
  integrityFileInvalid,
  developerModeEnabled,
  usbDebuggingEnabled,
  settingReadRestricted,
  settingValueUnavailable,
}

enum SecurityErrorCode {
  cancelled,
  timeout,
  disposed,
  unsupported,
  invalidConfiguration,
  invalidResponse,
  platformUnavailable,
  providerUnavailable,
  internalError,
}

/// Contains no raw platform messages, identifiers or proof material.
final class SecurityFailure implements Exception {
  const SecurityFailure(this.code, {this.retryable = false});
  final SecurityErrorCode code;
  final bool retryable;
  @override
  String toString() => 'SecurityFailure(${code.name})';
}

final class DetectorCapability {
  const DetectorCapability({
    required this.id,
    required this.supported,
    this.requiresExplicitOptIn = false,
  });
  final String id;
  final bool supported;

  /// An implementation exists but a non-default request option is required.
  /// Availability is not a promise that the OS call or prerequisite will succeed.
  final bool requiresExplicitOptIn;

  Map<String, Object?> toJson() => {
    'id': id,
    'supported': supported,
    'requiresExplicitOptIn': requiresExplicitOptIn,
  };
}

final class SecurityFinding {
  const SecurityFinding({
    required this.detectorId,
    required this.detectorVersion,
    required this.status,
    this.reason,
  }) : values = const {};

  /// Numeric/boolean readings only. No paths, addresses, identifiers or raw errors.
  SecurityFinding.withValues({
    required this.detectorId,
    required this.detectorVersion,
    required this.status,
    this.reason,
    required Map<String, Object?> values,
  }) : values = _copyFindingValues(values);

  final Map<String, Object?> values;
  final String detectorId;
  final String detectorVersion;
  final DetectionStatus status;
  final FindingReason? reason;

  Map<String, Object?> toJson() => {
    'detectorId': detectorId,
    'detectorVersion': detectorVersion,
    'status': status.name,
    'reason': reason?.name,
    'values': Map<String, Object?>.of(values),
  };
}

Map<String, Object?> _copyFindingValues(Map<String, Object?> values) {
  if (values.length > 16 ||
      values.entries.any(
        (entry) =>
            !RegExp(r'^[a-zA-Z][a-zA-Z0-9]{0,63}$').hasMatch(entry.key) ||
            !(entry.value == null ||
                entry.value is bool ||
                (entry.value is num && (entry.value as num).isFinite)),
      )) {
    throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
  }
  return Map<String, Object?>.unmodifiable(values);
}

/// A local observation, not an authorization decision or proof of safety.
final class SecuritySnapshot {
  SecuritySnapshot({
    required this.contextId,
    required DateTime observedAt,
    required Iterable<SecurityFinding> findings,
  }) : observedAt = observedAt.toUtc(),
       findings = List.unmodifiable(findings);

  final String contextId;
  final DateTime observedAt;
  final List<SecurityFinding> findings;

  /// UTC ISO-8601 timestamp, preserving available subsecond precision.
  Map<String, Object?> toJson() => {
    'contextId': contextId,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'findings': [for (final finding in findings) finding.toJson()],
  };

  @override
  String toString() => 'SecuritySnapshot(findings: ${findings.length})';
}

final class ScanRequest {
  ScanRequest({
    required this.contextId,
    required Iterable<String> detectorIds,
    required this.timeout,
    this.cancellation,
    this.timeReference,
    this.locationSample,
    this.integrityPolicy,
    this.iosDebuggerMode = IosDebuggerMode.debugBuildOnly,
  }) : detectorIds = List.unmodifiable(detectorIds) {
    if (contextId.isEmpty ||
        timeout <= Duration.zero ||
        this.detectorIds.isEmpty ||
        this.detectorIds.any((id) => id.isEmpty) ||
        this.detectorIds.toSet().length != this.detectorIds.length) {
      throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
    }
  }

  /// Opaque, non-personal correlation value provided by the host.
  final String contextId;
  final List<String> detectorIds;
  final TrustedTimeReference? timeReference;
  final LocationRiskSample? locationSample;
  final AppIntegrityPolicy? integrityPolicy;
  final IosDebuggerMode iosDebuggerMode;
  final Duration timeout;
  final CancellationToken? cancellation;
  @override
  String toString() => 'ScanRequest(detectors: ${detectorIds.length})';
}

/// Provider-neutral binding bytes. Not automatically logged or serialized.
final class EvidenceRequest {
  EvidenceRequest({
    required this.contextId,
    required List<int> binding,
    required this.timeout,
    this.cancellation,
  }) : _binding = Uint8List.fromList(binding) {
    if (contextId.isEmpty ||
        timeout <= Duration.zero ||
        binding.isEmpty ||
        binding.any((byte) => byte < 0 || byte > 255)) {
      throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
    }
  }
  final String contextId;
  final Uint8List _binding;
  Uint8List get binding => Uint8List.fromList(_binding);
  final Duration timeout;
  final CancellationToken? cancellation;
  @override
  String toString() => 'EvidenceRequest(redacted)';
}

/// Only the host decides whether/how to send a reference to its backend.
final class EvidenceReference {
  const EvidenceReference({required this.provider, required this.reference});
  final String provider;
  final String reference;
  @override
  String toString() => 'EvidenceReference(redacted)';
}
