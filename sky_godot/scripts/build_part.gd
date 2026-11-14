class_name SkyBuildPart
extends StaticBody3D

var part_id: int = 0
var owner_id: int = 0
var health: float = 100.0
var size := Vector3(2.0, 0.2, 0.03)
var material_kind: String = "board"
var visual: MeshInstance3D
var shape: CollisionShape3D
var joints: Node3D
var joint_count: int = 0
var _joint_signature: int = -1

func configure(id: int, data: Dictionary) -> void:
	var changed: bool = visual==null or size!=data.size or material_kind!=str(data.material)
	part_id = id
	owner_id = int(data.owner)
	size = data.size
	material_kind = str(data.material)
	set_meta("part_id", id)
	if visual==null:
		visual = MeshInstance3D.new()
		add_child(visual)
		shape = CollisionShape3D.new()
		add_child(shape)
		joints = Node3D.new()
		add_child(joints)
	if changed:
		var box := BoxMesh.new()
		box.size = size
		visual.mesh = box
		visual.material_override = SkyArt.material("brick" if material_kind=="brick" else "wood")
		var collider := BoxShape3D.new()
		collider.size = size
		shape.shape = collider
		_joint_signature = -1
	if global_position!=data.position or rotation!=data.rotation:
		global_position = data.position
		rotation = data.rotation
		_joint_signature = -1

func update_joints(records: Dictionary) -> void:
	var relevant: Array = []
	for key in records:
		if int(records[key].a)==part_id: relevant.append([key,records[key].item,records[key].position])
	var signature := hash(relevant)
	if signature==_joint_signature: return
	_joint_signature = signature
	for child in joints.get_children():
		child.free()
	joint_count = 0
	for key in records:
		var data: Dictionary = records[key]
		if int(data.a) != part_id:
			continue
		joint_count += 1
		var local: Vector3 = to_local(data.position)
		var relative := local / (size * 0.5)
		var axis := 0
		if absf(relative.y) > absf(relative.x): axis = 1
		if absf(relative.z) > absf(relative[axis]): axis = 2
		var normal := Vector3.ZERO
		normal[axis] = signf(relative[axis])
		var head := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.005 if str(data.item) == "nail" else 0.007
		cylinder.bottom_radius = cylinder.top_radius
		cylinder.height = 0.003
		cylinder.radial_segments = 12
		head.mesh = cylinder
		head.material_override = SkyArt.material("metal")
		joints.add_child(head)
		head.position = local + normal * 0.002
		head.quaternion = Quaternion(Vector3.UP, normal)
		if str(data.item) == "screw":
			var slot := MeshInstance3D.new()
			var slot_mesh := BoxMesh.new()
			slot_mesh.size = Vector3(0.009, 0.001, 0.0015)
			slot.mesh = slot_mesh
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.08, 0.09, 0.10)
			slot.material_override = dark
			head.add_child(slot)
			slot.position.y = 0.002

func receive_damage(amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0: return false
	health = maxf(0.0, health - amount / (1.0 + minf(joint_count, 16) * 0.15))
	return health <= 0.0
