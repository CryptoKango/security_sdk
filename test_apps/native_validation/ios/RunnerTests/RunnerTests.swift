import Flutter
import XCTest
@testable import security_flutter
@testable import Runner

final class RunnerTests: XCTestCase {
  private func invoke(_ plugin: SecurityFlutterPlugin, _ method: String, _ arguments: [String:Any]) -> Any? {
    let completed = expectation(description: method)
    var response: Any?
    plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { result in
      response = result; completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
    return response
  }
  func testValidationSceneConfigurationHasStableNameAndDelegate() {
    let config = UISceneConfiguration(name: RealWindowValidation.activityType, sessionRole: .windowApplication)
    XCTAssertEqual(config.name, RealWindowValidation.activityType)
    XCTAssertNotNil(config.delegateClass)
    if let delegate = config.delegateClass {
      XCTAssertEqual(NSStringFromClass(delegate), NSStringFromClass(WindowValidationSceneDelegate.self))
    }
    XCTAssertNil(config.storyboard)
  }

  func testDeveloperSettingsAreExplicitlyUnsupportedOnIOS() {
    let plugin = SecurityFlutterPlugin()
    let ids = ["developerMode", "usbDebugging"]
    let response = invoke(plugin, "capabilities", [:]) as? [String: Any]
    let capabilities = response?["capabilities"] as? [[String: Any]] ?? []
    for id in ids {
      let entries = capabilities.filter { $0["id"] as? String == id }
      XCTAssertEqual(entries.count, 1)
      XCTAssertEqual(entries.first?["supported"] as? Bool, false)
    }
    let result = invoke(plugin, "scan", ["owner":"test", "contextId":"test", "detectorIds":ids]) as? [String: Any]
    let findings = result?["findings"] as? [[String: Any]] ?? []
    XCTAssertEqual(findings.count, 2)
    for finding in findings {
      XCTAssertEqual(finding["status"] as? String, "unsupported")
      XCTAssertEqual(finding["reason"] as? String, "unsupportedPlatform")
      XCTAssertEqual(finding["detectorVersion"] as? String, "local-v1")
    }
  }
  func testHeadlessCaptureStartIsUnavailable() {
    let result = invoke(SecurityFlutterPlugin(), "startScreenshotObservation", ["owner":"test"])
    XCTAssertEqual((result as? FlutterError)?.code, "platform_unavailable")
  }
  func testHeadlessRecordingAndUnstartedScreenshotRemainUnknown() {
    let result = invoke(SecurityFlutterPlugin(), "scan", ["owner":"test", "contextId":"test", "detectorIds":["screenshot","screenRecording"]])
    let findings = (result as? [String:Any])?["findings"] as? [[String:Any]]
    XCTAssertEqual(findings?.count, 2)
    XCTAssertEqual(findings?[0]["status"] as? String, "error")
    XCTAssertEqual(findings?[0]["reason"] as? String, "observationRequired")
    XCTAssertEqual(findings?[1]["status"] as? String, "error")
    XCTAssertEqual(findings?[1]["reason"] as? String, "noActivity")
  }
  func testMalformedOwnerCannotRegisterObservation() {
    let result = invoke(SecurityFlutterPlugin(), "startScreenshotObservation", ["owner":""])
    XCTAssertEqual((result as? FlutterError)?.code, "invalid_request")
  }
  func testStopWithoutWindowIsIdempotent() {
    let plugin = SecurityFlutterPlugin()
    for _ in 0..<2 {
      let result = invoke(plugin, "stopScreenshotObservation", ["owner":"test"])
      XCTAssertEqual((result as? [String:Any])?["schemaVersion"] as? Int, 1)
    }
  }
}
