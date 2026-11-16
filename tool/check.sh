#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
dart format --output=none --set-exit-if-changed packages example/lib example/test example/integration_test example/test_driver
dart analyze packages/security_core
flutter analyze --no-pub packages/security_flutter
if [ "${CHECK_NATIVE_FIXTURE:-0}" = "1" ]; then
  (cd test_apps/native_validation && flutter pub get && dart format --output=none --set-exit-if-changed lib integration_test test_driver && flutter analyze --no-pub)
fi
flutter analyze --no-pub example
(cd packages/security_core && dart test)
(cd packages/security_flutter && flutter test --no-pub)
(cd example && flutter test --no-pub)

python3 -m unittest discover -s tool -p test_window_validation.py

python3 -m unittest discover -s tool -p test_demo_validation.py

python3 -m unittest discover -s tool -p test_flutter_compatibility.py

python3 -m unittest discover -s tool -p test_capture_probe_validation.py

python3 -m unittest discover -s tool -p test_physical_lifecycle_validation.py

python3 -m unittest discover -s tool -p test_projection_validation.py

python3 -m unittest discover -s tool -p test_process_restart_validation.py
