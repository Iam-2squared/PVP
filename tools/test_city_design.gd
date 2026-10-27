extends SceneTree
## Check the delivered city composition against its loaded meshes and physics.
## Full stair traversal is covered by test_palace_routes.gd, which walks every
## published route; this suite checks the new arrivals and public-space intent.

const GARDEN_BUFFER := Rect2(-65, -18, 130, 28)
const FOUNTAIN_RESERVED := Rect2(-22, 0, 44, 36)
const REQUIRED_FACILITIES := ["adventurers_guild", "blacksmith"]

var failures: Array[String] = []
var checks := 0
var _world: Node3D
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D
var _capsule: CapsuleShape3D
var _visuals: Array[Node] = []
var _details: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(a, b)
	query.exclude = [_player.get_rid()]
	return _space.intersect_ray(query)


func _clear_at(feet: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.92)
	query.exclude = [_player.get_rid()]
	return _space.intersect_shape(query, 1).is_empty()


func _standing_at(feet: Vector3) -> bool:
	# Published landing poses must stand clear at their authored coordinates.
	# Do not lift a waypoint onto a riser to conceal an embedded arrival pose.
	var floor_hit := _ray(feet + Vector3.UP * 0.5, feet - Vector3.UP * 0.75)
	if floor_hit.is_empty() or floor_hit.normal.y < 0.9 or absf(floor_hit.position.y - feet.y) > 0.3:
		return false
	return _clear_at(feet)


func _house_footprint(house: Dictionary) -> PackedVector2Array:
	var center: Vector3 = house["centre"]
	var half := Vector2(float(house["width"]), float(house["depth"])) * 0.5
	var basis := Basis(Vector3.UP, float(house.get("orientation", 0.0)))
	var polygon := PackedVector2Array()
	for corner in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
		var point: Vector3 = center + basis * corner
		polygon.append(Vector2(point.x, point.z))
	return polygon


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])


func _check_house_reserves(town: Dictionary) -> void:
	var ordinary := 0
	var garden_intrusions: Array[String] = []
	var fountain_intrusions: Array[String] = []
	for house: Dictionary in town.get("houses", []):
		if str(house.get("kind", "house")) not in ["house", "shop"]:
			continue
		ordinary += 1
		var polygon := _house_footprint(house)
		if not Geometry2D.intersect_polygons(polygon, _rect_polygon(GARDEN_BUFFER)).is_empty():
			garden_intrusions.append(str(house.get("id", house["centre"])))
		if not Geometry2D.intersect_polygons(polygon, _rect_polygon(FOUNTAIN_RESERVED)).is_empty():
			fountain_intrusions.append(str(house.get("id", house["centre"])))
	_check(ordinary > 0, "No ordinary-house footprints were loaded for the public-space checks")
	_check(garden_intrusions.is_empty(), "Ordinary houses occupy the palace garden buffer: " + str(garden_intrusions))
	_check(fountain_intrusions.is_empty(), "Ordinary houses occupy the grand fountain reserve: " + str(fountain_intrusions))
	_details["ordinary_houses_checked"] = ordinary


func _check_side_approaches(palace: Dictionary) -> void:
	var checked: Array[String] = []
	for side in [{"id":"terrace_approach_west", "sign":-1.0}, {"id":"terrace_approach_east", "sign":1.0}]:
		var found: Dictionary = {}
		for route: Dictionary in palace.get("route_waypoints", []):
			if str(route.get("id", "")) == side["id"]:
				found = route
		var points: Array = Array(found.get("points", []))
		_check(points.size() >= 3, "Missing side approach to the palace: " + str(side["id"]))
		if points.size() < 3:
			continue
		var lateral_reach := 0.0
		var lowest := INF
		var highest := -INF
		for point: Vector3 in points:
			lateral_reach = maxf(lateral_reach, point.x * float(side["sign"]))
			lowest = minf(lowest, point.y)
			highest = maxf(highest, point.y)
			_check(_standing_at(point), "Side-approach landing has no clear standing surface: %s at %s" % [side["id"], point])
		_check(lateral_reach > 20.0, "Approach remains on the central staircase instead of its side: " + str(side["id"]))
		_check(lowest < 3.0 and highest - lowest > 8.0, "Side approach does not connect city ground to the upper castle court: " + str(side["id"]))
		checked.append(str(side["id"]))
	_details["side_routes"] = checked
	_check_upper_stair_profiles(palace)


func _check_upper_stair_profiles(palace: Dictionary) -> void:
	var profiles: Dictionary = {}
	for id in ["terrace_west_stair", "terrace_east_stair"]:
		var flight: Dictionary = {}
		for stair: Dictionary in palace.get("stairs", []):
			if str(stair.get("id", "")) == id:
				flight = stair.get("upper_flight", {})
		_check(flight.has("bottom") and flight.has("top"), "Side staircase has no upper-flight endpoints: " + id)
		if not flight.has("bottom") or not flight.has("top"):
			continue
		var bottom: Vector3 = flight["bottom"]
		var top: Vector3 = flight["top"]
		_check(absf(top.x) < absf(bottom.x) - 8.0 and top.y > bottom.y + 2.0, "Upper staircase does not ascend substantially toward the castle center: " + id)
		var profile: Array = []
		var previous_x := INF
		var previous_y := -INF
		var monotonic := true
		# Mid-interval probes avoid the riser edges and inspect real tread tops.
		# Their heights come from the saved collision mesh, never metadata lerps.
		for sample in range(16):
			var point := bottom.lerp(top, (float(sample) + 0.5) / 16.0)
			var hit := _ray(Vector3(point.x, top.y + 2.0, point.z), Vector3(point.x, bottom.y - 1.0, point.z))
			var floor_ok: bool = not hit.is_empty() and hit.normal.y > 0.9
			_check(floor_ok, "Upper staircase has no horizontal tread at %s on %s" % [point, id])
			if not floor_ok:
				monotonic = false
				continue
			var measured: Vector3 = hit.position
			var inward_x := absf(measured.x)
			monotonic = monotonic and inward_x < previous_x and measured.y >= previous_y - 0.05
			previous_x = inward_x
			previous_y = measured.y
			profile.append([inward_x, measured.y])
		_check(monotonic and profile.size() == 16, "Actual upper treads do not rise while |X| decreases: " + id)
		if profile.size() == 16:
			_check(float(profile[-1][1]) - float(profile[0][1]) > 2.5, "Actual upper flight has no meaningful inward elevation gain: " + id)
			_check(float(profile[0][1]) <= bottom.y + 0.75 and float(profile[-1][1]) >= top.y - 0.4, "Actual upper treads do not join the lower and upper landings: " + id)
		profiles[id] = profile
	_details["upper_stair_profiles_abs_x_y"] = profiles


func _check_fountain(town: Dictionary) -> void:
	var fountain: Dictionary = town.get("fountain", {})
	var probes: Array = Array(fountain.get("rim_probes", []))
	_check(not fountain.is_empty() and probes.size() >= 4, "Grand fountain and its actual stone-rim probes were not baked")
	var measured: Array[Vector3] = []
	for probe: Vector3 in probes:
		var hit := _ray(probe + Vector3.UP * 2.0, probe - Vector3.UP * 0.25)
		var okay: bool = not hit.is_empty() and hit.position.y > float(town.get("ground_top", 2.0)) + 0.25
		_check(okay, "Grand fountain rim has no raised solid geometry at " + str(probe))
		if okay:
			measured.append(hit.position)
	var span := Vector2.ZERO
	if not measured.is_empty():
		var minimum := Vector2(measured[0].x, measured[0].z)
		var maximum := minimum
		for point in measured:
			minimum = minimum.min(Vector2(point.x, point.z))
			maximum = maximum.max(Vector2(point.x, point.z))
		span = maximum - minimum
	_check(span.x >= 20.0 and span.y >= 20.0, "Actual grand fountain stone footprint is too small: " + str(span))
	_details["fountain_measured_span_m"] = [span.x, span.y]
	var perimeter: Array = Array(fountain.get("perimeter_route", []))
	_check(perimeter.size() >= 4, "Grand fountain has no published public perimeter")
	for segment in range(1, perimeter.size()):
		var a: Vector3 = perimeter[segment - 1]
		var b: Vector3 = perimeter[segment]
		var samples := maxi(1, ceili(a.distance_to(b) / 1.5))
		var clear := true
		var blocked := Vector3.ZERO
		for sample in range(samples + 1):
			var point := a.lerp(b, float(sample) / samples)
			if not _standing_at(point):
				clear = false
				blocked = point
				break
		_check(clear, "Public fountain perimeter is obstructed at " + str(blocked))


func _green(color: Color) -> bool:
	return color.g > color.r * 1.08 and color.g > color.b * 1.08


func _has_green_geometry(bounds: AABB) -> bool:
	for node in _visuals:
		var visual := node as MeshInstance3D
		if visual.mesh == null or not visual.is_visible_in_tree():
			continue
		var actual_bounds: AABB = visual.global_transform * visual.get_aabb()
		if not actual_bounds.intersects(bounds):
			continue
		for surface in range(visual.mesh.get_surface_count()):
			var material := visual.get_active_material(surface)
			if material is StandardMaterial3D and _green(material.albedo_color):
				return true
			if material is ShaderMaterial and material.shader != null:
				for uniform in material.shader.get_shader_uniform_list():
					if uniform["name"] == "base_color":
						var color: Variant = material.get_shader_parameter("base_color")
						if color is Color and _green(color):
							return true
			var arrays := visual.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_COLOR] == null:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for index in range(mini(vertices.size(), colors.size())):
				if _green(colors[index]) and bounds.has_point(visual.global_transform * vertices[index]):
					return true
	return false


func _check_gardens(town: Dictionary) -> void:
	var unique: Dictionary = {}
	for park: Dictionary in town.get("parks", []):
		var id := str(park.get("id", ""))
		if id.is_empty() or unique.has(id):
			continue
		unique[id] = true
		var bounds: AABB = park.get("bounds", AABB())
		_check(bounds.size.x * bounds.size.z >= 20.0, "Garden has no usable spatial footprint: " + id)
		_check(_has_green_geometry(bounds), "Garden has no visible green planting or green ground mesh: " + id)
	_check(unique.size() >= 5, "The delivered city needs at least five distinct gardens and parks")
	_details["gardens_and_parks"] = unique.size()


func _find_building(town: Dictionary, id: String) -> Dictionary:
	for building: Dictionary in town.get("enterable_buildings", []):
		if str(building.get("id", "")) == id:
			return building
	return {}


func _check_sign_visibility(text: MeshInstance3D, front: Vector3, id: String) -> void:
	var view_id := "guild_sign" if id == "adventurers_guild" else "blacksmith_sign"
	var view: Dictionary = {}
	for candidate: Dictionary in _world.preview_locations:
		if str(candidate.get("id", "")) == view_id:
			view = candidate
	_check(view.has("position"), "Facility sign has no published street-level viewing point: " + id)
	if not view.has("position"):
		return
	var eye: Vector3 = view["position"] + Vector3.UP * _player.camera.position.y
	var bounds := text.mesh.get_aabb()
	for fraction in [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9), Vector2(0.9, 0.9)]:
		var local := bounds.position + Vector3(bounds.size.x * fraction.x, bounds.size.y * fraction.y, bounds.size.z * 0.5)
		var target: Vector3 = text.global_transform * local + front * 0.02
		var hit := _ray(eye, target)
		# Glyphs have no physics; contact with their backing at the paint plane
		# is acceptable, but a portico/roof in front of the name is not.
		var clear: bool = hit.is_empty() or eye.distance_to(hit.position) >= eye.distance_to(target) - 0.1
		_check(clear, "Facility name is hidden from its actual street viewpoint: %s sample %s, blocker %s" % [id, fraction, hit.get("position", "none")])


func _check_facility_signs(town: Dictionary) -> void:
	var signs := _world.find_child("FacilitySigns", true, false)
	_check(signs != null, "World-space facility signs were not loaded with the baked city")
	if signs == null:
		return
	var records: Array = Array(signs.get_meta("facility_signs", []))
	var verified: Array[String] = []
	for id: String in REQUIRED_FACILITIES:
		var building := _find_building(town, id)
		var record: Dictionary = {}
		for candidate: Dictionary in records:
			if str(candidate.get("id", "")) == id:
				record = candidate
		_check(not building.is_empty() and not record.is_empty(), "Principal facility has no entrance/sign pairing: " + id)
		if building.is_empty() or record.is_empty():
			continue
		_check(not str(record.get("title", "")).is_empty() and not str(record.get("icon_kind", "")).is_empty(), "Facility sign has no readable name or recognizable trade symbol: " + id)
		var text := signs.get_node_or_null(NodePath(str(record.get("text_node", "")))) as MeshInstance3D
		_check(text != null and text.mesh is ArrayMesh, "Facility name is missing its baked glyph mesh: " + id)
		if text == null or text.mesh == null:
			continue
		_check(text.mesh.get_faces().size() > 36, "Facility name has no actual glyph outline geometry: " + id)
		var bounds: AABB = text.global_transform * text.get_aabb()
		var center := bounds.get_center()
		var entry: Vector3 = building["entrance"]
		var front: Vector3 = building.get("front_direction", Basis(Vector3.UP, float(building.get("orientation", 0.0))) * Vector3.FORWARD)
		front.y = 0
		front = front.normalized()
		_check(maxf(bounds.size.x, bounds.size.z) > 1.5 and bounds.size.y > 0.4, "Facility name is too small to read as a physical street sign: " + id)
		_check(Vector2(center.x - entry.x, center.z - entry.z).length() < 10.0 and center.y > entry.y + 2.0, "Facility name is detached from its entrance: " + id)
		_check((text.global_basis.z.normalized()).dot(front) > 0.9 and (center - entry).dot(front) > -1.0, "Facility name faces into the building instead of its approach: " + id)
		var backing := _ray(center + front * 1.5, center - front * 1.5)
		_check(not backing.is_empty(), "Facility lettering has no physical signboard behind it: " + id)
		_check(_clear_at(entry), "Facility sign blocks its public entrance: " + id)
		_check_sign_visibility(text, front, id)
		verified.append(id)
	_details["principal_signs"] = verified


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "Main preview scene could not be loaded")
	if packed == null:
		_finish()
		return
	var scene = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in range(20):
		await physics_frame
	_world = scene.world
	_player = scene.player
	_space = _world.get_world_3d().direct_space_state
	_capsule = CapsuleShape3D.new()
	_capsule.height = 1.8
	_capsule.radius = 0.34
	_visuals = _world.find_children("*", "MeshInstance3D", true, false)
	var town: Dictionary = _world.town_data
	_check(not town.is_empty(), "Baked town metadata is missing")
	_check_house_reserves(town)
	_check_side_approaches(_world.palace_data)
	_check_fountain(town)
	_check_gardens(town)
	_check_facility_signs(town)
	_finish()


func _finish() -> void:
	_details["checks"] = checks
	_details["failures"] = failures
	print("CITY_DESIGN_TEST_RESULT ", JSON.stringify(_details))
	quit(0 if failures.is_empty() else 1)
