class_name SkyIsland
extends Node3D
## Smooth, closed 3D scalar-field island. All dimensions are metres (Godot Y-up).
## Mesh/collision are derived locally; saves/net snapshots carry only seed + stamps.
## The authority owning this node must validate reach/tool/ownership before excavating.

const MAX_STAMPS: int = 128
const MIN_DIG_RADIUS: float = 0.8
const MAX_DIG_RADIUS: float = 2.6
const CORNERS: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1)]
const TETS: Array = [[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
	[0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6]]

var seed: int = 41
var radius: float = 24.0
var stamps: Array = []
var last_removed_volume: float = 0.0
var mesh_instance: MeshInstance3D
var body: StaticBody3D
var collision: CollisionShape3D
var last_rebuild_ms: int = 0
var triangle_count: int = 0

var _ground_material: Material
var _rock_material: Material
var _cell: float = 1.5
var _low: Vector3
var _nx: int
var _ny: int
var _nz: int
var _sx: int
var _sy: int
var _plane: int
var _point_count: int
var _values := PackedFloat64Array()
var _gradient_cache := PackedVector3Array()
var _gradient_known := PackedByteArray()
var _edge_cache: Dictionary = {}
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uv := PackedVector2Array()
var _ground_indices := PackedInt32Array()
var _rock_indices := PackedInt32Array()

func _ready() -> void:
	_ensure_nodes()

func configure(new_seed: int, new_radius: float) -> void:
	seed = clampi(new_seed, 0, 1000000)
	radius = clampf(new_radius, 5.0, 60.0) if is_finite(new_radius) else 24.0
	stamps.clear()
	last_removed_volume = 0.0
	_ensure_nodes()
	_reset_grid()
	_rebuild_geometry()

func set_surface_materials(ground: Material, rock: Material) -> void:
	_ground_material = ground
	_rock_material = rock
	_apply_materials()

func density(world_point: Vector3) -> float:
	if not world_point.is_finite():
		return -INF
	return _density_local(_local_point(world_point))

func material_at(world_point: Vector3) -> String:
	if not world_point.is_finite():
		return "stone"
	return _material_local(_local_point(world_point))

func top_height(local_x: float, local_z: float) -> float:
	var a: float = float(seed % 997) * 0.137
	return 0.42 * sin(local_x * 0.135 + a) * cos(local_z * 0.115 - a) + 0.19 * sin((local_x + local_z) * 0.21 + a * 0.37)

func excavate(world_point: Vector3, dig_radius: float = 1.25) -> float:
	last_removed_volume = 0.0
	if not world_point.is_finite() or stamps.size() >= MAX_STAMPS:
		return 0.0
	var center: Vector3 = _local_point(world_point)
	if not _valid_stamp(center, dig_radius):
		return 0.0
	for old in stamps:
		if center.distance_squared_to(old["center"]) < 0.00000001 and absf(dig_radius - float(old["radius"])) < 0.000001:
			return 0.0
	# Deterministic volume quadrature: only previously solid samples award resources.
	# Mesh samples and excavation samples are independent to avoid granting mesh-cell air.
	const N: int = 12
	var step: float = 2.0 * dig_radius / float(N)
	var count: int = 0
	for z in range(N):
		for y in range(N):
			for x in range(N):
				var offset := Vector3(-dig_radius + (float(x) + 0.5) * step,
					-dig_radius + (float(y) + 0.5) * step, -dig_radius + (float(z) + 0.5) * step)
				if offset.length_squared() < dig_radius * dig_radius and _density_local(center + offset) > 0.000001:
					count += 1
	last_removed_volume = float(count) * step * step * step
	if last_removed_volume <= 0.0:
		return 0.0
	stamps.append({"center": center, "radius": dig_radius})
	# Only field grid points touched by this stamp are updated; old stamps are not
	# re-evaluated for every mesh vertex on every dig.
	if _values.is_empty():
		_ensure_nodes()
		_reset_grid()
	else:
		_apply_stamp_grid(center, dig_radius)
	_rebuild_geometry()
	return last_removed_volume

func get_stamps() -> Array:
	var result: Array = []
	for stamp in stamps:
		var center: Vector3 = stamp["center"]
		result.append({"center": [center.x, center.y, center.z], "radius": float(stamp["radius"])})
	return result

func restore_stamps(data: Array) -> bool:
	if data.size() > MAX_STAMPS:
		return false
	var checked: Array = []
	for value in data:
		if not value is Dictionary or not value.has("center") or not value.has("radius"):
			return false
		var raw_center: Variant = value["center"]
		if not raw_center is Array or raw_center.size() != 3 or not _number(value["radius"]):
			return false
		for coordinate in raw_center:
			if not _number(coordinate):
				return false
		var center := Vector3(float(raw_center[0]), float(raw_center[1]), float(raw_center[2]))
		var dig_radius: float = float(value["radius"])
		if not _valid_stamp(center, dig_radius):
			return false
		checked.append({"center": center, "radius": dig_radius})
	# Full validation precedes replacing the current field: corrupt saves cannot
	# silently restore inventory while leaving an undug island behind.
	stamps = checked
	last_removed_volume = 0.0
	_ensure_nodes()
	_reset_grid()
	_rebuild_geometry()
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _local_point(world_point: Vector3) -> Vector3:
	return global_transform.affine_inverse() * world_point if is_inside_tree() else transform.affine_inverse() * world_point

func _base_density(p: Vector3) -> float:
	if not p.is_finite():
		return -INF
	var radial: float = Vector2(p.x, p.z).length()
	var theta: float = atan2(p.z, p.x)
	var a: float = float(seed % 997) * 0.137
	var limit: float = radius * (1.0 + 0.045 * sin(theta * 3.0 + a) + 0.025 * sin(theta * 7.0 - a))
	var q: float = radial / limit
	var bottom: float = -radius * 0.75 * pow(maxf(0.0, 1.0 - q * q), 0.55) - 0.7
	return minf(minf(top_height(p.x, p.z) - p.y, p.y - bottom), limit - radial)

func _density_local(p: Vector3) -> float:
	var d: float = _base_density(p)
	for stamp in stamps:
		d = minf(d, p.distance_to(stamp["center"]) - float(stamp["radius"]))
	return d

func _material_local(p: Vector3) -> String:
	var depth: float = top_height(p.x, p.z) - p.y
	if depth < 1.3:
		return "soil"
	if depth < 3.3:
		return "clay"
	var vein: float = sin(p.x * 0.8 + float(seed)) * cos(p.z * 0.9) + sin(p.y * 1.2)
	return "ore" if depth > 5.5 and vein > 1.25 else "stone"

func _valid_stamp(center: Vector3, dig_radius: float) -> bool:
	return center.is_finite() and is_finite(dig_radius) and dig_radius >= MIN_DIG_RADIUS and dig_radius <= MAX_DIG_RADIUS \
		and absf(center.x) <= radius * 1.2 + MAX_DIG_RADIUS and absf(center.z) <= radius * 1.2 + MAX_DIG_RADIUS \
		and center.y >= -radius * 0.9 - MAX_DIG_RADIUS and center.y <= 5.0

func _ensure_nodes() -> void:
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "TerrainMesh"
		add_child(mesh_instance)
	if body == null:
		body = StaticBody3D.new()
		body.name = "TerrainBody"
		body.set_meta("island", self)
		body.collision_layer = 1
		body.collision_mask = 1
		add_child(body)
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "TerrainCollision"
		body.add_child(collision)

func _reset_grid() -> void:
	_cell = maxf(1.5, radius / 18.0)
	_low = Vector3(-radius * 1.1 - _cell, -radius * 0.8 - 1.2 - _cell, -radius * 1.1 - _cell)
	var high := Vector3(radius * 1.1 + _cell, 1.5 + _cell, radius * 1.1 + _cell)
	_nx = int(ceil((high.x - _low.x) / _cell))
	_ny = int(ceil((high.y - _low.y) / _cell))
	_nz = int(ceil((high.z - _low.z) / _cell))
	_sx = _nx + 1
	_sy = _ny + 1
	_plane = _sx * _sy
	_point_count = _plane * (_nz + 1)
	_values.resize(_point_count)
	_gradient_cache.resize(_point_count)
	_gradient_known.resize(_point_count)
	_gradient_known.fill(0)
	for z in range(_nz + 1):
		for y in range(_ny + 1):
			for x in range(_nx + 1):
				_values[_index(x, y, z)] = _base_density(_point(x, y, z))
	for stamp in stamps:
		_apply_stamp_grid(stamp["center"], float(stamp["radius"]))

func _index(x: int, y: int, z: int) -> int:
	return z * _plane + y * _sx + x

func _point(x: int, y: int, z: int) -> Vector3:
	return _low + Vector3(float(x), float(y), float(z)) * _cell

func _apply_stamp_grid(center: Vector3, dig_radius: float) -> void:
	var lo: Vector3i = Vector3i(((center - Vector3.ONE * dig_radius - _low) / _cell).floor())
	var hi: Vector3i = Vector3i(((center + Vector3.ONE * dig_radius - _low) / _cell).ceil())
	for z in range(maxi(0, lo.z), mini(_nz, hi.z) + 1):
		for y in range(maxi(0, lo.y), mini(_ny, hi.y) + 1):
			for x in range(maxi(0, lo.x), mini(_nx, hi.x) + 1):
				var i: int = _index(x, y, z)
				_values[i] = minf(_values[i], _point(x, y, z).distance_to(center) - dig_radius)
	# Gradient entries sample neighboring grid points. Small padded dirty region.
	for z in range(maxi(0, lo.z - 1), mini(_nz, hi.z + 1) + 1):
		for y in range(maxi(0, lo.y - 1), mini(_ny, hi.y + 1) + 1):
			for x in range(maxi(0, lo.x - 1), mini(_nx, hi.x + 1) + 1):
				_gradient_known[_index(x, y, z)] = 0

func _gradient(i: int) -> Vector3:
	if _gradient_known[i] != 0:
		return _gradient_cache[i]
	var z: int = int(i / _plane)
	var rem: int = i - z * _plane
	var y: int = int(rem / _sx)
	var x: int = rem - y * _sx
	var result := Vector3(
		_values[_index(maxi(0, x - 1), y, z)] - _values[_index(mini(_nx, x + 1), y, z)],
		_values[_index(x, maxi(0, y - 1), z)] - _values[_index(x, mini(_ny, y + 1), z)],
		_values[_index(x, y, maxi(0, z - 1))] - _values[_index(x, y, mini(_nz, z + 1))])
	result = result.normalized() if result.length_squared() > 0.00000001 else Vector3.UP
	_gradient_cache[i] = result
	_gradient_known[i] = 1
	return result

func _position_for_index(i: int) -> Vector3:
	var z: int = int(i / _plane)
	var rem: int = i - z * _plane
	var y: int = int(rem / _sx)
	return _point(rem - y * _sx, y, z)

func _edge_vertex(a: int, b: int) -> int:
	var key: int = mini(a, b) * _point_count + maxi(a, b)
	if _edge_cache.has(key):
		return int(_edge_cache[key])
	var da: float = _values[a]
	var t: float = da / (da - _values[b])
	var p: Vector3 = _position_for_index(a).lerp(_position_for_index(b), t)
	var n: Vector3 = _gradient(a).lerp(_gradient(b), t).normalized()
	var id: int = _vertices.size()
	_vertices.append(p)
	_normals.append(n if n.length_squared() > 0.1 else Vector3.UP)
	_uv.append(Vector2(p.x, p.z) * 0.3)
	_edge_cache[key] = id
	return id

func _emit_triangle(a: int, b: int, c: int) -> void:
	var pa: Vector3 = _vertices[a]
	var pb: Vector3 = _vertices[b]
	var pc: Vector3 = _vertices[c]
	var face: Vector3 = (pb - pa).cross(pc - pa)
	if face.length_squared() < 0.00000000000001:
		return
	var average: Vector3 = _normals[a] + _normals[b] + _normals[c]
	# Godot front faces use clockwise winding; outward shading normals are opposite
	# the mathematical cross product of the first two triangle edges.
	if face.dot(average) > 0.0:
		var swap: int = b
		b = c
		c = swap
	var center: Vector3 = (pa + pb + pc) / 3.0
	if _material_local(center) == "soil" and average.y > 0.6:
		_ground_indices.append_array(PackedInt32Array([a, b, c]))
	else:
		_rock_indices.append_array(PackedInt32Array([a, b, c]))

func _rebuild_geometry() -> void:
	var started: int = Time.get_ticks_msec()
	_edge_cache.clear()
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_uv = PackedVector2Array()
	_ground_indices = PackedInt32Array()
	_rock_indices = PackedInt32Array()
	for z in range(_nz):
		for y in range(_ny):
			for x in range(_nx):
				var corners := PackedInt32Array()
				var positive: bool = false
				var negative: bool = false
				for corner in CORNERS:
					var i: int = _index(x + corner.x, y + corner.y, z + corner.z)
					corners.append(i)
					positive = positive or _values[i] > 0.0
					negative = negative or _values[i] <= 0.0
				if not positive or not negative:
					continue
				for tet in TETS:
					var inside := PackedInt32Array()
					var outside := PackedInt32Array()
					for t in tet:
						var i: int = corners[t]
						if _values[i] > 0.0:
							inside.append(i)
						else:
							outside.append(i)
					match inside.size():
						1:
							_emit_triangle(_edge_vertex(inside[0], outside[0]), _edge_vertex(inside[0], outside[1]), _edge_vertex(inside[0], outside[2]))
						3:
							_emit_triangle(_edge_vertex(outside[0], inside[0]), _edge_vertex(outside[0], inside[1]), _edge_vertex(outside[0], inside[2]))
						2:
							var a: int = _edge_vertex(inside[0], outside[0])
							var b: int = _edge_vertex(inside[0], outside[1])
							var c: int = _edge_vertex(inside[1], outside[0])
							var d: int = _edge_vertex(inside[1], outside[1])
							_emit_triangle(a, b, d)
							_emit_triangle(a, d, c)
	var mesh := ArrayMesh.new()
	var faces := PackedVector3Array()
	for material_indices in [_ground_indices, _rock_indices]:
		if material_indices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_TEX_UV] = _uv
		arrays[Mesh.ARRAY_INDEX] = material_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		for i in material_indices:
			faces.append(_vertices[i])
	triangle_count = int(faces.size() / 3)
	mesh_instance.mesh = mesh
	_apply_materials()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	collision.shape = shape
	last_rebuild_ms = Time.get_ticks_msec() - started

func _apply_materials() -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var surface: int = 0
	if not _ground_indices.is_empty():
		if _ground_material != null:
			mesh_instance.set_surface_override_material(surface, _ground_material)
		surface += 1
	if not _rock_indices.is_empty() and _rock_material != null:
		mesh_instance.set_surface_override_material(surface, _rock_material)
