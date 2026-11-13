#!/usr/bin/env python3
"""Compile, create a real cookable map, import assets, and optionally package UE 5.6.

Requires a legitimately installed engine. This script never downloads UE or reports
an APK unless Unreal Automation Tool really produced one.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "SkyIslands.uproject"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--engine", type=Path, default=os.environ.get("UE56_ROOT"))
    p.add_argument("--target", choices=("editor", "windows", "android", "server"), default="editor")
    p.add_argument("--skip-assets", action="store_true", help="Use procedural development visuals; no art import")
    p.add_argument("--configuration", choices=("Development", "Shipping"), default="Development")
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    if not args.engine:
        parser().error("--engine or UE56_ROOT must point to an installed UE 5.6 directory")
    engine = args.engine.expanduser().resolve()
    version_path = engine / "Engine/Build/Build.version"
    if not version_path.is_file():
        raise SystemExit("Installed engine not found: " + str(version_path))
    version = json.loads(version_path.read_text(encoding="utf-8-sig"))
    if (version.get("MajorVersion"), version.get("MinorVersion")) != (5, 6):
        raise SystemExit("This project is pinned to UE 5.6; use a separate branch to migrate engine versions")
    system = platform.system()
    if system == "Windows":
        host = "Win64"
        build = engine / "Engine/Build/BatchFiles/Build.bat"
        uat = engine / "Engine/Build/BatchFiles/RunUAT.bat"
        editor = engine / "Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
    elif system == "Linux":
        host = "Linux"
        build = engine / "Engine/Build/BatchFiles/Linux/Build.sh"
        uat = engine / "Engine/Build/BatchFiles/RunUAT.sh"
        editor = engine / "Engine/Binaries/Linux/UnrealEditor-Cmd"
    else:
        raise SystemExit("Build automation supports a Windows or Linux UE 5.6 host")
    if args.target in ("windows", "server") and system != "Windows":
        raise SystemExit("Windows/server package target currently requires a Windows host")
    for path in (build, editor, uat):
        if not path.is_file():
            raise SystemExit("Engine installation is missing " + str(path))
    log_dir = ROOT / "Artifacts/BuildLogs"
    log_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "engine": str(engine), "engine_version": version,
        "project": str(PROJECT), "target": args.target,
        "configuration": args.configuration,
        "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "steps": [], "status": "running",
    }

    def run(name, command, marker=None):
        command = [str(x) for x in command]
        if system == "Windows" and command[0].lower().endswith(".bat"):
            # Batch scripts must run under cmd.exe, with Windows subprocess quoting.
            prefix = subprocess.list2cmdline([os.environ.get("COMSPEC", "cmd.exe"), "/d", "/s", "/c"])
            command = prefix + ' "' + subprocess.list2cmdline(command) + '"'
        print("Running:", name, flush=True)
        proc = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace",
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (log_dir / (name + ".log")).write_text(proc.stdout, encoding="utf-8")
        print(proc.stdout, end="", flush=True)
        step = {"name": name, "returncode": proc.returncode}
        report["steps"].append(step)
        if proc.returncode != 0:
            raise RuntimeError(f"{name} failed ({proc.returncode}); see Artifacts/BuildLogs")
        if marker and marker not in proc.stdout:
            raise RuntimeError(f"{name} produced no verified success marker {marker}")
        return proc.stdout

    try:
        run("compile-editor", [build, "SkyIslandsEditor", host, "Development", PROJECT,
                               "-WaitMutex", "-NoHotReloadFromIDE"])
        run("create-map", [editor, PROJECT, "/Engine/Maps/Entry", "-run=pythonscript",
                           "-script=" + str(ROOT / "Tools/create_world.py"),
                           "-unattended", "-nop4", "-nosplash", "-NullRHI", "-nosound"],
            "SKY_WORLD_BOOTSTRAP_OK")
        map_file = ROOT / "Content/Maps/SkyWorld.umap"
        if not map_file.is_file() or map_file.stat().st_size == 0:
            raise RuntimeError("Bootstrap did not write Content/Maps/SkyWorld.umap")
        if not args.skip_assets:
            run("fetch-assets", [sys.executable, ROOT / "Tools/fetch_assets.py"])
            run("import-assets", [editor, PROJECT, "/Engine/Maps/Entry", "-run=pythonscript",
                                  "-script=" + str(ROOT / "Tools/import_assets.py"),
                                  "-unattended", "-nop4", "-nosplash", "-NullRHI", "-nosound"],
                "SKY_ASSET_IMPORT_OK")
        if args.target != "editor":
            target_platform = "Android" if args.target == "android" else "Win64"
            destination = ROOT / "Artifacts" / args.target
            command = [uat, "BuildCookRun", "-project=" + str(PROJECT), "-noP4", "-utf8output",
                       "-unattended", "-build", "-cook", "-map=/Game/Maps/SkyWorld",
                       "-stage", "-pak", "-iostore", "-package", "-archive",
                       "-archivedirectory=" + str(destination)]
            if args.target == "server":
                command += ["-server", "-noclient", "-serverplatform=Win64",
                            "-serverconfig=" + args.configuration]
            else:
                command += ["-platform=" + target_platform, "-clientconfig=" + args.configuration]
            if args.target == "android":
                command += ["-cookflavor=ASTC"]
            run("package-" + args.target, command)
            if args.target == "android":
                apks = [str(p.relative_to(ROOT)) for p in destination.rglob("*.apk") if p.stat().st_size]
                if not apks:
                    raise RuntimeError("UAT returned success but no APK exists in the archive")
                report["apk_files"] = apks
        report["status"] = "succeeded"
    except (RuntimeError, OSError) as exc:
        report["status"] = "failed"
        report["error"] = str(exc)
        print(str(exc), file=sys.stderr)
    finally:
        report["finished_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        (log_dir / "BuildReport.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return 0 if report["status"] == "succeeded" else 1


if __name__ == "__main__":
    raise SystemExit(main())
