import 'models.dart';

enum DevicePlatform { android, ios }

enum DeviceInfoStatus { available, unsupported, error }

/// Basic OS-provided descriptors, not a device identifier or fingerprint.
final class DeviceInfo {
  DeviceInfo({
    required this.platform,
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.systemVersion,
    this.apiLevel,
  }) {
    for (final value in [manufacturer, brand, model, systemVersion]) {
      if (value.trim().isEmpty ||
          value.length > 256 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
      }
    }
    if ((platform == DevicePlatform.android &&
            (apiLevel == null || apiLevel! <= 0)) ||
        (platform == DevicePlatform.ios && apiLevel != null)) {
      throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
    }
  }
  final DevicePlatform platform;
  final String manufacturer;
  final String brand;

  /// Android Build.MODEL; iOS uname machine (simulators report host architecture).
  final String model;
  final String systemVersion;

  /// Android API level only. iOS has no equivalent and returns null.
  final int? apiLevel;
  @override
  String toString() => 'DeviceInfo(${platform.name})';
}

final class DeviceInfoResult {
  const DeviceInfoResult.available(DeviceInfo value)
    : status = DeviceInfoStatus.available,
      info = value,
      code = null;
  const DeviceInfoResult.unsupported()
    : status = DeviceInfoStatus.unsupported,
      info = null,
      code = SecurityErrorCode.unsupported;
  const DeviceInfoResult.failure(SecurityErrorCode value)
    : status = DeviceInfoStatus.error,
      info = null,
      code = value;
  final DeviceInfoStatus status;
  final DeviceInfo? info;
  final SecurityErrorCode? code;
  @override
  String toString() => 'DeviceInfoResult(${status.name})';
}

/// Aggregates independent observations; not an atomic OS snapshot or a verdict.
final class DeviceSecurityReport {
  DeviceSecurityReport({
    required this.device,
    required Iterable<DetectorCapability> capabilities,
    required this.security,
  }) : capabilities = List.unmodifiable(capabilities);
  final DeviceInfoResult device;
  final List<DetectorCapability> capabilities;
  final SecuritySnapshot security;
  @override
  String toString() =>
      'DeviceSecurityReport(findings: ${security.findings.length})';
}
