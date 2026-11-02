extends Node3D
## Six pre-baked poses, each rendered as an instanced group instead of one node per unit.
var batches: Array[MultiMeshInstance3D] = []
var capacity := 0
var clock := 0.0
var initialised := false
var shadow_batch: MultiMeshInstance3D

func setup(model_path: String, max_instances: int, infected: bool = false) -> void:
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
            var crowd_mesh: Mesh = mesh_node.mesh
            if infected:
                crowd_mesh = mesh_node.mesh.duplicate(true)
                for surface in range(crowd_mesh.get_surface_count()):
                    var original: Material = crowd_mesh.surface_get_material(surface)
                    if original != null and original is StandardMaterial3D:
                        var stained: StandardMaterial3D = original.duplicate()
                        stained.albedo_color = Color(0.65, 0.40, 0.36)
                        stained.roughness = 0.95
                        crowd_mesh.surface_set_material(surface, stained)
            multi.mesh = crowd_mesh
            multi.instance_count = capacity
            multi.visible_instance_count = 0
            var batch := MultiMeshInstance3D.new()
            batch.multimesh = multi
            batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            add_child(batch)
            batches.append(batch)
    instance.queue_free()
    var disk := CylinderMesh.new()
    disk.top_radius = 0.37
    disk.bottom_radius = 0.37
    disk.height = 0.012
    disk.radial_segments = 12
    var shadow_mat := StandardMaterial3D.new()
    shadow_mat.albedo_color = Color(0.02, 0.025, 0.025, 0.26)
    shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    disk.material = shadow_mat
    var shadows := MultiMesh.new()
    shadows.transform_format = MultiMesh.TRANSFORM_3D
    shadows.mesh = disk
    shadows.instance_count = capacity
    shadows.visible_instance_count = 0
    shadow_batch = MultiMeshInstance3D.new()
    shadow_batch.multimesh = shadows
    shadow_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(shadow_batch)
    initialised = batches.size() == 6
    if not initialised:
        push_error("Crowd model must contain six animation poses: " + model_path)

func show_units(units: Array, delta: float) -> void:
    if not initialised:
        return
    clock += delta
    var counts := [0, 0, 0, 0, 0, 0]
    var shadow_count := 0
    for item in units:
        if shadow_count < capacity:
            var shadow_size: float = float(item.get("size", 1.0))
            shadow_batch.multimesh.set_instance_transform(shadow_count, Transform3D(Basis().scaled(Vector3(shadow_size, 1.0, shadow_size)), Vector3(float(item["x"]), 0.025, float(item["z"]))))
            shadow_count += 1
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
    shadow_batch.multimesh.visible_instance_count = shadow_count

func visible_count() -> int:
    var total := 0
    for batch in batches:
        total += batch.multimesh.visible_instance_count
    return total
