#!/usr/bin/env python3
"""Align only this example's Android tooling with the selected Flutter SDK."""
import argparse
import json
from pathlib import Path
import re


def template_versions(flutter):
    source = (Path(flutter).resolve().parent.parent / 'packages/flutter_tools/lib/src/android/gradle_utils.dart').read_text()
    versions = {}
    for key, constant in [('gradle', 'templateDefaultGradleVersion'),
                          ('agp', 'templateAndroidGradlePluginVersion'),
                          ('kotlin', 'templateKotlinGradlePluginVersion')]:
        matches = re.findall(r"const " + constant + r" = '([0-9]+(?:\.[0-9]+){1,2})';", source)
        if len(matches) != 1:
            raise ValueError('Unknown Flutter template layout; review before configuring')
        versions[key] = matches[0]
    return versions


def configure(android, versions):
    android = Path(android)
    settings = android / 'settings.gradle.kts'
    wrapper = android / 'gradle/wrapper/gradle-wrapper.properties'
    properties = android / 'gradle.properties'
    app = android / 'app/build.gradle.kts'
    text = settings.read_text()
    for plugin, version in [('com.android.application', versions['agp']),
                            ('org.jetbrains.kotlin.android', versions['kotlin'])]:
        text, count = re.subn(r'(id\("' + re.escape(plugin) + r'"\) version ")[^"]+(" apply false)',
                             lambda match: match[1] + version + match[2], text)
        if count != 1:
            raise ValueError('Unexpected example plugin configuration')
    distribution, count = re.subn(r'gradle-[0-9.]+-all\.zip', 'gradle-' + versions['gradle'] + '-all.zip', wrapper.read_text())
    if count != 1:
        raise ValueError('Unexpected example Gradle wrapper')
    app_text = app.read_text()
    kotlin_line = '    id("org.jetbrains.kotlin.android")\n'
    if app_text.count('id("com.android.application")') != 1 or app_text.count(kotlin_line) > 1:
        raise ValueError('Unexpected example application plugins')
    app_text = app_text.replace(kotlin_line, '')
    if int(versions['agp'].split('.')[0]) < 9:
        app_text = app_text.replace('    id("com.android.application")\n',
                                    '    id("com.android.application")\n' + kotlin_line)
    # Current Flutter auto-applies KGP to plugins; retain its AGP 9 bridge flags.

    flags = [line for line in properties.read_text().splitlines()
             if not line.startswith(('android.newDsl=', 'android.builtInKotlin='))]
    if int(versions['agp'].split('.')[0]) >= 9:
        flags += ['android.newDsl=false', 'android.builtInKotlin=false']
    # Validate all inputs before writing any file. No app/library source changes.
    settings.write_text(text)
    app.write_text(app_text)
    wrapper.write_text(distribution)
    properties.write_text('\n'.join(flags) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', type=Path, required=True)
    args = parser.parse_args()
    versions = template_versions(args.flutter)
    configure(Path(__file__).resolve().parents[1] / 'example/android', versions)
    print(json.dumps(versions))


if __name__ == '__main__':
    main()
