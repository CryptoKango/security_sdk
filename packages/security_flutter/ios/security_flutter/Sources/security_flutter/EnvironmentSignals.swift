import UIKit
import CFNetwork
import Darwin


enum EnvironmentSignals {
  static func scan(_ id: String) -> LocalFinding {
    switch id {
    case "emulator":
      #if targetEnvironment(simulator)
      return .signal(true, "emulatorBuild")
      #else
      return .signal(false, "emulatorBuild")
      #endif
    // No public app-level Developer Mode / USB-debugging query on iOS.
    case "automation", "developerMode", "usbDebugging":
      return .unsupported("unsupportedPlatform")
    case "accessibility":
      let voiceOver = UIAccessibility.isVoiceOverRunning
      let switchControl = UIAccessibility.isSwitchControlRunning
      return LocalFinding.signal(voiceOver || switchControl, "accessibilityEnabled")
        .withValues(["voiceOverEnabled": voiceOver, "switchControlEnabled": switchControl])
    case "vpn": return tunnelSignal()
    case "proxy":
      guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
        return .error("nativeFailure")
      }
      let enabled = [kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesProxyAutoConfigEnable].contains {
        (settings[$0 as String] as? NSNumber)?.boolValue == true
      }
      return LocalFinding.signal(enabled, "proxyConfigured").withValues([
        "httpProxyEnabled": (settings[kCFNetworkProxiesHTTPEnable as String] as? NSNumber)?.boolValue as Any? ?? NSNull(),
        "pacProxyConfigured": (settings[kCFNetworkProxiesProxyAutoConfigEnable as String] as? NSNumber)?.boolValue as Any? ?? NSNull()
      ])
    default: return .unsupported("unimplemented")
    }
  }

  /// Tunnel interfaces are a heuristic, including some legitimate OS services.
  /// Do not inspect or return interface addresses or names.
  private static func tunnelSignal() -> LocalFinding {
    var first: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&first) == 0 else { return .error("nativeFailure") }
    defer { if let first = first { freeifaddrs(first) } }
    var cursor = first
    var policy = TunnelInterfacePolicy()
    while let entry = cursor {
      guard let pointer = entry.pointee.ifa_name else { return .error("nativeFailure") }
      let length = strnlen(pointer, Int(IFNAMSIZ))
      guard length > 0, length < Int(IFNAMSIZ),
        let name = String(bytes: UnsafeBufferPointer(start: pointer, count: length).map { UInt8(bitPattern: $0) },
                          encoding: .utf8) else { return .error("nativeFailure") }
      let flags = entry.pointee.ifa_flags
      let family = entry.pointee.ifa_addr.map { Int32($0.pointee.sa_family) }
      if let failure = policy.observe(name: name, up: flags & UInt32(IFF_UP) != 0,
        running: flags & UInt32(IFF_RUNNING) != 0, family: family) { return failure }
      cursor = entry.pointee.ifa_next
    }
    return policy.finish()
  }
}
