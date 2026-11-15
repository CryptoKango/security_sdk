import Foundation

struct IOSIntegrityPolicy {
  let expectedApplicationId: String
  let files: [String: String]
  static func parse(_ raw: Any?) -> IOSIntegrityPolicy? {
    guard let map = raw as? [String: Any], let expected = map["expectedApplicationId"] as? String,
      !expected.isEmpty, expected.count <= 255,
      expected.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45,46,95].contains($0) }),
      let files = map["iosBundleFileSha256"] as? [String: String],
      !files.isEmpty, files.count <= 32,
      files.allSatisfy({ RuntimePolicy.validPath($0.key) && RuntimePolicy.validHash($0.value) }) else { return nil }
    return IOSIntegrityPolicy(expectedApplicationId: expected, files: files.mapValues { $0.lowercased() })
  }
}

enum RuntimePolicy {
  static let ids: Set<String> = ["root", "hook", "debugger", "appIntegrity", "multiInstance"]
  private static let modules: Set<String> = ["fridagadget.dylib", "libfrida-gadget.dylib",
    "frida-agent.dylib", "libfrida-agent.dylib", "mobilesubstrate.dylib", "cydiasubstrate",
    "substitute-loader.dylib", "libsubstitute.dylib", "libhooker.dylib", "ellekit.dylib", "libellekit.dylib"]
  static func knownHookModule(_ path: String) -> Bool {
    safeImagePath(path) && modules.contains((path as NSString).lastPathComponent.lowercased())
  }
  // Recognize actual loaded-image origins, never arbitrary app resource names.
  private static let prebootRoot = try! NSRegularExpression(
    pattern: "^/private/preboot/[a-fA-F0-9]{40,128}/(?:jb-[a-zA-Z0-9]{6}|dopamine-[a-zA-Z0-9]{6})/procursus/")
  static func jailbreakImagePath(_ path: String) -> Bool {
    guard safeImagePath(path) else { return false }
    return systemInjectionPath(path) || path.hasPrefix("/var/jb/") || path.hasPrefix("/private/var/jb/") ||
      prebootRoot.firstMatch(in:path, range:NSRange(path.startIndex..., in:path)) != nil
  }
  static func injectionImagePath(_ path: String) -> Bool {
    guard safeImagePath(path), path.hasSuffix(".dylib") else { return false }
    if systemInjectionPath(path) { return true }
    guard jailbreakImagePath(path) else { return false }
    let relative: String
    if path.hasPrefix("/var/jb/") { relative = String(path.dropFirst("/var/jb".count)) }
    else if path.hasPrefix("/private/var/jb/") { relative = String(path.dropFirst("/private/var/jb".count)) }
    else if let match = prebootRoot.firstMatch(in:path, range:NSRange(path.startIndex..., in:path)),
      let range = Range(match.range, in:path) { relative = "/" + path[range.upperBound...] }
    else { return false }
    return systemInjectionPath(relative)
  }
  private static func systemInjectionPath(_ path: String) -> Bool {
    guard path.hasSuffix(".dylib") else { return false }
    return path.hasPrefix("/Library/MobileSubstrate/DynamicLibraries/") ||
      path.hasPrefix("/usr/lib/TweakInject/") || path == "/usr/lib/ellekit/libinjector.dylib"
  }
  static func safeImagePath(_ path: String) -> Bool {
    path.hasPrefix("/") && path.utf8.count <= 4096 &&
      !path.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } &&
      path.dropFirst().components(separatedBy:"/").allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }
  static func validHash(_ hash: String) -> Bool {
    hash.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
  }
  static func validPath(_ path: String) -> Bool {
    !path.isEmpty && path.utf16.count <= 512 &&
      !path.unicodeScalars.contains { $0.value < 32 || $0.value == 127 || $0 == "\\" || $0 == ":" } &&
      path.components(separatedBy: "/").allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }
}
