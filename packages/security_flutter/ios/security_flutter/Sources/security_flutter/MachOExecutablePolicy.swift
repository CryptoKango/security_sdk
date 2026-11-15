import Foundation

/// Reads only bounded Mach-O header metadata; no segments, symbols or code bytes.
enum MachOExecutablePolicy {
  enum Kind { case application, library, unsupported, invalid }
  static func classify(size: UInt64, cpu: UInt32, read: (UInt64, Int) -> [UInt8]?) -> Kind {
    guard let prefix = read(0, 8), prefix.count == 8 else { return .invalid }
    let magic = number(prefix, 0, big: true)
    if [0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca].contains(magic) {
      let big = magic == 0xcafebabe || magic == 0xcafebabf
      let wide = magic == 0xcafebabf || magic == 0xbfbafeca
      let count = number(prefix, 4, big: big)
      guard count > 0 else { return .invalid }
      guard count <= 16 else { return .unsupported }
      let stride = wide ? 32 : 20
      let tableSize = Int(count) * stride
      guard size >= UInt64(8 + tableSize), let table = read(8, tableSize), table.count == tableSize else { return .invalid }
      var selected: (UInt64, UInt64)?
      for i in 0..<Int(count) {
        let at = i * stride
        let offset = wide ? number64(table, at + 8, big: big) : UInt64(number(table, at + 8, big: big))
        let length = wide ? number64(table, at + 16, big: big) : UInt64(number(table, at + 12, big: big))
        guard offset >= UInt64(8 + tableSize), offset <= size, length <= size - offset, length >= 28 else { return .invalid }
        if number(table, at, big: big) == cpu {
          // Multiple CPU subtypes are not guessed. No silent wrong-slice verdict.
          guard selected == nil else { return .unsupported }
          selected = (offset, length)
        }
      }
      guard let (offset, length) = selected else { return .unsupported }
      return thin(offset:offset, size:length, cpu:cpu, read:read)
    }
    return thin(offset:0, size:size, cpu:cpu, read:read)
  }

  private static func thin(offset: UInt64, size: UInt64, cpu: UInt32, read: (UInt64, Int) -> [UInt8]?) -> Kind {
    guard let prefix = read(offset, 8), prefix.count == 8 else { return .invalid }
    let magic = number(prefix, 0, big: true)
    let wide = magic == 0xcffaedfe || magic == 0xfeedfacf
    guard wide || magic == 0xcefaedfe || magic == 0xfeedface else { return .unsupported }
    let big = magic == 0xfeedface || magic == 0xfeedfacf
    let bytes = wide ? 32 : 28
    guard size >= UInt64(bytes), let header = read(offset, bytes), header.count == bytes else { return .invalid }
    guard number(header, 4, big:big) == cpu else { return .unsupported }
    guard wide == (cpu & 0x01000000 != 0) else { return .invalid }
    let commands = number(header, 16, big:big)
    let commandBytes = number(header, 20, big:big)
    guard UInt64(commandBytes) <= size - UInt64(bytes), UInt64(commands) * 8 <= UInt64(commandBytes) else { return .invalid }
    switch number(header, 12, big:big) {
    case 2: return .application // MH_EXECUTE
    case 6: return .library     // MH_DYLIB
    default: return .unsupported
    }
  }
  private static func number(_ b: [UInt8], _ i: Int, big: Bool) -> UInt32 {
    let part = Array(b[i..<i+4])
    return (big ? part : Array(part.reversed())).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
  }
  private static func number64(_ b: [UInt8], _ i: Int, big: Bool) -> UInt64 {
    let part = Array(b[i..<i+8])
    return (big ? part : Array(part.reversed())).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  }
}
