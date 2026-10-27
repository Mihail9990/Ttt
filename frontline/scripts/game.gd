extends Node3D
## FRONTLINE: CONFLICT - compact offline campaign vertical slice.
## No network access, monetization or account required.

const World = preload("res://scripts/world.gd")
const Soldier = preload("res://scripts/soldier.gd")
const Player = preload("res://scripts/player.gd")
const HUD = preload("res://scripts/hud.gd")
const Sound = preload("res://scripts/sound.gd")

enum Stage { MENU, PLAYING, MISSION_COMPLETE, DEFEAT, CAMPAIGN_COMPLETE }

var state: Stage = Stage.MENU
var mission_index := 0
var world: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var sound: Node
var soldiers: Array = []
var particles: Array = []
var wave := 1
var timer := 0.0
var mission_time := 0.0
var message := ""
var message_time := 0.0
var extraction_position := Vector3.ZERO

func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    sound = Sound.new()
    add_child(sound)
    hud = HUD.new()
    hud.game = self
    add_child(hud)
    hud.refresh()

func start_mission(index: int = -1) -> void:
    if index >= 0:
        mission_index = clampi(index, 0, 1)
    _clear_level()
    world = World.new()
    add_child(world)
    world.generate(mission_index)
    extraction_position = world.extraction_position
    player = Player.new()
    player.game = self
    world.add_child(player)
    player.global_position = world.player_spawn
    soldiers.clear()
    wave = 1
    timer = 0.0
    mission_time = 0.0
    state = Stage.PLAYING
    hud.clear_touches()
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    _spawn_wave(1)
    if mission_index == 0:
        flash_message("ОПЕРАЦИЯ «ПРОРЫВ»", 3.3)
    else:
        flash_message("ОПЕРАЦИЯ «ЭВАКУАЦИЯ»", 3.3)
    hud.refresh()

func _clear_level() -> void:
    if is_instance_valid(world):
        world.free()
    world = null
    player = null
    soldiers.clear()
    particles.clear()

func _spawn_wave(number: int) -> void:
    var locations: Array
    if mission_index == 0:
        locations = [
            Vector3(-4, 1.2, 7), Vector3(6, 1.2, -3),
            Vector3(-7, 1.2, -16), Vector3(8, 1.2, -23),
            Vector3(0, 1.2, -31), Vector3(-5, 1.2, -42)
        ]
    elif number == 1:
        locations = [
            Vector3(-3, 1.2, 3), Vector3(5, 1.2, -6),
            Vector3(-6, 1.2, -18), Vector3(7, 1.2, -28)
        ]
    else:
        locations = [
            Vector3(-9, 1.2, -9), Vector3(10, 1.2, -18),
            Vector3(-5, 1.2, -31), Vector3(5, 1.2, -35),
            Vector3(0, 1.2, -43)
        ]
    for pos in locations:
        var enemy = Soldier.new()
        enemy.game = self
        world.add_child(enemy)
        enemy.global_position = pos
        soldiers.append(enemy)

func living_enemies() -> int:
    var remaining := 0
    for enemy in soldiers:
        if is_instance_valid(enemy) and not enemy.dead:
            remaining += 1
    return remaining

func _process(delta: float) -> void:
    timer += delta
    if message_time > 0:
        message_time -= delta
    for i in range(particles.size() - 1, -1, -1):
        var particle_data: Dictionary = particles[i]
        var node: Node3D = particle_data["node"]
        if not is_instance_valid(node):
            particles.remove_at(i)
            continue
        particle_data["age"] += delta
        node.position += particle_data["velocity"] * delta
        if particle_data["age"] >= particle_data["lifetime"]:
            node.queue_free()
            particles.remove_at(i)
        else:
            particles[i] = particle_data

    if state != Stage.PLAYING:
        return
    mission_time += delta
    if not is_instance_valid(player):
        return
    if player.health <= 0:
        state = Stage.DEFEAT
        sound.play_death()
        hud.clear_touches()
        hud.refresh()
        return

    if mission_index == 0:
        if living_enemies() == 0:
            if player.global_position.distance_to(extraction_position) < 5.0:
                complete_mission()
    elif living_enemies() == 0:
        if wave == 1:
            wave = 2
            _spawn_wave(2)
            flash_message("ПОДКРЕПЛЕНИЕ ПРОТИВНИКА!", 2.8)
        elif player.global_position.distance_to(extraction_position) < 5.0:
            complete_mission()

func objective() -> String:
    if state != Stage.PLAYING:
        return ""
    if mission_index == 0:
        if living_enemies() > 0:
            return "УСТРАНИТЕ ОХРАНУ БАЗЫ: %d" % living_enemies()
        return "ДОБЕРИТЕСЬ ДО АНТЕННЫ СВЯЗИ"
    if living_enemies() > 0:
        return "ОТРАЗИТЕ АТАКУ (%d) • ВОЛНА %d/2" % [living_enemies(), wave]
    return "ДОБЕРИТЕСЬ ДО ТОЧКИ ЭВАКУАЦИИ"

func flash_message(text: String, seconds: float = 2.0) -> void:
    message = text
    message_time = seconds

func complete_mission() -> void:
    hud.clear_touches()
    sound.play_success()
    if mission_index == 0:
        state = Stage.MISSION_COMPLETE
    else:
        state = Stage.CAMPAIGN_COMPLETE
    hud.refresh()

func next_mission() -> void:
    if state == Stage.MISSION_COMPLETE:
        start_mission(1)

func back_to_menu() -> void:
    _clear_level()
    state = Stage.MENU
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    hud.clear_touches()
    hud.refresh()

func damage_enemy(enemy: Node, amount: float, point: Vector3) -> void:
    if not is_instance_valid(enemy) or enemy.dead:
        return
    var killed: bool = enemy.take_damage(amount)
    if is_instance_valid(player):
        player.hit_confirm = 0.24
    impact(point, Color(1.0, 0.66, 0.28), 4)
    sound.play_hit()
    if killed:
        sound.play_kill()
        flash_message("ЦЕЛЬ УСТРАНЕНА", 0.7)

func impact(pos: Vector3, tint: Color, count: int = 5) -> void:
    if not is_instance_valid(world):
        return
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    for _i in range(mini(count, 9)):
        var spark := MeshInstance3D.new()
        var mesh := SphereMesh.new()
        mesh.radius = 0.035
        mesh.height = 0.07
        spark.mesh = mesh
        var mat := StandardMaterial3D.new()
        mat.albedo_color = tint
        mat.emission_enabled = true
        mat.emission = tint
        mat.emission_energy_multiplier = 2.0
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        spark.material_override = mat
        world.add_child(spark)
        spark.global_position = pos
        var vel = Vector3(rng.randf_range(-3.5, 3.5), rng.randf_range(0.3, 4.0), rng.randf_range(-3.5, 3.5))
        particles.append({"node": spark, "age": 0.0, "lifetime": rng.randf_range(0.2, 0.5), "velocity": vel})

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED and state == Stage.PLAYING:
        hud.pause_game()
