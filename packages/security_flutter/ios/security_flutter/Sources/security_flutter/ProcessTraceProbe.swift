import Darwin

/// Raw self-process query data stays inside the native implementation.
struct ProcessTraceSample {
  let returnCode: Int32
  let errorNumber: Int32
  let returnedSize: Int
  let processID: pid_t
  let flags: Int32
}

/// Read-only snapshot, not anti-attach or tamper-resistant proof. No private
/// symbol lookup, hard-coded struct offsets, ptrace or exception-port changes.
enum ProcessTraceProbe {
  static var isDebugBuild: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
  }
  static var requiresReleaseOptIn: Bool { !isDebugBuild }
  static var expectedSize: Int { MemoryLayout<kinfo_proc>.stride }

  static func scan(mode raw: Any?, debugBuild: Bool = isDebugBuild,
                   read: () -> ProcessTraceSample = readSystem) -> LocalFinding {
    let mode: String
    if let raw = raw {
      guard let value = raw as? String,
        ["debugBuildOnly", "allowReleaseProcessTrace"].contains(value) else {
        return .error("debuggerPolicyInvalid")
      }
      mode = value
    } else { mode = "debugBuildOnly" }
    guard debugBuild || mode == "allowReleaseProcessTrace" else {
      return .unsupported("releaseDebuggerOptInRequired")
    }
    return evaluate(read(), expectedPID: getpid())
  }

  static func evaluate(_ sample: ProcessTraceSample, expectedPID: pid_t) -> LocalFinding {
    guard sample.returnCode == 0 else {
      return .error([EACCES, EPERM].contains(sample.errorNumber) ? "probeAccessRestricted" : "nativeFailure")
    }
    // kinfo_proc has no ABI-stability guarantee. These guards detect some layout
    // or response changes; they cannot prove ABI compatibility on a future OS.
    guard sample.returnedSize == expectedSize, expectedPID > 0,
      sample.processID == expectedPID else { return .error("processInfoMismatch") }
    return .signal(sample.flags & P_TRACED != 0, "debuggerAttached")
  }

  static func readSystem() -> ProcessTraceSample {
    var info = kinfo_proc()
    var size = expectedSize
    let pid = getpid()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    let code = mib.withUnsafeMutableBufferPointer { buffer in
      sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
    }
    let savedError = code == 0 ? 0 : errno
    return ProcessTraceSample(returnCode: code, errorNumber: savedError,
      returnedSize: size, processID: info.kp_proc.p_pid, flags: info.kp_proc.p_flag)
  }
}
