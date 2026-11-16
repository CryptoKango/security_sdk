#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/security-sdk-swift.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
source_dir=packages/security_flutter/ios/security_flutter/Sources/security_flutter
xcrun swiftc "$source_dir/LocalFinding.swift" "$source_dir/RuntimePolicy.swift" \
  "$source_dir/BundleIntegrityVerifier.swift" "$source_dir/LoadedImageProbe.swift" "$source_dir/DyldImageSnapshot.swift" \
  packages/security_flutter/ios/Tests/RuntimePolicyTests.swift -o "$work_dir/runtime-policy-tests"
"$work_dir/runtime-policy-tests"

for build_mode in release debug; do
  if [ "$build_mode" = release ]; then
    xcrun swiftc -O "$source_dir/LocalFinding.swift" "$source_dir/ProcessTraceProbe.swift" \
      packages/security_flutter/ios/Tests/ProcessTraceProbeTests.swift -o "$work_dir/process-trace-tests"
  else
    xcrun swiftc -Onone -D DEBUG "$source_dir/LocalFinding.swift" "$source_dir/ProcessTraceProbe.swift" \
      packages/security_flutter/ios/Tests/ProcessTraceProbeTests.swift -o "$work_dir/process-trace-tests"
  fi
  "$work_dir/process-trace-tests"
done

xcrun swiftc "$source_dir/LocalFinding.swift" "$source_dir/MachOExecutablePolicy.swift" "$source_dir/IOSContainerProbe.swift" \
  packages/security_flutter/ios/Tests/IOSContainerProbeTests.swift -o "$work_dir/container-tests"
"$work_dir/container-tests"

xcrun swiftc "$source_dir/MachOExecutablePolicy.swift" \
  packages/security_flutter/ios/Tests/MachOExecutablePolicyTests.swift -o "$work_dir/macho-tests"
"$work_dir/macho-tests"

xcrun swiftc "$source_dir/LocalFinding.swift" "$source_dir/LocationMetadataPolicy.swift" "$source_dir/TunnelInterfacePolicy.swift" \
  packages/security_flutter/ios/Tests/CompatibilityPolicyTests.swift -o "$work_dir/compatibility-tests"
"$work_dir/compatibility-tests"

xcrun swiftc "$source_dir/LocalFinding.swift" "$source_dir/CaptureObservation.swift" \
  packages/security_flutter/ios/Tests/CaptureObservationTests.swift -o "$work_dir/capture-tests"
"$work_dir/capture-tests"

# Includes live macOS loader churn, not an iOS device efficacy claim.
sh tool/check_dyld_snapshot.sh

xcrun swiftc "$source_dir/DeviceInformation.swift" \
  packages/security_flutter/ios/Tests/DeviceInformationTests.swift -o "$work_dir/device-info-tests"
"$work_dir/device-info-tests"
