extends Control
## UI is drawn at a 720 x 1440 design size and scales to any portrait screen.
var game: Node
var font: Font
var time := 0.0
var scale_factor := 1.0
var offset := Vector2.ZERO
var dragging := false
var pressed_on_pause := false
var pointer_index := -1
const C_WHITE := Color("#f6f4e9")
const C_MUTED := Color("#a5bac0")
const C_CYAN := Color("#54e1e0")
const C_ORANGE := Color("#ffb54b")
const C_RED := Color("#fb6854")
const C_DARK := Color("#101e27")

func _ready() -> void:
    font = ThemeDB.fallback_font
    set_process(true)

func _process(dt: float) -> void:
    time += dt
    scale_factor = minf(size.x / 720.0, size.y / 1440.0)
    offset = (size - Vector2(720, 1440) * scale_factor) * 0.5
    queue_redraw()

func _draw() -> void:
    if game == null or font == null:
        return
    draw_set_transform(offset, 0, Vector2.ONE * scale_factor)
    match game.phase:
        game.Phase.MENU: _menu()
        game.Phase.PLAY: _play()
        game.Phase.CHOICE:
            _play()
            _choice()
        game.Phase.GAME_OVER: _game_over()
        game.Phase.SHOP: _shop()
        game.Phase.PAUSED:
            _play()
            _pause()
        game.Phase.CREDITS: _credits()
    draw_set_transform(Vector2.ZERO)

func _box(rect: Rect2, color: Color, radius: int = 14, border: Color = Color.TRANSPARENT, width: int = 0) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(radius)
    if width > 0:
        style.border_color = border
        style.set_border_width_all(width)
    draw_style_box(style, rect)

func _text(content: String, position: Vector2, size_px: int, color: Color = C_WHITE, width: float = -1, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
    draw_string(font, position, content, align, width, size_px, color)

func _center(content: String, y: float, size_px: int, color: Color = C_WHITE) -> void:
    _text(content, Vector2(0, y), size_px, color, 720, HORIZONTAL_ALIGNMENT_CENTER)

func _button(rect: Rect2, label: String, primary: bool = true, sub: String = "") -> void:
    var fill := C_ORANGE if primary else Color(0.07, 0.15, 0.19, 0.95)
    var ink := Color("#172328") if primary else C_WHITE
    var border := Color("#ffd182") if primary else Color("#50666b")
    _box(rect, fill, 12, border, 2)
    _text(label, Vector2(rect.position.x, rect.position.y + (51 if sub.is_empty() else 42)), 29, ink, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    if not sub.is_empty():
        _text(sub, Vector2(rect.position.x, rect.position.y + 70), 18, ink, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _veil(alpha: float = 0.77) -> void:
    draw_rect(Rect2(0, 0, 720, 1440), Color(0.015, 0.035, 0.045, alpha))

func _top_label(label: String, y: float) -> void:
    _text(label, Vector2(48, y), 18, C_CYAN)
    draw_line(Vector2(48, y + 18), Vector2(672, y + 18), Color(C_CYAN, 0.35), 2)

func _menu() -> void:
    draw_rect(Rect2(0, 0, 720, 410), Color(0.01, 0.025, 0.04, 0.72))
    _text("ПОСЛЕДНЯЯ ЛИНИЯ ОБОРОНЫ", Vector2(48, 76), 17, C_CYAN)
    _text("LEGION", Vector2(42, 163), 84, C_WHITE)
    _text("RUSH", Vector2(42, 245), 92, C_ORANGE)
    _text("ВЕДИ ОТРЯД. ВЫЖИВИ. СТАНЬ СИЛЬНЕЕ.", Vector2(48, 293), 18, C_WHITE)
    _box(Rect2(43, 326, 235, 43), Color(0.05, 0.14, 0.17, 0.9), 8, Color(C_CYAN, 0.55), 1)
    _text("ОДНА ЖИЗНЬ • ОДИН ОТРЯД", Vector2(56, 354), 14, C_CYAN)
    _box(Rect2(35, 961, 650, 421), Color(0.025, 0.06, 0.075, 0.94), 18, Color(0.36, 0.46, 0.46, 0.6), 1)
    _text("НОВЫЙ ЗАБЕГ", Vector2(62, 1010), 20, C_CYAN)
    _text("Уничтожай волну за волной", Vector2(62, 1046), 25, C_WHITE)
    _button(Rect2(62, 1080, 596, 88), "В БОЙ  →")
    _button(Rect2(62, 1183, 596, 84), "УЛУЧШЕНИЯ   •   %d ◈" % int(game.profile["coins"]), false)
    _text("РЕКОРД  %d М" % int(game.profile["best"]), Vector2(64, 1312), 18, C_MUTED)
    _text("ОБ ИГРЕ", Vector2(497, 1312), 18, C_MUTED)
    _text("АВТОМАТИЧЕСКИЙ ОГОНЬ  /  УПРАВЛЕНИЕ ОДНИМ ПАЛЬЦЕМ", Vector2(62, 1354), 12, Color(C_MUTED, 0.8))

func _play() -> void:
    _box(Rect2(20, 26, 680, 110), Color(0.035, 0.08, 0.10, 0.91), 14, Color(0.38, 0.53, 0.52, 0.55), 1)
    _text("ОТРЯД", Vector2(42, 59), 15, C_MUTED)
    _text("%02d" % game.squad_count, Vector2(41, 109), 47, C_WHITE)
    _text("БОЙЦОВ", Vector2(111, 106), 14, C_CYAN)
    draw_line(Vector2(220, 45), Vector2(220, 115), Color(0.35, 0.47, 0.47, 0.55), 2)
    _text("ДИСТАНЦИЯ", Vector2(245, 59), 15, C_MUTED)
    _text("%d М" % int(game.distance), Vector2(245, 105), 35, C_WHITE)
    draw_line(Vector2(421, 45), Vector2(421, 115), Color(0.35, 0.47, 0.47, 0.55), 2)
    _text("ЗАБЕГ", Vector2(445, 59), 15, C_MUTED)
    _text("◈ %d" % game.earned, Vector2(445, 103), 29, C_ORANGE)
    _box(Rect2(618, 43, 60, 72), Color(0.18, 0.25, 0.26, 0.9), 8)
    _text("Ⅱ", Vector2(618, 92), 30, C_WHITE, 60, HORIZONTAL_ALIGNMENT_CENTER)
    if game.shield > 0:
        _box(Rect2(25, 150, 155, 40), Color(0.02, 0.16, 0.20, 0.88), 8, Color(C_CYAN, 0.5), 1)
        _text("◆  БРОНЯ %d" % game.shield, Vector2(37, 177), 16, C_CYAN)
    if not game.boss.is_empty():
        _box(Rect2(115, 164, 490, 53), Color(0.07, 0.06, 0.06, 0.92), 8)
        _text("ГРОМИЛА", Vector2(128, 187), 16, C_WHITE)
        draw_rect(Rect2(128, 196, 464, 8), Color(0.3, 0.14, 0.13))
        draw_rect(Rect2(128, 196, 464 * clampf(float(game.boss["hp"]) / float(game.boss["max_hp"]), 0, 1), 8), C_RED)
    if game.combo >= 5:
        _text("СЕРИЯ ×%d" % game.combo, Vector2(475, 182), 21, C_ORANGE)
    if not game.toast_message.is_empty():
        _box(Rect2(115, 249, 490, 65), Color(0.035, 0.10, 0.11, 0.9), 9, Color(C_CYAN, 0.6), 1)
        _text(game.toast_message, Vector2(115, 292), 23, C_WHITE, 490, HORIZONTAL_ALIGNMENT_CENTER)
    if game.elapsed < 8.0:
        _box(Rect2(114, 1300, 492, 72), Color(0.02, 0.06, 0.07, 0.78), 12)
        _text("←  ВЕДИ ОТРЯД ПАЛЬЦЕМ  →", Vector2(114, 1344), 20, C_WHITE, 492, HORIZONTAL_ALIGNMENT_CENTER)

func _choice() -> void:
    _veil(0.80)
    _center("ВЫБЕРИ УСИЛЕНИЕ", 348, 38)
    _center("Останется до конца забега", 388, 20, C_MUTED)
    for i in range(3):
        var y := 435.0 + float(i) * 155.0
        var option: Dictionary = game.choices[i]
        _box(Rect2(60, y, 600, 132), Color(0.07, 0.15, 0.18, 0.98), 12, Color(C_CYAN, 0.55), 2)
        _box(Rect2(78, y + 20, 85, 90), Color(0.07, 0.28, 0.29, 0.9), 9)
        _text(str(option["icon"]), Vector2(78, y + 81), 43, C_CYAN, 85, HORIZONTAL_ALIGNMENT_CENTER)
        _text(str(option["title"]), Vector2(183, y + 51), 22, C_WHITE)
        _text(str(option["description"]), Vector2(183, y + 88), 19, C_MUTED)
        _text("›", Vector2(615, y + 82), 42, C_ORANGE)

func _game_over() -> void:
    _veil(0.80)
    _box(Rect2(42, 286, 636, 870), Color(0.04, 0.09, 0.11, 0.98), 18, Color(0.4, 0.52, 0.50, 0.7), 1)
    _center("ОТРЯД ПАЛ", 374, 45)
    _center("Но человечество ещё сражается", 416, 20, C_MUTED)
    draw_line(Vector2(78, 449), Vector2(642, 449), Color(0.42, 0.53, 0.50, 0.5), 2)
    _center("%d М" % int(game.distance), 554, 72, C_WHITE)
    _center("ПРОЙДЕНО", 588, 17, C_MUTED)
    _text("УНИЧТОЖЕНО", Vector2(90, 662), 17, C_MUTED)
    _text("%d" % game.kills, Vector2(90, 712), 38, C_WHITE)
    _text("ПОЛУЧЕНО", Vector2(379, 662), 17, C_MUTED)
    _text("◈ %d" % game.earned, Vector2(379, 712), 38, C_ORANGE)
    _text("РЕКОРД: %d М" % int(game.profile["best"]), Vector2(90, 766), 19, C_CYAN)
    _button(Rect2(83, 812, 554, 88), "ЕЩЁ РАЗ  →")
    _button(Rect2(83, 920, 554, 84), "УЛУЧШИТЬ ОТРЯД", false)
    _text("В ГЛАВНОЕ МЕНЮ", Vector2(83, 1066), 18, C_MUTED, 554, HORIZONTAL_ALIGNMENT_CENTER)

func _shop() -> void:
    _veil(0.89)
    _top_label("АРСЕНАЛ СОПРОТИВЛЕНИЯ", 80)
    _text("УЛУЧШЕНИЯ", Vector2(45, 158), 42)
    _text("Постоянные бонусы для каждого забега", Vector2(48, 199), 19, C_MUTED)
    _box(Rect2(44, 231, 632, 71), Color(0.10, 0.17, 0.18), 10)
    _text("НА СЧЁТЕ", Vector2(66, 276), 18, C_MUTED)
    _text("◈ %d" % int(game.profile["coins"]), Vector2(421, 277), 28, C_ORANGE, 225, HORIZONTAL_ALIGNMENT_RIGHT)
    var rows := [
        {"kind":"damage", "title":"ОГНЕВАЯ МОЩЬ", "description":"+14% к урону за уровень", "icon":"✦"},
        {"kind":"squad", "title":"ПОПОЛНЕНИЕ", "description":"+2 бойца в начале забега", "icon":"+"},
        {"kind":"rate", "title":"ТЕМП СТРЕЛЬБЫ", "description":"+12% к скорости за уровень", "icon":"»"}
    ]
    for i in range(rows.size()):
        var row: Dictionary = rows[i]
        var y := 332.0 + float(i) * 190.0
        var kind: String = row["kind"]
        var level := int(game.profile[kind])
        _box(Rect2(42, y, 636, 166), Color(0.07, 0.14, 0.16, 0.98), 12, Color(0.35, 0.48, 0.47, 0.65), 1)
        _box(Rect2(61, y + 21, 82, 80), Color(0.08, 0.27, 0.28), 8)
        _text(row["icon"], Vector2(61, y + 77), 38, C_CYAN, 82, HORIZONTAL_ALIGNMENT_CENTER)
        _text(row["title"], Vector2(160, y + 49), 20, C_WHITE)
        _text(row["description"], Vector2(160, y + 78), 16, C_MUTED)
        _text("УРОВЕНЬ %d / 20" % level, Vector2(64, y + 139), 15, C_MUTED)
        var cost: int = game.upgrade_cost(kind)
        var can_buy: bool = level < 20 and int(game.profile["coins"]) >= cost
        var button_fill := C_ORANGE if can_buy else Color(0.21, 0.27, 0.27)
        _box(Rect2(445, y + 102, 210, 48), button_fill, 8)
        var button_text := "МАКС." if level >= 20 else "◈ %d" % cost
        _text(button_text, Vector2(445, y + 134), 20, Color("#182629") if can_buy else C_MUTED, 210, HORIZONTAL_ALIGNMENT_CENTER)
    _button(Rect2(57, 1062, 606, 86), "НАЗАД", false)
    _text("МОНЕТЫ ЗАРАБАТЫВАЮТСЯ В БОЯХ", Vector2(0, 1201), 15, C_MUTED, 720, HORIZONTAL_ALIGNMENT_CENTER)

func _pause() -> void:
    _veil(0.80)
    _center("ПАУЗА", 514, 48)
    _button(Rect2(77, 586, 566, 88), "ПРОДОЛЖИТЬ")
    _button(Rect2(77, 696, 566, 84), "В ГЛАВНОЕ МЕНЮ", false)
    _center("Награды начисляются после завершения забега", 835, 17, C_MUTED)

func _credits() -> void:
    _veil(0.92)
    _top_label("ИНФОРМАЦИЯ", 84)
    _text("LEGION RUSH", Vector2(48, 165), 44)
    var lines := ["Выживание отряда в опасном мире.", "Огонь автоматический — веди отряд пальцем.", "", "3D-МОДЕЛИ", "Боец: Meshy AI, CC BY 4.0 (адаптировано).", "Заражённые: Meshy AI, CC BY 4.0 (адаптировано).", "Громила: HorrorGameMaker.com, CC0.", "Разбитая машина: alexdelker, CC BY 4.0.", "Остальные материалы: Poly Haven и ambientCG, CC0.", "", "Полные ссылки и условия — в CREDITS.md", "в исходном коде игры.", "", "Игра работает без интернета."]
    var y := 225.0
    for line in lines:
        _text(line, Vector2(48, y), 18, C_MUTED if not line.ends_with("МОДЕЛИ") else C_CYAN)
        y += 39
    _button(Rect2(57, 1050, 606, 86), "НАЗАД", false)

func _virtual(point: Vector2) -> Vector2:
    return (point - offset) / maxf(0.01, scale_factor)

func _gui_input(event: InputEvent) -> void:
    if game == null:
        return
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        var p := _virtual(touch.position)
        if touch.pressed and pointer_index == -1:
            pointer_index = touch.index
            _press(p)
        elif not touch.pressed and touch.index == pointer_index:
            _release(p)
            pointer_index = -1
        accept_event()
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if dragging and drag.index == pointer_index:
            game.target_x = clampf(game.target_x + drag.relative.x / maxf(scale_factor, 0.01) * 0.019, -5.15, 5.15)
        accept_event()
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_LEFT:
            if button.pressed:
                _press(_virtual(button.position))
            else:
                _release(_virtual(button.position))
            accept_event()
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if dragging and game.phase == game.Phase.PLAY:
            game.target_x = clampf(game.target_x + motion.relative.x / maxf(scale_factor, 0.01) * 0.019, -5.15, 5.15)
            accept_event()

func _press(p: Vector2) -> void:
    if game.phase == game.Phase.PLAY:
        pressed_on_pause = p.x >= 605 and p.y <= 145
        dragging = not pressed_on_pause

func _release(p: Vector2) -> void:
    if game.phase == game.Phase.PLAY:
        if pressed_on_pause and p.x >= 605 and p.y <= 155:
            game.phase = game.Phase.PAUSED
        dragging = false
        pressed_on_pause = false
        return
    dragging = false
    match game.phase:
        game.Phase.MENU:
            if Rect2(62, 1080, 596, 88).has_point(p):
                game.start_run()
            elif Rect2(62, 1183, 596, 84).has_point(p):
                game.previous_phase = game.Phase.MENU
                game.phase = game.Phase.SHOP
            elif Rect2(470, 1278, 185, 60).has_point(p):
                game.previous_phase = game.Phase.MENU
                game.phase = game.Phase.CREDITS
        game.Phase.GAME_OVER:
            if Rect2(83, 812, 554, 88).has_point(p):
                game.start_run()
            elif Rect2(83, 920, 554, 84).has_point(p):
                game.previous_phase = game.Phase.GAME_OVER
                game.phase = game.Phase.SHOP
            elif Rect2(83, 1020, 554, 80).has_point(p):
                game.return_to_menu()
        game.Phase.CHOICE:
            for i in range(3):
                if Rect2(60, 435 + i * 155, 600, 132).has_point(p):
                    game.select_choice(i)
                    break
        game.Phase.SHOP:
            if Rect2(57, 1062, 606, 86).has_point(p):
                game.phase = game.previous_phase
            else:
                for i in range(3):
                    if Rect2(42, 332 + i * 190, 636, 166).has_point(p):
                        game.purchase(["damage", "squad", "rate"][i])
                        break
        game.Phase.CREDITS:
            if Rect2(57, 1050, 606, 86).has_point(p):
                game.phase = game.previous_phase
        game.Phase.PAUSED:
            if Rect2(77, 586, 566, 88).has_point(p):
                game.phase = game.Phase.PLAY
            elif Rect2(77, 696, 566, 84).has_point(p):
                game.return_to_menu()
