#!/usr/bin/env python3
"""Kill only the background test process, verify exit, relaunch twice. Not an LMK test."""
import argparse
import http.server
import json
import os
from pathlib import Path
import queue
import secrets
import subprocess
import threading
import time
from process_restart_validation import validate_probe, validate_run

PACKAGE='dev.securitysdk.security_flutter_example'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--device',required=True);p.add_argument('--adb',default='adb');p.add_argument('--flutter',required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.device.startswith('emulator-'):p.error('This runner requires an explicitly selected physical device')
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    app=Path(__file__).resolve().parents[1]/'test_apps/native_validation'
    token=secrets.token_hex(24);received=queue.Queue()
    def adb(*args,check=True):return subprocess.run([a.adb,'-s',a.device,*args],check=check,capture_output=True,timeout=25).stdout
    def pid():
        values=adb('shell','pidof',PACKAGE,check=False).split()
        if len(values)>1:raise ValueError('Unexpected multiple test processes')
        return values[0] if values else None
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self,*_):pass
        def do_POST(self):
            if self.path!='/armed' or self.headers.get('X-Test-Token')!=token:self.send_error(403);return
            try:
                size=int(self.headers.get('Content-Length','0'))
                if not 0<size<=65536:raise ValueError()
                value=json.loads(self.rfile.read(size));validate_probe(value)
                received.put(value);self.send_response(200);self.end_headers()
            except (ValueError,TypeError,KeyError):
                received.put(None);self.send_error(400)
    server=http.server.HTTPServer(('127.0.0.1',0),Handler);port=server.server_port
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report=dict(schemaVersion=1,status='incomplete',terminationMethod='adbAmKillBackground',actualLowMemoryKillVerified=False,buildValidated=False,cleanupCompleted=False,launches=[])
    mapped=False;installed=False;existed=False
    try:
        if adb('get-state').strip()!=b'device' or adb('shell','getprop','ro.kernel.qemu').strip()==b'1':raise ValueError('Physical device unavailable')
        if int(adb('shell','getprop','ro.build.version.sdk'))<35:raise ValueError('API 35 required')
        if b'TYPE_SCREEN_CAPTURE' in adb('shell','dumpsys','media_projection'):raise ValueError('Existing projection must not be interrupted')
        existed=bool(adb('shell','pm','list','packages',PACKAGE).strip())
        adb('reverse',f'tcp:{port}',f'tcp:{port}');mapped=True
        with (out/'build.log').open('w') as log:
            print('Building fresh restart probe...',flush=True)
            subprocess.run([a.flutter,'build','apk','--debug','--target=integration_test/process_restart_probe.dart',f'--dart-define=PROCESS_TEST_PORT={port}',f'--dart-define=PROCESS_TEST_TOKEN={token}'],cwd=app,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1200)
        report['buildValidated']=True
        adb('install','-r',str(app/'build/app/outputs/flutter-apk/app-debug.apk'));installed=True
        adb('shell','am','force-stop',PACKAGE) # Initial setup only; never counted as the tested kill.
        adb('shell','input','keyevent','KEYCODE_WAKEUP');adb('shell','wm','dismiss-keyguard');adb('shell','cmd','statusbar','collapse')
        previous=None
        for index in range(3):
            adb('shell','am','start','-n',PACKAGE+'/.MainActivity')
            value=received.get(timeout=100)
            if value is None:raise ValueError('Startup probe rejected')
            current=pid()
            if current is None or (previous is not None and current==previous):raise ValueError('Fresh process not established')
            launch=dict(round=index+1,probe=value)
            if previous is not None:launch.update(previousProcessExited=True,differentProcess=True)
            report['launches'].append(launch)
            (out/'observations.json').write_text(json.dumps(report,indent=2)+'\n')
            print(f'Round {index+1}: new observation required, empty startup cache, then cached engine seeded.',flush=True)
            if index<2:
                adb('shell','input','keyevent','KEYCODE_HOME');time.sleep(1)
                adb('shell','am','kill',PACKAGE)
                for _ in range(50):
                    if pid() is None:break
                    time.sleep(.2)
                else:raise ValueError('Background process did not exit; no force-stop fallback accepted')
                previous=current
                print('Test process exit confirmed. Relaunching without clearing app data.',flush=True)
    except Exception:
        report['reason']='executionOrEvidenceFailed'
    finally:
        cleanup=True
        if installed:
            try:
                adb('shell','am','force-stop',PACKAGE)
                if not existed:adb('uninstall',PACKAGE)
            except Exception:cleanup=False
        if mapped:
            try:adb('reverse','--remove',f'tcp:{port}')
            except Exception:cleanup=False
        server.shutdown();server.server_close();report['cleanupCompleted']=cleanup
        if 'reason' not in report:
            try:report['status']=validate_run(report)
            except ValueError:report['reason']='finalEvidenceFailed'
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='launches'},indent=2),flush=True)
    return 0 if report['status']=='passedControlledRestart' else 1

if __name__=='__main__':raise SystemExit(main())
