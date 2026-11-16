import Foundation

@main
struct CaptureObservationTests {
  static func main() {
    var passed = 0
    func test(_ name: String, _ body: () -> Bool) {
      guard body() else { fatalError("FAILED: \(name)") }
      passed += 1; print("PASS: \(name)")
    }
    test("event in the same active window is retained") {
      let window = NSObject(); let observation = CaptureObservation(target:window)
      guard observation.finding(target:window,foreground:true).status == "notDetected" else { return false }
      observation.record(target:window,foreground:true)
      return observation.finding(target:window,foreground:true).reason == "screenshotObserved"
    }
    test("background gap is terminal even if foreground returns") {
      let window = NSObject(); let observation = CaptureObservation(target:window)
      _ = observation.finding(target:window,foreground:false)
      observation.record(target:window,foreground:true)
      return observation.finding(target:window,foreground:true).reason == "observationInterrupted"
    }
    test("window replacement never inherits an old clean or positive result") {
      let first = NSObject(); let next = NSObject(); let observation = CaptureObservation(target:first)
      observation.record(target:first,foreground:true)
      return observation.finding(target:next,foreground:true).status == "error" &&
        observation.finding(target:first,foreground:true).status == "error"
    }
    test("stop and late callbacks cannot reactivate a window") {
      let window = NSObject(); let observation = CaptureObservation(target:window)
      observation.interrupt(); observation.record(target:window,foreground:true)
      return observation.finding(target:window,foreground:true).status == "error"
    }
    test("cleanup is one shot and invalidates before reentrant callbacks") {
      let window = NSObject(); let observation = CaptureObservation(target:window)
      var releases = 0
      observation.addCleanup { releases += 1; observation.record(target:window,foreground:true) }
      observation.interrupt(); observation.interrupt()
      return releases == 1 && observation.finding(target:window,foreground:true).status == "error"
    }
    test("late listener installation after interruption releases immediately") {
      let window = NSObject(); let observation = CaptureObservation(target:window)
      var releases = 0; observation.interrupt(); observation.addCleanup { releases += 1 }
      return releases == 1
    }
    test("separate engine owners on the same window do not share state or cleanup") {
      let window = NSObject(); let a = CaptureObservation(target:window); let b = CaptureObservation(target:window)
      var ar = 0; var br = 0
      a.addCleanup { ar += 1 }; b.addCleanup { br += 1 }; a.interrupt()
      guard ar == 1, br == 0, b.finding(target:window,foreground:true).status == "notDetected" else { return false }
      b.record(target:window,foreground:true)
      return b.finding(target:window,foreground:true).reason == "screenshotObserved"
    }
    test("deallocated target becomes unknown without retaining the window") {
      var target: NSObject? = NSObject(); weak var weakTarget = target
      let observation = CaptureObservation(target:target!); target = nil
      return weakTarget == nil && observation.finding(target:nil,foreground:true).status == "error"
    }
    test("deinit releases remaining observers without explicit stop") {
      let target = NSObject(); var released = false
      do { let observation = CaptureObservation(target:target); observation.addCleanup { released = true } }
      return released
    }
    let hidden = Notification.Name("test.hidden")
    let inactive = Notification.Name("test.scene.inactive")
    let background = Notification.Name("test.scene.background")
    let disconnected = Notification.Name("test.scene.disconnected")
    let appInactive = Notification.Name("test.app.inactive")
    func watch(_ observation: CaptureObservation, _ center: NotificationCenter) {
      observation.watchLifecycle(center:center,windowHidden:hidden,
        sceneEvents:[inactive,background,disconnected],appEvents:[appInactive])
    }
    test("another Scene and process notifications cannot interrupt the active Scene") {
      let center=NotificationCenter(); let w1=NSObject(); let w2=NSObject(); let s1=NSObject(); let s2=NSObject()
      let a=CaptureObservation(target:w1,scene:s1); let b=CaptureObservation(target:w2,scene:s2)
      watch(a,center); watch(b,center)
      center.post(name:appInactive,object:nil)
      center.post(name:inactive,object:s2)
      return !a.interrupted && b.interrupted && a.validate(target:w1,scene:s1,foreground:true)
    }
    test("each own Scene terminal event interrupts even without a preceding event") {
      let center=NotificationCenter(); let w=NSObject(); let scene=NSObject()
      for event in [inactive,background,disconnected] {
        let observation=CaptureObservation(target:w,scene:scene); watch(observation,center)
        center.post(name:event,object:scene)
        if !observation.interrupted { return false }
      }
      return true
    }
    test("legacy hosts retain application lifecycle and ignore unrelated windows") {
      let center=NotificationCenter(); let w=NSObject(); let other=NSObject()
      let observation=CaptureObservation(target:w); watch(observation,center)
      center.post(name:hidden,object:other)
      guard !observation.interrupted else { return false }
      center.post(name:appInactive,object:nil)
      return observation.interrupted
    }
    test("window hiding is local to its window even inside one Scene") {
      let center=NotificationCenter(); let w1=NSObject(); let w2=NSObject(); let scene=NSObject()
      let a=CaptureObservation(target:w1,scene:scene); let b=CaptureObservation(target:w2,scene:scene)
      watch(a,center); watch(b,center); center.post(name:hidden,object:w1)
      return a.interrupted && !b.interrupted
    }
    test("moving the same window between Scenes invalidates prior evidence") {
      let window=NSObject(); let first=NSObject(); let next=NSObject()
      let observation=CaptureObservation(target:window,scene:first)
      observation.record(target:window,scene:first,foreground:true)
      return observation.finding(target:window,scene:next,foreground:true).reason == "observationInterrupted"
    }
    test("legacy to Scene and Scene to legacy transitions require restart") {
      let window=NSObject(); let scene=NSObject()
      let legacy=CaptureObservation(target:window); let scoped=CaptureObservation(target:window,scene:scene)
      return !legacy.validate(target:window,scene:scene,foreground:true) &&
        !scoped.validate(target:window,foreground:true)
    }
    test("same Scene with a different screen is not the original capture scope") {
      let window=NSObject(); let scene=NSObject(); let first=NSObject(); let next=NSObject()
      let observation=CaptureObservation(target:window,scene:scene,screen:first)
      return observation.validate(target:window,scene:scene,screen:first,foreground:true) &&
        !observation.validate(target:window,scene:scene,screen:next,foreground:true)
    }
    test("a released Scene is unknown even when both weak context values are nil") {
      let window=NSObject(); var scene: NSObject?=NSObject()
      let observation=CaptureObservation(target:window,scene:scene); scene=nil
      return !observation.validate(target:window,foreground:true)
    }
    test("recording scope changes in either direction are read at reply time") {
      let window=NSObject(); let observation=CaptureObservation(target:window)
      var captured=false; var reads=0
      func read() -> LocalFinding { reads += 1; return .signal(captured,"screenCaptured") }
      let first=observation.recordingFinding(target:window,foreground:true,read:read)
      captured=true
      let second=observation.recordingFinding(target:window,foreground:true,read:read)
      captured=false
      let third=observation.recordingFinding(target:window,foreground:true,read:read)
      return first.status=="notDetected" && second.status=="detected" && third.status=="notDetected" && reads==3
    }
    test("recording does not read a replaced or detached window") {
      let window=NSObject(); let next=NSObject(); let observation=CaptureObservation(target:window)
      var reads=0
      func read() -> LocalFinding { reads += 1; return .signal(true,"screenCaptured") }
      let replaced=observation.recordingFinding(target:next,foreground:true,read:read)
      let restored=observation.recordingFinding(target:window,foreground:true,read:read)
      return replaced.reason=="observationInterrupted" && restored.reason=="observationInterrupted" && reads==0
    }
    test("recording reader failures remain errors") {
      let window=NSObject(); let observation=CaptureObservation(target:window)
      return observation.recordingFinding(target:window,foreground:true,read:{ .error("nativeFailure") }).status=="error"
    }
    print("\(passed) capture observation tests passed")
  }
}
