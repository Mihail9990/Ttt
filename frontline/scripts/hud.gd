extends CanvasLayer
## Screen-safe mobile controller, menus, pause and HUD state.
const Painter = preload("res://scripts/ui_surface.gd")
var game: Node3D
var surface: Control
var move_axis := Vector2.ZERO
var fire_held := false
var ads_held := false
var sprint_held := false
var paused := false
var selected_mission := 0
var touch_roles: Dictionary = {}
var joystick_anchor := Vector2.ZERO
var joystick_point := Vector2.ZERO

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    surface = Painter.new()
    surface.hud = self
    add_child(surface)
    surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
    get_viewport().size_changed.connect(_on_resized)
    _on_resized()

func _on_resized() -> void:
    surface.position = Vector2.ZERO
    surface.size = get_viewport().get_visible_rect().size
    refresh()

func _process(_dt: float) -> void:
    if surface:
        surface.queue_redraw()

func refresh() -> void:
    if is_instance_valid(surface):
        surface.queue_redraw()

func clear_touches() -> void:
    move_axis = Vector2.ZERO
    fire_held = false
    ads_held = false
    sprint_held = false
    touch_roles.clear()
    if paused:
        paused = false
        get_tree().paused = false

func pause_game() -> void:
    if game.state != 1:
        return
    paused = not paused
    if paused:
        fire_held = false
        ads_held = false
        move_axis = Vector2.ZERO
        touch_roles.clear()
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    elif not OS.has_feature("mobile"):
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    get_tree().paused = paused
    refresh()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
            if game.state == 1:
                pause_game()
                return
        if event.keycode == KEY_R and game.state == 1 and is_instance_valid(game.player):
            game.player.reload()
        if event.keycode == KEY_ENTER and game.state == 0:
            game.start_mission(selected_mission)
            return

    if event is InputEventMouseMotion and not OS.has_feature("mobile"):
        if game.state == 1 and not paused and is_instance_valid(game.player):
            game.player.look(event.relative.x, event.relative.y)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if game.state != 1 or paused:
            _handle_menu_press(event.position)
    elif event is InputEventScreenTouch:
        if event.pressed:
            if game.state != 1 or paused:
                _handle_menu_press(event.position)
                return
            _touch_down(event.index, event.position)
        else:
            _touch_up(event.index)
    elif event is InputEventScreenDrag and game.state == 1 and not paused:
        _touch_drag(event.index, event.position, event.relative)

func _handle_menu_press(pos: Vector2) -> void:
    var sz = surface.size
    var w: float = sz.x
    var h: float = sz.y
    if paused:
        if pos.y > h * 0.53 and pos.y < h * 0.75:
            pause_game()
        elif pos.y >= h * 0.75:
            pause_game()
            game.back_to_menu()
        return
    if game.state == 0:
        if pos.y > h * 0.44 and pos.y < h * 0.70:
            selected_mission = 0 if pos.x < w * 0.5 else 1
            refresh()
        elif pos.y > h * 0.70:
            game.start_mission(selected_mission)
    elif game.state == 2:
        game.next_mission()
    elif game.state == 3:
        game.start_mission(game.mission_index)
    elif game.state == 4:
        game.back_to_menu()

func _touch_down(id: int, pos: Vector2) -> void:
    var w: float = surface.size.x
    var h: float = surface.size.y
    if pos.x < w * 0.40 and pos.y > h * 0.42:
        touch_roles[id] = "move"
        joystick_anchor = pos
        joystick_point = pos
    elif pos.x > w * 0.77 and pos.y > h * 0.46:
        touch_roles[id] = "fire"
        fire_held = true
    elif pos.x > w * 0.74 and pos.y < h * 0.34:
        touch_roles[id] = "reload"
        if is_instance_valid(game.player):
            game.player.reload()
    elif pos.x > w * 0.58 and pos.y > h * 0.62:
        touch_roles[id] = "ads"
        ads_held = true
    elif pos.x < w * 0.52 and pos.y < h * 0.31:
        touch_roles[id] = "sprint"
        sprint_held = true
    else:
        touch_roles[id] = "look"

func _touch_drag(id: int, pos: Vector2, relative: Vector2) -> void:
    if not touch_roles.has(id):
        return
    match touch_roles[id]:
        "move":
            joystick_point = pos
            move_axis = ((pos - joystick_anchor) / (surface.size.y * 0.16)).limit_length(1.0)
        "look":
            if is_instance_valid(game.player):
                game.player.look(relative.x * 1.18, relative.y * 1.18)

func _touch_up(id: int) -> void:
    if not touch_roles.has(id):
        return
    match touch_roles[id]:
        "move":
            move_axis = Vector2.ZERO
        "fire":
            fire_held = false
        "ads":
            ads_held = false
        "sprint":
            sprint_held = false
    touch_roles.erase(id)
