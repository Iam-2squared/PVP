extends SceneTree
## Check the actual baked map, gates, terrain collision and exploration controls.

var failures: Array[String] = []
var checks := 0
var _exclude: Array[RID] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ray(space: PhysicsDirectSpaceState3D,a: Vector3,b: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(a,b)
	query.exclude = _exclude
	return space.intersect_ray(query)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in range(40):
		await physics_frame
	var world = scene.world
	var player = scene.player
	_exclude = [player.get_rid()]
	_check(world.get_meta("environment_preview",false),"Must open the terrain/wall preview")
	_check(world.house_count==0,"This phase must not include houses")
	var vertices: PackedVector2Array=world.city_vertices
	_check(vertices.size()==8,"City wall must have eight corners")
	var edge_length: float=vertices[0].distance_to(vertices[1])
	for i in range(8):
		_check(absf(vertices[i].distance_to(vertices[(i+1)%8])-edge_length)<=0.1,"Rasterized octagon edge length differs by more than a voxel tolerance")
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	for p in [Vector3(0,6,0),Vector3(0,6,152),Vector3(145,6,0),Vector3(-145,6,0),Vector3(0,6,-145)]:
		var hit := _ray(space,p,p-Vector3(0,10,0))
		_check(not hit.is_empty(),"Ground missing at %s"%p)
		if not hit.is_empty() and (maxf(absf(p.x),absf(p.z))<=136.0 or p.z==152.0):
			_check(absf(hit.position.y-2.0)<0.1,"Gate/plateau ground must remain level at %s: %s"%[p,hit.position.y])
	_check(_ray(space,Vector3(240,5,240),Vector3(240,-1.5,240)).is_empty(),"Sea must have no collision floor at the surface")
	for pair in [[Vector3(0,4,116),Vector3(0,4,142)],[Vector3(116,4,0),Vector3(142,4,0)],[Vector3(-116,4,0),Vector3(-142,4,0)],[Vector3(0,4,-116),Vector3(0,4,-142)]]:
		_check(_ray(space,pair[0],pair[1]).is_empty(),"Gate passage is blocked")
	_check(not _ray(space,Vector3(35,6,120),Vector3(35,6,136)).is_empty(),"Wall collision missing")
	var walk_hit := _ray(space,Vector3(35,20,128),Vector3(35,10,128))
	_check(not walk_hit.is_empty(),"Wall walk has no solid floor")
	_check(player.is_on_floor(),"Player should settle on the ground")
	var start: Vector3=player.position
	Input.action_press("move_forward")
	for i in range(80):
		await physics_frame
	Input.action_release("move_forward")
	_check(start.distance_to(player.position)>3,"First person movement blocked at spawn")
	player.set_overview(true)
	_check(player.aerial_camera.current,"Overview camera did not activate")
	player.set_overview(false)
	_check(player.camera.current,"First person camera did not reactivate")
	player.position=Vector3(235,-2.1,235)
	for i in range(3):
		await physics_frame
	_check(player.position.distance_to(world.get_spawn_position())<2,"Falling into the sea should restore the preview spawn")
	player.position=Vector3(-123.75,2.1,16)
	player.rotation.y=PI
	player.velocity=Vector3.ZERO
	for i in range(12):
		await physics_frame
	Input.action_press("move_forward")
	for i in range(450):
		await physics_frame
		if player.position.y>15.7 and player.position.z>=46.0:
			break
	Input.action_release("move_forward")
	for i in range(12):
		await physics_frame
	_check(player.position.y>15.7 and player.position.z>45,"Stairs must be walkable without jumping: %s"%player.position)
	Input.action_press("move_right")
	for i in range(75):
		await physics_frame
	Input.action_release("move_right")
	_check(player.position.y>15.5 and player.position.x < -126.5,"Stair landing must connect to the wall walk: %s"%player.position)
	var terrain_stats: Dictionary=world.stats["terrain"]
	var wall_stats: Dictionary=world.stats["walls"]
	_check(wall_stats["voxels"]>400000,"Detailed wall voxel construction missing")
	_check(wall_stats["triangles"]<200000,"Wall geometry budget exceeded")
	_check(terrain_stats["land_triangles"]<150000,"Terrain geometry budget exceeded")
	print("VOXEL_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"terrain":terrain_stats,"walls":wall_stats}))
	quit(0 if failures.is_empty() else 1)
