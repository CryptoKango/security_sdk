#!/usr/bin/env python3
"""Explicit-device OS validation. Blocked != passed. Uses only Python stdlib."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

SCENARIOS = ("android_split", "ios_scenes", "ios_pip")

def validate_report(report, scenario):
    if not isinstance(report, dict) or type(report.get("schemaVersion")) is not int or report["schemaVersion"] != 1 or report.get("scenario") != scenario:
        raise ValueError("Invalid schema/scenario")
    status = report.get("status")
    if status not in ("passed", "blocked", "failed") or not isinstance(report.get("reason"), str) or not report["reason"]:
        raise ValueError("Missing explicit outcome")
    if status != "passed":
        return 3 if status == "blocked" else 1
    if report.get("buildValidated") is not True: raise ValueError("No validated build")
    e = report.get("evidence", {})
    def require(value):
        if not value: raise ValueError("Passed report lacks required OS/SDK evidence")
    require(isinstance(e, dict))
    def yes(m, key): return isinstance(m, dict) and m.get(key) is True
    def count(m, key):
        require(isinstance(m, dict))
        value = m.get(key)
        require(type(value) is int and value >= 0)
        return value
    if scenario == "android_split":
        s, restored, capture = e.get("split", {}), e.get("restored", {}), e.get("unfocusedCapture", {})
        require(all(yes(s,k) for k in ("mainMultiWindow", "peerMultiWindow", "peerFocus", "peerReceived")))
        require(capture == {"status":"error", "reason":"observationInterrupted"})
        require(restored.get("mainMultiWindow") is False and all(yes(restored,k) for k in ("mainFocus", "mainResumed", "peerClosed")))
    elif scenario == "ios_scenes":
        require(count(e,"finalRegistryCount") == 0)
        cycles = e.get("cycles")
        require(type(e.get("requestedCycles")) is int and e["requestedCycles"] == 3)
        require(isinstance(cycles, list) and len(cycles) == 3)
        for index, cycle in enumerate(cycles, 1):
            require(isinstance(cycle, dict) and type(cycle.get("cycle")) is int and cycle["cycle"] == index)
            c, closed, before = cycle.get("connected", {}), cycle.get("closed", {}), cycle.get("beforeClose", {})
            require(all(isinstance(m, dict) for m in (c, closed, before)))
            require(all(yes(c,k) for k in ("connected", "ready", "distinctScenes", "freshSession", "configurationNamed", "engineStarted", "pluginRegistered")))
            require(count(c,"cyclesStarted") == index and count(c,"registryCount") == 1)
            require(type(before.get("peerActive")) is bool)
            require(cycle.get("inactiveCloseRejected") is (not before["peerActive"]))
            require(yes(cycle.get("closeTarget", {}), "peerActive"))
            require(cycle.get("peerBeforeStart") == {"status":"error", "reason":"observationRequired"})
            require(cycle.get("peerCapture") == {"status":"notDetected", "reason":"noKnownSignal"})
            require(all(yes(closed,k) for k in ("detached", "mainActive", "sessionDiscarded", "resourcesReleased", "engineReleased", "pluginReleased", "controllerReleased", "contextDestroyed")))
            require(all(closed.get(k) is False for k in ("connected", "systemConnected", "sessionRegistered")))
            require(count(closed,"disconnectCallbacks") == 1 and count(closed,"teardownCount") == 1)
            expected = {"status":"notDetected", "reason":"noKnownSignal"} if count(before,"mainInterruptions") == count(closed,"mainInterruptions") else {"status":"error", "reason":"observationInterrupted"}
            require(cycle.get("mainAfterClose") == expected)
            require(cycle.get("mainRestarted") == {"status":"notDetected", "reason":"noKnownSignal"})
    else:
        prepared, active, stopped = e.get("prepared", {}), e.get("active", {}), e.get("stopped", {})
        require(yes(prepared,"possible") and yes(active,"active") and count(active,"starts") > 0)
        require(stopped.get("active") is False and count(stopped,"stops") > 0)
        expected = "notDetected" if yes(active,"mainActive") and count(prepared,"mainInterruptions") == count(active,"mainInterruptions") else "error"
        require(e.get("duringPip", {}).get("status") == expected)
    return 0

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=SCENARIOS, required=True)
    parser.add_argument("--device", required=True, help="Explicit Flutter device ID; no automatic selection")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--ios-device", action="store_true", help="Build a signed iOS device app instead of the default simulator app")
    parser.add_argument("--report", type=Path, required=True, help="New JSON path; existing artifacts never reused")
    args = parser.parse_args()
    report = args.report.resolve(); log = report.with_suffix(".log")
    if report.exists() or log.exists(): parser.error("Report/log already exists; choose a new path")
    report.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, SECURITY_VALIDATION_REPORT=str(report))
    example = Path(__file__).resolve().parents[1]/"test_apps/native_validation"
    defines = ["--dart-define=VALIDATION_SCENARIO=" + args.scenario]
    build = [args.flutter, "build"] + (["apk"] if args.scenario == "android_split" else ["ios"] + ([] if args.ios_device else ["--simulator"]))
    build += ["--debug", "--target=integration_test/real_window_test.dart", "--no-pub"] + defines
    binary = example / ("build/app/outputs/flutter-apk/app-debug.apk" if args.scenario == "android_split" else
                        "build/ios/iphoneos/Runner.app" if args.ios_device else "build/ios/iphonesimulator/Runner.app")
    command = [args.flutter, "drive", "--driver=test_driver/window_validation.dart", "--target=integration_test/real_window_test.dart",
               "-d", args.device, "--no-pub", "--no-start-paused", "--use-application-binary=" + str(binary)] + defines
    try:
        with log.open("x") as output:
            dependencies = subprocess.run([args.flutter, "pub", "get"], cwd=example, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=300)
            if dependencies.returncode != 0: raise ValueError("Fixture dependency resolution failed")
            built = subprocess.run(build, cwd=example, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=1200)
            if built.returncode != 0 or not binary.exists(): raise ValueError("Build failed; refusing an installed/stale binary")
            completed = subprocess.run(command, cwd=example, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=1200)
        if completed.returncode != 0: raise ValueError("Flutter execution/teardown failed; no passing result accepted")
        data = json.loads(report.read_text()); data["buildValidated"] = True
        code = validate_report(data, args.scenario)
        report.write_text(json.dumps(data, indent=2))
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        try:
            try:
                data = json.loads(report.read_text()) if report.exists() else {}
            except ValueError:
                data = {}
            if not isinstance(data, dict): data = {}
            data.update(schemaVersion=1, scenario=args.scenario, status="failed", reason="executionOrReportValidationFailed")
            report.write_text(json.dumps(data, indent=2))
        except (OSError, ValueError): pass
        print(f"FAILED: {error}; log: {log}")
        return 1
    print(f"{args.scenario}: {['PASSED', 'FAILED', '', 'BLOCKED'][code]}; report: {report}")
    return code

if __name__ == "__main__": sys.exit(main())
