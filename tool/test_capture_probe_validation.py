import copy
import unittest
from capture_probe_validation import classify_capture_evidence


class CaptureProbeValidationTests(unittest.TestCase):
    def fixture(self):
        start = dict(kind='start', value=True, sequence=0, elapsedMs=0)
        before = dict(callbacks=0, registered=True, cleanupPending=True, focused=True,
                      resumed=True, attached=True, sameWindow=True, inPictureInPicture=False,
                      secureWindow=False, permissionGranted=True, eventsTruncated=False, events=[start])
        after = copy.deepcopy(before)
        after['callbacks'] = 1
        after['events'].append(dict(kind='screenshot', value=True, sequence=1, elapsedMs=1000))
        return dict(schemaVersion=3, completed=True, cleanupCompleted=True,
                    captureInput='hardwareButtonsConfirmed', nativeBefore=before, nativeAfter=after,
                    sdkBefore=dict(status='notDetected', reason='noKnownSignal', values={'signalDetected':False}),
                    sdk=dict(status='detected', reason='screenshotObserved', values={'signalDetected':True}),
                    afterStop=dict(status='error', reason='observationRequired', values={}),
                    afterRestart=dict(status='notDetected', reason='noKnownSignal', values=dict(signalDetected=False, screenshotObserved=False, observationActive=True)))

    def test_paired_positive_requires_hardware_confirmation(self):
        e = self.fixture()
        self.assertEqual('passed', classify_capture_evidence(e))
        for stimulus in ['unableToCapture', 'notConfirmed', 'adbExport']:
            self.assertEqual('inconclusiveInput', classify_capture_evidence(dict(e, captureInput=stimulus)))

    def test_missing_native_callback_is_not_a_clean_or_sdk_failure_verdict(self):
        e = self.fixture()
        e['nativeAfter'] = copy.deepcopy(e['nativeBefore'])
        e['sdk'] = copy.deepcopy(e['sdkBefore'])
        self.assertEqual('noSystemCallbackObserved', classify_capture_evidence(e))

    def test_stable_window_native_positive_sdk_negative_identifies_mismatch(self):
        e = self.fixture(); e['sdk'] = copy.deepcopy(e['sdkBefore'])
        self.assertEqual('sdkMissedCallback', classify_capture_evidence(e))

    def test_focus_gap_is_not_ignored_after_focus_returns(self):
        e = self.fixture()
        e['nativeAfter']['events'] += [dict(kind='focus', value=False, sequence=2, elapsedMs=1001),
                                       dict(kind='focus', value=True, sequence=3, elapsedMs=2000)]
        e['sdk'] = dict(status='error', reason='observationInterrupted', values={})
        self.assertEqual('scopeInterrupted', classify_capture_evidence(e))
        e['sdk'] = copy.deepcopy(e['sdkBefore'])
        self.assertEqual('unexpectedResultAcrossInterruption', classify_capture_evidence(e))

    def test_pause_and_replaced_window_are_not_passed_as_positive(self):
        for field in ['resumed', 'attached', 'sameWindow']:
            e = self.fixture(); e['nativeAfter'][field] = False
            self.assertEqual('unexpectedResultAcrossInterruption', classify_capture_evidence(e))

    def test_missing_permission_secure_window_and_failed_cleanup_cannot_pass(self):
        for key,value in [('permissionGranted', False), ('secureWindow', True)]:
            e = self.fixture(); e['nativeBefore'][key] = value
            self.assertEqual('preconditionUnavailable', classify_capture_evidence(e))
        e = self.fixture(); e['cleanupCompleted'] = False
        with self.assertRaises(ValueError): classify_capture_evidence(e)

    def test_truncated_events_are_inconclusive(self):
        e = self.fixture(); e['nativeAfter']['eventsTruncated'] = True
        self.assertEqual('incompleteEventHistory', classify_capture_evidence(e))

    def test_bad_types_counters_event_order_or_inconsistent_values_are_rejected(self):
        mutations = [lambda e:e['nativeAfter'].update(callbacks=True),
                     lambda e:e['nativeAfter'].update(callbacks=2),
                     lambda e:e['nativeAfter']['events'][1].update(sequence=0),
                     lambda e:e['nativeAfter']['events'][1].update(elapsedMs=-1),
                     lambda e:e['nativeBefore'].update(focused=1),
                     lambda e:e['sdk']['values'].update(signalDetected=False),
                     lambda e:e['nativeAfter'].update(unexpected='text'),
                     lambda e:e['nativeBefore']['events'][0].update(elapsedMs=-1),
                     lambda e:e['sdk']['values'].update(unexpected=1)]
        for mutate in mutations:
            e = self.fixture(); mutate(e)
            with self.assertRaises(ValueError): classify_capture_evidence(e)

    def test_verified_history_survives_gap_but_does_not_mark_window_active(self):
        e = self.fixture()
        e['nativeAfter']['events'].append(dict(kind='focus', value=False, sequence=2, elapsedMs=1100))
        e['sdk'] = dict(status='error', reason='observationInterrupted',
                        values=dict(screenshotObserved=True, observationActive=False))
        self.assertEqual('passedWithInterruption', classify_capture_evidence(e))
        e['sdk']['values']['screenshotObserved'] = False
        self.assertEqual('scopeInterrupted', classify_capture_evidence(e))

    def test_callback_only_after_gap_does_not_prove_active_observation(self):
        e = self.fixture()
        e['nativeAfter']['events'][1] = dict(kind='focus', value=False, sequence=1, elapsedMs=500)
        e['nativeAfter']['events'].append(dict(kind='screenshot', value=False, sequence=2, elapsedMs=1000))
        e['sdk'] = dict(status='error', reason='observationInterrupted',
                        values=dict(screenshotObserved=True, observationActive=False))
        self.assertEqual('scopeInterrupted', classify_capture_evidence(e))

    def test_restart_cannot_retain_historical_positive(self):
        e = self.fixture(); e['afterRestart']['values']['screenshotObserved'] = True
        with self.assertRaises(ValueError): classify_capture_evidence(e)
