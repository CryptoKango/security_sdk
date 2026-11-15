import Foundation
import Darwin

@main
struct IOSContainerProbeTests {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let home = root.appendingPathComponent("Data/Home")
    let host = root.appendingPathComponent("Installed/Host.app")
    let process = host.appendingPathComponent("Host")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    #if arch(arm64)
    let cpu: UInt32 = 0x0100000c
    #else
    let cpu: UInt32 = 0x01000007
    #endif
    func header(_ type: UInt32) -> Data {
      let words: [UInt32] = [0xfeedfacf, cpu, 0, type, 0, 0, 0, 0]
      return Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    }
    func executable(_ bundle: URL, _ name: String = "Guest") throws -> URL {
      try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
      let url = bundle.appendingPathComponent(name)
      try header(2).write(to: url)
      return url
    }
    _ = try executable(host, "Host")
    defer { try? FileManager.default.removeItem(at: root) }
    var passed = 0
    func test(_ name: String, _ body: () throws -> Bool) throws {
      guard try body() else { fatalError("FAILED: \(name)") }
      passed += 1; print("PASS: \(name)")
    }
    func check(_ b: URL, _ e: URL, _ p: URL = process) -> LocalFinding {
      IOSContainerProbe.evaluate(bundle: b, executable: e, processExecutable: p, home: home)
    }
    try test("normal app execution has no container evidence") { check(host, process).status == "notDetected" }
    try test("legitimate sandbox guest layout plus different file identities is required") {
      for directory in ["Documents", "Library", "tmp"] {
        let guest = home.appendingPathComponent(directory + "/Apps/Guest.app")
        let binary = try executable(guest)
        if check(guest, binary).reason != "embeddedAppBundle" { return false }
      }
      return true
    }
    try test("unexplained mismatch outside own data area remains error") {
      let other = root.appendingPathComponent("Installed/Other.app")
      return check(other, try executable(other)).reason == "processIdentityMismatch"
    }
    try test("similar home prefix cannot create a container positive") {
      let other = URL(fileURLWithPath:home.path + "Backup/Documents/Other.app")
      return check(other, try executable(other)).status == "error"
    }
    try test("symlink spelling of a normal executable does not cause a mismatch") {
      let alias = host.appendingPathComponent("Alias")
      try FileManager.default.createSymbolicLink(at:alias, withDestinationURL:process)
      return check(host, alias).status == "notDetected"
    }
    try test("same inode through hardlinks is not different executable identity") {
      let guest = home.appendingPathComponent("Documents/Linked.app")
      try FileManager.default.createDirectory(at:guest, withIntermediateDirectories:true)
      let linked = guest.appendingPathComponent("Linked")
      try FileManager.default.linkItem(at:process, to:linked)
      return check(guest, linked).status == "notDetected"
    }
    try test("missing or nonregular executable is unknown") {
      let directory = host.appendingPathComponent("directory")
      try FileManager.default.createDirectory(at:directory, withIntermediateDirectories:true)
      return check(host, host.appendingPathComponent("missing")).status == "error" &&
        check(host, directory).status == "error"
    }
    try test("FIFO executable metadata is rejected without a blocking read") {
      let pipe = host.appendingPathComponent("pipe")
      guard mkfifo(pipe.path, 0o600) == 0 else { return false }
      return check(host, pipe).reason == "processIdentityUnavailable"
    }
    try test("extensions and non-app hosts are unsupported, not clones") {
      let extensionBundle = root.appendingPathComponent("Extension.appex")
      let binary = try executable(extensionBundle)
      return check(extensionBundle,binary,binary).reason == "unsupportedProcess"
    }
    try test("same sandbox development host mismatch lacks separate host evidence") {
      let embeddedHost = home.appendingPathComponent("Library/DevHost.app")
      let binary = try executable(embeddedHost)
      let guest = home.appendingPathComponent("Documents/Guest.app")
      return check(guest, try executable(guest), binary).reason == "processIdentityMismatch"
    }
    try test("bundle-executable relationship must be coherent") {
      let other = root.appendingPathComponent("Installed/Unrelated.app")
      let binary = try executable(other)
      return check(host, binary).reason == "processIdentityMismatch"
    }
    try test("unsupported URL schemes fail before filesystem access") {
      IOSContainerProbe.evaluate(bundle:host, executable:process, processExecutable:process,
        home:URL(string:"https://invalid.example/")!).reason == "processIdentityUnavailable"
    }
    try test("APPL main executable as dylib remains observable even when paths agree") {
      let guest = home.appendingPathComponent("Documents/Patched.app")
      let binary = try executable(guest)
      try header(6).write(to:binary)
      return check(guest, binary, binary).reason == "appExecutableIsLibrary"
    }
    try test("normal app may contain arbitrary libraries without being a clone") {
      let library = host.appendingPathComponent("Host.debug.dylib")
      try header(6).write(to:library)
      return check(host, process).status == "notDetected"
    }
    try test("framework packages and unknown headers do not become clone positives") {
      let framework = root.appendingPathComponent("Library.framework")
      let binary = try executable(framework)
      try header(6).write(to:binary)
      let notApp = IOSContainerProbe.evaluate(bundle:framework, executable:binary,
        processExecutable:process, home:home, packageType:"FMWK")
      let unknown = host.appendingPathComponent("Unknown")
      try Data(repeating:0,count:32).write(to:unknown)
      return notApp.status == "unsupported" && check(host, unknown, unknown).reason == "executableFormatUnavailable"
    }
    print("\(passed) iOS container probe tests passed")
  }
}
