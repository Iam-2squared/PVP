extends SceneTree
## Frontend behavior only: no generated city, player controller or save service.
## Run: godot --headless --path . --script res://tools/test_frontend.gd

const Data = preload("res://scripts/frontend/home_data.gd")
const Frontend = preload("res://scenes/frontend/start_home.tscn")
const CharacterSlot = preload("res://scripts/frontend/character_slot.gd")
var _passed := 0
var _failed := 0
var _ui: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/frontend/start_home.tscn", "project starts in frontend")
	_ui = Frontend.instantiate()
	root.add_child(_ui)
	await _frames()
	_check(_ui.current_page == "title", "startup shows title")
	_check(_ui.find_children("*", "Node3D", true, false).is_empty(), "startup does not load city or Player")
	_check(_ui.find_children("*", "CharacterBody3D", true, false).is_empty(), "startup has no gameplay controller")
	_press("StartButton")
	await _frames()
	_check(_ui.current_page == "home", "Start pressed opens home")
	_check_page_buttons_fit("home")
	_check(_has_label("Lv. 1"), "home shows level")
	_check(_has_label("次のレベルまで  100 EXP"), "home shows remaining level EXP")
	_check(_has_label("0 / 100 EXP"), "home shows current level EXP")
	for key in ["筋力", "耐久力", "精神力", "HP", "MP", "回復力", "敏捷力", "器用さ"]:
		_check(_has_label(key), "home shows stat " + key)
	_check(_has_label("強撃   Lv. 1"), "home shows skill level")
	_check(_has_label("表示サンプル · 初期値未確定"), "demo data is identified")
	_check(_ui.find_child("PlayerCharacterSlot", true, false) != null, "home reserves central character slot")
	_press("OwnedWeaponsButton")
	await _frames()
	_check(_ui.get("_popup").visible and _has_label("まだ武器を持っていません"), "empty inventory opens")
	_press("CloseDetailButton")
	await _frames()
	_check(not _ui.get("_popup").visible, "inventory closes")
	_press("SkillTreeButton")
	await _frames()
	_check(_ui.current_page == "tree", "skill tree navigation")
	_check_page_buttons_fit("tree")
	var jobs := Data.jobs()
	_check(jobs.size() == 6, "six first jobs")
	for job in jobs:
		var button: Button = _ui.find_child("Job_" + str(job["id"]), true, false)
		_check(is_instance_valid(button), "job card exists " + str(job["id"]))
		if not is_instance_valid(button):
			continue
		button.pressed.emit()
		await _frames()
		var popup: PopupPanel = _ui.get("_popup")
		_check(popup.visible, "job detail opens " + str(job["id"]))
		_check(_has_label(str(job["name"]) + "  /  第一職業"), "job detail title " + str(job["id"]))
		_check(_has_label(str(job["skill_description"])), "job detail skill " + str(job["id"]))
		for second in job["second_jobs"]:
			_check(_has_label("└  " + str(second["name"])), "second branch " + str(second["name"]))
		_check(not _joined_labels().contains("第三職業"), "later jobs hidden " + str(job["id"]))
		_press("CloseDetailButton")
		await _frames()
		_check(not popup.visible, "job detail closes " + str(job["id"]))
	_press("HomeButton")
	await _frames()
	var snapshot := {
		"username": "検証用冒険者", "level": 12, "exp": 340, "gold": 12345,
		"stats": {"筋力": 15, "耐久力": 23, "精神力": 31, "HP": 405, "MP": 63, "回復力": 17, "敏捷力": 28, "器用さ": 39},
		"skills": {"strong_strike": 4},
		"equipment": {"head": "検証用の兜"},
		"owned_weapons": [{"name": "検証用の剣", "type": "剣", "rank": "コモン", "equipped": true, "description": "表示確認のための武器"}],
	}
	_ui.set_profile(snapshot)
	await _frames()
	_check(_has_label("検証用冒険者"), "profile injection updates name")
	_check(_has_label("Lv. 12"), "profile injection updates level")
	_check(_has_label("次のレベルまで  860 EXP"), "remaining EXP follows level times 100")
	_check(_has_label("340 / 1200 EXP"), "current EXP displayed")
	_check(_has_label("12,345"), "money formatted")
	_check(_has_label("強撃   Lv. 4"), "injected skill level")
	for value in snapshot["stats"].values():
		_check(_has_label(str(value)), "injected stat " + str(value))
	_check(_has_label("検証用の兜"), "injected armor")
	_check(_has_label("検証用の剣"), "equipped weapon appears in equipment")
	_check(_has_label("プレイヤー情報"), "real snapshot replaces demo marker")
	_press("OwnedWeaponsButton")
	await _frames()
	_check(_has_label("検証用の剣  ·  装備中"), "inventory marks equipped weapon")
	_check(_has_label("対応武器  剣   /   コモン"), "inventory weapon type and rank")
	_check(_has_label("所持金  12,345"), "inventory shows wallet")
	_press("CloseDetailButton")
	await _frames()
	await _check_character_slots()
	_check(_ui.find_children("*", "CharacterBody3D", true, false).is_empty(), "frontend remains independent of gameplay player")
	_ui.queue_free()
	await _frames()
	print("FRONTEND_TEST_RESULT ", JSON.stringify({"passed": _passed, "failed": _failed}))
	quit(1 if _failed > 0 else 0)


func _check_character_slots() -> void:
	var model := Node3D.new()
	model.name = "VerificationModel"
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	model.add_child(mesh)
	mesh.owner = model
	var packed := PackedScene.new()
	_check(packed.pack(model) == OK, "test model packs")
	model.free()
	_ui.character_scene = packed
	_ui.show_home()
	await _frames()
	var slot: Control = _ui.find_child("PlayerCharacterSlot", true, false)
	var viewports := slot.find_children("*", "SubViewport", true, false)
	_check(viewports.size() == 1, "optional character creates viewport")
	_check(slot.find_child("VerificationModel", true, false) != null, "optional character scene loaded")
	_check(not slot.get("_placeholder"), "optional character replaces placeholder")
	var other_slot := CharacterSlot.new()
	_ui.add_child(other_slot)
	other_slot.display_scene(packed)
	await _frames()
	var other_viewport: SubViewport = other_slot.get("_viewport")
	if viewports.size() == 1:
		_check(viewports[0].find_world_3d() != other_viewport.find_world_3d(), "character slots have independent worlds")
	other_slot.queue_free()


func _press(node_name: String) -> void:
	var button: Button = _ui.find_child(node_name, true, false)
	_check(is_instance_valid(button), "button exists " + node_name)
	if is_instance_valid(button):
		button.pressed.emit()


func _has_label(expected: String) -> bool:
	for label in _ui.find_children("*", "Label", true, false):
		if label.text == expected:
			return true
	return false


func _check_page_buttons_fit(page_name: String) -> void:
	var visible_rect := root.get_visible_rect()
	for button in _ui.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			_check(visible_rect.encloses(button.get_global_rect()), "%s button fits viewport: %s" % [page_name, button.name])


func _joined_labels() -> String:
	var result := ""
	for label in _ui.find_children("*", "Label", true, false):
		result += label.text + "\n"
	return result


func _frames() -> void:
	for frame in range(4):
		await process_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("PASS ", description)
	else:
		_failed += 1
		push_error("FAIL " + description)
