#!/usr/bin/env python3
"""Fetch or verify the pinned, redistributable Poly Haven starter assets.

Uses only Python's standard library. This downloader does not access Fab,
Megascans, accounts, EULAs or payment endpoints.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import sys
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MAX_PACK_BYTES = 30 * 1024 * 1024
MAX_FILE_BYTES = 20 * 1024 * 1024


def safe_path(root: Path, value: str) -> Path:
    rel = PurePosixPath(value)
    if not value or rel.is_absolute() or '..' in rel.parts or '\\' in value:
        raise ValueError('Unsafe asset path: ' + value)
    path = (root / Path(*rel.parts)).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Asset path escapes source root: ' + value)
    return path


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def load_manifest(path: Path) -> dict:
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema_version') != 1:
        raise ValueError('Unsupported asset manifest schema')
    entries = [file for asset in data['assets'] for file in asset['files']]
    if sum(file['bytes'] for file in entries) > MAX_PACK_BYTES:
        raise ValueError('Asset pack exceeds the reviewed 30 MiB budget')
    paths = set()
    for asset in data['assets']:
        if asset.get('license') != 'CC0-1.0':
            raise ValueError('Unreviewed asset license: ' + asset['id'])
        for file in asset['files']:
            safe_path(path.parent, file['path'])
            if file['path'] in paths:
                raise ValueError('Duplicate file path: ' + file['path'])
            paths.add(file['path'])
            if file.get('generated'):
                if asset.get('upstream', {}).get('derivation') != 'gltf_mesh_variant':
                    raise ValueError('Unreviewed asset derivation: ' + asset['id'])
            else:
                url = urllib.parse.urlsplit(file['url'])
                if url.scheme != 'https' or url.hostname != 'dl.polyhaven.org':
                    raise ValueError('Unreviewed download host: ' + file['url'])
            if not 0 < file['bytes'] <= MAX_FILE_BYTES:
                raise ValueError('Invalid reviewed file size')
            if len(file['sha256']) != 64 or any(c not in '0123456789abcdef' for c in file['sha256']):
                raise ValueError('Missing or malformed pinned SHA-256')
        if asset.get('upstream'):
            for kind in ('gltf', 'buffer'):
                entry = asset['upstream'][kind]
                url = urllib.parse.urlsplit(entry['url'])
                if url.scheme != 'https' or url.hostname != 'dl.polyhaven.org':
                    raise ValueError('Unreviewed upstream URL')
                if not 0 < entry['bytes'] <= MAX_FILE_BYTES or len(entry['sha256']) != 64:
                    raise ValueError('Unreviewed upstream length or hash')
    return data


def matches(path: Path, entry: dict) -> bool:
    return path.is_file() and path.stat().st_size == entry['bytes'] and digest(path) == entry['sha256']


def fetch(root: Path, entry: dict) -> None:
    path = safe_path(root, entry['path'])
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + '.part')
    request = urllib.request.Request(entry['url'], headers={'User-Agent': 'SkyIslandsAssetFetcher/0.1 (Poly Haven CC0 assets)'})
    try:
        with urllib.request.urlopen(request, timeout=60) as response, partial.open('wb') as output:
            if urllib.parse.urlsplit(response.url).hostname != 'dl.polyhaven.org':
                raise ValueError('Download redirected to an unreviewed host')
            total = 0
            while True:
                chunk = response.read(256 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > entry['bytes']:
                    raise ValueError('Download exceeds pinned byte count: ' + entry['path'])
                output.write(chunk)
        if not matches(partial, entry):
            raise ValueError('Download size/hash mismatch: ' + entry['path'])
        os.replace(partial, path)
    finally:
        partial.unlink(missing_ok=True)


def derive_asset(root: Path, asset: dict) -> None:
    """Select one source tree variant; preserve its exact vertex/index bytes."""
    inputs = {}
    for kind in ('gltf', 'buffer'):
        entry = asset['upstream'][kind]
        request = urllib.request.Request(entry['url'], headers={'User-Agent': 'SkyIslandsAssetFetcher/0.1'})
        with urllib.request.urlopen(request, timeout=90) as response:
            if urllib.parse.urlsplit(response.url).hostname != 'dl.polyhaven.org':
                raise ValueError('Upstream redirected to an unreviewed host')
            data = response.read(entry['bytes'] + 1)
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Upstream size/hash mismatch for ' + asset['id'])
        inputs[kind] = data
    spec = importlib.util.spec_from_file_location('sky_extract_gltf', root / 'extract_gltf.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    generated = {entry['role']: entry for entry in asset['files'] if entry.get('generated')}
    gltf, binary = module.extract_mesh(inputs['gltf'], inputs['buffer'], asset['upstream']['mesh_index'],
                                       Path(generated['buffer']['path']).name)
    for role, data in (('gltf', gltf), ('buffer', binary)):
        entry = generated[role]
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Derived asset is not reproducible: ' + asset['id'])
        path = safe_path(root, entry['path'])
        path.parent.mkdir(parents=True, exist_ok=True)
        partial = path.with_name(path.name + '.part')
        partial.write_bytes(data)
        os.replace(partial, path)


def verify_gltf(root: Path, assets: list) -> None:
    for asset in assets:
        if asset['kind'] != 'model':
            continue
        path = safe_path(root, asset['entry'])
        data = json.loads(path.read_text(encoding='utf-8'))
        files = {safe_path(root, item['path']) for item in asset['files']}
        for item in data.get('buffers', []) + data.get('images', []):
            uri = item.get('uri', '')
            if not uri or urllib.parse.urlsplit(uri).scheme or '..' in PurePosixPath(uri).parts:
                raise ValueError('Unreviewed glTF dependency: ' + uri)
            target = (path.parent / uri).resolve()
            if target not in files or not target.is_file():
                raise ValueError('Missing glTF dependency: ' + str(target))
        for buffer in data.get('buffers', []):
            target = (path.parent / buffer['uri']).resolve()
            if target.stat().st_size != buffer['byteLength']:
                raise ValueError('glTF buffer length mismatch: ' + str(target))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'ArtSource' / 'manifest.json')
    parser.add_argument('--verify-only', action='store_true', help='Do not access the network; fail on missing or altered bytes')
    parser.add_argument('--asset', action='append', dest='ids', help='Select an asset ID; may be repeated')
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.manifest.resolve())
        assets = manifest['assets']
        if args.ids:
            known = {asset['id'] for asset in assets}
            unknown = set(args.ids) - known
            if unknown:
                raise ValueError('Unknown asset IDs: ' + ', '.join(sorted(unknown)))
            assets = [asset for asset in assets if asset['id'] in args.ids]
        root = args.manifest.resolve().parent
        total_files = 0
        total_bytes = 0
        for asset in assets:
            if not args.verify_only and any(entry.get('generated') and not matches(safe_path(root, entry['path']), entry) for entry in asset['files']):
                print('Deriving reviewed source variant', asset['id'], flush=True)
                derive_asset(root, asset)
            for entry in asset['files']:
                path = safe_path(root, entry['path'])
                if not matches(path, entry):
                    if args.verify_only:
                        raise ValueError('Missing or changed asset: ' + entry['path'])
                    print('Downloading', entry['path'], flush=True)
                    fetch(root, entry)
                total_files += 1
                total_bytes += entry['bytes']
        verify_gltf(root, assets)
        print(f'SKY_ASSET_SOURCES_OK assets={len(assets)} files={total_files} bytes={total_bytes}')
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('Asset preparation failed:', error, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
