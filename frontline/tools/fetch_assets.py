#!/usr/bin/env python3
"""Fetch explicitly credited art assets for the FRONTLINE Android build.

Upstream CC0/CC BY materials are pinned to a single Git commit to avoid
silently changing the models at future CI builds.
"""
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import quote
import hashlib
import time

UPSTREAM_REV = "130ac2a5c856401ec36e7d35afcfefe40c5801f4"
ROOT = Path(__file__).resolve().parents[1] / "assets"
BASE = f"https://raw.githubusercontent.com/cktang88/3d-fps/{UPSTREAM_REV}/"
ASSETS = [
    ["public/assets/models/fp/m4a1.glb", "models/first_person_m4a1.glb",1497044],
    ["public/assets/models/fp/arms_basecolor.webp", "models/arms_basecolor.webp",136406],
    ["public/assets/models/fp/arms_normal.webp", "models/arms_normal.webp",278326],
    ["public/assets/models/characters/soldier_tac.glb", "models/soldier_tactical.glb",4532132],
    ["public/assets/models/props/old_military_crate/old_military_crate.glb", "models/crate.glb",375004],
    ["public/assets/models/props/concrete_road_barrier/concrete_road_barrier.glb", "models/road_barrier.glb",447480],
    ["public/assets/models/props/Barrel_01/Barrel_01.glb", "models/barrel.glb",378644],
    ["public/assets/models/props/street_lamp_01/street_lamp_01.glb", "models/street_lamp.glb",261532],
    ["public/assets/models/props/ammo_box/ammo_box.glb", "models/ammo_box.glb",154940],
    ["public/assets/models/props/portable_generator/portable_generator.glb", "models/generator.glb",654252],
    ["public/assets/ambience/models/burnt_car/burnt_car.glb", "models/destroyed_car.glb",2605856],
    ["public/assets/ambience/models/uh60/uh60.glb", "models/helicopter.glb",3245704],
    ["public/assets/hdr/bambanani_sunset_2k.hdr", "textures/sunset.hdr",6490374],
    ["public/assets/textures/Asphalt031/Color.webp", "textures/Asphalt031/Color.webp",1630170],
    ["public/assets/textures/Asphalt031/NormalGL.webp", "textures/Asphalt031/NormalGL.webp",1765202],
    ["public/assets/textures/Asphalt031/Roughness.webp", "textures/Asphalt031/Roughness.webp",432128],
    ["public/assets/textures/Bricks097/Color.webp", "textures/Bricks097/Color.webp",654112],
    ["public/assets/textures/Bricks097/NormalGL.webp", "textures/Bricks097/NormalGL.webp",616596],
    ["public/assets/textures/Bricks097/Roughness.webp", "textures/Bricks097/Roughness.webp",167388],
    ["public/assets/textures/Concrete034/Color.webp", "textures/Concrete034/Color.webp",49028],
    ["public/assets/textures/Concrete034/NormalGL.webp", "textures/Concrete034/NormalGL.webp",112146],
    ["public/assets/textures/Concrete034/Roughness.webp", "textures/Concrete034/Roughness.webp",32162],
    ["public/assets/textures/Ground110/Color.webp", "textures/Ground110/Color.webp",1477038],
    ["public/assets/textures/Ground110/NormalGL.webp", "textures/Ground110/NormalGL.webp",1879782],
    ["public/assets/textures/Ground110/Roughness.webp", "textures/Ground110/Roughness.webp",355530],
    ["public/assets/textures/Metal046B/Color.webp", "textures/Metal046B/Color.webp",167772],
    ["public/assets/textures/Metal046B/NormalGL.webp", "textures/Metal046B/NormalGL.webp",93526],
    ["public/assets/textures/Metal046B/Roughness.webp", "textures/Metal046B/Roughness.webp",89326],
    ["public/assets/textures/PavingStones138/Color.webp", "textures/PavingStones138/Color.webp",180828],
    ["public/assets/textures/PavingStones138/NormalGL.webp", "textures/PavingStones138/NormalGL.webp",115180],
    ["public/assets/textures/PavingStones138/Roughness.webp", "textures/PavingStones138/Roughness.webp",59238]
]  # (source, destination, expected size)

def main():
    print(f"Fetching {len(ASSETS)} licensed 3D/PBR resources pinned at {UPSTREAM_REV[:12]}")
    for source, dest, expected_size in ASSETS:
        path = ROOT / dest
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.is_file() and path.stat().st_size == expected_size:
            print(f"[cached] {dest}")
            continue
        # Encode whitespace and unicode when needed.
        url = BASE + quote(source, safe="/")
        for attempt in range(3):
            try:
                with urlopen(Request(url, headers={"User-Agent": "FRONTLINE-Godot-Android-CI/1.0"}), timeout=120) as stream:
                    data = stream.read()
                if len(data) != expected_size:
                    raise RuntimeError(f"{source}: got {len(data)} bytes, expected {expected_size}")
                path.write_bytes(data)
                print(f"[asset] {dest}: {len(data):,} bytes / sha256={hashlib.sha256(data).hexdigest()[:12]}")
                break
            except Exception as exc:
                if attempt == 2:
                    raise RuntimeError(f"Could not download {source}: {exc}") from exc
                time.sleep(attempt + 1)
    print("ASSET_FETCH_OK")

if __name__ == "__main__":
    main()
