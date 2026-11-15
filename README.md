# Security SDK (development)

Independent Dart/Flutter packages for explicit local security observations.
Package names are provisional. No package is published; `publish_to: none` remains
until names, publisher, license, compatibility and release review are complete.

## Implemented scope

- `security_core`: immutable observations, closed reason codes, cancellation,
  trusted-time comparison and authorized host-supplied location-source assessment.
- `security_flutter`: Android/iOS environment signals, explicit screenshot
  observation windows, native screen-capture snapshots, defensive channel parsing,
  per-instance cleanup, deadlines and cancellation.
- `example/`: runnable Android/iOS integration demo, explicit scans and capture controls.
- `test_apps/native_validation`: native lifecycle/integration validation host.

See [the precise detection matrix and integration guide](docs/detection_coverage.md).
Support is platform/API dependent. Android clone/automation checks and iOS VPN
checks are heuristics. Accessibility, VPN and managed profiles are legitimate
features, not proof of abuse. `notDetected` is not proof of safety. Unsupported,
missing permissions and absent/stale inputs stay distinct from negative results.

Root/jailbreak and hook indicators, debugger observations and host-baseline app
integrity checks are implemented with platform-specific limits. See
[the runtime detection guide](docs/runtime_security.md). iOS Release process-trace
checks require explicit request-level opt-in because of the unstable process-info
ABI; see [Release debugger detection](docs/ios_release_debugger.md). iOS integrity
compares selected bundle files, not Apple signatures or platform attestation.
Third-party fingerprinting is intentionally not implemented. Attestation adapters,
general event streams and hardware keys are also outside this implementation.

No HTTP client, backend URL, telemetry, automatic scan, account model, coordinate
collection, persistent cache or business enforcement is included. Hosts own legal
basis/consent, permissions, trusted time, business location acquisition, lifecycle,
reporting and authorization. The SDK does not add optional Android permissions to
host manifests; the example declares its own demonstration permissions.

See [the runnable example](example/README.md) for setup, state semantics and host-supplied inputs.

## Development

Minimum: Dart 3.10.9 / Flutter 3.38.10. Flutter has no upper-version constraint;
Dart remains below 4.0. The plugin keeps Android minSdk 24 / compileSdk 36 and
iOS 13 as its own floor; the effective app floor also follows Flutter (iOS 15+
for Flutter 3.50).
The portable Android example requires an installed JDK 17 and selects it using
project-local Gradle Daemon JVM criteria (including when Flutter selects a newer JBR).
See [Flutter compatibility](docs/flutter_compatibility.md) for executed version
checks, Android toolchain selection and the rolling stable CI lane.

```sh
python3 tool/configure_example_android.py --flutter /absolute/path/to/flutter
flutter pub get
sh tool/check.sh
# macOS/Xcode: native Swift policy and resource-isolation tests
sh tool/check_swift_policy.sh
cd example
flutter run
# Android native logic tests (JDK 17+; use your installed supported JDK):
cd android
./gradlew :security_flutter:testDebugUnitTest
```

The simulator-only native integration test lives in
`test_apps/native_validation/integration_test/native_signals_test.dart`. From the
fixture directory, using Flutter 3.44.9 or newer, run:

```sh
flutter pub get
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/native_signals_test.dart \
  -d <simulator-id> --no-start-paused
```

It is a native API/lifecycle test and constructs no Flutter widgets. It expects
an emulator/simulator and Android 14+ for screenshot observation. The documented
verification run used the iOS 26.5 simulator; Android runtime validation remains
in the acceptance matrix.

The portable workspace uses version dependencies. The independent
`test_apps/native_validation` Scene/PiP fixture uses development-only local overrides
and does not raise the public packages' minimum Flutter version. Native
organization, podspec metadata and license are placeholders. Validate standalone
hosted consumers before publication. See [roadmap](docs/roadmap.md) and
[security boundaries](SECURITY.md).

See [the detection review](docs/review_findings.md) for repaired false-positive paths,
remaining gaps and the order of device validation work.

Native local-v2 first added bounded root-mount, known memfd/injection-origin and
Android container identity checks. See [the hidden-environment guide](docs/hidden_environment.md)
for false-positive controls and remaining gaps. No device fingerprinting is added.

Native local-v3 adds limited iOS application-executable/container signals and
public-API-gated Android profile handling. Ambiguous OEM/private profiles remain
unsupported; profile IDs, brands, iPad scenes and ordinary bundled dylibs do not
establish cloning. See [the iOS/OEM multi-instance guide](docs/ios_oem_multi_instance.md) for
coverage, reasons and remaining device validation. Third-party fingerprinting is
still deferred.

Native local-v4 tightens active tunnel matching and invalid location metadata
handling. Low-OS framework regressions and an iOS 13 availability check are now
provided; see `docs/compatibility_review.md` in the repository. Unknown location
sources stay unknown. No third-party fingerprinting was added.

Capture lifecycle, multi-engine ownership, interruption recovery and recording
attribution limits are documented in [capture_lifecycle.md](docs/capture_lifecycle.md).
Native local-v5 adds lifecycle regressions and real headless-engine integration
fixtures; physical capture and multi-Scene device validation remain separate.

Native local-v6 scopes iOS activation observers to their own Scene (App events only
for legacy hosts), binds capture to Window/Scene/Screen identity, and repairs Android
decor reattachment/focus observation. Android PiP cannot satisfy foreground capture
prerequisites. Geometry-only changes preserve accumulated evidence; real gaps stay
unknown. See `docs/scene_window_lifecycle.md` in the repository for limits and tests.
No third-party fingerprinting was added.


Real OS window validation (test hosts only): see
[real_window_validation.md](docs/real_window_validation.md) for explicit-device
multi-Scene, dual-app split-screen and iOS AVKit PiP runners, evidence requirements,
and the remaining physical-device matrix. Failed/blocked runs are never counted
as successful coverage. No fingerprint provider is included.

Android local-v7 adds current-user CLONE profile detection on API 35+, known Root
framework directories in system overlay backing paths, and executable LSPatch
module names. iOS now uses local-v8 after its subsequent snapshot review. Private/unknown profiles remain unsupported;
these observations are not maliciousness verdicts. See the separate
[physical-device acceptance matrix](docs/hidden_environment_acceptance.md).

iOS local-v7 adds exact ElleKit/system injection origins, bounded image-name reads
and best-effort image identity revalidation. Concurrency and fully hidden images
remain limitations; see [iOS review and device acceptance](docs/ios_hidden_review.md).

iOS local-v8 copies self-task dyld metadata with public Mach VM reads and validates
its generation before accepting findings. No dyld-owned name pointer is directly
dereferenced. See [concurrency review and device acceptance](docs/ios_dyld_snapshot.md).

The runnable [example API guide](example/README.md#完整-api-演示索引) covers all 16
shipped detector IDs and the implemented SDK lifecycle/cancellation/input methods.
[Simulator results and physical-device checklist](docs/example_device_validation.md)
separate Android system recording acceptance from screenshot/iOS export-only checks.

Developer settings: `developerMode` and `usbDebugging` are independent Android
positive-only public-setting observations. A zero may be redacted, so it remains
unsupported; missing/invalid/read-failed values remain errors. iOS is explicitly
unsupported. See [developer-setting semantics and device checks](docs/developer_settings.md).

Findings expose optional immutable `values` for measured booleans, numeric readings
and explicit nulls. The example shows these alongside every SDK result field and
a detector-specific explanation. See [reading semantics](docs/finding_values.md);
absent readings are never inferred from a status.
