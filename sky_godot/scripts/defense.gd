class_name SkyDefense
extends StaticBody3D
var unit_id: int = 0
var owner_id: int = 1
var kind: String = "turret"
var health: float = 100.0
var game: Node
var origin := Vector3.ZERO
var clock: float = 0.0
var cooldown: float = 0.0
var head: Node3D
var state_label: Label3D

func configure(id: int, owner: int, type: String, manager: Node) -> void:
	unit_id = id
	owner_id = owner
	kind = type
	game = manager
	origin = global_position
	set_meta("defense_id", id)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.5
	collider.shape = capsule
	collider.position.y = 0.75
	add_child(collider)
	var foundation := _box(Vector3(0.65,0.2,0.65), Vector3(0,0.1,0))
	foundation.material_override = SkyArt.material("metal")
	head = Node3D.new()
	head.position.y = 1.1
	add_child(head)
	if kind == "guard":
		_box(Vector3(0.45,0.8,0.25), Vector3(0,0.65,0)).material_override = _cloth()
		var skull := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.17
		sphere.height = 0.34
		skull.mesh = sphere
		skull.material_override = SkyArt.material("metal")
		head.add_child(skull)
		for x in [-0.13, 0.13]:
			_box(Vector3(0.15,0.45,0.2),Vector3(x,0.25,0)).material_override = _cloth()
	elif kind == "drone":
		head.position.y = 1.8
		for x in [-0.42,0.42]:
			for z in [-0.42,0.42]:
				var rotor := _box(Vector3(0.55,0.025,0.06),Vector3(x,1.8,z))
				rotor.material_override = SkyArt.material("metal")
		_box(Vector3(0.4,0.2,0.5),Vector3(0,1.8,0)).material_override = SkyArt.material("metal")
	else:
		_box(Vector3(0.15,0.9,0.15),Vector3(0,0.65,0)).material_override = SkyArt.material("metal")
	var barrel := MeshInstance3D.new()
	var barrel_mesh := BoxMesh.new()
	barrel_mesh.size = Vector3(0.08,0.10,0.8)
	barrel.mesh = barrel_mesh
	barrel.material_override = SkyArt.material("metal")
	head.add_child(barrel)
	barrel.position.z = -0.35
	state_label = Label3D.new()
	state_label.text = {"guard":"Охранник", "turret":"Турель", "drone":"Дрон"}.get(kind,kind)
	state_label.position.y = 2.4
	state_label.font_size = 24
	state_label.pixel_size = 0.002
	state_label.modulate = Color(0.55,0.8,0.85)
	add_child(state_label)

func _box(dimensions: Vector3, point: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	instance.mesh = box
	add_child(instance)
	instance.position = point
	return instance

func _cloth() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18,0.21,0.17)
	m.roughness = 0.9
	return m

func server_tick(delta: float) -> void:
	if not is_instance_valid(game) or not game.is_authority(): return
	clock += delta
	cooldown -= delta
	if kind == "drone":
		global_position = origin + Vector3(sin(clock*0.35)*3.0,0.3+sin(clock)*0.2,cos(clock*0.35)*3.0)
	var target: Node3D = null
	var best: float = 15.0 if kind == "turret" else 12.0
	for id in game.players:
		if int(id) == owner_id: continue
		var player: Node3D = game.players[id]
		var distance := global_position.distance_to(player.global_position)
		if distance < best:
			var query := PhysicsRayQueryParameters3D.create(head.global_position,player.global_position+Vector3.UP*0.8)
			query.exclude = [get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.get("collider") == player:
				target = player
				best = distance
	if target == null: return
	head.look_at(target.global_position+Vector3.UP,Vector3.UP)
	if cooldown <= 0.0 and game.sim.consume(owner_id,"ammo",1):
		cooldown = 0.8
		game.damage_player(target.player_id,12.0,owner_id)
		game.mark_dirty()
