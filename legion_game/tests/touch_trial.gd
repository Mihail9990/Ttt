extends SceneTree
## Feeds real touch events through the viewport, not directly into the UI method.
func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    root.size = Vector2i(720, 1440)
    var game: Node = load("res://scenes/Main.tscn").instantiate()
    game.test_mode = true
    root.add_child(game)
    await process_frame
    game.set_process(false)
    var ui: Control = game.hud.surface
    ui.size = Vector2(720, 1440)
    ui._process(0)
    await tap(Vector2(300, 1110))
    if game.phase != game.Phase.PLAY:
        printerr("TOUCH FAIL: start button")
        quit(1)
        return
    var down := InputEventScreenTouch.new()
    down.position = Vector2(340, 800)
    down.index = 0
    down.pressed = true
    Input.parse_input_event(down)
    await process_frame
    var drag := InputEventScreenDrag.new()
    drag.index = 0
    drag.position = Vector2(440, 800)
    drag.relative = Vector2(100, 0)
    Input.parse_input_event(drag)
    await process_frame
    var up := InputEventScreenTouch.new()
    up.position = drag.position
    up.index = 0
    up.pressed = false
    Input.parse_input_event(up)
    await process_frame
    if game.target_x < 1.0:
        printerr("TOUCH FAIL: drag, ", game.target_x)
        quit(1)
        return
    await tap(Vector2(645, 70))
    if game.phase != game.Phase.PAUSED:
        printerr("TOUCH FAIL: pause")
        quit(1)
        return
    await tap(Vector2(300, 625))
    if game.phase != game.Phase.PLAY:
        printerr("TOUCH FAIL: resume")
        quit(1)
        return
    print("TOUCH PASS: start, drag, pause and resume through viewport")
    quit()

func tap(position: Vector2) -> void:
    var event := InputEventScreenTouch.new()
    event.position = position
    event.index = 0
    event.pressed = true
    Input.parse_input_event(event)
    await process_frame
    var release := InputEventScreenTouch.new()
    release.position = position
    release.index = 0
    release.pressed = false
    Input.parse_input_event(release)
    await process_frame
