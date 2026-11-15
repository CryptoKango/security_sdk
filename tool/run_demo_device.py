#!/usr/bin/env python3
"""Run example on an explicit simulator. Loopback coordination exists only in tests."""
import argparse
import http.server
import json
import os
import re
import xml.etree.ElementTree as ET
from pathlib import Path
import secrets
import signal
import subprocess
import threading
import time

from demo_validation import validate_evidence


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--platform', choices=['android', 'ios'], required=True)
    p.add_argument('--device', required=True)
    p.add_argument('--flutter', required=True)
    p.add_argument('--adb', default='adb')
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if a.platform == 'android' and not a.device.startswith('emulator-'):
        p.error('This runner only accepts an Android emulator')
    # simctl operations below require a simulator UDID, never a physical iOS device.
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[1]
    app = root / 'example'
    token = secrets.token_hex(24)
    recording = None
    system_recording = False
    record_tile = None
    recording_log = None
    actions = []
    def command(args, **kwargs):
        return subprocess.run(args, check=True, timeout=40, capture_output=True, **kwargs)
    def adb(*args): return command([a.adb, '-s', a.device, *args])
    def sim(*args): return command(['xcrun', 'simctl', *args])
    def screenshot(name):
        path = out / (name + '.png')
        if a.platform == 'android': path.write_bytes(adb('exec-out', 'screencap', '-p').stdout)
        else: sim('io', a.device, 'screenshot', str(path))
        if not path.exists() or path.stat().st_size == 0: raise RuntimeError('Empty screenshot')
    def return_to_app():
        if a.platform == 'android':
            adb('shell', 'cmd', 'statusbar', 'collapse')
            adb('shell', 'am', 'start', '-n', 'dev.securitysdk.security_sdk_demo/.MainActivity')
        else:
            sim('launch', a.device, 'dev.securitysdk.securitySdkDemo')
        time.sleep(2)
    def tap_system(label, optional=False):
        # Only the emulator's observed English SystemUI labels are supported.
        adb('shell', 'rm', '-f', '/sdcard/security-demo-ui.xml')
        dump = adb('shell', 'uiautomator', 'dump', '/sdcard/security-demo-ui.xml')
        if b'UI hierchary dumped to:' not in dump.stdout: raise RuntimeError('SystemUI did not become idle')
        tree = ET.fromstring(adb('shell', 'cat', '/sdcard/security-demo-ui.xml').stdout)
        nodes = [n for n in tree.iter('node') if n.get('package') == 'com.android.systemui'
                 and (n.get('text') == label or n.get('content-desc', '').startswith(label + ','))]
        if not nodes:
            if optional: return None
            raise RuntimeError('Required SystemUI control unavailable')
        bounds = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', nodes[0].get('bounds', ''))
        if bounds is None: raise RuntimeError('Invalid SystemUI bounds')
        x1,y1,x2,y2 = map(int, bounds.groups())
        adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        time.sleep(1)
        return ((x1+x2)//2, (y1+y2)//2)
    def projection_active():
        return b'TYPE_SCREEN_CAPTURE' in adb('shell', 'dumpsys', 'media_projection').stdout
    def stop_record():
        nonlocal recording, recording_log, system_recording
        if system_recording and not projection_active():
            system_recording = False
            return_to_app()
        if system_recording:
            adb('shell', 'cmd', 'statusbar', 'expand-settings')
            time.sleep(2)
            # Recording timer prevents uiautomator idle; reuse this run's observed
            # tile position. Rotation/tile edits are outside this fixed-profile run.
            screenshot('stop-recording-controls')
            if record_tile is None: raise RuntimeError('Missing owned recorder control')
            adb('shell', 'input', 'tap', *map(str, record_tile))
            time.sleep(2)
            if projection_active(): raise RuntimeError('System recording did not stop')
            system_recording = False
            return_to_app()
        if recording is None: return
        if a.platform == 'ios' and recording.poll() is None: recording.send_signal(signal.SIGINT)
        recording.wait(timeout=20)
        if recording.returncode != 0: raise RuntimeError('Recording exporter failed')
        recording = None
        if recording_log: recording_log.close(); recording_log = None
        if a.platform == 'android':
            adb('pull', '/sdcard/security-sdk-demo.mp4', str(out / 'export.mp4'))
            adb('shell', 'rm', '/sdcard/security-sdk-demo.mp4')
        if not (out/'export.mp4').exists() or (out/'export.mp4').stat().st_size == 0:
            raise RuntimeError('Empty recording')
    def action(phase):
        nonlocal recording, recording_log, system_recording, record_tile
        if phase == 'screenshot':
            screenshot('screenshot')
            return {'kind':'externalExport', 'artifact':True}
        if phase == 'record_start':
            if a.platform == 'android':
                if projection_active(): raise RuntimeError('A recording already exists')
                adb('shell', 'cmd', 'statusbar', 'expand-settings')
                time.sleep(2)
                record_tile = tap_system('Screen record')
                if tap_system('A single app', optional=True) is not None:
                    tap_system('Entire screen')
                tap_system('Start recording')
                # Own the cleanup from the moment Start is accepted, even on timeout.
                system_recording = True
                time.sleep(5)
                if not projection_active(): raise RuntimeError('No active MediaProjection')
                return_to_app()
                screenshot('during-recording')
                return {'kind':'systemMediaProjection', 'started':True}
            recording_log = (out/'recording.log').open('w')
            cmd = [a.adb,'-s',a.device,'shell','screenrecord','--time-limit','8','/sdcard/security-sdk-demo.mp4'] if a.platform == 'android' else ['xcrun','simctl','io',a.device,'recordVideo',str(out/'export.mp4')]
            recording = subprocess.Popen(cmd,stdout=recording_log,stderr=subprocess.STDOUT)
            time.sleep(1)
            if recording.poll() is not None: raise RuntimeError('Exporter did not stay running')
            return {'kind':'externalExport', 'started':True}
        if phase == 'record_stop':
            stop_record()
            return {'kind':'systemMediaProjection' if a.platform == 'android' else 'externalExport', 'stopped':True}
        if phase == 'background':
            if a.platform == 'android': adb('shell','input','keyevent','3')
            else: sim('launch',a.device,'com.apple.Preferences')
            time.sleep(2)
            screenshot('background')
            return_to_app()
            return {'kind':'realAppSwitch', 'returned':True}
        if phase == 'final_view':
            screenshot('final')
            return {'artifact':True}
        raise ValueError('Unknown phase')
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def do_POST(self):
            if self.headers.get('X-Test-Token') != token:
                self.send_error(403); return
            phase = self.path.strip('/')
            try:
                data = action(phase)
                actions.append({'phase':phase, 'status':'passed', **data})
                body = json.dumps(data).encode()
                self.send_response(200)
            except Exception:
                actions.append({'phase':phase,'status':'failed'})
                body = b'{"error":"hostActionFailed"}'
                self.send_response(500)
            self.send_header('Content-Type','application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)
    server = http.server.HTTPServer(('127.0.0.1',0), Handler)
    port = server.server_port
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report = {'schemaVersion':1, 'platform':a.platform,'status':'failed','buildValidated':False,'actions':actions}
    try:
        if a.platform == 'ios':
            devices = json.loads(sim('list', 'devices', 'booted', '-j').stdout)['devices']
            if not any(d['udid'] == a.device for group in devices.values() for d in group):
                raise RuntimeError('Expected a booted iOS simulator')
        else:
            if adb('shell', 'getprop', 'ro.kernel.qemu').stdout.strip() != b'1':
                raise RuntimeError('Expected an Android emulator')
            if int(adb('shell', 'getprop', 'ro.build.version.sdk').stdout) < 35:
                raise RuntimeError('System recording profile requires API 35+')
        if a.platform == 'android': adb('reverse',f'tcp:{port}',f'tcp:{port}')
        env = dict(os.environ, DEMO_REPORT=str(out/'observations.json'),
                   FLUTTER_SWIFT_PACKAGE_MANAGER='false', FLUTTER_UISCENE_MIGRATION='false')
        defines = [f'--dart-define=DEMO_TEST_PORT={port}',f'--dart-define=DEMO_TEST_TOKEN={token}']
        build = [a.flutter,'build'] + (['apk'] if a.platform == 'android' else ['ios','--simulator']) + ['--debug','--no-pub','--target=integration_test/demo_device_test.dart'] + defines
        binary = app / ('build/app/outputs/flutter-apk/app-debug.apk' if a.platform == 'android' else 'build/ios/iphonesimulator/Runner.app')
        with (out/'build.log').open('w') as log:
            subprocess.run(build,cwd=app,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1200)
        if not binary.exists(): raise RuntimeError('Missing built binary')
        report['buildValidated'] = True
        drive = [a.flutter,'drive','--driver=test_driver/device_driver.dart','--target=integration_test/demo_device_test.dart','-d',a.device,'--no-pub','--no-start-paused',f'--use-application-binary={binary}']
        with (out/'drive.log').open('w') as log:
            subprocess.run(drive,cwd=app,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=600)
        evidence = json.loads((out/'observations.json').read_text())
        validate_evidence(a.platform, evidence, actions)
        report['status'] = 'passed'
        report['screenshotPositiveAcceptance'] = 'pendingPhysicalDevice'
        report['recordingPositiveAcceptance'] = 'passedSystemMediaProjection' if a.platform == 'android' else 'pendingPhysicalDevice'
    except Exception:
        # Never print raw command lines: build arguments contain a test-only token.
        report['reason'] = 'executionOrEvidenceFailed'
    finally:
        try: stop_record()
        except Exception: report['status'] = 'failed'; report['cleanupFailed'] = True
        server.shutdown(); server.server_close()
        if a.platform == 'android':
            try: adb('reverse','--remove',f'tcp:{port}')
            except Exception: report['status'] = 'failed'; report['cleanupFailed'] = True
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    if report['status'] != 'passed': raise SystemExit(1)
    print(json.dumps(report, indent=2))

if __name__ == '__main__': main()
