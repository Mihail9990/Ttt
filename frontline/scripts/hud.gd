extends CanvasLayer
## Mobile FPS controller: separate finger IDs for movement, camera, fire, ADS and reload.
## Godot touch-to-mouse emulation is disabled in project.godot.
const Painter = preload("res://scripts/ui_surface.gd")

var game: Node3D
var surface: Control
var move_axis := Vector2.ZERO
var fire_held := false
var ads_held := false
var sprint_held := false
var paused := false
var selected_mission := 0
var show_credits := false
var touch_roles: Dictionary = {}
var joystick_anchor := Vector2.ZERO
var joystick_point := Vector2.ZERO
var touch_sensitivity := 1.8

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
    joystick_anchor = Vector2(surface.size.x * 0.106, surface.size.y * 0.72)
    joystick_point = joystick_anchor
    refresh()

func _process(_dt: float) -> void:
    if is_instance_valid(surface):
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
    joystick_point = joystick_anchor
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
        if event.keycode in [KEY_ESCAPE, KEY_P]:
            if game.state == 1:
                pause_game()
                return
        if event.keycode == KEY_R and game.state == 1 and is_instance_valid(game.player):
            game.player.reload()
        if event.keycode == KEY_ENTER and game.state == 0:
            game.start_mission(selected_mission)
            return

    # On Android, exclusively handle InputEventScreenTouch/ScreenDrag.
    # Mouse input can never trigger shooting on a phone.
    if not OS.has_feature("mobile"):
        if event is InputEventMouseMotion:
            if game.state == 1 and not paused and is_instance_valid(game.player):
                game.player.look(event.relative.x, event.relative.y)
        elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            if game.state != 1 or paused:
                _handle_menu_press(event.position)
    if event is InputEventScreenTouch:
        if event.pressed:
            if game.state != 1 or paused:
                _handle_menu_press(event.position)
            else:
                _touch_down(event.index, event.position)
        else:
            _touch_up(event.index)
    elif event is InputEventScreenDrag and game.state == 1 and not paused:
        _touch_drag(event.index, event.position, event.relative)

func _handle_menu_press(pos: Vector2) -> void:
    var w: float = surface.size.x
    var h: float = surface.size.y
    if show_credits:
        show_credits = false
        return
    if paused:
        if pos.y >= h * 0.45 and pos.y < h * 0.68:
            pause_game()
        elif pos.y >= h * 0.68:
            pause_game()
            game.back_to_menu()
        return
    if game.state == 0:
        if pos.y > h * 0.44 and pos.y < h * 0.69:
            selected_mission = 0 if pos.x < w * 0.5 else 1
        elif pos.y > h * 0.70 and pos.y < h * 0.89:
            game.start_mission(selected_mission)
        elif pos.y > h * 0.90:
            show_credits = true
    elif game.state == 2:
        game.next_mission()
    elif game.state == 3:
        game.start_mission(game.mission_index)
    elif game.state == 4:
        game.back_to_menu()

func _hit(pos: Vector2, center_ratio: Vector2, radius: float) -> bool:
    var center := Vector2(center_ratio.x * surface.size.x, center_ratio.y * surface.size.y)
    var pixels := radius * minf(surface.size.x / 1280.0, surface.size.y / 720.0)
    return pos.distance_to(center) <= pixels

func _touch_down(id: int, pos: Vector2) -> void:
    var w: float = surface.size.x
    var h: float = surface.size.y
    # Tapping pause must not fire or rotate camera.
    if pos.y < h * 0.12 and absf(pos.x - w * 0.5) < w * 0.09:
        touch_roles[id] = "pause"
        pause_game()
        return
    # Fire exclusively inside the visible, circular FIRE button.
    if _hit(pos, Vector2(1123.0 / 1280.0, 540.0 / 720.0), 83.0):
        touch_roles[id] = "fire"
        fire_held = true
    elif _hit(pos, Vector2(845.0 / 1280.0, 601.0 / 720.0), 56.0):
        touch_roles[id] = "ads"
        ads_held = true
    elif _hit(pos, Vector2(1100.0 / 1280.0, 229.0 / 720.0), 49.0):
        touch_roles[id] = "reload"
        if is_instance_valid(game.player):
            game.player.reload()
    elif _hit(pos, Vector2(72.0 / 1280.0, 146.0 / 720.0), 57.0):
        touch_roles[id] = "sprint"
        sprint_held = true
    elif pos.x < w * 0.39 and pos.y > h * 0.35:
        touch_roles[id] = "move"
        joystick_anchor = Vector2(w * (135.0 / 1280.0), h * (520.0 / 720.0))
        joystick_point = pos
        move_axis = ((pos - joystick_anchor) / (h * 0.16)).limit_length(1.0)
    elif pos.x >= w * 0.39:
        touch_roles[id] = "look"
    else:
        touch_roles[id] = "none"

func _touch_drag(id: int, pos: Vector2, relative: Vector2) -> void:
    if not touch_roles.has(id):
        return
    match touch_roles[id]:
        "move":
            joystick_point = pos
            move_axis = ((pos - joystick_anchor) / (surface.size.y * 0.16)).limit_length(1.0)
        "look":
            if is_instance_valid(game.player):
                game.player.look(relative.x * touch_sensitivity, relative.y * touch_sensitivity)

func _touch_up(id: int) -> void:
    if not touch_roles.has(id):
        return
    match touch_roles[id]:
        "move":
            move_axis = Vector2.ZERO
            joystick_point = joystick_anchor
        "fire":
            fire_held = false
        "ads":
            ads_held = false
        "sprint":
            sprint_held = false
    touch_roles.erase(id)
