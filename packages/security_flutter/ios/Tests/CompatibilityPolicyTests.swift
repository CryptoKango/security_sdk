import Foundation
import Darwin

@main
struct CompatibilityPolicyTests {
  static func main() {
    var passed = 0
    func test(_ name: String, _ body: () -> Bool) {
      guard body() else { fatalError("FAILED: \(name)") }
      passed += 1; print("PASS: \(name)")
    }
    test("wire preserves measured false and explicit null without fabricating unknown readings") {
      let finding = LocalFinding.signal(false, "proxyConfigured")
        .withValues(["httpProxyEnabled": false, "pacProxyConfigured": NSNull()])
      let wire = finding.wire("proxy")
      guard let values = wire["values"] as? [String: Any] else { return false }
      return wire["status"] as? String == "notDetected" &&
        values["signalDetected"] as? Bool == false && values["httpProxyEnabled"] as? Bool == false &&
        values["pacProxyConfigured"] is NSNull &&
        LocalFinding.error("nativeFailure").wire("proxy")["values"] == nil &&
        LocalFinding.unsupported("unsupportedPlatform").values.isEmpty
    }
    test("older OS or absent location source remains null") {
      let result = LocationMetadataPolicy.metadata(age: 1, accuracy: 5, source: { nil })
      return result?["isMocked"] is NSNull && result?["ageMilliseconds"] as? Double == 1000
    }
    test("valid source metadata preserves both boolean values without coordinates") {
      [false,true].allSatisfy { value in
        let result = LocationMetadataPolicy.metadata(age: 0, accuracy: 0, source: { value })!
        return result["isMocked"] as? Bool == value && Set(result.keys) == ["isMocked", "ageMilliseconds"]
      }
    }
    test("invalid accuracy is rejected before reading a source flag") {
      [-1, Double.nan, Double.infinity].allSatisfy { accuracy in
        LocationMetadataPolicy.metadata(age: 1, accuracy: accuracy, source: { fatalError("must not read") }) == nil
      }
    }
    test("future nonfinite and overflow ages cannot produce verdicts") {
      [-1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude].allSatisfy { age in
        LocationMetadataPolicy.metadata(age: age, accuracy: 5, source: { fatalError("must not read") }) == nil
      }
    }
    func signal(_ name: String, up: Bool = true, running: Bool = true, family: Int32? = AF_INET) -> LocalFinding {
      var policy = TunnelInterfacePolicy()
      return policy.observe(name:name, up:up, running:running, family:family) ?? policy.finish()
    }
    test("numbered active IP tunnel interface is a specific signal") {
      ["utun0", "tun1", "ppp12", "ipsec3"].allSatisfy { name in
        [AF_INET, AF_INET6].allSatisfy { signal(name, family:$0).reason == "tunnelInterface" }
      }
    }
    test("similar interface names are not tunnel evidence") {
      ["tunnel0", "tun", "utunctl", "pppoe0", "ipsecurity0", "en0", "lo0"].allSatisfy {
        signal($0).status == "notDetected"
      }
    }
    test("inactive or addressless tunnel interfaces are not active IP tunnels") {
      signal("utun0",up:false).status == "notDetected" &&
        signal("utun0",running:false).status == "notDetected" &&
        signal("utun0",family:nil).status == "notDetected" &&
        signal("utun0",family:AF_LINK).status == "notDetected"
    }
    test("empty malformed and overbudget interface snapshots remain unknown") {
      guard TunnelInterfacePolicy().finish().status == "error",
        signal("").status == "error", signal(String(repeating:"a",count:Int(IFNAMSIZ))).status == "error" else { return false }
      var policy = TunnelInterfacePolicy()
      for _ in 0..<1024 {
        if policy.observe(name:"en0", up:true, running:true, family:AF_INET) != nil { return false }
      }
      return policy.observe(name:"en0",up:true,running:true,family:AF_INET)?.reason == "scanLimitExceeded"
    }
    print("\(passed) compatibility policy tests passed")
  }
}
