import Foundation
import Darwin
import CryptoKit

@main
struct RuntimePolicyTests {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    try Data("abc".utf8).write(to: root.appendingPathComponent("fixture"))
    var passed = 0
    func test(_ name: String, _ body: () throws -> Bool) throws {
      guard try body() else { fatalError("FAILED: \(name)") }
      passed += 1; print("PASS: \(name)")
    }
    try test("stable resource baseline matches") {
      BundleIntegrityVerifier.verify(root: root, files: ["fixture":abc]).reason == "bundleBaselineMatched"
    }
    try test("modified resource is detected") {
      BundleIntegrityVerifier.verify(root: root, files: ["fixture":String(repeating:"0",count:64)]).reason == "integrityFileMismatch"
    }
    try test("missing resource is detected") {
      BundleIntegrityVerifier.verify(root: root, files: ["missing":abc]).reason == "integrityFileMissing"
    }
    try test("unsafe paths never reach filesystem reads") {
      ["../escape", "/absolute", "a//b", "a/./b", "a\\b", "a:b", "a\u{0}b"].allSatisfy {
        BundleIntegrityVerifier.verify(root: root, files: [$0:abc]).reason == "integrityPolicyInvalid"
      }
    }
    try FileManager.default.createSymbolicLink(atPath:root.appendingPathComponent("link").path,
      withDestinationPath:root.appendingPathComponent("fixture").path)
    try test("final symlink is rejected even when target is inside bundle") {
      BundleIntegrityVerifier.verify(root:root,files:["link":abc]).reason == "integrityFileInvalid"
    }
    try FileManager.default.createSymbolicLink(atPath:root.appendingPathComponent("directoryLink").path,withDestinationPath:root.path)
    try test("intermediate symlink is rejected") {
      BundleIntegrityVerifier.verify(root:root,files:["directoryLink/fixture":abc]).reason == "integrityFileInvalid"
    }
    try FileManager.default.createDirectory(at:root.appendingPathComponent("directory"),withIntermediateDirectories:true)
    try test("directory cannot masquerade as an empty file") {
      BundleIntegrityVerifier.verify(root:root,files:["directory":abc]).reason == "integrityFileInvalid"
    }
    guard mkfifo(root.appendingPathComponent("pipe").path, 0o600) == 0 else { fatalError("Fixture creation failed") }
    try test("FIFO is rejected without blocking") {
      BundleIntegrityVerifier.verify(root:root,files:["pipe":abc]).reason == "integrityFileInvalid"
    }
    try Data(repeating:0,count:BundleIntegrityVerifier.perFileLimit+1).write(to:root.appendingPathComponent("oversize"))
    try test("resource size limits produce unknown not clean") {
      BundleIntegrityVerifier.verify(root:root,files:["oversize":abc]).reason == "scanLimitExceeded"
    }
    let payload = Data(repeating:0, count:BundleIntegrityVerifier.perFileLimit)
    let payloadHash = SHA256.hash(data:payload).map { String(format:"%02x",$0) }.joined()
    let large = root.appendingPathComponent("large")
    try payload.write(to:large)
    var baseline: [String:String] = [:]
    for index in 0..<5 {
      let path = "large-\(index)"
      try FileManager.default.linkItem(at:large,to:root.appendingPathComponent(path))
      baseline[path] = payloadHash
    }
    try test("aggregate read budget is enforced across individually valid files") {
      BundleIntegrityVerifier.verify(root:root,files:baseline).reason == "scanLimitExceeded"
    }
    try test("native policy rejects missing hashes and normalizes valid baseline") {
      IOSIntegrityPolicy.parse(["expectedApplicationId":"bad\n", "iosBundleFileSha256":["fixture":abc]]) == nil &&
      IOSIntegrityPolicy.parse(["expectedApplicationId":"example.app", "iosBundleFileSha256":[String:String]()]) == nil &&
      IOSIntegrityPolicy.parse(["expectedApplicationId":"example.app", "iosBundleFileSha256":["fixture":abc.uppercased()]])?.files["fixture"] == abc
    }
    try test("hook module matching uses exact basenames") {
      RuntimePolicy.knownHookModule("/Library/FridaGadget.dylib") &&
      !RuntimePolicy.knownHookModule("/apps/frida/normal.dylib") &&
      !RuntimePolicy.knownHookModule("/Library/FridaGadget.dylib.backup")
    }
    try test("rootless loaded image origins include randomized preboot roots") {
      let preboot = "/private/preboot/" + String(repeating:"A",count:96)
      return RuntimePolicy.jailbreakImagePath("/var/jb/usr/lib/renamed.dylib") &&
        RuntimePolicy.jailbreakImagePath(preboot + "/dopamine-Ab12Cd/procursus/usr/lib/renamed.dylib") &&
        RuntimePolicy.jailbreakImagePath(preboot + "/jb-Ab12Cd/procursus/usr/lib/renamed.dylib")
    }
    try test("renamed tweak images are recognized only in injection directories") {
      RuntimePolicy.injectionImagePath("/Library/MobileSubstrate/DynamicLibraries/renamed.dylib") &&
        RuntimePolicy.injectionImagePath("/var/jb/usr/lib/TweakInject/renamed.dylib") &&
        !RuntimePolicy.injectionImagePath("/var/jb/usr/lib/ordinary.dylib")
    }
    try test("normal app bundles and incidental names are not jailbreak origins") {
      ["/var/containers/Bundle/Application/id/App.app/var/jb/library.dylib",
       "/var/containers/Bundle/Application/id/App.app/usr/lib/TweakInject/a.dylib",
       "/var/jb_backup/lib.dylib", "/private/preboot/normal/lib.dylib",
       "/var/jb/../normal/lib.dylib", "/var/jb//lib.dylib"].allSatisfy {
        !RuntimePolicy.jailbreakImagePath($0) && !RuntimePolicy.injectionImagePath($0)
      }
    }
    try test("preboot injection paths require the complete known layout") {
      let prefix = "/private/preboot/" + String(repeating:"a",count:96) + "/dopamine-123456/procursus"
      return RuntimePolicy.injectionImagePath(prefix + "/usr/lib/TweakInject/unknown.dylib") &&
        !RuntimePolicy.injectionImagePath(prefix + "/usr/lib/TweakInject/unknown.dylib.backup") &&
        !RuntimePolicy.jailbreakImagePath("/private/preboot/id/dopamine-123456/procursus/usr/lib/a.dylib")
    }
    try test("ElleKit exact module and injector origins") {
      RuntimePolicy.knownHookModule("/var/jb/usr/lib/libellekit.dylib") &&
        RuntimePolicy.injectionImagePath("/usr/lib/ellekit/libinjector.dylib") &&
        RuntimePolicy.injectionImagePath("/private/var/jb/usr/lib/ellekit/libinjector.dylib") &&
        RuntimePolicy.jailbreakImagePath("/usr/lib/ellekit/libinjector.dylib") &&
        RuntimePolicy.jailbreakImagePath("/Library/MobileSubstrate/DynamicLibraries/renamed.dylib")
    }
    try test("generic injector names and app paths are not system origins") {
      ["/App.app/libinjector.dylib", "/App.app/usr/lib/ellekit/libinjector.dylib",
        "/usr/lib/ellekit/libinjector.dylib.backup", "/usr/lib/ellekit/ordinary.dylib",
        "/usr/lib/TweakInject_backup/a.dylib"].allSatisfy {
        !RuntimePolicy.injectionImagePath($0) && !RuntimePolicy.jailbreakImagePath($0) && !RuntimePolicy.knownHookModule($0)
      }
    }
    try test("malformed module paths cannot bypass path validation") {
      ["libellekit.dylib", "/a/../libellekit.dylib", "/a//libellekit.dylib",
        "/a/\u{0}/libellekit.dylib", "/" + String(repeating:"a", count:4096) + "/libellekit.dylib"].allSatisfy {
        !RuntimePolicy.knownHookModule($0)
      }
    }
    try test("bounded C names preserve UTF8 and reject truncation or invalid bytes") {
      func decode(_ bytes: [UInt8]) -> String? {
        bytes.map { CChar(bitPattern:$0) }.withUnsafeBufferPointer { try? DyldImageSnapshot.name(address:UInt(bitPattern:$0.baseAddress!)) }
      }
      return decode(Array("/正常.dylib".utf8) + [0]) == "/正常.dylib" &&
        decode([0]) == nil && decode([47,255,0]) == nil &&
        decode(Array(repeating:65,count:4097)) == nil &&
        decode(Array(repeating:65,count:4096) + [0])?.count == 4096
    }
    let normal = LoadedImageProbe.Image(header:1,path:"/usr/lib/libSystem.B.dylib")
    let hook = LoadedImageProbe.Image(header:2,path:"/var/jb/usr/lib/libellekit.dylib")
    try test("stable snapshots retain independent root and hook reasons") {
      LoadedImageProbe.scan(checkRoot:false,count:{1},image:{_ in hook}).reason == "hookModule" &&
        LoadedImageProbe.scan(checkRoot:true,count:{1},image:{_ in hook}).reason == "jailbreakLoadedImage" &&
        LoadedImageProbe.scan(checkRoot:false,count:{1},image:{_ in normal}).status == "notDetected"
    }
    try test("empty oversized nil and invalid-header snapshots are unknown") {
      LoadedImageProbe.scan(checkRoot:false,count:{0},image:{_ in normal}).status == "error" &&
        LoadedImageProbe.scan(checkRoot:false,count:{4097},image:{_ in fatalError("must not read")}).reason == "scanLimitExceeded" &&
        LoadedImageProbe.scan(checkRoot:false,count:{1},image:{_ in nil}).status == "error" &&
        LoadedImageProbe.scan(checkRoot:false,count:{1},image:{_ in .init(header:0,path:normal.path)}).status == "error"
    }
    try test("same-count header or path replacement is not clean or positive") {
      [normal, LoadedImageProbe.Image(header:hook.header,path:normal.path),
        LoadedImageProbe.Image(header:99,path:hook.path)].allSatisfy { replacement in
        var reads = 0
        return LoadedImageProbe.scan(checkRoot:false,count:{1},image:{_ in
          reads += 1; return reads == 1 ? hook : replacement
        }).status == "error"
      }
    }
    try test("count changes in either verification phase invalidate findings") {
      [2,3].allSatisfy { phase in
        var counts = 0
        return LoadedImageProbe.scan(checkRoot:true,count:{
          counts += 1; return counts == phase ? 2 : 1
        },image:{_ in hook}).status == "error"
      }
    }
    try test("missing image after a hit and verification disappearance stay unknown") {
      let first = LoadedImageProbe.scan(checkRoot:false,count:{2},image:{ $0 == 0 ? hook : nil })
      var reads = 0
      let second = LoadedImageProbe.scan(checkRoot:false,count:{1},image:{_ in
        reads += 1; return reads == 1 ? hook : nil
      })
      return first.status == "error" && second.status == "error"
    }
    try test("aggregate image path budget stops bounded but excessive snapshots") {
      let large = LoadedImageProbe.Image(header:1,path:"/" + String(repeating:"a",count:4095))
      return LoadedImageProbe.scan(checkRoot:true,count:{513},image:{_ in large}).reason == "scanLimitExceeded"
    }
    print("\(passed) native Swift policy tests passed")
  }
}
