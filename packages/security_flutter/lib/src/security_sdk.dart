import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:security_core/security_core.dart';

import 'method_channel_security_platform.dart';
import 'security_platform.dart';

/// Explicit, per-instance scanner. No background collection or network access.
final class SecuritySdk implements SecurityScanner {
  SecuritySdk({required Duration operationTimeout, SecurityPlatform? platform})
    : _timeout = operationTimeout,
      _platform = platform ?? _defaultPlatform() {
    if (operationTimeout <= Duration.zero) {
      throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
    }
  }

  final Duration _timeout;
  final SecurityPlatform _platform;
  final CancellationToken _lifetime = CancellationToken();
  Future<void>? _disposal;
  int _captureRevision = 0;
  bool _captureWanted = false;

  static SecurityPlatform _defaultPlatform() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return MethodChannelSecurityPlatform();
    }
    return const UnsupportedSecurityPlatform();
  }

  @override
  Future<List<DetectorCapability>> capabilities() => _run(
    () async => [
      ...(await _platform.capabilities()).where(
        (c) => !_inputIds.contains(c.id),
      ),
      for (final id in _inputIds) DetectorCapability(id: id, supported: true),
    ],
    _timeout,
  );

  static const _inputIds = {
    SecurityDetectors.timeAnomaly,
    SecurityDetectors.mockLocation,
  };

  @override
  Future<SecuritySnapshot> scan(ScanRequest request) => _run(
    () async {
      final nativeIds = request.detectorIds
          .where((id) => !_inputIds.contains(id))
          .toList();
      final findings = <String, SecurityFinding>{};
      if (nativeIds.isNotEmpty) {
        final native = await _platform.scan(
          ScanRequest(
            contextId: request.contextId,
            detectorIds: nativeIds,
            timeout: request.timeout,
            cancellation: request.cancellation,
            integrityPolicy: request.integrityPolicy,
            iosDebuggerMode: request.iosDebuggerMode,
          ),
        );
        if (native.contextId != request.contextId ||
            native.findings.length != nativeIds.length ||
            native.findings.map((f) => f.detectorId).toSet().length !=
                nativeIds.length ||
            native.findings.any((f) => !nativeIds.contains(f.detectorId))) {
          throw const SecurityFailure(SecurityErrorCode.invalidResponse);
        }
        findings.addEntries(
          native.findings.map((f) => MapEntry(f.detectorId, f)),
        );
      }
      for (final id in request.detectorIds.where(_inputIds.contains)) {
        findings[id] = id == SecurityDetectors.timeAnomaly
            ? request.timeReference?.evaluate(DateTime.now()) ??
                  SecurityFinding(
                    detectorId: id,
                    detectorVersion: 'local-v1',
                    status: DetectionStatus.error,
                    reason: FindingReason.timeReferenceRequired,
                  )
            : request.locationSample?.evaluate() ??
                  SecurityFinding(
                    detectorId: id,
                    detectorVersion: 'local-v1',
                    status: DetectionStatus.error,
                    reason: FindingReason.locationSampleRequired,
                  );
      }
      return SecuritySnapshot(
        contextId: request.contextId,
        observedAt: DateTime.now(),
        findings: request.detectorIds.map((id) => findings[id]!),
      );
    },
    request.timeout,
    request.cancellation,
  );

  /// Begin an observation window. Repeating start preserves a still-valid window.
  /// An explicit start after interruption replaces the invalid window; merely
  /// returning to the foreground never resumes observation automatically.
  /// Scan `screenshot` to read whether an event occurred since start; stop/start
  /// opens a new window. Host must stop when leaving the relevant UI.
  Future<void> startScreenshotObservation() async {
    final platform = _platform;
    if (platform is! ScreenshotObservationPlatform) {
      return _run(
        () =>
            Future.error(const SecurityFailure(SecurityErrorCode.unsupported)),
        _timeout,
      );
    }
    if (_lifetime.isCancelled) {
      throw const SecurityFailure(SecurityErrorCode.disposed);
    }
    final revision = ++_captureRevision;
    _captureWanted = true;
    var started = false;
    try {
      await _run(() {
        started = true;
        final capture = platform as ScreenshotObservationPlatform;
        final pending = capture.startScreenshotObservation();
        void cleanLateCompletion() {
          if (!_captureWanted || _lifetime.isCancelled) {
            // Custom providers may finish registration after stop/dispose.
            // Consume cleanup errors and never let old completion stop a newer start.
            unawaited(
              Future<void>.sync(
                capture.stopScreenshotObservation,
              ).timeout(_timeout).catchError((Object _) {}),
            );
          }
        }

        unawaited(
          pending.then<void>(
            (_) => cleanLateCompletion(),
            onError: (Object _, StackTrace _) => cleanLateCompletion(),
          ),
        );
        return pending;
      }, _timeout);
    } catch (_) {
      // Only the newest start may clean up its window. An older timeout must
      // not stop a later start, stop or dispose operation on the same owner.
      if (started && revision == _captureRevision) {
        _captureWanted = false;
        try {
          await (platform as ScreenshotObservationPlatform)
              .stopScreenshotObservation()
              .timeout(_timeout);
        } catch (_) {
          /* Original failure takes precedence. dispose retries cleanup. */
        }
      }
      rethrow;
    }
  }

  Future<void> stopScreenshotObservation() {
    _captureRevision++;
    _captureWanted = false;
    return _run(() async {
      final platform = _platform;
      if (platform is ScreenshotObservationPlatform) {
        await (platform as ScreenshotObservationPlatform)
            .stopScreenshotObservation();
      }
    }, _timeout);
  }

  Future<T> _run<T>(
    Future<T> Function() work,
    Duration timeout, [
    CancellationToken? cancellation,
  ]) {
    if (_lifetime.isCancelled) {
      return Future.error(const SecurityFailure(SecurityErrorCode.disposed));
    }
    if (cancellation?.isCancelled ?? false) {
      return Future.error(const SecurityFailure(SecurityErrorCode.cancelled));
    }
    final result = Completer<T>();
    void fail(SecurityErrorCode code) {
      if (!result.isCompleted) result.completeError(SecurityFailure(code));
    }

    final timer = Timer(timeout, () => fail(SecurityErrorCode.timeout));
    final detachLifetime = _lifetime.addListener(
      () => fail(SecurityErrorCode.disposed),
    );
    final detachCancellation = cancellation?.addListener(
      () => fail(SecurityErrorCode.cancelled),
    );
    Future<T>.sync(work).then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) {
          result.completeError(
            error is SecurityFailure
                ? error
                : const SecurityFailure(SecurityErrorCode.internalError),
          );
        }
      },
    );
    return result.future.whenComplete(() {
      timer.cancel();
      detachLifetime();
      detachCancellation?.call();
    });
  }

  @override
  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    _captureRevision++;
    _captureWanted = false;
    _lifetime.cancel();
    return _disposal = Future<void>.sync(_platform.dispose)
        .timeout(
          _timeout,
          onTimeout: () {
            throw const SecurityFailure(SecurityErrorCode.timeout);
          },
        )
        .onError((error, stack) {
          if (error is SecurityFailure) throw error;
          throw const SecurityFailure(SecurityErrorCode.platformUnavailable);
        });
  }
}
