import Foundation
import Darwin

/// A bounded interface observation, not proof of a VPN or its traffic routing.
struct TunnelInterfacePolicy {
  private(set) var count = 0
  private var found = false
  mutating func observe(name: String, up: Bool, running: Bool, family: Int32?) -> LocalFinding? {
    count += 1
    guard count <= 1024 else { return .error("scanLimitExceeded") }
    guard !name.isEmpty, name.utf8.count < Int(IFNAMSIZ),
      name.utf8.allSatisfy({ $0 >= 33 && $0 < 127 }) else { return .error("nativeFailure") }
    let namedTunnel = ["utun", "tun", "ppp", "ipsec"].contains { prefix in
      guard name.hasPrefix(prefix) else { return false }
      let suffix = name.dropFirst(prefix.count)
      return !suffix.isEmpty && suffix.utf8.allSatisfy { (48...57).contains($0) }
    }
    if namedTunnel, up, running, family == AF_INET || family == AF_INET6 { found = true }
    return nil
  }
  func finish() -> LocalFinding {
    count == 0 ? .error("nativeFailure") : .signal(found, "tunnelInterface")
  }
}
