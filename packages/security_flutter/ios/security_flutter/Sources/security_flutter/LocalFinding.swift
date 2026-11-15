import Foundation

struct LocalFinding {
  let status: String
  let reason: String
  let values: [String: Any]
  init(status: String, reason: String, values: [String: Any] = [:]) {
    self.status = status; self.reason = reason; self.values = values
  }
  func wire(_ id: String) -> [String: Any] {
    var result: [String: Any] = ["detectorId": id,
      "detectorVersion": (id == "developerMode" || id == "usbDebugging") ? "local-v1" : "local-v8",
      "status": status, "reason": reason]
    if !values.isEmpty { result["values"] = values }
    return result
  }
  func withValues(_ extra: [String: Any]) -> LocalFinding {
    LocalFinding(status: status, reason: reason, values: values.merging(extra) { _, new in new })
  }
  static func signal(_ found: Bool, _ reason: String) -> LocalFinding {
    LocalFinding(status: found ? "detected" : "notDetected", reason: found ? reason : "noKnownSignal",
                 values: ["signalDetected": found])
  }
  static func error(_ reason: String) -> LocalFinding { LocalFinding(status: "error", reason: reason) }
  static func unsupported(_ reason: String) -> LocalFinding { LocalFinding(status: "unsupported", reason: reason) }
}
