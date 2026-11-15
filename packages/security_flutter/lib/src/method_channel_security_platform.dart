import 'dart:math';

import 'package:flutter/services.dart';
import 'package:security_core/security_core.dart';

import 'security_platform.dart';
import 'local_finding_contract.dart';
import 'local_finding_values.dart';

final class MethodChannelSecurityPlatform
    implements SecurityPlatform, ScreenshotObservationPlatform {
  MethodChannelSecurityPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('security_sdk/local/v1');
  final MethodChannel _channel;
  final String _owner = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  bool _captureAttempted = false;
  int _captureRevision = 0;
  bool _disposed = false;

  Future<Map<Object?, Object?>> _invoke(String method, [Object? args]) async {
    try {
      final response = await _channel.invokeMethod<Object?>(method, args);
      if (response is! Map ||
          response['schemaVersion'] is! int ||
          response['schemaVersion'] != 1) {
        throw const SecurityFailure(SecurityErrorCode.invalidResponse);
      }
      return Map<Object?, Object?>.from(response);
    } on MissingPluginException {
      throw const SecurityFailure(SecurityErrorCode.platformUnavailable);
    } on PlatformException catch (error) {
      throw SecurityFailure(
        error.code == 'unsupported'
            ? SecurityErrorCode.unsupported
            : SecurityErrorCode.platformUnavailable,
      );
    }
  }

  @override
  Future<List<DetectorCapability>> capabilities() async {
    final response = await _invoke('capabilities');
    final raw = response['capabilities'];
    if (raw is! List) _invalid();
    final ids = <String>{};
    final result = <DetectorCapability>[];
    for (final item in raw) {
      if (item is! Map ||
          item['id'] is! String ||
          (item['id'] as String).isEmpty ||
          item['supported'] is! bool ||
          (item.containsKey('requiresExplicitOptIn') &&
              item['requiresExplicitOptIn'] is! bool) ||
          !ids.add(item['id'] as String)) {
        _invalid();
      }
      result.add(
        DetectorCapability(
          id: item['id'] as String,
          supported: item['supported'] as bool,
          requiresExplicitOptIn:
              item['requiresExplicitOptIn'] as bool? ?? false,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  @override
  Future<SecuritySnapshot> scan(ScanRequest request) async {
    final response = await _invoke('scan', {
      'owner': _owner,
      'contextId': request.contextId,
      'detectorIds': request.detectorIds,
      if (request.detectorIds.contains(SecurityDetectors.debugger) &&
          request.iosDebuggerMode != IosDebuggerMode.debugBuildOnly)
        'iosDebuggerMode': request.iosDebuggerMode.name,
      if (request.detectorIds.contains(SecurityDetectors.appIntegrity) &&
          request.integrityPolicy != null)
        'integrityPolicy': {
          'expectedApplicationId':
              request.integrityPolicy!.expectedApplicationId,
          'androidSignerSha256Sets':
              request.integrityPolicy!.androidSignerSha256Sets,
          'iosBundleFileSha256': request.integrityPolicy!.iosBundleFileSha256,
        },
    });
    final raw = response['findings'];
    if (response['contextId'] != request.contextId || raw is! List) _invalid();
    final remaining = request.detectorIds.toSet();
    final findings = <SecurityFinding>[];
    for (final item in raw) {
      if (item is! Map ||
          item['detectorId'] is! String ||
          !remaining.remove(item['detectorId']) ||
          item['detectorVersion'] is! String ||
          (item['detectorVersion'] as String).isEmpty) {
        _invalid();
      }
      final statuses = DetectionStatus.values.where(
        (s) => s.name == item['status'],
      );
      if (statuses.isEmpty) _invalid();
      FindingReason? reason;
      if (item['reason'] != null) {
        final reasons = FindingReason.values.where(
          (r) => r.name == item['reason'],
        );
        if (reasons.isEmpty) _invalid();
        reason = reasons.single;
      }
      if (!validLocalFinding(
        item['detectorId'] as String,
        statuses.single,
        reason,
      )) {
        _invalid();
      }
      findings.add(
        SecurityFinding.withValues(
          detectorId: item['detectorId'] as String,
          detectorVersion: item['detectorVersion'] as String,
          status: statuses.single,
          reason: reason,
          values: decodeLocalValues(
            item['detectorId'] as String,
            statuses.single,
            reason,
            item['values'],
          ),
        ),
      );
    }
    if (remaining.isNotEmpty) _invalid();
    return SecuritySnapshot(
      contextId: request.contextId,
      observedAt: DateTime.now(),
      findings: findings,
    );
  }

  Never _invalid() =>
      throw const SecurityFailure(SecurityErrorCode.invalidResponse);
  @override
  Future<void> dispose() {
    _disposed = true;
    return stopScreenshotObservation();
  }

  @override
  Future<void> startScreenshotObservation() async {
    if (_disposed) {
      throw const SecurityFailure(SecurityErrorCode.disposed);
    }
    _captureRevision++;
    _captureAttempted = true;
    await _invoke('startScreenshotObservation', {'owner': _owner});
  }

  @override
  Future<void> stopScreenshotObservation() async {
    if (!_captureAttempted) return;
    final revision = ++_captureRevision;
    await _invoke('stopScreenshotObservation', {'owner': _owner});
    // A delayed stop acknowledgement must not erase a later start's ownership.
    if (_captureRevision == revision) _captureAttempted = false;
  }
}
