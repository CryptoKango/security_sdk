import Foundation
import CryptoKit
import Darwin

/// Hash only host-selected main-bundle regular files. Descriptor-relative walks
/// reject symlinks in every segment; no arbitrary path or recursive scanning.
enum BundleIntegrityVerifier {
  static let perFileLimit = 16 * 1024 * 1024
  static let totalLimit = 64 * 1024 * 1024

  static func verify(root: URL, files: [String: String]) -> LocalFinding {
    guard !files.isEmpty, files.count <= 32,
      files.allSatisfy({ RuntimePolicy.validPath($0.key) && RuntimePolicy.validHash($0.value) }) else {
      return .error("integrityPolicyInvalid")
    }
    let fd = open(root.resolvingSymlinksInPath().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { return .error("nativeFailure") }
    defer { close(fd) }
    var total = 0
    for path in files.keys.sorted() {
      if let failed = checkFile(root: fd, path: path, expected: files[path]!.lowercased(), total: &total) { return failed }
    }
    return LocalFinding(status: "notDetected", reason: "bundleBaselineMatched")
  }

  private static func checkFile(root: Int32, path: String, expected: String, total: inout Int) -> LocalFinding? {
    var fd = dup(root)
    guard fd >= 0 else { return .error("nativeFailure") }
    defer { close(fd) }
    let parts = path.components(separatedBy: "/")
    for (index, part) in parts.enumerated() {
      let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (index == parts.count - 1 ? O_NONBLOCK : O_DIRECTORY)
      let next = openat(fd, part, flags)
      guard next >= 0 else {
        switch errno {
        case ENOENT: return .signal(true, "integrityFileMissing")
        case ELOOP, ENOTDIR: return .signal(true, "integrityFileInvalid")
        case EACCES, EPERM: return .error("probeAccessRestricted")
        default: return .error("nativeFailure")
        }
      }
      close(fd); fd = next
    }
    // File-type metadata is confined to the host's app bundle (C617.1).
    var info = stat()
    guard fstat(fd, &info) == 0 else { return .error("nativeFailure") }
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return .signal(true, "integrityFileInvalid") }
    guard info.st_size <= perFileLimit else { return .error("scanLimitExceeded") }
    var hash = SHA256()
    var count = 0
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let readCount = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
      if readCount < 0 { return .error("nativeFailure") }
      if readCount == 0 { break }
      count += readCount; total += readCount
      if count > perFileLimit || total > totalLimit { return .error("scanLimitExceeded") }
      hash.update(data: Data(buffer.prefix(readCount)))
    }
    let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
    return actual == expected ? nil : .signal(true, "integrityFileMismatch")
  }
}
