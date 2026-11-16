import 'package:security_core/security_core.dart';

/// Optional in schema v1 for compatibility with earlier native implementations.
/// Only allow measured booleans and bounded settings; never forward raw strings.
Map<String, Object?> decodeLocalValues(
  String id,
  DetectionStatus status,
  FindingReason? reason,
  Object? raw,
) {
  if (raw == null) return const {};
  Never invalid() =>
      throw const SecurityFailure(SecurityErrorCode.invalidResponse);
  if (raw is! Map || raw.length > 16) {
    invalid();
  }
  final allowed = <String>{
    'signalDetected',
    ...switch (id) {
      SecurityDetectors.developerMode || SecurityDetectors.usbDebugging => {
        'settingValue',
        'settingPresent',
        'settingValueValid',
      },
      SecurityDetectors.accessibility => {
        'accessibilityEnabled',
        'voiceOverEnabled',
        'switchControlEnabled',
      },
      SecurityDetectors.screenshot => {
        'screenshotObserved',
        'observationActive',
      },
      SecurityDetectors.vpn => {'activeNetworkAvailable', 'vpnTransport'},
      SecurityDetectors.proxy => {
        'hostProxyConfigured',
        'httpProxyEnabled',
        'pacProxyConfigured',
      },
      SecurityDetectors.debugger => {
        'javaDebuggerConnected',
        'waitingForDebugger',
        'processTraced',
      },
      _ => <String>{},
    },
  };
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || !allowed.contains(key)) {
      invalid();
    }
    if (key == 'settingValue') {
      if (value != null && !(value is int && (value == 0 || value == 1))) {
        invalid();
      }
    } else if (!(value is bool ||
        (value == null &&
            (key == 'httpProxyEnabled' || key == 'pacProxyConfigured')))) {
      invalid();
    }
    result[key] = value;
  }
  if (result.containsKey('signalDetected') &&
      ((status != DetectionStatus.detected &&
              status != DetectionStatus.notDetected) ||
          result['signalDetected'] != (status == DetectionStatus.detected))) {
    invalid();
  }
  if (result.containsKey('screenshotObserved') ||
      result.containsKey('observationActive')) {
    if (!result.containsKey('screenshotObserved') ||
        !result.containsKey('observationActive')) {
      invalid();
    }
    if (result['observationActive'] == true) {
      if ((status != DetectionStatus.detected &&
              status != DetectionStatus.notDetected) ||
          result['screenshotObserved'] !=
              (status == DetectionStatus.detected)) {
        invalid();
      }
    } else if (status != DetectionStatus.error ||
        reason != FindingReason.observationInterrupted) {
      invalid();
    }
  }
  if (result.keys.any((key) => key.startsWith('setting'))) {
    if (!result.keys.toSet().containsAll({
      'settingValue',
      'settingPresent',
      'settingValueValid',
    })) {
      invalid();
    }
    final value = result['settingValue'];
    if (result['settingValueValid'] != (value != null) ||
        (value != null && result['settingPresent'] != true)) {
      invalid();
    }
    if (value == 1 && status != DetectionStatus.detected) {
      invalid();
    }
    if (value == 0 &&
        (status != DetectionStatus.unsupported ||
            reason != FindingReason.settingReadRestricted)) {
      invalid();
    }
    if (value == null &&
        (status != DetectionStatus.error ||
            reason != FindingReason.settingValueUnavailable)) {
      invalid();
    }
  }
  if (result['activeNetworkAvailable'] == false &&
      (reason != FindingReason.noActiveNetwork ||
          result.containsKey('vpnTransport'))) {
    invalid();
  }
  return Map.unmodifiable(result);
}
