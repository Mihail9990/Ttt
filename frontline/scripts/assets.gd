extends RefCounted
## Resource loader and deterministic sizing for licensed external glTF models.
## All downloaded .glb files are included in the APK by the CI pipeline.
const MODEL_DIR := "res://assets/models/"

static func _collect_bounds(node: Node, anchor: Node3D, data: Dictionary) -> void:
    if node is MeshInstance3D:
        var mesh_node: MeshInstance3D = node as MeshInstance3D
        if mesh_node.mesh != null:
            var rect: AABB = mesh_node.get_aabb()
            var transform_to_root: Transform3D = anchor.global_transform.affine_inverse() * mesh_node.global_transform
            for bx in [0.0, 1.0]:
                for by in [0.0, 1.0]:
                    for bz in [0.0, 1.0]:
                        var point: Vector3 = rect.position + rect.size * Vector3(bx, by, bz)
                        var mapped: Vector3 = transform_to_root * point
                        if not data["found"]:
                            data["found"] = true
                            data["low"] = mapped
                            data["high"] = mapped
                        else:
                            var low: Vector3 = data["low"]
                            var high: Vector3 = data["high"]
                            data["low"] = Vector3(minf(low.x, mapped.x), minf(low.y, mapped.y), minf(low.z, mapped.z))
                            data["high"] = Vector3(maxf(high.x, mapped.x), maxf(high.y, mapped.y), maxf(high.z, mapped.z))
    for child in node.get_children():
        _collect_bounds(child, anchor, data)

static func _bounds(node: Node3D) -> AABB:
    var state := {"found": false, "low": Vector3.ZERO, "high": Vector3.ZERO}
    _collect_bounds(node, node, state)
    if not state["found"]:
        return AABB(Vector3.ZERO, Vector3.ONE)
    var low: Vector3 = state["low"]
    var high: Vector3 = state["high"]
    return AABB(low, high - low)

static func load_mesh(filename: String, parent: Node3D) -> Node3D:
    var uri := MODEL_DIR + filename + ".glb"
    if not ResourceLoader.exists(uri):
        push_warning("Optional art model unavailable: " + uri)
        return null
    var source := load(uri) as PackedScene
    if source == null:
        push_warning("Invalid glTF art model: " + uri)
        return null
    var wrapper := Node3D.new()
    parent.add_child(wrapper)
    var visual := source.instantiate() as Node3D
    if visual == null:
        wrapper.queue_free()
        return null
    wrapper.add_child(visual)
    return wrapper

static func add_ground_model(parent: Node3D, filename: String, world_position: Vector3, final_height: float, yaw: float = 0.0) -> Node3D:
    var wrapper := load_mesh(filename, parent)
    if wrapper == null:
        return null
    var mesh_root := wrapper.get_child(0) as Node3D
    var bb: AABB = _bounds(wrapper)
    var height: float = maxf(bb.size.y, 0.05)
    var factor: float = final_height / height
    mesh_root.scale = Vector3.ONE * factor
    mesh_root.position = Vector3(
        -(bb.position.x + bb.size.x * 0.5) * factor,
        -bb.position.y * factor,
        -(bb.position.z + bb.size.z * 0.5) * factor)
    wrapper.position = world_position
    wrapper.rotation.y = yaw
    return wrapper

static func add_first_person_weapon(parent: Node3D) -> Node3D:
    var wrapper := load_mesh("first_person_m4a1", parent)
    if wrapper == null:
        return null
    var imported := wrapper.get_child(0) as Node3D
    var bb: AABB = _bounds(wrapper)
    # Normalize the longest axis to a believable rifle + forearms length.
    if bb.size.x > bb.size.z * 1.20 and bb.size.x > bb.size.y * 1.20:
        imported.rotation.y = PI * 0.5
    elif bb.size.y > bb.size.z * 1.20 and bb.size.y > bb.size.x * 1.20:
        imported.rotation.x = PI * 0.5
    bb = _bounds(wrapper)
    var extent: float = maxf(0.1, maxf(bb.size.x, maxf(bb.size.y, bb.size.z)))
    var factor: float = 1.75 / extent
    imported.scale = Vector3.ONE * factor
    # The model is a camera-local viewmodel; keep the muzzle pointing toward -Z.
    imported.position = Vector3(
        -(bb.position.x + bb.size.x * 0.5) * factor,
        -0.02 - (bb.position.y + bb.size.y * 0.5) * factor,
        -0.65 - (bb.position.z + bb.size.z * 0.5) * factor)
    return wrapper
