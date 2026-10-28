extends SceneTree
## Compare the unchanged city at fixed camera poses, with no frame-rate cap.
## Software-renderer timings are comparative measurements, not phone FPS.

var output := "res://captures/render-benchmark"
var frames := 20
var poses := [
	{"id":"south_gate", "feet":Vector3(0,2.15,150), "target":Vector3(0,3.8,0)},
	{"id":"market_street", "feet":Vector3(-65,2.15,46), "target":Vector3(-140,3.8,46)},
	{"id":"palace_forecourt", "feet":Vector3(22,14.15,-32), "target":Vector3(0,32,-82)},
	{"id":"overview", "feet":Vector3(0,2.15,150), "camera":Vector3(300,320,380), "target":Vector3(0,20,0)},
]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		elif arg.begins_with("--frames="): frames=maxi(10,int(arg.trim_prefix("--frames=")))
	_run.call_deferred()

func _percentile(values:Array[float],fraction:float)->float:
	var sorted:=values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size()-1,int(sorted.size()*fraction))]

func _run()->void:
	if DisplayServer.get_name()=="headless":
		push_error("This benchmark requires a real render target.")
		quit(1)
		return
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var arena=load("res://scripts/battle/arena_client.gd").new()
	root.add_child(arena)
	var start:=Time.get_ticks_usec()
	arena._ensure_world()
	var load_us:=Time.get_ticks_usec()-start
	var player:CharacterBody3D=arena.player
	player.set_physics_process(false)
	player.set_process(false)
	player.hud.visible=false
	player.hud.set_process(false)
	var camera:Camera3D=player.camera
	var report:={"viewport":[1280,720],"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"renderer":RenderingServer.get_video_adapter_name(),"load_us":load_us,"measurements":[]}
	for pose:Dictionary in poses:
		player.position=pose.feet
		player.rotation=Vector3.ZERO
		camera.position=Vector3(0,1.65,0)
		if pose.has("camera"):camera.global_position=pose.camera
		camera.look_at(pose.target)
		arena.world._process(1.0)
		for i in range(8):await process_frame
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path(output.path_join(pose.id+".png")))
		var times:Array[float]=[]
		var process_ms:Array[float]=[]
		var physics_ms:Array[float]=[]
		var draw_calls:Array[float]=[]
		var primitives:Array[float]=[]
		var previous:=Time.get_ticks_usec()
		for i in range(frames):
			await process_frame
			await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec()
			times.append(float(now-previous)/1000.0)
			previous=now
			process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
			draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var row:={"pose":pose.id,"frames":frames,"frame_median_ms":_percentile(times,0.5),"frame_p95_ms":_percentile(times,0.95),"process_median_ms":_percentile(process_ms,0.5),"physics_median_ms":_percentile(physics_ms,0.5),"draw_calls":_percentile(draw_calls,0.5),"primitives":_percentile(primitives,0.5)}
		report.measurements.append(row)
		print("RENDER_BENCHMARK ",JSON.stringify(row))
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	arena.queue_free()
	await process_frame
	quit(0)
