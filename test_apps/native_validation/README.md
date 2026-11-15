# Native validation test app

Internal Android/iOS regression host for native detector integration, multiple
Flutter engines, real Scene creation/destruction, split-screen and PiP. For public
API usage and the runnable integration demo, use [example/](../../example/README.md).

Requires Flutter >=3.44.9 / Dart >=3.12.2. This test app resolves dependencies
independently of the portable SDK workspace. Its development-only
`pubspec_overrides.yaml` links the local SDK through `../../packages/`; its higher
minimum does not constrain SDK consumers. Application IDs remain unchanged so
existing explicit-device validation and the Android companion still address the
same test apps.

From this directory:

```sh
flutter pub get
flutter run
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/native_signals_test.dart \
  -d <simulator-id> --no-start-paused
```

The scan button explicitly calls implemented native detectors. Results depend on
platform and environment; unsupported or error does not mean the device is safe.
No backend, account or third-party fingerprint provider is required.

From the repository root, `CHECK_NATIVE_FIXTURE=1 sh tool/check.sh` also checks
this test app. For the actual OS-mode runners, companion setup and remaining
physical-device checks, see [real window validation](../../docs/real_window_validation.md).
These use `tool/run_window_validation.py` and an explicitly selected device.
Multi-Scene/PiP controls and background capabilities are Debug-only; signing team
and deployment credentials are not included.
