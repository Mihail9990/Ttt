#!/usr/bin/env python3
"""Run actual localhost ENet host/client processes against the Godot game scene.

Usage: python3 sky_godot/tests/run_network_tests.py
Exit77 means the OS rejected UDP hosting; it is NOT a network PASS.
Each process uses an isolated XDG data directory and --fresh, leaving real saves alone.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=shutil.which('godot') or 'godot')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='sky-network-') as temporary:
        output = Path(temporary)
        processes: list[subprocess.Popen] = []
        log_files = []
        try:
            def start(role: str):
                environment = os.environ.copy()
                environment['XDG_DATA_HOME'] = str(output / (role + '-data'))
                environment['XDG_CONFIG_HOME'] = str(output / (role + '-config'))
                log = (output / (role + '.log')).open('w', encoding='utf-8')
                log_files.append(log)
                command = [args.godot, '--headless', '--path', str(ROOT), '--script',
                           'res://tests/network_peer.gd', '--', '--fresh',
                           '--net-role=' + role, '--net-output=' + str(output)]
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, env=environment)
                processes.append(process)
                return process

            host = start('host')
            deadline = time.monotonic() + 20
            while not (output / 'host.ready.json').is_file():
                if host.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Host failed before network became ready')
                time.sleep(0.05)
            ready = json.loads((output / 'host.ready.json').read_text())
            if ready.get('blocked'):
                host.wait(timeout=5)
                print('GODOT NETWORK ENVIRONMENT BLOCKED:', ready.get('message'))
                return 77
            client = start('client')
            client.wait(timeout=25)
            host.wait(timeout=8)
            reports = {role: json.loads((output / (role + '.json')).read_text()) for role in ('host', 'client')}
            for role, process in (('host', host), ('client', client)):
                if process.returncode != 0 or reports[role].get('failures'):
                    raise RuntimeError(role + ' failed: ' + json.dumps(reports[role], ensure_ascii=False))
                log = (output / (role + '.log')).read_text(encoding='utf-8')
                if any(marker in log for marker in ('SCRIPT ERROR:', 'Parse Error:', 'Assertion failed:', 'ERROR:')):
                    raise RuntimeError(role + ' emitted a Godot runtime error')
            print('GODOT NETWORK PASS: actual 2-process ENet handshake, peer-owned inventory, '
                  'NPC purchase, spoofed identity rejection, replay rejection, and late-join edited terrain')
            print(json.dumps(reports, ensure_ascii=False))
            return 0
        except (RuntimeError, subprocess.TimeoutExpired, OSError, ValueError) as error:
            print('GODOT NETWORK FAIL:', error, file=sys.stderr)
            for role in ('host', 'client'):
                log = output / (role + '.log')
                if log.exists():
                    print('--- ' + role + ' ---\n' + log.read_text(encoding='utf-8'), file=sys.stderr)
            return 1
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
            for process in processes:
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            for log in log_files:
                log.close()


if __name__ == '__main__':
    raise SystemExit(main())
