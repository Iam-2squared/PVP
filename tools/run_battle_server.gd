extends SceneTree
func _initialize() -> void:
	Engine.max_fps=60
	_start.call_deferred()

func _start() -> void:
	var server=load("res://scripts/battle/arena_server.gd").new()
	var env_port:=OS.get_environment("PORT")
	if env_port.is_valid_int(): server.port=int(env_port)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): server.port=int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-dir="): server.save_directory=arg.trim_prefix("--save-dir=")
		elif arg.begins_with("--bind="): server.bind_address=arg.trim_prefix("--bind=")
	if server.port<1 or server.port>65535: push_error("Invalid server port"); quit(1); return
	root.add_child(server)
	if server.listen_error!=OK: quit(1)
