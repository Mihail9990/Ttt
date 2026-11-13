#!/usr/bin/env python3
"""Portable source/config validation. This is not Unreal compilation."""
from pathlib import Path
import ast
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def validate():
    project = json.loads((ROOT / "SkyIslands.uproject").read_text(encoding="utf-8"))
    assert project["EngineAssociation"] == "5.6", "Unexpected engine version"
    assert any(m["Name"] == "SkyIslands" for m in project["Modules"]), "Runtime module missing"
    plugins = {p["Name"] for p in project["Plugins"] if p.get("Enabled")}
    assert {"ProceduralMeshComponent", "PythonScriptPlugin", "EditorScriptingUtilities"} <= plugins
    for relative in ("Source/SkyIslands.Target.cs", "Source/SkyIslandsEditor.Target.cs",
                     "Source/SkyIslandsServer.Target.cs", "Source/SkyIslands/SkyIslands.Build.cs",
                     "Tools/create_world.py", "Tools/build.py"):
        assert (ROOT / relative).is_file(), "Required file missing: " + relative
    for script in ROOT.rglob("*.py"):
        if any(x in script.parts for x in ("Intermediate", "Binaries", "Saved", "Artifacts")):
            continue
        ast.parse(script.read_text(encoding="utf-8"), filename=str(script))
    engine_config = (ROOT / "Config/DefaultEngine.ini").read_text(encoding="utf-8")
    assert "GameDefaultMap=/Game/Maps/SkyWorld" in engine_config
    assert "GlobalDefaultGameMode=/Script/SkyIslands.SkyGameMode" in engine_config
    assert "bRemoteExecution=False" in engine_config, "Remote Python execution must remain disabled"
    input_config = (ROOT / "Config/DefaultInput.ini").read_text(encoding="utf-8")
    for mapping in ("MoveForward", "MoveRight", "Turn", "LookUp", "Primary", "Secondary",
                    "Jump", "Interact", "Save", "Load", "Market", "Fastener", "Tool1", "Tool6"):
        assert 'Name="' + mapping + '"' in input_config, "Input mapping missing: " + mapping
    # Catch integration mistakes between new runtime bindings and input config.
    for cpp in (ROOT / "Source/SkyIslands").rglob("*.cpp"):
        text = cpp.read_text(encoding="utf-8")
        includes = re.findall(r'^\s*#include\s+[<"]([^>"]+)[>"]', text, re.MULTILINE)
        if (ROOT / "Source/SkyIslands/Public" / (cpp.stem + ".h")).exists() or (cpp.parent / (cpp.stem + ".h")).exists():
            assert includes and includes[0] == cpp.stem + ".h", "Matching header must be first for IWYU: " + str(cpp)
        for binding in re.findall(r'Bind(?:Axis|Action)\("([^\"]+)"', text):
            assert 'Name="' + binding + '"' in input_config, "Runtime binding missing from Config: " + binding
    for header in (ROOT / "Source/SkyIslands").rglob("*.h"):
        text = header.read_text(encoding="utf-8")
        if "UCLASS(" not in text and "USTRUCT(" not in text:
            continue
        includes = re.findall(r'^\s*#include\s+[<"]([^>"]+)[>"]', text, re.MULTILINE)
        assert includes and includes[-1] == header.stem + ".generated.h", "UHT include must be last: " + str(header)
    print("PORTABLE_SOURCE_CHECKS_OK (Unreal compilation still required)")


if __name__ == "__main__":
    validate()
