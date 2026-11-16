"""Strict evidence checks for the example's simulator acceptance profile."""
PHASES = ['screenshot', 'record_start', 'record_stop', 'background', 'final_view']
DETECTORS = {'root', 'hook', 'debugger', 'appIntegrity', 'emulator', 'multiInstance',
             'automation', 'developerMode', 'usbDebugging', 'accessibility', 'vpn', 'proxy', 'screenRecording',
             'screenshot', 'timeAnomaly', 'mockLocation'}


def validate_evidence(platform, evidence, actions, *, physical_android=False, screenshot_executed=True):
    def require(value):
        if not value:
            raise ValueError('Incomplete or inconsistent example evidence')

    def finding(stage, detector, status, reason=None):
        values = evidence.get(stage, [])
        matches = [v for v in values if v.get('id') == detector]
        require(len(matches) == 1)
        require(matches[0].get('status') == status)
        if reason is not None:
            require(matches[0].get('reason') == reason)

    require(platform in ('android', 'ios'))
    require(not physical_android or platform == 'android')
    require(evidence.get('completed') is True and evidence.get('disposed') is True)
    require(screenshot_executed or physical_android)
    require([a.get('phase') for a in actions] == [p for p in PHASES if screenshot_executed or p != 'screenshot'])
    by_phase = {a['phase']: a for a in actions}
    for action in actions:
        require(action.get('status') == 'passed')
        host = evidence.get('host_' + action['phase'])
        require(host == {k: v for k, v in action.items() if k not in ('phase', 'status')})
    if screenshot_executed:
        require(by_phase['screenshot'].get('kind') == ('systemScreenshot' if physical_android else 'externalExport'))
        if not physical_android:
            require(by_phase['screenshot'].get('artifact') is True)
    kind = 'systemMediaProjection' if platform == 'android' else 'externalExport'
    require(by_phase['record_start'].get('kind') == kind and by_phase['record_start'].get('started') is True)
    require(by_phase['record_stop'].get('kind') == kind and by_phase['record_stop'].get('stopped') is True)
    require(by_phase['background'].get('kind') == 'realAppSwitch' and by_phase['background'].get('returned') is True)
    require(by_phase['final_view'].get('checked' if physical_android else 'artifact') is True)
    ids = [f.get('id') for f in evidence.get('allDetectors', [])]
    require(len(ids) == len(DETECTORS) and set(ids) == DETECTORS)
    for detector, enabled_reason in [('developerMode', 'developerModeEnabled'), ('usbDebugging', 'usbDebuggingEnabled')]:
        sample = next(f for f in evidence['allDetectors'] if f['id'] == detector)
        allowed = {('unsupported', 'unsupportedPlatform')} if platform == 'ios' else {
            ('detected', enabled_reason), ('unsupported', 'settingReadRestricted'),
            ('error', 'settingValueUnavailable'), ('error', 'missingPermission'), ('error', 'nativeFailure')}
        require((sample.get('status'), sample.get('reason')) in allowed)
    if physical_android:
        finding('local', 'emulator', 'notDetected', 'noKnownSignal')
        if screenshot_executed:
            samples = [v for v in evidence.get('afterScreenshot', []) if v.get('id') == 'screenshot']
            require(len(samples) == 1)
            capture = samples[0]
            pair = (capture.get('status'), capture.get('reason'))
            if pair == ('error', 'observationInterrupted'):
                values = capture.get('values', {})
                require(set(values) == {'screenshotObserved', 'observationActive'})
                require(values['screenshotObserved'] is True and values['observationActive'] is False)
            else:
                require(pair == ('detected', 'screenshotObserved'))
    else:
        finding('local', 'emulator', 'detected', 'emulatorBuild')
        finding('local', 'hook', 'notDetected', 'noKnownSignal')
    if platform == 'ios':
        finding('local', 'root', 'unsupported', 'simulatorEnvironment')
    for detector, reason in [('appIntegrity', 'integrityBaselineRequired'),
                             ('timeAnomaly', 'timeReferenceRequired'),
                             ('mockLocation', 'locationSampleRequired')]:
        finding('missingInputs', detector, 'error', reason)
    for detector in ('screenshot', 'screenRecording'):
        finding('captureInitial', detector, 'notDetected', 'noKnownSignal')
    finding('duringRecording', 'screenRecording',
            'detected' if platform == 'android' else 'notDetected',
            'screenCaptured' if platform == 'android' else 'noKnownSignal')
    finding('afterRecording', 'screenRecording', 'notDetected', 'noKnownSignal')
    lifecycle = evidence.get('lifecycle', [])
    require('paused' in lifecycle and lifecycle[-1] == 'resumed')
    finding('afterBackground', 'screenshot', 'error', 'observationInterrupted')
    finding('explicitStartAfterInterruption', 'screenshot', 'notDetected', 'noKnownSignal')
    finding('restarted', 'screenshot', 'notDetected', 'noKnownSignal')
    finding('stopped', 'screenshot', 'error', 'observationRequired')
