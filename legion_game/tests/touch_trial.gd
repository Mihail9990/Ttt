extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var game = load("res://scenes/Main.tscn").instantiate()
    game.test_mode = true
    root.add_child(game)
    await process_frame
    game.set_process(false)
    var ui = game.hud.surface
    ui.size = Vector2(720,1440)
    ui._process(0)
    var down := InputEventScreenTouch.new()
    down.position = Vector2(300, 1110)
    down.index = 0
    down.pressed = true
    ui._gui_input(down)
    var up := InputEventScreenTouch.new()
    up.position = down.position
    up.index = 0
    up.pressed = false
    ui._gui_input(up)
    if game.phase != game.Phase.PLAY:
        printerr("TOUCH FAIL: start button")
        quit(1)
        return
    down.position = Vector2(340,800)
    ui._gui_input(down)
    var drag := InputEventScreenDrag.new()
    drag.index = 0
    drag.position = Vector2(440,800)
    drag.relative = Vector2(100,0)
    ui._gui_input(drag)
    up.position = drag.position
    ui._gui_input(up)
    if game.target_x < 1.0:
        printerr("TOUCH FAIL: drag, ", game.target_x)
        quit(1)
        return
    print("TOUCH PASS: play button and one-finger drag")
    quit()
