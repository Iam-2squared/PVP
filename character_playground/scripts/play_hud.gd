extends CanvasLayer
## Small, translucent first-person controls. All click classification belongs to combat.

signal attack_tapped
signal skill_tapped
signal jump_requested
signal selection_requested
signal equipment_toggled

var move_vector := Vector2.ZERO
var blocked := false:
	set(value):
		blocked = value
		if value:
			reset_input()
		if is_instance_valid(_canvas):
			_canvas.visible = not value

var _canvas: HudCanvas
var _font: Font
var _touch_owners: Dictionary = {}
var _mouse_owner := ""
var _stick_value := Vector2.ZERO
var _job_name := "戦士"
var _hp := 100.0
var _mp := 100.0
var _equipped := true
var _feedback := ""
var _feedback_remaining := 0.0
var _feedback_strong := false
var _target_name := ""
var _target_hp := 0.0
var _target_max := 100.0
var _skill_name := "強撃"
var _cooldown := 0.0
var _pressed: Dictionary = {}

const PAPER := Color(0.94, 0.95, 0.91, 0.80)
const MUTED := Color(0.91, 0.93, 0.90, 0.56)
const LINE := Color(0.82, 0.88, 0.83, 0.38)
const GOLD := Color(0.92, 0.78, 0.47, 0.85)


class HudCanvas extends Control:
	var host: CanvasLayer

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		host._draw_hud(self)


func _ready() -> void:
	layer = 15
	_font = load("res://assets/ui.otf") if ResourceLoader.exists("res://assets/ui.otf") else ThemeDB.fallback_font
	_canvas = HudCanvas.new()
	_canvas.name = "PlayControls"
	_canvas.host = self
	add_child(_canvas)
	_canvas.visible = not blocked


func _process(delta: float) -> void:
	if _feedback_remaining > 0.0:
		_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
	if _canvas:
		_canvas.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		reset_input()


func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _layout_scale() -> float:
	var view := _viewport_size()
	return clampf(minf(view.x / 1000.0, view.y / 570.0), 0.65, 1.0)


func _control_rects() -> Dictionary:
	var view := _viewport_size()
	var s := _layout_scale()
	return {
		"stick": Rect2(Vector2(35.0 * s, view.y - 186.0 * s), Vector2(142, 142) * s),
		"attack": Rect2(Vector2(view.x - 151.0 * s, view.y - 185.0 * s), Vector2(112, 112) * s),
		"jump": Rect2(Vector2(view.x - 255.0 * s, view.y - 111.0 * s), Vector2(76, 76) * s),
		"skill": Rect2(Vector2(view.x - 259.0 * s, view.y - 215.0 * s), Vector2(84, 84) * s),
		"selection": Rect2(Vector2(view.x - 162.0 * s, 28.0 * s), Vector2(132, 37) * s),
		"equipment": Rect2(Vector2(view.x - 269.0 * s, 28.0 * s), Vector2(96, 37) * s),
	}


func _hit_control(pos: Vector2) -> String:
	var rects := _control_rects()
	for control_name in rects:
		var rect: Rect2 = rects[control_name]
		if control_name in ["stick", "attack", "jump", "skill"]:
			if pos.distance_to(rect.get_center()) <= rect.size.x * 0.5:
				return control_name
		# Slim toolbar visuals keep a taller touch area at phone landscape sizes.
		elif rect.grow_individual(0.0, 20.0 * _layout_scale(), 0.0, 20.0 * _layout_scale()).has_point(pos):
			return control_name
	return ""


func is_ui_position(pos: Vector2) -> bool:
	return blocked or not _hit_control(pos).is_empty()


func _input(event: InputEvent) -> void:
	if blocked or not is_instance_valid(_canvas) or not _canvas.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var owner := _hit_control(event.position)
			if owner.is_empty():
				return
			# A second finger may press a different button while the first moves.
			if owner == "stick" and _touch_owners.values().has("stick"):
				get_viewport().set_input_as_handled()
				return
			_touch_owners[event.index] = owner
			_pressed[owner] = true
			if owner == "stick":
				_update_stick(event.position)
			else:
				_emit_tap(owner)
			get_viewport().set_input_as_handled()
		elif _touch_owners.has(event.index):
			_release_owner(_touch_owners[event.index])
			_touch_owners.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _touch_owners.has(event.index):
		if _touch_owners[event.index] == "stick":
			_update_stick(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			var owner := _hit_control(event.position)
			if owner.is_empty():
				return
			_mouse_owner = owner
			_pressed[owner] = true
			if owner == "stick":
				_update_stick(event.position)
			else:
				_emit_tap(owner)
			get_viewport().set_input_as_handled()
		elif not event.pressed and not _mouse_owner.is_empty():
			_release_owner(_mouse_owner)
			_mouse_owner = ""
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _mouse_owner == "stick":
		_update_stick(event.position)
		get_viewport().set_input_as_handled()


func _emit_tap(owner: String) -> void:
	match owner:
		"attack": attack_tapped.emit()
		"skill": skill_tapped.emit()
		"jump": jump_requested.emit()
		"selection": selection_requested.emit()
		"equipment": equipment_toggled.emit()


func _update_stick(pos: Vector2) -> void:
	var rect: Rect2 = _control_rects()["stick"]
	_stick_value = ((pos - rect.get_center()) / (rect.size.x * 0.34)).limit_length(1.0)
	move_vector = _stick_value


func _release_owner(owner: String) -> void:
	_pressed.erase(owner)
	if owner == "stick":
		move_vector = Vector2.ZERO
		_stick_value = Vector2.ZERO


func reset_input() -> void:
	move_vector = Vector2.ZERO
	_stick_value = Vector2.ZERO
	_touch_owners.clear()
	_mouse_owner = ""
	_pressed.clear()


func set_status(job_name: String, hp: float, mp: float, equipped: bool) -> void:
	_job_name = job_name
	_hp = clampf(hp, 0.0, 100.0)
	_mp = clampf(mp, 0.0, 100.0)
	_equipped = equipped


func show_feedback(message: String, strong: bool = false) -> void:
	_feedback = message
	_feedback_remaining = 1.5
	_feedback_strong = strong


func set_target(target_name: String, hp: float, max_hp: float) -> void:
	_target_name = target_name
	_target_hp = hp
	_target_max = maxf(max_hp, 0.001)


func set_skill(skill_name: String, cooldown: float) -> void:
	_skill_name = skill_name
	_cooldown = maxf(cooldown, 0.0)


func _text(canvas: Control, content: String, pos: Vector2, font_size: int, color: Color = PAPER) -> void:
	# Small shadow keeps low-opacity labels readable against either pale ground or sky.
	canvas.draw_string(_font, pos + Vector2(0, 1), content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.025, 0.04, 0.045, color.a * 0.7))
	canvas.draw_string(_font, pos, content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _center_text(canvas: Control, content: String, center: Vector2, font_size: int, color: Color = PAPER) -> void:
	var width := _font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(canvas, content, center - Vector2(width * 0.5, 0), font_size, color)


func _panel(canvas: Control, rect: Rect2) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.065, 0.07, 0.23)
	style.border_color = Color(0.82, 0.88, 0.83, 0.20)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	canvas.draw_style_box(style, rect)


func _meter(canvas: Control, rect: Rect2, ratio: float, tint: Color) -> void:
	canvas.draw_rect(rect, Color(0.025, 0.055, 0.055, 0.28))
	var bar := rect
	bar.size.x *= clampf(ratio, 0.0, 1.0)
	canvas.draw_rect(bar, tint)


func _draw_hud(canvas: Control) -> void:
	var view := _viewport_size()
	var s := _layout_scale()
	var rects := _control_rects()
	var left := 34.0 * s
	_text(canvas, "P V P   /   CHARACTER LAB", Vector2(left, 42 * s), int(13 * s), MUTED)
	_text(canvas, _job_name + "  /  Lv.1", Vector2(left, 72 * s), int(21 * s))
	_text(canvas, "HP", Vector2(left, 95 * s), int(11 * s), MUTED)
	_meter(canvas, Rect2(Vector2(left + 27 * s, 87 * s), Vector2(144, 4) * s), _hp / 100.0, Color(0.58, 0.77, 0.65, 0.67))
	_text(canvas, "MP", Vector2(left, 113 * s), int(11 * s), MUTED)
	_meter(canvas, Rect2(Vector2(left + 27 * s, 105 * s), Vector2(144, 3) * s), _mp / 100.0, Color(0.52, 0.67, 0.82, 0.62))
	var equipment_rect: Rect2 = rects["equipment"]
	var selection_rect: Rect2 = rects["selection"]
	_panel(canvas, equipment_rect)
	_panel(canvas, selection_rect)
	_center_text(canvas, "装備 ON" if _equipped else "素手", equipment_rect.get_center() + Vector2(0, 5 * s), int(13 * s))
	_center_text(canvas, "キャラ選択", selection_rect.get_center() + Vector2(0, 5 * s), int(13 * s))
	_draw_stick(canvas, rects["stick"], s)
	_draw_round_button(canvas, rects["attack"], "攻撃", "1 tap / 2 tap", "attack", s)
	_draw_round_button(canvas, rects["jump"], "跳ぶ", "SPACE", "jump", s)
	_draw_round_button(canvas, rects["skill"], "スキル", _skill_name, "skill", s)
	var center := view * 0.5
	canvas.draw_circle(center, 2.3 * s, Color(0.035, 0.06, 0.065, 0.4))
	canvas.draw_circle(center, 1.2 * s, Color(0.95, 0.97, 0.91, 0.8))
	for d in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		canvas.draw_line(center + d * 6 * s, center + d * 9 * s, Color(0.93, 0.95, 0.87, 0.42), s, true)
	if not _target_name.is_empty():
		_center_text(canvas, _target_name, center + Vector2(0, -51 * s), int(12 * s), MUTED)
		_meter(canvas, Rect2(center + Vector2(-48, -42) * s, Vector2(96, 3) * s), _target_hp / _target_max, Color(0.78, 0.63, 0.40, 0.7))
	if _feedback_remaining > 0.0:
		var color := GOLD if _feedback_strong else PAPER
		color.a *= minf(_feedback_remaining * 3.0, 1.0)
		_center_text(canvas, _feedback, center + Vector2(0, 48 * s), int(15 * s), color)
	_center_text(canvas, "WASD 移動  ·  マウス 視点  ·  Space 跳ぶ  ·  Tab / Esc 選択", Vector2(view.x * 0.5, view.y - 23 * s), int(11 * s), Color(0.91, 0.93, 0.90, 0.48))
	_center_text(canvas, "2回で威力 ×1.2", Vector2(view.x - 95 * s, view.y - 51 * s), int(11 * s), MUTED)


func _draw_stick(canvas: Control, rect: Rect2, s: float) -> void:
	var center := rect.get_center()
	var radius := rect.size.x * 0.5
	var active := _pressed.has("stick")
	canvas.draw_circle(center, radius, Color(0.035, 0.065, 0.07, 0.16))
	canvas.draw_arc(center, radius - 1, 0, TAU, 64, Color(0.86, 0.90, 0.86, 0.31), 1 * s, true)
	for d in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		canvas.draw_line(center + d * (radius - 11 * s), center + d * (radius - 5 * s), Color(0.86, 0.90, 0.86, 0.31), 1 * s, true)
	var knob := center + _stick_value * radius * 0.6
	canvas.draw_circle(knob, 25 * s, Color(0.83, 0.88, 0.83, 0.29 if active else 0.15))
	canvas.draw_arc(knob, 25 * s, 0, TAU, 40, Color(0.86, 0.90, 0.86, 0.46 if active else 0.25), s, true)
	_center_text(canvas, "移動", center + Vector2(0, radius + 22 * s), int(11 * s), MUTED)


func _draw_round_button(canvas: Control, rect: Rect2, title: String, subtitle: String, button_name: String, s: float) -> void:
	var center := rect.get_center()
	var radius := rect.size.x * 0.5 - s
	var active := _pressed.has(button_name)
	canvas.draw_circle(center, radius, Color(0.035, 0.065, 0.07, 0.33 if active else 0.20))
	canvas.draw_arc(center, radius, 0, TAU, 64, Color(0.88, 0.91, 0.85, 0.63 if active else 0.34), 1.2 * s, true)
	if button_name == "attack":
		var a := center + Vector2(-7, -27) * s
		var b := center + Vector2(11, -45) * s
		canvas.draw_line(a, b, Color(0.91, 0.93, 0.87, 0.60), 3 * s, true)
		canvas.draw_line(a + Vector2(-4, -3) * s, a + Vector2(4, 5) * s, Color(0.91, 0.93, 0.87, 0.60), 2 * s, true)
		_center_text(canvas, title, center + Vector2(0, 9 * s), int(20 * s))
		_center_text(canvas, subtitle, center + Vector2(0, 29 * s), int(9 * s), MUTED)
	else:
		_center_text(canvas, title, center + Vector2(0, -1 * s), int(15 * s))
		_center_text(canvas, subtitle, center + Vector2(0, 19 * s), int(10 * s), MUTED)
	if button_name == "skill" and _cooldown > 0.0:
		_center_text(canvas, "%.1f" % _cooldown, center + Vector2(0, -23 * s), int(10 * s), GOLD)
