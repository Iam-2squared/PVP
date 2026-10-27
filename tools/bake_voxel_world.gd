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
	var factory = load("res://scripts/voxel/factory.gd").new()
	var world: Node3D = factory.build()
	root.add_child(world)
	_own(world, world)
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
	var metrics := {"build_seconds":(Time.get_ticks_msec()-started)/1000.0,"bytes":FileAccess.get_file_as_bytes("res://generated/kingdom.scn").size(),"world":world.stats}
	var file := FileAccess.open("res://generated/world_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"  ")+"\n")
	print("BAKE_RESULT ",JSON.stringify(metrics))
	quit()
