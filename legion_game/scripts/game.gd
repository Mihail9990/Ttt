extends Node3D
## A complete offline run: swipe to steer, pick a gate, survive the horde.
const WorldScript = preload("res://scripts/world.gd")
const CrowdScript = preload("res://scripts/crowd_batch.gd")
const SoundScript = preload("res://scripts/sound.gd")
const HudScript = preload("res://scripts/hud.gd")
const MAX_SQUAD := 60
const MAX_ENEMIES := 110
const ROAD_SPEED := 7.5
const SAVE_PATH := "user://legion_profile.json"

enum Phase { MENU, PLAY, CHOICE, GAME_OVER, SHOP, PAUSED, CREDITS }
var phase := Phase.MENU
var world: Node3D
var marines: Node3D
var zombies: Node3D
var sound: Node
var hud: CanvasLayer
var rng := RandomNumberGenerator.new()
var profile := {"coins": 0, "damage": 0, "squad": 0, "rate": 0, "best": 0, "best_kills": 0, "runs": 0}
var enemies: Array = []
var squad_visual: Array = []
var shots: Array = []
var sparks: Array = []
var gates: Array = []
var choices: Array = []
var distance := 0.0
var elapsed := 0.0
var squad_count := 14
var player_x := 0.0
var target_x := 0.0
var damage := 12.0
var rate := 1.0
var shield := 0
var splash := 0.0
var shot_number := 0
var choice_round := 0
var kills := 0
var earned := 0
var combo := 0
var combo_timer := 0.0
var fire_accum := 0.0
var spawn_timer := 0.0
var next_gate := 0.0
var next_boss := 0.0
var next_choice := 0
var boss: Dictionary = {}
var toast_message := ""
var toast_time := 0.0
var camera_shake := 0.0
var shot_audio_timer := 0.0
var test_mode := false
var save_path := SAVE_PATH
var previous_phase := Phase.MENU

func _ready() -> void:
    rng.randomize()
    _load_profile()
    world = WorldScript.new()
    world.name = "World"
    add_child(world)
    world.build()
    marines = CrowdScript.new()
    marines.name = "Squad"
    add_child(marines)
    marines.setup("res://assets/models/marine_poses.glb", MAX_SQUAD)
    zombies = CrowdScript.new()
    zombies.name = "Horde"
    add_child(zombies)
    zombies.setup("res://assets/models/zombie_poses.glb", MAX_ENEMIES, true)
    sound = SoundScript.new()
    add_child(sound)
    hud = HudScript.new()
    add_child(hud)
    hud.setup(self)
    _make_menu_scene()

func _load_profile() -> void:
    if not FileAccess.file_exists(save_path):
        return
    var f := FileAccess.open(save_path, FileAccess.READ)
    if f == null:
        return
    var data = JSON.parse_string(f.get_as_text())
    if data is Dictionary:
        for key in profile.keys():
            if data.has(key):
                profile[key] = maxi(0, int(data[key]))

func save_profile() -> void:
    if test_mode:
        return
    var f := FileAccess.open(save_path, FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(profile))

func _make_menu_scene() -> void:
    squad_count = 11
    player_x = 0
    target_x = 0
    enemies.clear()
    for row in range(3):
        for col in range(8):
            enemies.append({"x": (col - 3.5) * 1.4, "z": -13.0 - row * 1.7, "hp": 25.0, "phase": float((row * 3 + col) % 6), "size": 1.0})
    _update_visuals(0.0)

func start_run() -> void:
    for gate in gates:
        if is_instance_valid(gate["node"]):
            gate["node"].queue_free()
    gates.clear()
    enemies.clear()
    shots.clear()
    sparks.clear()
    world.boss_root.visible = false
    boss = {}
    distance = 0.0
    elapsed = 0.0
    player_x = 0.0
    target_x = 0.0
    squad_count = mini(MAX_SQUAD, 14 + 2 * int(profile["squad"]))
    damage = 12.0 * (1.0 + float(profile["damage"]) * 0.14)
    rate = 1.0 + float(profile["rate"]) * 0.12
    shield = 0
    splash = 0.0
    shot_number = 0
    choice_round = 0
    kills = 0
    earned = 0
    combo = 0
    combo_timer = 0.0
    fire_accum = 0.0
    spawn_timer = 1.8
    next_gate = 68.0
    next_boss = 210.0
    next_choice = 45
    toast_message = ""
    toast_time = 0
    phase = Phase.PLAY
    _spawn_wave(true)
    _spawn_gates(-15.0)
    _update_visuals(0.0)

func _process(delta: float) -> void:
    var dt := minf(delta, 0.08)
    shot_audio_timer = maxf(0.0, shot_audio_timer - dt)
    if phase == Phase.PLAY:
        _update_run(dt)
    elif phase == Phase.MENU:
        world.advance(dt, 2.0)
        marines.show_units(squad_visual, dt)
        zombies.show_units(enemies, dt)
    elif phase == Phase.GAME_OVER:
        world.advance(dt, 0.0)
        _age_effects(dt)
        world.draw_effects(shots, sparks)
    if toast_time > 0:
        toast_time -= dt
        if toast_time <= 0:
            toast_message = ""
    camera_shake = maxf(0.0, camera_shake - dt * 3.5)

func _update_run(dt: float) -> void:
    elapsed += dt
    distance += ROAD_SPEED * dt
    var axis := Input.get_axis("ui_left", "ui_right")
    if axis != 0:
        target_x = clampf(target_x + axis * 8.0 * dt, -5.15, 5.15)
    player_x = lerpf(player_x, target_x, minf(1.0, dt * 9.0))
    world.advance(dt, ROAD_SPEED, camera_shake)
    combo_timer -= dt
    if combo_timer <= 0:
        combo = 0
    spawn_timer -= dt
    if spawn_timer <= 0.0:
        _spawn_wave(false)
        spawn_timer = maxf(1.25, 2.65 - distance / 900.0)
    if distance >= next_gate:
        _spawn_gates(-38.0)
        next_gate += 75.0
    if distance >= next_boss and boss.is_empty():
        _spawn_boss()
        next_boss += 240.0
    _advance_gates(dt)
    _advance_enemies(dt)
    if phase != Phase.PLAY:
        return
    _advance_boss(dt)
    _fire(dt)
    _age_effects(dt)
    _update_visuals(dt)
    world.draw_effects(shots, sparks)
    if kills >= next_choice:
        next_choice += 55
        _offer_choices()

func _spawn_wave(first: bool) -> void:
    var wave_size := 48 if first else mini(38, 21 + int(distance / 90.0) * 2)
    wave_size = mini(wave_size, MAX_ENEMIES - enemies.size())
    var columns := 10 if first else 9
    var start_z := -22.0 if first else -37.0
    for i in range(wave_size):
        var col := i % columns
        var row := int(i / columns)
        var x := (float(col) - (float(columns) - 1.0) * 0.5) * (1.25 if first else 1.45) + rng.randf_range(-0.12, 0.12)
        enemies.append({"x": x, "z": start_z - float(row) * 1.35 - rng.randf_range(0.0, 0.4), "hp": 23.0 + distance * 0.025, "phase": rng.randf_range(0, 6), "size": rng.randf_range(0.95, 1.08)})

func _advance_enemies(dt: float) -> void:
    for i in range(enemies.size() - 1, -1, -1):
        var e: Dictionary = enemies[i]
        e["z"] = float(e["z"]) + (ROAD_SPEED + 1.5) * dt
        if float(e["z"]) > 7.4:
            var hit_x := float(e["x"])
            enemies.remove_at(i)
            if absf(hit_x - player_x) < 3.8:
                _hurt_squad(1)
                if phase != Phase.PLAY:
                    return

func _spawn_gates(z: float) -> void:
    var rounds := [
        [{"kind":"squad", "value":5, "label":"+5\nБОЙЦОВ"}, {"kind":"damage", "value":0.25, "label":"+25%\nУРОН"}],
        [{"kind":"squad", "value":8, "label":"+8\nБОЙЦОВ"}, {"kind":"rate", "value":0.3, "label":"+30%\nСКОРОСТЬ"}],
        [{"kind":"shield", "value":5, "label":"+5\nБРОНЯ"}, {"kind":"squad", "value":6, "label":"+6\nБОЙЦОВ"}],
        [{"kind":"damage", "value":0.35, "label":"+35%\nУРОН"}, {"kind":"squad", "value":9, "label":"+9\nБОЙЦОВ"}]
    ]
    var options: Array = rounds[int(distance / 75.0) % rounds.size()]
    for i in range(2):
        var option: Dictionary = options[i].duplicate()
        option["side"] = -1 if i == 0 else 1
        option["node"] = world.make_gate(-3.9 if i == 0 else 3.9, z, option["label"], false)
        gates.append(option)

func _advance_gates(dt: float) -> void:
    if gates.is_empty():
        return
    for g in gates:
        g["node"].position.z += ROAD_SPEED * dt
    # Gates always appear in pairs. Test crossing once, then clear both.
    if is_instance_valid(gates[0]["node"]) and gates[0]["node"].position.z >= 6.6:
        var selected: Dictionary = gates[0] if player_x < 0.0 else gates[1]
        _apply_upgrade(selected)
        sound.play("gate")
        for g in gates:
            if is_instance_valid(g["node"]):
                g["node"].queue_free()
        gates.clear()

func _apply_upgrade(option: Dictionary) -> void:
    match str(option["kind"]):
        "squad":
            var before := squad_count
            squad_count = mini(MAX_SQUAD, squad_count + int(option["value"]))
            _notice("+%d БОЙЦОВ" % (squad_count - before))
        "damage":
            damage *= 1.0 + float(option["value"])
            _notice("ОГНЕВАЯ МОЩЬ ↑")
        "rate":
            rate *= 1.0 + float(option["value"])
            _notice("СКОРОСТРЕЛЬНОСТЬ ↑")
        "shield":
            shield += int(option["value"])
            _notice("БРОНЯ +%d" % int(option["value"]))
        "splash":
            splash += float(option["value"])
            _notice("ВЗРЫВНЫЕ ПАТРОНЫ ↑")

func _spawn_boss() -> void:
    var hp := 420.0 + distance * 1.1
    boss = {"hp":hp, "max_hp":hp, "x":0.0, "z":-32.0, "attack":2.0}
    world.boss_root.visible = true
    world.boss_root.position = Vector3(0, 0, -32)
    _notice("ВНИМАНИЕ: ГРОМИЛА")
    sound.play("boss")

func _advance_boss(dt: float) -> void:
    if boss.is_empty():
        return
    boss["z"] = minf(-1.0, float(boss["z"]) + (ROAD_SPEED - 1.0) * dt)
    boss["x"] = move_toward(float(boss["x"]), player_x * 0.65, dt * 1.0)
    world.boss_root.position = Vector3(float(boss["x"]), 0, float(boss["z"]))
    if float(boss["z"]) >= -1.01:
        boss["attack"] = float(boss["attack"]) - dt
        if float(boss["attack"]) <= 0:
            boss["attack"] = 2.3
            _hurt_squad(2 if absf(float(boss["x"]) - player_x) < 3.3 else 1)

func _fire(dt: float) -> void:
    fire_accum = minf(14.0, fire_accum + dt * float(squad_count) * 1.35 * rate)
    var attempts := mini(12, int(fire_accum))
    if attempts <= 0:
        return
    for unused in range(attempts):
        var target_index := -1
        var best_z := -1000.0
        for i in range(enemies.size()):
            var e: Dictionary = enemies[i]
            if absf(float(e["x"]) - player_x) < 5.0 and float(e["z"]) > best_z:
                best_z = float(e["z"])
                target_index = i
        var shoot_boss := not boss.is_empty() and float(boss["z"]) > best_z
        if target_index == -1 and not shoot_boss:
            fire_accum = minf(fire_accum, 1.0)
            break
        fire_accum -= 1.0
        var origin := Vector3(player_x + rng.randf_range(-1.6, 1.6), 1.3, 7.0 + rng.randf_range(0, 1.0))
        var destination := Vector3.ZERO
        if shoot_boss:
            destination = Vector3(float(boss["x"]) + rng.randf_range(-1.0, 1.0), rng.randf_range(1.4, 3.2), float(boss["z"]))
            boss["hp"] = float(boss["hp"]) - damage
            if float(boss["hp"]) <= 0:
                earned += 30
                kills += 1
                boss = {}
                world.boss_root.visible = false
                camera_shake = 1.2
                _notice("ГРОМИЛА ПОВЕРЖЕН  +30")
                sound.play("upgrade")
        else:
            var e: Dictionary = enemies[target_index]
            destination = Vector3(float(e["x"]), 1.0, float(e["z"]))
            e["hp"] = float(e["hp"]) - damage
            if float(e["hp"]) <= 0:
                enemies.remove_at(target_index)
                _credit_kill()
        shot_number += 1
        if splash > 0.0 and shot_number % 4 == 0:
            _splash_damage(destination)
        shots.append({"from":origin,"to":destination,"age":0.0,"life":0.14})
        if sparks.size() < 80:
            sparks.append({"pos":destination,"age":0.0,"life":0.18,"size":rng.randf_range(0.7, 1.6)})
        if shot_audio_timer <= 0:
            sound.play("shot", -20.0)
            shot_audio_timer = 0.10

func _credit_kill() -> void:
    kills += 1
    combo += 1
    combo_timer = 2.0
    earned += 1 + (1 if combo >= 20 and combo % 5 == 0 else 0)
    if combo == 10 or combo == 25 or combo == 50:
        _notice("СЕРИЯ ×%d" % combo)

func _splash_damage(center: Vector3) -> void:
    if sparks.size() < 80:
        sparks.append({"pos":center, "age":0.0, "life":0.30, "size":3.2})
    for i in range(enemies.size() - 1, -1, -1):
        var enemy: Dictionary = enemies[i]
        var separation := Vector2(float(enemy["x"]) - center.x, float(enemy["z"]) - center.z)
        if separation.length_squared() <= 3.24:
            enemy["hp"] = float(enemy["hp"]) - damage * splash
            if float(enemy["hp"]) <= 0:
                enemies.remove_at(i)
                _credit_kill()

func _hurt_squad(amount: int) -> void:
    var absorbed := mini(shield, amount)
    shield -= absorbed
    amount -= absorbed
    if amount > 0:
        squad_count = maxi(0, squad_count - amount)
    camera_shake = 0.65
    sound.play("damage", -11.0)
    if squad_count <= 0:
        finish_run()

func _age_effects(dt: float) -> void:
    for items in [shots, sparks]:
        for i in range(items.size() - 1, -1, -1):
            items[i]["age"] = float(items[i]["age"]) + dt
            if float(items[i]["age"]) >= float(items[i]["life"]):
                items.remove_at(i)

func _update_visuals(dt: float) -> void:
    squad_visual.clear()
    var cols := mini(9, maxi(1, int(ceil(sqrt(float(squad_count) * 1.5)))))
    for i in range(squad_count):
        var col := i % cols
        var row := int(i / cols)
        squad_visual.append({"x":player_x + (float(col) - (float(cols) - 1.0) * 0.5) * 0.62, "z":(-2.0 if phase == Phase.MENU else 7.0) + float(row) * 0.65, "phase":float(i % 6), "size":1.0, "yaw":PI})
    marines.show_units(squad_visual, dt)
    zombies.show_units(enemies, dt)

func _offer_choices() -> void:
    if choice_round % 2 == 0:
        choices = [
            {"kind":"squad", "value":7, "title":"ПОДКРЕПЛЕНИЕ", "description":"+7 бойцов в отряд", "icon":"+"},
            {"kind":"damage", "value":0.30, "title":"ТЯЖЁЛЫЕ ПАТРОНЫ", "description":"+30% к урону", "icon":"✦"},
            {"kind":"shield", "value":6, "title":"БРОНЯ ОТРЯДА", "description":"Поглощает 6 атак", "icon":"◆"}
        ]
    else:
        choices = [
            {"kind":"rate", "value":0.35, "title":"СКОРОСТРЕЛЬНОСТЬ", "description":"+35% к темпу огня", "icon":"»"},
            {"kind":"splash", "value":0.65, "title":"ВЗРЫВНЫЕ ПАТРОНЫ", "description":"Каждый 4-й выстрел бьёт по площади", "icon":"✹"},
            {"kind":"squad", "value":9, "title":"РЕЗЕРВНЫЙ ОТРЯД", "description":"+9 бойцов в отряд", "icon":"+"}
        ]
    choice_round += 1
    phase = Phase.CHOICE
    sound.play("upgrade")

func select_choice(index: int) -> void:
    if phase != Phase.CHOICE or index < 0 or index >= choices.size():
        return
    _apply_upgrade(choices[index])
    phase = Phase.PLAY
    sound.play("upgrade")

func _notice(message: String) -> void:
    toast_message = message
    toast_time = 2.0

func finish_run() -> void:
    if phase != Phase.PLAY:
        return
    phase = Phase.GAME_OVER
    profile["coins"] = int(profile["coins"]) + earned
    profile["best"] = maxi(int(profile["best"]), int(distance))
    profile["best_kills"] = maxi(int(profile["best_kills"]), kills)
    profile["runs"] = int(profile["runs"]) + 1
    save_profile()
    sound.play("end")

func purchase(kind: String) -> void:
    if not kind in ["damage", "squad", "rate"]:
        return
    var level := int(profile[kind])
    var cost := upgrade_cost(kind)
    if level >= 20 or int(profile["coins"]) < cost:
        sound.play("damage", -18.0)
        return
    profile["coins"] = int(profile["coins"]) - cost
    profile[kind] = level + 1
    save_profile()
    sound.play("upgrade")

func upgrade_cost(kind: String) -> int:
    return int(40 + int(profile[kind]) * 35 + int(profile[kind]) * int(profile[kind]) * 8)

func return_to_menu() -> void:
    phase = Phase.MENU
    for gate in gates:
        if is_instance_valid(gate["node"]):
            gate["node"].queue_free()
    gates.clear()
    boss = {}
    world.boss_root.visible = false
    shots.clear()
    sparks.clear()
    world.draw_effects(shots, sparks)
    _make_menu_scene()
