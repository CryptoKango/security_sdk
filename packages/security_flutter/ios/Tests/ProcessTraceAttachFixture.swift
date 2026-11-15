import Foundation
import Darwin

@_cdecl("security_sdk_probe_checkpoint")
@inline(never)
func probeCheckpoint() { usleep(1000) }

@main
struct ProcessTraceAttachFixture {
  static func emit(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  }
  static func main() {
    guard !ProcessTraceProbe.isDebugBuild else { emit("FAIL debug build"); exit(1) }
    guard ProcessTraceProbe.scan(mode:nil).reason == "releaseDebuggerOptInRequired" else { exit(2) }
    let initial = ProcessTraceProbe.scan(mode:"allowReleaseProcessTrace")
    guard initial.status == "notDetected" else { emit("FAIL initial \(initial.status)/\(initial.reason)"); exit(3) }
    emit("READY \(getpid())")
    var attached = false
    for _ in 0..<600 {
      let result = ProcessTraceProbe.scan(mode:"allowReleaseProcessTrace")
      if result.status == "detected" {
        if !attached { emit("ATTACHED"); attached = true; probeCheckpoint() }
      } else if result.status == "notDetected" {
        if attached { emit("DETACHED"); exit(0) }
      } else { emit("FAIL query \(result.status)/\(result.reason)"); exit(4) }
      usleep(100_000)
    }
    emit("FAIL no complete attach/detach cycle"); exit(5)
  }
}
