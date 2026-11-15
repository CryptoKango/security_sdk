import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_sdk_demo/src/finding_presentation.dart';

void main() {
  SecurityFinding f(
    String id,
    DetectionStatus status,
    FindingReason reason, [
    Map<String, Object?> values = const {},
  ]) => SecurityFinding.withValues(
    detectorId: id,
    detectorVersion: 'local-v1',
    status: status,
    reason: reason,
    values: values,
  );
  test('missing prerequisites have explicit outcomes and next steps', () {
    expect(
      findingConclusion(
        f('vpn', DetectionStatus.notDetected, FindingReason.noActiveNetwork),
      ),
      contains('无法判断 VPN'),
    );
    expect(
      findingConclusion(
        f(
          'timeAnomaly',
          DetectionStatus.error,
          FindingReason.timeReferenceRequired,
        ),
      ),
      contains('缺少可信时间基准'),
    );
    expect(
      findingConclusion(
        f(
          'mockLocation',
          DetectionStatus.error,
          FindingReason.locationSampleRequired,
        ),
      ),
      contains('未提供位置样本'),
    );
    expect(
      findingConclusion(
        f(
          'screenshot',
          DetectionStatus.error,
          FindingReason.observationInterrupted,
        ),
      ),
      contains('重新开始观察'),
    );
    expect(
      findingConclusion(
        f(
          'developerMode',
          DetectionStatus.unsupported,
          FindingReason.settingReadRestricted,
        ),
      ),
      contains('无法确认关闭'),
    );
    expect(
      findingConclusion(
        f(
          'developerMode',
          DetectionStatus.unsupported,
          FindingReason.unsupportedPlatform,
        ),
      ),
      contains('当前平台未提供'),
    );
  });
  test(
    'negative capture and accessibility conclusions state observation scope',
    () {
      expect(
        findingConclusion(
          f(
            'screenshot',
            DetectionStatus.notDetected,
            FindingReason.noKnownSignal,
          ),
        ),
        '本次观察期间未收到截图事件',
      );
      expect(
        findingConclusion(
          f(
            'screenRecording',
            DetectionStatus.notDetected,
            FindingReason.noKnownSignal,
          ),
        ),
        contains('当前窗口'),
      );
      expect(
        findingConclusion(
          f(
            'accessibility',
            DetectionStatus.notDetected,
            FindingReason.noKnownSignal,
          ),
        ),
        contains('被检查的无障碍功能'),
      );
      for (final id in [
        ...SecurityDetectors.runtime,
        ...SecurityDetectors.environment,
        'screenshot',
        'timeAnomaly',
        'mockLocation',
      ]) {
        expect(detectorName(id), id == 'vpn' ? 'VPN' : isNot(id));
        expect(
          findingConclusion(
            f(id, DetectionStatus.error, FindingReason.nativeFailure),
          ),
          contains('调用失败'),
        );
      }
    },
  );
  test('output includes SDK fields and exact false, zero and null values', () {
    final output = findingOutput(
      f(
        'developerMode',
        DetectionStatus.unsupported,
        FindingReason.settingReadRestricted,
        {'settingValue': 0, 'settingPresent': false, 'otherReading': null},
      ),
    );
    for (final text in [
      'detectorId: developerMode',
      'status: unsupported',
      'reason: settingReadRestricted',
      'detectorVersion: local-v1',
      'settingValue: 0',
      'settingPresent: false',
      'otherReading: null',
    ]) {
      expect(output, contains(text));
    }
    expect(
      findingOutput(
        f('root', DetectionStatus.notDetected, FindingReason.noKnownSignal),
      ),
      contains('values: {}'),
    );
  });
  test(
    'available readings distinguish missing, invalid and disabled settings',
    () {
      expect(
        findingConclusion(
          f(
            'developerMode',
            DetectionStatus.error,
            FindingReason.settingValueUnavailable,
            {
              'settingPresent': false,
              'settingValue': null,
              'settingValueValid': false,
            },
          ),
        ),
        contains('系统未返回此设置'),
      );
      expect(
        findingConclusion(
          f(
            'developerMode',
            DetectionStatus.error,
            FindingReason.settingValueUnavailable,
            {
              'settingPresent': true,
              'settingValue': null,
              'settingValueValid': false,
            },
          ),
        ),
        contains('非 0/1'),
      );
      expect(
        findingConclusion(
          f(
            'accessibility',
            DetectionStatus.notDetected,
            FindingReason.noKnownSignal,
            {'accessibilityEnabled': false},
          ),
        ),
        contains('false（未启用）'),
      );
      expect(
        findingConclusion(
          f(
            'accessibility',
            DetectionStatus.notDetected,
            FindingReason.noKnownSignal,
            {'voiceOverEnabled': false, 'switchControlEnabled': false},
          ),
        ),
        contains('均未启用'),
      );
    },
  );
  test('time readings keep their precision and explicit units', () {
    final output = findingOutput(
      f('timeAnomaly', DetectionStatus.detected, FindingReason.timeDeviation, {
        'deviationUs': 3000001,
        'allowedSkewUs': 3000000,
      }),
    );
    expect(output, contains('deviationUs: 3000001（时间绝对偏差，微秒）'));
  });
}
