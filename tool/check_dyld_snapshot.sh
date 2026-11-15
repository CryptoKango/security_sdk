#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/security-dyld-snapshot.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
printf 'int security_snapshot_fixture(void) { return 7; }\n' > "$work_dir/fixture.c"
xcrun clang -dynamiclib "$work_dir/fixture.c" -o "$work_dir/fixture.dylib"
source_dir=packages/security_flutter/ios/security_flutter/Sources/security_flutter
xcrun swiftc -O "$source_dir/LocalFinding.swift" "$source_dir/RuntimePolicy.swift" \
  "$source_dir/LoadedImageProbe.swift" "$source_dir/DyldImageSnapshot.swift" \
  packages/security_flutter/ios/Tests/DyldSnapshotTests.swift -o "$work_dir/tests"
"$work_dir/tests" "$work_dir/fixture.dylib"
