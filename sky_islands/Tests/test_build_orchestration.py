"""Exercise failure/reporting with a simulated engine, not Unreal itself."""
from contextlib import redirect_stdout, redirect_stderr
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "Tools/build.py"
spec = importlib.util.spec_from_file_location("sky_build", MODULE)
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BuildReportingTests(unittest.TestCase):
    def setup_fake(self, temp, editor_body, compiler_status=0):
        root = Path(temp) / "Project"
        engine = Path(temp) / "UE"
        (root / "Tools").mkdir(parents=True)
        (root / "SkyIslands.uproject").write_text('{}')
        version = engine / "Engine/Build/Build.version"
        version.parent.mkdir(parents=True)
        version.write_text('{"MajorVersion":5,"MinorVersion":6,"PatchVersion":0}')
        scripts = {
            "Engine/Build/BatchFiles/Linux/Build.sh": f"#!/bin/sh\nexit {compiler_status}\n",
            "Engine/Build/BatchFiles/RunUAT.sh": "#!/bin/sh\nexit 0\n",
            "Engine/Binaries/Linux/UnrealEditor-Cmd": "#!/bin/sh\n" + editor_body,
        }
        for relative, body in scripts.items():
            path = engine / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body)
            path.chmod(0o755)
        return root, engine

    def invoke(self, root, engine):
        with patch.object(build, "ROOT", root), patch.object(build, "PROJECT", root / "SkyIslands.uproject"), \
             patch.object(build.platform, "system", return_value="Linux"), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            status = build.main(["--engine", str(engine), "--skip-assets"])
        report = json.loads((root / "Artifacts/BuildLogs/BuildReport.json").read_text())
        return status, report

    def test_compiler_failure_stops_before_map(self):
        with tempfile.TemporaryDirectory() as temp:
            root, engine = self.setup_fake(temp, "exit 0\n", compiler_status=7)
            status, report = self.invoke(root, engine)
            self.assertEqual(status, 1)
            self.assertEqual(report["status"], "failed")
            self.assertEqual([s["name"] for s in report["steps"]], ["compile-editor"])
            self.assertNotIn("apk_files", report)

    def test_silent_python_failure_is_not_success(self):
        with tempfile.TemporaryDirectory() as temp:
            root, engine = self.setup_fake(temp, "echo 'Python exception'\nexit 0\n")
            status, report = self.invoke(root, engine)
            self.assertEqual(status, 1)
            self.assertIn("success marker", report["error"])
            self.assertEqual(report["status"], "failed")

    def test_marker_without_saved_map_is_not_success(self):
        with tempfile.TemporaryDirectory() as temp:
            root, engine = self.setup_fake(temp, "echo SKY_WORLD_BOOTSTRAP_OK\nexit 0\n")
            status, report = self.invoke(root, engine)
            self.assertEqual(status, 1)
            self.assertIn("did not write", report["error"])


if __name__ == "__main__":
    unittest.main()
