class_name SkyResource
extends StaticBody3D
var deposit_id: int = 0
var resource_kind: String = "timber"
var remaining: int = 0
var visual: Node3D
var collider: CollisionShape3D
var depleted := false

func configure(id: int, kind: String, amount: int, scale_factor: float = 1.0) -> void:
	deposit_id = id
	resource_kind = kind
	remaining = amount
	set_meta("deposit_id", id)
	visual = SkyArt.model("tree" if kind == "timber" else "rock")
	if visual == null:
		visual = MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.height = 4.0 if kind == "timber" else 1.0
		mesh.top_radius = 0.08 if kind == "timber" else 0.6
		mesh.bottom_radius = 0.16 if kind == "timber" else 0.8
		visual.mesh = mesh
		visual.material_override = SkyArt.material("wood" if kind == "timber" else "rock")
		visual.position.y = mesh.height * 0.5
	add_child(visual)
	visual.scale = Vector3.ONE * scale_factor
	collider = CollisionShape3D.new()
	var collision := CylinderShape3D.new()
	collision.height = 3.0 if kind == "timber" else 1.0
	collision.radius = 0.18 if kind == "timber" else 0.6
	collider.shape = collision
	collider.position.y = collision.height * 0.5
	add_child(collider)
	set_remaining(amount, false)

func set_remaining(amount: int, animate: bool = true) -> void:
	remaining = amount
	if amount > 0:
		depleted = false
		visible = true
		visual.rotation = Vector3.ZERO
		collider.set_deferred("disabled", false)
		return
	if depleted: return
	depleted = true
	collider.set_deferred("disabled", true)
	if animate and resource_kind == "timber" and is_inside_tree():
		var tween := create_tween()
		tween.tween_property(visual, "rotation:z", 1.5, 0.7).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(hide)
	else: hide()
