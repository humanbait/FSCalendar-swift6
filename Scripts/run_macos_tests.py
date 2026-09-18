#!/usr/bin/env python3
"""Run package + window-hosted/UI tests on an explicit native Mac destination."""
import argparse
import datetime
import hashlib
import json
import platform
from pathlib import Path
import subprocess
from run_device_tests import command_output, run_logged

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--destination', default=f'platform=macOS,arch={platform.machine()}')
    parser.add_argument('--label', default='macos')
    parser.add_argument('xcode_arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.destination.startswith('platform=macOS,'):
        parser.error('Use an explicit native Mac destination: platform=macOS,id=... or platform=macOS,arch=...')
    if not args.label.replace('-', '').replace('_', '').isalnum():
        parser.error('Label must contain only letters, digits, hyphens or underscores')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = ROOT / 'artifacts' / f'{args.label}-{stamp}'
    output.mkdir(parents=True)
    metadata = {'startedAt': stamp, 'implementation': 'AppKit', 'destination': args.destination,
                'configuration': 'Debug', 'status': 'running', 'artifacts': str(output),
                'fixtures': {'calendar': 'gregorian', 'timeZone': 'GMT', 'locale': 'en_US_POSIX',
                             'today': '2024-02-14', 'bounds': ['2020-01-01', '2030-12-31']}}
    for name, command in [('toolchain', ['xcodebuild', '-version']), ('swift', ['swift', '--version']),
                          ('os', ['sw_vers']), ('hardware', ['system_profiler', 'SPHardwareDataType']),
                          ('git-revision', ['git', 'rev-parse', 'HEAD']), ('git-status', ['git', 'status', '--short'])]:
        command_output(command, output / f'{name}.txt')
    files = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard'], cwd=ROOT, text=True).splitlines()
    metadata['sourceSHA256'] = {f: hashlib.sha256((ROOT / f).read_bytes()).hexdigest() for f in sorted(set(files)) if (ROOT / f).is_file()}
    def save():
        (output / 'run.json').write_text(json.dumps(metadata, indent=2) + '\n')
    save()
    package = ['swift', 'test', '-Xswiftc', '-warnings-as-errors']
    code, reason = run_logged(package, output / 'package.log', 180, 900)
    metadata['packageExitCode'] = code
    result = output / 'Tests.xcresult'
    if code == 0:
        extra = args.xcode_arguments
        if extra[:1] == ['--']: extra = extra[1:]
        command = ['xcodebuild', 'test', '-project', str(ROOT / 'Example/CalendarShowcase.xcodeproj'),
                   '-scheme', 'CalendarShowcaseMac', '-destination', args.destination,
                   '-derivedDataPath', str(ROOT / 'artifacts/MacDerivedData'), '-resultBundlePath', str(result),
                   '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES',
                   '-maximum-test-execution-time-allowance', '300', 'SWIFT_TREAT_WARNINGS_AS_ERRORS=YES', *extra]
        metadata['command'] = command; save()
        code, reason = run_logged(command, output / 'build.log', 180, 1800)
    metadata.update(exitCode=code, status='passed' if code == 0 else 'failed', stopReason=reason)
    if result.exists():
        status = command_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)], output / 'summary.json')
        if status == 0:
            summary = json.loads((output / 'summary.json').read_text())
            metadata['tests'] = {k: summary.get(k) for k in ['result', 'totalTestCount', 'passedTests', 'failedTests', 'skippedTests']}
        command_output(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(output / 'attachments')], output / 'attachment-export.log')
        command_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'metrics', '--path', str(result)], output / 'metrics.json')
    save()
    (output / 'summary.md').write_text(f"# Native macOS validation\n\nStatus: **{metadata['status']}**\n\nDestination: `{args.destination}`\n\nPackage exit: {metadata['packageExitCode']}; Xcode exit: {code}\n\nTests: `{json.dumps(metadata.get('tests', {}))}`\n\nHardware/toolchain/source hashes, logs, metrics and screenshots are stored beside this summary.\n\nManual VoiceOver and system accessibility observations are recorded separately in Documentation/MACOS-VALIDATION.md. macOS 13 runtime and exact Swift 6.2 remain separate release gates.\n")
    if code == 0:
        app = ROOT / 'artifacts/MacDerivedData/Build/Products/Debug/CalendarShowcaseMac.app'
        command_output(['open', '-n', str(app)], output / 'launch.log')
    print(f'\nMac test artifacts: {output}')
    return code

if __name__ == '__main__':
    raise SystemExit(main())
