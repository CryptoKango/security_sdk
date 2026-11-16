"""Classify paired screenshot observations without inventing positive stimuli."""
INPUTS = {'hardwareButtonsConfirmed', 'unableToCapture', 'notConfirmed', 'adbExport'}
FLAGS = {'registered', 'cleanupPending', 'focused', 'resumed', 'attached', 'sameWindow',
         'inPictureInPicture', 'secureWindow', 'permissionGranted', 'eventsTruncated'}


def validate_capture_snapshots(before, after):
    """Validate bounded, ordered native callback evidence without SDK assumptions."""
    def require(ok):
        if not ok: raise ValueError('Incomplete or inconsistent capture evidence')
    snapshots = []
    for state in (before, after):
        require(isinstance(state, dict) and set(state) == FLAGS | {'callbacks', 'events'})
        require(all(type(state.get(k)) is bool for k in FLAGS))
        require(not state['registered'] or state['cleanupPending'])
        require(type(state.get('callbacks')) is int and state['callbacks'] >= 0)
        events = state.get('events')
        require(isinstance(events, list) and len(events) <= 64)
        previous_ms = -1
        for index, event in enumerate(events):
            require(isinstance(event, dict) and set(event) == {'kind', 'value', 'sequence', 'elapsedMs'})
            require(event.get('kind') in {'start', 'focus', 'resumed', 'screenshot'})
            require(type(event.get('value')) is bool)
            require(type(event.get('sequence')) is int and event['sequence'] == index)
            require(type(event.get('elapsedMs')) is int and event['elapsedMs'] >= max(0, previous_ms))
            previous_ms = event['elapsedMs']
        require(bool(events) and events[0]['kind'] == 'start')
        if not state['eventsTruncated']:
            require(sum(e['kind'] == 'screenshot' for e in events) == state['callbacks'])
        snapshots.append(state)
    before, after = snapshots
    require(before['callbacks'] == 0)
    require(after['events'][:len(before['events'])] == before['events'])
    return before, after


def classify_capture_evidence(evidence):
    def require(ok):
        if not ok:
            raise ValueError('Incomplete or inconsistent capture evidence')

    require(evidence.get('schemaVersion') == 3 and evidence.get('completed') is True)
    require(evidence.get('cleanupCompleted') is True)
    stimulus = evidence.get('captureInput')
    require(stimulus in INPUTS)
    before, after = validate_capture_snapshots(evidence.get('nativeBefore'), evidence.get('nativeAfter'))
    for name in ['sdkBefore', 'sdk', 'afterStop', 'afterRestart']:
        state = evidence.get(name)
        require(isinstance(state, dict))
        pair = (state.get('status'), state.get('reason'))
        require(pair in {('detected', 'screenshotObserved'), ('notDetected', 'noKnownSignal'),
                         ('error', 'observationInterrupted'), ('error', 'noActivity'),
                         ('error', 'missingPermission'), ('error', 'nativeFailure'),
                         ('error', 'observationRequired')})
        values = state.get('values')
        require(isinstance(values, dict) and set(values) <= {'signalDetected', 'screenshotObserved', 'observationActive'})
        if 'signalDetected' in values:
            require(type(values['signalDetected']) is bool and pair[0] in {'detected', 'notDetected'})
            require(values['signalDetected'] == (pair[0] == 'detected'))
        if 'screenshotObserved' in values or 'observationActive' in values:
            require(type(values.get('screenshotObserved')) is bool and type(values.get('observationActive')) is bool)
            if values['observationActive']:
                require(pair[0] in {'detected', 'notDetected'} and values['screenshotObserved'] == (pair[0] == 'detected'))
            else:
                require(pair == ('error', 'observationInterrupted'))
    require((evidence['afterStop']['status'], evidence['afterStop']['reason']) == ('error', 'observationRequired'))
    require(evidence['afterRestart']['status'] == 'notDetected' and evidence['afterRestart']['reason'] == 'noKnownSignal')
    require(evidence['afterRestart']['values'] == {'signalDetected':False, 'screenshotObserved':False, 'observationActive':True})
    if stimulus != 'hardwareButtonsConfirmed':
        return 'inconclusiveInput'
    if (any(not before[k] for k in ['registered', 'focused', 'resumed', 'attached', 'sameWindow', 'permissionGranted'])
            or before['inPictureInPicture'] or before['secureWindow']
            or evidence['sdkBefore']['status'] != 'notDetected'):
        return 'preconditionUnavailable'
    if before['eventsTruncated'] or after['eventsTruncated']:
        return 'incompleteEventHistory'
    if not after['registered'] or not after['permissionGranted']:
        return 'observerUnavailable'
    pair = (evidence['sdk']['status'], evidence['sdk']['reason'])
    gap = (any(not after[k] for k in ['focused', 'resumed', 'attached', 'sameWindow'])
           or after['inPictureInPicture'] or after['secureWindow']
           or any(e['kind'] in {'focus', 'resumed'} and not e['value'] for e in after['events']))
    if gap:
        # Confirm the historical callback before the first gap. This passes
        # screenshot receipt only; it does not claim ongoing observation is valid.
        prefix = []
        for event in after['events']:
            if event['kind'] in {'focus', 'resumed'} and not event['value']: break
            prefix.append(event)
        confirmed_before_gap = any(e['kind'] == 'screenshot' and e['value'] for e in prefix)
        if (confirmed_before_gap and pair == ('error', 'observationInterrupted') and
                evidence['sdk']['values'] == {'screenshotObserved':True, 'observationActive':False}):
            return 'passedWithInterruption'
        return 'scopeInterrupted' if pair in {('error', 'observationInterrupted'), ('error', 'noActivity')} else 'unexpectedResultAcrossInterruption'
    if after['callbacks'] == 0:
        if pair == ('notDetected', 'noKnownSignal'):
            return 'noSystemCallbackObserved'
        return 'inconsistentCallbacks' if pair[0] == 'detected' else 'sdkUnavailable'
    if pair == ('detected', 'screenshotObserved'):
        return 'passed'
    return 'sdkMissedCallback' if pair[0] == 'notDetected' else 'sdkUnavailable'
