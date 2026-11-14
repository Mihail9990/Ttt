class_name SkyHUD
extends CanvasLayer

const ITEM_NAMES: Dictionary = {"soil": "Земля", "clay": "Глина", "sand": "Песок", "stone": "Камень", "timber": "Древесина", "board": "Доски", "brick": "Кирпич", "ore": "Руда", "metal": "Металл", "nail": "Гвозди", "screw": "Саморезы", "fuel": "Топливо", "ammo": "Патроны"}
const TOOL_NAMES: Dictionary = {"shovel": "Лопата", "axe": "Топор", "pickaxe": "Кирка", "hammer": "Молоток", "driver": "Шуруповёрт", "build": "Строительство", "rifle": "Оружие"}
const FACTORY_NAMES: Dictionary = {"sawmill": "Лесопилка", "brick_kiln": "Кирпичный завод", "smelter": "Плавильня"}
var game: Node
var _root: Control
var _scrim: ColorRect
var _stats: Label
var _inventory: Label
var _tool_label: Label
var _notice: Label
var _help: Label
var _market_panel: PanelContainer
var _build_panel: PanelContainer
var _menu_panel: PanelContainer
var _offers_box: VBoxContainer
var _factory_box: VBoxContainer
var _market_hint: Label
var _dimension_spins: Array[SpinBox] = []
var _angle_spins: Array[SpinBox] = []
var _kind_picker: OptionButton
var _sell_item: OptionButton
var _sell_quantity: SpinBox
var _sell_price: SpinBox
var _house_price: SpinBox
var _network_address: LineEdit
var _synchronizing: bool = false
var _action_held: bool = false
var _action_clock: float = 0.0
var _refresh_clock: float = 0.0
var _last_offers: String = ""
var _last_factories: String = ""
var _last_notice: String = ""
var _notice_age: float = 0.0
var _tool_buttons: Dictionary = {}
var _descend_button: Button
var _jump_button: Button
var _interact_button: Button
var _glider_button: Button

class MovePad extends Control:
	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, minf(size.x, size.y) * 0.42, Color(0.08, 0.15, 0.19, 0.20))
		draw_arc(center, minf(size.x, size.y) * 0.42, 0, TAU, 48, Color(0.78, 0.87, 0.86, 0.35), 2)
		draw_circle(center, 10, Color(0.75, 0.86, 0.85, 0.25))

func setup(manager: Node) -> void:
	game = manager
	_build_ui()

func _panel_style(opacity: float = 0.94) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.065, 0.085, opacity)
	style.border_color = Color(0.24, 0.36, 0.38, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func _button(text: String, callback: Callable, width: float = 0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 44)
	button.add_theme_font_size_override("font_size", 16)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_to_group("sky_ui_blocker")
	button.pressed.connect(callback)
	button.focus_mode = Control.FOCUS_NONE
	return button

func _label(text: String, font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _vbox(separation: int = 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "HUD"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var theme := Theme.new()
	theme.default_font_size = 16
	var button_normal := _panel_style(0.84)
	button_normal.content_margin_left = 12
	button_normal.content_margin_right = 12
	theme.set_stylebox("normal", "Button", button_normal)
	var hovered := button_normal.duplicate() as StyleBoxFlat
	hovered.bg_color = Color(0.10, 0.24, 0.27, 0.95)
	theme.set_stylebox("hover", "Button", hovered)
	var pressed := button_normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.13, 0.39, 0.38, 0.96)
	theme.set_stylebox("pressed", "Button", pressed)
	_root.theme = theme
	var top := PanelContainer.new()
	top.position = Vector2(18, 16)
	top.custom_minimum_size = Vector2(480, 104)
	top.add_theme_stylebox_override("panel", _panel_style(0.74))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	var top_box := _vbox(3)
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_box)
	var title := _label("НЕБЕСНЫЕ ОСТРОВА", 20)
	title.add_theme_color_override("font_color", Color(0.88, 0.95, 0.94))
	top_box.add_child(title)
	_stats = _label("")
	top_box.add_child(_stats)
	_inventory = _label("", 14)
	_inventory.add_theme_color_override("font_color", Color(0.68, 0.81, 0.81))
	top_box.add_child(_inventory)
	var top_actions := HBoxContainer.new()
	top_actions.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_actions.position = Vector2(-428, 18)
	top_actions.add_theme_constant_override("separation", 6)
	_root.add_child(top_actions)
	top_actions.add_child(_button("Рынок", show_market, 92))
	top_actions.add_child(_button("Строить", show_build, 92))
	top_actions.add_child(_button("Сеть", toggle_menu, 82))
	top_actions.add_child(_button("Сохранить", func() -> void: _submit({"action": "save"}), 112))
	var crosshair := _label("+", 23)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-7, -17)
	crosshair.modulate = Color(0.9, 0.98, 0.96, 0.8)
	_root.add_child(crosshair)
	var center_bottom := VBoxContainer.new()
	center_bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	center_bottom.position = Vector2(-268, -148)
	center_bottom.custom_minimum_size.x = 536
	center_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center_bottom)
	_tool_label = _label("Лопата", 18)
	_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_bottom.add_child(_tool_label)
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 5)
	center_bottom.add_child(tool_row)
	var short_names: Array[String] = ["ЛОП", "ТОП", "КИР", "МОЛ", "ШУР", "СТР", "ОРУ"]
	for index: int in range(SkyPlayer.TOOLS.size()):
		var id: String = SkyPlayer.TOOLS[index]
		var button := _button("%d\n%s" % [index + 1, short_names[index]], _choose_tool.bind(id), 72)
		button.custom_minimum_size.y = 58
		_tool_buttons[id] = button
		tool_row.add_child(button)
	_notice = _label("", 17)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_notice.position = Vector2(-440, -215)
	_notice.size = Vector2(880, 48)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_notice)
	_help = _label("WASD — движение · Мышь — обзор · M — рынок · B — строительство · F — планер · Esc — меню", 14)
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_help.position = Vector2(-410, -24)
	_help.size.x = 820
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.modulate.a = 0.65
	_root.add_child(_help)
	var move_pad := MovePad.new()
	move_pad.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	move_pad.position = Vector2(20, -205)
	move_pad.size = Vector2(170, 170)
	move_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(move_pad)
	var right_actions := VBoxContainer.new()
	right_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	right_actions.position = Vector2(-184, -292)
	right_actions.add_theme_constant_override("separation", 8)
	_root.add_child(right_actions)
	var action := _button("ДЕЙСТВИЕ", func() -> void: pass, 160)
	action.custom_minimum_size.y = 65
	action.button_down.connect(func() -> void:
		_action_held = true
		_action_clock = 0.0
		var player := _player()
		if player != null: player.use_tool())
	action.button_up.connect(func() -> void: _action_held = false)
	right_actions.add_child(action)
	_jump_button = _button("ПРЫЖОК", func() -> void:
		var player := _player()
		if player != null: player.request_jump(), 160)
	_jump_button.button_down.connect(func() -> void:
		var player := _player()
		if player != null: player.ascend_held = true)
	_jump_button.button_up.connect(func() -> void:
		var player := _player()
		if player != null: player.ascend_held = false)
	right_actions.add_child(_jump_button)
	_descend_button = _button("НИЖЕ", func() -> void: pass, 160)
	_descend_button.button_down.connect(func() -> void:
		var player := _player()
		if player != null: player.descend_held = true)
	_descend_button.button_up.connect(func() -> void:
		var player := _player()
		if player != null: player.descend_held = false)
	right_actions.add_child(_descend_button)
	_interact_button = _button("ВЗАИМОДЕЙСТВ.", func() -> void: _submit({"action": "interact"}), 160)
	right_actions.add_child(_interact_button)
	_glider_button = _button("ПЛАНЕР", func() -> void:
		var player := _player()
		if player != null:
			player.glider = not player.glider
			game.notice = "Планер раскрыт" if player.glider else "Планер сложен", 160)
	right_actions.add_child(_glider_button)
	_scrim = ColorRect.new()
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(0.005, 0.015, 0.025, 0.30)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.add_to_group("sky_ui_blocker")
	_scrim.visible = false
	_root.add_child(_scrim)
	_build_market()
	_build_construction()
	_build_network_menu()

func _modal(title: String, width: float = 760, height: float = 540) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-width * 0.5, -height * 0.5)
	panel.custom_minimum_size = Vector2(width, height)
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_to_group("sky_ui_blocker")
	_root.add_child(panel)
	var content := _vbox(10)
	content.name = "Content"
	panel.add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var label := _label(title, 22)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	heading.add_child(_button("Закрыть", _close_panels, 100))
	panel.visible = false
	return panel

func _build_market() -> void:
	_market_panel = _modal("Маркетплейс", 840, 548)
	var content := _market_panel.get_node("Content") as VBoxContainer
	_market_hint = _label("Товары игроков и торговцев", 14)
	_market_hint.add_theme_color_override("font_color", Color(0.7, 0.82, 0.82))
	content.add_child(_market_hint)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.y = 410
	tabs.add_theme_font_size_override("font_size", 16)
	content.add_child(tabs)
	var buy_scroll := ScrollContainer.new()
	buy_scroll.name = "Купить"
	buy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(buy_scroll)
	_offers_box = _vbox(6)
	_offers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_scroll.add_child(_offers_box)
	var sell := _vbox(12)
	sell.name = "Продать"
	tabs.add_child(sell)
	sell.add_child(_label("Выбери ресурс, количество и общую цену объявления."))
	_sell_item = OptionButton.new()
	_sell_item.custom_minimum_size.y = 42
	for item: String in ITEM_NAMES.keys():
		_sell_item.add_item(str(ITEM_NAMES[item]))
		_sell_item.set_item_metadata(_sell_item.item_count - 1, item)
	sell.add_child(_sell_item)
	_sell_quantity = _spin_row(sell, "Количество", 1, 1000, 1, 5)
	_sell_price = _spin_row(sell, "Общая цена, монет", 1, 100000, 1, 10)
	var sell_buttons := HBoxContainer.new()
	sell.add_child(sell_buttons)
	sell_buttons.add_child(_button("Предложить торговцу NPC", _sell.bind(true), 320))
	sell_buttons.add_child(_button("Объявление для игроков", _sell.bind(false), 320))
	var industry_scroll := ScrollContainer.new()
	industry_scroll.name = "Производство"
	industry_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(industry_scroll)
	var industry := _vbox(10)
	industry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	industry_scroll.add_child(industry)
	industry.add_child(_label("Покупка мастерской и производство из своих ресурсов."))
	for kind: String in FACTORY_NAMES.keys():
		var price: int = {"sawmill": 120, "brick_kiln": 160, "smelter": 200}[kind]
		industry.add_child(_button("%s — %d монет" % [FACTORY_NAMES[kind], price], _submit.bind({"action": "factory_buy", "kind": kind})))
	_factory_box = _vbox(6)
	industry.add_child(_factory_box)
	industry.add_child(_label("Лесопилка: древесина → доски\nКирпичный завод: глина + песок + топливо → кирпич\nПлавильня: руда + топливо → металл", 14))
	var homes := _vbox(12)
	homes.name = "Постройки"
	tabs.add_child(homes)
	var description := _label("Собери постройку и закрепи детали. Наведи прицел на неё перед открытием рынка.")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	homes.add_child(description)
	_house_price = _spin_row(homes, "Цена постройки, монет", 1, 1000000, 10, 250)
	homes.add_child(_button("Выставить свою постройку", func() -> void: _submit({"action": "house_list", "price": int(_house_price.value)})))
	homes.add_child(_label("Свои объявления можно снять во вкладке «Купить».", 14))
	homes.add_child(_button("Вернуть постройку к свободному строительству", _submit.bind({"action": "house_release"})))
	var remodel_hint := _label("Постройка останется на месте. Сначала сними объявление, затем освободи нужные детали от крепежа инструментом.", 14)
	remodel_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	homes.add_child(remodel_hint)
	var defense := _vbox(12)
	defense.name = "Охрана"
	tabs.add_child(defense)
	var defense_hint := _label("Наведи прицел на место на своём острове, затем выбери охрану. Размещать её можно в любое время.")
	defense_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	defense.add_child(defense_hint)
	for kind: String in ["guard", "turret", "drone"]:
		var details: Dictionary = {"guard": ["Вооружённый охранник", 80], "turret": ["Пулемётная турель", 120], "drone": ["Патрульный дрон", 160]}
		defense.add_child(_button("%s — %d монет" % [details[kind][0], details[kind][1]], _submit.bind({"action": "defense_buy", "kind": kind})))
	defense.add_child(_label("Для стрелкового оружия нужны патроны из вкладки «Купить».", 14))

func _spin_row(parent: Control, title: String, minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(180, 40)
	row.add_child(spin)
	return spin

func _build_construction() -> void:
	_build_panel = _modal("Свободное строительство", 660, 555)
	var content := _build_panel.get_node("Content") as VBoxContainer
	_kind_picker = OptionButton.new()
	_kind_picker.add_item("Доска")
	_kind_picker.add_item("Кирпич")
	_kind_picker.add_item("Брус")
	_kind_picker.custom_minimum_size.y = 42
	_kind_picker.item_selected.connect(func(index: int) -> void:
		if _synchronizing: return
		var player := _player()
		if player != null: player.build_kind = ["board", "brick", "beam"][index])
	content.add_child(_kind_picker)
	var size_titles: Array[String] = ["Длина, м", "Ширина, м", "Толщина, м"]
	for index: int in range(3):
		var spin := _spin_row(content, size_titles[index], [0.1, 0.02, 0.01][index], [6.0, 2.0, 1.0][index], 0.01, [2.0, 0.2, 0.03][index])
		spin.value_changed.connect(_set_dimension.bind(index))
		_dimension_spins.append(spin)
	content.add_child(_label("Поворот детали", 18))
	for index: int in range(3):
		var spin := _spin_row(content, ["Наклон X, °", "Поворот Y, °", "Крен Z, °"][index], -180, 180, 15, 0)
		spin.value_changed.connect(_set_angle.bind(index))
		_angle_spins.append(spin)
	var hint := _label("Закрой панель, наведи прицел и установи деталь. Затем выбери молоток или шуруповёрт и работай по месту соединения.", 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

func _build_network_menu() -> void:
	_menu_panel = _modal("Совместная игра", 660, 350)
	var content := _menu_panel.get_node("Content") as VBoxContainer
	content.add_child(_label("Играй в одном мире с друзьями по адресу сервера."))
	content.add_child(_button("Открыть этот мир для подключения", func() -> void:
		game.notice = str(game.host_game())
		_close_panels()))
	_network_address = LineEdit.new()
	_network_address.placeholder_text = "Адрес сервера, например 192.168.1.10"
	_network_address.custom_minimum_size.y = 44
	content.add_child(_network_address)
	content.add_child(_button("Подключиться", func() -> void:
		var address := _network_address.text.strip_edges()
		if not address.is_empty():
			game.notice = str(game.join_game(address))
			_close_panels()))
	content.add_child(_button("Вернуться в мир", _close_panels))

func _player() -> SkyPlayer:
	if not is_instance_valid(game):
		return null
	return game.get("local_player") as SkyPlayer

func _submit(payload: Dictionary) -> void:
	if is_instance_valid(game):
		game.request_action(payload)
		_refresh_clock = 1.0

func _choose_tool(id: String) -> void:
	var player := _player()
	if player != null:
		player.set_tool(id)
		if id == "build": show_build()

func _sell(npc: bool) -> void:
	var item: String = str(_sell_item.get_item_metadata(_sell_item.selected))
	_submit({"action": "trade_sell", "item": item, "quantity": int(_sell_quantity.value), "price": int(_sell_price.value), "npc": npc})

func _set_dimension(value: float, index: int) -> void:
	if _synchronizing: return
	var player := _player()
	if player != null:
		player.part_size[index] = value

func _set_angle(value: float, index: int) -> void:
	if _synchronizing: return
	var player := _player()
	if player != null:
		player.part_rotation[index] = deg_to_rad(value)

func _set_modal_state() -> void:
	var blocked: bool = _market_panel.visible or _build_panel.visible or _menu_panel.visible
	_scrim.visible = blocked
	var player := _player()
	if player != null:
		player.set_input_blocked(blocked)
	_action_held = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if blocked or OS.has_feature("mobile") else Input.MOUSE_MODE_CAPTURED

func _close_panels() -> void:
	_market_panel.hide()
	_build_panel.hide()
	_menu_panel.hide()
	_set_modal_state()

func show_market() -> void:
	var was_visible: bool = _market_panel.visible
	_close_panels()
	_market_panel.visible = not was_visible
	_refresh_market(true)
	_set_modal_state()

func show_build() -> void:
	var player := _player()
	if player == null: return
	player.set_tool("build")
	_close_panels()
	_synchronizing = true
	_kind_picker.select(maxi(0, ["board", "brick", "beam"].find(player.build_kind)))
	for index: int in range(3):
		_dimension_spins[index].value = player.part_size[index]
		_angle_spins[index].value = rad_to_deg(player.part_rotation[index])
	_synchronizing = false
	_build_panel.show()
	_set_modal_state()

func toggle_menu() -> void:
	var was_visible: bool = _menu_panel.visible
	_close_panels()
	_menu_panel.visible = not was_visible
	_set_modal_state()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("market"):
		show_market()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if _market_panel.visible or _build_panel.visible or _menu_panel.visible: _close_panels()
			else: toggle_menu()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_B:
			show_build()
			get_viewport().set_input_as_handled()

func _refresh_market(force: bool = false) -> void:
	if not is_instance_valid(game) or not _market_panel.visible: return
	var offers: Array = game.get_offers() if game.has_method("get_offers") else []
	var cache: String = str(offers)
	if force or cache != _last_offers:
		_last_offers = cache
		for child: Node in _offers_box.get_children(): child.queue_free()
		if offers.is_empty(): _offers_box.add_child(_label("Сейчас нет открытых объявлений."))
		for offer: Dictionary in offers:
			var row := HBoxContainer.new()
			_offers_box.add_child(row)
			var id: int = int(offer.get("id", offer.get("listing", 0)))
			var is_house: bool = str(offer.get("kind", "items")) == "house"
			var item: String = str(offer.get("item", ""))
			var text: String = "Постройка #%d" % int(offer.get("house", id)) if is_house else "%s × %d" % [ITEM_NAMES.get(item, item), int(offer.get("quantity", 1))]
			var player := _player()
			var own_offer: bool = player != null and int(offer.get("seller", 0)) == player.player_id
			var seller: String = "твоё объявление" if own_offer else "торговец NPC" if bool(offer.get("npc", false)) or int(offer.get("seller", 0)) == 900000 else "игрок"
			var label := _label("%s\n%d монет · %s" % [text, int(offer.get("price", 0)), seller], 16)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			if own_offer:
				row.add_child(_button("Снять", _submit.bind({"action": "trade_cancel", "listing": id}), 115))
			else:
				row.add_child(_button("Купить", _submit.bind({"action": "house_buy" if is_house else "trade_buy", "listing": id}), 115))
	var factories: Dictionary = game.sim.factories
	cache = str(factories)
	if force or cache != _last_factories:
		_last_factories = cache
		for child: Node in _factory_box.get_children(): child.queue_free()
		var player := _player()
		if player != null:
			for id: Variant in factories:
				var factory: Dictionary = factories[id]
				if int(factory.get("owner", 0)) != player.player_id: continue
				_factory_box.add_child(_button("Произвести: %s #%d" % [FACTORY_NAMES.get(str(factory.get("kind", "")), "Мастерская"), int(id)], _submit.bind({"action": "factory_run", "factory": int(id)})))

func _process(delta: float) -> void:
	if not is_instance_valid(game) or _root == null: return
	var player := _player()
	if player == null: return
	var stats: Dictionary = game.get_local_stats() if game.has_method("get_local_stats") else {}
	var piloting: bool = player.is_piloting()
	_descend_button.visible = piloting
	_jump_button.text = "ВЫШЕ" if piloting else "ПРЫЖОК"
	_interact_button.text = "ОСТАНОВИТЬ ПОЛЁТ" if piloting else "ВЗАИМОДЕЙСТВ."
	_glider_button.visible = not piloting
	var coins: int = int(stats.get("coins", 0))
	var hp: float = float(stats.get("health", player.health))
	_stats.text = "Здоровье %d     Монеты %d" % [int(hp), coins]
	var inventory: Dictionary = stats.get("inventory", {})
	_inventory.text = "Доски %d   Кирпич %d   Гвозди %d   Саморезы %d" % [int(inventory.get("board", 0)), int(inventory.get("brick", 0)), int(inventory.get("nail", 0)), int(inventory.get("screw", 0))]
	_tool_label.text = "Управление островом" if piloting else "%s%s" % [TOOL_NAMES.get(player.tool, player.tool), " · планер" if player.glider else ""]
	_help.text = "WASD — полёт · Пробел — выше · Ctrl — ниже · E — остановить полёт" if piloting else "WASD — движение · Мышь — обзор · M — рынок · B — строительство · F — планер · Esc — меню"
	for id: String in _tool_buttons:
		var button: Button = _tool_buttons[id]
		button.modulate = Color(0.68, 1.0, 0.87) if id == player.tool else Color.WHITE
	var notice: String = str(game.notice)
	if notice != _last_notice:
		_last_notice = notice
		_notice_age = 0
	_notice_age += delta
	_notice.text = notice
	_notice.modulate.a = clampf(7.0 - _notice_age, 0.0, 1.0)
	_help.visible = not OS.has_feature("mobile")
	if _action_held and not player.input_blocked:
		_action_clock += delta
		if _action_clock >= 0.34:
			_action_clock = 0
			player.use_tool()
	_refresh_clock += delta
	if _refresh_clock >= 0.5:
		_refresh_clock = 0
		_refresh_market()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _root != null:
		toggle_menu()
