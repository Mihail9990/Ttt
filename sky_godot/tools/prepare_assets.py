#!/usr/bin/env python3
"""Stage the reviewed CC0 source pack for Godot, verifying every upstream byte.

No engine account or online marketplace is used. Existing verified downloads are
reused; missing ones are fetched by the UE project's reviewed Poly Haven fetcher.
Requires Pillow only for converting four DirectX normal maps to Godot/OpenGL Y.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PROJECT = ROOT.parent / 'sky_islands'
SOURCE_ROOT = SOURCE_PROJECT / 'ArtSource'
SOURCE_MANIFEST = SOURCE_ROOT / 'manifest.json'
DEST = ROOT / 'assets'
RECEIPT = DEST / 'receipt.json'
SCHEMA = 1
SURFACES = {
    'wood_planks': 'wood', 'brown_mud_03': 'ground',
    'rock_boulder_cracked': 'rock', 'brick_wall_001': 'brick',
}
MODELS = {
    'Drill_01': 'drill', 'wooden_hammer_01': 'hammer',
    'boulder_01': 'rock', 'pine_sapling_small': 'tree',
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_under(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Path escapes reviewed asset root: ' + relative)
    return path


def source_check(verify_only: bool) -> dict:
    command = [sys.executable, str(SOURCE_PROJECT / 'Tools/fetch_assets.py')]
    if verify_only:
        command.append('--verify-only')
    subprocess.run(command, cwd=ROOT.parent, check=True)
    data = json.loads(SOURCE_MANIFEST.read_text(encoding='utf-8'))
    if data.get('schema_version') != 1:
        raise ValueError('Unsupported source manifest')
    expected = set(SURFACES) | set(MODELS)
    if {a['id'] for a in data['assets']} != expected:
        raise ValueError('Source pack changed; review the Godot asset selection first')
    for asset in data['assets']:
        if asset.get('license') != 'CC0-1.0':
            raise ValueError('Unreviewed license: ' + asset['id'])
        for entry in asset['files']:
            p = safe_under(SOURCE_ROOT, entry['path'])
            if p.stat().st_size != entry['bytes'] or sha(p) != entry['sha256']:
                raise ValueError('Source size/hash mismatch: ' + entry['path'])
    return data


def convert_normal(source: Path, target: Path) -> None:
    # PBR normals from the texture packs use DirectX convention. Inverting only
    # green changes the tangent-space Y sign without altering X/Z or roughness.
    try:
        from PIL import Image, ImageOps
    except ImportError as exc:
        raise SystemExit('Pillow is required: python -m pip install Pillow') from exc
    with Image.open(source) as im:
        red, green, blue = im.convert('RGB').split()
        converted = Image.merge('RGB', (red, ImageOps.invert(green), blue))
        converted.save(target, format='PNG', optimize=False, compress_level=9)


def record(path: Path, upstream_sha: str, records: list[dict]) -> None:
    records.append({
        'path': path.relative_to(DEST).as_posix(),
        'bytes': path.stat().st_size,
        'sha256': sha(path),
        'source_sha256': upstream_sha,
    })


def stage(data: dict) -> dict:
    records: list[dict] = []
    models: dict[str, str] = {}
    materials: dict[str, dict[str, str]] = {}
    for asset in data['assets']:
        aid = asset['id']
        if aid in MODELS:
            folder = DEST / 'models' / aid
            folder.mkdir(parents=True, exist_ok=True)
            original_folder = safe_under(SOURCE_ROOT, asset['entry']).parent
            for entry in asset['files']:
                source = safe_under(SOURCE_ROOT, entry['path'])
                relative = source.relative_to(original_folder)
                target = safe_under(folder, relative.as_posix())
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                record(target, entry['sha256'], records)
            entry_path = folder / Path(asset['entry']).name
            models[MODELS[aid]] = 'res://' + entry_path.relative_to(ROOT).as_posix()
        else:
            kind = SURFACES[aid]
            folder = DEST / 'materials' / kind
            folder.mkdir(parents=True, exist_ok=True)
            textures: dict[str, str] = {}
            for entry in asset['files']:
                source = safe_under(SOURCE_ROOT, entry['path'])
                role = entry['role']
                if role == 'normal_dx':
                    target = folder / 'normal_gl.png'
                    convert_normal(source, target)
                    textures['normal'] = 'res://' + target.relative_to(ROOT).as_posix()
                else:
                    target = folder / (role + source.suffix.lower())
                    shutil.copyfile(source, target)
                    textures[role] = 'res://' + target.relative_to(ROOT).as_posix()
                record(target, entry['sha256'], records)
            materials[kind] = textures
    receipt = {
        'schema_version': SCHEMA,
        'source_manifest_sha256': sha(SOURCE_MANIFEST),
        'source_license': 'CC0-1.0',
        'normal_conversion': 'DirectX to OpenGL: RGB, green = 255 - green',
        'models': models, 'materials': materials,
        'files': sorted(records, key=lambda x: x['path']),
    }
    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    RECEIPT.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return receipt


def verify() -> dict:
    source_check(True)
    if not RECEIPT.is_file():
        raise ValueError('Staged assets are missing: run tools/prepare_assets.py')
    data = json.loads(RECEIPT.read_text(encoding='utf-8'))
    if data.get('schema_version') != SCHEMA or data.get('source_manifest_sha256') != sha(SOURCE_MANIFEST):
        raise ValueError('Asset receipt/source manifest mismatch')
    for entry in data['files']:
        p = safe_under(DEST, entry['path'])
        if not p.is_file() or p.stat().st_size != entry['bytes'] or sha(p) != entry['sha256']:
            raise ValueError('Staged asset size/hash mismatch: ' + entry['path'])
    return data


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args(argv)
    try:
        data = verify() if args.verify_only else stage(source_check(False))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        print('Asset preparation failed: ' + str(exc), file=sys.stderr)
        return 1
    print('GODOT_ASSETS_OK models={} materials={} files={} bytes={}'.format(
        len(data['models']), len(data['materials']), len(data['files']),
        sum(x['bytes'] for x in data['files'])))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
