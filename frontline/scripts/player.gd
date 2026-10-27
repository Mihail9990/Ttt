extends CharacterBody3D
## First-person controller, touch/keyboard support, hitscan combat and animated weapon.

var game: Node3D
var health := 100.0
var ammo := 30
var reserve := 210
var reloading := false
var reload_remaining := 0.0
var shot_cooldown := 0.0
var hit_confirm := 0.0
var damage_flash := 0.0
var invulnerability := 1.3
var heal_delay := 0.0
var total_kills := 0
var camera: Camera3D
var gun: Node3D
var muzzle: MeshInstance3D
var current_bob := 0.0
var recoil_amount := 0.0
var ads_held := false
var step_clock := 0.0
var shoot_count := 0
var move_speed := 6.4
var last_fire_time := 0.0

func _ready() -> void:
    name = "Player"
    collision_layer = 1
    collision_mask = 1
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.39
    capsule.height = 1.8
    var collision := CollisionShape3D.new()
    collision.shape = capsule
    add_child(collision)
    camera = Camera3D.new()
    camera.position = Vector3(0, 0.68, 0)
    camera.current = true
    camera.fov = 77
    camera.near = 0.045
    add_child(camera)
    _build_weapon()
    if not OS.has_feature("mobile"):
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _mat(hex: String, metallic: float, rough: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(hex)
    mat.metallic = metallic
    mat.roughness = rough
    return mat

func _part(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, circular: bool = false) -> MeshInstance3D:
    var item := MeshInstance3D.new()
    if circular:
        var cyl := CylinderMesh.new()
        cyl.top_radius = size.x * 0.5
        cyl.bottom_radius = size.x * 0.5
        cyl.height = size.z
        cyl.radial_segments = 12
        item.mesh = cyl
        item.rotation.x = PI * 0.5
    else:
        var box := BoxMesh.new()
        box.size = size
        item.mesh = box
    item.material_override = mat
    item.position = pos
    parent.add_child(item)
    return item

func _build_weapon() -> void:
    gun = Node3D.new()
    gun.position = Vector3(0.36, -0.30, -0.66)
    camera.add_child(gun)
    var graphite := _mat("#20292e", 0.68, 0.41)
    var steel := _mat("#3e4b50", 0.8, 0.28)
    var polymer := _mat("#303a39", 0.22, 0.72)
    var bronze := _mat("#7d7364", 0.55, 0.49)
    var optic := _mat("#111d22", 0.2, 0.12)
    var fabric := _mat("#806f59", 0.0, 0.98)
    # Full depth silhouette of an original tactical rifle, not a replica of a brand.
    _part(gun, Vector3(0, -0.03, -0.28), Vector3(0.23, 0.23, 0.72), graphite)
    _part(gun, Vector3(0, 0.07, -0.69), Vector3(0.20, 0.17, 0.63), steel)
    _part(gun, Vector3(0, 0.008, -1.04), Vector3(0.095, 0.095, 0.68), steel, true)
    _part(gun, Vector3(0, -0.03, -1.42), Vector3(0.16, 0.14, 0.13), graphite, true)
    _part(gun, Vector3(0, 0.06, -0.52), Vector3(0.26, 0.025, 0.58), graphite)
    _part(gun, Vector3(0, -0.21, -0.13), Vector3(0.16, 0.42, 0.17), polymer)
    _part(gun, Vector3(0, -0.24, -0.42), Vector3(0.18, 0.40, 0.19), bronze)
    _part(gun, Vector3(0, 0.22, -0.23), Vector3(0.19, 0.16, 0.26), graphite)
    _part(gun, Vector3(0, 0.31, -0.26), Vector3(0.10, 0.09, 0.2), optic, true)
    _part(gun, Vector3(-0.19, -0.17, 0.16), Vector3(0.17, 0.12, 0.43), polymer)
    _part(gun, Vector3(0, 0.20, -1.09), Vector3(0.065, 0.19, 0.05), graphite)
    # Tactical rails, handguard cuts and accent insets.
    for i in range(5):
        _part(gun, Vector3(0.115, 0.10, -0.43 - i * 0.1), Vector3(0.018, 0.025, 0.054), bronze)
        _part(gun, Vector3(-0.115, 0.10, -0.43 - i * 0.1), Vector3(0.018, 0.025, 0.054), bronze)
    # First-person gloves.
    _part(gun, Vector3(0.13, -0.25, -0.50), Vector3(0.22, 0.20, 0.30), fabric)
    _part(gun, Vector3(-0.08, -0.33, 0.13), Vector3(0.22, 0.22, 0.32), fabric)
    muzzle = MeshInstance3D.new()
    var flash_mesh := SphereMesh.new()
    flash_mesh.radius = 0.16
    flash_mesh.height = 0.25
    muzzle.mesh = flash_mesh
    var flash_mat := StandardMaterial3D.new()
    flash_mat.albedo_color = Color(1.0, 0.85, 0.38)
    flash_mat.emission_enabled = true
    flash_mat.emission = Color(1.0, 0.65, 0.13)
    flash_mat.emission_energy_multiplier = 4.0
    flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    muzzle.material_override = flash_mat
    muzzle.position = Vector3(0, 0.005, -1.52)
    muzzle.visible = false
    gun.add_child(muzzle)

func _physics_process(dt: float) -> void:
    if not is_instance_valid(game) or game.state != 1:
        velocity = Vector3.ZERO
        return
    if invulnerability > 0.0:
        invulnerability -= dt
    var axis: Vector2 = game.hud.move_axis
    if Input.is_key_pressed(KEY_A):
        axis.x -= 1.0
    if Input.is_key_pressed(KEY_D):
        axis.x += 1.0
    if Input.is_key_pressed(KEY_W):
        axis.y -= 1.0
    if Input.is_key_pressed(KEY_S):
        axis.y += 1.0
    axis = axis.limit_length(1.0)
    var movement := global_transform.basis.x * axis.x + global_transform.basis.z * axis.y
    var sprinting: bool = (Input.is_key_pressed(KEY_SHIFT) or game.hud.sprint_held) and axis.y < -0.1
    var speed: float = 8.6 if sprinting else move_speed
    velocity.x = move_toward(velocity.x, movement.x * speed, dt * 33.0)
    velocity.z = move_toward(velocity.z, movement.z * speed, dt * 33.0)
    if not is_on_floor():
        velocity.y -= 23.0 * dt
    else:
        velocity.y = -0.3
        if Input.is_key_pressed(KEY_SPACE):
            velocity.y = 5.8
    move_and_slide()
    var walk_amount: float = Vector2(velocity.x, velocity.z).length()
    step_clock += dt * walk_amount * 1.6
    current_bob = lerpf(current_bob, minf(1.0, walk_amount / 6.0), minf(1.0, dt * 10.0))

func _process(dt: float) -> void:
    if not is_instance_valid(game) or game.state != 1:
        return
    shot_cooldown = maxf(0.0, shot_cooldown - dt)
    hit_confirm = maxf(0.0, hit_confirm - dt)
    damage_flash = maxf(0.0, damage_flash - dt)
    heal_delay = maxf(0.0, heal_delay - dt)
    recoil_amount = maxf(0.0, recoil_amount - dt * 4.5)
    if heal_delay <= 0.0 and health > 0.0:
        health = minf(100.0, health + dt * 3.1)
    if reloading:
        reload_remaining -= dt
        if reload_remaining <= 0:
            finish_reload()
    ads_held = game.hud.ads_held or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
    var target_fov := 52.0 if ads_held else 77.0
    camera.fov = lerpf(camera.fov, target_fov, minf(1.0, dt * 11.0))
    var bob := sin(step_clock * 1.8) * 0.013 * current_bob
    var gun_offset := Vector3(0.36, -0.30, -0.66) if not ads_held else Vector3(0.0, -0.27, -0.55)
    gun.position = gun.position.lerp(gun_offset + Vector3(bob, absf(bob) * 0.4, recoil_amount * 0.13), minf(1.0, dt * 14.0))
    muzzle.visible = shot_cooldown > 0.07 and shot_cooldown < 0.12
    if game.hud.fire_held or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        shoot()
    if ammo == 0 and not reloading:
        reload()

func look(dx: float, dy: float) -> void:
    if not is_instance_valid(game) or game.state != 1:
        return
    rotate_y(-dx * 0.0025)
    camera.rotation.x = clampf(camera.rotation.x - dy * 0.0025, -1.22, 1.22)

func shoot() -> void:
    if shot_cooldown > 0 or reloading or ammo <= 0:
        return
    shot_cooldown = 0.125
    recoil_amount = minf(1.0, recoil_amount + 0.44)
    ammo -= 1
    shoot_count += 1
    camera.rotation.x = clampf(camera.rotation.x + 0.0065, -1.22, 1.22)
    game.sound.play_shot()
    var from := camera.global_position
    var forward := -camera.global_transform.basis.z
    var spread := 0.0032 if ads_held else 0.013
    var rng := RandomNumberGenerator.new()
    rng.seed = int(shoot_count * 173 + Time.get_ticks_msec())
    var direction := (forward
        + camera.global_transform.basis.x * rng.randf_range(-spread, spread)
        + camera.global_transform.basis.y * rng.randf_range(-spread, spread)).normalized()
    var destination := from + direction * 85.0
    var ray := PhysicsRayQueryParameters3D.create(from, destination)
    ray.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(ray)
    if not hit.is_empty():
        destination = hit["position"]
        var target = hit["collider"]
        if target.has_method("take_damage"):
            game.damage_enemy(target, 35.0, destination)
        else:
            game.impact(destination, Color(0.8, 0.73, 0.60), 3)
    _tracer(from + direction * 0.55, destination)

func _tracer(origin: Vector3, target: Vector3) -> void:
    var delta := target - origin
    if delta.length() < 0.1:
        return
    var beam := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = 0.009
    cyl.bottom_radius = 0.009
    cyl.height = delta.length()
    cyl.radial_segments = 4
    beam.mesh = cyl
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("#ffe8ab")
    mat.emission_enabled = true
    mat.emission = Color("#ffad45")
    mat.emission_energy_multiplier = 2.1
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    beam.material_override = mat
    game.world.add_child(beam)
    beam.global_position = origin.lerp(target, 0.5)
    beam.quaternion = Quaternion(Vector3.UP, delta.normalized())
    game.particles.append({"node": beam, "age": 0.0, "lifetime": 0.075, "velocity": Vector3.ZERO})

func reload() -> void:
    if reloading or ammo >= 30 or reserve == 0:
        return
    reloading = true
    reload_remaining = 1.6
    game.sound.play_reload()

func finish_reload() -> void:
    reloading = false
    var required := mini(30 - ammo, reserve)
    ammo += required
    reserve -= required

func take_damage(amount: float) -> void:
    if invulnerability > 0 or health <= 0:
        return
    health = maxf(0.0, health - amount)
    damage_flash = 0.6
    heal_delay = 5.0
    game.sound.play_impact()
