import copy
import unittest
from demo_validation import DETECTORS, validate_evidence


class DemoEvidenceTests(unittest.TestCase):
    def fixture(self, platform='android'):
        kind = 'systemMediaProjection' if platform == 'android' else 'externalExport'
        actions = [dict(phase='screenshot', status='passed', kind='externalExport', artifact=True),
                   dict(phase='record_start', status='passed', kind=kind, started=True),
                   dict(phase='record_stop', status='passed', kind=kind, stopped=True),
                   dict(phase='background', status='passed', kind='realAppSwitch', returned=True),
                   dict(phase='final_view', status='passed', artifact=True)]
        def f(id, status='notDetected', reason='noKnownSignal'):
            return dict(id=id, status=status, reason=reason)
        evidence = dict(completed=True, disposed=True,
            allDetectors=[f(id) for id in DETECTORS],
            local=[f('emulator', 'detected', 'emulatorBuild'), f('hook'), f('root', 'unsupported', 'simulatorEnvironment')],
            missingInputs=[f(id, 'error', reason) for id, reason in [('appIntegrity', 'integrityBaselineRequired'), ('timeAnomaly', 'timeReferenceRequired'), ('mockLocation', 'locationSampleRequired')]],
            captureInitial=[f('screenshot'), f('screenRecording')],
            duringRecording=[f('screenRecording', 'detected', 'screenCaptured') if platform == 'android' else f('screenRecording')],
            afterRecording=[f('screenRecording')], lifecycle=['inactive', 'paused', 'resumed'],
            afterBackground=[f('screenshot', 'error', 'observationInterrupted')],
            explicitStartAfterInterruption=[f('screenshot')],
            restarted=[f('screenshot')], stopped=[f('screenshot', 'error', 'observationRequired')])
        for sample in evidence['allDetectors']:
            if sample['id'] in ('developerMode', 'usbDebugging'):
                sample.update(status='unsupported', reason='unsupportedPlatform' if platform == 'ios' else 'settingReadRestricted')
        for a in actions:
            evidence['host_' + a['phase']] = {k:v for k,v in a.items() if k not in ('phase', 'status')}
        return evidence, actions

    def test_complete_profiles_pass(self):
        for platform in ('android', 'ios'):
            validate_evidence(platform, *self.fixture(platform))

    def test_missing_host_actions_cannot_pass(self):
        e, _ = self.fixture()
        with self.assertRaises(ValueError): validate_evidence('android', e, [])

    def test_absent_failed_duplicate_or_reordered_phase_is_rejected(self):
        e, a = self.fixture()
        for bad in [a[:-1], a + [a[0]], list(reversed(a)), [dict(a[0], status='failed')] + a[1:]]:
            with self.assertRaises(ValueError): validate_evidence('android', e, bad)

    def test_external_export_is_not_android_recording_acceptance(self):
        with self.assertRaises(ValueError): validate_evidence('android', *self.fixture('ios'))

    def test_unknown_capture_or_false_clean_background_cannot_pass(self):
        e, a = self.fixture()
        for stage in ('duringRecording', 'afterBackground', 'explicitStartAfterInterruption', 'restarted', 'stopped'):
            bad = copy.deepcopy(e)
            bad[stage][0]['status'] = 'unsupported'
            with self.assertRaises(ValueError): validate_evidence('android', bad, a)

    def test_completion_flag_alone_is_not_pass(self):
        _, a = self.fixture()
        with self.assertRaises(ValueError): validate_evidence('android', dict(completed=True, disposed=True), a)

    def test_missing_resume_or_disposal_is_rejected(self):
        e, a = self.fixture()
        for change in [dict(lifecycle=['paused']), dict(disposed=False), dict(completed=1)]:
            with self.assertRaises(ValueError): validate_evidence('android', dict(e, **change), a)

    def test_duplicate_detector_cannot_hide_missing_coverage(self):
        e, a = self.fixture()
        e['allDetectors'][-1] = e['allDetectors'][0]
        with self.assertRaises(ValueError): validate_evidence('android', e, a)

    def test_host_action_and_app_acknowledgement_must_match(self):
        e, a = self.fixture()
        e['host_background']['returned'] = False
        with self.assertRaises(ValueError): validate_evidence('android', e, a)

    def test_developer_settings_cannot_claim_clean_or_mix_positive_reasons(self):
        for platform in ('android', 'ios'):
            for status, reason in [('notDetected', 'noKnownSignal'), ('detected', 'debuggerAttached')]:
                e, a = self.fixture(platform)
                next(f for f in e['allDetectors'] if f['id'] == 'developerMode').update(status=status, reason=reason)
                with self.assertRaises(ValueError): validate_evidence(platform, e, a)

    def test_explicit_android_enabled_settings_are_accepted(self):
        e, a = self.fixture()
        for sample in e['allDetectors']:
            if sample['id'] in ('developerMode', 'usbDebugging'):
                sample.update(status='detected', reason=sample['id'] + 'Enabled')
        validate_evidence('android', e, a)
