extends SceneTree
## Actual viewport input: the movement finger and right-half camera finger
## retain separate owners through interleaved touches and lifecycle changes.
const Player=preload("res://scripts/battle/arena_local_player.gd")
var player:CharacterBody3D
var checks:=0
var failures:Array[String]=[]
var skipped:Array[String]=[]
var taps:Dictionary={"attack":0,"jump":0,"skill":0,"home":0}

func _initialize()->void:
	_run.call_deferred()

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func _touch(id:int,pos:Vector2,pressed:bool,canceled:bool=false)->void:
	var event:=InputEventScreenTouch.new()
	event.index=id
	event.position=pos
	event.pressed=pressed
	event.canceled=canceled
	root.push_input(event,true)

func _drag(id:int,pos:Vector2,relative:Vector2)->void:
	var event:=InputEventScreenDrag.new()
	event.index=id
	event.position=pos
	event.relative=relative
	root.push_input(event,true)

func _mouse(pos:Vector2,relative:Vector2,device:int=0)->void:
	var event:=InputEventMouseMotion.new()
	event.position=pos
	event.global_position=pos
	event.relative=relative
	event.device=device
	root.push_input(event,true)

func _click(pos:Vector2,device:int=0)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.position=pos
		event.global_position=pos
		event.pressed=pressed
		event.device=device
		root.push_input(event,true)

func _aim()->Vector2:
	return Vector2(player.rotation.y,player._pitch)

func _reset()->void:
	player.set_active(true)
	player.rotation.y=0
	player._pitch=0
	player.camera.rotation.x=0
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _right()->Vector2:
	return Vector2(root.get_visible_rect().size.x*0.74,root.get_visible_rect().size.y*0.32)

func _stick()->Vector2:
	return player.hud._control_rects()["stick"].get_center()

func _run()->void:
	root.size=Vector2i(1280,720)
	player=Player.new()
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.hud.attack_tapped.connect(func():taps.attack+=1)
	player.hud.jump_requested.connect(func():taps.jump+=1)
	player.hud.skill_tapped.connect(func():taps.skill+=1)
	player.hud.home_requested.connect(func():taps.home+=1)
	await process_frame
	_reset()
	_check(not Input.emulate_mouse_from_touch,"Battle must retain explicit multi-touch rather than mouse emulation")
	# A left-side press, including the old 35%-50% camera region, never becomes look.
	var left:=Vector2(575,240)
	_touch(7,left,true)
	_drag(7,left+Vector2(30,10),Vector2(30,10))
	_check(player._look_touch==-1 and _aim()==Vector2.ZERO,"Left-half touch acquired or moved the camera")
	_drag(7,_right(),Vector2(350,0))
	_check(player._look_touch==-1 and _aim()==Vector2.ZERO,"A left-starting finger became camera after crossing right")
	_touch(7,_right(),false)
	# Interleave movement and look. Releasing movement must not release look.
	_touch(5,_stick(),true)
	_drag(5,_stick()+Vector2(24,-28),Vector2(24,-28))
	var move:Vector2=player.hud.get_move_vector()
	_check(move.length()>0.1 and _aim()==Vector2.ZERO,"Movement stick changed camera or failed to move")
	_touch(19,_right(),true)
	_check(player._look_touch==19 and player.hud.get_move_vector()==move,"Right press stole the movement finger")
	_drag(19,_right()+Vector2(20,-10),Vector2(20,-10))
	_check(_aim().is_equal_approx(Vector2(-20,10)*Player.TOUCH_SENSITIVITY),"Right drag did not apply the expected look delta")
	var aim:=_aim()
	_drag(5,_stick()+Vector2(-20,-25),Vector2(-44,3))
	_check(_aim()==aim and player._look_touch==19,"Movement drag changed the camera owner")
	_touch(5,_stick(),false)
	_check(player.hud.get_move_vector()==Vector2.ZERO and player._look_touch==19,"Releasing movement released the camera finger")
	_drag(19,_right()+Vector2(25,-10),Vector2(5,0))
	_check(_aim()!=aim,"Camera stopped after movement finger release")
	_touch(19,_right(),false)
	_check(player._look_touch==-1,"Camera release did not clear its owner")
	# Browser drag.relative may be measured from the other finger. Derive the
	# camera delta from this owned finger's absolute positions in either ID order.
	for ids in [[2,1],[1,2]]:
		_reset()
		var look_id:int=ids[0]
		var move_id:int=ids[1]
		var look_start:=Vector2(1000,310)
		_touch(look_id,look_start,true)
		_touch(move_id,_stick(),true)
		_drag(move_id,_stick()+Vector2(0,-51),Vector2(0,-51))
		var look_end:=look_start+Vector2(20,0)
		var other_finger_relative:=look_end-(_stick()+Vector2(0,-51))
		_drag(look_id,look_end,other_finger_relative)
		_check(_aim().is_equal_approx(Vector2(-20,0)*Player.TOUCH_SENSITIVITY),"Browser mixed another finger into camera delta for IDs "+str(ids))
		_check(player.hud.get_move_vector().length()>0.1 and player._look_touch==look_id,"Browser-relative correction changed touch ownership")
	# The reverse order and unrelated IDs behave the same; no held finger takeover.
	_reset()
	_touch(2,_right(),true)
	_touch(31,_stick(),true)
	_drag(31,_stick()+Vector2(20,-20),Vector2(20,-20))
	_touch(44,_right()+Vector2(25,20),true)
	_drag(44,_right()+Vector2(35,20),Vector2(10,0))
	_check(player._look_touch==2 and _aim()==Vector2.ZERO,"Second camera candidate stole an existing owner")
	_touch(2,_right(),false)
	move=player.hud.get_move_vector()
	_check(move.length()>0.1,"Releasing camera stopped the movement finger")
	_drag(44,_right()+Vector2(45,20),Vector2(10,0))
	_check(player._look_touch==-1 and _aim()==Vector2.ZERO,"Already-held finger took over after another release")
	_drag(31,_right(),Vector2(800,-200))
	_check(player._look_touch==-1 and _aim()==Vector2.ZERO,"Movement finger crossing right took over camera")
	_touch(31,_right(),false)
	_touch(44,_right(),false)
	# Look pauses outside the right half. The boundary-return delta is discarded.
	_reset()
	_touch(83,_right(),true)
	_drag(83,_right()+Vector2(12,0),Vector2(12,0))
	aim=_aim()
	_drag(83,Vector2(620,240),Vector2(-339,10))
	_drag(83,Vector2(300,300),Vector2(-320,60))
	_check(_aim()==aim and player._look_touch==83,"Left-half drag moved or released the camera")
	_check(player.hud.get_move_vector()==Vector2.ZERO,"Camera finger became stick input while crossing left")
	_drag(83,Vector2(700,240),Vector2(400,-60))
	_check(_aim()==aim,"Returning to right half caused a camera jump")
	_drag(83,Vector2(710,245),Vector2(10,5))
	_check(_aim().is_equal_approx(aim+Vector2(-10,-5)*Player.TOUCH_SENSITIVITY),"Camera did not resume with the next right-side delta")
	_touch(83,Vector2(710,245),false)
	# Every combat/Home control owns its touch even when dragged outside the UI.
	for key:String in taps:
		_reset()
		var count:int=taps[key]
		var button:Vector2=player.hud._control_rects()[key].get_center()
		_touch(67,button,true)
		_check(taps[key]==count+1 and player._look_touch==-1,"UI press failed or acquired look: "+key)
		_drag(67,_right(),_right()-button)
		_check(_aim()==Vector2.ZERO and player._look_touch==-1,"UI touch became camera after leaving its button: "+key)
		_touch(67,_right(),false)
		_check(player.hud._touch_owners.is_empty(),"UI release retained its owner: "+key)
	# UI touch during look must not steal it, and releasing look cannot promote UI.
	_reset()
	_touch(9,_right(),true)
	var attack:Vector2=player.hud._control_rects()["attack"].get_center()
	_touch(21,attack,true)
	_check(player._look_touch==9,"Attack press stole camera owner")
	_touch(9,_right(),false)
	_drag(21,_right(),_right()-attack)
	_check(player._look_touch==-1 and _aim()==Vector2.ZERO,"Held attack finger became look after camera release")
	_touch(21,_right(),false)
	# Per-finger OS cancellation preserves the other owner's input.
	_reset()
	_touch(11,_stick(),true)
	_drag(11,_stick()+Vector2(15,-20),Vector2(15,-20))
	_touch(28,_right(),true)
	_touch(28,_right(),false,true)
	_check(player._look_touch==-1 and player.hud.get_move_vector().length()>0.1,"Canceled look disrupted movement or retained camera")
	_touch(11,_stick(),false,true)
	_check(player.hud.get_move_vector()==Vector2.ZERO and player.hud._touch_owners.is_empty(),"Canceled movement stayed active")
	var attack_count:int=taps.attack
	_touch(55,attack,true,true)
	_check(taps.attack==attack_count and player._look_touch==-1,"Canceled press fired a control or acquired look")
	# Resizing/orientation cancels both owners and recomputes the halfway boundary.
	for size in [Vector2i(900,720),Vector2i(720,1280),Vector2i(1280,720)]:
		_touch(1,_stick(),true)
		_drag(1,_stick()+Vector2(15,-15),Vector2(15,-15))
		_touch(3,_right(),true)
		root.size=size
		await process_frame
		_check(player._look_touch==-1 and player.hud.get_move_vector()==Vector2.ZERO and player.hud._touch_owners.is_empty(),"Resize kept old touch ownership: "+str(size))
		_check(is_equal_approx(player._look_split_x,root.get_visible_rect().size.x*0.5),"Resize left a stale camera boundary")
		aim=_aim()
		_drag(3,_right()+Vector2(15,0),Vector2(15,0))
		_check(_aim()==aim,"Old camera drag survived resize")
		var new_left:=Vector2(root.get_visible_rect().size.x*0.45,200)
		_touch(4,new_left,true)
		_check(player._look_touch==-1,"New left half acquired camera after resize")
		_touch(4,new_left,false)
		_touch(6,_right(),true)
		_check(player._look_touch==6,"Fresh right press did not work after resize")
		_touch(6,_right(),false)
	# Home/death/spawn preparation and focus loss clear both owners.
	for lifecycle in ["home","death","spawn","focus"]:
		_reset()
		_touch(16,_stick(),true)
		_drag(16,_stick()+Vector2(10,-10),Vector2(10,-10))
		_touch(23,_right(),true)
		match lifecycle:
			"home","death":player.set_active(false)
			"spawn":player.prepare_spawn()
			"focus":player.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		_check(player._look_touch==-1 and player.hud.get_move_vector()==Vector2.ZERO and player.hud._touch_owners.is_empty(),"Lifecycle did not clear owners: "+lifecycle)
		player.set_active(true)
		aim=_aim()
		_drag(23,_right()+Vector2(20,0),Vector2(20,0))
		_check(_aim()==aim and player._look_touch==-1,"Stale touch resumed after lifecycle: "+lifecycle)
	# Desktop mouse capture/attack remains unchanged; emulated mouse is ignored.
	_reset()
	_click(_right(),-1)
	_check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Emulated mouse acquired capture")
	_click(_right())
	var window_capture:=DisplayServer.get_name()!="headless"
	if window_capture:
		_check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Real mouse could not capture camera")
	else:
		# Godot's headless display keeps mouse_mode VISIBLE even after CAPTURED.
		skipped.append("Window required: real mouse capture")
	_mouse(_right(),Vector2(13,-4))
	if window_capture:
		_check(_aim().is_equal_approx(Vector2(-13,4)*Player.MOUSE_SENSITIVITY),"Real mouse camera fallback changed")
	else:skipped.append("Window required: captured mouse camera")
	aim=_aim()
	_mouse(_right(),Vector2(100,100),-1)
	_check(_aim()==aim,"Emulated mouse duplicated touch camera movement")
	_click(_right(),-1)
	_check(player._pending_normal<0,"Emulated mouse generated an attack")
	_click(_right())
	if window_capture:
		_check(player._pending_normal>0,"Real mouse attack fallback stopped working")
	else:skipped.append("Window required: captured mouse attack")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	player.queue_free()
	await process_frame
	print("ARENA_TOUCH_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"skipped":skipped,"native_input_events":true}))
	quit(0 if failures.is_empty() else 1)
