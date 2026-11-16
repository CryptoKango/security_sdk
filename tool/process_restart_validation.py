"""Controlled process restart evidence; never classifies an adb kill as LMK."""


def validate_probe(value):
    def need(ok):
        if not ok: raise ValueError('Incomplete or inconsistent restart probe')
    need(type(value) is dict and set(value)=={'schemaVersion','completed','startup','beforeStart','active','seeded','interrupted'})
    need(type(value['schemaVersion']) is int and value['schemaVersion']==1 and value['completed'] is True)
    def native(state, seeded):
        need(type(state) is dict and set(state)=={'activityCreates','lastExitCause','cache'})
        need(type(state['activityCreates']) is int and state['activityCreates']==1)
        need(state['lastExitCause'] in ('none','unsupported','lowMemory','userRequested','signaled','other'))
        cache=state['cache'];need(type(cache) is dict)
        counts=dict(activityCreated=int(seeded),activityDestroyed=int(seeded),engineCreated=int(seeded),engineDestroyed=0,trimCallbacks=0)
        flags=dict(cachePresent=seeded,cacheMatchesEngine=seeded,enginePresent=seeded,activityPresent=False,ready=seeded,focused=False)
        need(set(cache)==set(counts)|set(flags))
        for key,expected in counts.items():
            need(type(cache[key]) is int and cache[key]>=0)
            if key!='trimCallbacks':need(cache[key]==expected)
        for key,expected in flags.items():need(cache[key] is expected)
    native(value['startup'],False);native(value['seeded'],True)
    cases=[('beforeStart',dict(status='error',reason='observationRequired',values={})),
           ('active',dict(status='notDetected',reason='noKnownSignal',values=dict(signalDetected=False,screenshotObserved=False,observationActive=True))),
           ('interrupted',dict(status='error',reason='observationInterrupted',values=dict(screenshotObserved=False,observationActive=False)))]
    for key,shot in cases:
        result=value[key];need(type(result) is dict and set(result)=={'screenshot','screenRecording'})
        for finding in result.values():
            need(type(finding) is dict and type(finding.get('values')) is dict)
            need(all(type(v) is bool for v in finding['values'].values()))
        need(result['screenshot']==shot)
        need(result['screenRecording']==dict(status='notDetected',reason='noKnownSignal',values=dict(signalDetected=False)))
    return True


def validate_run(value):
    def need(ok):
        if not ok:raise ValueError('Process exit/relaunch evidence missing')
    need(type(value) is dict and 'reason' not in value)
    need(value.get('buildValidated') is True and value.get('cleanupCompleted') is True)
    need(value.get('terminationMethod')=='adbAmKillBackground')
    need(value.get('actualLowMemoryKillVerified') is False)
    launches=value.get('launches');need(type(launches) is list and len(launches)==3)
    for index,launch in enumerate(launches):
        need(type(launch) is dict and type(launch.get('round')) is int and launch.get('round')==index+1)
        validate_probe(launch.get('probe'))
        if index:need(launch.get('previousProcessExited') is True and launch.get('differentProcess') is True)
    return 'passedControlledRestart'
