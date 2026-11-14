# Photoreal asset starter pack

This project has a real, downloaded CC0 starter pack, not just a list of sources.
The reproducible source files live under `ArtSource/PolyHaven/` and are excluded
from Git. `ArtSource/manifest.json` pins every delivered file by byte count and
SHA-256. Build preparation downloads and validates those exact bytes.

The pack uses 1K texture variants to keep the initial source bundle small. This
is an initial material/tool/nature library, not a claim that the cinematic
concept images have been rendered in Unreal or on Android.

## Reviewed sources

| Asset | Author(s) | Purpose | Source |
|---|---|---|---|
| Drill 01 | Fernando Quinn | Cordless drill visual | https://polyhaven.com/a/Drill_01 |
| Wooden Hammer 01 | James Ray Cock | Hammer visual | https://polyhaven.com/a/wooden_hammer_01 |
| Wood Planks | Amal Kumar | Weathered wood PBR surface | https://polyhaven.com/a/wood_planks |
| Brown Mud 03 | Rob Tuytel | Soil PBR surface | https://polyhaven.com/a/brown_mud_03 |
| Rock Boulder Cracked | Dario Barresi; Dimitrios Savva | Cliff/cave PBR surface | https://polyhaven.com/a/rock_boulder_cracked |
| Brick Wall 001 | Dimitrios Savva; Rob Tuytel | Assembled masonry PBR surface | https://polyhaven.com/a/brick_wall_001 |
| Boulder 01 | Rico Cilliers | Actual scanned rock mesh | https://polyhaven.com/a/boulder_01 |
| Pine Sapling Small | Rico Cilliers (model); Rob Tuytel (photography) | Actual pine sapling mesh, first source variant | https://polyhaven.com/a/pine_sapling_small |

All eight assets are identified as CC0 by their official pages and Poly Haven's
asset license: https://polyhaven.com/license . Credit is retained here for
traceability. Poly Haven assets are separate from Poly Haven logos, preview
renders, and website text; no website logos or preview renders are included.

Useful provider documentation:

- Asset license: https://polyhaven.com/license
- Public API: https://polyhaven.com/our-api
- CC0 reference: https://creativecommons.org/publicdomain/zero/1.0/

No Fab or Megascans assets are silently acquired by this script. Any future
addition from those catalogs needs its own verified download entitlement,
license record, source hash, and performance review. This pack does not assume
that an entire third-party catalog is free or freely redistributable.

## Source preparation

From `sky_islands`:

```sh
python Tools/fetch_assets.py
python Tools/fetch_assets.py --verify-only
```

The verifier checks reviewed download hosts, pack size, pinned byte counts,
SHA-256 hashes, local glTF dependencies and geometry buffer lengths. A mismatch
is a failure, not a reason to silently choose a different resolution or asset.
Only the standard Python library is needed. A single asset can be selected with
`--asset Drill_01` (repeat the flag to select several).

The pine source contains three separate sapling variants. The retained first
variant is extracted without changing its vertex/index data, normals, UVs,
material slots or textures. `ArtSource/extract_gltf.py` compacts only the used
buffer ranges and replaces the three-node scene with one local-space tree.
The manifest pins the original glTF and binary as upstream inputs and pins the
derived glTF/binary outputs. Downloads of upstream inputs are held temporarily;
the three-tree geometry is not included in the final source pack. This
extraction is reproducible through `Tools/fetch_assets.py`.

## Unreal import

Required editor plugins: Python Script Plugin, Editor Scripting Utilities and
Interchange Editor with the glTF translator. Run the project using Unreal 5.6:

```text
UnrealEditor-Cmd SkyIslands.uproject /Engine/Maps/Entry -run=pythonscript -script=Tools/import_assets.py -unattended -NullRHI
```

Use an absolute script path when invoking Unreal from another directory.
The importer uses blocking `AssetImportTask.get_objects()`, verifies each
returned asset type, creates/saves the PBR materials, preserves nature material
slots, and only then emits `SKY_ASSET_IMPORT_OK`. Missing imports, failed saves,
changed source metadata or unsuccessful nature LOD generation fail the step.
The receipt is written to `Saved/AssetImportReceipt.json` with actual imported
object paths. It is not checked into source control.

Canonical materials are generated under `/Game/SkyIslands/Art/<asset>/M_<asset>`.
Stable runtime aliases are:

| Runtime path | Source |
|---|---|
| `/Game/Art/Materials/M_Ground.M_Ground` | Brown Mud 03 PBR |
| `/Game/Art/Materials/M_Rock.M_Rock` | Rock Boulder Cracked PBR |
| `/Game/Art/Materials/M_Wood.M_Wood` | Wood Planks PBR |
| `/Game/Art/Materials/M_Brick.M_Brick` | Brick Wall 001 PBR |
| `/Game/Art/Materials/M_Metal.M_Metal` | Authored neutral metal material, not a downloaded scan |
| `/Game/Art/Tools/SM_Drill.SM_Drill` | Drill 01 mesh |
| `/Game/Art/Tools/SM_Hammer.SM_Hammer` | Wooden Hammer 01 mesh |
| `/Game/Art/Nature/SM_Rock.SM_Rock` | Boulder 01 mesh |
| `/Game/Art/Nature/SM_Tree.SM_Tree` | First Pine Sapling Small mesh variant |

Source nature materials are preserved: bark/needle material slots must not be
replaced with a generic wood material. For authored materials, diffuse maps
use sRGB; roughness/packed masks use linear sampling; standalone normals are
DirectX; the glTF tool normal textures have their green channel flipped when
converted into the authored Unreal material. Packed ARM is R=occlusion,
G=roughness, B=metallic.

The nature importer requests four conventional LODs at retained triangle ratios
1.0, 0.35, 0.10 and 0.025 and disables Nanite for this Android-oriented path.
The source sapling is approximately 122,235 triangles and the boulder is
66,122 triangles before Unreal reduction. Actual LOD generation, material
compilation, draw cost, collision and frame time must be checked on the target
Unreal installation and phone. No mobile frame-rate result is claimed here.

The generated namespaces are owned by this importer. Store hand-edited
materials elsewhere. Existing fixed mesh aliases are reused only when their
source hash metadata matches; a stale alias causes a clear failure rather than
silently replacing custom content.

## Gameplay boundaries

The drill mesh is one visual mesh; its presence does not implement bit motion,
screw attachment, battery use or damage. The hammer likewise does not include
hand animations. Those behaviors belong to game code and animation assets.

The brick-wall texture represents assembled masonry. Individual bricks still
need individual geometry, mortar placement and gameplay properties. Surface
normal/displacement detail does not create mineable material or excavated
caves. The procedural island implementation owns the actual terrain geometry.

The source set contains no character hands, guard rigs, drone animations,
finished houses or airship model. Those are further production tasks, not
implicitly supplied by this starter pack.
