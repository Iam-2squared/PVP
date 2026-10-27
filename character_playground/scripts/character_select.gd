extends CanvasLayer

## Character selection is a consumer of character previews; it owns no map data.
signal preview_changed(job_id: String, female: bool)
signal play_requested(job_id: String, female: bool)

const JOBS := {
	"warrior": {
		"name": "戦士", "tagline": "剣を手に、前線へ。", "description": "近接攻撃と打たれ強さが基本。\n簡素な鎧をまとった、剣の使い手。",
		"attack": "剣で斬る", "skill": "強撃", "skill_detail": "力を込めた高威力の一撃", "color": "a6b7c0",
		"routes": [{"name": "騎士", "text": "剣を扱い、前線を支える"}, {"name": "重戦士", "text": "重い武器による一撃を重視"}],
	},
	"mage": {
		"name": "メイジ", "tagline": "小さな炎が、道をひらく。", "description": "魔法による攻撃と妨害の基礎を扱う。\n黒い薄手のマントと魔法杖が目印。",
		"attack": "魔法杖から小さな火球", "skill": "火炎爆発", "skill_detail": "狭い範囲を炎で攻撃", "color": "b59fcb",
		"routes": [{"name": "元素術師", "text": "属性魔法を磨く攻撃型の術者"}, {"name": "秘術師", "text": "結界や幻で戦況を操る"}],
	},
	"scout": {
		"name": "斥候", "tagline": "軽い足取り、鋭い一突き。", "description": "素早い移動と敵の発見が得意。\n身軽な装いと短剣で、隙を突く。",
		"attack": "短剣で突く", "skill": "急所突き", "skill_detail": "会心が出やすい一撃", "color": "a6bea0",
		"routes": [{"name": "盗賊", "text": "奇襲や罠で敵の隙を作る"}, {"name": "遊撃兵", "text": "接近と離脱を繰り返して戦う"}],
	},
	"archer": {
		"name": "弓使い", "tagline": "距離を測り、一矢を放つ。", "description": "距離を保ち、矢で攻撃する。\n弓と矢筒を携えた、遠距離の射手。",
		"attack": "弓で矢を射る", "skill": "貫通矢", "skill_detail": "敵を貫いて直線上を攻撃", "color": "b7c69d",
		"routes": [{"name": "射手", "text": "射程と狙いの正確さを重視"}, {"name": "狩人", "text": "追跡し、動きながら矢を射る"}],
	},
	"cleric": {
		"name": "僧侶", "tagline": "祈りの光を、力に変えて。", "description": "回復と聖なる術で仲間を支える。\n明るい法衣と聖杖を携える。",
		"attack": "聖杖から小さな光弾", "skill": "ヒール", "skill_detail": "自分か味方のHPを回復", "color": "ded2a5",
		"routes": [{"name": "司祭", "text": "回復と祝福の力を専門に磨く"}, {"name": "武僧", "text": "身体と聖なる力で前線に立つ"}],
	},
	"artisan": {
		"name": "工匠", "tagline": "道具と工夫が、武器になる。", "description": "戦闘道具で攻撃や援護を行う。\n作業着に工具槌、腰には道具袋。",
		"attack": "工具槌で殴る", "skill": "投擲爆弾", "skill_detail": "小さな爆弾で範囲攻撃", "color": "c7a280",
		"routes": [{"name": "工兵", "text": "設備や仕掛けで戦場を変える"}, {"name": "錬金術師", "text": "薬品の調合で戦闘と補給を担う"}],
	},
}
const ORDER := ["warrior", "mage", "scout", "archer", "cleric", "artisan"]
const GOLD := Color("c9b78e")
const PAPER := Color("ebe6d6")
const MUTED := Color("adb8b7")

var is_open := false
var _job := "warrior"
var _female := false
var _root: Control
var _layout: Control
var _buttons: Dictionary = {}
var _touch_buttons: Array[Button] = []
var _male_button: Button
var _female_button: Button
var _name: Label
var _character_index: Label
var _tagline: Label
var _description: Label
var _attack: Label
var _skill: Label
var _route_labels: Array[Label] = []
var _font: Font


func _ready() -> void:
	layer = 20
	_font = load("res://assets/ui.otf") as Font
	_build()
	get_viewport().size_changed.connect(_fit)
	_fit()
	_root.visible = is_open
	_refresh()


func _build() -> void:
	_root = Control.new()
	_root.name = "SelectionInputShield"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_layout = Control.new()
	_layout.name = "CharacterSelection"
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.size = Vector2(1280, 720)
	_root.add_child(_layout)

	_label("P V P  /  CHARACTER LAB", Vector2(36, 27), Vector2(530, 28), 17, GOLD)
	_label("はじまりの職業", Vector2(33, 64), Vector2(590, 64), 40, PAPER)
	_label("6つの職業から、あなたの一歩を。", Vector2(37, 127), Vector2(570, 32), 19, MUTED)
	_character_index = _label("CHARACTER  /  01", Vector2(946, 36), Vector2(300, 28), 15, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("男女各1体  ·  全12体", Vector2(946, 70), Vector2(300, 28), 17, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)

	_panel(Rect2(28, 177, 284, 401), Color(0.045, 0.067, 0.075, 0.79))
	_label("第一職業", Vector2(45, 189), Vector2(240, 26), 16, GOLD)
	for index in ORDER.size():
		var id: String = ORDER[index]
		var b := _button("%02d    %s" % [index + 1, JOBS[id]["name"]], Rect2(40, 229 + index * 55, 260, 47), 23)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_choose_job.bind(id))
		_buttons[id] = b

	_panel(Rect2(930, 165, 322, 435), Color(0.045, 0.067, 0.075, 0.77))
	_name = _label("", Vector2(950, 181), Vector2(282, 46), 32, PAPER)
	_tagline = _label("", Vector2(950, 231), Vector2(282, 29), 18, GOLD)
	_description = _label("", Vector2(950, 273), Vector2(284, 60), 16, MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label("通常攻撃", Vector2(950, 345), Vector2(280, 24), 15, GOLD)
	_attack = _label("", Vector2(950, 371), Vector2(284, 27), 18, PAPER)
	_skill = _label("", Vector2(950, 407), Vector2(284, 50), 16, MUTED)
	_label("Lv100  /  第二職業への道", Vector2(950, 467), Vector2(284, 25), 15, GOLD)
	for i in 2:
		var route := _label("", Vector2(950, 501 + i * 42), Vector2(286, 45), 16, PAPER)
		_route_labels.append(route)

	_caption_backdrop(Rect2(352, 546, 576, 72), 0.76)
	_label("同じ動き・同じ射程", Vector2(366, 550), Vector2(548, 26), 16, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label("ダブルタップで、威力1.2倍の一撃。", Vector2(346, 579), Vector2(588, 32), 22, PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_label("外見による性能差はありません", Vector2(39, 589), Vector2(300, 24), 15, MUTED)
	_male_button = _button("男性", Rect2(39, 628, 122, 54), 21)
	_female_button = _button("女性", Rect2(172, 628, 122, 54), 21)
	_male_button.pressed.connect(_choose_gender.bind(false))
	_female_button.pressed.connect(_choose_gender.bind(true))
	_caption_backdrop(Rect2(446, 644, 354, 32), 0.66)
	_label("一人称で移動・攻撃を試せます", Vector2(350, 648), Vector2(545, 24), 17, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var play := _button("練習をはじめる  →", Rect2(930, 624, 322, 62), 23)
	play.add_theme_stylebox_override("normal", _style(Color(0.19, 0.23, 0.23, 0.93), GOLD, 1))
	play.pressed.connect(_play)


func _label(text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.position = at
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.horizontal_alignment = alignment
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.add_theme_font_override("font", _font)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.035, 0.55))
	node.add_theme_constant_override("shadow_offset_y", 1)
	_layout.add_child(node)
	return node


func _panel(rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(color, Color(0.65, 0.65, 0.55, 0.22), 1))
	_layout.add_child(panel)
	return panel


func _caption_backdrop(rect: Rect2, opacity: float) -> void:
	var panel := _panel(rect, Color(0.045, 0.067, 0.075, opacity))
	panel.add_theme_stylebox_override("panel", _style(Color(0.045, 0.067, 0.075, opacity), Color.TRANSPARENT, 0))


func _button(text: String, rect: Rect2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", Color("fff6df"))
	button.add_theme_stylebox_override("normal", _style(Color(0.11, 0.15, 0.16, 0.56), Color(0.6, 0.65, 0.63, 0.18), 1))
	button.add_theme_stylebox_override("hover", _style(Color(0.22, 0.27, 0.26, 0.85), Color(0.8, 0.73, 0.57, 0.72), 1))
	button.add_theme_stylebox_override("pressed", _style(Color(0.29, 0.31, 0.27, 0.94), GOLD, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_layout.add_child(button)
	_touch_buttons.append(button)
	return button


func _style(fill: Color, edge: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(5)
	style.content_margin_left = 15
	style.content_margin_right = 15
	return style


func _fit() -> void:
	var available := get_viewport().get_visible_rect().size
	var factor := minf(available.x / 1280.0, available.y / 720.0)
	_layout.scale = Vector2.ONE * factor
	_layout.position = (available - Vector2(1280, 720) * factor) * 0.5


func open(current_job: String = "warrior", female: bool = false) -> void:
	_job = current_job if JOBS.has(current_job) else "warrior"
	_female = female
	is_open = true
	if is_instance_valid(_root):
		_root.show()
		_refresh()
	preview_changed.emit(_job, _female)


func close() -> void:
	is_open = false
	if is_instance_valid(_root):
		_root.hide()


func _choose_job(id: String) -> void:
	_job = id
	_refresh()
	preview_changed.emit(_job, _female)


func _choose_gender(female: bool) -> void:
	_female = female
	_refresh()
	preview_changed.emit(_job, _female)


func _refresh() -> void:
	if not is_instance_valid(_name):
		return
	var data: Dictionary = JOBS[_job]
	_character_index.text = "CHARACTER  /  %02d" % (ORDER.find(_job) * 2 + (2 if _female else 1))
	_name.text = data["name"]
	_tagline.text = data["tagline"]
	_description.text = data["description"]
	_attack.text = data["attack"]
	_skill.text = "スキル  ·  %s\n%s" % [data["skill"], data["skill_detail"]]
	for i in 2:
		var route: Dictionary = data["routes"][i]
		_route_labels[i].text = "%s  /  %s" % [route["name"], route["text"]]
		_route_labels[i].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for id in _buttons:
		var selected: bool = id == _job
		var button: Button = _buttons[id]
		button.add_theme_stylebox_override("normal", _style(Color(0.25, 0.28, 0.25, 0.92) if selected else Color(0.11, 0.15, 0.16, 0.56), GOLD if selected else Color(0.6, 0.65, 0.63, 0.18), 1))
	for entry in [[_male_button, not _female], [_female_button, _female]]:
		var button: Button = entry[0]
		button.add_theme_stylebox_override("normal", _style(Color(0.25, 0.28, 0.25, 0.92) if entry[1] else Color(0.11, 0.15, 0.16, 0.56), GOLD if entry[1] else Color(0.6, 0.65, 0.63, 0.18), 1))


func _play() -> void:
	play_requested.emit(_job, _female)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			for button in _touch_buttons:
				if button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
					button.pressed.emit()
					break
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
			_play()
		get_viewport().set_input_as_handled()
