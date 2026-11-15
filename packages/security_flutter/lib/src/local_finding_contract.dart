import 'package:security_core/security_core.dart';

/// Validate built-in native observations, not third-party provider contracts.
/// Successful observations must agree with both their detector and reason.
bool validLocalFinding(
  String id,
  DetectionStatus status,
  FindingReason? reason,
) {
  if (reason == null) {
    // Preserve legacy unknown results, but never accept an unexplained verdict.
    return status == DetectionStatus.error ||
        status == DetectionStatus.unsupported;
  }
  return switch (status) {
    DetectionStatus.detected => _positiveReasons[id]?.contains(reason) ?? false,
    DetectionStatus.notDetected =>
      id == SecurityDetectors.appIntegrity
          ? const {
              FindingReason.signingBaselineMatched,
              FindingReason.bundleBaselineMatched,
            }.contains(reason)
          : id != SecurityDetectors.developerMode &&
                id != SecurityDetectors.usbDebugging &&
                _positiveReasons.containsKey(id) &&
                (reason == FindingReason.noKnownSignal ||
                    (id == SecurityDetectors.vpn &&
                        reason == FindingReason.noActiveNetwork)),
    DetectionStatus.unsupported => const {
      FindingReason.unimplemented,
      FindingReason.unsupportedPlatform,
      FindingReason.unsupportedProcess,
      FindingReason.profileTypeUnavailable,
      FindingReason.executableFormatUnavailable,
      FindingReason.unsupportedOsVersion,
      FindingReason.simulatorEnvironment,
      FindingReason.unsupportedBuildMode,
      FindingReason.releaseDebuggerOptInRequired,
      FindingReason.settingReadRestricted,
    }.contains(reason),
    DetectionStatus.error => const {
      FindingReason.missingPermission,
      FindingReason.noActivity,
      FindingReason.observationRequired,
      FindingReason.observationInterrupted,
      FindingReason.nativeFailure,
      FindingReason.settingValueUnavailable,
      FindingReason.processIdentityMismatch,
      FindingReason.processIdentityUnavailable,
      FindingReason.debuggerPolicyInvalid,
      FindingReason.processInfoMismatch,
      FindingReason.probeAccessRestricted,
      FindingReason.scanLimitExceeded,
      FindingReason.integrityBaselineRequired,
      FindingReason.integrityPolicyInvalid,
      FindingReason.signingInfoUnavailable,
    }.contains(reason),
  };
}

const _positiveReasons = <String, Set<FindingReason>>{
  SecurityDetectors.root: {
    FindingReason.rootArtifact,
    FindingReason.rootMountArtifact,
    FindingReason.jailbreakLoadedImage,
    FindingReason.rootUid,
    FindingReason.testKeysBuild,
    FindingReason.jailbreakArtifact,
  },
  SecurityDetectors.hook: {
    FindingReason.hookModule,
    FindingReason.hookClass,
    FindingReason.hookMemfd,
    FindingReason.injectedModulePath,
  },
  SecurityDetectors.debugger: {
    FindingReason.debuggerAttached,
    FindingReason.debuggerWaiting,
  },
  SecurityDetectors.appIntegrity: {
    FindingReason.applicationIdMismatch,
    FindingReason.signingCertificateMismatch,
    FindingReason.integrityFileMissing,
    FindingReason.integrityFileMismatch,
    FindingReason.integrityFileInvalid,
  },
  SecurityDetectors.emulator: {FindingReason.emulatorBuild},
  SecurityDetectors.multiInstance: {
    FindingReason.managedProfile,
    FindingReason.cloneProfile,
    FindingReason.virtualContainerPath,
    FindingReason.virtualContainerIdentity,
    FindingReason.embeddedAppBundle,
    FindingReason.appExecutableIsLibrary,
  },
  SecurityDetectors.developerMode: {FindingReason.developerModeEnabled},
  SecurityDetectors.usbDebugging: {FindingReason.usbDebuggingEnabled},
  SecurityDetectors.automation: {
    FindingReason.monkey,
    FindingReason.testHarness,
    FindingReason.gestureService,
  },
  SecurityDetectors.accessibility: {FindingReason.accessibilityEnabled},
  SecurityDetectors.vpn: {
    FindingReason.vpnTransport,
    FindingReason.tunnelInterface,
  },
  SecurityDetectors.proxy: {FindingReason.proxyConfigured},
  SecurityDetectors.screenshot: {FindingReason.screenshotObserved},
  SecurityDetectors.screenRecording: {FindingReason.screenCaptured},
};
