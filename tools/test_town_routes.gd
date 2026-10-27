extends SceneTree
## Check the delivered town's public walking routes, never a synthetic mock map.
var failures: Array[String]=[]
var checks:=0
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func _walk_to(target: Vector3) -> bool:
	var limit:=ceili(Vector2(target.x-_player.position.x,target.z-_player.position.z).length()/4.8*90)+120
	var previous:=_player.position
	var stuck:=0
	for i in range(limit):
		var delta:=target-_player.position
		delta.y=0
		if delta.length()<0.42:
			Input.action_release("move_forward")
			for j in range(10): await physics_frame
			return absf(_player.position.y-target.y)<0.8
		_player.rotation.y=atan2(-delta.x,-delta.z)
		Input.action_press("move_forward")
		await physics_frame
		if _player.position.distance_squared_to(previous)<0.000001: stuck+=1
		else: stuck=0
		previous=_player.position
		if stuck>90: break
	Input.action_release("move_forward")
	return false

func _run() -> void:
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	for i in range(20): await physics_frame
	var world=scene.world
	_player=scene.player
	_space=world.get_world_3d().direct_space_state
	var town: Dictionary=world.town_data
	_check(not town.is_empty(),"No castle town in the baked scene")
	_check(world.house_count>=450,"Dense residential blocks are missing")
	var routes: Array=town.get("route_waypoints",[])
	_check(not routes.is_empty(),"Missing connected town walking routes")
	for route in routes:
		var points: Array=Array(route.get("points",[]))
		if points.size()<2: continue
		_player.position=points[0]
		_player.velocity=Vector3.ZERO
		for i in range(12): await physics_frame
		var okay:=true
		for i in range(1,points.size()):
			if not await _walk_to(points[i]):
				_check(false,"Blocked street %s segment %d: target %s actual %s"%[route["id"],i,points[i],_player.position])
				okay=false
				break
		if okay: _check(true,"Walked street "+str(route["id"]))
		print("TOWN_ROUTE ",route["id"]," ","PASS" if okay else "FAIL")
	var capsule:=CapsuleShape3D.new()
	capsule.height=1.8
	capsule.radius=0.34
	var buildings: Array=Array(town.get("enterable_buildings",town.get("houses",[])))
	for building in buildings:
		if not building.get("enterable",false): continue
		var p: Vector3=building["entrance"]
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*0.92)
		query.exclude=[_player.get_rid()]
		_check(_space.intersect_shape(query,1).is_empty(),"Public entrance is obstructed: "+str(building.get("id","building")))
	print("TOWN_TEST_RESULT ",JSON.stringify({"checks":checks,"houses":world.house_count,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
