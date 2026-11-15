import Foundation

@main
struct MachOExecutablePolicyTests {
  static func main() {
    let cpu: UInt32 = 0x0100000c
    func word(_ x: UInt32, _ big: Bool) -> [UInt8] {
      (0..<4).map { UInt8(truncatingIfNeeded:x >> ((big ? 3 - $0 : $0) * 8)) }
    }
    func thin(_ type: UInt32, big: Bool = false, wide: Bool = true, target: UInt32 = 0x0100000c) -> [UInt8] {
      var words: [UInt32] = [wide ? 0xfeedfacf : 0xfeedface, target, 0, type, 0, 0, 0]
      if wide { words.append(0) }
      return words.flatMap { word($0, big) }
    }
    func classify(_ data: [UInt8], target: UInt32 = 0x0100000c) -> MachOExecutablePolicy.Kind {
      MachOExecutablePolicy.classify(size:UInt64(data.count), cpu:target) { offset, count in
        guard offset <= data.count, UInt64(count) <= UInt64(data.count) - offset else { return nil }
        return Array(data[Int(offset)..<Int(offset)+count])
      }
    }
    var passed = 0
    func test(_ name: String, _ body: () -> Bool) {
      guard body() else { fatalError("FAILED: \(name)") }
      passed += 1; print("PASS: \(name)")
    }
    test("thin executable and library headers are distinct in either byte order") {
      [false,true].allSatisfy { big in [false,true].allSatisfy { wide in
        let target: UInt32 = wide ? cpu : 12
        return classify(thin(2,big:big,wide:wide,target:target),target:target) == .application &&
          classify(thin(6,big:big,wide:wide,target:target),target:target) == .library
      } }
    }
    test("wrong CPU and unknown file types remain unsupported") {
      classify(thin(2,target:7)) == .unsupported && classify(thin(8)) == .unsupported
    }
    test("truncated headers and impossible command sizes are invalid") {
      var bad = thin(2); bad.replaceSubrange(16..<20, with:word(10,false))
      return classify([]) == .invalid && classify(Array(thin(2).prefix(16))) == .invalid &&
        classify(bad) == .invalid && classify(thin(6,wide:false)) == .invalid
    }
    test("fat32 selected CPU slice is checked within file bounds") {
      let payload = thin(6)
      let bytes = word(0xcafebabe,true) + word(1,true) +
        [cpu,0,28,UInt32(payload.count),0].flatMap { word($0,true) } + payload
      return classify(bytes) == .library
    }
    test("fat64 little endian table is supported") {
      let payload = thin(2)
      let bytes = word(0xcafebabf,false) + word(1,false) +
        [cpu,0,40,0,UInt32(payload.count),0,0,0].flatMap { word($0,false) } + payload
      return classify(bytes) == .application
    }
    test("fat offsets outside file and overbudget tables never become clean") {
      let outside = word(0xcafebabe,true) + word(1,true) + [cpu,0,500,32,0].flatMap { word($0,true) }
      return classify(outside) == .invalid && classify(word(0xcafebabe,true) + word(17,true)) == .unsupported
    }
    test("multiple matching subtypes are not guessed") {
      let payload = thin(2)
      let records = [cpu,0,48,32,0,cpu,2,80,32,0].flatMap { word($0,true) }
      return classify(word(0xcafebabe,true) + word(2,true) + records + payload + payload) == .unsupported
    }
    print("\(passed) Mach-O header tests passed")
  }
}
