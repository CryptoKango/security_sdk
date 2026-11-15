import 'package:flutter/material.dart';
import 'package:security_flutter/security_flutter.dart';

void main() => runApp(const MaterialApp(home: ScanExample()));

class ScanExample extends StatefulWidget {
  const ScanExample({super.key});
  @override
  State<ScanExample> createState() => _ScanExampleState();
}

class _ScanExampleState extends State<ScanExample> {
  final _sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
  String _status = 'No scan requested. Signals do not imply fraud or safety.';
  bool _busy = false;

  Future<void> _scan() async {
    setState(() => _busy = true);
    String status;
    try {
      final snapshot = await _sdk.scan(
        ScanRequest(
          contextId: 'example-operation',
          detectorIds: [
            ...SecurityDetectors.environment,
            ...SecurityDetectors.runtime,
            SecurityDetectors.timeAnomaly,
            SecurityDetectors.mockLocation,
          ],
          timeout: const Duration(seconds: 5),
        ),
      );
      status = snapshot.findings
          .map(
            (f) =>
                '${f.detectorId}: ${f.status.name} (${f.reason?.name ?? 'unspecified'})',
          )
          .join('\n');
    } on SecurityFailure catch (failure) {
      status = failure.code.name;
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  Future<void> _observe() async {
    try {
      await _sdk.startScreenshotObservation();
      if (mounted) {
        setState(
          () => _status =
              'Screenshot observation started. Take a screenshot, then read the window. Android shows a system notice.',
        );
      }
    } on SecurityFailure catch (failure) {
      if (mounted) setState(() => _status = failure.code.name);
    }
  }

  Future<void> _readObservation() async {
    try {
      final result = await _sdk.scan(
        ScanRequest(
          contextId: 'example-capture',
          detectorIds: [SecurityDetectors.screenshot],
          timeout: const Duration(seconds: 5),
        ),
      );
      if (mounted) {
        setState(
          () => _status =
              '${result.findings.single.status.name}: ${result.findings.single.reason?.name}',
        );
      }
    } on SecurityFailure catch (failure) {
      if (mounted) setState(() => _status = failure.code.name);
    }
  }

  Future<void> _stopObservation() async {
    try {
      await _sdk.stopScreenshotObservation();
      if (mounted) setState(() => _status = 'Screenshot observation stopped.');
    } on SecurityFailure catch (failure) {
      if (mounted) setState(() => _status = failure.code.name);
    }
  }

  @override
  void dispose() {
    _sdk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Security SDK example')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_status),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _scan,
            child: const Text('Scan locally'),
          ),
          TextButton(
            onPressed: _observe,
            child: const Text('Start screenshot observation'),
          ),
          TextButton(
            onPressed: _readObservation,
            child: const Text('Read screenshot window'),
          ),
          TextButton(
            onPressed: _stopObservation,
            child: const Text('Stop screenshot observation'),
          ),
        ],
      ),
    ),
  );
}
