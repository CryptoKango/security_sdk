import Flutter
import UIKit

/// No collection on registration. Per-instance screenshot windows are explicit.
public class SecurityFlutterPlugin: NSObject, FlutterPlugin {
  private weak var registrar: FlutterPluginRegistrar?
  private let worker = DispatchQueue(label: "security_sdk.runtime", qos: .utility)
  private var generation = 0
  private var pendingRuntimeScans = 0
  private var observations: [String: CaptureObservation] = [:]
  private var pendingCapture: [ObjectIdentifier: CaptureObservation] = [:]
  private let ids = ["root", "hook", "debugger", "appIntegrity", "emulator", "multiInstance",
                     "automation", "developerMode", "usbDebugging", "accessibility", "vpn", "proxy", "screenshot", "screenRecording"]
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "security_sdk/local/v1", binaryMessenger: registrar.messenger())
    let plugin = SecurityFlutterPlugin()
    plugin.registrar = registrar
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "deviceInfo":
      guard let value = DeviceInformation.collect(systemVersion: UIDevice.current.systemVersion) else {
        result(FlutterError(code: "platform_unavailable", message: "Device information unavailable", details: nil)); return
      }
      result(value)
    case "capabilities":
      var supported: Set<String> = ["emulator", "accessibility", "vpn", "proxy", "screenshot", "screenRecording", "hook", "appIntegrity", "debugger", "multiInstance"]
      if RuntimeSignals.rootSupported { supported.insert("root") }
      result(["schemaVersion": 1, "capabilities": ids.map {
        ["id": $0, "supported": supported.contains($0),
         "requiresExplicitOptIn": $0 == "debugger" && ProcessTraceProbe.requiresReleaseOptIn] as [String: Any]
      }])
    case "scan":
      guard let args = call.arguments as? [String: Any],
            let contextId = args["contextId"] as? String, !contextId.isEmpty,
            let owner = args["owner"] as? String, !owner.isEmpty,
            let requested = args["detectorIds"] as? [String], !requested.isEmpty,
            requested.allSatisfy({ !$0.isEmpty }), Set(requested).count == requested.count else {
        result(FlutterError(code: "invalid_request", message: "Invalid scan request", details: nil)); return
      }
      let immediate = Dictionary(uniqueKeysWithValues: requested.filter { !RuntimePolicy.ids.contains($0) }.map { id in
        let finding: LocalFinding
        switch id {
        case "screenshot": finding = screenshot(owner)
        case "screenRecording": finding = screenRecording()
        default: finding = EnvironmentSignals.scan(id)
        }
        return (id, finding.wire(id))
      })
      let runtime = requested.filter { RuntimePolicy.ids.contains($0) }
      if runtime.isEmpty {
        result(["schemaVersion": 1, "contextId": contextId, "findings": requested.map { immediate[$0]! }]); return
      }
      guard pendingRuntimeScans < 8 else {
        var findings = immediate
        runtime.forEach { findings[$0] = LocalFinding.error("scanLimitExceeded").wire($0) }
        result(["schemaVersion": 1, "contextId": contextId, "findings": requested.map { findings[$0]! }]); return
      }
      let captureIds = requested.filter { $0 == "screenshot" || $0 == "screenRecording" }
      let originalObservation = observations[owner]
      var guardObservation: CaptureObservation?
      if !captureIds.isEmpty, let current = window, foreground {
        let guardWindow = CaptureObservation(target: current, scene: current.windowScene, screen: current.screen)
        watchLifecycle(guardWindow)
        pendingCapture[ObjectIdentifier(guardWindow)] = guardWindow
        guardObservation = guardWindow
      }
      let captureGuard = guardObservation
      let reply: ([String: [String: Any]]) -> Void = { [weak self] incoming in
        guard let self = self else { captureGuard?.interrupt(); return }
        defer {
          captureGuard?.interrupt()
          if let captureGuard = captureGuard { self.pendingCapture.removeValue(forKey: ObjectIdentifier(captureGuard)) }
        }
        var findings = incoming
        if let captureGuard = captureGuard {
          let valid = captureGuard.validate(target: self.window, scene: self.window?.windowScene, screen: self.window?.screen, foreground: self.foreground)
          if !valid && self.observations[owner] === originalObservation {
            originalObservation?.interrupt() // Do not invalidate a newer owner's replacement.
          }
          for id in captureIds where ["detected", "notDetected"].contains(findings[id]?["status"] as? String ?? "") {
            if id == "screenRecording" {
              findings[id] = captureGuard.recordingFinding(target: self.window, scene: self.window?.windowScene,
                screen: self.window?.screen, foreground: self.foreground, read: self.screenRecording).wire(id)
            } else if !valid || (id == "screenshot" && (self.observations[owner] !== originalObservation || originalObservation?.interrupted == true)) {
              findings[id] = LocalFinding.error("observationInterrupted").wire(id)
            }
          }
        }
        result(["schemaVersion": 1, "contextId": contextId, "findings": requested.map { findings[$0]! }])
      }
      pendingRuntimeScans += 1
      let currentGeneration = generation
      let policy = args["integrityPolicy"]
      let debuggerMode = args["iosDebuggerMode"]
      worker.async {
        var findings = immediate
        for id in runtime { findings[id] = RuntimeSignals.scan(id, policy: policy, debuggerMode: debuggerMode).wire(id) }
        let completed = findings
        DispatchQueue.main.async { [weak self] in
          guard let self = self, self.generation == currentGeneration else { return }
          self.pendingRuntimeScans -= 1
          reply(completed)
        }
      }
    case "startScreenshotObservation", "stopScreenshotObservation":
      guard let args = call.arguments as? [String: Any], let owner = args["owner"] as? String,
            !owner.isEmpty, owner.count <= 128 else {
        result(FlutterError(code: "invalid_request", message: "Invalid owner", details: nil)); return
      }
      if call.method == "stopScreenshotObservation" {
        observations.removeValue(forKey: owner)?.interrupt()
      } else if !startScreenshot(owner) {
        result(FlutterError(code: "platform_unavailable", message: "Observation unavailable", details: nil)); return
      }
      result(["schemaVersion": 1])
    default: result(FlutterMethodNotImplemented)
    }
  }

  private var window: UIWindow? { registrar?.viewController?.viewIfLoaded?.window }
  private var foreground: Bool {
    guard let window = window, !window.isHidden, registrar?.viewController?.viewIfLoaded?.isHidden == false else { return false }
    // Older UIKit hosts may not adopt UIScene even on iOS 13+.
    if let scene = window.windowScene { return scene.activationState == .foregroundActive }
    return UIApplication.shared.applicationState == .active
  }

  private func watchLifecycle(_ observation: CaptureObservation) {
    observation.watchLifecycle(windowHidden: UIWindow.didBecomeHiddenNotification,
      sceneEvents: [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                    UIScene.didDisconnectNotification],
      appEvents: [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification])
  }

  private func startScreenshot(_ owner: String) -> Bool {
    if let existing = observations[owner] {
      if existing.validate(target: window, scene: window?.windowScene, screen: window?.screen, foreground: foreground) { return true }
      observations.removeValue(forKey: owner)?.interrupt()
    }
    guard foreground, let current = window, observations.count < 64 else { return false }
    let observation = CaptureObservation(target: current, scene: current.windowScene, screen: current.screen)
    observations[owner] = observation
    watchLifecycle(observation)
    let center = NotificationCenter.default
    let token = center.addObserver(forName: UIApplication.userDidTakeScreenshotNotification,
        object: nil, queue: .main) { [weak self, weak observation] _ in
      guard let self = self, let observation = observation,
        self.observations[owner] === observation else { return }
      observation.record(target: self.window, scene: self.window?.windowScene, screen: self.window?.screen, foreground: self.foreground)
    }
    observation.addCleanup { center.removeObserver(token) }
    return true
  }

  private func screenshot(_ owner: String) -> LocalFinding {
    guard let observation = observations[owner] else { return .error("observationRequired") }
    return observation.finding(target: window, scene: window?.windowScene, screen: window?.screen, foreground: foreground)
  }

  private func screenRecording() -> LocalFinding {
    guard let window = window, foreground else { return .error("noActivity") }
    if #available(iOS 17.0, *), window.windowScene != nil {
      switch window.traitCollection.sceneCaptureState {
      case .active: return .signal(true, "screenCaptured")
      case .inactive: return .signal(false, "screenCaptured")
      default: return .error("nativeFailure")
      }
    }
    return .signal(window.screen.isCaptured, "screenCaptured")
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    generation += 1
    pendingRuntimeScans = 0
    observations.values.forEach { $0.interrupt() }
    pendingCapture.values.forEach { $0.interrupt() }
    pendingCapture.removeAll()
    observations.removeAll()
    self.registrar = nil
  }
}
