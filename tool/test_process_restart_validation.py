import copy
import unittest
from process_restart_validation import validate_probe,validate_run


def probe():
    def native(seeded):return dict(activityCreates=1,lastExitCause='userRequested',cache=dict(activityCreated=int(seeded),activityDestroyed=int(seeded),engineCreated=int(seeded),engineDestroyed=0,trimCallbacks=0,cachePresent=seeded,cacheMatchesEngine=seeded,enginePresent=seeded,activityPresent=False,ready=seeded,focused=False))
    recording=dict(status='notDetected',reason='noKnownSignal',values=dict(signalDetected=False))
    def result(status,reason,values):return dict(screenshot=dict(status=status,reason=reason,values=values),screenRecording=copy.deepcopy(recording))
    return dict(schemaVersion=1,completed=True,startup=native(False),seeded=native(True),
        beforeStart=result('error','observationRequired',{}),
        active=result('notDetected','noKnownSignal',dict(signalDetected=False,screenshotObserved=False,observationActive=True)),
        interrupted=result('error','observationInterrupted',dict(screenshotObserved=False,observationActive=False)))


def run():
    return dict(buildValidated=True,cleanupCompleted=True,terminationMethod='adbAmKillBackground',actualLowMemoryKillVerified=False,
        launches=[dict(round=i+1,probe=probe(),**(dict(previousProcessExited=True,differentProcess=True) if i else {})) for i in range(3)])


class ProcessRestartValidationTest(unittest.TestCase):
    def test_three_startups_after_two_confirmed_exits(self):self.assertEqual('passedControlledRestart',validate_run(run()))
    def test_activity_only_restart_cannot_pass(self):
        e=run();e['launches'][1]['differentProcess']=False
        with self.assertRaises(ValueError):validate_run(e)
    def test_process_must_have_disappeared_before_relaunch(self):
        e=run();del e['launches'][1]['previousProcessExited']
        with self.assertRaises(ValueError):validate_run(e)
    def test_controlled_kill_cannot_be_labelled_actual_lmk(self):
        e=run();e['actualLowMemoryKillVerified']=True
        with self.assertRaises(ValueError):validate_run(e)
    def test_force_stop_fallback_cannot_be_counted_as_background_kill(self):
        e=run();e['terminationMethod']='forceStop'
        with self.assertRaises(ValueError):validate_run(e)
    def test_restored_cache_is_not_fresh_startup(self):
        p=probe();p['startup']['cache']['cachePresent']=True
        with self.assertRaises(ValueError):validate_probe(p)
    def test_new_process_must_require_explicit_start(self):
        p=probe();p['beforeStart']=p['active']
        with self.assertRaises(ValueError):validate_probe(p)
    def test_interrupted_observation_must_exist_before_kill(self):
        p=probe();p['interrupted']=p['beforeStart']
        with self.assertRaises(ValueError):validate_probe(p)
    def test_cache_removal_without_seeding_cannot_exercise_restart(self):
        p=probe();p['seeded']=p['startup']
        with self.assertRaises(ValueError):validate_probe(p)
    def test_unknown_fields_and_numeric_bools_rejected(self):
        for mutate in [lambda p:p.update(pid=123),lambda p:p['startup'].update(rawError='text'),lambda p:p['active']['screenshot']['values'].update(observationActive=1),lambda p:p['startup']['cache'].update(engineCreated=False)]:
            p=probe();mutate(p)
            with self.assertRaises(ValueError):validate_probe(p)
    def test_failed_cleanup_or_partial_run_rejected(self):
        e=run();e['cleanupCompleted']=False
        with self.assertRaises(ValueError):validate_run(e)
        e=run();e['launches'].pop()
        with self.assertRaises(ValueError):validate_run(e)
    def test_exit_reason_alone_is_not_lmk_verification(self):
        e=run();e['launches'][1]['probe']['startup']['lastExitCause']='lowMemory'
        self.assertEqual('passedControlledRestart',validate_run(e))
        self.assertIs(e['actualLowMemoryKillVerified'],False)

if __name__=='__main__':unittest.main()
