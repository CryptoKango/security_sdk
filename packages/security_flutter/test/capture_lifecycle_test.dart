import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_flutter/security_flutter.dart';
import 'package:security_flutter/src/method_channel_security_platform.dart';

class LateCapturePlatform
    implements SecurityPlatform, ScreenshotObservationPlatform {
  final firstStart = Completer<void>();
  int starts = 0;
  int stops = 0;
  bool active = false;
  @override
  Future<void> startScreenshotObservation() async {
    if (++starts == 1) await firstStart.future;
    active = true;
  }

  @override
  Future<void> stopScreenshotObservation() async {
    stops++;
    active = false;
  }

  @override
  Future<void> dispose() => stopScreenshotObservation();
  @override
  Future<List<DetectorCapability>> capabilities() async => [];
  @override
  Future<SecuritySnapshot> scan(ScanRequest request) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_sdk/capture_lifecycle_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Matcher failure(SecurityErrorCode code) =>
      throwsA(isA<SecurityFailure>().having((e) => e.code, 'code', code));
  SecuritySdk sdk(SecurityPlatform platform) => SecuritySdk(
    operationTimeout: const Duration(milliseconds: 30),
    platform: platform,
  );
  test(
    'old stop acknowledgement cannot erase a newer start before dispose',
    () async {
      final oldStop = Completer<Object?>();
      var stops = 0;
      var active = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'startScreenshotObservation') active = true;
        if (call.method == 'stopScreenshotObservation') {
          active = false;
          if (++stops == 1) return oldStop.future;
        }
        return {'schemaVersion': 1};
      });
      final platform = MethodChannelSecurityPlatform(channel: channel);
      await platform.startScreenshotObservation();
      final stop = platform.stopScreenshotObservation();
      await Future<void>.delayed(Duration.zero);
      await platform.startScreenshotObservation();
      oldStop.complete({'schemaVersion': 1});
      await stop;
      expect(active, isTrue);
      await platform.dispose();
      expect(stops, 2);
      expect(active, isFalse);
      await expectLater(
        platform.startScreenshotObservation(),
        failure(SecurityErrorCode.disposed),
      );
    },
  );
  test('older start timeout does not stop a newer native start', () async {
    final first = Completer<Object?>();
    var starts = 0;
    var stops = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startScreenshotObservation' && ++starts == 1) {
        return first.future;
      }
      if (call.method == 'stopScreenshotObservation') stops++;
      return {'schemaVersion': 1};
    });
    final client = sdk(MethodChannelSecurityPlatform(channel: channel));
    final old = expectLater(
      client.startScreenshotObservation(),
      failure(SecurityErrorCode.timeout),
    );
    await Future<void>.delayed(Duration.zero);
    await client.startScreenshotObservation();
    await old;
    expect(stops, 0);
    first.complete({'schemaVersion': 1});
    await Future<void>.delayed(Duration.zero);
    expect(stops, 0);
    await client.dispose();
    expect(stops, 1);
  });
  test('late custom registration after dispose is cleaned up', () async {
    final platform = LateCapturePlatform();
    final client = sdk(platform);
    final start = expectLater(
      client.startScreenshotObservation(),
      failure(SecurityErrorCode.disposed),
    );
    await client.dispose();
    await start;
    platform.firstStart.complete();
    await Future<void>.delayed(Duration.zero);
    expect(platform.active, isFalse);
    expect(platform.stops, greaterThanOrEqualTo(2));
  });
  test('late custom registration after stop is cleaned up', () async {
    final platform = LateCapturePlatform();
    final client = sdk(platform);
    final start = client.startScreenshotObservation();
    await client.stopScreenshotObservation();
    platform.firstStart.complete();
    await start;
    await Future<void>.delayed(Duration.zero);
    expect(platform.active, isFalse);
    await client.dispose();
  });
  test(
    'timed out custom registration is also cleaned after actual completion',
    () async {
      final platform = LateCapturePlatform();
      final client = sdk(platform);
      await expectLater(
        client.startScreenshotObservation(),
        failure(SecurityErrorCode.timeout),
      );
      platform.firstStart.complete();
      await Future<void>.delayed(Duration.zero);
      expect(platform.active, isFalse);
      await client.dispose();
    },
  );
  test(
    'late completion of an old start does not clean a newer wanted window',
    () async {
      final platform = LateCapturePlatform();
      final client = sdk(platform);
      final old = expectLater(
        client.startScreenshotObservation(),
        failure(SecurityErrorCode.timeout),
      );
      await client.startScreenshotObservation();
      await old;
      platform.firstStart.complete();
      await Future<void>.delayed(Duration.zero);
      expect(platform.active, isTrue);
      expect(platform.stops, 0);
      await client.dispose();
    },
  );
  test(
    'failed native stop preserves cleanup ownership for dispose retry',
    () async {
      var stops = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'stopScreenshotObservation' && ++stops == 1) {
          throw PlatformException(code: 'platform_unavailable');
        }
        return {'schemaVersion': 1};
      });
      final client = sdk(MethodChannelSecurityPlatform(channel: channel));
      await client.startScreenshotObservation();
      await expectLater(
        client.stopScreenshotObservation(),
        failure(SecurityErrorCode.platformUnavailable),
      );
      await client.dispose();
      expect(stops, 2);
    },
  );
}
