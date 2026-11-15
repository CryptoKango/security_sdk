import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:security_flutter/security_flutter.dart';

import '../host_input_example.dart';

/// The demo owns one SDK instance. Nothing runs until a user action.
class DemoController extends ChangeNotifier {
  DemoController({SecuritySdk? sdk, this.hostInputs = const DemoHostInputs()})
    : _sdk = sdk ?? SecuritySdk(operationTimeout: const Duration(seconds: 5));

  final SecuritySdk _sdk;
  final DemoHostInputs hostInputs;
  static const detectorIds = [
    ...SecurityDetectors.runtime,
    ...SecurityDetectors.environment,
    SecurityDetectors.screenshot,
    SecurityDetectors.timeAnomaly,
    SecurityDetectors.mockLocation,
  ];
  String selectedDetector = SecurityDetectors.root;
  Duration scanTimeout = const Duration(seconds: 5);
  CancellationToken? _cancellation;
  bool released = false;
  bool get canCancel => !_closed && _cancellation != null;

  void selectDetector(String? value) {
    if (_closed || busy || value == null || !detectorIds.contains(value)) {
      return;
    }
    selectedDetector = value;
    notifyListeners();
  }

  void setTimeoutSeconds(int? seconds) {
    if (_closed || busy || ![1, 5, 10].contains(seconds)) return;
    scanTimeout = Duration(seconds: seconds!);
    notifyListeners();
  }

  void cancelScan() => _cancellation?.cancel();
  Future<void> scanSelected() => _scan([selectedDetector]);
  Future<void> scanAll() => _scan(detectorIds);

  Future<void> startObservation() => _run(() async {
    await _sdk.startScreenshotObservation();
    return '已开始观察：有效窗口保留事件；已中断的窗口会被本次显式 start 替换。';
  });

  Future<void> releaseSdk() => _run(() async {
    released = true;
    await _sdk.dispose();
    return 'SDK 已释放。后续调用返回 disposed；重新运行应用可创建新实例。';
  });
  bool _closed = false;
  bool busy = false;
  bool allowReleaseDebugger = false;
  String message = '尚未检查。点击扫描后查看各项结论和实际输出值。';
  List<SecurityFinding> findings = const [];
  List<DetectorCapability> capabilities = const [];
  int _operation = 0;

  void setReleaseDebugger(bool value) {
    if (_closed || busy) return;
    allowReleaseDebugger = value;
    notifyListeners();
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_closed || busy) return;
    busy = true;
    message = '正在执行…';
    // Clear prior observations so a failed refresh cannot show stale success.
    findings = const [];
    capabilities = const [];
    notifyListeners();
    try {
      final result = await action();
      if (!_closed) message = result;
    } on SecurityFailure catch (failure) {
      if (!_closed) message = '操作未完成：${failure.code.name}';
    } catch (_) {
      // Do not expose raw platform errors or personal evidence.
      if (!_closed) message = '操作未完成：internalError';
    } finally {
      if (!_closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> queryCapabilities() => _run(() async {
    final result = await _sdk.capabilities();
    if (!_closed) capabilities = result;
    return '实现可用不代表权限、输入或前台条件已满足。';
  });

  Future<void> _scan(List<String> ids, {bool omitInputs = false}) =>
      _run(() async {
        final cancellation = CancellationToken();
        _cancellation = cancellation;
        if (!_closed) notifyListeners();
        try {
          final result = await _sdk.scan(
            ScanRequest(
              contextId: 'demo-${++_operation}',
              detectorIds: ids,
              timeout: scanTimeout,
              cancellation: cancellation,
              integrityPolicy: omitInputs ? null : hostInputs.integrityPolicy,
              timeReference: omitInputs ? null : hostInputs.timeReference,
              locationSample: omitInputs ? null : hostInputs.locationSample,
              iosDebuggerMode: allowReleaseDebugger
                  ? IosDebuggerMode.allowReleaseProcessTrace
                  : IosDebuggerMode.debugBuildOnly,
            ),
          );
          if (!_closed) findings = result.findings;
          return '本次检查完成。请分别阅读状态与原因，不支持或失败不能视为正常。';
        } finally {
          _cancellation = null;
        }
      });

  Future<void> scanLocal() => _scan([
    ...SecurityDetectors.environment,
    SecurityDetectors.root,
    SecurityDetectors.hook,
    SecurityDetectors.debugger,
  ]);

  Future<void> showMissingInputs() => _scan([
    SecurityDetectors.appIntegrity,
    SecurityDetectors.timeAnomaly,
    SecurityDetectors.mockLocation,
  ], omitInputs: true);

  Future<void> restartObservation() => _run(() async {
    await _sdk.stopScreenshotObservation();
    if (_closed) return '';
    await _sdk.startScreenshotObservation();
    return '已开始新观察窗口，旧事件已清空。手动截图后读取结果；Android 可能显示系统通知。';
  });

  Future<void> readCapture() =>
      _scan([SecurityDetectors.screenshot, SecurityDetectors.screenRecording]);

  Future<void> stopObservation() => _run(() async {
    await _sdk.stopScreenshotObservation();
    return '截图观察已停止。';
  });

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    unawaited(_sdk.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
