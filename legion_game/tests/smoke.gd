extends SceneTree
## Run with Godot --headless --path legion_game --script res://tests/smoke.gd
var failures := 0
var game: Node
func check(ok: bool, what: String) -> void:
    if ok:
        print("PASS: ", what)
    else:
        failures += 1
        printerr("FAIL: ", what)

func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var packed := load("res://scenes/Main.tscn") as PackedScene
    game = packed.instantiate()
    game.test_mode = true
    root.add_child(game)
    await process_frame
    game.set_process(false)
    game.profile = {"coins":0,"damage":0,"squad":0,"rate":0,"best":0,"best_kills":0,"runs":0}
    check(game.marines.initialised and game.zombies.initialised, "animated instanced 3D models loaded")
    check(game.marines.visible_count() == 11 and game.zombies.visible_count() == 24, "menu displays squad and horde")
    game.start_run()
    check(game.phase == game.Phase.PLAY and game.squad_count == 14, "new run starts with fourteen fighters")
    check(game.gates.size() == 2 and game.enemies.size() == 48, "initial horde and gate choices spawn")
    game.player_x = -2.0
    for gate in game.gates:
        gate["node"].position.z = 6.7
    game._advance_gates(0.01)
    check(game.gates.is_empty() and game.squad_count == 19, "left gate adds five fighters")
    game.start_run()
    game.player_x = 2.0
    for gate in game.gates:
        gate["node"].position.z = 6.7
    game._advance_gates(0.01)
    check(game.damage > 14.9 and game.squad_count == 14, "right gate increases damage")
    game.enemies = [{"x":0.0,"z":1.0,"hp":1.0,"phase":0.0,"size":1.0}]
    game.player_x = 0.0
    game.fire_accum = 1.0
    game._fire(0.01)
    check(game.kills == 1 and game.enemies.is_empty() and game.earned == 1, "automatic fire defeats enemy and awards coins")
    game._spawn_boss()
    game.boss["hp"] = 1.0
    game.boss["z"] = 1.0
    game.fire_accum = 1.0
    game._fire(0.01)
    check(game.boss.is_empty() and not game.world.boss_root.visible and game.earned == 31, "boss can be defeated for reward")
    game._offer_choices()
    game.select_choice(2)
    check(game.phase == game.Phase.PLAY and game.shield == 6, "choice grants armor and resumes")
    game._offer_choices()
    game.select_choice(1)
    check(game.splash > 0.6, "later upgrade unlocks explosive shots")
    game.enemies = [{"x":0.0,"z":1.0,"hp":1.0,"phase":0.0,"size":1.0}]
    game._splash_damage(Vector3(0, 1, 1))
    check(game.enemies.is_empty(), "explosive rounds damage nearby enemies")
    game._hurt_squad(2)
    check(game.shield == 4 and game.squad_count == 14, "armor absorbs damage")
    game._hurt_squad(20)
    check(game.phase == game.Phase.GAME_OVER and int(game.profile["coins"]) == 32, "defeat banks earned coins")
    game.profile["coins"] = 100
    game.purchase("damage")
    check(int(game.profile["damage"]) == 1 and int(game.profile["coins"]) == 60, "permanent upgrade spends coins once")
    game.purchase("damage")
    check(int(game.profile["damage"]) == 1 and int(game.profile["coins"]) == 60, "purchase denied without enough coins")
    game.save_path = "user://legion_smoke_profile.json"
    game.test_mode = false
    game.save_profile()
    game.profile["coins"] = 0
    game.profile["damage"] = 0
    game._load_profile()
    check(int(game.profile["coins"]) == 60 and int(game.profile["damage"]) == 1, "save file restores permanent progress")
    game.test_mode = true
    game.return_to_menu()
    check(game.phase == game.Phase.MENU and game.marines.visible_count() == 11, "return to menu restores scene")
    game.start_run()
    var peak_enemies := 0
    for frame in range(1000):
        if game.phase == game.Phase.CHOICE:
            game.select_choice(0)
        if game.phase != game.Phase.PLAY:
            break
        game._update_run(0.05)
        peak_enemies = maxi(peak_enemies, game.enemies.size())
    print("SIMULATION: ", int(game.distance), " m, ", game.kills, " kills, peak enemies ", peak_enemies, ", phase ", game.phase)
    check(game.distance > 100.0 and game.kills > 10, "continuous run progresses and kills waves")
    check(peak_enemies <= game.MAX_ENEMIES, "horde respects mobile rendering limit")
    print("SMOKE RESULT: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
    quit(0 if failures == 0 else 1)
