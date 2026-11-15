import Foundation
import Darwin

/// Evaluates owned image values; live acquisition belongs to DyldImageSnapshot.
enum LoadedImageProbe {
  struct Image: Equatable {
    let header: UInt
    let path: String
  }
  static func scan(checkRoot: Bool, count: () -> UInt32,
                   image: (UInt32) -> Image?) -> LocalFinding {
    let initial = count()
    guard initial > 0 else { return .error("nativeFailure") }
    guard initial <= 4096 else { return .error("scanLimitExceeded") }
    var images: [Image] = []
    var bytes = 0
    var reason: String?
    for index in 0..<initial {
      guard let item = image(index), item.header != 0,
        RuntimePolicy.safeImagePath(item.path) else { return .error("nativeFailure") }
      bytes += item.path.utf8.count
      guard bytes <= 2 * 1024 * 1024 else { return .error("scanLimitExceeded") }
      images.append(item)
      if checkRoot {
        if RuntimePolicy.jailbreakImagePath(item.path) { reason = "jailbreakLoadedImage" }
      } else if RuntimePolicy.knownHookModule(item.path) { reason = "hookModule" }
      else if RuntimePolicy.injectionImagePath(item.path), reason == nil { reason = "injectedModulePath" }
    }
    guard count() == initial else { return .error("nativeFailure") }
    // Defend this evaluator against an inconsistent provider. Production passes
    // an immutable owned array and separately checks the dyld generation.
    for index in 0..<initial {
      guard let current = image(index), current == images[Int(index)] else { return .error("nativeFailure") }
    }
    guard count() == initial else { return .error("nativeFailure") }
    return .signal(reason != nil, reason ?? "hookModule")
  }
}
