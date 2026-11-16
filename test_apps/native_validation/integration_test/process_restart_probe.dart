import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:security_flutter/security_flutter.dart';
import 'reclaim_test.dart' as peer;

@pragma('vm:entry-point')
Future<void> reclaimMain() => peer.reclaimMain();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: SafeArea(child: Text('进程重启回归\n测试会短暂切到后台并自动重启。'))),
    ),
  );
  final report = <String, Object?>{'schemaVersion': 1, 'completed': false};
  const fixture = MethodChannel('security_sdk/lifecycle_test');
  final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
  Future<Map<String, Object?>> native(String method) async =>
      (await fixture.invokeMapMethod<String, Object?>(method))!;
  Future<void> wait(
    String method,
    bool Function(Map<String, Object?>) ready,
  ) async {
    for (var i = 0; i < 100; i++) {
      if (ready(await native(method))) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('transitionUnavailable');
  }

  Future<Map<String, Object?>> scan() async {
    final result = await sdk.scan(
      ScanRequest(
        contextId: 'process-restart',
        detectorIds: const ['screenshot', 'screenRecording'],
        timeout: const Duration(seconds: 5),
      ),
    );
    return {
      for (final f in result.findings)
        f.detectorId: {
          'status': f.status.name,
          'reason': f.reason?.name,
          'values': f.values,
        },
    };
  }

  try {
    await wait('uiState', (s) => s['focus'] == true && s['resumed'] == true);
    report['startup'] = await native('processEvidence');
    report['beforeStart'] = await scan();
    await sdk.startScreenshotObservation();
    report['active'] = await scan();
    await fixture.invokeMethod<void>('cachedStart');
    await wait(
      'reclaimState',
      (s) => s['ready'] == true && s['focused'] == true,
    );
    await fixture.invokeMethod<void>('reclaimCommand', 'start');
    await fixture.invokeMethod<void>('reclaimClose');
    await wait(
      'reclaimState',
      (s) => s['activityPresent'] == false && s['activityDestroyed'] == 1,
    );
    await wait('uiState', (s) => s['focus'] == true && s['resumed'] == true);
    report['seeded'] = await native('processEvidence');
    report['interrupted'] = await scan();
    report['completed'] = true;
    // Keep both SDK owners and the cached engine alive. The host terminates this
    // test process externally; a new launch must not recover their observations.
  } catch (_) {
    report['failure'] = 'probeFailed';
  }
  final client = HttpClient();
  try {
    final port = int.parse(const String.fromEnvironment('PROCESS_TEST_PORT'));
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/armed'));
    req.headers.set(
      'X-Test-Token',
      const String.fromEnvironment('PROCESS_TEST_TOKEN'),
    );
    req.headers.contentType = ContentType.json;
    final body = utf8.encode(jsonEncode(report));
    req.contentLength = body.length;
    req.add(body);
    final response = await req.close();
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}
