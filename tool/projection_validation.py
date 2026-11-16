"""UID-scoped projection evidence: global projection alone never proves capture."""

def validate_projection(e, stages):
    def need(ok):
        if not ok: raise ValueError('Missing or contradictory projection evidence')
    need(type(e) is dict and e.get('schemaVersion')==1 and e.get('completed') is True and e.get('cleanupCompleted') is True)
    expected=['other_app','own_app','full_display','stopped']
    need([s.get('stage') for s in stages]==expected)
    phases=e.get('phases');need(type(phases) is list and len(phases)==4)
    def recording(value, positive):
        need(value==dict(status='detected' if positive else 'notDetected',reason='screenCaptured' if positive else 'noKnownSignal',values=dict(signalDetected=positive)))
    recording(e.get('baseline',{}).get('screenRecording'),False)
    for name,phase,host in zip(expected,phases,stages):
        need(phase.get('name')==name and phase.get('host')==host and host.get('confirmed') is True)
        need(host.get('scopeConfirmation')=='systemPickerOperatorConfirmed')
        need(host.get('projectionActive') is (name!='stopped'))
        positive=name in ('own_app','full_display')
        before=phase.get('beforeRestart',{});after=phase.get('afterRestart',{})
        recording(before.get('screenRecording'),positive);recording(after.get('screenRecording'),positive)
        need(before.get('screenshot')==dict(status='error',reason='observationInterrupted',values=dict(screenshotObserved=False,observationActive=False)))
        need(after.get('screenshot')==dict(status='notDetected',reason='noKnownSignal',values=dict(signalDetected=False,screenshotObserved=False,observationActive=True)))
    return 'passed'
