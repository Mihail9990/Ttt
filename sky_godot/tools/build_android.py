#!/usr/bin/env python3
"""Import, test and export a real Godot4.6.3 debug APK; never fabricate success.

Uses the existing personal development key from the repository (not a store key).
Android SDK and a complete Java SDK must be installed before invoking this tool.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BAD_LOG = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|Error importing|^ERROR:", re.I | re.M)


def cli():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--sdk', type=Path, default=os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME'))
    parser.add_argument('--java', type=Path, default=os.environ.get('JAVA_HOME'))
    parser.add_argument('--keystore', type=Path, default=os.environ.get('GODOT_ANDROID_KEYSTORE_DEBUG_PATH'))
    parser.add_argument('--output', type=Path, default=ROOT / 'Artifacts/Sky-Islands-Godot.apk')
    parser.add_argument('--skip-assets', action='store_true', help='Use sources that were already verified and staged')
    parser.add_argument('--skip-tests', action='store_true', help='Only for a separately tested identical source revision')
    parser.add_argument('--prepare-only', action='store_true', help='Validate dependencies/settings without running Godot')
    return parser


def main(argv=None):
    args = cli().parse_args(argv)
    sdk = args.sdk.expanduser().resolve() if args.sdk else None
    java = args.java.expanduser().resolve() if args.java else None
    key = args.keystore.expanduser().resolve() if args.keystore else ROOT.parent / 'legion_game/signing/legion-test.jks'
    if not key.is_file():
        local_key = ROOT / '.local-tools/legion-test.jks'
        if local_key.is_file():
            key = local_key
    if not sdk or not (sdk / 'platform-tools/adb').is_file():
        raise SystemExit('Set --sdk or ANDROID_SDK_ROOT to an Android SDK with platform-tools')
    suffix = '.exe' if os.name == 'nt' else ''
    if not java or not (java / ('bin/javac' + suffix)).is_file():
        raise SystemExit('Set --java or JAVA_HOME to a full Java SDK (JDK17 recommended)')
    if not key.is_file():
        raise SystemExit('Personal development signing key not found; pass --keystore')
    apksigner = sdk / 'build-tools/35.0.1' / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
    if not apksigner.is_file() or not (sdk / 'platforms/android-35/android.jar').is_file():
        raise SystemExit('Install build-tools;35.0.1 and platforms;android-35 with sdkmanager')
    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    logs = ROOT / 'Artifacts/Logs'
    logs.mkdir(parents=True, exist_ok=True)
    config = ROOT / '.local-tools/godot-config'
    (config / 'godot').mkdir(parents=True, exist_ok=True)
    escape = lambda p: str(p).replace('\\', '/').replace('"', '\\"')
    (config / 'godot/editor_settings-4.6.tres').write_text(
        '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
        f'export/android/android_sdk_path = "{escape(sdk)}"\n'
        f'export/android/java_sdk_path = "{escape(java)}"\n', encoding='utf-8')
    env = os.environ.copy()
    env.update({'JAVA_HOME': str(java), 'ANDROID_HOME': str(sdk), 'ANDROID_SDK_ROOT': str(sdk),
                'XDG_CONFIG_HOME': str(config), 'GODOT_ANDROID_KEYSTORE_DEBUG_PATH': str(key),
                'GODOT_ANDROID_KEYSTORE_DEBUG_USER': 'legiondebug',
                'GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD': 'android'})
    env['PATH'] = str(java / 'bin') + os.pathsep + env.get('PATH', '')
    report = {'engine': 'Godot 4.6.3', 'started_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'status': 'running', 'steps': [], 'source_revision': os.environ.get('GITHUB_SHA', 'local')}

    def run(name, command, timeout=600, scan=True):
        print('Running:', name, flush=True)
        proc = subprocess.run([str(x) for x in command], cwd=ROOT, env=env, text=True,
                              encoding='utf-8', errors='replace', stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=timeout)
        (logs / (name + '.log')).write_text(proc.stdout, encoding='utf-8')
        print(proc.stdout, end='', flush=True)
        report['steps'].append({'name': name, 'returncode': proc.returncode})
        if proc.returncode or (scan and BAD_LOG.search(proc.stdout)):
            raise RuntimeError(f'{name} failed; inspect Artifacts/Logs/{name}.log')
        return proc.stdout

    preset = ROOT / 'export_presets.cfg'
    original_preset = preset.read_text(encoding='utf-8')
    try:
        version = run('engine-version', [args.godot, '--headless', '--version'], scan=False)
        if not version.strip().startswith('4.6.3.stable'):
            raise RuntimeError('Use official Godot4.6.3 stable and matching export templates')
        if args.prepare_only:
            report['status'] = 'dependencies_ready'
            return 0
        if not args.skip_assets:
            run('prepare-assets', [sys.executable, ROOT / 'tools/prepare_assets.py'])
        run('import', [args.godot, '--headless', '--path', ROOT, '--editor', '--import'])
        if not args.skip_tests:
            for script in ('test_simulation.gd', 'test_terrain.gd', 'test_game.gd', 'test_state.gd', 'test_network.gd'):
                path = ROOT / 'tests' / script
                if not path.is_file():
                    raise RuntimeError('Required gameplay test is missing: ' + str(path))
                run(script[:-3], [args.godot, '--headless', '--path', ROOT, '--script', 'res://tests/' + script, '--', '--fresh'])
        number = int(os.environ.get('GITHUB_RUN_NUMBER', '0'))
        if number < 0 or number > 999999:
            raise RuntimeError('Invalid workflow run number')
        updated = re.sub(r'^version/code=\d+$', f'version/code={20000+number}', original_preset, flags=re.M)
        updated = re.sub(r'^version/name="[^"]+"$', f'version/name="0.2.{number}"', updated, flags=re.M)
        preset.write_text(updated, encoding='utf-8')
        # Remove only the exact requested previous artifact, so a failed export
        # cannot accidentally validate an old APK from a previous run.
        if output.exists():
            output.unlink()
        run('export-android', [args.godot, '--headless', '--path', ROOT, '--export-debug', 'Android', output], timeout=1200)
        if not output.is_file() or output.stat().st_size < 1024*1024:
            raise RuntimeError('Godot did not produce a non-empty APK')
        with zipfile.ZipFile(output) as archive:
            if 'AndroidManifest.xml' not in archive.namelist() or not any(p.startswith('lib/arm64-v8a/') for p in archive.namelist()):
                raise RuntimeError('Output does not contain an Android manifest and arm64 libraries')
        run('verify-signature', [apksigner, 'verify', '--print-certs', output], scan=False)
        report['status'] = 'succeeded'
        report['apk'] = str(output)
        report['apk_bytes'] = output.stat().st_size
        print('SKY_GODOT_APK_OK', output, flush=True)
    except (RuntimeError, OSError, subprocess.TimeoutExpired, zipfile.BadZipFile) as exc:
        report['status'] = 'failed'
        report['error'] = str(exc)
        print(str(exc), file=sys.stderr)
    finally:
        preset.write_text(original_preset, encoding='utf-8')
        report['finished_utc'] = dt.datetime.now(dt.timezone.utc).isoformat()
        (ROOT / 'Artifacts/BuildReport.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return 0 if report['status'] == 'succeeded' else 1


if __name__ == '__main__':
    raise SystemExit(main())
