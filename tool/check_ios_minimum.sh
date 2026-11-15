#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Usage: sh tool/check_ios_minimum.sh /absolute/path/to/flutter_sdk
# Availability/type checking, not execution on an iOS 13 device.
security_flutter_sdk=${1:?Pass the Flutter SDK directory}
framework_dir="$security_flutter_sdk/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64"
[ -d "$framework_dir" ] || { echo 'Run flutter precache --ios for this SDK first' >&2; exit 1; }
sdk_path=$(xcrun --sdk iphoneos --show-sdk-path)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/security-ios-minimum.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
xcrun --sdk iphoneos swiftc -typecheck -target arm64-apple-ios13.0 -sdk "$sdk_path" \
  -F "$framework_dir" -module-cache-path "$work_dir/cache" -module-name security_flutter \
  packages/security_flutter/ios/security_flutter/Sources/security_flutter/*.swift
printf 'iOS 13 arm64 availability/type check passed (no device execution)\n'
