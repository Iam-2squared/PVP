extends SceneTree
## Generate the static, compressed voxel map once; runtime only loads this file.

func _initialize() -> void:
	_bake.call_deferred()

func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)

func _bake() -> void:
	var started := Time.get_ticks_msec()
	var stage := "town"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--stage="):
			stage = argument.trim_prefix("--stage=")
	if stage not in ["walls","palace","town"]:
		push_error("Unknown build stage: "+stage)
		quit(1)
		return
	var factory = load("res://scripts/voxel/factory.gd").new()
	var world: Node3D = factory.build(stage)
	root.add_child(world)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://generated/parts"))
	for old_file in DirAccess.get_files_at("res://generated/parts"):
		if old_file.begins_with("component_") and old_file.ends_with(".scn"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://generated/parts/"+old_file))
	var part_paths: Array[String]=[]
	var total_bytes:=0
	# Independent scenes keep each asset small and avoid re-embedding every mesh
	# in the world file when only a room or a building changes.
	for child in world.get_children():
		_own(child,child)
		var component:=PackedScene.new()
		var component_error:=component.pack(child)
		if component_error!=OK:
			push_error("Could not pack component: "+str(child.name)); quit(1); return
		var path: String="res://generated/parts/component_"+str(child.name).to_snake_case()+".scn"
		component_error=ResourceSaver.save(component,path,ResourceSaver.FLAG_COMPRESS|ResourceSaver.FLAG_CHANGE_PATH)
		if component_error!=OK:
			push_error("Could not save component: "+path); quit(1); return
		part_paths.append(path)
		total_bytes+=FileAccess.get_file_as_bytes(path).size()
		# Reopen the saved scene so Godot records an external instance path.
		# In-memory PackedScenes otherwise re-pack as empty owner-only nodes.
		var saved: PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_REPLACE)
		var instance:=saved.instantiate()
		instance.name=child.name
		world.remove_child(child)
		child.free()
		world.add_child(instance)
		instance.owner=world
	var packed := PackedScene.new()
	var error := packed.pack(world)
	if error != OK:
		push_error("Could not pack generated map: %s" % error)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://generated"))
	error = ResourceSaver.save(packed,"res://generated/kingdom.scn",ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Could not save generated map: %s" % error)
		quit(1)
		return
	var root_bytes:=FileAccess.get_file_as_bytes("res://generated/kingdom.scn").size()
	var metrics := {"build_seconds":(Time.get_ticks_msec()-started)/1000.0,"bytes":root_bytes,"total_scene_bytes":root_bytes+total_bytes,"part_files":part_paths,"world":world.stats}
	var file := FileAccess.open("res://generated/world_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"  ")+"\n")
	print("BAKE_RESULT ",JSON.stringify({"stage":stage,"build_seconds":metrics["build_seconds"],"total_scene_bytes":metrics["total_scene_bytes"],"components":part_paths.size(),"palace_rooms":world.palace_data.get("room_count",0),"town_houses":world.house_count}))
	quit()
