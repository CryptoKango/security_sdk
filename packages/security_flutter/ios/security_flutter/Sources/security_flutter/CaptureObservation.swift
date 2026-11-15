import Foundation

/// Per-owner/per-engine observation. A gap is terminal until an explicit restart.
/// Cleanup is also used by short-lived guards around asynchronous capture scans.
final class CaptureObservation {
  private weak var target: AnyObject?
  private weak var scene: AnyObject?
  private weak var screen: AnyObject?
  private let hasScene: Bool
  private let hasScreen: Bool
  private var seen = false
  private(set) var interrupted = false
  private var cleanup: [() -> Void] = []
  init(target: AnyObject, scene: AnyObject? = nil, screen: AnyObject? = nil) {
    self.target = target; self.scene = scene; self.screen = screen
    hasScene = scene != nil; hasScreen = screen != nil
  }

  /// Scene-based hosts must not subscribe to process-wide activation changes:
  /// UIKit can also post those when a different Scene deactivates.
  func watchLifecycle(center: NotificationCenter = .default, windowHidden: Notification.Name,
                      sceneEvents: [Notification.Name], appEvents: [Notification.Name]) {
    guard let target = target, !hasScene || scene != nil else { interrupt(); return }
    func watch(_ name: Notification.Name, object: AnyObject?) {
      let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
        self?.interrupt()
      }
      addCleanup { center.removeObserver(token) }
    }
    watch(windowHidden, object: target)
    if hasScene {
      sceneEvents.forEach { watch($0, object: scene) }
    } else {
      appEvents.forEach { watch($0, object: nil) }
    }
  }

  private func sameContext(_ original: AnyObject?, _ current: AnyObject?, expected: Bool) -> Bool {
    if !expected { return current == nil }
    guard let original = original, let current = current else { return false }
    return original === current
  }
  func addCleanup(_ action: @escaping () -> Void) {
    if interrupted { action() } else { cleanup.append(action) }
  }
  func interrupt() {
    interrupted = true // Invalidate before removing listeners or running reentrant cleanup.
    let actions = cleanup
    cleanup.removeAll()
    actions.forEach { $0() }
  }
  func validate(target current: AnyObject?, scene currentScene: AnyObject? = nil, screen currentScreen: AnyObject? = nil, foreground: Bool) -> Bool {
    guard !interrupted else { return false }
    guard let original = target, let current = current, original === current,
      sameContext(scene, currentScene, expected: hasScene),
      sameContext(screen, currentScreen, expected: hasScreen), foreground else {
      interrupt(); return false
    }
    return true
  }
  func record(target: AnyObject?, scene: AnyObject? = nil, screen: AnyObject? = nil, foreground: Bool) {
    if validate(target: target, scene: scene, screen: screen, foreground: foreground) { seen = true }
  }
  func finding(target: AnyObject?, scene: AnyObject? = nil, screen: AnyObject? = nil, foreground: Bool) -> LocalFinding {
    validate(target: target, scene: scene, screen: screen, foreground: foreground)
      ? .signal(seen, "screenshotObserved") : .error("observationInterrupted")
  }
  deinit { cleanup.forEach { $0() } }
}
