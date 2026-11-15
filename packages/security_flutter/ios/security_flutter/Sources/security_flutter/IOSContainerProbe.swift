import Foundation
import Darwin
import MachO

/// A bounded local execution-origin check, not enumeration of installed apps.
enum IOSContainerProbe {
  private struct FileIdentity: Equatable { let device: Int64; let inode: UInt64 }
  private struct ProbeFailure: Error { let reason: String }

  static func scan(bundle: Bundle = .main) -> LocalFinding {
    guard let executable = bundle.executableURL else { return .error("processIdentityUnavailable") }
    var buffer = [CChar](repeating: 0, count: 4096)
    var size = UInt32(buffer.count)
    let code = buffer.withUnsafeMutableBufferPointer { _NSGetExecutablePath($0.baseAddress, &size) }
    guard code == 0 else { return .error(size > buffer.count ? "scanLimitExceeded" : "nativeFailure") }
    guard let end = buffer.firstIndex(of: 0), end > 0,
      let path = String(bytes: buffer.prefix(end).map { UInt8(bitPattern: $0) }, encoding: .utf8),
      path.hasPrefix("/") else { return .error("processIdentityUnavailable") }
    return evaluate(bundle: bundle.bundleURL, executable: executable,
      processExecutable: URL(fileURLWithPath: path), home: URL(fileURLWithPath: NSHomeDirectory()),
      packageType: bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String)
  }

  /// Internal entry point also used by filesystem-backed policy regression tests.
  static func evaluate(bundle: URL, executable: URL, processExecutable: URL, home: URL, packageType: String? = "APPL") -> LocalFinding {
    let urls = [bundle, executable, processExecutable, home]
    guard urls.allSatisfy({ $0.isFileURL && !$0.path.isEmpty && $0.path.utf8.count <= 4096 &&
      !$0.path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }) else {
      return .error("processIdentityUnavailable")
    }
    // _NSGetExecutablePath may return a symlink. Compare actual file identities,
    // not path spelling, UUIDs, executable names or signing/distribution channels.
    let b = bundle.standardizedFileURL.resolvingSymlinksInPath()
    let e = executable.standardizedFileURL.resolvingSymlinksInPath()
    let p = processExecutable.standardizedFileURL.resolvingSymlinksInPath()
    let h = home.standardizedFileURL.resolvingSymlinksInPath()
    guard packageType == "APPL", b.pathExtension == "app", p.deletingLastPathComponent().pathExtension == "app" else {
      return .unsupported("unsupportedProcess")
    }
    guard e.deletingLastPathComponent().path == b.path else { return .error("processIdentityMismatch") }
    do {
      let expected = try inspect(e, inspectHeader: true)
      let actual = try inspect(p, inspectHeader: false)
      switch expected.1 {
      case .library: return .signal(true, "appExecutableIsLibrary")
      case .unsupported: return .unsupported("executableFormatUnavailable")
      case .invalid: return .error("processIdentityUnavailable")
      case .application: break
      }
      if expected.0 == actual.0 { return .signal(false, "embeddedAppBundle") }
      // A mismatch alone can arise in development/custom hosts. Require a guest
      // .app inside this reported home data area and a separate main app bundle.
      let writableRoots = ["Documents", "Library", "tmp"].map { h.appendingPathComponent($0).path + "/" }
      let embedded = writableRoots.contains { b.path.hasPrefix($0) }
      guard embedded, !p.path.hasPrefix(h.path + "/"), p.deletingLastPathComponent().path != b.path else {
        return .error("processIdentityMismatch")
      }
      return .signal(true, "embeddedAppBundle")
    } catch let failure as ProbeFailure { return .error(failure.reason) }
    catch { return .error("nativeFailure") }
  }

  private static func inspect(_ file: URL, inspectHeader: Bool) throws -> (FileIdentity, MachOExecutablePolicy.Kind) {
    let fd = open(file.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW)
    guard fd >= 0 else {
      throw ProbeFailure(reason: [EACCES, EPERM].contains(errno) ? "probeAccessRestricted" : "processIdentityUnavailable")
    }
    defer { close(fd) }
    // C617.1: only self-reported app bundle/main executable metadata. No file
    // timestamps, header bytes, paths or inode values leave the native probe.
    // Only the main executable header is read; no segments or other libraries.
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw ProbeFailure(reason: "nativeFailure") }
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw ProbeFailure(reason: "processIdentityUnavailable")
    }
    guard info.st_size >= 0 else { throw ProbeFailure(reason: "processIdentityUnavailable") }
    let identity = FileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    guard inspectHeader else { return (identity, .unsupported) }
    #if arch(arm64)
    let cpu: UInt32 = 0x0100000c
    #elseif arch(x86_64)
    let cpu: UInt32 = 0x01000007
    #elseif arch(arm)
    let cpu: UInt32 = 12
    #else
    let cpu: UInt32 = 0
    #endif
    let kind = MachOExecutablePolicy.classify(size: UInt64(info.st_size), cpu: cpu) { offset, count in
      guard offset <= UInt64(Int64.max) else { return nil }
      var bytes = [UInt8](repeating:0, count:count)
      let actual = bytes.withUnsafeMutableBytes { pread(fd, $0.baseAddress, count, off_t(offset)) }
      return actual == count ? bytes : nil
    }
    return (identity, kind)
  }
}
