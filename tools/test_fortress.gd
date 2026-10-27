extends SceneTree

var failures: Array[String] = []
var checks := 0
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(a,b)
	query.exclude = [_player.get_rid()]
	return _space.intersect_ray(query)

func _walk_to(target: Vector3, max_frames: int = 1000) -> bool:
	for i in range(max_frames):
		var delta := target-_player.position
		delta.y=0
		if delta.length()<0.45:
			Input.action_release("move_forward")
			for j in range(12): await physics_frame
			return true
		_player.rotation.y=atan2(-delta.x,-delta.z)
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	return false

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	for i in range(40): await physics_frame
	var world = scene.world
	_player=scene.player
	_space=world.get_world_3d().direct_space_state
	var design: Dictionary=world.stats["design"]
	var a: float=world.city_half_extent
	_check(a>=160,"City footprint was not enlarged")
	_check(design["wall_walk_height"]>=24,"Wall walk was not raised")
	_check(world.city_vertices.size()==8,"Expected eight main corners")
	for gate in design["gates"]:
		var p: Vector3=gate["position"]
		var normal:=Vector3(p.x,0,p.z).normalized()
		_check(_ray(p-normal*12+Vector3.UP*2,p+normal*16+Vector3.UP*2).is_empty(),"Gate obstructed: "+gate["title"])
	var shots: Array=design.get("shooting_positions",[])
	_check(shots.size()>=8,"Missing usable shooting positions")
	for shot in shots:
		var p: Vector3=shot["position"]
		var eye: float=float(shot.get("eye_height",1.65))
		var aim: Vector3=shot["aim_point"]
		_check(_ray(p+Vector3.UP*eye,aim).is_empty(),"Shooting opening obstructs view at %s"%p)
	var stairs: Array=design.get("staircases",design.get("stairways",[]))
	_check(stairs.size()>=4,"Need four ways up to the wall")
	for stair in stairs:
		var bottom: Vector3=stair["bottom"]
		var top: Vector3=stair["top"]
		var back:=bottom-top
		back.y=0
		back=back.normalized()
		_player.position=bottom+back*1.5+Vector3.UP*0.1
		_player.velocity=Vector3.ZERO
		for i in range(12): await physics_frame
		var reached: bool=await _walk_to(top,1200)
		_check(reached and _player.position.y>=design["wall_walk_height"]-0.3,"Cannot walk up staircase: %s -> %s (at %s)"%[bottom,top,_player.position])
	_player.position=world.get_spawn_position()
	_player.velocity=Vector3.ZERO
	print("FORTRESS_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
