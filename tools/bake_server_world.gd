extends SceneTree
## Preserve every saved collider and shared metadata while excluding resources
## used only for drawing. Never regenerate or modify the accepted client city.
const SOURCE := "res://generated/kingdom.scn"
const OUTPUT := "res://generated/server_kingdom.scn"
const REPORT := "res://docs/performance-server.json"
const Rules = preload("res://scripts/battle/arena_rules.gd")
const WORLD_DATA := ["landmarks", "city_vertices", "city_half_extent", "stats",
	"spawn_position", "palace_data", "town_data", "preview_locations", "house_count"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var verify_only := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--verify-only": verify_only = true
		elif argument.begins_with("--profile-scene="):
			await _profile(argument.trim_prefix("--profile-scene="))
			return
	var client: Node3D = load(SOURCE).instantiate()
	var source_files := _source_hashes()
	var before := _summary(client)
	if not verify_only:
		var dedicated: Node3D = client.duplicate()
		_strip_visuals(dedicated)
		_flatten(dedicated, dedicated)
		var packed := PackedScene.new()
		var error := packed.pack(dedicated)
		if error == OK: error = ResourceSaver.save(packed, OUTPUT, ResourceSaver.FLAG_COMPRESS)
		dedicated.free()
		if error != OK:
			_fail("Could not save the dedicated server city: " + error_string(error))
			client.free()
			return
	var saved: PackedScene = ResourceLoader.load(OUTPUT, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null:
		_fail("Dedicated city is missing. Run tools/bake_server_world.gd first.")
		client.free()
		return
	var server := saved.instantiate() as Node3D
	var after := _summary(server)
	var failures: Array[String] = []
	if before.collision_sha256 != after.collision_sha256:
		failures.append("Saved collider properties, transforms or shape data differ")
	if before.shared_data_sha256 != after.shared_data_sha256:
		failures.append("Shared node metadata or world data differ")
	if after.visuals != 0: failures.append("Dedicated city still contains visual nodes")
	if before.shapes != after.shapes or before.static_bodies != after.static_bodies:
		failures.append("Dedicated city has a different number of colliders")
	for dependency in ResourceLoader.get_dependencies(OUTPUT):
		if str(dependency).contains(".scn"):
			failures.append("Dedicated city still loads a visual scene dependency: " + str(dependency))
	# Also compare the exact runtime gate colliders. The optional flag affects
	# only meshes: the client still gets the same visible portcullises.
	Rules.close_gates(client)
	Rules.close_gates(server, false)
	var closed_client := _summary(client)
	var closed_server := _summary(server)
	if closed_client.collision_sha256 != closed_server.collision_sha256:
		failures.append("Runtime gates differ between client and server")
	if closed_server.visuals != 0: failures.append("Server gates allocate visual nodes")
	if source_files != _source_hashes(): failures.append("Accepted client source files changed during baking")
	if not failures.is_empty():
		for message in failures: push_error(message)
		print("SERVER_WORLD_TEST_RESULT ", JSON.stringify({"failures":failures}))
		client.free()
		server.free()
		quit(1)
		return
	if not verify_only:
		var report := {
			"schema_version":1,
			"scope":"Dedicated server only. Client city, all visual objects, materials and collision geometry are preserved.",
			"generation_command":"godot --headless --path . --script res://tools/bake_server_world.gd",
			"verification_command":"godot --headless --path . --script res://tools/bake_server_world.gd -- --verify-only",
			"source_files_sha256":source_files,
			"source":before,
			"dedicated_server":after,
			"runtime_gates":{"client_shapes":closed_client.shapes - before.shapes,
				"server_shapes":closed_server.shapes - after.shapes,
				"collision_sha256":closed_server.collision_sha256,"exact_collision_match":true},
			"output_scene_bytes":FileAccess.get_file_as_bytes(OUTPUT).size(),
			"client_web_export_excludes":"generated/server_kingdom.scn",
			"limitations":"Removing server drawing resources saves server memory; it does not measure or promise smartphone rendering speed. Collision topology and 60 Hz physics are unchanged."
		}
		var file := FileAccess.open(REPORT, FileAccess.WRITE)
		if file == null:
			_fail("Could not write server verification report")
			client.free()
			server.free()
			return
		file.store_string(JSON.stringify(report, "  ") + "\n")
		file.close()
	print("SERVER_WORLD_TEST_RESULT ", JSON.stringify({"shapes":after.shapes,
		"concave_triangles":after.concave_triangles,"server_visuals":after.visuals,
		"exact_collision_match":true,"exact_shared_data_match":true,
		"runtime_gates_match":true,"failures":[]}))
	client.free()
	server.free()
	quit()

func _strip_visuals(node: Node) -> void:
	for child in node.get_children():
		if child is VisualInstance3D:
			node.remove_child(child)
			child.free()
		else: _strip_visuals(child)

func _flatten(node: Node, world: Node) -> void:
	# Clear external scene-instance links so saving cannot silently reload the
	# original visual parts. All nonvisual nodes keep their names/transforms.
	node.scene_file_path = ""
	if node != world: node.owner = world
	for child in node.get_children(): _flatten(child, world)

func _summary(world: Node3D) -> Dictionary:
	var info := {"nodes":0,"visuals":0,"meshes":0,"render_triangles":0,
		"static_bodies":0,"shapes":0,"concave_triangles":0}
	var collision := HashingContext.new()
	var shared := HashingContext.new()
	collision.start(HashingContext.HASH_SHA256)
	shared.start(HashingContext.HASH_SHA256)
	var data: Dictionary = {}
	for key in WORLD_DATA: data[key] = world.get(key)
	shared.update(var_to_bytes(data))
	_scan(world, Transform3D.IDENTITY, "", info, collision, shared)
	info["collision_sha256"] = collision.finish().hex_encode()
	info["shared_data_sha256"] = shared.finish().hex_encode()
	return info

func _scan(node: Node, inherited: Transform3D, path: String, info: Dictionary,
		collision: HashingContext, shared: HashingContext) -> void:
	info.nodes += 1
	var transform: Transform3D = inherited * node.transform if node is Node3D else inherited
	var here := path + "/" + str(node.name)
	if node is VisualInstance3D:
		info.visuals += 1
		if node is MeshInstance3D and node.mesh != null:
			info.meshes += 1
			for surface in range(node.mesh.get_surface_count()):
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				if arrays[Mesh.ARRAY_INDEX] != null: info.render_triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
				elif arrays[Mesh.ARRAY_VERTEX] != null: info.render_triangles += arrays[Mesh.ARRAY_VERTEX].size() / 3
		return
	var metadata: Dictionary = {}
	for key in node.get_meta_list(): metadata[str(key)] = node.get_meta(key)
	shared.update(var_to_bytes({"path":here,"type":node.get_class(),"metadata":metadata,
		"groups":node.get_groups(),"transform":transform,"process_mode":node.process_mode}))
	if node is StaticBody3D:
		info.static_bodies += 1
		collision.update(var_to_bytes({"path":here,"transform":transform,
			"properties":_stored_properties(node)}))
	if node is CollisionShape3D:
		info.shapes += 1
		collision.update(var_to_bytes({"path":here,"transform":transform,
			"properties":_stored_properties(node)}))
		if node.shape is ConcavePolygonShape3D: info.concave_triangles += node.shape.get_faces().size() / 3
	for child in node.get_children(): _scan(child, transform, here, info, collision, shared)

func _stored_properties(object: Object) -> Dictionary:
	var result: Dictionary = {}
	for property in object.get_property_list():
		var key := str(property.name)
		if not int(property.usage) & PROPERTY_USAGE_STORAGE: continue
		if key in ["owner", "scene_file_path", "resource_path", "resource_scene_unique_id"]: continue
		var value: Variant = object.get(key)
		if value is Script: result[key] = {"script":value.resource_path}
		elif value is Resource: result[key] = {"resource_class":value.get_class(),"properties":_stored_properties(value)}
		else: result[key] = value
	return result

func _source_hashes() -> Dictionary:
	var result := {SOURCE:FileAccess.get_sha256(SOURCE)}
	var metrics: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/world_metrics.json"))
	for path in metrics.part_files: result[path] = FileAccess.get_sha256(path)
	return result

func _profile(which: String) -> void:
	if which not in ["source", "server"]:
		_fail("--profile-scene must be source or server")
		return
	var baseline := OS.get_static_memory_usage()
	var started := Time.get_ticks_usec()
	var world: Node3D = load(SOURCE if which == "source" else OUTPUT).instantiate()
	var load_ms := (Time.get_ticks_usec() - started) / 1000.0
	world.set_process(false)
	root.add_child(world)
	for frame in range(30): await physics_frame
	var memory := OS.get_static_memory_usage()
	print("SERVER_WORLD_MEMORY ", JSON.stringify({"scene":which,
		"godot_version":Engine.get_version_info().string,"display_server":DisplayServer.get_name(),
		"managed_memory_baseline_bytes":baseline,"managed_memory_loaded_bytes":memory,
		"managed_memory_delta_bytes":memory - baseline,"load_and_instantiate_ms":load_ms,
		"node_count":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resource_count":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"scope":"Single Linux headless process, filesystem may be warm; no smartphone or GPU performance claim."}))
	world.free()
	quit()

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
