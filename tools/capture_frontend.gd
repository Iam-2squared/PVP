extends SceneTree
## Render frontend screenshots with a display, e.g. DISPLAY=:1 godot --path .
## --rendering-method gl_compatibility --audio-driver Dummy
## --script res://tools/capture_frontend.gd -- --page=home --output=/tmp/home.png
## Pages: title, home, tree, warrior, mage, scout, archer, cleric, artisan, weapons.
## Optional --size=844,390 exercises real viewport scaling on a landscape window.
## --exercise-input tests mouse, touch, gender previews and Escape navigation.
## --female renders the female home character / first-job previews.

var page := "title"
var output := "/tmp/frontend.png"
var window_size := Vector2i(1280, 720)
var exercise_input := false
var female := false
var argument_error := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--page="):
			page = argument.trim_prefix("--page=")
		elif argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				argument_error = "--size requires two positive integers, e.g. 844,390"
			else:
				window_size = Vector2i(int(parts[0]), int(parts[1]))
		elif argument == "--female":
			female = true
		elif argument == "--exercise-input":
			exercise_input = true
	_capture.call_deferred()

func _frames() -> void:
	for i in range(6):
		await process_frame

func _click(button: Control) -> void:
	var point := button.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = point
	root.push_input(up, true)
	await _frames()

func _touch(button: Control) -> void:
	# parse_input_event expects physical window coordinates, including letterboxing.
	var point := root.get_final_transform() * button.get_global_rect().get_center()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = point
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = point
	Input.parse_input_event(up)
	await _frames()

func _watchdog() -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 15
	root.add_child(timer)
	timer.timeout.connect(func() -> void:
		push_error("Frontend capture timed out; a display and Compatibility renderer are required.")
		quit(1)
	)
	timer.start()

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Capture needs a display, e.g. DISPLAY=:1; do not use --headless.")
		quit(1)
		return
	if not argument_error.is_empty() or window_size.x <= 0 or window_size.y <= 0:
		push_error(argument_error if not argument_error.is_empty() else "Window dimensions must be positive.")
		quit(1)
		return
	if not page in ["title", "home", "tree", "warrior", "mage", "scout", "archer", "cleric", "artisan", "weapons"]:
		push_error("Unknown frontend page: " + page)
		quit(1)
		return
	if not output.is_absolute_path():
		output = ProjectSettings.globalize_path("res://" + output)
	if not DirAccess.dir_exists_absolute(output.get_base_dir()):
		push_error("Output directory does not exist: " + output.get_base_dir())
		quit(1)
		return
	_watchdog()
	root.size = window_size
	root.gui_embed_subwindows = true
	var frontend = load("res://scenes/frontend/start_home.tscn").instantiate()
	root.add_child(frontend)
	current_scene = frontend
	await _frames()
	if exercise_input:
		await _click(frontend.find_child("StartButton", true, false))
		if frontend.current_page != "home":
			push_error("Mouse click did not enter home")
			quit(1)
			return
		await _touch(frontend.find_child("SkillTreeButton", true, false))
		if frontend.current_page != "tree":
			push_error("Screen touch did not enter skill tree")
			quit(1)
			return
		await _touch(frontend.find_child("Job_mage", true, false))
		if not is_instance_valid(frontend._popup) or not frontend._popup.visible:
			push_error("Screen touch did not open mage details")
			quit(1)
			return
		await _frames()
		# Route through the root in window coordinates to reach an embedded popup.
		var close = frontend._popup.find_child("CloseDetailButton", true, false)
		var point = close.get_global_rect().get_center() + Vector2(frontend._popup.position)
		var down := InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.position = point
		root.push_input(down, true)
		await process_frame
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = point
		root.push_input(up, true)
		await _frames()
		if frontend._popup.visible:
			push_error("Mouse click did not close details")
			quit(1)
			return
		await _touch(frontend.find_child("Job_warrior", true, false))
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		root.push_input(escape, true)
		await _frames()
		if frontend._popup.visible:
			push_error("Escape did not close details")
			quit(1)
			return
		await _touch(frontend.find_child("TreeFemaleButton", true, false))
		if not frontend.tree_preview_female:
			push_error("Touch did not switch female previews")
			quit(1)
			return
		await _touch(frontend.find_child("TreeMaleButton", true, false))
		if frontend.tree_preview_female:
			push_error("Touch did not switch male previews")
			quit(1)
			return
		print("FRONTEND_REAL_INPUT_OK mouse_start touch_tree touch_mage mouse_close escape_close touch_gender")
	frontend.profile["female"] = female
	frontend.tree_preview_female = female
	if page == "title":
		frontend.show_title()
	elif page == "home":
		frontend.show_home()
	elif page == "tree":
		frontend.show_tree()
	elif page == "weapons":
		frontend.show_home()
		frontend.show_weapons()
	elif page != "title":
		frontend.show_tree()
		for job in frontend.Data.jobs():
			if job["id"] == page:
				frontend.show_job_detail(job)
	await _frames()
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var result := frame.save_png(output)
	print(JSON.stringify({"page":page,"output":output,"viewport":str(frontend.get_viewport_rect()),"window_size":str(root.size),"save_error":result,"content_minimum":str(frontend._page.get_combined_minimum_size())}))
	quit(0 if result == OK else 1)
