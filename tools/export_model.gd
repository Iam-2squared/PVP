extends SceneTree
## Export runtime-generated world geometry to a portable GLB model.
## godot --path . --script res://tools/export_model.gd -- \
##   --output=res://build/selesia.glb
## --probe validates the conversion with three shared-mesh colored boxes.
## A real renderer is required: Godot's dummy/headless renderer does not retain
## readable MultiMesh instance transforms/colors. Linux CI can use an X11 dummy
## display with Mesa software OpenGL (DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1).

var output := "res://build/selesia.glb"
var probe := false
var _materials: Dictionary = {}
var _parts := 0
var _normal_meshes := 0
var _model: Node3D


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument == "--probe":
			probe = true
	_export.call_deferred()


func _export() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Use an actual rendering display for MultiMesh export; --headless loses instance transforms and colors")
		return
	var world: Node3D
	if probe:
		world = _probe_world()
		root.add_child(world)
	else:
		var scene_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
		if scene_path.is_empty():
			scene_path = "res://scenes/main.tscn"
		var packed: PackedScene = load(scene_path)
		if packed == null:
			_fail("Cannot load scene: " + scene_path)
			return
		var scene := packed.instantiate()
		root.add_child(scene)
		current_scene = scene
		await process_frame
		await process_frame
		var candidate: Variant = scene.get("world")
		if not candidate is Node3D:
			_fail("The scene must expose its generated Node3D as world")
			return
		world = candidate
	_model = Node3D.new()
	_model.name = "SelesiaKingdom"
	root.add_child(_model)
	_collect(world)
	if _parts == 0:
		_fail("No world meshes were found")
		return
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var error := document.append_from_scene(_model, state)
	if error != OK:
		_fail("GLTF scene conversion failed: " + str(error))
		return
	var absolute := ProjectSettings.globalize_path(output)
	error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		_fail("Cannot create export directory: " + str(error))
		return
	error = document.write_to_filesystem(state, absolute)
	if error != OK:
		_fail("GLB export failed: " + str(error))
		return
	print("MODEL_EXPORT ", JSON.stringify({
		"path": absolute,
		"parts": _parts,
		"ordinary_meshes": _normal_meshes,
		"cached_instance_materials": _materials.size(),
		"bytes": FileAccess.get_file_as_bytes(absolute).size(),
		"probe": probe,
	}))
	quit()


func _collect(node: Node) -> void:
	if node is MultiMeshInstance3D:
		var source := node as MultiMeshInstance3D
		var multi := source.multimesh
		if multi != null and multi.mesh != null:
			for index in range(multi.instance_count):
				var instance := MeshInstance3D.new()
				instance.mesh = multi.mesh
				instance.transform = source.global_transform * multi.get_instance_transform(index)
				var color := multi.get_instance_color(index) if multi.use_colors else Color.WHITE
				instance.material_override = _instance_material(source, color)
				_add_part(instance)
	elif node is MeshInstance3D:
		var source := node as MeshInstance3D
		if source.mesh != null:
			var instance := MeshInstance3D.new()
			instance.mesh = source.mesh
			instance.transform = source.global_transform
			instance.material_override = source.material_override
			if source.has_meta("glb_albedo"):
				var fallback:=StandardMaterial3D.new()
				fallback.albedo_color=source.get_meta("glb_albedo")
				fallback.roughness=1.0
				instance.material_override=fallback
			for surface_index in range(source.mesh.get_surface_count()):
				var material := source.get_surface_override_material(surface_index)
				if material != null:
					instance.set_surface_override_material(surface_index, material)
			instance.name = source.name
			_add_part(instance)
			_normal_meshes += 1
	# Only MeshInstance3D nodes are copied. Physics, cameras, HUD and gameplay
	# scripts are deliberately excluded, while nested visual geometry is retained.
	for child in node.get_children():
		_collect(child)


func _instance_material(source: MultiMeshInstance3D, color: Color) -> StandardMaterial3D:
	var source_material := source.material_override as StandardMaterial3D
	var source_key := str(source_material.get_instance_id()) if source_material != null else "default"
	var key := source_key + ":" + color.to_html(true)
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D
	if source_material != null:
		material = source_material.duplicate() as StandardMaterial3D
		material.albedo_color = source_material.albedo_color * color
	else:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
	material.vertex_color_use_as_albedo = false
	material.resource_name = "Color_" + color.to_html(false)
	_materials[key] = material
	return material


func _add_part(instance: MeshInstance3D) -> void:
	_parts += 1
	if instance.name.is_empty():
		instance.name = "Part_%05d" % _parts
	_model.add_child(instance)
	instance.owner = _model


func _probe_world() -> Node3D:
	var world := Node3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = BoxMesh.new()
	multi.instance_count = 3
	for index in range(3):
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(index * 2, 0, 0)))
		multi.set_instance_color(index, Color.RED if index < 2 else Color.BLUE)
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = multi
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	visual.material_override = material
	world.add_child(visual)
	return world


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
