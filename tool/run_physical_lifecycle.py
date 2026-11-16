#!/usr/bin/env python3
"""Real Android rotation/split/fold capture matrix; explicit physical confirmations."""
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
from physical_lifecycle_validation import validate, validate_fold
from projection_validation import validate_projection


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--device',required=True); p.add_argument('--flutter',required=True)
    p.add_argument('--adb',default='adb'); p.add_argument('--output',type=Path,required=True)
    p.add_argument('--held-fold',action='store_true',help='Two rounds: hold closed until acknowledged, then reopen')
    p.add_argument('--closed-state',type=int,help='OEM CLOSED state identifier from cmd device_state print-states')
    p.add_argument('--projection-scope',action='store_true',help='System-picker-confirmed other app / this app / full display projection')
    a=p.parse_args()
    if a.projection_scope and a.held_fold: p.error('Choose only one profile')
    if a.held_fold and a.closed_state is None: p.error('--held-fold requires verified --closed-state')
    if a.device.startswith('emulator-'): p.error('Physical device required')
    out=a.output.resolve(); out.mkdir(parents=True,exist_ok=False)
    root=Path(__file__).resolve().parents[1]; app=root/'test_apps/native_validation'
    token=secrets.token_hex(24); stages=[]
    expected=['record_start','fold_closed_1','fold_opened_1','fold_closed_2','fold_opened_2','record_stop'] if a.held_fold else ['screenshot','record_start','fold','record_stop']
    if a.projection_scope: expected=['other_app','own_app','full_display','stopped']
    def adb(*args):
        return subprocess.run([a.adb,'-s',a.device,*args],check=True,capture_output=True,timeout=15).stdout
    def projection(): return b'TYPE_SCREEN_CAPTURE' in adb('shell','dumpsys','media_projection')
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self,*_): pass
        def do_POST(self):
            stage=self.path[1:]
            if self.headers.get('X-Test-Token') != token or len(stages)>=len(expected) or stage != expected[len(stages)]:
                self.send_error(403); return
            states=[]; stopped=threading.Event(); truncated=[False]; read_failed=[False]
            def sample():
                while not stopped.is_set():
                    try:
                        value=int(adb('shell','cmd','device_state','print-state').strip())
                        if not states or states[-1] != value:
                            if len(states)<64: states.append(value)
                            else: truncated[0]=True
                    except Exception: read_failed[0]=True
                    stopped.wait(.2)
            sampler=None
            if stage=='fold':
                sampler=threading.Thread(target=sample,daemon=True); sampler.start()
            instruction='keep device closed' if stage.startswith('fold_closed_') else 'return to stable fixture foreground'
            print('LIFECYCLE_READY: '+stage+'; '+instruction+'; enter confirmed / cancel.',flush=True)
            value=input().strip() if select.select([sys.stdin],[],[],300)[0] else 'cancel'
            stopped.set()
            if sampler: sampler.join(timeout=20)
            result=dict(stage=stage,confirmed=value=='confirmed',projectionActive=projection())
            if a.projection_scope: result['scopeConfirmation']='systemPickerOperatorConfirmed' if value=='confirmed' else 'notConfirmed'
            if a.held_fold: result['deviceState']=int(adb('shell','cmd','device_state','print-state').strip())
            if stage=='fold':
                result.update(deviceStates=states,statesTruncated=truncated[0] or read_failed[0] or sampler.is_alive())
            stages.append(result)
            (out/'stages.json').write_text(json.dumps(stages,indent=2)+'\n')
            body=json.dumps(result).encode(); self.send_response(200)
            self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)))
            self.end_headers();self.wfile.write(body)
    server=http.server.HTTPServer(('127.0.0.1',0),Handler); port=server.server_port
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report=dict(schemaVersion=1,status='incomplete',buildValidated=False)
    mapped=False
    try:
        if adb('get-state').strip()!=b'device' or adb('shell','getprop','ro.kernel.qemu').strip()==b'1': raise ValueError('Physical device required')
        if int(adb('shell','getprop','ro.build.version.sdk'))<35 or projection(): raise ValueError('API 35+ and no pre-existing recording required')
        if not adb('shell','pm','list','packages','dev.securitysdk.window_companion').strip(): raise ValueError('Build/install companion first')
        adb('reverse',f'tcp:{port}',f'tcp:{port}');mapped=True
        env=dict(os.environ,DEMO_REPORT=str(out/'observations.json'))
        target='integration_test/physical_fold_test.dart' if a.held_fold else 'integration_test/physical_lifecycle_test.dart'
        if a.projection_scope: target='integration_test/projection_scope_test.dart'
        with (out/'build.log').open('w') as log:
            print('Building physical lifecycle fixture...',flush=True)
            subprocess.run([a.flutter,'build','apk','--debug','--target='+target,f'--dart-define=LIFECYCLE_TEST_PORT={port}',f'--dart-define=LIFECYCLE_TEST_TOKEN={token}'],cwd=app,env=env,stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,check=True,timeout=1200)
        report['buildValidated']=True
        adb('shell','cmd','statusbar','collapse')
        with (out/'drive.log').open('w') as log:
            subprocess.run([a.flutter,'drive','--driver='+str(root/'example/test_driver/device_driver.dart'),'--target='+target,'-d',a.device,'--no-pub','--no-start-paused','--use-application-binary='+str(app/'build/app/outputs/flutter-apk/app-debug.apk')],cwd=app,env=env,stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,check=True,timeout=1800)
        evidence=json.loads((out/'observations.json').read_text())
        report['status']=validate_projection(evidence,stages) if a.projection_scope else validate_fold(evidence,stages,a.closed_state) if a.held_fold else validate(evidence,stages)
    except Exception:
        report['reason']='executionOrEvidenceFailed'
        if stages and stages[-1].get('confirmed') is False:
            report.update(status='blocked',reason='physicalStepNotConfirmed')
    finally:
        server.shutdown();server.server_close()
        if mapped:
            try: adb('reverse','--remove',f'tcp:{port}')
            except Exception: report.update(status='incomplete',cleanupFailed=True)
        # Never silently terminate a projection: the host must stop its own recorder.
        try: report['recordingStillActive']=projection()
        except Exception: report['status']='incomplete'
        if report.get('recordingStillActive'): report['status']='incomplete'
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)
    return 0 if report['status']=='passed' else 3 if (report['status'].startswith('partial') or report['status']=='blocked') else 1

if __name__=='__main__': sys.exit(main())
