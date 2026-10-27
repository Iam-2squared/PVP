extends CanvasLayer

signal jump_requested
signal attack_requested
signal overview_requested
signal tour_requested

var player: Node3D
var world: Node

var _root: Control
var _stick: MoveStick
var _overview_button: Button
var _tour_button: Button
var _attack_button: Button
var _jump_button: Button
var _skill_button: Button
var _title_panel: Panel
var _area_label: Label
var _help_label: Label
var _debug_label: Label
var _hotbar: HBoxContainer
var _minimap: CityMap
var _crosshair: Reticle
var _interactive: Array[Control] = []
var _button_touches: Dictionary = {}
var _overview := false
var _debug := false
var _update_clock := 0.0
var _ui_font: Font
var _environment_preview := false
var _city_extent := 180.0

const INK := Color(0.045, 0.073, 0.105, 0.85)
const GOLD := Color(0.84, 0.70, 0.40)
const PAPER := Color(0.96, 0.94, 0.87)


class MoveStick extends Control:
	var value := Vector2.ZERO
	var touch_id := -1
	var mouse_held := false
	var active := false
	var radius := 59.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process_input(true)

	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, radius + 6.0, Color(0.02, 0.04, 0.065, 0.28))
		draw_circle(center, radius, Color(0.08, 0.11, 0.15, 0.39))
		draw_arc(center, radius, 0.0, TAU, 48, Color(0.91, 0.82, 0.59, 0.6), 1.5, true)
		for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			draw_line(center + direction * (radius - 8.0), center + direction * (radius - 2.0), Color(0.9, 0.86, 0.72, 0.45), 1.0, true)
		var knob := center + value * (radius - 20.0)
		draw_circle(knob + Vector2(0, 3), 24.0, Color(0.0, 0.0, 0.0, 0.18))
		draw_circle(knob, 23.0, Color(0.75, 0.71, 0.59, 0.44 if active else 0.27))
		draw_arc(knob, 23.0, 0.0, TAU, 32, Color(1.0, 0.93, 0.73, 0.7), 1.5, true)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			mouse_held = true
			active = true
			_move(event.position)
			accept_event()

	func _input(event: InputEvent) -> void:
		# Handle native touch directly: a GUI Control does not receive every raw
		# ScreenTouch path, and mouse emulation cannot represent multiple fingers.
		if event is InputEventScreenTouch and event.pressed and touch_id == -1:
			if is_visible_in_tree() and get_global_rect().has_point(event.position):
				touch_id = event.index
				active = true
				_move(get_global_transform_with_canvas().affine_inverse() * event.position)
				get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag and event.index == touch_id:
			_move(get_global_transform_with_canvas().affine_inverse() * event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch and event.index == touch_id and not event.pressed:
			reset()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and mouse_held:
			_move(get_global_transform_with_canvas().affine_inverse() * event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and mouse_held:
			reset()
			get_viewport().set_input_as_handled()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			reset()

	func _move(local_position: Vector2) -> void:
		value = ((local_position - size * 0.5) / (radius - 20.0)).limit_length(1.0)
		queue_redraw()

	func reset() -> void:
		value = Vector2.ZERO
		touch_id = -1
		mouse_held = false
		active = false
		queue_redraw()


class Reticle extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var shade := Color(0.07, 0.09, 0.11, 0.5)
		var light := Color(1, 0.98, 0.9, 0.9)
		draw_circle(c, 2.5, shade)
		draw_circle(c, 1.3, light)
		for d in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			draw_line(c + d * 6.0, c + d * 10.0, shade, 3.0, true)
			draw_line(c + d * 6.0, c + d * 10.0, light, 1.0, true)


class CityMap extends Control:
	var target: Node3D
	var half_extent := 180.0
	var preview_only := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_style_box(_background(), rect)
		var center := size * 0.5 + Vector2(0, 4)
		var a := half_extent
		var b := a * (sqrt(2.0) - 1.0)
		var scale_factor := (minf(size.x, size.y) - 29.0) / (a * 2.22)
		var vertices := PackedVector2Array()
		for point in [Vector2(-b,-a), Vector2(b,-a), Vector2(a,-b), Vector2(a,b), Vector2(b,a), Vector2(-b,a), Vector2(-a,b), Vector2(-a,-b)]:
			vertices.append(center + point * scale_factor)
		draw_colored_polygon(vertices, Color(0.18, 0.23, 0.23, 0.76))
		var outline := vertices.duplicate()
		outline.append(vertices[0])
		draw_polyline(outline, Color(0.82, 0.72, 0.47, 0.83), 1.4, true)
		if not preview_only:
			draw_line(center + Vector2(-170, 0) * scale_factor, center + Vector2(170, 0) * scale_factor, Color(0.8,0.75,0.6,0.23), 2.5, true)
			draw_line(center + Vector2(0, -150) * scale_factor, center + Vector2(0, 170) * scale_factor, Color(0.8,0.75,0.6,0.23), 2.5, true)
			draw_circle(center, 10.0 * scale_factor, Color(0.72, 0.64, 0.43, 0.6))
			draw_rect(Rect2(center + Vector2(-22, -139) * scale_factor, Vector2(44, 34) * scale_factor), Color(0.38,0.57,0.75,0.85))
		if is_instance_valid(target):
			var marker: Vector2 = center + Vector2(target.global_position.x, target.global_position.z) * scale_factor
			marker = marker.clamp(Vector2(8, 14), size - Vector2(8, 8))
			var direction := Vector2(-sin(target.rotation.y), -cos(target.rotation.y))
			draw_line(marker, marker + direction * 10.0, Color(0.96, 0.84, 0.48), 2.0, true)
			draw_circle(marker, 3.5, Color(0.98, 0.86, 0.44))
			draw_circle(marker, 1.5, Color(1,1,0.9))

	func _background() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.035, 0.06, 0.085, 0.76)
		style.border_color = Color(0.77, 0.67, 0.42, 0.35)
		style.set_border_width_all(1)
		style.set_corner_radius_all(14)
		return style


func _ready() -> void:
	layer = 10
	if is_instance_valid(world):
		_environment_preview = bool(world.get_meta("environment_preview", false))
		for property in world.get_property_list():
			if property["name"] == "city_half_extent":
				_city_extent = float(world.get("city_half_extent"))
				break
	if ResourceLoader.exists("res://assets/fonts/ui.otf"):
		_ui_font = load("res://assets/fonts/ui.otf")
	elif ResourceLoader.exists("res://assets/fonts/ui.ttf"):
		_ui_font = load("res://assets/fonts/ui.ttf")
	_root = Control.new()
	_root.name = "Overlay"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	if _ui_font:
		theme.default_font = _ui_font
	theme.default_font_size = 16
	_root.theme = theme

	_title_panel = Panel.new()
	_title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_panel.add_theme_stylebox_override("panel", _panel_style(INK, Color(GOLD, 0.36), 12))
	_root.add_child(_title_panel)
	var title := _label("王都セレシア", 25, PAPER)
	title.position = Vector2(18, 10)
	_title_panel.add_child(title)
	var mode := _label("王都見学プレビュー" if _environment_preview else "歩行プレビュー", 12, GOLD)
	mode.position = Vector2(20, 46)
	_title_panel.add_child(mode)
	_area_label = _label("現在地  ·  城下町", 15, PAPER)
	_root.add_child(_area_label)

	_overview_button = _button("全体図  M", 16, 12)
	_overview_button.pressed.connect(func() -> void: overview_requested.emit())
	_interactive.append(_overview_button)
	_tour_button = _button("見学先 ▶  N", 15, 12)
	_tour_button.tooltip_text = "次の見学場所へ移動（N）"
	_tour_button.pressed.connect(func() -> void: tour_requested.emit())
	_tour_button.visible = _has_preview_locations()
	_interactive.append(_tour_button)
	_attack_button = _button("攻撃", 22, 60)
	_attack_button.pressed.connect(func() -> void: attack_requested.emit())
	_interactive.append(_attack_button)
	_jump_button = _button("跳ぶ", 17, 45)
	_jump_button.pressed.connect(func() -> void: jump_requested.emit())
	_interactive.append(_jump_button)
	_skill_button = _button("強撃", 17, 45)
	_skill_button.disabled = true
	_skill_button.tooltip_text = "選択中のスキル。今回は街を歩くプレビューです。"
	_interactive.append(_skill_button)

	_stick = MoveStick.new()
	_stick.name = "MovementStick"
	_root.add_child(_stick)
	_interactive.append(_stick)

	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 7)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hotbar)
	var items := ["剣", "パン", "果実", "水"]
	for i in range(4):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(54, 54)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var edge: Color = GOLD if i == 0 else Color(0.69, 0.7, 0.68, 0.31)
		slot.add_theme_stylebox_override("panel", _panel_style(Color(INK, 0.76), edge, 9, 2 if i == 0 else 1))
		_hotbar.add_child(slot)
		var item := _label(items[i], 17, PAPER if i == 0 else Color(0.87,0.86,0.79,0.66))
		item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(item)

	_crosshair = Reticle.new()
	_crosshair.size = Vector2(32,32)
	_root.add_child(_crosshair)
	_minimap = CityMap.new()
	_minimap.target = player
	_minimap.half_extent = _city_extent
	_minimap.preview_only = _environment_preview
	_root.add_child(_minimap)
	var north_label := _label("N", 11, GOLD)
	north_label.position = Vector2(67, 3)
	_minimap.add_child(north_label)
	_help_label = _label("WASD 移動   ·   マウス 視点   ·   Space ジャンプ   ·   M 全体図", 12, Color(0.94,0.94,0.88,0.75))
	_root.add_child(_help_label)
	_debug_label = _label("", 13, Color(0.91,0.98,0.89))
	_debug_label.visible = false
	_root.add_child(_debug_label)
	_root.resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_overview(false)
	call_deferred("_layout")


func _layout() -> void:
	if not is_instance_valid(_root) or not is_instance_valid(_stick):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var width := viewport_size.x
	var height := viewport_size.y
	_title_panel.position = Vector2(22, 20)
	_title_panel.size = Vector2(270, 78)
	_area_label.position = Vector2(28, 110)
	_overview_button.position = Vector2(width - 164, 22)
	var header_button_height := 88.0 if _environment_preview and DisplayServer.is_touchscreen_available() else 48.0
	_overview_button.size = Vector2(142, header_button_height)
	_tour_button.position = Vector2(width - 350, 22)
	_tour_button.size = Vector2(174, header_button_height)
	_tour_button.visible = _has_preview_locations()
	_minimap.position = Vector2(width - 164, 34 + header_button_height)
	_minimap.size = Vector2(142, 142)
	_stick.position = Vector2(38, height - 198)
	_stick.size = Vector2(150, 150)
	_attack_button.position = Vector2(width - 142, height - 216)
	_attack_button.size = Vector2(106, 106)
	_jump_button.position = Vector2(width - 235, height - 126)
	_jump_button.size = Vector2(78, 78)
	if _environment_preview:
		_jump_button.position = Vector2(width - 132, height - 142)
		_jump_button.size = Vector2(88, 88)
	_skill_button.position = Vector2(width - 235, height - 275)
	_skill_button.size = Vector2(78, 78)
	_hotbar.position = Vector2(width * 0.5 - 119, height - 73)
	_hotbar.size = Vector2(237, 54)
	_crosshair.position = viewport_size * 0.5 - Vector2(16,16)
	_help_label.position = Vector2(width * 0.5 - 240, height - 38 if _environment_preview else height - 96)
	_help_label.visible = not DisplayServer.is_touchscreen_available()
	_debug_label.position = Vector2(28, 139)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _button_touches.has(event.index):
				get_viewport().set_input_as_handled()
				return
			for button in [_overview_button, _tour_button, _attack_button, _jump_button, _skill_button]:
				if is_instance_valid(button) and button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
					_button_touches[event.index] = button
					if not button.disabled:
						button.set_pressed_no_signal(true)
						button.pressed.emit()
					get_viewport().set_input_as_handled()
					return
		elif _button_touches.has(event.index):
			var button: Button = _button_touches[event.index]
			if is_instance_valid(button):
				button.set_pressed_no_signal(false)
			_button_touches.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _button_touches.has(event.index):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		reset_interaction_state()


func _process(delta: float) -> void:
	_update_clock += delta
	if _update_clock < 0.15:
		return
	_update_clock = 0.0
	if is_instance_valid(_minimap):
		_minimap.queue_redraw()
	if not is_instance_valid(player):
		return
	refresh_location()
	if _debug:
		var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		_debug_label.text = "FPS %d  |  Draw %d  |  Objects %d\n位置  %.1f, %.1f, %.1f" % [Engine.get_frames_per_second(), draw_calls, objects, player.global_position.x, player.global_position.y, player.global_position.z]


func get_move_vector() -> Vector2:
	return _stick.value if is_instance_valid(_stick) and not _overview else Vector2.ZERO


func _has_preview_locations() -> bool:
	return _environment_preview and is_instance_valid(player) and player.has_method("get_preview_locations") and not player.get_preview_locations().is_empty()


func reset_interaction_state() -> void:
	if is_instance_valid(_stick):
		_stick.reset()
	for button in _button_touches.values():
		if is_instance_valid(button):
			button.set_pressed_no_signal(false)
	_button_touches.clear()


func refresh_location() -> void:
	if not is_instance_valid(player) or not is_instance_valid(_area_label):
		return
	var location := "城壁内" if _environment_preview else "城下町"
	var best_score := 37.0
	var found := false
	var entries: Array = []
	if is_instance_valid(world):
		var landmarks: Variant = world.get("landmarks")
		if landmarks is Array:
			entries.append_array(landmarks)
	if player.has_method("get_preview_locations"):
		entries.append_array(player.get_preview_locations())
	for entry in entries:
		if not entry is Dictionary or not entry.get("position") is Vector3:
			continue
		var p: Vector3 = entry["position"]
		var height_difference := absf(player.global_position.y - p.y)
		if height_difference > 3.0:
			continue
		var distance := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
		var score := distance + height_difference * 1.5
		if distance < 37.0 and score <= best_score:
			best_score = score
			found = true
			location = str(entry.get("title", "城下町"))
	var p2 := Vector2(absf(player.global_position.x), absf(player.global_position.z))
	if not found and (p2.x > _city_extent or p2.y > _city_extent or p2.x + p2.y > _city_extent * sqrt(2.0)):
		location = "王都の外縁"
	_area_label.text = "現在地  ·  " + location
	if is_instance_valid(_tour_button):
		_tour_button.visible = _has_preview_locations()


func is_ui_position(pos: Vector2) -> bool:
	for control in _interactive:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(pos):
			return true
	return is_instance_valid(_hotbar) and _hotbar.is_visible_in_tree() and _hotbar.get_global_rect().has_point(pos)


func set_overview(enabled: bool) -> void:
	_overview = enabled
	if not is_instance_valid(_overview_button):
		return
	_overview_button.text = "歩行へ戻る  M" if enabled else "全体図  M"
	_stick.reset()
	_stick.visible = not enabled
	_attack_button.visible = not enabled and not _environment_preview
	_jump_button.visible = not enabled
	_skill_button.visible = not enabled and not _environment_preview
	_crosshair.visible = not enabled
	_hotbar.visible = not enabled and not _environment_preview
	_minimap.visible = not enabled
	_help_label.text = "M または右上のボタンで歩行へ戻る" if enabled else "WASD 移動   ·   マウス 視点   ·   Space ジャンプ   ·   N 見学先   ·   M 全体図" if _has_preview_locations() else "WASD 移動   ·   マウス 視点   ·   Space ジャンプ   ·   M 全体図"


func set_debug(enabled: bool) -> void:
	_debug = enabled
	if is_instance_valid(_debug_label):
		_debug_label.visible = enabled


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _button(text: String, font_size: int, radius: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", Color(1.0,0.96,0.78))
	button.add_theme_color_override("font_pressed_color", Color(1.0,0.94,0.67))
	button.add_theme_color_override("font_disabled_color", Color(0.83,0.8,0.69,0.65))
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.045,0.075,0.11,0.68), Color(GOLD,0.67), radius))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.13,0.17,0.19,0.83), GOLD, radius))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.25,0.25,0.19,0.87), Color(0.96,0.83,0.48), radius, 2))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.045,0.075,0.11,0.48), Color(GOLD,0.32), radius))
	_root.add_child(button)
	return button


func _panel_style(background: Color, edge: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
