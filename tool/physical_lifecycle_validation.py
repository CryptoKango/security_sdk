"""Accept physical lifecycle evidence only with OS transitions and fresh SDK values."""

from capture_probe_validation import validate_capture_snapshots


def validate(e, stages):
    def need(value):
        if not value: raise ValueError('Missing or contradictory lifecycle evidence')
    need(type(e) is dict and e.get('schemaVersion') == 1 and e.get('completed') is True and e.get('cleanupCompleted') is True)
    c = e.get('checks', {})
    need(type(c) is dict)
    need([s.get('stage') for s in stages] == ['screenshot','record_start','fold','record_stop'])
    for s in stages:
        need(s.get('confirmed') is True and c.get(s['stage']) == s)
        need(type(s.get('projectionActive')) is bool)
    need(stages[0]['projectionActive'] is False and stages[1]['projectionActive'] is True and stages[3]['projectionActive'] is False)
    states = stages[2].get('deviceStates')
    need(type(states) is list and len(states) >= 1 and all(type(x) is int and x >= 0 for x in states))
    need(stages[2].get('statesTruncated') is False)
    fold_verified=len(states)>=3 and len(set(states))>=2 and states[0]==states[-1]
    fold_recording = stages[2]['projectionActive']
    def finding(name, history, recording, focused=True, fresh=False):
        v=c.get(name, {}); shot=v.get('screenshot', {}); rec=v.get('screenRecording', {})
        values=shot.get('values', {})
        need(values.get('screenshotObserved') is history)
        if shot.get('status') == 'error':
            need(not fresh and shot.get('reason') == 'observationInterrupted' and values == {'screenshotObserved':history,'observationActive':False})
        else:
            need(focused and shot.get('status') == ('detected' if history else 'notDetected'))
            need(shot.get('reason') == ('screenshotObserved' if history else 'noKnownSignal'))
            need(values == {'signalDetected':history,'screenshotObserved':history,'observationActive':True})
        if focused:
            need(rec == {'status':'detected' if recording else 'notDetected','reason':'screenCaptured' if recording else 'noKnownSignal','values':{'signalDetected':recording}})
        else:
            need(rec == {'status':'error','reason':'noActivity','values':{}})
    for name, recording in [('baseline',False),('beforeScreenshot',False),('historyCleared',False),('recording',True),('beforeFold',True),('foldRestarted',fold_recording),('recordingStopped',False)]:
        finding(name,False,recording,fresh=True)
    finding('afterScreenshot',True,False)
    finding('afterFold',False,fold_recording)
    for prefix, history, recording in [('negative',False,False),('history',True,False),('recording',False,True),('stopped',False,False)]:
        for cycle in (1,2):
            key=f'{prefix}-rotation-{cycle}'
            finding(key,history,recording)
            ui=c.get(key+'-ui',{}); before=ui.get('before',{}); after=ui.get('after',{})
            need(before.get('orientation') in (1,2) and after.get('orientation') in (1,2) and before['orientation'] != after['orientation'])
            need(type(after.get('configurationChanges')) is int and type(before.get('configurationChanges')) is int and after['configurationChanges'] > before['configurationChanges'])
            need(after.get('focus') is True and after.get('resumed') is True)
    split_verified=True
    for prefix, recording in [('negative',False),('recording',True)]:
        finding(prefix+'-beforeSplit',False,recording,fresh=True)
        finding(prefix+'-unfocused',False,recording,focused=False)
        finding(prefix+'-returned',False,recording)
        finding(prefix+'-restarted',False,recording,fresh=True)
        s=c.get(prefix+'-split-ui',{}); r=c.get(prefix+'-restored-ui',{})
        need(s.get('peerReceived') is True and s.get('peerFocus') is True and s.get('mainFocus') is False)
        need(r.get('peerClosed') is True and r.get('mainMultiWindow') is False and r.get('mainFocus') is True and r.get('mainResumed') is True)
        split_verified &= s.get('mainMultiWindow') is True and s.get('peerMultiWindow') is True
    before=c.get('probeBefore',{}); after=c.get('probeAfter',{})
    need(before.get('callbacks') == 0 and type(after.get('callbacks')) is int and after['callbacks'] > 0)
    for probe in (before,after,c.get('foldProbeBefore',{}),c.get('foldProbeAfter',{})):
        need(probe.get('registered') is True and probe.get('eventsTruncated') is False and probe.get('permissionGranted') is True)
    need(c['foldProbeBefore']['callbacks'] == 0 and c['foldProbeAfter']['callbacks'] == 0)
    for before_key, after_key, sdk_key in [('probeBefore','probeAfter','afterScreenshot'),('foldProbeBefore','foldProbeAfter','afterFold')]:
        before, after = validate_capture_snapshots(c[before_key],c[after_key])
        need(all(before[k] for k in ('registered','focused','resumed','attached','sameWindow','permissionGranted')))
        need(not before['secureWindow'] and not before['inPictureInPicture'])
        gaps=[x for x in after['events'] if x['kind'] in ('focus','resumed') and not x['value']]
        gap=bool(gaps) or any(not after[k] for k in ('focused','resumed','attached','sameWindow')) or after['inPictureInPicture']
        if gap: need(c[sdk_key]['screenshot']['status']=='error')
        if sdk_key=='afterScreenshot':
            prefix=after['events'][:gaps[0]['sequence']] if gaps else after['events']
            need(any(x['kind']=='screenshot' and x['value'] for x in prefix))
    if not fold_verified: return 'partialFoldUnverified' if split_verified else 'partialFoldAndSplitUnverified'
    return 'passed' if split_verified else 'partialSplitUnavailable'


def validate_fold(e, stages, closed_state):
    def need(ok):
        if not ok: raise ValueError('Incomplete or inconsistent held-fold evidence')
    need(type(e) is dict and e.get('completed') is True and e.get('cleanupCompleted') is True)
    expected=['record_start','fold_closed_1','fold_opened_1','fold_closed_2','fold_opened_2','record_stop']
    need([s.get('stage') for s in stages] == expected)
    need(all(s.get('confirmed') is True and type(s.get('deviceState')) is int and type(s.get('projectionActive')) is bool for s in stages))
    need(stages[0]['projectionActive'] is True and stages[-1]['projectionActive'] is False)
    need(e.get('record_start') == stages[0] and e.get('record_stop') == stages[-1])
    cycles=e.get('cycles');need(type(cycles) is list and len(cycles)==2)
    opened_state=stages[0]['deviceState']; need(opened_state!=closed_state)
    def shot(value, interrupted):
        need(value == (dict(status='error',reason='observationInterrupted',values=dict(screenshotObserved=False,observationActive=False)) if interrupted else dict(status='notDetected',reason='noKnownSignal',values=dict(signalDetected=False,screenshotObserved=False,observationActive=True))))
    def recording(value, visible):
        need(value == dict(status='detected' if visible else 'notDetected',reason='screenCaptured' if visible else 'noKnownSignal',values=dict(signalDetected=visible)))
    for n,c in enumerate(cycles,1):
        need(c.get('cycle') == n)
        closed,opened=stages[n*2-1:n*2+1]
        need(c.get('closed')==closed and c.get('opened')==opened)
        need(closed['deviceState']==closed_state and opened['deviceState']==opened_state)
        before,after=validate_capture_snapshots(c.get('nativeBefore'),c.get('nativeAfter'))
        need(after['callbacks']==0 and after['eventsTruncated'] is False and before['focused'] is True and before['resumed'] is True)
        need(any(x['kind'] in ('focus','resumed') and not x['value'] for x in after['events']))
        shot(c['before']['screenshot'],False)
        recording(c['before']['screenRecording'],stages[0 if n==1 else 2]['projectionActive'])
        shot(c['whileClosed']['screenshot'],True)
        need(c['whileClosed']['screenRecording']==dict(status='error',reason='noActivity',values={}))
        shot(c['after']['screenshot'],True)
        recording(c['after']['screenRecording'],opened['projectionActive'])
        shot(c['restarted']['screenshot'],False)
        recording(c['restarted']['screenRecording'],opened['projectionActive'])
    recording(e['stopped']['screenRecording'],False)
    # Some OEMs stop recording on fold: no recorder overlay is then needed.
    final_shot=e['stopped']['screenshot']
    shot(final_shot,final_shot.get('status')=='error')
    return 'passed'
