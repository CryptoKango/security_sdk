import copy
import unittest
from physical_lifecycle_validation import validate
import test_capture_probe_validation as capture_fixtures


def evidence():
    stages=[dict(stage=s, confirmed=True, projectionActive=s in ('record_start','fold')) for s in ('screenshot','record_start','fold','record_stop')]
    stages[2].update(deviceStates=[3,0,3],statesTruncated=False)
    c={s['stage']:copy.deepcopy(s) for s in stages}
    def scan(name,history=False,recording=False,focused=True):
        c[name]=dict(screenshot=dict(status='detected' if history else 'notDetected',reason='screenshotObserved' if history else 'noKnownSignal',values=dict(signalDetected=history,screenshotObserved=history,observationActive=True)),screenRecording=dict(status='detected' if recording else 'notDetected',reason='screenCaptured' if recording else 'noKnownSignal',values=dict(signalDetected=recording)))
        if not focused:
            c[name]['screenshot']=dict(status='error',reason='observationInterrupted',values=dict(screenshotObserved=history,observationActive=False))
            c[name]['screenRecording']=dict(status='error',reason='noActivity',values={})
    for name,recording in [('baseline',False),('beforeScreenshot',False),('historyCleared',False),('recording',True),('beforeFold',True),('foldRestarted',True),('recordingStopped',False),('afterFold',True)]: scan(name,recording=recording)
    scan('afterScreenshot',history=True)
    for prefix,history,recording in [('negative',False,False),('history',True,False),('recording',False,True),('stopped',False,False)]:
        for n in (1,2):
            key=f'{prefix}-rotation-{n}';scan(key,history,recording)
            c[key+'-ui']=dict(before=dict(orientation=n,configurationChanges=n),after=dict(orientation=3-n,configurationChanges=n+1,focus=True,resumed=True))
    for prefix,recording in [('negative',False),('recording',True)]:
        for name in ('beforeSplit','unfocused','returned','restarted'): scan(prefix+'-'+name,recording=recording,focused=name!='unfocused')
        c[prefix+'-split-ui']=dict(peerReceived=True,peerFocus=True,mainFocus=False,mainMultiWindow=True,peerMultiWindow=True)
        c[prefix+'-restored-ui']=dict(peerClosed=True,mainMultiWindow=False,mainFocus=True,mainResumed=True)
    for name in ('probeBefore','probeAfter','foldProbeBefore','foldProbeAfter'):
        c[name]=copy.deepcopy(capture_fixtures.CaptureProbeValidationTests().fixture()['nativeAfter' if name=='probeAfter' else 'nativeBefore'])
    return dict(schemaVersion=1,completed=True,cleanupCompleted=True,checks=c),stages


class PhysicalLifecycleValidationTest(unittest.TestCase):
    def test_complete_matrix(self):
        self.assertEqual('passed',validate(*evidence()))
    def test_fullscreen_companion_is_partial_not_split_pass(self):
        e,s=evidence();e['checks']['recording-split-ui']['mainMultiWindow']=False
        self.assertEqual('partialSplitUnavailable',validate(e,s))
    def test_unconfirmed_fold_unchanged_state_and_truncation_rejected(self):
        for patch in [dict(confirmed=False),dict(statesTruncated=True),dict(deviceStates=[True,0,True])]:
            e,s=evidence();s[2].update(patch);e['checks']['fold']=copy.deepcopy(s[2])
            with self.assertRaises(ValueError):validate(e,s)
    def test_missing_fold_transition_never_passes(self):
        for states in ([3],[3,0]):
            e,s=evidence();s[2]['deviceStates']=states;e['checks']['fold']=copy.deepcopy(s[2])
            self.assertEqual('partialFoldUnverified',validate(e,s))
    def test_fake_rotation_rejected(self):
        e,s=evidence();e['checks']['negative-rotation-1-ui']['after']['orientation']=1
        with self.assertRaises(ValueError):validate(e,s)
    def test_stale_recording_after_stop_rejected(self):
        e,s=evidence();e['checks']['recordingStopped']['screenRecording']=e['checks']['recording']['screenRecording']
        with self.assertRaises(ValueError):validate(e,s)
    def test_unfocused_clean_is_rejected(self):
        e,s=evidence();e['checks']['recording-unfocused']=e['checks']['recording']
        with self.assertRaises(ValueError):validate(e,s)
    def test_history_cannot_cross_restart(self):
        e,s=evidence();e['checks']['historyCleared']=e['checks']['afterScreenshot']
        with self.assertRaises(ValueError):validate(e,s)
    def test_false_positive_without_capture_rejected(self):
        e,s=evidence();e['checks']['negative-rotation-1']=e['checks']['afterScreenshot']
        with self.assertRaises(ValueError):validate(e,s)
    def test_missing_step_or_failed_cleanup_rejected(self):
        for mutate in [lambda e:e.update(cleanupCompleted=False),lambda e:e['checks'].pop('history-rotation-2')]:
            e,s=evidence();mutate(e)
            with self.assertRaises(ValueError):validate(e,s)
    def test_history_error_does_not_claim_continuous_observation(self):
        e,s=evidence()
        e['checks']['probeAfter']['events'].append(dict(kind='focus',value=False,sequence=2,elapsedMs=1001))
        e['checks']['afterScreenshot']['screenshot']=dict(status='error',reason='observationInterrupted',values=dict(screenshotObserved=True,observationActive=False))
        self.assertEqual('passed',validate(e,s))
        e['checks']['afterScreenshot']['screenshot']['values']['observationActive']=True
        with self.assertRaises(ValueError):validate(e,s)
    def test_actual_os_recording_stop_during_fold_is_accepted(self):
        e,s=evidence();s[2]['projectionActive']=False;e['checks']['fold']=copy.deepcopy(s[2])
        for name in ('afterFold','foldRestarted'): e['checks'][name]['screenRecording']=copy.deepcopy(e['checks']['baseline']['screenRecording'])
        self.assertEqual('passed',validate(e,s))
    def test_fold_pause_cannot_silently_resume_clean(self):
        e,s=evidence()
        e['checks']['foldProbeAfter']['events'].append(dict(kind='resumed',value=False,sequence=1,elapsedMs=1000))
        with self.assertRaises(ValueError):validate(e,s)
        e['checks']['afterFold']['screenshot']=dict(status='error',reason='observationInterrupted',values=dict(screenshotObserved=False,observationActive=False))
        self.assertEqual('passed',validate(e,s))
    def test_host_and_device_confirmations_must_agree(self):
        e,s=evidence();e['checks']['record_start']['confirmed']=False
        with self.assertRaises(ValueError):validate(e,s)



def held_fold_evidence():
    from physical_lifecycle_validation import validate_fold
    stages=[dict(stage=s,confirmed=True,projectionActive=s!='record_stop',deviceState=0 if 'closed' in s else 3) for s in ('record_start','fold_closed_1','fold_opened_1','fold_closed_2','fold_opened_2','record_stop')]
    matrix,_=evidence();c=matrix['checks'];cycles=[]
    for n in (1,2):
        native=copy.deepcopy(c['foldProbeAfter']);native['events'].append(dict(kind='resumed',value=False,sequence=1,elapsedMs=1000))
        after=copy.deepcopy(c['recording']);after['screenshot']=copy.deepcopy(c['recording-unfocused']['screenshot'])
        cycles.append(dict(cycle=n,before=copy.deepcopy(c['recording']),closed=copy.deepcopy(stages[n*2-1]),opened=copy.deepcopy(stages[n*2]),whileClosed=copy.deepcopy(c['recording-unfocused']),after=after,restarted=copy.deepcopy(c['recording']),nativeBefore=copy.deepcopy(c['foldProbeBefore']),nativeAfter=native))
    stopped=copy.deepcopy(c['recording-unfocused']);stopped['screenRecording']=copy.deepcopy(c['baseline']['screenRecording'])
    return dict(schemaVersion=1,completed=True,cleanupCompleted=True,record_start=copy.deepcopy(stages[0]),record_stop=copy.deepcopy(stages[-1]),cycles=cycles,stopped=stopped),stages,validate_fold


class HeldFoldValidationTest(unittest.TestCase):
    def test_two_real_cycles(self):
        e,s,validate_fold=held_fold_evidence();self.assertEqual('passed',validate_fold(e,s,0))
    def test_wrong_closed_state_is_not_a_fold(self):
        e,s,validate_fold=held_fold_evidence();s[1]['deviceState']=3;e['cycles'][0]['closed']=copy.deepcopy(s[1])
        with self.assertRaises(ValueError):validate_fold(e,s,0)
    def test_clean_after_pause_is_rejected(self):
        e,s,validate_fold=held_fold_evidence();e['cycles'][1]['after']['screenshot']=e['cycles'][1]['restarted']['screenshot']
        with self.assertRaises(ValueError):validate_fold(e,s,0)
    def test_no_native_interruption_is_not_held_fold_evidence(self):
        e,s,validate_fold=held_fold_evidence();e['cycles'][0]['nativeAfter']=e['cycles'][0]['nativeBefore']
        with self.assertRaises(ValueError):validate_fold(e,s,0)
    def test_old_screenshot_cannot_reappear_on_unfold(self):
        e,s,validate_fold=held_fold_evidence();e['cycles'][0]['after']['screenshot']['values']['screenshotObserved']=True
        with self.assertRaises(ValueError):validate_fold(e,s,0)
    def test_already_stopped_recorder_does_not_require_an_extra_focus_gap(self):
        e,s,validate_fold=held_fold_evidence()
        e['stopped']['screenshot']=copy.deepcopy(e['cycles'][-1]['restarted']['screenshot'])
        self.assertEqual('passed',validate_fold(e,s,0))
    def test_incomplete_second_cycle_rejected(self):
        e,s,validate_fold=held_fold_evidence();e['cycles'].pop()
        with self.assertRaises(ValueError):validate_fold(e,s,0)

if __name__=='__main__': unittest.main()
