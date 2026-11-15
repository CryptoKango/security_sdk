import unittest
from unittest.mock import patch
import tempfile
from pathlib import Path
from types import SimpleNamespace
import json
import contextlib
import io
import run_window_validation as runner
from run_window_validation import validate_report

class ReportTests(unittest.TestCase):
    def report(self, scenario="ios_pip"):
        return {"buildValidated":True,"schemaVersion":1,"scenario":scenario,"status":"passed","reason":"assertionsCompleted","evidence":{
            "prepared":{"possible":True,"mainInterruptions":0},
            "active":{"active":True,"starts":1,"mainActive":True,"mainInterruptions":0},
            "stopped":{"active":False,"stops":1}, "duringPip":{"status":"notDetected"}}}
    def test_stale_binary_pass_is_rejected(self):
        r=self.report();r.pop("buildValidated")
        with self.assertRaises(ValueError):validate_report(r,"ios_pip")
    def test_real_pip_evidence_passes(self): self.assertEqual(validate_report(self.report(),"ios_pip"),0)
    def test_blocked_is_nonzero(self):
        r=self.report();r.update(status="blocked",reason="pipNotPossible")
        self.assertEqual(validate_report(r,"ios_pip"),3)
    def test_assertion_failure_is_nonzero(self):
        r=self.report();r["status"]="failed";self.assertEqual(validate_report(r,"ios_pip"),1)
    def test_request_without_start_callback_cannot_pass(self):
        r=self.report();r["evidence"]["active"]["starts"]=0
        with self.assertRaises(ValueError):validate_report(r,"ios_pip")
    def test_inactive_scene_cannot_be_clean(self):
        r=self.report();r["evidence"]["active"]["mainActive"]=False
        with self.assertRaises(ValueError):validate_report(r,"ios_pip")
    def test_boolean_callback_count_is_invalid(self):
        r=self.report();r["evidence"]["active"]["starts"]=True
        with self.assertRaises(ValueError):validate_report(r,"ios_pip")
    def test_wrong_scenario_cannot_reuse_report(self):
        with self.assertRaises(ValueError):validate_report(self.report(),"android_split")
    def test_boolean_schema_is_invalid(self):
        r=self.report();r["schemaVersion"]=True
        with self.assertRaises(ValueError):validate_report(r,"ios_pip")
    def test_split_launch_alone_is_not_proof(self):
        with self.assertRaises(ValueError):validate_report(self.report("android_split"),"android_split")
    def test_connected_scene_without_detach_evidence_is_not_pass(self):
        with self.assertRaises(ValueError):validate_report(self.report("ios_scenes"),"ios_scenes")
class SceneEvidenceTests(unittest.TestCase):
    def report(self):
        cycles = []
        for number in range(1, 4):
            cycles.append({
                "cycle": number, "inactiveCloseRejected":True, "closeTarget":{"peerActive":True},
                "connected": dict(connected=True, ready=True, distinctScenes=True,
                    freshSession=True, configurationNamed=True, engineStarted=True, pluginRegistered=True,
                    cyclesStarted=number, registryCount=1),
                "peerBeforeStart": {"status":"error", "reason":"observationRequired"},
                "peerCapture": {"status":"notDetected", "reason":"noKnownSignal"},
                "beforeClose": {"mainInterruptions":2, "peerActive":False},
                "closed": dict(detached=True, mainActive=True, sessionDiscarded=True,
                    resourcesReleased=True, engineReleased=True, pluginReleased=True,
                    controllerReleased=True, contextDestroyed=True, connected=False,
                    systemConnected=False, sessionRegistered=False,
                    disconnectCallbacks=1, teardownCount=1, mainInterruptions=4),
                "mainAfterClose": {"status":"error", "reason":"observationInterrupted"},
                "mainRestarted": {"status":"notDetected", "reason":"noKnownSignal"}})
        return dict(schemaVersion=1, scenario="ios_scenes", status="passed",
                    reason="assertionsCompleted", buildValidated=True,
                    evidence={"requestedCycles":3, "finalRegistryCount":0, "cycles":cycles})

    def test_three_completed_rounds_pass(self):
        self.assertEqual(validate_report(self.report(), "ios_scenes"), 0)

    def reject_change(self, field, value):
        report = self.report()
        report["evidence"]["cycles"][1]["closed"][field] = value
        with self.assertRaises(ValueError): validate_report(report, "ios_scenes")

    def test_dual_active_without_own_interruption_can_stay_clean(self):
        report = self.report()
        for cycle in report["evidence"]["cycles"]:
            cycle["beforeClose"]["peerActive"] = True
            cycle["inactiveCloseRejected"] = False  # No inactive target in this mode.
            cycle["closed"]["mainInterruptions"] = 2
            cycle["mainAfterClose"] = {"status":"notDetected", "reason":"noKnownSignal"}
        self.assertEqual(validate_report(report, "ios_scenes"), 0)

    def test_engine_still_retained_fails(self): self.reject_change("engineReleased", False)
    def test_plugin_still_retained_fails(self): self.reject_change("pluginReleased", False)
    def test_controller_still_retained_fails(self): self.reject_change("controllerReleased", False)
    def test_os_session_still_present_fails(self): self.reject_change("sessionRegistered", True)
    def test_missing_real_disconnect_fails(self): self.reject_change("disconnectCallbacks", 0)
    def test_double_teardown_fails(self): self.reject_change("teardownCount", 2)
    def test_unnamed_configuration_cannot_pass(self):
        report = self.report(); report["evidence"]["cycles"][0]["connected"]["configurationNamed"] = False
        with self.assertRaises(ValueError): validate_report(report, "ios_scenes")
    def test_partial_cycles_cannot_pass(self):
        report = self.report(); report["evidence"]["cycles"].pop()
        with self.assertRaises(ValueError): validate_report(report, "ios_scenes")
    def test_replayed_round_cannot_pass(self):
        report = self.report(); report["evidence"]["cycles"][1] = report["evidence"]["cycles"][0]
        with self.assertRaises(ValueError): validate_report(report, "ios_scenes")
    def test_scene_switch_cannot_clear_interruption(self):
        report = self.report(); cycle = report["evidence"]["cycles"][1]
        cycle["mainAfterClose"] = {"status":"notDetected", "reason":"noKnownSignal"}
        with self.assertRaises(ValueError): validate_report(report, "ios_scenes")

class RunnerTests(unittest.TestCase):
    def test_relocated_host_drives_only_its_newly_built_artifact(self):
        host = Path(runner.__file__).resolve().parents[1]/"test_apps/native_validation"
        for relative in ["pubspec.yaml", "pubspec_overrides.yaml", "integration_test/real_window_test.dart",
                         "test_driver/window_validation.dart", "android/window_companion/build.gradle.kts"]:
            self.assertTrue((host/relative).is_file(), relative)
        for scenario in runner.SCENARIOS:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                report = Path(directory)/"report.json"
                argv = ["runner", "--scenario", scenario, "--device", "test-only", "--report", str(report)]
                binary = host/("build/app/outputs/flutter-apk/app-debug.apk" if scenario == "android_split"
                               else "build/ios/iphonesimulator/Runner.app")
                calls = []
                def execute(command, **kwargs):
                    self.assertEqual(kwargs["cwd"], host)
                    calls.append(command)
                    if "drive" in command:
                        self.assertIn("--use-application-binary=" + str(binary), command)
                        report.write_text(json.dumps(dict(schemaVersion=1, scenario=scenario,
                            status="blocked", reason="testEnvironmentUnavailable")))
                    return SimpleNamespace(returncode=0)
                original = Path.exists
                def exists(path): return True if path == binary else original(path)
                with patch("sys.argv", argv), patch.object(runner.subprocess, "run", side_effect=execute), patch.object(Path, "exists", exists):
                    with contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(runner.main(), 3)
                self.assertEqual(len(calls), 3)
                self.assertEqual(calls[0][1:], ["pub", "get"])
                self.assertEqual(calls[1][1], "build")
                self.assertEqual(calls[2][1], "drive")
                self.assertIn("--target=integration_test/real_window_test.dart", calls[1])
                self.assertEqual(json.loads(report.read_text())["status"], "blocked")

    def test_dependency_or_build_failure_never_drives_installed_app(self):
        for codes in ([1], [0, 1]):
            with self.subTest(exitCodes=codes), tempfile.TemporaryDirectory() as directory:
                report = Path(directory)/"report.json"
                argv = ["runner", "--scenario", "ios_pip", "--device", "test-only", "--report", str(report)]
                results = [SimpleNamespace(returncode=code) for code in codes]
                with patch("sys.argv", argv), patch.object(runner.subprocess, "run", side_effect=results) as run:
                    with contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(runner.main(), 1)
                self.assertEqual(run.call_count, len(codes))
                self.assertTrue(all("drive" not in call.args[0] for call in run.call_args_list))
                self.assertEqual(json.loads(report.read_text())["status"], "failed")
    def test_invalid_json_is_failed_not_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory)/"report.json"
            argv = ["runner", "--scenario", "ios_pip", "--device", "test-only", "--report", str(report)]
            def execute(command, **kwargs):
                if "drive" in command: report.write_text("invalid")
                return SimpleNamespace(returncode=0)
            # Path.exists is only patched after the CLI's new-path precondition.
            original = Path.exists
            def exists(path): return True if path.name == "Runner.app" else original(path)
            with patch("sys.argv", argv), patch.object(runner.subprocess, "run", side_effect=execute), patch.object(Path, "exists", exists):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(runner.main(), 1)
            self.assertEqual(json.loads(report.read_text())["status"], "failed")

if __name__ == "__main__": unittest.main()
