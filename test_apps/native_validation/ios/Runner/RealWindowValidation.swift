#if DEBUG
import Flutter
import UIKit

// Test-only registry of explicitly requested sessions. Never enumerates foreign apps.
private final class ValidationSceneRecord {
  weak var delegate: WindowValidationSceneDelegate?
  var connected = false
  var ready = false
  var detached = false
  var discardWhenDisconnected = false
  var disconnectedNotification = false
  var sessionID: String?
  weak var engine: FlutterEngine?
  weak var controller: FlutterViewController?
  weak var plugin: NSObject?
  weak var observedWindow: UIWindow?
  var engineStarted = false
  var pluginRegistered = false
  var contextDestroyed = false
  var disconnectCallbacks = 0
  var teardownCount = 0
  var sessionDiscarded = false
  var freshSession = false
  var configurationNamed = false
  var resourcesReleased: Bool {
    engineStarted && pluginRegistered && contextDestroyed && engine == nil && controller == nil && plugin == nil && observedWindow == nil
  }
}
final class RealWindowValidation {
  static let activityType = "dev.securitysdk.window-validation"
  fileprivate static var records: [String: ValidationSceneRecord] = [:]
  private weak var registrar: FlutterPluginRegistrar?
  private var token: String?
  private var requestFailed = false
  private var closeRequests = 0
  private var previousSessionID: String?
  private var cyclesStarted = 0
  private var auditTokens: [NSObjectProtocol] = []
  private var interruptions = 0
  private var pip: ValidationPiP?
  init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }
  private var ownScene: UIWindowScene? { registrar?.viewController?.viewIfLoaded?.window?.windowScene }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    switch call.method {
    case "createValidationScene":
      guard UIApplication.shared.supportsMultipleScenes, ownScene != nil else {
        result(["supported": false, "reason": "multipleScenesUnavailable"]); return true
      }
      if let old = token, let record = Self.records[old], record.detached && record.resourcesReleased && !Self.sessionRegistered(record) {
        previousSessionID = record.sessionID
        Self.records.removeValue(forKey: old); token = nil
      }
      guard token == nil, Self.records.count < 4 else {
        result(FlutterError(code: "fixture_busy", message: "Scene already requested", details: nil)); return true
      }
      audit()
      let key = UUID().uuidString; token = key; requestFailed = false
      Self.records[key] = ValidationSceneRecord()
      closeRequests = 0; cyclesStarted += 1
      let activity = NSUserActivity(activityType: Self.activityType); activity.userInfo = ["token": key]
      UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { [weak self] _ in self?.requestFailed = true }
      result(["supported": true])
    case "validationSceneState":
      let record = token.flatMap { Self.records[$0] }; let other = record?.delegate?.window?.windowScene
      if let id = record?.sessionID { record?.freshSession = id != previousSessionID }
      result(["connected": record?.connected == true, "ready": record?.ready == true,
              "detached": record?.detached == true, "closeRequests": closeRequests, "disconnectedNotification": record?.disconnectedNotification == true,
              "sessionRegistered": record.map { Self.sessionRegistered($0) } ?? false,
              "systemConnected": record.map { r in UIApplication.shared.connectedScenes.contains { $0.session.persistentIdentifier == r.sessionID } } ?? false,
              "sessionDiscarded": record?.sessionDiscarded == true,
              "disconnectCallbacks": record?.disconnectCallbacks ?? 0, "teardownCount": record?.teardownCount ?? 0,
              "engineStarted": record?.engineStarted == true, "pluginRegistered": record?.pluginRegistered == true,
              "engineReleased": record?.engineStarted == true && record?.engine == nil,
              "controllerReleased": record?.engineStarted == true && record?.controller == nil,
              "pluginReleased": record?.pluginRegistered == true && record?.plugin == nil,
              "resourcesReleased": record?.resourcesReleased == true, "contextDestroyed": record?.contextDestroyed == true,
              "configurationNamed": record?.configurationNamed == true, "freshSession": record?.freshSession == true, "cyclesStarted": cyclesStarted,
              "registryCount": Self.records.count, "requestFailed": requestFailed,
              "distinctScenes": other != nil && ownScene != nil && other !== ownScene,
              "mainInterruptions": interruptions, "mainActive": ownScene?.activationState == .foregroundActive,
              "peerActive": other?.activationState == .foregroundActive])
    case "activateValidationScene", "activatePrimaryScene":
      let selected = call.method == "activatePrimaryScene" ? ownScene : token.flatMap { Self.records[$0]?.delegate?.window?.windowScene }
      guard let scene = selected else { result(FlutterError(code: "fixture_unavailable", message: "Scene unavailable", details: nil)); return true }
      UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil) { [weak self] _ in self?.requestFailed = true }
      result(nil)
    case "validationSceneCommand":
      guard let key = token, let delegate = Self.records[key]?.delegate,
        Self.records[key]?.ready == true, let command = call.arguments as? String else {
        result(FlutterError(code: "fixture_unavailable", message: "Peer not ready", details: nil)); return true
      }
      delegate.channel?.invokeMethod(command, arguments: nil, result: result)
    case "destroyValidationScene":
      if let record = token.flatMap({ Self.records[$0] }), record.connected,
        record.delegate?.window?.windowScene?.activationState != .foregroundActive {
        result(FlutterError(code: "fixture_scene_inactive", message: "Activate the test Scene before closing it", details: nil)); return true
      }
      closeScene(); result(nil)
    case "releaseValidationScene":
      if let key = token, let record = Self.records[key] {
        guard record.detached && record.resourcesReleased && !Self.sessionRegistered(record) else {
          result(FlutterError(code: "fixture_busy", message: "Scene resources have not been released", details: nil)); return true
        }
        Self.records.removeValue(forKey: key); token = nil
      }
      result(nil)
    case "prepareIosPip":
      guard pip == nil, let view = registrar?.viewController?.viewIfLoaded else {
        result(FlutterError(code: "fixture_unavailable", message: "Player view unavailable", details: nil)); return true
      }
      audit()
      pip = ValidationPiP(view: view); pip?.prepare(); result(nil)
    case "iosPipState":
      var state = pip?.state ?? ["phase": "absent", "active": false]
      state["mainActive"] = ownScene?.activationState == .foregroundActive
      state["mainInterruptions"] = interruptions
      result(state)
    case "startIosPip": pip?.start(); result(nil)
    case "stopIosPip": pip?.stop(); result(nil)
    case "disposeIosPip": pip?.dispose(); pip = nil; result(nil)
    default: return false
    }
    return true
  }
  private func audit() {
    auditTokens.forEach { NotificationCenter.default.removeObserver($0) }; auditTokens.removeAll(); interruptions = 0
    guard let scene = ownScene, let window = registrar?.viewController?.viewIfLoaded?.window else { return }
    for (name, object) in [(UIScene.willDeactivateNotification, scene as AnyObject),
                           (UIScene.didEnterBackgroundNotification, scene as AnyObject),
                           (UIWindow.didBecomeHiddenNotification, window as AnyObject)] {
      auditTokens.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in self?.interruptions += 1 })
    }
  }
  fileprivate static func sessionRegistered(_ record: ValidationSceneRecord) -> Bool {
    guard let id = record.sessionID else { return false }
    return UIApplication.shared.openSessions.contains { $0.persistentIdentifier == id }
  }
  static func didDiscard(_ sessions: Set<UISceneSession>) {
    for record in records.values where sessions.contains(where: { $0.persistentIdentifier == record.sessionID }) {
      record.sessionDiscarded = true
    }
  }
  private func closeScene() {
    guard let key = token, let session = Self.records[key]?.delegate?.window?.windowScene?.session else { return }
    closeRequests += 1
    UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { [weak self] _ in self?.requestFailed = true }
  }
  func dispose() {
    pip?.dispose(); pip = nil
    auditTokens.forEach { NotificationCenter.default.removeObserver($0) }; auditTokens.removeAll()
    if let key = token { Self.records[key]?.discardWhenDisconnected = true }
    closeScene()
    // Retain a bounded terminal record until disconnect; the delegate removes it.
    if let key = token, Self.records[key]?.connected != true { Self.records.removeValue(forKey: key) }
    token = nil
  }
}

final class WindowValidationSceneDelegate: FlutterSceneDelegate {
  fileprivate var channel: FlutterMethodChannel?
  private var engine: FlutterEngine?
  private var token: String?
  private var disconnectToken: NSObjectProtocol?
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene,
      let key = options.userActivities.first(where: { $0.activityType == RealWindowValidation.activityType })?.userInfo?["token"] as? String,
      let record = RealWindowValidation.records[key] else {
      UIApplication.shared.requestSceneSessionDestruction(session, options: nil); return
    }
    record.configurationNamed = session.configuration.name == RealWindowValidation.activityType
    token = key; record.sessionID = session.persistentIdentifier; record.delegate = self; record.connected = true; record.detached = false
    disconnectToken = NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) { [weak record] _ in
      record?.disconnectedNotification = true
      // Observe the system notification; cleanup belongs to the delegate callback.
    }
    let engine = FlutterEngine(name: "security-validation-scene", project: nil, allowHeadlessExecution: false)
    self.engine = engine
    record.engine = engine
    record.engineStarted = engine.run(withEntrypoint: "validationSceneMain")
    GeneratedPluginRegistrant.register(with: engine)
    record.plugin = engine.valuePublished(byPlugin: "SecurityFlutterPlugin")
    record.pluginRegistered = record.plugin != nil
    let bridge = FlutterMethodChannel(name: "security_sdk/scene_validation", binaryMessenger: engine.binaryMessenger)
    channel = bridge
    bridge.setMethodCallHandler { [weak record] call, result in
      if call.method == "ready" { record?.ready = true; result(nil) } else { result(FlutterMethodNotImplemented) }
    }
    let window = UIWindow(windowScene: scene)
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    record.controller = controller; record.observedWindow = window
    window.rootViewController = controller
    self.window = window; window.makeKeyAndVisible()
    super.scene(scene, willConnectTo: session, options: options)
  }
  // Test sessions are transient; never restore a stale token/engine after relaunch.
  override func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? { nil }
  override func sceneDidDisconnect(_ scene: UIScene) {
    if let key = token { RealWindowValidation.records[key]?.disconnectCallbacks += 1 }
    super.sceneDidDisconnect(scene)
    disconnect()
  }
  private func disconnect() {
    guard let key = token, let record = RealWindowValidation.records[key], !record.detached else { return }
    record.teardownCount += 1
    if let disconnectToken = disconnectToken { NotificationCenter.default.removeObserver(disconnectToken) }
    disconnectToken = nil
    channel?.setMethodCallHandler(nil); channel = nil
    window?.isHidden = true; window?.rootViewController = nil
    engine?.destroyContext()
    record.contextDestroyed = engine?.isolateId == nil
    engine = nil; window = nil
    if let key = token, let record = RealWindowValidation.records[key] {
      record.connected = false; record.ready = false; record.detached = true
      if record.discardWhenDisconnected { RealWindowValidation.records.removeValue(forKey: key) }
    }
  }
}
#endif
