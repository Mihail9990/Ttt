"""Run inside Unreal Editor 5.6 Python to import the reviewed CC0 starter pack.

UnrealEditor-Cmd SkyIslands.uproject /Engine/Maps/Entry -run=pythonscript
  -script=Tools/import_assets.py -unattended -NullRHI

Only the generated /Game/SkyIslands/Art and /Game/Art namespaces are managed.
The source downloader must have succeeded before this script is run.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

import unreal

ROOT = Path(unreal.Paths.project_dir()).resolve()
if not (ROOT / 'ArtSource' / 'manifest.json').is_file():
    ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'ArtSource'
TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
EAL = unreal.EditorAssetLibrary
MEL = unreal.MaterialEditingLibrary
BASE = '/Game/SkyIslands/Art'


def fail(message):
    raise RuntimeError('Sky Islands asset import: ' + message)


def save(asset):
    if not EAL.save_loaded_asset(asset, only_if_is_dirty=False):
        fail('Could not save ' + asset.get_path_name())


def verify_sources():
    spec = importlib.util.spec_from_file_location('sky_fetch_assets', ROOT / 'Tools' / 'fetch_assets.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if module.main(['--verify-only', '--manifest', str(SOURCE / 'manifest.json')]) != 0:
        fail('Pinned source files are missing or changed; run Tools/fetch_assets.py first')
    return module.load_manifest(SOURCE / 'manifest.json')


def import_file(filename, folder, name):
    EAL.make_directory(folder)
    task = unreal.AssetImportTask()
    task.set_editor_property('filename', str(filename))
    task.set_editor_property('destination_path', folder)
    task.set_editor_property('destination_name', name)
    task.set_editor_property('automated', True)
    task.set_editor_property('replace_existing', True)
    task.set_editor_property('save', True)
    task.set_editor_property('async_', False)
    TOOLS.import_asset_tasks([task])
    # UE 5.6 documents GetObjects as blocking even for an async importer.
    result = list(task.get_objects())
    if not result:
        result = [EAL.load_asset(path) for path in task.get_editor_property('imported_object_paths')]
    result = [obj for obj in result if obj is not None]
    if not result:
        fail('Importer produced no objects: ' + str(filename))
    return result


def import_texture(asset_id, entry):
    role = entry['role']
    folder = f'{BASE}/{asset_id}/Textures'
    name = f'T_{asset_id}_{role}'
    objects = import_file(SOURCE / entry['path'], folder, name)
    textures = [obj for obj in objects if isinstance(obj, unreal.Texture2D)]
    if len(textures) != 1:
        fail('Expected one texture for ' + entry['path'])
    tex = textures[0]
    tex.set_editor_property('srgb', role == 'base_color')
    if role in ('normal_gl', 'normal_dx'):
        tex.set_editor_property('compression_settings', unreal.TextureCompressionSettings.TC_NORMALMAP)
        tex.set_editor_property('flip_green_channel', role == 'normal_gl')
    # Keep the source resolution at 1K; higher-res source variants need a new
    # reviewed manifest and mobile performance checks, not an implicit upgrade.
    tex.set_editor_property('max_texture_size', 1024)
    save(tex)
    return tex


def new_material(folder, name):
    EAL.make_directory(folder)
    path = folder + '/' + name
    mat = EAL.load_asset(path)
    if mat is None:
        mat = TOOLS.create_asset(name, folder, unreal.Material, unreal.MaterialFactoryNew())
    if not isinstance(mat, unreal.Material):
        fail('Generated path is occupied by a non-material: ' + path)
    MEL.delete_all_material_expressions(mat)
    return mat


def connect(expression, output, prop):
    if not MEL.connect_material_property(expression, output, prop):
        fail('Could not connect material input ' + str(prop))


def texture_sample(mat, texture, role, y):
    node = MEL.create_material_expression(mat, unreal.MaterialExpressionTextureSample, -500, y)
    node.set_editor_property('texture', texture)
    if role in ('normal_gl', 'normal_dx'):
        sampler = unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL
    elif role == 'base_color':
        sampler = unreal.MaterialSamplerType.SAMPLERTYPE_COLOR
    else:
        sampler = unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR
    node.set_editor_property('sampler_type', sampler)
    return node


def scalar(mat, value, prop, y):
    node = MEL.create_material_expression(mat, unreal.MaterialExpressionConstant, -200, y)
    node.set_editor_property('r', value)
    connect(node, '', prop)


def material_for(asset, textures):
    mat = new_material(f"{BASE}/{asset['id']}", 'M_' + asset['id'])
    for index, (role, tex) in enumerate(textures.items()):
        node = texture_sample(mat, tex, role, index * 220)
        if role == 'base_color':
            connect(node, 'RGB', unreal.MaterialProperty.MP_BASE_COLOR)
        elif role in ('normal_dx', 'normal_gl'):
            connect(node, 'RGB', unreal.MaterialProperty.MP_NORMAL)
        elif role == 'roughness':
            connect(node, 'R', unreal.MaterialProperty.MP_ROUGHNESS)
        elif role == 'arm':
            connect(node, 'R', unreal.MaterialProperty.MP_AMBIENT_OCCLUSION)
            connect(node, 'G', unreal.MaterialProperty.MP_ROUGHNESS)
            connect(node, 'B', unreal.MaterialProperty.MP_METALLIC)
    if 'arm' not in textures:
        scalar(mat, 0.0, unreal.MaterialProperty.MP_METALLIC, 800)
    MEL.layout_material_expressions(mat)
    # Some UE versions return no value here, newer ones return compiler errors.
    errors = MEL.recompile_material(mat)
    if errors:
        fail('Material compile failed for ' + asset['id'] + ': ' + str(errors))
    save(mat)
    return mat


def alias_material(name, parent):
    folder = '/Game/Art/Materials'
    EAL.make_directory(folder)
    path = folder + '/' + name
    alias = EAL.load_asset(path)
    if alias is None:
        alias = TOOLS.create_asset(name, folder, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    if not isinstance(alias, unreal.MaterialInstanceConstant):
        fail('Generated alias is occupied by another asset type: ' + path)
    MEL.set_material_instance_parent(alias, parent)
    save(alias)
    return alias


def source_key(asset):
    values = '\n'.join(entry['path'] + ':' + entry['sha256'] for entry in asset['files'])
    return hashlib.sha256(values.encode('utf-8')).hexdigest()


def build_nature_lods(mesh):
    subsystem = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
    settings = [unreal.StaticMeshReductionSettings(percent_triangles=ratio, screen_size=size)
                for ratio, size in ((1.0, 1.0), (0.35, 0.5), (0.10, 0.2), (0.025, 0.06))]
    options = unreal.StaticMeshReductionOptions(auto_compute_lod_screen_size=False, reduction_settings=settings)
    generated = subsystem.set_lods(mesh, options)
    if generated < 0 or subsystem.get_lod_count(mesh) != 4:
        fail('Four nature LODs could not be generated for ' + mesh.get_path_name())
    # No Nanite dependency in the Android path; use the explicit conventional LODs.
    nanite = subsystem.get_nanite_settings(mesh)
    nanite.set_editor_property('enabled', False)
    subsystem.set_nanite_settings(mesh, nanite, apply_changes=True)
    body_setup = mesh.get_editor_property('body_setup')
    if body_setup is None:
        fail('Imported nature mesh has no collision body setup: ' + mesh.get_path_name())
    # Static nature props need precise harvesting traces. They are not physics-simulated.
    body_setup.set_editor_property('collision_trace_flag', unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)


def mesh_for(asset, material=None):
    alias_path = asset['mesh_alias']
    key = source_key(asset)
    mesh = EAL.load_asset(alias_path)
    if mesh is not None:
        if not isinstance(mesh, unreal.StaticMesh):
            fail('Mesh alias is occupied by another asset type: ' + alias_path)
        if EAL.get_metadata_tag(mesh, 'SkySourceSHA256') != key:
            fail('Mesh alias has unreviewed or changed source metadata; rebuild this generated alias in the editor: ' + alias_path)
    else:
        objects = import_file(SOURCE / asset['entry'], f"{BASE}/{asset['id']}/Model", 'SM_' + asset['id'])
        meshes = [obj for obj in objects if isinstance(obj, unreal.StaticMesh)]
        if len(meshes) != 1:
            fail('Expected exactly one mesh in reviewed tool model ' + asset['id'])
        mesh = meshes[0]
        EAL.make_directory(alias_path.rsplit('/', 1)[0])
        if not EAL.rename_asset(mesh.get_path_name(), alias_path):
            fail('Could not assign stable mesh alias ' + alias_path)
        mesh = EAL.load_asset(alias_path)
        EAL.set_metadata_tag(mesh, 'SkySourceSHA256', key)
    if material is not None:
        mesh.set_material(0, material)
    if asset.get('material_mode') == 'source':
        build_nature_lods(mesh)
    save(mesh)
    return mesh


def metal_material():
    mat = new_material(BASE + '/Fallback', 'M_MetalBase')
    color = MEL.create_material_expression(mat, unreal.MaterialExpressionConstant3Vector, -300, 0)
    color.set_editor_property('constant', unreal.LinearColor(0.32, 0.35, 0.38, 1.0))
    connect(color, '', unreal.MaterialProperty.MP_BASE_COLOR)
    scalar(mat, 1.0, unreal.MaterialProperty.MP_METALLIC, 200)
    scalar(mat, 0.32, unreal.MaterialProperty.MP_ROUGHNESS, 400)
    errors = MEL.recompile_material(mat)
    if errors:
        fail('Fallback metal material failed to compile: ' + str(errors))
    save(mat)
    return alias_material('M_Metal', mat)


def main():
    manifest = verify_sources()
    receipt = {'schema_version': 1, 'source': 'Poly Haven CC0 starter pack', 'materials': {}, 'meshes': {}}
    for asset in manifest['assets']:
        if asset.get('material_mode') == 'source':
            mesh = mesh_for(asset)
            receipt['meshes'][asset['id']] = mesh.get_path_name()
            continue
        textures = {}
        for entry in asset['files']:
            if entry['role'] in ('base_color', 'normal_gl', 'normal_dx', 'arm', 'roughness'):
                textures[entry['role']] = import_texture(asset['id'], entry)
        if not textures.get('base_color') or not (textures.get('normal_gl') or textures.get('normal_dx')):
            fail('Incomplete PBR inputs for ' + asset['id'])
        mat = material_for(asset, textures)
        receipt['materials'][asset['id']] = mat.get_path_name()
        if asset['kind'] == 'material':
            alias = alias_material(asset['alias'], mat)
            receipt['materials'][asset['alias']] = alias.get_path_name()
        elif asset['kind'] == 'model':
            mesh = mesh_for(asset, mat)
            receipt['meshes'][asset['id']] = mesh.get_path_name()
    metal = metal_material()
    receipt['materials']['M_Metal'] = metal.get_path_name()
    saved = ROOT / 'Saved' / 'AssetImportReceipt.json'
    saved.parent.mkdir(parents=True, exist_ok=True)
    saved.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    unreal.log('SKY_ASSET_IMPORT_OK ' + json.dumps(receipt, sort_keys=True))


if __name__ == '__main__':
    main()
