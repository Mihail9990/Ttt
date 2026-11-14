extends SceneTree
const IslandScript = preload("res://scripts/island.gd")
var assertions: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		if failures <= 5:
			push_error("TERRAIN FAIL: " + message)

func key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 1000000.0), roundi(p.y * 1000000.0), roundi(p.z * 1000000.0)]

func validate_mesh(island: Node3D) -> int:
	var mesh: ArrayMesh = island.mesh_instance.mesh
	var edges: Dictionary = {}
	var total: int = 0
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		check(indices.size() % 3 == 0, "triangle count")
		for p in vertices:
			check(p.is_finite(), "finite point")
		for n in normals:
			check(n.is_finite() and n.length() > 0.9 and n.length() < 1.1, "finite unit normal")
		for i in range(0, indices.size(), 3):
			var a: Vector3 = vertices[indices[i]]
			var b: Vector3 = vertices[indices[i + 1]]
			var c: Vector3 = vertices[indices[i + 2]]
			var normal: Vector3 = normals[indices[i]] + normals[indices[i + 1]] + normals[indices[i + 2]]
			check((b - a).cross(c - a).dot(normal) <= 0.000001, "Godot clockwise front faces")
			var names: Array[String] = [key(a), key(b), key(c)]
			for e in range(3):
				var first: String = names[e]
				var second: String = names[(e + 1) % 3]
				var edge: String = (first + ":" + second) if first < second else (second + ":" + first)
				edges[edge] = int(edges.get(edge, 0)) + 1
			total += 1
	for edge in edges:
		var count: int = edges[edge]
		check(count == 2, "closed watertight surface/cavity edge %s count=%d" % [edge,count])
	check(total > 500, "real volumetric island geometry")
	return total

func _initialize() -> void:
	var island = IslandScript.new()
	root.add_child(island)
	var started: int = Time.get_ticks_msec()
	island.configure(41, 24.0)
	check(island.body.get_meta("island") == island, "ray collider metadata")
	check(island.density(Vector3(0, -2, 0)) > 0, "solid interior")
	check(island.density(Vector3(0, 8, 0)) < 0, "air above")
	check(island.density(Vector3(0, -40, 0)) < 0, "air under island")
	check(island.material_at(Vector3(0, -0.4, 0)) == "soil", "soil layer")
	check(island.material_at(Vector3(0, -2.4, 0)) == "clay", "clay layer")
	check(island.material_at(Vector3(0, -5.0, 0)) == "stone", "stone layer")
	var initial_triangles: int = validate_mesh(island)
	var volume: float = island.excavate(Vector3(0, -6, 0), 2.0)
	check(volume > 25.0 and volume < 35.0, "newly removed solid volume in enclosed cavity")
	check(island.density(Vector3(0, -6, 0)) < 0, "cavity is real negative density")
	var dug_triangles: int = validate_mesh(island)
	check(dug_triangles > initial_triangles, "interior cavity has its own surface")
	check(island.excavate(Vector3(0, -6, 0), 2.0) == 0, "same dig cannot issue resources twice")
	check(island.excavate(Vector3(0, 4, 0), 0.8) == 0, "empty air cannot issue resources")
	check(island.excavate(Vector3(NAN, 0, 0), 1.2) == 0, "NaN point rejected")
	check(island.excavate(Vector3.ZERO, INF) == 0, "infinite radius rejected")
	check(island.excavate(Vector3.ZERO, 0.01) == 0, "tiny radius rejected")
	check(island.excavate(Vector3(9000, 0, 0), 1.2) == 0, "far stamp rejected")
	var saved: Array = island.get_stamps()
	var before: float = island.density(Vector3(1, -6, 0))
	check(not island.restore_stamps([{"center": [0, 0, 0], "radius": -1}]), "bad restore rejected")
	check(island.get_stamps() == saved, "bad restore atomic")
	check(not island.restore_stamps([{"center": ["bad", 0, 0], "radius": 1.2}]), "non-number restore rejected")
	check(island.restore_stamps(JSON.parse_string(JSON.stringify(saved))), "JSON round trip")
	check(island.density(Vector3(1, -6, 0)) == before, "restored field deterministic")
	var excessive: Array = []
	for i in range(129):
		excessive.append({"center": [0, -6, 0], "radius": 1.2})
	check(not island.restore_stamps(excessive), "stamp count bounded")
	# Coordinate transforms matter when this same island is positioned in the shared archipelago.
	island.position = Vector3(100, 20, -50)
	check(island.density(Vector3(100, 14, -50)) < 0, "world/local excavation coordinates")
	print("GODOT TERRAIN PASS: " if failures == 0 else "GODOT TERRAIN FAIL: ", assertions, " checks; ", initial_triangles, " -> ", dug_triangles, " triangles; new volume ", volume, " m3; total ", Time.get_ticks_msec() - started, " ms")
	island.free()
	quit(0 if failures == 0 else 1)
