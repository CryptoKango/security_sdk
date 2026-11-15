#!/usr/bin/env python3
"""Build/test independent copies so multiple Flutter SDKs cannot share generated state."""
import argparse
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess

from configure_example_android import configure, template_versions



def configure_jdk_override(repo, java_home):
    """Honor an explicit JDK only in the runner's disposable repository copy."""
    java_home = Path(java_home).resolve()
    if not (java_home/'bin/java').is_file():
        raise ValueError('Invalid JDK home')
    android = Path(repo)/'example/android'
    properties = android/'gradle.properties'
    lines = [line for line in properties.read_text().splitlines()
             if not line.startswith('org.gradle.java.home=')]
    # Daemon criteria outrank java.home, so remove them only in this isolated copy.
    (android/'gradle/gradle-daemon-jvm.properties').unlink(missing_ok=True)
    properties.write_text('\n'.join(lines + ['org.gradle.java.home=' + str(java_home)]) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter', type=Path, action='append', required=True)
    parser.add_argument('--jdk-home', type=Path, help='JDK 17 or 21; applied only to isolated Android build')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--native', nargs='*', choices=['android', 'ios'], default=[])
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).resolve().parents[1]
    reports = []
    env = dict(os.environ, FLUTTER_SWIFT_PACKAGE_MANAGER='false', FLUTTER_UISCENE_MIGRATION='false')
    ignored = shutil.ignore_patterns('.git', '.dart_tool', 'build', '.gradle', 'Pods', '.symlinks',
        'ephemeral', '__pycache__', '.flutter-plugins*', 'local.properties', 'Generated.xcconfig',
        'flutter_export_environment.sh', 'GeneratedPluginRegistrant.*')
    for index, executable in enumerate(args.flutter, 1):
        flutter = executable.resolve()
        dart = flutter.with_name('dart')
        run = output / str(index)
        run.mkdir()
        repo = run / 'repo'
        shutil.copytree(source, repo, ignore=ignored)
        if args.jdk_home:
            configure_jdk_override(repo, args.jdk_home)
        report = {'status': 'failed', 'steps': [], 'nativeTargets': args.native,
                  'jdkSelection': 'explicitOverride' if args.jdk_home else 'projectCriteria17'}
        reports.append(report)
        def command(name, argv, cwd=repo, timeout=1200):
            with (run / (name + '.log')).open('w') as log:
                result = subprocess.run([str(x) for x in argv], cwd=cwd, env=env,
                    stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
            report['steps'].append({'name': name, 'passed': result.returncode == 0})
            if result.returncode != 0:
                raise RuntimeError('Step failed')
        try:
            command('version', [flutter, '--version', '--machine'])
            version = json.loads((run / 'version.log').read_text())
            report['flutter'] = version['frameworkVersion']
            report['dart'] = version['dartSdkVersion']
            if 'android' in args.native:
                versions = template_versions(flutter)
                configure(repo / 'example/android', versions)
                report['androidToolchain'] = versions
            command('pub-get', [flutter, 'pub', 'get'])
            command('core-analyze', [dart, 'analyze', 'packages/security_core'])
            for package in ['packages/security_flutter', 'example']:
                command(package.split('/')[-1] + '-analyze', [flutter, 'analyze', '--no-pub', package])
            command('core-test', [dart, 'test'], repo / 'packages/security_core')
            for package in ['packages/security_flutter', 'example']:
                command(package.split('/')[-1] + '-test', [flutter, 'test', '--no-pub'], repo / package)
            if 'android' in args.native:
                command('android-build', [flutter, 'build', 'apk', '--debug', '--no-pub', '--target-platform=android-arm64'], repo / 'example')
                if not (repo/'example/build/app/outputs/flutter-apk/app-debug.apk').is_file():
                    raise RuntimeError('Missing APK')
                if int(versions['agp'].split('.')[0]) >= 9:
                    properties = (repo/'example/android/gradle.properties').read_text().splitlines()
                    if 'android.builtInKotlin=false' not in properties or 'android.builtInKotlin=true' in properties:
                        raise RuntimeError('Unexpected Flutter Kotlin bridge configuration')
                    report['kotlinMode'] = 'flutterLegacyBridge'
                else:
                    report['kotlinMode'] = 'externalPlugin'
            if 'ios' in args.native:
                command('ios-build', [flutter, 'build', 'ios', '--simulator', '--debug', '--no-pub'], repo / 'example')
                if not (repo/'example/build/ios/iphonesimulator/Runner.app').is_dir():
                    raise RuntimeError('Missing simulator app')
                app_info = repo/'example/build/ios/iphonesimulator/Runner.app/Info.plist'
                report['iosMinimumOSVersion'] = plistlib.loads(app_info.read_bytes())['MinimumOSVersion']
            report['status'] = 'passed'
        except Exception:
            report['reason'] = 'commandOrArtifactFailed'
        (run / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report), flush=True)
    (output / 'report.json').write_text(json.dumps(reports, indent=2) + '\n')
    if any(r['status'] != 'passed' for r in reports):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
