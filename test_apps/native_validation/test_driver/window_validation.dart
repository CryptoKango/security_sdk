import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final output = Platform.environment['SECURITY_VALIDATION_REPORT'];
    if (output == null || data == null) {
      throw StateError('Explicit report path and validation data required');
    }
    await File(
      output,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
