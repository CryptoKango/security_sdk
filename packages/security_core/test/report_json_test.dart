import 'dart:convert';

import 'package:security_core/security_core.dart';
import 'package:test/test.dart';

DeviceSecurityReport report(DevicePlatform os) => DeviceSecurityReport(
  device: DeviceInfoResult.available(
    DeviceInfo(
      platform: os,
      manufacturer: os == DevicePlatform.android ? 'samsung' : 'Apple',
      brand: os == DevicePlatform.android ? 'samsung' : 'Apple',
      model: os == DevicePlatform.android ? 'SM-F766U' : 'iPhone17,1',
      systemVersion: os == DevicePlatform.android ? '16' : '18.0',
      apiLevel: os == DevicePlatform.android ? 36 : null,
    ),
  ),
  capabilities: const [
    DetectorCapability(
      id: 'debugger',
      supported: true,
      requiresExplicitOptIn: true,
    ),
  ],
  security: SecuritySnapshot(
    contextId: 'check-"转义"\n',
    observedAt: DateTime.parse('2026-11-16T18:20:30.123456+08:00'),
    findings: [
      SecurityFinding.withValues(
        detectorId: 'debugger',
        detectorVersion: 'fixture-v1',
        status: DetectionStatus.unsupported,
        reason: FindingReason.unsupportedPlatform,
        values: {'flag': false, 'count': 0, 'offset': -1.25, 'unknown': null},
      ),
    ],
  ),
);

void main() {
  for (final os in DevicePlatform.values) {
    test('${os.name} exact versioned schema and JSON encoding', () {
      final r = report(os);
      final expected = {
        'schemaVersion': 1,
        'device': {
          'status': 'available',
          'code': null,
          'info': {
            'platform': os.name,
            'manufacturer': os == DevicePlatform.android ? 'samsung' : 'Apple',
            'brand': os == DevicePlatform.android ? 'samsung' : 'Apple',
            'model': os == DevicePlatform.android ? 'SM-F766U' : 'iPhone17,1',
            'systemVersion': os == DevicePlatform.android ? '16' : '18.0',
            'apiLevel': os == DevicePlatform.android ? 36 : null,
          },
        },
        'capabilities': [
          {'id': 'debugger', 'supported': true, 'requiresExplicitOptIn': true},
        ],
        'security': {
          'contextId': 'check-"转义"\n',
          'observedAt': '2026-11-16T10:20:30.123456Z',
          'findings': [
            {
              'detectorId': 'debugger',
              'detectorVersion': 'fixture-v1',
              'status': 'unsupported',
              'reason': 'unsupportedPlatform',
              'values': {
                'flag': false,
                'count': 0,
                'offset': -1.25,
                'unknown': null,
              },
            },
          ],
        },
      };
      expect(r.toJson(), expected);
      expect(jsonDecode(jsonEncode(r)), expected);
      expect(jsonDecode(jsonEncode(r.toJson())), expected);
      expect(
        jsonDecode(jsonEncode(r.device.info)),
        expected['device'] is Map ? (expected['device'] as Map)['info'] : null,
      );
      expect(r.toString(), isNot(contains(r.device.info!.model)));
    });
  }

  test('metadata failures remain explicit without losing scan findings', () {
    for (final result in [
      const DeviceInfoResult.unsupported(),
      const DeviceInfoResult.failure(SecurityErrorCode.platformUnavailable),
    ]) {
      final r = DeviceSecurityReport(
        device: result,
        capabilities: const [],
        security: report(DevicePlatform.android).security,
      );
      final json = jsonDecode(jsonEncode(r)) as Map;
      expect(json['device'], {
        'status': result.status == DeviceInfoStatus.error
            ? 'error'
            : 'unsupported',
        'code': result.status == DeviceInfoStatus.error
            ? 'platformUnavailable'
            : 'unsupported',
        'info': null,
      });
      expect(json['capabilities'], isEmpty);
      expect(json['security']['findings'], hasLength(1));
    }
  });

  test(
    'statuses, absent reason and empty readings retain their wire meaning',
    () {
      const statuses = {
        DetectionStatus.detected: 'detected',
        DetectionStatus.notDetected: 'notDetected',
        DetectionStatus.unsupported: 'unsupported',
        DetectionStatus.error: 'error',
      };
      expect(statuses.keys, containsAll(DetectionStatus.values));
      for (final entry in statuses.entries) {
        final f = SecurityFinding(
          detectorId: 'root',
          detectorVersion: 'v1',
          status: entry.key,
        );
        expect(jsonDecode(jsonEncode(f)), {
          'detectorId': 'root',
          'detectorVersion': 'v1',
          'status': entry.value,
          'reason': null,
          'values': <String, Object?>{},
        });
      }
      expect(const DetectorCapability(id: 'root', supported: false).toJson(), {
        'id': 'root',
        'supported': false,
        'requiresExplicitOptIn': false,
      });
    },
  );

  test(
    'mutating serialized containers cannot change report or another export',
    () {
      final r = report(DevicePlatform.android);
      final before = jsonEncode(r);
      final copy = r.toJson();
      ((copy['device'] as Map)['info'] as Map)['model'] = 'changed';
      ((copy['capabilities'] as List).first as Map)['supported'] = false;
      final findings = (copy['security'] as Map)['findings'] as List;
      (findings.first['values'] as Map)['flag'] = true;
      findings.clear();
      (copy['capabilities'] as List).clear();
      copy['schemaVersion'] = 999;
      expect(jsonEncode(r), before);
    },
  );

  test('UTC milliseconds and empty collections are not omitted', () {
    final s = SecuritySnapshot(
      contextId: 'empty',
      observedAt: DateTime.utc(2026, 11, 16),
      findings: [],
    );
    expect(jsonDecode(jsonEncode(s)), {
      'contextId': 'empty',
      'observedAt': '2026-11-16T00:00:00.000Z',
      'findings': [],
    });
  });
}
