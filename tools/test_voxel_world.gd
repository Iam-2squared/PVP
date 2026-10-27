extends SceneTree
## Exercise the baked main scene and preview controls. Wall routes and shooting
## openings have their own physics checks in test_fortress.gd; palace/town routes
## belong to their dedicated spatial checks, rather than fixed coordinates here.

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func _check_level_ground(world: Node3D, player: CharacterBody3D) -> void:
	var terrain: Dictionary = world.stats.get("terrain", {})
	_check(float(terrain.get("min_height", INF)) == 2.0 and float(terrain.get("max_height", INF)) == 2.0 and int(terrain.get("water_triangles", -1)) == 0, "Terrain must be level at Y=2 with no remaining water")
	# Isolate the continuous base collider. Future town floors/foundations can
	# cover these XZ points, so their top surfaces must not satisfy this test.
	var ground: StaticBody3D = null
	var extent: float = float(world.get_meta("world_extent", 320.0))
	for body in world.find_children("*", "StaticBody3D", true, false):
		for shape_node in body.get_children():
			if shape_node is CollisionShape3D and shape_node.shape is BoxShape3D:
				var size: Vector3 = shape_node.shape.size
				if size.x >= extent * 2.0 and size.z >= extent * 2.0:
					ground = body
	_check(ground != null, "Continuous base-ground collision was not loaded with the main scene")
	if ground == null:
		return
	var excluded: Array[RID] = [player.get_rid()]
	for body in world.find_children("*", "CollisionObject3D", true, false):
		if body != ground:
			excluded.append(body.get_rid())
	var space := world.get_world_3d().direct_space_state
	for p in [Vector3(70,2,70), Vector3(-130,2,40), Vector3(0,2,100), Vector3(250,2,0), Vector3(-230,2,-150), Vector3(0,2,260)]:
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p - Vector3.UP * 3.0)
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		_check(not hit.is_empty() and hit.get("collider") == ground and absf(hit.position.y - 2.0) <= 0.02, "Base ground is missing or uneven at %s: %s" % [p, hit.get("position", "no collision")])

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "Main scene could not be loaded")
	if packed == null:
		_finish({})
		return
	var scene = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(40)
	var world = scene.world
	var player = scene.player
	_check(is_instance_valid(world) and is_instance_valid(player), "Main scene did not create the world and player")
	if not is_instance_valid(world) or not is_instance_valid(player):
		_finish({})
		return
	_check(world.get_meta("environment_preview", false), "Main scene must open the environment preview")
	_check(player.camera.current, "Preview must start in first person")
	var spawn: Vector3 = world.get_spawn_position()
	_check(player.is_on_floor() and player.position.distance_to(spawn) < 1.0, "Player did not land safely at the authored spawn: %s" % player.position)
	_check_level_ground(world, player)

	# A real input-to-collision movement check also catches missing externally
	# packed terrain components, without asserting how many meshes were baked.
	var start: Vector3 = player.position
	Input.action_press("move_forward")
	await _frames(80)
	Input.action_release("move_forward")
	await _frames(18)
	_check(start.distance_to(player.position) > 3.0 and player.is_on_floor(), "Cannot walk on the terrain from the preview spawn: %s" % player.position)

	player.set_overview(true)
	_check(player.aerial_camera.current and player.get_overview(), "Overview camera did not activate")
	var overview_start: Vector3 = player.position
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_release("move_forward")
	_check(player.position.distance_to(overview_start) < 0.01, "Overview must pause character movement")
	# Test the visible footprint, so increasing the map does not silently crop it.
	var wall_height: float = float(world.stats.get("design", {}).get("wall_walk_height", 0.0))
	var footprint_visible: bool = not world.city_vertices.is_empty()
	for vertex in world.city_vertices:
		if not player.aerial_camera.is_position_in_frustum(Vector3(vertex.x, wall_height, vertex.y)):
			footprint_visible = false
	_check(footprint_visible, "Overview crops part of the city wall")
	player.set_overview(false)
	_check(player.camera.current and not player.get_overview(), "First person camera did not reactivate")

	var locations: Array[Dictionary] = player.get_preview_locations()
	_check(not locations.is_empty(), "Baked preview has no tour destinations")
	for i in range(locations.size()):
		var destination: Dictionary = locations[i]
		var title: String = str(destination.get("title", destination.get("id", i)))
		player.set_overview(true)
		player.velocity = Vector3(3, -2, 4)
		var visited: bool = player.visit_preview_location(i)
		_check(visited and player.camera.current and not player.get_overview(), "Tour failed to return to first person: " + title)
		var position: Vector3 = destination["position"]
		var pose_correct: bool = player.global_position.is_equal_approx(position)
		pose_correct = pose_correct and absf(angle_difference(player.rotation.y, deg_to_rad(float(destination.get("yaw_degrees", 0.0))))) < 0.001
		pose_correct = pose_correct and absf(player.camera.rotation.x - deg_to_rad(float(destination.get("pitch_degrees", 0.0)))) < 0.001
		_check(pose_correct and player.velocity.is_zero_approx(), "Tour did not apply the exact feet/camera pose or clear movement: " + title)
		_check(str(player.hud._area_label.text).ends_with(title), "Current-place label does not identify this tour destination/floor: " + title)
		await _frames(30)
		var horizontal_drift := Vector2(player.position.x - position.x, player.position.z - position.z).length()
		_check(player.is_on_floor() and absf(player.position.y - position.y) < 0.75 and horizontal_drift < 0.25, "Tour destination has no safe standing surface: %s at %s" % [title, player.position])

	if not locations.is_empty():
		# Exercise the actual shortcut dispatch as well as the direct tour API.
		var event := InputEventKey.new()
		event.keycode = KEY_N
		event.physical_keycode = KEY_N
		event.pressed = true
		root.push_input(event, true)
		await process_frame
		event = InputEventKey.new()
		event.keycode = KEY_N
		event.physical_keycode = KEY_N
		event.pressed = false
		root.push_input(event, true)
		_check(player.get_preview_location_index() == 0, "N did not cycle the last tour destination back to the first")

	# Falling below the world must restore the authored spawn. The exterior is
	# now flat cleared ground, so put the character below its collision surface.
	player.position = Vector3(world.city_half_extent * 1.5, -4.0, world.city_half_extent * 1.5)
	player.velocity = Vector3.ZERO
	await _frames(35)
	_check(player.position.distance_to(spawn) < 1.0 and player.is_on_floor(), "Falling below the world did not return the player safely to spawn")
	_finish({"destinations": locations.size(), "city_half_extent": world.city_half_extent, "terrain": world.stats.get("terrain", {}), "walls": world.stats.get("walls", {}), "palace_rooms": world.palace_data.get("rooms", []).size(), "town_houses": world.house_count})

func _finish(details: Dictionary) -> void:
	Input.action_release("move_forward")
	details["checks"] = checks
	details["failures"] = failures
	print("VOXEL_TEST_RESULT ", JSON.stringify(details))
	quit(0 if failures.is_empty() else 1)
