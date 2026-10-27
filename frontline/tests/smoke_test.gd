extends SceneTree
## CI sanity test: ensure both missions generate, player/enemies exist, and menu returns.
func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var packed = load("res://scenes/Main.tscn")
    assert(packed != null, "Cannot load Main.tscn")
    var game = packed.instantiate()
    root.add_child(game)
    assert(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch") == false,
        "Touch-to-mouse emulation must be disabled to prevent stray shots")
    for model_path in [
        "res://assets/models/soldier_tactical.glb",
        "res://assets/models/first_person_m4a1.glb",
        "res://assets/models/helicopter.glb",
        "res://assets/models/road_barrier.glb"
    ]:
        assert(load(model_path) is PackedScene, "Missing model asset: " + model_path)
    game.start_mission(0)
    assert(game.player != null, "No player in mission 1")
    assert(game.soldiers.size() > 0, "No enemies in mission 1")
    print("SMOKE_MISSION_1: ", game.soldiers.size(), " enemies")
    # Reproduce the phone bug: a camera swipe should NEVER hold the fire button.
    game.hud._touch_down(11, Vector2(790, 360))
    assert(game.hud.touch_roles.get(11) == "look", "Camera finger became an action")
    assert(not game.hud.fire_held, "A camera touch accidentally triggered firing")
    game.hud._touch_up(11)
    game.hud._touch_down(12, Vector2(1123, 540))
    assert(game.hud.fire_held, "Touching the FIRE button must shoot")
    game.hud._touch_up(12)
    assert(not game.hud.fire_held, "Releasing FIRE must stop shooting")
    print("SMOKE_MOBILE_CONTROLS_OK")
    game.start_mission(1)
    assert(game.player != null, "No player in mission 2")
    assert(game.soldiers.size() > 0, "No enemies in mission 2")
    print("SMOKE_MISSION_2: ", game.soldiers.size(), " enemies")
    game.back_to_menu()
    print("SMOKE_TEST_OK")
    quit(0)
