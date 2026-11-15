import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    await File(
      Platform.environment['DEMO_REPORT']!,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
