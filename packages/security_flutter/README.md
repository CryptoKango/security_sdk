# security_flutter

Explicit Android/iOS security observations with a framework-neutral Dart API.
Construction never scans or subscribes. Third-party fingerprinting is excluded.

```dart
final sdk = SecuritySdk(operationTimeout: const Duration(seconds: 5));
final result = await sdk.scan(ScanRequest(
  contextId: 'opaque-operation-id',
  detectorIds: SecurityDetectors.environment,
  timeout: const Duration(seconds: 5),
));
// Consume status + reason; never turn notDetected into an authorization verdict.
await sdk.dispose();
```

Screenshot observation is explicit: `startScreenshotObservation()`, scan
`SecurityDetectors.screenshot`, then `stopScreenshotObservation()`. Results mean
an event occurred in that instance's active window. Android requires API 34+ and
host-declared `DETECT_SCREEN_CAPTURE`; screen recording requires API 35+ and
`DETECT_SCREEN_RECORDING`; Android VPN/proxy need `ACCESS_NETWORK_STATE`.
Do not add location permissions solely to use this SDK.

Time/location are optional host inputs (`TrustedTimeReference`,
`LocationRiskSample`). Missing prerequisites yield `error`; unknown source flags
yield `unsupported`. No coordinates are sent to the SDK. See the repository's
`docs/detection_coverage.md` for platform limits, integration and test matrix.

`SecurityDetectors.runtime` scans root/jailbreak, known hook markers, debugger
state and app integrity. Pass an `AppIntegrityPolicy` built from trusted release
artifacts for integrity checks; absent baselines yield an error. Android compares
current signer sets exactly. iOS compares Bundle ID and selected file hashes;
iOS Release process-trace checks require
`iosDebuggerMode: IosDebuggerMode.allowReleaseProcessTrace` on the scan request;
capabilities expose `requiresExplicitOptIn`. The default remains Debug-only.
Read `docs/ios_release_debugger.md` and `docs/runtime_security.md` in the repository
for ABI caveats, platform limits and deployment instructions.

Development package, publication disabled. The SDK does not authorize business
operations and does not implement third-party device fingerprinting.

Native local-v2 first added bounded root-mount, known memfd/injection-origin and
Android container identity checks. See `docs/hidden_environment.md` in the repository
for false-positive controls and remaining gaps. No device fingerprinting is added.

Native local-v3 adds limited iOS application-executable/container signals and
public-API-gated Android profile handling. Ambiguous OEM/private profiles remain
unsupported; profile IDs, brands, iPad scenes and ordinary bundled dylibs do not
establish cloning. See the repository's `docs/ios_oem_multi_instance.md` for
coverage, reasons and remaining device validation. Third-party fingerprinting is
still deferred.

Native local-v4 tightens active tunnel matching and invalid location metadata
handling. Low-OS framework regressions and an iOS 13 availability check are now
provided; see `docs/compatibility_review.md` in the repository. Unknown location
sources stay unknown. No third-party fingerprinting was added.

Native local-v5 isolates capture lifecycle and cleanup across owners/engines,
invalidates observations across focus/background/window changes, and prevents
stale capture success after asynchronous scans. Failed unregister is retried
without accumulating listeners. Dart late start/stop/dispose races have regression
coverage. Recording remains a snapshot, and Android UID / iOS global screenshot
notification scope cannot establish exact engine attribution. See the repository's
`docs/capture_lifecycle.md`. Third-party fingerprinting remains deferred.

Native local-v6 scopes iOS activation observers to their own Scene (App events only
for legacy hosts), binds capture to Window/Scene/Screen identity, and repairs Android
decor reattachment/focus observation. Android PiP cannot satisfy foreground capture
prerequisites. Geometry-only changes preserve accumulated evidence; real gaps stay
unknown. See `docs/scene_window_lifecycle.md` in the repository for limits and tests.
No third-party fingerprinting was added.

Minimum Flutter 3.38.10 / Dart 3.10.9 (<4.0.0). Android AGP/Kotlin versions are
provided by the host rather than pinned by this plugin. AGP 8 applies the host
Kotlin plugin; AGP 9 leaves Kotlin mode to the Flutter host. The portable example
retains `android.newDsl=false` and `android.builtInKotlin=false` on AGP 9 for
Flutter's current migration bridge and compatibility with the full version range.
Toolchain compatibility does not expand OS APIs or prove device detection efficacy.

`SecurityDetectors.developerMode` and `SecurityDetectors.usbDebugging` are included
in the environment group. Android reports detected only for an explicit enabled
public setting; zero is unsupported/settingReadRestricted because it may be
redacted. Missing or failed reads stay errors. iOS is unsupported. These signals
do not mean a debugger is attached or wireless debugging is enabled.
