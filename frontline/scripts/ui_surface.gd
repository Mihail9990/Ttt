extends Control
## Branded, responsive, fully drawn 2D overlay. No downloaded assets.
var hud: CanvasLayer

const INK := Color("#081018")
const GOLD := Color("#f5af59")
const WHITE := Color("#f2f4f0")
const MUTED := Color("#b5c3c5")
const GREEN := Color("#77e2ae")
const RED := Color("#ff6963")

func _scale() -> float:
    return minf(size.x / 1280.0, size.y / 720.0)

func _pos(x: float, y: float) -> Vector2:
    return Vector2(x * size.x / 1280.0, y * size.y / 720.0)

func _rect(x: float, y: float, w: float, h: float) -> Rect2:
    var a := _pos(x, y)
    var b := _pos(x + w, y + h)
    return Rect2(a, b - a)

func _text(t: String, x: float, y: float, font_size: int = 23, color: Color = WHITE, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, max_w: float = -1.0) -> void:
    var width := max_w * size.x / 1280.0 if max_w > 0 else -1.0
    draw_string(ThemeDB.fallback_font, _pos(x, y), t, alignment, width, maxi(11, int(float(font_size) * _scale())), color)

func _panel(x: float, y: float, w: float, h: float, color: Color, line: Color) -> void:
    var rect := _rect(x, y, w, h)
    draw_rect(rect, color, true)
    draw_rect(rect, line, false, maxf(1.0, 2.0 * _scale()))

func _draw() -> void:
    if not is_instance_valid(hud) or not is_instance_valid(hud.game):
        return
    var state: int = hud.game.state
    if state == 0:
        _draw_menu()
    elif state == 1:
        _draw_game()
        if hud.paused:
            _draw_pause()
    elif state == 2 or state == 3 or state == 4:
        _draw_end(state)

func _stripe(top_y: float) -> void:
    draw_rect(_rect(0, top_y, 1280, 4), GOLD, true)
    draw_rect(_rect(0, top_y + 4, 1280, 2), Color(0.2, 0.33, 0.39, 0.5), true)

func _draw_backdrop() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), INK, true)
    for i in range(18):
        var y: float = float(i) * 47
        draw_line(_pos(0, y), _pos(1280, y - 280), Color(0.2, 0.29, 0.33, 0.21), maxf(1.0, _scale()))
    draw_circle(_pos(1130, 180), 260 * _scale(), Color(0.84, 0.34, 0.12, 0.055))
    draw_circle(_pos(180, 650), 320 * _scale(), Color(0.05, 0.27, 0.39, 0.14))

func _draw_menu() -> void:
    _draw_backdrop()
    draw_rect(_rect(55, 56, 8, 101), GOLD)
    _text("FRONTLINE", 84, 112, 69, WHITE)
    _text("C O N F L I C T", 87, 150, 27, GOLD)
    _text("ТАКТИЧЕСКИЙ 3D-ШУТЕР / ОДИНОЧНАЯ КАМПАНИЯ", 88, 206, 21, MUTED)
    draw_line(_pos(88, 231), _pos(1190, 231), Color(1,1,1,0.18), maxf(1.0,_scale()))
    _text("ВЫБЕРИ ОПЕРАЦИЮ", 88, 297, 31)
    var first: bool = hud.selected_mission == 0
    _panel(88, 323, 526, 155, Color(0.09,0.14,0.18,0.94), GOLD if first else Color("#465861"))
    _panel(640, 323, 526, 155, Color(0.09,0.14,0.18,0.94), GOLD if not first else Color("#465861"))
    _text("01", 111, 360, 29, GOLD)
    _text("ПРОРЫВ", 168, 365, 30, WHITE)
    _text("Горная база · лес · штурм", 112, 410, 20, MUTED)
    _text("Уничтожьте охрану и захватите связь", 112, 446, 16, Color("#99aaa9"))
    _text("02", 663, 360, 29, GOLD)
    _text("ЭВАКУАЦИЯ", 719, 365, 30, WHITE)
    _text("Разрушенный город · две волны", 664, 410, 20, MUTED)
    _text("Отразите атаку и доберитесь до вертолёта", 664, 446, 16, Color("#99aaa9"))
    _panel(423, 523, 432, 91, Color("#b86c2b"), Color("#f8ba7d"))
    _text("НАЧАТЬ ОПЕРАЦИЮ", 469, 578, 29, WHITE)
    _text("ANDROID  •  3D  •  ОФЛАЙН", 87, 666, 18, Color("#809ba6"))
    _text("Версия прототипа 0.1  /  управление двумя пальцами", 691, 666, 17, MUTED)

func _draw_game() -> void:
    draw_rect(_rect(0, 0, 1280, 92), Color(0.017, 0.031, 0.046, 0.64))
    _stripe(0)
    _text("FRONTLINE / OP %02d" % (hud.game.mission_index + 1), 35, 32, 23, WHITE)
    _text(hud.game.objective(), 35, 69, 20, GOLD)
    var player = hud.game.player
    if not is_instance_valid(player):
        return
    if player.health < 100:
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.54, 0.05, 0.02, 0.05 + player.damage_flash * 0.2))
    var middle := size * 0.5
    var cross_col: Color = RED if player.hit_confirm > 0 else WHITE
    var kick: float = player.recoil_amount * 8.0 * _scale()
    for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
        draw_line(middle + dir * (8 * _scale() + kick), middle + dir * (18 * _scale() + kick), cross_col, 2.0 * _scale(), true)
    draw_circle(middle, 1.6 * _scale(), cross_col)

    # Objective marker: bearing and distance to extraction when accessible.
    var remaining: int = hud.game.living_enemies()
    if remaining == 0:
        var distance := int(player.global_position.distance_to(hud.game.extraction_position))
        _panel(499, 122, 282, 57, Color(0.03,0.10,0.12,0.67), GREEN)
        _text("ЦЕЛЬ: %d М" % distance, 555, 160, 22, GREEN)
    if hud.game.message_time > 0:
        _panel(415, 198, 450, 61, Color(0.02,0.03,0.05,0.85), GOLD)
        _text(hud.game.message, 444, 239, 27, GOLD)

    draw_rect(_rect(25, 646, 250, 64), Color(0,0,0,0.46))
    _text("ЗДОРОВЬЕ", 39, 667, 16, MUTED)
    _text("%03d" % int(player.health), 40, 703, 30, WHITE)
    draw_rect(_rect(125, 681, 130, 9), Color(0.33,0.27,0.27))
    var max_health: float = clampf(player.health / 100.0, 0.0, 1.0)
    draw_rect(_rect(125, 681, 130 * max_health, 9), GREEN if player.health > 30 else RED)
    draw_rect(_rect(967, 631, 290, 79), Color(0,0,0,0.60))
    _text("ШТУРМОВАЯ ВИНТОВКА", 989, 655, 15, MUTED)
    _text("%02d" % player.ammo, 989, 694, 39, WHITE)
    _text("/ %d" % player.reserve, 1072, 691, 23, MUTED)
    if player.reloading:
        _text("ПЕРЕЗАРЯДКА...", 988, 622, 17, GOLD)

    var map_center := _pos(1190, 118)
    var map_radius := 58 * _scale()
    draw_circle(map_center, map_radius, Color(0.02, 0.07, 0.09, 0.75))
    draw_arc(map_center, map_radius, 0, TAU, 64, Color(0.63, 0.80, 0.77, 0.70), maxf(1.0, 1.5 * _scale()))
    draw_line(map_center + Vector2(-map_radius, 0), map_center + Vector2(map_radius, 0), Color(0.4,0.7,0.6,0.25))
    draw_line(map_center + Vector2(0,-map_radius), map_center + Vector2(0,map_radius), Color(0.4,0.7,0.6,0.25))
    draw_circle(map_center, 4 * _scale(), GREEN)
    for enemy in hud.game.soldiers:
        if not is_instance_valid(enemy) or enemy.dead:
            continue
        var rel: Vector3 = enemy.global_position - player.global_position
        var u: float = rel.dot(player.global_transform.basis.x)
        var v: float = -rel.dot(player.global_transform.basis.z)
        var dot_pos := map_center + Vector2(u, -v) * 2.3 * _scale()
        if dot_pos.distance_to(map_center) < map_radius - 5.0 * _scale():
            draw_circle(dot_pos, 3.5 * _scale(), RED)

    if OS.has_feature("mobile"):
        _draw_mobile_controls()

func _draw_mobile_controls() -> void:
    var scl := _scale()
    var base: Vector2 = hud.joystick_anchor if hud.joystick_anchor != Vector2.ZERO and not hud.move_axis.is_zero_approx() else _pos(135, 520)
    draw_circle(base, 76 * scl, Color(0.01,0.03,0.05,0.31))
    draw_arc(base, 76 * scl, 0, TAU, 32, Color(0.65,0.77,0.78,0.42), 2.0 * scl)
    draw_circle(base + hud.move_axis * 48.0 * scl, 31.0 * scl, Color(0.75,0.83,0.80,0.26))
    var fire_center := _pos(1123, 540)
    draw_circle(fire_center, 73.0 * scl, Color(0.86,0.37,0.16,0.55 if hud.fire_held else 0.31))
    draw_arc(fire_center, 73 * scl, 0, TAU, 48, GOLD, 2.0 * scl)
    _text("ОГОНЬ", 1073, 553, 21, WHITE)
    var scope := _pos(845, 601)
    draw_circle(scope, 47.0 * scl, Color(0.05,0.18,0.20,0.48))
    draw_arc(scope, 47 * scl, 0, TAU, 36, Color(0.63,0.86,0.84,0.75), 2.0 * scl)
    _text("ПРИЦЕЛ", 811, 609, 15, WHITE)
    var reload := _pos(1100, 229)
    draw_circle(reload, 41.0 * scl, Color(0.02,0.05,0.07,0.43))
    draw_arc(reload, 41 * scl, 0, TAU, 30, MUTED, 1.5 * scl)
    _text("R", 1091, 240, 26, WHITE)
    _text("БЕГ", 34, 156, 21, Color(0.85,0.93,0.9,0.74))
    _text("II", 604, 37, 22, MUTED)

func _draw_pause() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.01,0.02,0.03,0.79))
    _panel(364, 164, 553, 407, Color("#101d25"), GOLD)
    _text("ПАУЗА", 525, 272, 48, WHITE)
    _text("ПРОДОЛЖИТЬ", 499, 399, 30, GREEN)
    _text("В ГЛАВНОЕ МЕНЮ", 450, 521, 24, MUTED)

func _draw_end(state: int) -> void:
    _draw_backdrop()
    var title := "МИССИЯ ВЫПОЛНЕНА"
    var subtitle := "БАЗА ЗАХВАЧЕНА. СИГНАЛ ПЕРЕДАН."
    var action := "СЛЕДУЮЩАЯ МИССИЯ →"
    if state == 3:
        title = "БОЕЦ ПОГИБ"
        subtitle = "ЗАДАНИЕ НЕ ВЫПОЛНЕНО. ПОПРОБУЙТЕ СНОВА."
        action = "ПОВТОРИТЬ МИССИЮ"
    elif state == 4:
        title = "ОПЕРАЦИЯ ЗАВЕРШЕНА"
        subtitle = "ОБЕ МИССИИ УСПЕШНО ПРОЙДЕНЫ."
        action = "В ГЛАВНОЕ МЕНЮ"
    _panel(165, 150, 950, 417, Color(0.06,0.12,0.15,0.89), GREEN if state != 3 else RED)
    _text("FRONTLINE / CONFLICT", 222, 205, 24, GOLD)
    _text(title, 220, 295, 45, WHITE)
    _text(subtitle, 222, 366, 21, MUTED)
    _text("УБИЙСТВ: %d    /    ВРЕМЯ: %02d:%02d" % [hud.game.player.total_kills, int(hud.game.mission_time / 60), int(hud.game.mission_time) % 60], 222, 424, 23, WHITE)
    _panel(311, 477, 654, 69, Color("#ab642d"), GOLD)
    _text(action, 359, 522, 27, WHITE)
