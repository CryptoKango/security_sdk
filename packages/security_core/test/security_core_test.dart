import 'package:security_core/security_core.dart';
import 'package:security_core/testing.dart';
import 'package:test/test.dart';

void main() {
  test('requests copy detector ids and reject empty or duplicate input', () {
    final ids = ['root'];
    final request = ScanRequest(
      contextId: 'opaque',
      detectorIds: ids,
      timeout: const Duration(seconds: 1),
    );
    ids.add('hook');
    expect(request.detectorIds, ['root']);
    expect(() => request.detectorIds.add('hook'), throwsUnsupportedError);
    for (final invalid in [
      <String>[],
      [''],
      ['root', 'root'],
    ]) {
      expect(
        () => ScanRequest(
          contextId: 'opaque',
          detectorIds: invalid,
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<SecurityFailure>()),
      );
    }
    expect(
      () => ScanRequest(
        contextId: 'opaque',
        detectorIds: ['root'],
        timeout: Duration.zero,
      ),
      throwsA(isA<SecurityFailure>()),
    );
  });

  test('snapshots copy findings and normalize time', () {
    final findings = <SecurityFinding>[];
    final snapshot = SecuritySnapshot(
      contextId: 'private-context',
      observedAt: DateTime(2026),
      findings: findings,
    );
    findings.add(
      const SecurityFinding(
        detectorId: 'root',
        detectorVersion: 'test',
        status: DetectionStatus.detected,
      ),
    );
    expect(snapshot.findings, isEmpty);
    expect(snapshot.observedAt.isUtc, isTrue);
    expect(snapshot.toString(), isNot(contains('private-context')));
  });

  test('proof binding is defensively copied and redacted', () {
    final bytes = [1, 2, 3];
    final request = EvidenceRequest(
      contextId: 'private-context',
      binding: bytes,
      timeout: const Duration(seconds: 1),
    );
    bytes[0] = 10;
    request.binding[0] = 11;
    expect(request.binding, [1, 2, 3]);
    expect(request.toString(), 'EvidenceRequest(redacted)');
    expect(
      const EvidenceReference(
        provider: 'private-provider',
        reference: 'secret',
      ).toString(),
      'EvidenceReference(redacted)',
    );
    expect(
      () => EvidenceRequest(
        contextId: 'x',
        binding: [256],
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<SecurityFailure>()),
    );
  });

  test('cancellation is idempotent and unsubscribe works', () {
    final token = CancellationToken();
    var called = 0;
    final remove = token.addListener(() => called++);
    remove();
    remove();
    token.addListener(() => called++);
    token.cancel();
    token.cancel();
    expect(called, 1);
    token.addListener(() => called++);
    expect(called, 2);
  });

  test('one failing cancellation listener does not starve others', () {
    final token = CancellationToken();
    var called = false;
    token.addListener(() => throw StateError('test'));
    token.addListener(() => called = true);
    expect(token.cancel, throwsStateError);
    expect(called, isTrue);
    token.cancel();
  });

  test(
    'test scanner requires explicit results and rejects use after dispose',
    () async {
      final fake = FakeSecurityScanner(
        onCapabilities: () async => const [],
        onScan: (r) async => SecuritySnapshot(
          contextId: r.contextId,
          observedAt: DateTime.now(),
          findings: const [],
        ),
      );
      expect(await fake.capabilities(), isEmpty);
      await fake.dispose();
      await fake.dispose();
      await expectLater(fake.capabilities(), throwsA(isA<SecurityFailure>()));
    },
  );
}
