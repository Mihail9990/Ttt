extends CharacterBody3D
## Lightweight enemy AI: approach, strafe, line-of-sight fire, take damage, collapse.

var game: Node3D
var health := 95.0
var dead := false
var cooldown := 1.3
var thinking := 0.0
var strafe := 1.0
var death_time := 0.0
var mannequin: Node3D
var helmet: MeshInstance3D
var weapon_flash: MeshInstance3D
var shoot_flash := 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
    name = "Hostile"
    rng.randomize()
    strafe = -1.0 if rng.randi() % 2 == 0 else 1.0
    collision_layer = 1
    collision_mask = 1
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.43
    capsule.height = 1.8
    var shape := CollisionShape3D.new()
    shape.shape = capsule
    add_child(shape)
    _build_character()

func _mat(hex: String, metal: float = 0.0) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(hex)
    mat.metallic = metal
    mat.roughness = 0.83 if metal < 0.1 else 0.5
    return mat

func _box(at: Vector3, size: Vector3, mat: Material, root: Node3D) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    var bx := BoxMesh.new()
    bx.size = size
    mesh.mesh = bx
    mesh.material_override = mat
    mesh.position = at
    root.add_child(mesh)
    return mesh

func _sphere(at: Vector3, width: float, height: float, mat: Material, root: Node3D) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    var sph := SphereMesh.new()
    sph.radius = width
    sph.height = height
    sph.radial_segments = 10
    sph.rings = 5
    mesh.mesh = sph
    mesh.material_override = mat
    mesh.position = at
    root.add_child(mesh)
    return mesh

func _build_character() -> void:
    var olive := _mat("#414d40")
    var khaki := _mat("#77705b")
    var tan := _mat("#ad9579")
    var black := _mat("#1c2528", 0.3)
    var plated := _mat("#34433d")
    mannequin = Node3D.new()
    add_child(mannequin)
    _box(Vector3(0, 0.09, 0.04), Vector3(0.68, 0.78, 0.36), olive, mannequin)
    _box(Vector3(0, 0.09, -0.18), Vector3(0.58, 0.61, 0.17), plated, mannequin)
    for x in [-0.18, 0.18]:
        _box(Vector3(x, -0.04, -0.285), Vector3(0.19, 0.23, 0.045), khaki, mannequin)
    _box(Vector3(0, -0.42, 0), Vector3(0.50, 0.24, 0.37), khaki, mannequin)
    for x in [-0.19, 0.19]:
        _box(Vector3(x, -0.77, 0), Vector3(0.23, 0.58, 0.25), olive, mannequin)
        _box(Vector3(x, -1.00, -0.06), Vector3(0.25, 0.19, 0.37), black, mannequin)
        _box(Vector3(x * 1.9, 0.04, -0.08), Vector3(0.22, 0.65, 0.25), olive, mannequin)
        _box(Vector3(x * 1.9, -0.17, -0.25), Vector3(0.22, 0.25, 0.30), tan, mannequin)
    _sphere(Vector3(0, 0.70, 0), 0.235, 0.43, tan, mannequin)
    helmet = _sphere(Vector3(0, 0.88, 0), 0.28, 0.29, khaki, mannequin)
    _box(Vector3(0, 0.74, -0.22), Vector3(0.48, 0.12, 0.12), black, mannequin)
    _box(Vector3(0, 0.47, -0.23), Vector3(0.37, 0.18, 0.13), black, mannequin)
    _box(Vector3(0.04, -0.12, -0.53), Vector3(0.12, 0.14, 0.9), black, mannequin)
    _box(Vector3(0.04, -0.09, -1.05), Vector3(0.07, 0.07, 0.5), plated, mannequin)
    weapon_flash = _sphere(Vector3(0.04, -0.09, -1.38), 0.12, 0.24, _mat("#ffd996"), mannequin)
    weapon_flash.visible = false

func _physics_process(dt: float) -> void:
    if dead:
        death_time += dt
        mannequin.rotation.z = lerpf(mannequin.rotation.z, -1.3, minf(1.0, dt * 3))
        return
    if not is_instance_valid(game) or game.state != 1 or not is_instance_valid(game.player):
        velocity = Vector3.ZERO
        return
    var player: CharacterBody3D = game.player
    var diff := player.global_position - global_position
    diff.y = 0
    var distance := diff.length()
    if distance < 0.2:
        return
    var facing := atan2(-diff.x, -diff.z)
    rotation.y = lerp_angle(rotation.y, facing, minf(1.0, dt * 6.0))
    cooldown -= dt
    thinking -= dt
    shoot_flash -= dt
    weapon_flash.visible = shoot_flash > 0.0
    if thinking <= 0:
        thinking = rng.randf_range(1.5, 3.3)
        strafe *= -1.0

    var move_dir := Vector3.ZERO
    if distance > 13.0 and distance < 48:
        move_dir = diff.normalized()
    elif distance <= 13 and distance > 5:
        move_dir = Vector3(-diff.z, 0, diff.x).normalized() * strafe * 0.5
    velocity.x = move_toward(velocity.x, move_dir.x * 2.0, 10.0 * dt)
    velocity.z = move_toward(velocity.z, move_dir.z * 2.0, 10.0 * dt)
    if not is_on_floor():
        velocity.y -= 19.0 * dt
    else:
        velocity.y = -0.2
    move_and_slide()
    if distance < 26.0 and cooldown <= 0:
        cooldown = rng.randf_range(0.85, 1.55)
        _attack(player, distance)

func _attack(player: CharacterBody3D, distance: float) -> void:
    var origin := global_position + Vector3(0, 0.45, 0)
    var destination := player.camera.global_position
    var ray := PhysicsRayQueryParameters3D.create(origin, destination)
    ray.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(ray)
    if hit.is_empty() or hit["collider"] != player:
        return
    shoot_flash = 0.16
    game.sound.play_enemy_shot()
    if rng.randf() < 0.53 + clampf((18.0 - distance) * 0.014, 0, 0.17):
        player.take_damage(rng.randf_range(6, 12))

func take_damage(amount: float) -> bool:
    if dead:
        return false
    health -= amount
    mannequin.rotation.z = rng.randf_range(-0.06, 0.06)
    if health <= 0:
        dead = true
        collision_layer = 0
        collision_mask = 0
        game.player.total_kills += 1
        return true
    return false
