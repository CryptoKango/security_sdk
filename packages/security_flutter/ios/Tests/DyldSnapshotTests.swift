import Foundation
import Darwin
import MachO

@main struct DyldSnapshotTests {
  static func main() throws {
    var passed = 0
    func test(_ name: String, _ body: () throws -> Bool) rethrows {
      guard try body() else { fatalError("FAILED: \(name)") }
      passed += 1; print("PASS: \(name)")
    }
    typealias Probe = DyldImageSnapshot
    let base = Probe.Metadata(address: 1, version: 17, count: 1, array: 2, generation: 3)
    let hook = LoadedImageProbe.Image(header: 4, path: "/var/jb/usr/lib/libellekit.dylib")
    test("owned stable generation preserves finding") {
      Probe.scan(checkRoot: true, state: { base }, read: { _ in [hook] }).reason == "jailbreakLoadedImage"
    }
    test("ABA count and address reuse cannot hide generation changes") {
      var reads = 0
      return Probe.scan(checkRoot: false, state: {
        reads += 1
        return reads == 1 ? base : .init(address:1,version:17,count:1,array:2,generation:4)
      }, read: { _ in [hook] }).status == "error"
    }
    test("late change during classification cannot return a positive") {
      var reads = 0
      return Probe.scan(checkRoot: true, state: {
        reads += 1
        return reads < 3 ? base : .init(address:1,version:17,count:1,array:2,generation:4)
      }, read: { _ in [hook] }).status == "error"
    }
    test("busy unpublished arrays and budget excess never invoke reader") {
      let busy = Probe.Metadata(address:1,version:17,count:1,array:0,generation:3)
      let huge = Probe.Metadata(address:1,version:17,count:4097,array:2,generation:3)
      return Probe.scan(checkRoot:false,state:{busy},read:{_ in fatalError("read")}).status == "error" &&
        Probe.scan(checkRoot:false,state:{huge},read:{_ in fatalError("read")}).reason == "scanLimitExceeded"
    }
    test("partial and restricted copies cannot become clean") {
      Probe.scan(checkRoot:false,state:{base},read:{_ in []}).status == "error" &&
        Probe.scan(checkRoot:false,state:{base},read:{_ in throw Probe.Failure.restricted}).reason == "probeAccessRestricted"
    }
    try test("system separator aliases normalize without accepting traversal") {
      try Probe.normalizedPath("/usr/lib//ordinary.dylib") == "/usr/lib/ordinary.dylib" &&
        (try? Probe.normalizedPath("/var/jb/../ordinary.dylib")) == nil &&
        (try? Probe.normalizedPath("relative.dylib")) == nil
    }
    let size = Int(vm_page_size)
    let region = mmap(nil, size * 2, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)!
    guard region != MAP_FAILED else { fatalError("mmap") }
    defer { munmap(region, size * 2) }
    guard mprotect(region.advanced(by:size), size, PROT_NONE) == 0 else { fatalError("mprotect") }
    let end = region.advanced(by:size - 4).assumingMemoryBound(to:UInt8.self)
    end[0] = 47; end[1] = 97; end[2] = 98; end[3] = 0
    try test("name terminator on last readable byte does not cross protected page") {
      try Probe.name(address:UInt(bitPattern:end)) == "/ab"
    }
    test("protected and unmapped addresses return errors without dereference") {
      (try? Probe.name(address:UInt(bitPattern:region.advanced(by:size)))) == nil &&
        (try? Probe.name(address:1)) == nil
    }
    let dead = mmap(nil,size,PROT_READ | PROT_WRITE,MAP_ANON | MAP_PRIVATE,-1,0)!
    guard dead != MAP_FAILED, munmap(dead,size) == 0 else { fatalError("unmap") }
    test("released memory is copied through kernel and rejected") {
      (try? Probe.name(address:UInt(bitPattern:dead))) == nil
    }
    // A real, unloadable C-only dylib (no ObjC/Swift pinning) is supplied by script.
    let library = URL(fileURLWithPath:CommandLine.arguments[1]).resolvingSymlinksInPath().path
    func isFixture(_ image: LoadedImageProbe.Image) -> Bool {
      URL(fileURLWithPath:image.path).resolvingSymlinksInPath().path == library
    }
    let before = try Probe.metadata()
    guard let handle = dlopen(library, RTLD_NOW | RTLD_LOCAL) else { fatalError("dlopen") }
    let loaded = try Probe.metadata()
    let captured = try Probe.images(loaded)
    guard dlclose(handle) == 0 else { fatalError("dlclose") }
    let unloaded = try Probe.metadata()
    test("real load and unload advance generation and remove fixture") {
      before.generation != loaded.generation && loaded.generation != unloaded.generation &&
        captured.contains(where:isFixture) &&
        !(try! Probe.images(unloaded)).contains(where:isFixture)
    }
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
      for _ in 0..<1000 {
        guard let h = dlopen(library,RTLD_NOW | RTLD_LOCAL), dlclose(h) == 0 else { fatalError("churn") }
        usleep(50)
      }
      group.leave()
    }
    var clean = 0, unknown = 0
    for _ in 0..<300 {
      let finding = Probe.scan(checkRoot:false)
      if finding.status == "notDetected" { clean += 1 }
      else if finding.status == "error" { unknown += 1 }
      else { fatalError("normal dylib churn must not create risk") }
    }
    test("real concurrent loader churn completes without risk positives") {
      group.wait(timeout:.now()+30) == .success && clean + unknown == 300
    }
    // Warmed-up quiescent scan must work, not merely turn all scans into errors.
    let quiet = Probe.scan(checkRoot:false)
    test("quiescent real process scan remains usable") { quiet.status == "notDetected" }
    print("churn scans: clean=\(clean), unknown=\(unknown)")
    print("\(passed) dyld snapshot tests passed")
  }
}
