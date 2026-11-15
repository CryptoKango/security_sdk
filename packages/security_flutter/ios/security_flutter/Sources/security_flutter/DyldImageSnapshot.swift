import Foundation
import Darwin
import MachO

/// Copies only this task's published dyld metadata. Foreign pointers are addresses,
/// never dereferenced by Swift. VM copy failures remain unknown, not risk signals.
enum DyldImageSnapshot {
  enum Failure: Error { case unavailable, limit, restricted }
  struct Metadata: Equatable {
    let address: UInt
    let version: UInt32
    let count: UInt32
    let array: UInt
    let generation: UInt64
  }
  static func copy(address: UInt, into buffer: UnsafeMutableRawBufferPointer) throws {
    guard address > 0, let target = buffer.baseAddress, buffer.count > 0,
      address <= UInt.max - UInt(buffer.count) else { throw Failure.unavailable }
    var copied: vm_size_t = 0
    let status = vm_read_overwrite(mach_task_self_, vm_address_t(address), vm_size_t(buffer.count),
      vm_address_t(UInt(bitPattern: target)), &copied)
    guard status == KERN_SUCCESS, copied == buffer.count else {
      if status == KERN_PROTECTION_FAILURE { throw Failure.restricted }
      throw Failure.unavailable
    }
  }
  static func name(address: UInt) throws -> String {
    var bytes: [UInt8] = []
    // Never cross a VM page boundary: a terminator at the last mapped byte is valid.
    let page = UInt(vm_page_size)
    guard page > 0 else { throw Failure.unavailable }
    while bytes.count < 4097 {
      guard address <= UInt.max - UInt(bytes.count) else { throw Failure.unavailable }
      let cursor = address + UInt(bytes.count)
      let size = min(256, 4097 - bytes.count, Int(page - cursor % page))
      var chunk = [UInt8](repeating: 0, count: size)
      try chunk.withUnsafeMutableBytes { try copy(address: cursor, into: $0) }
      if let end = chunk.firstIndex(of: 0) {
        bytes.append(contentsOf: chunk[..<end])
        guard !bytes.isEmpty, bytes.count <= 4096,
          let value = String(bytes: bytes, encoding: .utf8) else { throw Failure.unavailable }
        return value
      }
      bytes.append(contentsOf: chunk)
    }
    throw Failure.limit
  }
  static func metadata() throws -> Metadata {
    var task = task_dyld_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_dyld_info_data_t>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &task) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_DYLD_INFO), $0, &count)
      }
    }
    let required = MemoryLayout<dyld_all_image_infos>.offset(of: \.infoArrayChangeTimestamp)! + MemoryLayout<UInt64>.size
    guard status == KERN_SUCCESS, count == MemoryLayout<task_dyld_info_data_t>.size / 4,
      task.all_image_info_format == TASK_DYLD_ALL_IMAGE_INFO_64,
      task.all_image_info_size >= required else { throw Failure.unavailable }
    var info = dyld_all_image_infos()
    try withUnsafeMutableBytes(of: &info) {
      try copy(address: UInt(task.all_image_info_addr), into: UnsafeMutableRawBufferPointer(rebasing: $0[..<required]))
    }
    // Known public layouts only; future/old layouts are not guessed.
    guard (15...18).contains(info.version), info.infoArrayChangeTimestamp != 0,
      let array = info.infoArray else { throw Failure.unavailable }
    return Metadata(address: UInt(task.all_image_info_addr), version: info.version,
      count: info.infoArrayCount, array: UInt(bitPattern: array), generation: info.infoArrayChangeTimestamp)
  }
  static func normalizedPath(_ path: String) throws -> String {
    // dyld metadata can contain redundant separators for ordinary system images.
    // Normalize only that lexical alias; never resolve symlinks or dot traversal.
    guard path.hasPrefix("/"), path.utf8.count <= 4096 else { throw Failure.unavailable }
    let value = "/" + path.split(separator:"/", omittingEmptySubsequences:true).joined(separator:"/")
    guard RuntimePolicy.safeImagePath(value) else { throw Failure.unavailable }
    return value
  }
  static func images(_ info: Metadata) throws -> [LoadedImageProbe.Image] {
    guard info.count > 0, info.count <= 4096 else { throw Failure.limit }
    var entries = [dyld_image_info](repeating: dyld_image_info(), count: Int(info.count))
    try entries.withUnsafeMutableBytes { try copy(address: info.array, into: $0) }
    var result: [LoadedImageProbe.Image] = []
    var total = 0
    for entry in entries {
      guard let header = entry.imageLoadAddress, let path = entry.imageFilePath else { throw Failure.unavailable }
      let value = try normalizedPath(name(address: UInt(bitPattern: path)))
      total += value.utf8.count
      guard total <= 2 * 1024 * 1024 else { throw Failure.limit }
      result.append(.init(header: UInt(bitPattern: header), path: value))
    }
    return result
  }
  static func scan(checkRoot: Bool, state: () throws -> Metadata = metadata,
                   read: (Metadata) throws -> [LoadedImageProbe.Image] = images) -> LocalFinding {
    do {
      let before = try state()
      guard before.count > 0, before.array != 0, before.generation != 0 else { throw Failure.unavailable }
      guard before.count <= 4096 else { throw Failure.limit }
      let owned = try read(before)
      guard owned.count == Int(before.count), try state() == before else { throw Failure.unavailable }
      let finding = LoadedImageProbe.scan(checkRoot: checkRoot, count: { before.count }, image: { owned[Int($0)] })
      guard try state() == before else { throw Failure.unavailable }
      return finding
    } catch Failure.limit { return .error("scanLimitExceeded")
    } catch Failure.restricted { return .error("probeAccessRestricted")
    } catch { return .error("nativeFailure") }
  }
}
