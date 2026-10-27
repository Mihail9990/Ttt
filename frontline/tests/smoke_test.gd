extends SceneTree
## CI sanity test: ensure both missions generate, player/enemies exist, and menu returns.
func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var packed = load("res://scenes/Main.tscn")
    assert(packed != null, "Cannot load Main.tscn")
    var game = packed.instantiate()
    root.add_child(game)
    game.start_mission(0)
    assert(game.player != null, "No player in mission 1")
    assert(game.soldiers.size() > 0, "No enemies in mission 1")
    print("SMOKE_MISSION_1: ", game.soldiers.size(), " enemies")
    game.start_mission(1)
    assert(game.player != null, "No player in mission 2")
    assert(game.soldiers.size() > 0, "No enemies in mission 2")
    print("SMOKE_MISSION_2: ", game.soldiers.size(), " enemies")
    game.back_to_menu()
    print("SMOKE_TEST_OK")
    quit(0)
