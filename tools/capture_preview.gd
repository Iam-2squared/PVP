extends SceneTree
## Render the real Godot scene to PNG; run with an actual display, not --headless.
## Example: DISPLAY=:99 godot --path . --audio-driver Dummy --script
## res://tools/capture_preview.gd -- --overview --output=/tmp/kingdom.png
## Optional framing: --position=x,y,z --yaw=degrees --pitch=degrees
## --overview-size=meters --camera-position=x,y,z --camera-target=x,y,z

var output := "/tmp/kingdom-preview.png"
var overview := false
var hide_hud := false
var wait_seconds := 1.5
var player_position := Vector3.ZERO
var camera_position := Vector3.ZERO
var camera_target := Vector3.ZERO
var yaw_degrees := 0.0
var pitch_degrees := 0.0
var overview_size := 0.0
var has_player_position := false
var has_camera_position := false
var has_camera_target := false
var has_yaw := false
var has_pitch := false
var argument_error := ""
var tour_id := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--overview":
			overview = true
		elif argument == "--hide-hud":
			hide_hud = true
		elif argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--tour="):
			tour_id=argument.trim_prefix("--tour=")
		elif argument.begins_with("--wait="):
			wait_seconds = argument.trim_prefix("--wait=").to_float()
		elif argument.begins_with("--position="):
			player_position = _parse_vector(argument.trim_prefix("--position="), "--position")
			has_player_position = true
		elif argument.begins_with("--yaw="):
			yaw_degrees = _parse_float(argument.trim_prefix("--yaw="), "--yaw")
			has_yaw = true
		elif argument.begins_with("--pitch="):
			pitch_degrees = _parse_float(argument.trim_prefix("--pitch="), "--pitch")
			has_pitch = true
		elif argument.begins_with("--overview-size="):
			overview_size = _parse_float(argument.trim_prefix("--overview-size="), "--overview-size")
			if overview_size <= 0.0:
				argument_error = "--overview-size must be greater than zero"
		elif argument.begins_with("--camera-position="):
			camera_position = _parse_vector(argument.trim_prefix("--camera-position="), "--camera-position")
			has_camera_position = true
		elif argument.begins_with("--camera-target="):
			camera_target = _parse_vector(argument.trim_prefix("--camera-target="), "--camera-target")
			has_camera_target = true
	_capture.call_deferred()


func _parse_float(value: String, flag: String) -> float:
	if not value.is_valid_float():
		argument_error = flag + " requires a valid number"
		return 0.0
	return value.to_float()


func _parse_vector(value: String, flag: String) -> Vector3:
	var components := value.split(",", false)
	if components.size() != 3:
		argument_error = flag + " requires three comma-separated numbers"
		return Vector3.ZERO
	return Vector3(_parse_float(components[0], flag), _parse_float(components[1], flag), _parse_float(components[2], flag))


func _capture() -> void:
	if not argument_error.is_empty():
		push_error(argument_error)
		quit(1)
		return
	var scene_path: String = "res://scenes/main.tscn"
	if scene_path.is_empty():
		scene_path = "res://scenes/main.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Cannot load scene: " + scene_path)
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(wait_seconds).timeout
	var player := root.find_child("Player", true, false)
	if not tour_id.is_empty() and player!=null and player.has_method("get_preview_locations"):
		var found:=false
		var locations: Array=player.get_preview_locations()
		for i in range(locations.size()):
			if str(locations[i].get("id",""))==tour_id:
				player.visit_preview_location(i)
				player.set_physics_process(false)
				found=true
				break
		if not found:
			push_error("Unknown tour location: "+tour_id)
			quit(1)
			return
	if (has_player_position or has_yaw or has_pitch) and not player is Node3D:
		push_error("Player framing arguments require a Player Node3D")
		quit(1)
		return
	if player is Node3D:
		# Static framing must not drift down a slope or fall while the final frame renders.
		if has_player_position or has_camera_position or has_camera_target:
			player.set_physics_process(false)
		if has_player_position:
			player.global_position = player_position
		if has_yaw:
			player.rotation.y = deg_to_rad(yaw_degrees)
		if has_pitch:
			var first_person: Variant = player.get("camera")
			if first_person is Camera3D:
				first_person.rotation.x = deg_to_rad(pitch_degrees)
		if overview_size > 0.0:
			var aerial: Variant = player.get("aerial_camera")
			if aerial is Camera3D:
				aerial.size = overview_size
	if player != null and overview and player.has_method("set_overview"):
		player.call("set_overview", true)
	if player != null and hide_hud:
		var hud: Variant = player.get("hud")
		if hud is CanvasLayer:
			hud.hide()
	var selected_camera := root.get_camera_3d()
	if has_camera_position or has_camera_target:
		if selected_camera == null:
			push_error("Camera framing arguments require a current Camera3D")
			quit(1)
			return
		if has_camera_position:
			selected_camera.global_position = camera_position
		if has_camera_target:
			if selected_camera.global_position.distance_squared_to(camera_target) < 0.0001:
				push_error("Camera position and target must be different")
				quit(1)
				return
			var look_direction := (camera_target - selected_camera.global_position).normalized()
			var up := Vector3.FORWARD if absf(look_direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
			selected_camera.look_at(camera_target, up)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("No rendered frame. Use an X11 display and the Compatibility renderer.")
		quit(1)
		return
	var error := image.save_png(output)
	if error != OK:
		push_error("PNG save failed: " + str(error))
		quit(1)
		return
	var metrics := {
		"screenshot": output,
		"width": image.get_width(),
		"height": image.get_height(),
		"overview": overview,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
	}
	if selected_camera != null:
		var p := selected_camera.global_position
		var r := selected_camera.global_rotation_degrees
		metrics["camera_position"] = [p.x, p.y, p.z]
		metrics["camera_rotation_degrees"] = [r.x, r.y, r.z]
	print(JSON.stringify(metrics))
	quit()
