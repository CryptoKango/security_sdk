import Darwin

@main
struct ProcessTraceProbeTests {
  static func main() {
    var passed = 0
    func test(_ name: String, _ body: () -> Bool) {
      guard body() else { fatalError("FAILED: \(name)") }
      passed += 1; print("PASS: \(name)")
    }
    func sample(_ flags: Int32 = 0, code: Int32 = 0, error: Int32 = 0,
                size: Int = ProcessTraceProbe.expectedSize, pid: pid_t = getpid()) -> ProcessTraceSample {
      ProcessTraceSample(returnCode: code, errorNumber: error, returnedSize: size, processID: pid, flags: flags)
    }
    test("Release default does not query process state") {
      var calls = 0
      let result = ProcessTraceProbe.scan(mode:nil, debugBuild:false) { calls += 1; return sample() }
      return calls == 0 && result.status == "unsupported" && result.reason == "releaseDebuggerOptInRequired"
    }
    test("explicit Release opt-in uses the same reader as Debug") {
      var calls = 0
      let release = ProcessTraceProbe.scan(mode:"allowReleaseProcessTrace", debugBuild:false) { calls += 1; return sample(P_TRACED) }
      let debug = ProcessTraceProbe.scan(mode:nil, debugBuild:true) { calls += 1; return sample(P_TRACED) }
      return calls == 2 && release.reason == "debuggerAttached" && debug.reason == release.reason
    }
    test("only the P_TRACED flag indicates tracing") {
      let idle = ProcessTraceProbe.evaluate(sample(P_SELECT), expectedPID:getpid())
      let traced = ProcessTraceProbe.evaluate(sample(P_SELECT | P_TRACED), expectedPID:getpid())
      return idle.status == "notDetected" && traced.status == "detected"
    }
    test("kernel failure cannot turn zeroed or traced bytes into a verdict") {
      let denied = ProcessTraceProbe.evaluate(sample(P_TRACED,code:-1,error:EPERM),expectedPID:getpid())
      let failed = ProcessTraceProbe.evaluate(sample(0,code:-1,error:ENOMEM),expectedPID:getpid())
      return denied.status == "error" && denied.reason == "probeAccessRestricted" && failed.status == "error"
    }
    test("truncated expanded and wrong-process samples are rejected") {
      let samples = [sample(size:0),sample(size:ProcessTraceProbe.expectedSize-1),
        sample(size:ProcessTraceProbe.expectedSize+8),sample(pid:0),sample(pid:getpid()+1)]
      return samples.allSatisfy { ProcessTraceProbe.evaluate($0,expectedPID:getpid()).reason == "processInfoMismatch" }
    }
    test("malformed policy never runs the syscall") {
      var calls = 0
      for mode: Any in [true, 1, "unknown", "allowReleaseProcessTrace "] {
        if ProcessTraceProbe.scan(mode:mode,debugBuild:true,read:{ calls += 1; return sample() }).reason != "debuggerPolicyInvalid" { return false }
      }
      return calls == 0
    }
    test("compiled default agrees with build configuration") {
      var calls = 0
      let result = ProcessTraceProbe.scan(mode:nil) { calls += 1; return sample() }
      return ProcessTraceProbe.isDebugBuild ? calls == 1 && result.status == "notDetected"
        : calls == 0 && result.reason == "releaseDebuggerOptInRequired"
    }
    test("actual self-process query has a valid ABI and identity") {
      let result = ProcessTraceProbe.scan(mode:"allowReleaseProcessTrace")
      return result.status == "detected" || result.status == "notDetected"
    }
    print("\(passed) process trace tests passed; Debug=\(ProcessTraceProbe.isDebugBuild)")
  }
}
