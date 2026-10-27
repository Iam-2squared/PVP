extends Control
## Home and battle share authoritative server snapshots. Local storage is only
## an identity credential store and an offline display cache.

const Data = preload("res://scripts/frontend/home_data.gd")
const CharacterSlot = preload("res://scripts/frontend/character_slot.gd")
const CharacterCatalog = preload("res://scripts/frontend/characters/character_catalog.gd")
const StatRadar = preload("res://scripts/frontend/stat_radar.gd")
const Profiles = preload("res://scripts/battle/profile_store.gd")
const Progression = preload("res://scripts/battle/progression.gd")
const GOLD := Color("d4ba80")
const PAPER := Color("ece8dc")
const MUTED := Color("99aaac")
const TEAL := Color("8bbdb6")
const INK := Color("101e26")

@export var character_scene: PackedScene
@export var first_job_scenes: Dictionary[String, PackedScene] = {}

var profile: Dictionary = {}
var is_demo := false
var store_path := Profiles.DEFAULT_PATH
var _store: RefCounted
var _session: Node3D
var _session_url := ""
var _connecting := false
var _enter_after_connect := false
var _notice_message := ""
var _allocation_pending := false
var current_page := "title"
var tree_preview_female := false
var _page: Control
var _content: VBoxContainer
var _popup: PopupPanel
var _previous_focus: Control
var _background: Control


func _ready() -> void:
	_store = Profiles.new(store_path)
	profile = _store.display_profile(_store.endpoint())
	var ui_theme := Theme.new()
	ui_theme.default_font = load("res://assets/frontend/ui.otf")
	ui_theme.default_font_size = 16
	ui_theme.set_color("font_color", "Label", PAPER)
	ui_theme.set_color("font_color", "Button", PAPER)
	ui_theme.set_color("font_hover_color", "Button", GOLD)
	ui_theme.set_color("font_focus_color", "Button", GOLD)
	ui_theme.set_stylebox("normal", "Button", _style(Color("172a33"), Color("3e5054"), 7, 12))
	ui_theme.set_stylebox("hover", "Button", _style(Color("243b43"), GOLD, 7, 12))
	ui_theme.set_stylebox("pressed", "Button", _style(Color("31474b"), GOLD, 7, 12))
	ui_theme.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, GOLD, 7, 0, 2))
	ui_theme.set_constant("outline_size", "Button", 0)
	theme = ui_theme
	_build_background()
	show_title()


func _build_background() -> void:
	_background = Control.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := TextureRect.new()
	background.texture = load("res://assets/frontend/kingdom-background.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.06, 0.09, 0.90)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _clear(page_name: String) -> void:
	current_page = page_name
	if is_instance_valid(_popup):
		_popup.queue_free()
		_popup = null
	if is_instance_valid(_page):
		remove_child(_page)
		_page.queue_free()
	_page = MarginContainer.new()
	_page.name = page_name.capitalize() + "Page"
	add_child(_page)
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		_page.add_theme_constant_override("margin_" + side, 28)
	_content = _column(_page, 16)


func show_title() -> void:
	_clear("title")
	var header := _row(_content)
	_label(header, "S E L E S I A   /   O N L I N E   P V P", 14, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(header, "王国で、生きる。", 14, MUTED)
	_spacer(_content)
	var center := CenterContainer.new()
	_content.add_child(center)
	var column := _column(center, 16)
	column.custom_minimum_size.x = 460
	_label(column, "—  王 都 セ レ シ ア  —", 19, GOLD, true)
	_label(column, "P V P", 96, PAPER, true)
	_label(column, "剣を取り、自分だけの道を。", 20, PAPER, true)
	_label(column, "戦闘  /  冒険  /  成長  /  転職", 15, MUTED, true)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	column.add_child(gap)
	var start := _button(column, "START   ›", show_home, "StartButton")
	start.custom_minimum_size.y = 64
	start.add_theme_font_size_override("font_size", 24)
	start.add_theme_color_override("font_color", GOLD)
	start.add_theme_stylebox_override("normal", _style(Color("23343b"), GOLD, 7, 14))
	_label(column, "タップしてホームへ", 13, MUTED, true)
	_spacer(_content)
	var footer := _row(_content)
	_label(footer, "王都セレシア", 14, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(footer, "時間無制限 PvP   ·   王都セレシア", 13, MUTED)
	start.grab_focus()
	print("FRONTEND_READY title")


func show_home() -> void:
	show()
	_clear("home")
	var job := _current_job()
	var header := _row(_content, 20)
	var identity := _column(header, 4)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := _row(identity, 14)
	_label(name_row, str(profile["username"]), 27)
	_label(name_row, "Lv. %d" % int(profile["level"]), 25, GOLD)
	_label(identity, "%s  /  第一職業     ·     名声  %s" % [job["name"], profile["fame"]], 14, MUTED)
	var experience := _column(header, 5)
	experience.custom_minimum_size.x = 290
	var required := int(profile["level"]) * 100
	_label(experience, "次のレベルまで  %d EXP" % maxi(0, required - int(profile["exp"])), 16, PAPER)
	var bar := ProgressBar.new()
	bar.name = "ExperienceBar"
	bar.show_percentage = false
	bar.max_value = required
	bar.value = int(profile["exp"])
	bar.custom_minimum_size.y = 5
	bar.add_theme_stylebox_override("background", _style(Color("293b43"), Color.TRANSPARENT, 2, 0))
	bar.add_theme_stylebox_override("fill", _style(TEAL, Color.TRANSPARENT, 2, 0))
	experience.add_child(bar)
	_label(experience, "%d / %d EXP" % [int(profile["exp"]), required], 12, MUTED)
	var wallet := _panel(header, 18)
	wallet.custom_minimum_size.x = 190
	var money := _column(wallet, 2)
	_label(money, "所持金", 12, MUTED)
	_label(money, _number(int(profile["gold"])), 26, GOLD)

	var scroll := ScrollContainer.new()
	scroll.name = "HomeScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)
	var body := _row(scroll, 18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.y = 440
	_build_status(body)
	var character_panel := _panel(body, 16)
	character_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var character_column := _column(character_panel, 8)
	var character_header := _row(character_column)
	_label(character_header, "MY CHARACTER", 12, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(character_header, "第一職業  ·  " + str(job["name"]), 13, MUTED)
	var slot := CharacterSlot.new()
	slot.name = "PlayerCharacterSlot"
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.custom_minimum_size = Vector2(180, 150)
	character_column.add_child(slot)
	var home_scene := character_scene if character_scene != null else CharacterCatalog.scene_for(str(job["id"]), bool(profile.get("female", false)))
	slot.display_scene(home_scene, not _equipped_weapon().is_empty())
	_label(character_column, "%s  ·  %s" % [job["name"], "女性" if bool(profile.get("female", false)) else "男性"], 15, MUTED, true)
	var skill_card := _panel(character_column, 12, Color("20333a"))
	var selected_skill := _row(skill_card)
	_label(selected_skill, "職業スキル", 12, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(selected_skill, "%s   Lv. %d" % [job["skill"], _skill_level(job)], 16, GOLD)

	var right := _column(body, 14)
	right.custom_minimum_size.x = 288
	var equipment_panel := _panel(right, 12)
	equipment_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var equipment := _column(equipment_panel, 4)
	_label(equipment, "装備", 20)
	_label(equipment, "EQUIPMENT", 11, GOLD)
	_equipment_row(equipment, "武器", _equipped_weapon())
	var slots := {"head": "頭", "body": "胴", "legs": "脚", "feet": "足"}
	for key in slots:
		_equipment_row(equipment, slots[key], str(profile["equipment"].get(key, "")))
	_spacer(equipment)
	_button(equipment, "保有武器  %d   ›" % profile["owned_weapons"].size(), show_weapons, "OwnedWeaponsButton")
	var skill_panel := _panel(right, 16)
	var skills := _column(skill_panel, 5)
	_label(skills, "スキルレベル", 16)
	_label(skills, "%s   Lv. %d" % [job["skill"], _skill_level(job)], 18, GOLD)
	_button(skills, "スキル詳細   ›", func() -> void: show_job_detail(job), "SkillDetailButton")
	_build_navigation()
	print("FRONTEND_PAGE home")


func _build_status(parent: Node) -> void:
	var panel := _panel(parent, 18)
	panel.custom_minimum_size.x = 310
	var column := _column(panel, 10)
	_label(column, "ステータス", 20)
	_label(column, "CHARACTER STATUS", 11, GOLD)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for key in StatRadar.KEYS:
		var cell := _column(grid, 3)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(cell, key, 13, MUTED, true)
		_label(cell, _stat_number(profile["stats"].get(key, 0)), 25, PAPER, true)
		var spend := _button(cell, "+1", _spend_point.bind(str(key)), "Allocate_"+str(grid.get_child_count()-1))
		spend.custom_minimum_size = Vector2(48,30)
		spend.add_theme_font_size_override("font_size",13)
		spend.set_meta("stat",str(key))
		spend.disabled = not _can_allocate()
		spend.tooltip_text = "ホームで1ポイントを使う"
	var points := _label(column, "未使用ポイント  %d"%int(profile.get("unspent_points",0)), 16, GOLD, true)
	points.name = "UnspentPointsLabel"
	var radar := StatRadar.new()
	radar.name = "StatusRadar"
	radar.values = profile["stats"]
	radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	radar.custom_minimum_size.y = 145
	column.add_child(radar)
	_label(column, "撃破でレベルアップ → ポイントを配分", 11, MUTED, true)


func show_tree() -> void:
	_clear("tree")
	var heading := _row(_content)
	var titles := _column(heading, 5)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(titles, "スキルツリー", 29)
	_label(titles, "第一職業をタップして、スキルと転職先を確認", 15, MUTED)
	_label(heading, "外見プレビュー", 13, MUTED)
	for female in [false, true]:
		var gender := _button(heading, "女性" if female else "男性", _set_tree_gender.bind(female), "TreeFemaleButton" if female else "TreeMaleButton")
		gender.custom_minimum_size.x = 86
		if female == tree_preview_female:
			gender.add_theme_color_override("font_color", GOLD)
			gender.add_theme_stylebox_override("normal", _style(Color("2b3b3e"), GOLD, 7, 12))
	var scroll := ScrollContainer.new()
	scroll.name = "TreeScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)
	var grid := GridContainer.new()
	grid.custom_minimum_size.y = 400
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.name = "FirstJobGrid"
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	for job in Data.jobs():
		var button := _button(grid, "", func() -> void: show_job_detail(job), "Job_" + str(job["id"]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%sの詳細・第二職業を見る" % job["name"]
		button.accessibility_name = str(job["name"]) + "の詳細"
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 16)
		var row := _row(margin, 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot := CharacterSlot.new()
		slot.custom_minimum_size.x = 106
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slot)
		slot.name = "JobCharacter_" + str(job["id"])
		slot.display_scene(_job_scene(str(job["id"])))
		var info := _column(row, 7)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.custom_minimum_size.x = 185
		_spacer(info)
		_label(info, "第一職業", 11, GOLD)
		_label(info, job["name"], 26)
		_label(info, job["skill"], 15, TEAL)
		_label(info, "詳細を見る  ›", 13, MUTED)
		_label(info, "女性" if tree_preview_female else "男性", 11, MUTED)
		_spacer(info)
		# Containers must not consume the card's mouse/touch events.
		_ignore_mouse(margin)
	_build_navigation()
	print("FRONTEND_PAGE tree")


func _set_tree_gender(female: bool) -> void:
	tree_preview_female = female
	show_tree()
	var button := find_child("TreeFemaleButton" if female else "TreeMaleButton", true, false)
	if button is Button:
		button.grab_focus()


func _job_scene(job_id: String) -> PackedScene:
	var variant := job_id + ("_female" if tree_preview_female else "_male")
	return first_job_scenes.get(variant, first_job_scenes.get(job_id, CharacterCatalog.scene_for(job_id, tree_preview_female)))


func show_job_detail(job: Dictionary) -> void:
	var column := _open_popup(str(job["name"]) + "  /  第一職業")
	_label(column, job["tagline"], 17, MUTED)
	if _can_choose_character():
		_button(column,"この職業・外見で始める",_choose_first_job.bind(str(job["id"])),"ChooseFirstJobButton")
	var basics := _panel(column, 14)
	var info := _column(basics, 8)
	_label(info, "対応武器  ·  " + str(job["weapon"]), 16)
	_label(info, job["bonus"], 15, TEAL)
	var skill_level := "   Lv. %d" % _skill_level(job) if job["id"] == profile["job_id"] else "   未習得"
	_label(info, "職業スキル  ·  " + str(job["skill"]) + skill_level, 20, GOLD)
	_label(info, job["skill_description"], 15)
	_label(column, "第二職業への分岐   /   Lv.100で第一転職", 18, GOLD)
	for second in job["second_jobs"]:
		var branch := _panel(column, 14)
		var branch_column := _column(branch, 6)
		_label(branch_column, "└  " + str(second["name"]), 20)
		_label(branch_column, second["bonus"], 14, TEAL)
		_label(branch_column, second["skills"], 15, PAPER, false, true)
	_label(column, "スキルの成長", 18, GOLD)
	_label(column, "攻撃スキル：そのスキルで敵を倒すとスキルEXPを獲得。\n支援スキル：支援した味方が敵を倒すとスキルEXPを獲得。\n使用回数だけでは成長しません。必要EXP・上限は未定です。", 14, MUTED, false, true)
	_label(column, "職業・スキルの内容は現在の構想です。この画面では転職しません。", 12, MUTED, false, true)
	print("FRONTEND_DETAIL ", job["id"])


func show_weapons() -> void:
	var column := _open_popup("保有武器")
	_label(column, "職業に対応する武器だけを装備できます。", 15, MUTED)
	if profile["owned_weapons"].is_empty():
		var panel := _panel(column, 28)
		var empty := _column(panel, 12)
		_label(empty, "まだ武器を持っていません", 22, PAPER, true)
		_label(empty, "冒険で手に入れた武器は、ここに表示されます。\n武器を装備していないときの通常攻撃は素手です。", 15, MUTED, true, true)
	else:
		for weapon in profile["owned_weapons"]:
			var panel := _panel(column, 14)
			var item := _column(panel, 5)
			var equipped := "  ·  装備中" if bool(weapon.get("equipped", false)) else ""
			_label(item, str(weapon.get("name", "武器")) + equipped, 20, GOLD)
			_label(item, "対応武器  %s   /   %s" % [weapon.get("type", "未設定"), weapon.get("rank", "ランク未設定")], 14, MUTED)
			_label(item, str(weapon.get("description", "")), 14, PAPER, false, true)
	_label(column, "所持金  " + _number(int(profile["gold"])), 18, GOLD)
	print("FRONTEND_WEAPONS")


func _open_popup(title_text: String) -> VBoxContainer:
	if is_instance_valid(_popup):
		remove_child(_popup)
		_popup.queue_free()
	_previous_focus = get_viewport().gui_get_focus_owner()
	_popup = PopupPanel.new()
	_popup.name = "DetailPopup"
	_popup.theme = theme
	_popup.add_theme_stylebox_override("panel", _style(INK, GOLD, 12, 22))
	add_child(_popup)
	var layout := _column(_popup, 16)
	var header := _row(layout)
	_label(header, title_text, 25).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := _button(header, "閉じる  ×", _close_popup, "CloseDetailButton")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var details := _column(scroll, 16)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_popup.popup_hide.connect(func() -> void:
		if is_instance_valid(_previous_focus):
			_previous_focus.grab_focus()
	)
	_popup.popup_centered_clamped(Vector2i(820, 590), 0.92)
	close.grab_focus()
	return details


func _close_popup() -> void:
	if is_instance_valid(_popup):
		_popup.hide()


func _build_navigation() -> void:
	var nav := _row(_content, 12)
	nav.custom_minimum_size.y = 56
	var home := _button(nav, "ホーム", show_home, "HomeButton")
	home.custom_minimum_size.x = 125
	var tree := _button(nav, "スキルツリー", show_tree, "SkillTreeButton")
	tree.custom_minimum_size.x = 180
	_button(nav, "保有武器", show_weapons, "WeaponsButton").custom_minimum_size.x = 135
	_button(nav, "プレイヤー設定", show_player_settings, "PlayerSettingsButton").custom_minimum_size.x = 130
	var status := _label(nav, _connection_caption(), 12, MUTED)
	status.name = "ConnectionStatus"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var battle := _button(nav,"接続中…" if _connecting else "バトルへ   ›",_request_battle,"BattleButton")
	battle.custom_minimum_size.x = 150
	battle.disabled = _connecting
	battle.add_theme_color_override("font_color",GOLD)
	_button(nav, "タイトルへ", show_title, "TitleButton")
	var selected := home if current_page == "home" else tree
	selected.add_theme_color_override("font_color", GOLD)
	selected.add_theme_stylebox_override("normal", _style(Color("2b3b3e"), GOLD, 7, 12))
	home.grab_focus()


func set_profile(snapshot: Dictionary) -> void:
	# This presentation setter never grants EXP or spends points. Only the
	# network callback stores a server-confirmed snapshot.
	var identity: Dictionary = _store.identity_for(_store.endpoint()) if _store!=null else {"player_id":"display"}
	profile = Progression.new_profile(str(identity["player_id"]))
	for key in snapshot:
		if key in ["stats", "skills", "equipment"] and snapshot[key] is Dictionary:
			profile[key].merge(snapshot[key], true)
		else:
			profile[key] = snapshot[key]
	profile["level"] = maxi(1, int(profile["level"]))
	profile["exp"] = maxi(0, int(profile["exp"]))
	is_demo = false
	if is_node_ready() and current_page == "home" and visible:
		show_home()



func _connection_caption() -> String:
	if not _notice_message.is_empty(): return _notice_message
	if _connecting: return "対戦サーバーに接続中"
	if _connected(): return "接続済み · 撃破したときだけEXP獲得"
	return "対戦待機 · サーバー未接続"

func _connected() -> bool:
	return is_instance_valid(_session) and _session.has_method("is_connected_to_server") and _session.is_connected_to_server()

func _can_allocate() -> bool:
	return current_page=="home" and _connected() and _session.is_in_home() and not _allocation_pending and int(profile.get("unspent_points",0))>0

func _can_choose_character() -> bool:
	return _store!=null and not _store.has_registered_identity(_store.endpoint()) and not _connected() and not _connecting

func _stat_number(value: Variant) -> String:
	var number := float(value)
	return str(roundi(number)) if is_equal_approx(number,roundf(number)) else "%.1f"%number

func _spend_point(stat: String) -> void:
	if not _can_allocate(): return
	_allocation_pending=true
	_session.request_allocate(stat,1)
	show_home()

func _request_battle() -> void:
	_notice_message=""
	if _connected():
		_session.enter_battle()
		return
	_enter_after_connect=true
	_connecting=true
	var url: String=_store.endpoint()
	if is_instance_valid(_session):
		_session.queue_free()
		_session=null
	var script=load("res://scripts/battle/arena_client.gd")
	if script==null:
		_connection_failed("対戦画面を読み込めませんでした")
		return
	_session=script.new()
	_session.name="ArenaSession"
	_session_url=url
	get_tree().root.add_child(_session)
	_session.home_requested.connect(_returned_home)
	_session.profile_received.connect(_received_profile)
	_session.identity_received.connect(_received_identity)
	_session.connection_failed.connect(_connection_failed)
	_session.operation_failed.connect(_operation_failed)
	_session.battle_started.connect(_battle_started)
	_session.start_connection(url,_store.identity_for(url))
	show_home()

func _battle_started() -> void:
	_connecting=false
	_enter_after_connect=false
	if is_instance_valid(_popup): _popup.hide()
	hide()

func _returned_home(snapshot: Dictionary) -> void:
	_enter_after_connect=false
	_connecting=false
	_allocation_pending=false
	_received_profile(snapshot)
	show_home()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _received_identity(identity: Dictionary) -> void:
	_store.remember_identity(_session_url,identity)

func _received_profile(snapshot: Dictionary) -> void:
	var clean: Dictionary=Progression.normalize_profile(snapshot)
	if clean.is_empty(): return
	_store.remember_snapshot(_session_url,clean)
	_connecting=false
	if clean!=profile: _allocation_pending=false
	_notice_message=""
	if clean!=profile:
		set_profile(clean)
	elif current_page=="home" and visible:
		# Pending allocation or first welcome may need to re-enable controls even
		# when the authoritative numbers did not change.
		var status=find_child("ConnectionStatus",true,false)
		if status is Label: status.text=_connection_caption()
		var battle=find_child("BattleButton",true,false)
		if battle is Button: battle.disabled=false; battle.text="バトルへ   ›"
		for node in find_children("Allocate_*","Button",true,false): node.disabled=not _can_allocate()
	if _enter_after_connect and _connected():
		_enter_after_connect=false
		_session.call_deferred("enter_battle")

func _connection_failed(message: String) -> void:
	_connecting=false
	_enter_after_connect=false
	_allocation_pending=false
	_notice_message=message
	show_home()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _operation_failed(message: String) -> void:
	_allocation_pending=false
	_notice_message=message
	if visible and current_page=="home": show_home()

func _choose_first_job(job_id: String) -> void:
	if not _can_choose_character(): return
	_store.configure(_store.endpoint(),str(profile.get("username","冒険者")),job_id,tree_preview_female)
	profile=_store.display_profile(_store.endpoint())
	_close_popup()
	show_home()

func show_player_settings() -> void:
	var column:=_open_popup("プレイヤー設定")
	var changeable:=_can_choose_character()
	_label(column,"名前・職業・外見は初回の対戦接続前に選べます。",14,MUTED,false,true)
	_label(column,"プレイヤー名",14,GOLD)
	var name_edit:=LineEdit.new()
	name_edit.name="PlayerNameEdit"
	name_edit.text=str(profile.get("username","冒険者"))
	name_edit.max_length=24
	name_edit.editable=changeable
	column.add_child(name_edit)
	var choices:=_row(column,14)
	var job_choice:=OptionButton.new()
	job_choice.name="FirstJobChoice"
	job_choice.custom_minimum_size=Vector2(240,44)
	var jobs:=Data.jobs()
	for i in range(jobs.size()):
		job_choice.add_item(str(jobs[i]["name"]))
		if jobs[i]["id"]==profile["job_id"]: job_choice.select(i)
	job_choice.disabled=not changeable
	choices.add_child(job_choice)
	var gender:=OptionButton.new()
	gender.name="GenderChoice"
	gender.custom_minimum_size=Vector2(160,44)
	gender.add_item("男性")
	gender.add_item("女性")
	gender.select(1 if bool(profile.get("female",false)) else 0)
	gender.disabled=not changeable
	choices.add_child(gender)
	_label(column,"対戦サーバー",14,GOLD)
	var endpoint:=LineEdit.new()
	endpoint.name="ServerUrlEdit"
	endpoint.text=_store.endpoint()
	endpoint.placeholder_text="ws://サーバーのアドレス:8910"
	column.add_child(endpoint)
	var error:=_label(column,"",14,Color("efb3a4"),false,true)
	_button(column,"保存",func() -> void:
		var url:=endpoint.text.strip_edges()
		if not (url.begins_with("ws://") or url.begins_with("wss://")) or url.contains(" ") or url.trim_prefix("ws://").trim_prefix("wss://").is_empty():
			error.text="対戦サーバーは ws:// または wss:// で指定してください。"
			return
		var old_url: String=_store.endpoint()
		var job_id: String=str(jobs[job_choice.selected]["id"]) if changeable else str(profile["job_id"])
		_store.configure(url,name_edit.text if changeable else str(profile["username"]),job_id,gender.selected==1 if changeable else bool(profile.get("female",false)))
		if url!=old_url and is_instance_valid(_session):
			_session.queue_free()
			_session=null
			_connecting=false
			_allocation_pending=false
		profile=_store.display_profile(url)
		_notice_message=""
		_close_popup()
		show_home()
	,"SavePlayerSettingsButton")

func _exit_tree() -> void:
	if is_instance_valid(_session): _session.queue_free()


func _current_job() -> Dictionary:
	for job in Data.jobs():
		if job["id"] == profile["job_id"]:
			return job
	return Data.jobs()[0]


func _skill_level(job: Dictionary) -> int:
	return int(profile["skills"].get(job.get("skill_id", "strong_strike"), 0))


func _equipped_weapon() -> String:
	for weapon in profile["owned_weapons"]:
		if bool(weapon.get("equipped", false)):
			return str(weapon.get("name", ""))
	return ""


func _equipment_row(parent: Node, slot_name: String, item_name: String) -> void:
	var row := _row(parent, 12)
	row.custom_minimum_size.y = 28
	_label(row, slot_name, 14, GOLD).custom_minimum_size.x = 40
	var item := _label(row, "未装備" if item_name.is_empty() else item_name, 14, MUTED if item_name.is_empty() else PAPER)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item.tooltip_text = item.text


func _number(value: int) -> String:
	var digits := str(value)
	var output := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			output += ","
		output += digits[i]
	return output


func _style(background: Color, edge: Color, radius: int = 8, padding: int = 16, border: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _panel(parent: Node, padding: int = 16, color: Color = Color("14252e")) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(color, Color("34474d"), 10, padding))
	parent.add_child(panel)
	return panel


func _column(parent: Node, gap: int = 10) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", gap)
	parent.add_child(column)
	return column


func _row(parent: Node, gap: int = 10) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	parent.add_child(row)
	return row


func _label(parent: Node, text: String, font_size: int = 16, color: Color = PAPER, centered: bool = false, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable, node_name: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	if not node_name.is_empty():
		button.name = node_name
	button.pressed.connect(action, CONNECT_DEFERRED)
	parent.add_child(button)
	return button


func _spacer(parent: Node) -> void:
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(space)


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
