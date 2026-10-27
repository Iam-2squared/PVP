extends SceneTree
## Integration checks against the baked physics scene, including walkable stairs.

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

func _ray(a: Vector3,b: Vector3) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(a,b)
	query.exclude=[_player.get_rid()]
	return _space.intersect_ray(query)

func _walk_to(target: Vector3) -> bool:
	var limit:=ceili(Vector2(target.x-_player.position.x,target.z-_player.position.z).length()/4.8*90)+180
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

func _walk_route(route: Dictionary, reverse: bool = false) -> bool:
	var points: Array=Array(route.get("points",[])).duplicate()
	if points.size()<2: return false
	if reverse: points.reverse()
	var direction: String="return" if reverse else "outbound"
	_player.position=points[0]
	_player.velocity=Vector3.ZERO
	for i in range(12): await physics_frame
	var okay:=true
	for i in range(1,points.size()):
		if not await _walk_to(points[i]):
			_check(false,"Blocked route %s (%s) at segment %d: target %s actual %s"%[route["id"],direction,i,points[i],_player.position])
			okay=false
			break
	if okay: _check(true,"Walked route %s (%s)"%[route["id"],direction])
	print("PALACE_ROUTE ",route["id"]," ",direction," ","PASS" if okay else "FAIL")
	return okay

func _run() -> void:
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	for i in range(20): await physics_frame
	_player=scene.player
	var world=scene.world
	_space=world.get_world_3d().direct_space_state
	var palace: Dictionary=world.palace_data
	_check(not palace.is_empty(),"Royal palace is missing from the baked world")
	var rooms: Array=palace.get("rooms",[])
	_check(rooms.size()>=12,"Palace needs distinct furnished rooms")
	var capsule:=CapsuleShape3D.new()
	capsule.height=1.8
	capsule.radius=0.34
	for room in rooms:
		var p: Vector3=room["position"]
		var title: String=room.get("title",str(room.get("id","room")))
		var floor_hit:=_ray(p+Vector3.UP*0.25,p-Vector3.UP*1.0)
		_check(not floor_hit.is_empty(),"Missing room floor: "+title+" at "+str(p))
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*0.92)
		query.exclude=[_player.get_rid()]
		_check(_space.intersect_shape(query,1).is_empty(),"Room arrival intersects furniture/wall: "+title+" at "+str(p))
	for view in palace.get("viewpoints",[]):
		var p: Vector3=view["position"]
		_check(not _ray(p+Vector3.UP*0.25,p-Vector3.UP*1.0).is_empty(),"Viewpoint has no floor: "+str(view["id"]))
	for door in palace.get("doors",[]):
		var p: Vector3=door["position"]
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*0.92)
		query.exclude=[_player.get_rid()]
		_check(_space.intersect_shape(query,1).is_empty(),"Doorway is obstructed: "+str(door["id"])+" at "+str(p))
	var routes: Array=palace.get("route_waypoints",[])
	_check(not routes.is_empty(),"Missing palace walking routes")
	var return_walks:=0
	for route in routes:
		var points: Array=Array(route.get("points",[]))
		if points.size()<2: continue
		await _walk_route(route)
		if str(route.get("id","")).begins_with("terrace_approach_"):
			if await _walk_route(route,true): return_walks+=1
	_check(return_walks>=2,"Both side approaches must be walkable back from the castle to city ground")
	print("PALACE_TEST_RESULT ",JSON.stringify({"checks":checks,"side_return_walks":return_walks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
