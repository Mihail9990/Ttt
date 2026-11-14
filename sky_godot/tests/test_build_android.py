"""Failure-mode checks: Godot parse errors and stale artifacts never pass as APKs."""
from __future__ import annotations
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / 'tools/build_android.py'
spec = importlib.util.spec_from_file_location('sky_build_android', MODULE_PATH)
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BuildFailureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'project'
        self.root.mkdir()
        self.sdk = Path(self.temp.name) / 'sdk'
        self.java = Path(self.temp.name) / 'java'
        for path in (self.sdk/'platform-tools/adb', self.sdk/'build-tools/35.0.1/apksigner',
                     self.sdk/'platforms/android-35/android.jar', self.java/'bin/javac',
                     self.root/'.local-tools/legion-test.jks'):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'test fixture')
        self.preset = 'version/code=20000\nversion/name="0.2.0"\n'
        (self.root/'export_presets.cfg').write_text(self.preset)
        self.output = self.root/'Artifacts/game.apk'
        self.args = ['--sdk',str(self.sdk),'--java',str(self.java),'--skip-assets','--skip-tests','--output',str(self.output)]

    def tearDown(self):
        self.temp.cleanup()

    def invoke(self, output_for):
        def fake_run(command, **kwargs):
            if '--version' in command:
                output = '4.6.3.stable.official.test\n'
            else:
                output = output_for(command)
            return subprocess.CompletedProcess(command, 0, output)
        with patch.object(build,'ROOT',self.root), patch.object(build.subprocess,'run',side_effect=fake_run), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            result = build.main(self.args)
        report = json.loads((self.root/'Artifacts/BuildReport.json').read_text())
        self.assertEqual((self.root/'export_presets.cfg').read_text(), self.preset)
        return result,report

    def test_parse_error_with_zero_process_exit_fails(self):
        code,report = self.invoke(lambda command:'SCRIPT ERROR: Parse Error: broken script\n' if '--import' in command else '')
        self.assertEqual(code,1)
        self.assertEqual(report['status'],'failed')
        self.assertNotIn('apk',report)
        self.assertEqual(len(report['steps']),2)

    def test_success_without_new_apk_fails(self):
        code,report = self.invoke(lambda command:'')
        self.assertEqual(code,1)
        self.assertIn('did not produce',report['error'])
        self.assertNotIn('apk',report)

    def test_previous_apk_cannot_mask_failed_export(self):
        self.output.parent.mkdir(parents=True)
        self.output.write_bytes(b'old artifact' * 200000)
        code,report = self.invoke(lambda command:'')
        self.assertEqual(code,1)
        self.assertFalse(self.output.exists())
        self.assertNotIn('apk',report)


if __name__ == '__main__':
    unittest.main()
