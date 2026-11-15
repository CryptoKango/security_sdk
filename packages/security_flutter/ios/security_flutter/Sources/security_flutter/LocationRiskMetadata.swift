import CoreLocation

/// Adapts a location already obtained by an authorized host business flow.
/// No CLLocationManager, permission request or position acquisition is started.
/// Invalid accuracy/age returns nil; absent source metadata remains NSNull.
public enum LocationRiskMetadata {
  public static func fromLocation(_ location: CLLocation) -> [String: Any]? {
    LocationMetadataPolicy.metadata(age: Date().timeIntervalSince(location.timestamp),
      accuracy: location.horizontalAccuracy) {
      if #available(iOS 15.0, *), let source = location.sourceInformation {
        return source.isSimulatedBySoftware
      }
      // iOS 13–14 or absent source metadata: unknown, never default false.
      // Accessory location alone is not a simulation or fraud signal.
      return nil
    }
  }
}
