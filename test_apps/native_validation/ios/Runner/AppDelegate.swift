import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  #if DEBUG
  override func application(_ application: UIApplication, didDiscardSceneSessions sessions: Set<UISceneSession>) {
    // FlutterAppDelegate declares this optional callback but has no implementation.
    RealWindowValidation.didDiscard(sessions)
  }
  override func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                            options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    if options.userActivities.contains(where: { $0.activityType == RealWindowValidation.activityType }) {
      // Load the complete named configuration. Mutating delegate/storyboard here
      // turns it into an unnamed runtime configuration on current UIKit.
      return UISceneConfiguration(name: RealWindowValidation.activityType, sessionRole: session.role)
    }
    return UISceneConfiguration(name: "flutter", sessionRole: session.role)
  }
  #endif

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    #if DEBUG
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LifecycleFixture") {
      LifecycleFixture.register(with: registrar)
    }
    #endif
  }
}

#if DEBUG
// Example integration fixture only. The peer has no FlutterViewController.
private final class LifecycleFixture: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.publish(LifecycleFixture(registrar: registrar))
  }
  private let validation: RealWindowValidation
  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private var originalOrientation: UIInterfaceOrientation?
  private var peer: FlutterEngine?
  private var pending: FlutterResult?
  private var deadline: DispatchWorkItem?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    validation = RealWindowValidation(registrar: registrar)
    channel = FlutterMethodChannel(name: "security_sdk/lifecycle_test", binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if self.validation.handle(call, result: result) { return }
      switch call.method {
      case "startPeer":
        guard self.peer == nil else {
          result(FlutterError(code: "peer_exists", message: "Peer already running", details: nil)); return
        }
        let engine = FlutterEngine(name: "security-lifecycle-peer", project: nil, allowHeadlessExecution: true)
        self.peer = engine
        self.pending = result
        let timeout = DispatchWorkItem { [weak self] in
          self?.pending?(FlutterError(code: "peer_timeout", message: "Peer did not start", details: nil))
          self?.pending = nil
          self?.releasePeer()
        }
        self.deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        engine.run(withEntrypoint: "lifecyclePeerMain")
        GeneratedPluginRegistrant.register(with: engine)
        let report = FlutterMethodChannel(name: "security_sdk/lifecycle_peer", binaryMessenger: engine.binaryMessenger)
        report.setMethodCallHandler { [weak self] message, response in
          guard message.method == "ready" else { response(FlutterMethodNotImplemented); return }
          self?.deadline?.cancel()
          self?.pending?(message.arguments)
          self?.pending = nil
          response(nil)
        }
      case "interruptCapture":
        // Exercise real NotificationCenter subscriptions; this is not a device capture.
        if let scene = self.registrar?.viewController?.viewIfLoaded?.window?.windowScene {
          NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
        } else {
          NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        }
        result(nil)
      case "applicationInactive":
        // Verify process notifications do not interrupt a Scene-bound observation.
        // Foreign Scene identity filtering uses an isolated native test center;
        // never post fake Scene objects into UIKit's global notification center.
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        result(self.registrar?.viewController?.viewIfLoaded?.window?.windowScene != nil)
      case "uiState":
        let scene = self.registrar?.viewController?.viewIfLoaded?.window?.windowScene
        result(["orientation": scene?.interfaceOrientation.rawValue ?? 0,
                "focus": scene?.activationState == .foregroundActive])
      case "rotate", "restoreOrientation":
        guard #available(iOS 16.0, *),
          let scene = self.registrar?.viewController?.viewIfLoaded?.window?.windowScene else {
          result(0); return // Old iOS/legacy hosts: fixture cannot request Scene geometry.
        }
        if self.originalOrientation == nil { self.originalOrientation = scene.interfaceOrientation }
        let target: UIInterfaceOrientation = call.method == "rotate"
          ? (scene.interfaceOrientation.isPortrait ? .landscapeLeft : .portrait)
          : (self.originalOrientation ?? .portrait)
        let mask: UIInterfaceOrientationMask = target == .landscapeLeft ? .landscapeLeft
          : target == .landscapeRight ? .landscapeRight : target == .portraitUpsideDown ? .portraitUpsideDown : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        result(target.rawValue)
      case "screenshot":
        NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        result(nil)
      case "stopPeer": self.releasePeer(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func releasePeer() {
    deadline?.cancel()
    deadline = nil
    pending?(FlutterError(code: "peer_stopped", message: "Peer stopped", details: nil))
    pending = nil
    peer?.destroyContext()
    peer = nil
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) { releasePeer(); validation.dispose() }
  deinit { releasePeer(); validation.dispose() }
}
#endif
