import Foundation
import Darwin
import MachO

/// Read-only local indicators. No sandbox-write probes, fork, ptrace or sockets.
enum RuntimeSignals {
  static var rootSupported: Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    return true
    #endif
  }
  static func scan(_ id: String, policy: Any?, debuggerMode: Any? = nil, bundle: Bundle = .main) -> LocalFinding {
    switch id {
    case "root": return root()
    case "multiInstance": return IOSContainerProbe.scan(bundle: bundle)
    case "hook": return loadedImageFinding(checkRoot: false)
    case "debugger": return ProcessTraceProbe.scan(mode: debuggerMode)
    case "appIntegrity":
      guard let raw = policy else { return .error("integrityBaselineRequired") }
      if let map = raw as? [String: Any], let files = map["iosBundleFileSha256"] as? [String: String], files.isEmpty {
        return .error("integrityBaselineRequired")
      }
      guard let policy = IOSIntegrityPolicy.parse(raw) else { return .error("integrityPolicyInvalid") }
      guard let id = bundle.bundleIdentifier else { return .error("nativeFailure") }
      guard id == policy.expectedApplicationId else { return .signal(true, "applicationIdMismatch") }
      return BundleIntegrityVerifier.verify(root: bundle.bundleURL, files: policy.files)
    default: return .unsupported("unimplemented")
    }
  }

  private static func root() -> LocalFinding {
    #if targetEnvironment(simulator)
    return .unsupported("simulatorEnvironment")
    #else
    if getuid() == 0 { return .signal(true, "rootUid") }
    var restricted = false
    for path in ["/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
      "/Library/MobileSubstrate/MobileSubstrate.dylib", "/usr/sbin/sshd", "/usr/bin/ssh",
      "/etc/apt", "/var/jb", "/private/preboot/jb"] {
      if access(path, F_OK) == 0 { return .signal(true, "jailbreakArtifact") }
      switch errno {
      case ENOENT, ENOTDIR: break
      case EACCES, EPERM: restricted = true
      default: return .error("nativeFailure")
      }
    }
    let loaded = loadedImageFinding(checkRoot: true)
    if loaded.status != "notDetected" { return loaded }
    return restricted ? .error("probeAccessRestricted") : .signal(false, "jailbreakArtifact")
    #endif
  }

  private static func loadedImageFinding(checkRoot: Bool) -> LocalFinding {
    DyldImageSnapshot.scan(checkRoot: checkRoot)
  }
}
