"""Deterministically extract one mesh from an uncompressed, single-buffer glTF 2.

The geometry is copied byte-for-byte. This is a packaging operation, not mesh
simplification: material slots, textures and images are retained, while variant
placement transforms and other nodes are intentionally removed. Only material-
and texture-local extensions are supported. No third-party modules are needed.
"""
from __future__ import annotations

import copy
import json
import re
from typing import Any

_COMPONENT_BYTES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
_VECTOR_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
# These extensions introduce no node, accessor, or buffer references.
_SAFE_EXTENSIONS = {
    "KHR_texture_transform", "KHR_mesh_quantization", "KHR_materials_unlit",
    "KHR_materials_pbrSpecularGlossiness", "KHR_materials_clearcoat",
    "KHR_materials_transmission", "KHR_materials_volume", "KHR_materials_ior",
    "KHR_materials_specular", "KHR_materials_sheen", "KHR_materials_iridescence",
    "KHR_materials_anisotropy", "KHR_materials_emissive_strength",
    "KHR_materials_dispersion", "KHR_texture_basisu", "EXT_texture_webp",
    "EXT_texture_avif",
}


def _integer(value: Any, label: str, minimum: int = 0) -> int:
    if type(value) is not int or value < minimum:
        raise ValueError(f"{label} must be an integer >= {minimum}")
    return value


def _index(value: Any, items: list, label: str) -> int:
    value = _integer(value, label)
    if value >= len(items):
        raise ValueError(f"{label} is outside the source array")
    return value


def _element_bytes(accessor: dict) -> int:
    component_type = accessor.get("componentType")
    if component_type not in _COMPONENT_BYTES:
        raise ValueError("Unsupported accessor componentType")
    size = _COMPONENT_BYTES[component_type]
    kind = accessor.get("type")
    if kind in _VECTOR_COUNTS:
        return size * _VECTOR_COUNTS[kind]
    if kind in ("MAT2", "MAT3", "MAT4"):
        columns = int(kind[-1])
        return columns * ((columns * size + 3) // 4 * 4)
    raise ValueError("Unsupported accessor type")


def extract_mesh(
    gltf_bytes: bytes,
    buffer_bytes: bytes,
    mesh_index: int,
    output_bin_name: str,
) -> tuple[bytes, bytes]:
    """Return stable UTF-8 glTF JSON and a compact, four-byte-aligned BIN.

    Raises ValueError for unsupported/malformed input. No files or network
    requests are performed. Images stay external when they were external in the
    source; embedded image bufferViews are included and remapped.
    """
    if not isinstance(gltf_bytes, bytes) or not isinstance(buffer_bytes, bytes):
        raise ValueError("Input glTF and BIN must be bytes")
    if not isinstance(output_bin_name, str) or not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*\.bin", output_bin_name):
        raise ValueError("Output buffer name must be a relative .bin filename")
    try:
        source = json.loads(gltf_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("Invalid glTF JSON") from error
    if not isinstance(source, dict) or source.get("asset", {}).get("version") != "2.0":
        raise ValueError("Expected glTF 2.0")
    for field in ("animations", "skins", "cameras"):
        if source.get(field):
            raise ValueError(f"{field} need node remapping and are unsupported")
    for field in ("extensionsUsed", "extensionsRequired"):
        extensions = source.get(field, [])
        if not isinstance(extensions, list) or any(name not in _SAFE_EXTENSIONS for name in extensions):
            raise ValueError("Unsupported extension requiring extra reference remapping")
    if source.get("extensions"):
        raise ValueError("Top-level extension payloads are unsupported")

    buffers = source.get("buffers", [])
    if not isinstance(buffers, list) or len(buffers) != 1:
        raise ValueError("Exactly one source buffer is required")
    if buffers[0].get("extensions"):
        raise ValueError("Buffer extensions are unsupported")
    if _integer(buffers[0].get("byteLength"), "buffer.byteLength") != len(buffer_bytes):
        raise ValueError("Source BIN length does not match declared buffer byteLength")
    meshes = source.get("meshes", [])
    mesh_index = _index(mesh_index, meshes, "mesh_index")
    mesh = copy.deepcopy(meshes[mesh_index])
    if mesh.get("extensions"):
        raise ValueError("Mesh extensions are unsupported")
    primitives = mesh.get("primitives", [])
    if not isinstance(primitives, list) or not primitives:
        raise ValueError("Selected mesh has no primitives")
    accessors = source.get("accessors", [])
    views = source.get("bufferViews", [])
    if not isinstance(accessors, list) or not isinstance(views, list):
        raise ValueError("Invalid accessor or bufferView arrays")
    if any(accessor.get("sparse") is not None for accessor in accessors):
        raise ValueError("Sparse accessors are unsupported")

    accessor_ids: set[int] = set()
    for primitive in primitives:
        if primitive.get("extensions"):
            raise ValueError("Primitive extensions, including compression, are unsupported")
        attributes = primitive.get("attributes", {})
        if not isinstance(attributes, dict) or "POSITION" not in attributes:
            raise ValueError("Primitive must contain POSITION attributes")
        for index in attributes.values():
            accessor_ids.add(_index(index, accessors, "attribute accessor"))
        if "indices" in primitive:
            index = _index(primitive["indices"], accessors, "indices accessor")
            if accessors[index].get("type") != "SCALAR" or accessors[index].get("componentType") not in (5121, 5123, 5125):
                raise ValueError("Indices must use an unsigned SCALAR accessor")
            accessor_ids.add(index)
        for target in primitive.get("targets", []):
            if not isinstance(target, dict):
                raise ValueError("Invalid morph target")
            for index in target.values():
                accessor_ids.add(_index(index, accessors, "morph accessor"))
        if "material" in primitive:
            _index(primitive["material"], source.get("materials", []), "material index")

    view_ids: set[int] = set()
    for index in accessor_ids:
        accessor = accessors[index]
        if accessor.get("extensions"):
            raise ValueError("Accessor extensions are unsupported")
        element_size = _element_bytes(accessor)
        count = _integer(accessor.get("count"), "accessor.count", 1)
        offset = _integer(accessor.get("byteOffset", 0), "accessor.byteOffset")
        component_size = _COMPONENT_BYTES[accessor["componentType"]]
        if offset % component_size:
            raise ValueError("Accessor byteOffset is not component-aligned")
        if "bufferView" in accessor:
            view_id = _index(accessor["bufferView"], views, "accessor.bufferView")
            view = views[view_id]
            stride = _integer(view.get("byteStride", element_size), "bufferView.byteStride", element_size)
            if stride % component_size:
                raise ValueError("Accessor stride is not component-aligned")
            length = _integer(view.get("byteLength"), "bufferView.byteLength")
            if offset + (count - 1) * stride + element_size > length:
                raise ValueError("Accessor reads beyond its bufferView")
            view_ids.add(view_id)
        elif offset:
            raise ValueError("Accessor without bufferView cannot have nonzero byteOffset")
    for image in source.get("images", []):
        if "bufferView" in image:
            view_ids.add(_index(image["bufferView"], views, "image.bufferView"))

    new_bin = bytearray()
    new_views = []
    view_map = {}
    for index in sorted(view_ids):
        view = copy.deepcopy(views[index])
        if view.get("extensions"):
            raise ValueError("BufferView extensions, including compression, are unsupported")
        if view.get("buffer") != 0:
            raise ValueError("Referenced bufferView must use buffer 0")
        offset = _integer(view.get("byteOffset", 0), "bufferView.byteOffset")
        length = _integer(view.get("byteLength"), "bufferView.byteLength", 1)
        if offset + length > len(buffer_bytes):
            raise ValueError("BufferView extends past source buffer")
        while len(new_bin) % 4:
            new_bin.append(0)
        view["byteOffset"] = len(new_bin)
        view["buffer"] = 0
        new_bin.extend(buffer_bytes[offset:offset + length])
        view_map[index] = len(new_views)
        new_views.append(view)
    while len(new_bin) % 4:
        new_bin.append(0)

    new_accessors = []
    accessor_map = {}
    for index in sorted(accessor_ids):
        accessor = copy.deepcopy(accessors[index])
        if "bufferView" in accessor:
            accessor["bufferView"] = view_map[accessor["bufferView"]]
        accessor_map[index] = len(new_accessors)
        new_accessors.append(accessor)
    for primitive in primitives:
        primitive["attributes"] = {name: accessor_map[index] for name, index in primitive["attributes"].items()}
        if "indices" in primitive:
            primitive["indices"] = accessor_map[primitive["indices"]]
        for target in primitive.get("targets", []):
            for name, index in list(target.items()):
                target[name] = accessor_map[index]

    result = copy.deepcopy(source)
    result["meshes"] = [mesh]
    result["nodes"] = [{"mesh": 0, "name": mesh.get("name", f"Mesh_{mesh_index}")}]
    result["scenes"] = [{"nodes": [0]}]
    result["scene"] = 0
    result["accessors"] = new_accessors
    result["bufferViews"] = new_views
    result["buffers"] = [{"byteLength": len(new_bin), "uri": output_bin_name}]
    for image in result.get("images", []):
        if "bufferView" in image:
            image["bufferView"] = view_map[image["bufferView"]]
    return (json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8"), bytes(new_bin)
