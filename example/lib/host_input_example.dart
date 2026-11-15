import 'package:security_flutter/security_flutter.dart';

/// Inject only actual host inputs. An absent input stays absent and produces the
/// SDK's explicit prerequisite error; this example never fabricates a baseline.
class DemoHostInputs {
  const DemoHostInputs({
    this.integrityPolicy,
    this.timeReference,
    this.locationSample,
  });
  final AppIntegrityPolicy? integrityPolicy;
  final TrustedTimeReference? timeReference;
  final LocationRiskSample? locationSample;
}

/// Call from a host that already has an approved release baseline,
/// authenticated time reference and a legally obtained location source sample.
/// This example deliberately does not manufacture those inputs or request location.
Future<SecuritySnapshot> scanWithHostInputs(
  SecuritySdk sdk, {
  required AppIntegrityPolicy integrityPolicy,
  required TrustedTimeReference timeReference,
  required LocationRiskSample locationSample,
}) => sdk.scan(
  ScanRequest(
    contextId: 'host-input-example',
    detectorIds: [
      SecurityDetectors.appIntegrity,
      SecurityDetectors.timeAnomaly,
      SecurityDetectors.mockLocation,
    ],
    timeout: const Duration(seconds: 5),
    integrityPolicy: integrityPolicy,
    timeReference: timeReference,
    locationSample: locationSample,
  ),
);

/// Build from a trusted release manifest, never from the current installation.
AppIntegrityPolicy integrityFromReleaseManifest({
  required String applicationId,
  Iterable<Iterable<String>> androidSignerSets = const [],
  Map<String, String> iosStableFiles = const {},
}) => AppIntegrityPolicy(
  expectedApplicationId: applicationId,
  androidSignerSha256Sets: androidSignerSets,
  iosBundleFileSha256: iosStableFiles,
);

/// Call once when the host authenticates and receives a fresh reference.
TrustedTimeReference timeAtAuthenticatedReceipt({
  required DateTime serverTimeAtReceipt,
  required Duration allowedSkew,
  required Duration validFor,
}) => TrustedTimeReference(
  serverTimeAtReceipt: serverTimeAtReceipt,
  allowedSkew: allowedSkew,
  validFor: validFor,
);

/// Metadata from the host's existing authorized location flow; no coordinates.
LocationRiskSample locationFromAuthorizedFlow({
  required bool businessUseAuthorized,
  required bool permissionGranted,
  required bool? isMocked,
  required Duration ageAtReceipt,
  required Duration maxAge,
}) => LocationRiskSample(
  businessUseAuthorized: businessUseAuthorized,
  permissionGranted: permissionGranted,
  isMocked: isMocked,
  ageAtReceipt: ageAtReceipt,
  maxAge: maxAge,
);

/// Pure Dart evaluation for hosts that already own sample freshness accounting.
SecurityFinding evaluateTimeWithoutNative({
  required DateTime localTime,
  required DateTime serverTimeAtReceipt,
  required Duration elapsed,
  required Duration validFor,
  required Duration allowedSkew,
}) => assessTimeAnomaly(
  localTime: localTime,
  serverTimeAtReceipt: serverTimeAtReceipt,
  elapsed: elapsed,
  validFor: validFor,
  allowedSkew: allowedSkew,
);

SecurityFinding evaluateLocationWithoutNative({
  required bool businessUseAuthorized,
  required bool permissionGranted,
  required bool? isMocked,
  required Duration age,
  required Duration maxAge,
}) => assessLocationRisk(
  businessUseAuthorized: businessUseAuthorized,
  permissionGranted: permissionGranted,
  isMocked: isMocked,
  age: age,
  maxAge: maxAge,
);
