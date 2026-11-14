class_name SkyPlayer
extends CharacterBody3D

const TOOLS: Array[String] = ["shovel", "axe", "pickaxe", "hammer", "driver", "build", "rifle"]
const ART = preload("res://scripts/art.gd")
var player_id: int = 1
var local_player: bool = false
var game: Node
var camera: Camera3D
var tool: String = "shovel"
var build_kind: String = "board"
var part_size: Vector3 = Vector3(2.0, 0.2, 0.03)
var part_rotation: Vector3 = Vector3.ZERO
var input_blocked: bool = false
var glider: bool = false
var ascend_held: bool = false
var descend_held: bool = false
var health: float = 100.0
var look_pitch: float = 0.0
var _body_visual: Node3D
var _held_root: Node3D
var _held: Node3D
var _preview: MeshInstance3D
var _tool_shown: String = ""
var _move_finger: int = -1
var _look_finger: int = -1
var _move_origin: Vector2 = Vector2.ZERO
var _touch_move: Vector2 = Vector2.ZERO
var _last_look: Vector2 = Vector2.ZERO
var _jump_queued: bool = false
var _pose_clock: float = 0.0
var _kick: float = 0.0
var _bob: float = 0.0

func _init() -> void:
	name = "Player"
	collision_layer = 2
	collision_mask = 1 | 2
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.76
	collision.shape = capsule
	collision.position.y = 0.88
	add_child(collision)
	_body_visual = Node3D.new()
	_body_visual.name = "Avatar"
	add_child(_body_visual)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.29
	body_mesh.height = 1.2
	body_mesh.radial_segments = 12
	body.mesh = body_mesh
	body.position.y = 0.85
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = Color(0.18, 0.25, 0.24)
	fabric.roughness = 0.95
	body.material_override = fabric
	_body_visual.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.19
	head_mesh.height = 0.38
	head_mesh.radial_segments = 12
	head.mesh = head_mesh
	head.position.y = 1.57
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.61, 0.44, 0.32)
	skin.roughness = 0.85
	head.material_override = skin
	_body_visual.add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, 1.62, 0.0)
	camera.fov = 76.0
	camera.near = 0.05
	add_child(camera)
	_held_root = Node3D.new()
	_held_root.position = Vector3(0.24, -0.23, -0.44)
	camera.add_child(_held_root)

func configure(id: int, is_local: bool, manager: Node) -> void:
	player_id = id
	local_player = is_local
	game = manager
	name = "Player_%d" % id
	_body_visual.visible = not is_local
	_held_root.visible = is_local
	camera.current = is_local
	if is_local:
		_update_held_tool()

func _ready() -> void:
	if local_player:
		camera.make_current()

func get_eye() -> Vector3:
	return camera.global_position

func get_aim() -> Vector3:
	return -camera.global_basis.z

func set_tool(value: String) -> void:
	if value not in TOOLS:
		return
	tool = value
	_update_held_tool()

func next_tool(delta: int = 1) -> void:
	set_tool(TOOLS[posmod(TOOLS.find(tool) + delta, TOOLS.size())])

func use_tool() -> void:
	if not local_player or input_blocked or not is_instance_valid(game):
		return
	_kick = 1.0
	game.request_action({"action": "use", "tool": tool, "build_kind": build_kind,
		"size": [part_size.x, part_size.y, part_size.z],
		"rotation": [part_rotation.x, part_rotation.y, part_rotation.z]})

func get_move_input() -> Vector2:
	if input_blocked: return Vector2.ZERO
	return (Input.get_vector("move_left", "move_right", "move_forward", "move_back") + _touch_move).limit_length()

func is_piloting() -> bool:
	if not is_instance_valid(game):
		return false
	var owner: Variant = game.get("pilot_player")
	var island: Variant = game.get("pilot_island")
	return typeof(owner) == TYPE_INT and typeof(island) == TYPE_INT and int(owner) == player_id and int(island) > 0

func request_jump() -> void:
	if not input_blocked and not is_piloting():
		_jump_queued = true

func set_input_blocked(value: bool) -> void:
	input_blocked = value
	if value:
		_move_finger = -1
		_look_finger = -1
		_touch_move = Vector2.ZERO
		ascend_held = false
		descend_held = false

func _unhandled_input(event: InputEvent) -> void:
	if not local_player:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
		return
	if event is InputEventScreenDrag:
		_handle_drag(event)
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if input_blocked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.0025)
		look_pitch = clampf(look_pitch - event.relative.y * 0.0025, -1.45, 1.45)
		camera.rotation.x = look_pitch
	if event.is_action_pressed("use"):
		if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			use_tool()
	elif event.is_action_pressed("jump"):
		request_jump()
	elif event.is_action_pressed("tool_next"):
		next_tool()
	elif event.is_action_pressed("tool_previous"):
		next_tool(-1)
	elif event.is_action_pressed("alt_use"):
		if tool == "build":
			var kinds: Array[String] = ["board", "brick", "beam"]
			build_kind = kinds[posmod(kinds.find(build_kind) + 1, kinds.size())]
		else:
			game.request_action({"action": "remove", "tool": tool})
	elif event.is_action_pressed("interact"):
		game.request_action({"action": "interact"})
	elif event.is_action_pressed("save"):
		game.request_action({"action": "save"})
	elif event.is_action_pressed("rotate"):
		part_rotation.y = wrapf(part_rotation.y + deg_to_rad(15), -PI, PI)
	elif event.is_action_pressed("pitch"):
		part_rotation.x = wrapf(part_rotation.x + deg_to_rad(15), -PI, PI)
	elif event.is_action_pressed("roll"):
		part_rotation.z = wrapf(part_rotation.z + deg_to_rad(15), -PI, PI)
	elif event.is_action_pressed("length_up"):
		part_size.x = minf(6.0, part_size.x + 0.1)
	elif event.is_action_pressed("length_down"):
		part_size.x = maxf(0.1, part_size.x - 0.1)
	elif event.is_action_pressed("width_up"):
		part_size.y = minf(2.0, part_size.y + 0.05)
	elif event.is_action_pressed("width_down"):
		part_size.y = maxf(0.02, part_size.y - 0.05)
	elif event.is_action_pressed("height_up"):
		part_size.z = minf(1.0, part_size.z + 0.01)
	elif event.is_action_pressed("height_down"):
		part_size.z = maxf(0.01, part_size.z - 0.01)
	for index: int in range(TOOLS.size()):
		if event.is_action_pressed("tool_%d" % (index + 1)):
			set_tool(TOOLS[index])
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		glider = not glider
		game.notice = "Планер раскрыт" if glider else "Планер сложен"

func _handle_touch(event: InputEventScreenTouch) -> void:
	if input_blocked:
		return
	if not event.pressed:
		if event.index == _move_finger:
			_move_finger = -1
			_touch_move = Vector2.ZERO
		if event.index == _look_finger:
			_look_finger = -1
		return
	for control: Node in get_tree().get_nodes_in_group("sky_ui_blocker"):
		if control is Control and control.is_visible_in_tree() and control.get_global_rect().has_point(event.position):
			return
	var viewport_size := get_viewport().get_visible_rect().size
	if event.position.x < viewport_size.x * 0.43 and _move_finger < 0:
		_move_finger = event.index
		_move_origin = event.position
	elif _look_finger < 0:
		_look_finger = event.index
		_last_look = event.position

func _handle_drag(event: InputEventScreenDrag) -> void:
	if input_blocked:
		return
	if event.index == _move_finger:
		var delta := (event.position - _move_origin) / 85.0
		_touch_move = Vector2(clampf(delta.x, -1, 1), clampf(delta.y, -1, 1))
	elif event.index == _look_finger:
		var delta := event.position - _last_look
		rotate_y(-delta.x * 0.004)
		look_pitch = clampf(look_pitch - delta.y * 0.004, -1.45, 1.45)
		camera.rotation.x = look_pitch
		_last_look = event.position

func _physics_process(delta: float) -> void:
	if not local_player:
		return
	if is_piloting():
		# The island controller owns the pilot's displacement. Character gravity
		# and walking must not fight the moving platform or slide off the helm.
		velocity = Vector3.ZERO
		_jump_queued = false
	else:
		var movement := get_move_input()
		var direction := (transform.basis * Vector3(movement.x, 0, movement.y)).normalized()
		var speed: float = 7.5 if glider and not is_on_floor() else 4.4
		velocity.x = move_toward(velocity.x, direction.x * speed, delta * 22)
		velocity.z = move_toward(velocity.z, direction.z * speed, delta * 22)
		if not is_on_floor():
			velocity.y -= 16.5 * delta
			# Keep ordinary falling within the authoritative pose speed budget.
			# Gliding uses its own slower descent cap.
			velocity.y = maxf(velocity.y, -1.8 if glider else -22.0)
		elif _jump_queued:
			velocity.y = 6.2
		_jump_queued = false
		move_and_slide()
	_pose_clock += delta
	if _pose_clock >= 0.10 and is_instance_valid(game):
		_pose_clock = 0.0
		game.send_player_pose(player_id, global_position, rotation.y, look_pitch)
	if _tool_shown != tool:
		_update_held_tool()
	_kick = move_toward(_kick, 0.0, delta * 5.5)
	_bob += delta * Vector2(velocity.x, velocity.z).length() * 2.8
	_held_root.rotation = Vector3(-0.12 + _kick * 0.6, 0.0, -_kick * 0.15)
	_held_root.position = Vector3(0.24, -0.23 + sin(_bob) * 0.008, -0.44 + _kick * 0.07)
	_update_preview()

func _update_held_tool() -> void:
	_tool_shown = tool
	if is_instance_valid(_held):
		_held.queue_free()
	_held = null
	if not local_player or tool == "build":
		return
	if tool == "driver":
		_held = ART.model("drill")
	elif tool == "hammer":
		_held = ART.model("hammer")
	if _held == null:
		_held = _fallback_tool(tool)
	_held_root.add_child(_held)
	_held.rotation = Vector3(0.15, PI * 0.5, 0.0)

func _fallback_tool(kind: String) -> Node3D:
	var root := Node3D.new()
	var handle := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.017
	cylinder.bottom_radius = 0.02
	cylinder.height = 0.65
	cylinder.radial_segments = 12
	handle.mesh = cylinder
	handle.position.y = 0.03
	handle.material_override = ART.material("wood")
	root.add_child(handle)
	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	if kind == "pickaxe":
		box.size = Vector3(0.40, 0.045, 0.045)
	elif kind == "axe":
		box.size = Vector3(0.20, 0.15, 0.035)
	elif kind == "rifle":
		box.size = Vector3(0.06, 0.10, 0.65)
		handle.visible = false
	else:
		box.size = Vector3(0.19, 0.23, 0.018)
	head.mesh = box
	head.position = Vector3(0.0, 0.36, 0.0)
	head.material_override = ART.material("metal")
	root.add_child(head)
	return root

func _update_preview() -> void:
	if not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.name = "BuildPreview"
		_preview.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.85, 0.75, 0.32)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview.material_override = mat
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.add_child(_preview)
	_preview.visible = tool == "build" and not input_blocked
	if not _preview.visible:
		return
	var query := PhysicsRayQueryParameters3D.create(get_eye(), get_eye() + get_aim() * 6.0, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_preview.visible = false
		return
	var size := Vector3(0.25, 0.12, 0.065) if build_kind == "brick" else Vector3(part_size.x, 0.12, 0.12) if build_kind == "beam" else part_size
	var angles := Vector3(part_rotation.x, part_rotation.y + rotation.y, part_rotation.z)
	var orientation := Basis.from_euler(angles)
	var normal: Vector3 = hit["normal"]
	var extent := (absf(normal.dot(orientation.x)) * size.x + absf(normal.dot(orientation.y)) * size.y + absf(normal.dot(orientation.z)) * size.z) * 0.5
	_preview.mesh.size = size
	_preview.global_transform = Transform3D(orientation, hit["position"] + normal * (extent + 0.01))

func _exit_tree() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()
