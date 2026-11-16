import Foundation
import Darwin

/// No UIDevice.name, identifierForVendor, advertising ID or persistent state.
enum DeviceInformation {
  static func collect(systemVersion: String) -> [String: Any]? {
    var system = utsname()
    guard uname(&system) == 0 else { return nil }
    let model = withUnsafeBytes(of: &system.machine) { bytes in
      String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
    }
    guard let model = model, !model.isEmpty else { return nil }
    return ["schemaVersion": 1, "device": ["platform": "ios", "manufacturer": "Apple",
      "brand": "Apple", "model": model, "systemVersion": systemVersion, "apiLevel": NSNull()]]
  }
}
