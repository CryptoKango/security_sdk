import copy
import unittest
from projection_validation import validate_projection


def evidence():
    stages=[dict(stage=n,confirmed=True,projectionActive=n!='stopped',scopeConfirmation='systemPickerOperatorConfirmed') for n in ('other_app','own_app','full_display','stopped')]
    def recording(positive): return dict(status='detected' if positive else 'notDetected',reason='screenCaptured' if positive else 'noKnownSignal',values=dict(signalDetected=positive))
    active=dict(status='notDetected',reason='noKnownSignal',values=dict(signalDetected=False,screenshotObserved=False,observationActive=True))
    interrupted=dict(status='error',reason='observationInterrupted',values=dict(screenshotObserved=False,observationActive=False))
    phases=[dict(name=s['stage'],host=copy.deepcopy(s),beforeRestart=dict(screenRecording=recording(s['stage'] in ('own_app','full_display')),screenshot=copy.deepcopy(interrupted)),afterRestart=dict(screenRecording=recording(s['stage'] in ('own_app','full_display')),screenshot=copy.deepcopy(active))) for s in stages]
    return dict(schemaVersion=1,completed=True,cleanupCompleted=True,baseline=dict(screenRecording=recording(False)),phases=phases),stages


class ProjectionValidationTest(unittest.TestCase):
    def test_all_scopes(self):self.assertEqual('passed',validate_projection(*evidence()))
    def test_global_projection_cannot_count_as_current_uid_positive(self):
        e,s=evidence();e['phases'][0]['afterRestart']=e['phases'][1]['afterRestart']
        with self.assertRaises(ValueError):validate_projection(e,s)
    def test_stopped_projection_cannot_keep_positive(self):
        e,s=evidence();e['phases'][3]['afterRestart']=e['phases'][1]['afterRestart']
        with self.assertRaises(ValueError):validate_projection(e,s)
    def test_missing_system_selection_confirmation_rejected(self):
        e,s=evidence();s[1]['scopeConfirmation']='inferred';e['phases'][1]['host']=copy.deepcopy(s[1])
        with self.assertRaises(ValueError):validate_projection(e,s)
    def test_no_actual_projection_rejected(self):
        e,s=evidence();s[1]['projectionActive']=False;e['phases'][1]['host']=copy.deepcopy(s[1])
        with self.assertRaises(ValueError):validate_projection(e,s)
    def test_wrong_order_or_incomplete_sequence_rejected(self):
        e,s=evidence();s.reverse()
        with self.assertRaises(ValueError):validate_projection(e,s)
        e,s=evidence();e['phases'].pop()
        with self.assertRaises(ValueError):validate_projection(e,s)
    def test_projection_cannot_invent_screenshot(self):
        e,s=evidence();e['phases'][1]['afterRestart']['screenshot']['values']['screenshotObserved']=True
        with self.assertRaises(ValueError):validate_projection(e,s)
    def test_failed_cleanup_rejected(self):
        e,s=evidence();e['cleanupCompleted']=False
        with self.assertRaises(ValueError):validate_projection(e,s)
    def test_focus_gap_cannot_be_implicitly_reopened(self):
        e,s=evidence();e['phases'][0]['beforeRestart']['screenshot']=e['phases'][0]['afterRestart']['screenshot']
        with self.assertRaises(ValueError):validate_projection(e,s)

if __name__=='__main__':unittest.main()
