#!/usr/bin/env python3
"""Explicit Android hardware callback comparison; terminal confirmation after ready."""
import argparse
import http.server
import json
import os
from pathlib import Path
import secrets
import select
import subprocess
import sys
import threading

from capture_probe_validation import classify_capture_evidence


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--device', required=True)
    p.add_argument('--flutter', required=True)
    p.add_argument('--adb', default='adb')
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    if a.device.startswith('emulator-'):
        p.error('A physical Android device is required')
    out = a.output.resolve(); out.mkdir(parents=True, exist_ok=False)
    app = Path(__file__).resolve().parents[1] / 'test_apps/native_validation'
    token = secrets.token_hex(24)
    confirmation = []

    def adb(*args):
        return subprocess.run([a.adb, '-s', a.device, *args], check=True, capture_output=True, timeout=30).stdout

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def do_POST(self):
            if self.path != '/ready' or self.headers.get('X-Test-Token') != token or confirmation:
                self.send_error(403); return
            print('CAPTURE_READY: hardware screenshot now; enter captured / unable / cancel.', flush=True)
            value = input().strip() if select.select([sys.stdin], [], [], 300)[0] else 'cancel'
            source = {'captured': 'hardwareButtonsConfirmed', 'unable':'unableToCapture'}.get(value, 'notConfirmed')
            confirmation.append(source)
            body = json.dumps({'captureInput':source}).encode()
            self.send_response(200); self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)

    server = http.server.HTTPServer(('127.0.0.1',0), Handler)
    port = server.server_port
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report = dict(schemaVersion=1, status='incomplete', buildValidated=False)
    mapped = False
    try:
        if adb('get-state').strip() != b'device' or adb('shell','getprop','ro.kernel.qemu').strip() == b'1':
            raise ValueError('Physical authorized device required')
        if int(adb('shell','getprop','ro.build.version.sdk')) < 34:
            raise ValueError('API 34 required')
        if b'TYPE_SCREEN_CAPTURE' in adb('shell','dumpsys','media_projection'):
            raise ValueError('Existing recording must not be interrupted')
        adb('reverse',f'tcp:{port}',f'tcp:{port}'); mapped = True
        env = dict(os.environ, DEMO_REPORT=str(out/'observations.json'))
        target = 'integration_test/capture_probe_test.dart'
        print('Building capture comparison...',flush=True)
        with (out/'build.log').open('w') as log:
            subprocess.run([a.flutter,'build','apk','--debug','--target='+target,
                            f'--dart-define=CAPTURE_TEST_PORT={port}',f'--dart-define=CAPTURE_TEST_TOKEN={token}'],
                           cwd=app,env=env,stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,check=True,timeout=1200)
        report['buildValidated'] = True
        adb('shell','cmd','statusbar','collapse')
        print('Installing comparison fixture...',flush=True)
        with (out/'drive.log').open('w') as log:
            subprocess.run([a.flutter,'drive','--driver='+str(app.parents[1]/'example/test_driver/device_driver.dart'),
                            '--target='+target,'-d',a.device,'--no-pub','--no-start-paused',
                            '--use-application-binary='+str(app/'build/app/outputs/flutter-apk/app-debug.apk')],
                           cwd=app,env=env,stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,check=True,timeout=600)
        evidence = json.loads((out/'observations.json').read_text())
        if confirmation != [evidence.get('captureInput')]:
            raise ValueError('Input confirmation mismatch')
        report['classification'] = classify_capture_evidence(evidence)
        report['observationContinuous'] = report['classification'] == 'passed'
        report['status'] = 'passed' if report['classification'] in {'passed', 'passedWithInterruption'} else 'notAccepted'
    except Exception:
        report['reason'] = 'executionOrEvidenceFailed'
    finally:
        server.shutdown(); server.server_close()
        if mapped:
            try: adb('reverse','--remove',f'tcp:{port}')
            except Exception: report.update(status='incomplete',cleanupFailed=True)
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)
    if report['status'] != 'passed': raise SystemExit(1)


if __name__ == '__main__': main()
