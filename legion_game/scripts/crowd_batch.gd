extends Node3D
## Six pre-baked poses, each rendered as an instanced group instead of one node per unit.
var batches: Array[MultiMeshInstance3D] = []
var capacity := 0
var clock := 0.0
var initialised := false

func setup(model_path: String, max_instances: int) -> void:
    capacity = max_instances
    var resource := load(model_path) as PackedScene
    if resource == null:
        push_error("Cannot load crowd model: " + model_path)
        return
    var instance := resource.instantiate() as Node3D
    add_child(instance)
    var children := instance.get_children()
    children.sort_custom(func(a: Node, b: Node): return str(a.name) < str(b.name))
    for child in children:
        if child is MeshInstance3D:
            var mesh_node := child as MeshInstance3D
            var multi := MultiMesh.new()
            multi.transform_format = MultiMesh.TRANSFORM_3D
            multi.mesh = mesh_node.mesh
            multi.instance_count = capacity
            multi.visible_instance_count = 0
            var batch := MultiMeshInstance3D.new()
            batch.multimesh = multi
            batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            add_child(batch)
            batches.append(batch)
    instance.queue_free()
    initialised = batches.size() == 6
    if not initialised:
        push_error("Crowd model must contain six animation poses: " + model_path)

func show_units(units: Array, delta: float) -> void:
    if not initialised:
        return
    clock += delta
    var counts := [0, 0, 0, 0, 0, 0]
    for item in units:
        var frame := posmod(int(floor(clock * 8.5 + float(item.get("phase", 0.0)))), 6)
        var index: int = counts[frame]
        if index >= capacity:
            continue
        var size: float = float(item.get("size", 1.0))
        var yaw: float = float(item.get("yaw", 0.0))
        var tilt: float = float(item.get("tilt", 0.0))
        var orientation := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
        orientation = orientation.scaled(Vector3.ONE * size)
        var transform := Transform3D(orientation, Vector3(float(item["x"]), float(item.get("y", 0.02)), float(item["z"])))
        batches[frame].multimesh.set_instance_transform(index, transform)
        counts[frame] = index + 1
    for i in range(6):
        batches[i].multimesh.visible_instance_count = counts[i]

func visible_count() -> int:
    var total := 0
    for batch in batches:
        total += batch.multimesh.visible_instance_count
    return total
