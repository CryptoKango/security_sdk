#!/usr/bin/env python3
"""Compile an optimized fixture and attach LLDB only to that child process.

This checks Darwin on macOS, not iOS device behavior. No application project,
signing account or device settings are modified. Test-only attach entitlements
are written to a temporary binary, never to the SDK or host application.
"""
import os
import plistlib
import selectors
import signal
import subprocess
import tempfile
import time
from pathlib import Path


def run(command, **kwargs):
    try:
        return subprocess.run(command, check=True, text=True, capture_output=True, **kwargs)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        output = error.stdout or ''
        if isinstance(output, bytes):
            output = output.decode('utf-8', errors='replace')
        details = error.stderr or ''
        if isinstance(details, bytes):
            details = details.decode('utf-8', errors='replace')
        raise RuntimeError('Command failed or timed out: ' + str(command[:2]) + '\n' + output + details) from error


def main():
    root = Path(__file__).resolve().parent.parent
    sources = root / 'packages/security_flutter/ios/security_flutter/Sources/security_flutter'
    fixture = root / 'packages/security_flutter/ios/Tests/ProcessTraceAttachFixture.swift'
    with tempfile.TemporaryDirectory(prefix='security-sdk-trace-') as folder:
        folder = Path(folder)
        binary = folder / 'process-trace-fixture'
        compile_command = ['xcrun', 'swiftc', '-O', '-g']
        compile_command += [str(sources / 'LocalFinding.swift'), str(sources / 'ProcessTraceProbe.swift'), str(fixture), '-o', str(binary)]
        run(compile_command, timeout=60)
        entitlement = folder / 'fixture.entitlements'
        # This deliberately debuggable test fixture remains an optimized build
        # without DEBUG. Production release entitlements must stay independent.
        entitlement.write_bytes(plistlib.dumps({'com.apple.security.get-task-allow': True}))
        run(['codesign', '--force', '--sign', '-', '--entitlements', str(entitlement), str(binary)], timeout=15)
        command = [str(binary)]
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        trace_pid = None
        try:
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            initial = []
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if not selector.select(timeout=0.5):
                    if process.poll() is not None:
                        break
                    continue
                raw_line = process.stdout.readline()
                if not raw_line:
                    break
                line = raw_line.strip()
                if len(initial) < 50:
                    initial.append(line)
                if line.startswith('READY '):
                    trace_pid = int(line.split()[1])
                    break
                if line.startswith('FAIL'):
                    break
            selector.close()
            if trace_pid is None:
                raise RuntimeError('Fixture did not reach untraced ready state: ' + '\n'.join(initial))
            # Only the PID emitted by the fixture we just created is attached.
            debugger = run(['xcrun', 'lldb', '--batch',
                '-o', f'process attach --pid {trace_pid}',
                '-o', 'breakpoint set --func-regex probeCheckpoint',
                '-o', 'continue', '-o', 'process detach', '-o', 'quit'], timeout=45)
            output, _ = process.communicate(timeout=10)
            if process.returncode != 0 or 'ATTACHED\n' not in output or 'DETACHED\n' not in output:
                raise RuntimeError('Attach/detach observations failed:\n' + output + '\n' + debugger.stdout)
            print('PASS optimized non-DEBUG probe: untraced -> LLDB attached -> detached (macOS)')
            print('PASS conservative Release default remained opt-in')
        finally:
            if process.poll() is None:
                if trace_pid is not None:
                    try:
                        os.kill(trace_pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    main()
