import Foundation

@main
struct DeviceInformationTests {
  static func main() {
    guard let result=DeviceInformation.collect(systemVersion:"18.0"),
      let device=result["device"] as? [String:Any] else { fatalError("Device descriptors unavailable") }
    precondition(Set(result.keys)==["schemaVersion","device"])
    precondition(Set(device.keys)==["platform","manufacturer","brand","model","systemVersion","apiLevel"])
    print("PASS: closed descriptor field set excludes identifiers and assigned names")
    precondition(device["platform"] as? String == "ios" && device["manufacturer"] as? String == "Apple")
    precondition(device["systemVersion"] as? String == "18.0" && device["apiLevel"] is NSNull)
    print("PASS: iOS version and API-level semantics")
    precondition(!(device["model"] as? String ?? "").isEmpty)
    print("PASS: uname machine is copied into an owned string")
    print("3 device information tests passed")
  }
}
