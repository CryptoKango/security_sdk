import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

ScanRequest request({CancellationToken? cancellation, Duration? timeout}) =>
    ScanRequest(
      contextId: 'opaque',
      detectorIds: ['root'],
      timeout: timeout ?? const Duration(seconds: 2),
      cancellation: cancellation,
    );
SecuritySnapshot snapshot() => SecuritySnapshot(
  contextId: 'opaque',
  observedAt: DateTime.now(),
  findings: const [
    SecurityFinding(
      detectorId: 'root',
      detectorVersion: 'test',
      status: DetectionStatus.unsupported,
    ),
  ],
);
Matcher fails(SecurityErrorCode code) =>
    throwsA(isA<SecurityFailure>().having((e) => e.code, 'code', code));

class TestPlatform implements SecurityPlatform {
  TestPlatform(this.result);
  final Future<SecuritySnapshot> result;
  int calls = 0;
  int disposals = 0;
  @override
  Future<List<DetectorCapability>> capabilities() async {
    calls++;
    return const [];
  }

  @override
  Future<SecuritySnapshot> scan(ScanRequest request) {
    calls++;
    return result;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'construction does not collect and unsupported is not a clean verdict',
    () async {
      final platform = TestPlatform(Future.value(snapshot()));
      final sdk = SecuritySdk(
        operationTimeout: const Duration(seconds: 1),
        platform: platform,
      );
      expect(platform.calls, 0);
      expect(
        (await sdk.scan(request())).findings.single.status,
        DetectionStatus.unsupported,
      );
      await sdk.dispose();
    },
  );

  test('pre-cancelled scans never invoke the platform', () async {
    final platform = TestPlatform(Future.value(snapshot()));
    final token = CancellationToken()..cancel();
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 1),
      platform: platform,
    );
    await expectLater(
      sdk.scan(request(cancellation: token)),
      fails(SecurityErrorCode.cancelled),
    );
    expect(platform.calls, 0);
    await sdk.dispose();
  });

  test('cancellation drops a late native result', () async {
    final pending = Completer<SecuritySnapshot>();
    final token = CancellationToken();
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 1),
      platform: TestPlatform(pending.future),
    );
    final check = expectLater(
      sdk.scan(request(cancellation: token)),
      fails(SecurityErrorCode.cancelled),
    );
    token.cancel();
    await check;
    pending.complete(snapshot());
    await sdk.dispose();
  });

  test('timeout ignores a late platform error', () async {
    final pending = Completer<SecuritySnapshot>();
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 1),
      platform: TestPlatform(pending.future),
    );
    await expectLater(
      sdk.scan(request(timeout: const Duration(milliseconds: 10))),
      fails(SecurityErrorCode.timeout),
    );
    pending.completeError(StateError('raw private error'));
    await Future<void>.delayed(Duration.zero);
    await sdk.dispose();
  });

  test('dispose rejects inflight and future work and releases once', () async {
    final pending = Completer<SecuritySnapshot>();
    final platform = TestPlatform(pending.future);
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 1),
      platform: platform,
    );
    final check = expectLater(
      sdk.scan(request()),
      fails(SecurityErrorCode.disposed),
    );
    await sdk.dispose();
    await sdk.dispose();
    await check;
    await expectLater(sdk.capabilities(), fails(SecurityErrorCode.disposed));
    expect(platform.disposals, 1);
    pending.complete(snapshot());
  });

  test('disposing one client does not cancel another', () async {
    final a = SecuritySdk(
      operationTimeout: const Duration(seconds: 1),
      platform: TestPlatform(Future.value(snapshot())),
    );
    final b = SecuritySdk(
      operationTimeout: const Duration(seconds: 1),
      platform: TestPlatform(Future.value(snapshot())),
    );
    await a.dispose();
    expect((await b.scan(request())).findings, hasLength(1));
    await b.dispose();
  });

  test('unexpected errors are redacted', () async {
    final pending = Completer<SecuritySnapshot>();
    final sdk = SecuritySdk(
      operationTimeout: const Duration(seconds: 1),
      platform: TestPlatform(pending.future),
    );
    final check = expectLater(
      sdk.scan(request()),
      fails(SecurityErrorCode.internalError),
    );
    pending.completeError(StateError('private native material'));
    await check;
    await sdk.dispose();
  });

  const channel = MethodChannel('security_sdk/test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('missing native registration is an error, not unsupported', () async {
    final platform = MethodChannelSecurityPlatform(channel: channel);
    await expectLater(
      platform.capabilities(),
      fails(SecurityErrorCode.platformUnavailable),
    );
  });

  test('valid unsupported response preserves the requested context', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'schemaVersion': 1,
        'contextId': 'opaque',
        'findings': [
          {
            'detectorId': 'root',
            'detectorVersion': 'unimplemented',
            'status': 'unsupported',
          },
        ],
      },
    );
    final result = await MethodChannelSecurityPlatform(
      channel: channel,
    ).scan(request());
    expect(result.contextId, 'opaque');
    expect(result.findings.single.status, DetectionStatus.unsupported);
  });

  test(
    'malformed or incomplete results never become clean snapshots',
    () async {
      final finding = {
        'detectorId': 'root',
        'detectorVersion': 'v1',
        'status': 'notDetected',
      };
      final responses = [
        null,
        {'schemaVersion': 2},
        {
          'schemaVersion': 1,
          'contextId': 'other',
          'findings': [finding],
        },
        {'schemaVersion': 1, 'contextId': 'opaque', 'findings': []},
        {
          'schemaVersion': 1,
          'contextId': 'opaque',
          'findings': [finding, finding],
        },
        {
          'schemaVersion': 1,
          'contextId': 'opaque',
          'findings': [
            {...finding, 'status': 'clean'},
          ],
        },
        {
          'schemaVersion': 1,
          'contextId': 'opaque',
          'findings': [
            {...finding, 'detectorId': 'unknown'},
          ],
        },
      ];
      for (final response in responses) {
        messenger.setMockMethodCallHandler(channel, (call) async => response);
        await expectLater(
          MethodChannelSecurityPlatform(channel: channel).scan(request()),
          fails(SecurityErrorCode.invalidResponse),
        );
      }
    },
  );

  test('duplicate or malformed capabilities are rejected', () async {
    final capability = {'id': 'root', 'supported': false};
    for (final capabilities in [
      [capability, capability],
      [
        {'id': 'root', 'supported': 'yes'},
      ],
    ]) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {'schemaVersion': 1, 'capabilities': capabilities},
      );
      await expectLater(
        MethodChannelSecurityPlatform(channel: channel).capabilities(),
        fails(SecurityErrorCode.invalidResponse),
      );
    }
  });
}
