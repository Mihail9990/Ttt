extends SceneTree
## Captures actual running game frames, including the real UI and assets.
func _initialize() -> void:
    call_deferred("_capture")

func _capture() -> void:
    DisplayServer.window_set_size(Vector2i(720, 1440))
    root.content_scale_size = Vector2i(720, 1440)
    root.size = Vector2i(720, 1440)
    var directory := OS.get_environment("LEGION_PREVIEW_DIR")
    if directory.is_empty():
        directory = "."
    var game: Node = load("res://scenes/Main.tscn").instantiate()
    game.test_mode = true
    root.add_child(game)
    await create_timer(2.0).timeout
    root.get_texture().get_image().save_png(directory + "/menu.png")
    game.start_run()
    await create_timer(2.2).timeout
    root.get_texture().get_image().save_png(directory + "/gameplay.png")
    game._offer_choices()
    await create_timer(0.6).timeout
    root.get_texture().get_image().save_png(directory + "/upgrades.png")
    game.phase = game.Phase.PLAY
    game.enemies.clear()
    game._spawn_boss()
    game.boss["hp"] = 2000.0
    game.boss["max_hp"] = 2000.0
    game.boss["z"] = -5.0
    game.world.boss_root.position = Vector3(0, 0, -5)
    game._update_visuals(0)
    await create_timer(0.7).timeout
    root.get_texture().get_image().save_png(directory + "/boss.png")
    print("Saved real game screenshots to preview/")
    quit()
