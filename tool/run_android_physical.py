#!/usr/bin/env python3
"""Opt-in Android hardware regression with operator-driven system capture UI.

Only the example is installed. System settings are not changed. Screenshot and
recording positives must come from OS callbacks, not adb image/video exports.
No screen artifacts or device identifiers are written to the evidence report.
"""
import argparse
import http.server
import json
import os
from pathlib import Path
import secrets
import select
import sys
import subprocess
import threading
import time

from demo_validation import validate_evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--skip-screenshot', action='store_true', help='Run only the remaining profile; screenshot acceptance stays notRun')
    args = parser.parse_args()
    if args.device.startswith('emulator-'):
        parser.error('Use run_demo_device.py for emulators')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    app = Path(__file__).resolve().parents[1] / 'example'
    actions = []
    token = secrets.token_hex(24)
    recording_requested = False

    def adb(*parts):
        return subprocess.run([args.adb, '-s', args.device, *parts], check=True,
                              capture_output=True, timeout=30).stdout

    def projection_active():
        return b'TYPE_SCREEN_CAPTURE' in adb('shell', 'dumpsys', 'media_projection')

    def acknowledge(phase):
        print('AWAITING ' + phase + ': perform the system action, then enter done (or fail).', flush=True)
        if not select.select([sys.stdin], [], [], 240)[0] or input().strip() != 'done':
            raise RuntimeError('Operator did not confirm action')

    def return_to_app():
        adb('shell', 'cmd', 'statusbar', 'collapse')
        adb('shell', 'am', 'start', '-n', 'dev.securitysdk.security_sdk_demo/.MainActivity')
        time.sleep(2)

    def action(phase):
        nonlocal recording_requested
        if phase == 'screenshot':
            acknowledge(phase)
            return {'kind': 'systemScreenshot'}
        if phase == 'record_start':
            if projection_active():
                raise RuntimeError('Recording already active')
            recording_requested = True
            acknowledge(phase)
            deadline = time.monotonic() + 12
            while not projection_active() and time.monotonic() < deadline:
                time.sleep(0.5)
            if not projection_active():
                raise RuntimeError('System recording did not start')
            return_to_app()
            return {'kind': 'systemMediaProjection', 'started': True}
        if phase == 'record_stop':
            acknowledge(phase)
            if projection_active():
                raise RuntimeError('System recording did not stop')
            recording_requested = False
            return_to_app()
            return {'kind': 'systemMediaProjection', 'stopped': True}
        if phase == 'background':
            if projection_active():
                raise RuntimeError('Refuse background switching while recording')
            adb('shell', 'input', 'keyevent', '3')
            time.sleep(2)
            return_to_app()
            return {'kind': 'realAppSwitch', 'returned': True}
        if phase == 'final_view':
            # The Flutter test asserts the visible example controls; no phone
            # screenshots or notification/home-screen data are exported here.
            return {'checked': True}
        raise ValueError('Unknown test phase')

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            if self.headers.get('X-Test-Token') != token:
                self.send_error(403)
                return
            phase = self.path.strip('/')
            if phase in [a['phase'] for a in actions]:
                self.send_error(409)
                return
            try:
                result = action(phase)
                actions.append({'phase': phase, 'status': 'passed', **result})
                payload = json.dumps(result).encode()
                self.send_response(200)
            except Exception:
                actions.append({'phase': phase, 'status': 'failed'})
                payload = b'{"error":"hostActionFailed"}'
                self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
    port = server.server_port
    threading.Thread(target=server.serve_forever, daemon=True).start()
    report = {'schemaVersion': 1, 'platform': 'android', 'profile': 'physicalWithoutScreenshot' if args.skip_screenshot else 'physical',
              'status': 'failed', 'buildValidated': False, 'actions': actions}
    reverse_added = False
    try:
        if adb('get-state').strip() != b'device':
            raise RuntimeError('Device not authorized')
        if adb('shell', 'getprop', 'ro.kernel.qemu').strip() == b'1':
            raise RuntimeError('Physical device required')
        api = int(adb('shell', 'getprop', 'ro.build.version.sdk'))
        if api < 35:
            raise RuntimeError('Recording regression requires API 35+')
        report['androidApi'] = api
        if projection_active():
            raise RuntimeError('Do not interrupt an existing recording')
        adb('reverse', f'tcp:{port}', f'tcp:{port}')
        reverse_added = True
        env = dict(os.environ, DEMO_REPORT=str(out / 'observations.json'))
        defines = ['--dart-define=DEMO_PHYSICAL_ANDROID=true',
                   '--dart-define=DEMO_SKIP_SCREENSHOT=' + str(args.skip_screenshot).lower(),
                   f'--dart-define=DEMO_TEST_PORT={port}', f'--dart-define=DEMO_TEST_TOKEN={token}']
        target = 'integration_test/demo_device_test.dart'
        binary = app / 'build/app/outputs/flutter-apk/app-debug.apk'
        print('Building physical-device regression example...', flush=True)
        with (out / 'build.log').open('w') as log:
            subprocess.run([args.flutter, 'build', 'apk', '--debug', '--no-pub', '--target=' + target, *defines],
                           cwd=app, env=env, check=True, timeout=1200, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        report['buildValidated'] = True
        adb('shell', 'cmd', 'statusbar', 'collapse')
        print('Running scan, capture and lifecycle regression...', flush=True)
        with (out / 'drive.log').open('w') as log:
            subprocess.run([args.flutter, 'drive', '--driver=test_driver/device_driver.dart',
                            '--target=' + target, '-d', args.device, '--no-pub', '--no-start-paused',
                            '--use-application-binary=' + str(binary)], cwd=app, env=env, check=True,
                           timeout=1800, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        evidence = json.loads((out / 'observations.json').read_text())
        validate_evidence('android', evidence, actions, physical_android=True, screenshot_executed=not args.skip_screenshot)
        if not args.skip_screenshot:
            screenshot = next(f for f in evidence['afterScreenshot'] if f['id'] == 'screenshot')
            report['screenshotObservationInterrupted'] = screenshot['reason'] == 'observationInterrupted'
        report.update(status='passed', screenshotPositiveAcceptance='notRun' if args.skip_screenshot else 'passedSystemScreenshot',
                      recordingPositiveAcceptance='passedSystemMediaProjection')
    except Exception:
        report['reason'] = 'executionOrEvidenceFailed'
    finally:
        # Only ask to stop a recording if this test entered its start phase.
        if recording_requested:
            try:
                if projection_active():
                    acknowledge('cleanup_recording_stop')
                    if projection_active():
                        raise RuntimeError('Recording still active')
            except Exception:
                report.update(status='failed', cleanupFailed=True)
        server.shutdown()
        server.server_close()
        if reverse_added:
            try:
                adb('reverse', '--remove', f'tcp:{port}')
            except Exception:
                report.update(status='failed', cleanupFailed=True)
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2), flush=True)
    if report['status'] != 'passed':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
