#!/usr/bin/env python3
"""Fetch pinned, openly licensed source art and bake animated crowd meshes."""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MODELS = 'https://raw.githubusercontent.com/agustindiazcano/zombie-horde-survivors/02f1a2502aed27e38f1c6f1305552d781873b700/public/models/'
ENV = 'https://raw.githubusercontent.com/cktang88/3d-fps/130ac2a5c856401ec36e7d35afcfefe40c5801f4/public/assets/'
TIDE = 'https://raw.githubusercontent.com/AetherRadar/operation-steel-tide/d6a33b932e00fb9016dea407eca3f909aeaf2dcb/assets/models/tide_hunter_monster/'
# Source, destination, expected SHA-256. Pinning protects builds from changed upstream files.
FILES = [
 (MODELS+'soldier-marine-light.glb','models/soldier-marine-light.glb','4d0a0a5a21ef989be55b5d5ea76915ee7a159dd0ba177d3db2556fb51aec9903'),
 (MODELS+'enemy-zombie.glb','models/enemy-zombie.glb','3afd2837b117f264afd037a350759b96d6f837fc9b381cca35cf6796b4bab09d'),
 (ENV+'models/props/concrete_road_barrier/concrete_road_barrier.glb','models/road_barrier.glb','e9cfeb1a2e7e6e78c2f2952b21f42dbffb81ca99b02690128344da750619cf6d'),
 (ENV+'ambience/models/burnt_car/burnt_car.glb','models/destroyed_car.glb','73d2a55f768d121f7c3111c618bf097b35e0dfb4d7aa947be28fe5baded60413'),
 (TIDE+'tide_hunter_monster.glb','models/tide/tide_hunter_monster.glb','449e20050bd46e7cd9ee53287b1e1f1b4ecc96d2dc0d16177afe3b350f3f61fb'),
 (ENV+'textures/Asphalt031/Color.webp','textures/Asphalt031/Color.webp','e453d290634f80505e3eb4f81ad5d16bea39fe0c780dda229a70444dd3e4a0bc'),
 (ENV+'textures/Asphalt031/NormalGL.webp','textures/Asphalt031/NormalGL.webp','34850c41d5bb10cb78117d18f04bf44d6b49620f6290c22e7951483e95338ddc'),
 (ENV+'textures/Asphalt031/Roughness.webp','textures/Asphalt031/Roughness.webp','bde4d81c6d0b777f1fc4791edead3b61670b2168f0408e3ef9adc5fedaff243f'),
 (ENV+'textures/Concrete034/Color.webp','textures/Concrete034/Color.webp','e625f68cf31147f58e884cd894fc25aa618e2f863889bb44290550865da579f4'),
 (ENV+'textures/Concrete034/NormalGL.webp','textures/Concrete034/NormalGL.webp','9000201a37d670de441cae0b5e21c1a432aac3d1abaa515da51007040ab3972c'),
 (ENV+'textures/Concrete034/Roughness.webp','textures/Concrete034/Roughness.webp','cdf3db7c67c8a4c34a7d068dc66f443e9c00ad00acbd0bb3d70fb020f860ce90'),
 (ENV+'textures/Metal046B/Color.webp','textures/Metal046B/Color.webp','b9ad28c578382e4e2a0c3a11c0b33b078507976bb7285bb32f21dd456e3be1e5'),
 (ENV+'textures/Metal046B/NormalGL.webp','textures/Metal046B/NormalGL.webp','319ea7fd8be666655ec9a574af24524ce99ac536438800470ef92d427428f8ad'),
 (ENV+'textures/Metal046B/Roughness.webp','textures/Metal046B/Roughness.webp','a8dacd34e0549fc013054d657d62041c7149cc899b2411e92ec87e5b091d11e1'),
 (ENV+'hdr/bambanani_sunset_2k.hdr','textures/sunset.hdr','63ece1716a4a6f598f243efa3484b2e47773e9add9cba6d1677a5ec4b2ee6ef8'),
]

def download(item):
    url, rel, expected = item
    dest = ROOT / 'assets' / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_file() and sha256(dest.read_bytes()).hexdigest() == expected:
        return rel + ' cached'
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'LegionRush-build/1.0'})
            with urllib.request.urlopen(req, timeout=90) as response:
                data = response.read()
            if sha256(data).hexdigest() != expected:
                raise ValueError('SHA-256 mismatch for ' + rel)
            dest.write_bytes(data)
            return rel + ' downloaded and verified'
        except Exception:
            if attempt == 3:
                raise
            time.sleep(attempt + 1)

with ThreadPoolExecutor(max_workers=5) as pool:
    for result in pool.map(download, FILES):
        print(result, flush=True)
bake = ROOT / 'tools' / 'bake_crowd_models.py'
for source, output, clip in [('soldier-marine-light.glb','marine_poses.glb','Running'),('enemy-zombie.glb','zombie_poses.glb','Run_Attack')]:
    subprocess.run([sys.executable, str(bake), str(ROOT/'assets/models'/source), str(ROOT/'assets/models'/output), '--clip', clip, '--poses', '6'], check=True)
