import Foundation

/// Validate metadata before querying sourceInformation or reporting any verdict.
enum LocationMetadataPolicy {
  static func metadata(age: Double, accuracy: Double, source: () -> Bool?) -> [String: Any]? {
    let milliseconds = age * 1000
    guard age.isFinite, age >= 0, milliseconds.isFinite,
      accuracy.isFinite, accuracy >= 0 else { return nil }
    return ["isMocked": source().map { $0 as Any } ?? NSNull(), "ageMilliseconds": milliseconds]
  }
}
