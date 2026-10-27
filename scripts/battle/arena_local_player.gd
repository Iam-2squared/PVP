extends "res://scripts/player_controller.gd"
## Prediction uses the existing stair-capable city controller. The server owns hits.
signal attack_requested(strong:bool,skill:bool)
signal home_requested
const ArenaHUD=preload("res://scripts/battle/arena_hud.gd")
const Figure=preload("res://scripts/frontend/characters/voxel_character.gd")
const Rules=preload("res://scripts/battle/arena_rules.gd")
const DOUBLE_WINDOW:=0.25
var active:=false
var job_id:="warrior"
var speed_scale:=1.0
var _pending_normal:=-1.0
var _pending_skill:=-1.0
var _network_jump:=false
var _server_position:=Vector3(0,2.15,150)
var _last_authoritative_alive:=false
var _last_spawn_serial:=-1

func _ready()->void:
	floor_snap_length=0.35
	floor_max_angle=deg_to_rad(48.0)
	safe_margin=0.02
	_ensure_input_actions()
	_environment_preview=false
	_world_extent=160.0
	_create_body()
	collision_layer=4
	collision_mask=1
	_create_cameras()
	_create_weapon()
	hud=ArenaHUD.new()
	add_child(hud)
	hud.attack_tapped.connect(_attack)
	hud.skill_tapped.connect(_skill_tap)
	hud.jump_requested.connect(_queue_jump)
	hud.home_requested.connect(func():home_requested.emit())
	Input.emulate_mouse_from_touch=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _create_weapon()->void:
	if _weapon!=null:
		camera.remove_child(_weapon)
		_weapon.free()
	_weapon=Figure.create_weapon(job_id)
	_weapon.position=_weapon_rest_position
	_weapon.rotation_degrees=Vector3(-18,-8,-24)
	camera.add_child(_weapon)

func configure_profile(profile:Dictionary)->void:
	speed_scale=clampf(1.0+(float(profile.get("stats",{}).get("敏捷力",10))-10.0)*0.002,1.0,1.3)
	var next_job:=str(profile.get("job_id","warrior"))
	if next_job!=job_id:
		job_id=next_job
		if is_instance_valid(camera):_create_weapon()
	if is_instance_valid(hud):hud.set_profile(profile)

func set_active(enabled:bool)->void:
	if enabled and not active:_last_authoritative_alive=false
	active=enabled
	cancel_input()
	if is_instance_valid(hud):hud.visible=enabled
	if enabled:
		camera.current=true
	else:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func prepare_spawn()->void:
	_last_authoritative_alive=false
	_last_spawn_serial=-1
	active=false
	cancel_input()
	if is_instance_valid(hud):hud.visible=true

func cancel_input()->void:
	_pending_normal=-1
	_pending_skill=-1
	_network_jump=false
	_jump_queued=false
	_look_touch=-1
	velocity=Vector3.ZERO
	if is_instance_valid(hud):hud.reset_input()

func _queue_jump()->void:
	if active:
		_jump_queued=true
		_network_jump=true

func _unhandled_key_input(event:InputEvent)->void:
	if not active or not event is InputEventKey or not event.pressed or event.echo:return
	if event.physical_keycode in [KEY_ESCAPE,KEY_P]:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event.physical_keycode==KEY_Q:
		_skill_tap()
		get_viewport().set_input_as_handled()

func _unhandled_input(event:InputEvent)->void:
	if not active:return
	super._unhandled_input(event)

func _input(event:InputEvent)->void:
	if not active:return
	super._input(event)

func _notification(what:int)->void:
	super._notification(what)
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:cancel_input()

func _attack()->void:
	if not active:return
	if _pending_normal>=0:
		_pending_normal=-1
		_send_attack(true,false)
	else:_pending_normal=DOUBLE_WINDOW

func _skill_tap()->void:
	if not active:return
	if _pending_skill>=0:
		_pending_skill=-1
		_send_attack(false,true)
	else:_pending_skill=DOUBLE_WINDOW

func _send_attack(strong:bool,skill:bool)->void:
	_attack_strength=1.2 if strong or skill else 1.0
	_attack_time=0.32
	attack_requested.emit(strong,skill)

func _physics_process(delta:float)->void:
	if not active:return
	if Input.is_action_just_pressed("jump"):_network_jump=true
	if _pending_normal>=0:
		_pending_normal-=delta
		if _pending_normal<=0:
			_pending_normal=-1
			_send_attack(false,false)
	if _pending_skill>=0:
		_pending_skill-=delta
		if _pending_skill<=0:
			_pending_skill=-1
			hud.show_feedback(str(hud._skill_name)+" 選択 · 2回タップで使用")
	var was_grounded:=is_on_floor()
	var input_vector:=Input.get_vector("move_left","move_right","move_forward","move_back")
	var touch_vector:Vector2=hud.get_move_vector()
	if touch_vector.length_squared()>0.001:input_vector=touch_vector
	var movement:=global_transform.basis*Vector3(input_vector.x,0,input_vector.y)
	movement.y=0
	if movement.length_squared()>1:movement=movement.normalized()
	var speed:float=(RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED)*speed_scale
	var acceleration:=24.0 if is_on_floor() else 10.0
	velocity.x=move_toward(velocity.x,movement.x*speed,acceleration*delta)
	velocity.z=move_toward(velocity.z,movement.z*speed,acceleration*delta)
	if not is_on_floor():velocity.y-=GRAVITY*delta
	elif velocity.y<0:velocity.y=-0.2
	var jumping:bool=(Input.is_action_just_pressed("jump") or _jump_queued) and is_on_floor()
	if jumping:velocity.y=JUMP_SPEED
	_jump_queued=false
	var horizontal_motion:=Vector3(velocity.x,0,velocity.z)*delta
	move_and_slide()
	if was_grounded and not jumping and velocity.y<=0.1 and is_on_wall() and horizontal_motion.length_squared()>0.000001:
		_try_step_up(horizontal_motion)
	if position.y< -8 or not Rules.inside_city(position):respawn()

func input_packet()->Dictionary:
	var input_vector:=Input.get_vector("move_left","move_right","move_forward","move_back") if active else Vector2.ZERO
	if active and hud.get_move_vector().length_squared()>0.001:input_vector=hud.get_move_vector()
	var movement:=global_transform.basis*Vector3(input_vector.x,0,input_vector.y)
	if movement.length_squared()>1:movement=movement.normalized()
	var packet:={"move":[movement.x,movement.z],"yaw":rotation.y,"pitch":_pitch,"jump":_network_jump,"sprint":Input.is_action_pressed("sprint") and active}
	_network_jump=false
	return packet

func reconcile(data:Dictionary)->void:
	var pos:Array=data.get("position",[])
	if pos.size()!=3:return
	_server_position=Vector3(float(pos[0]),float(pos[1]),float(pos[2]))
	var living:=bool(data.get("alive",false))
	var spawn_serial:=int(data.get("spawn_serial",-1))
	var fresh_spawn:=spawn_serial>=0 and spawn_serial!=_last_spawn_serial
	if living and (not _last_authoritative_alive or fresh_spawn):
		position=_server_position
		rotation.y=float(data.get("yaw",0))
		_pitch=0
		camera.rotation.x=0
		_step_visual_offset=0
		velocity=Vector3.ZERO
	elif living:
		var distance:=position.distance_to(_server_position)
		if distance>1.25:position=_server_position
		elif distance>0.15:position=position.lerp(_server_position,0.32)
	_last_authoritative_alive=living
	if spawn_serial>=0:_last_spawn_serial=spawn_serial
	if living!=active:
		active=living
		cancel_input()
	_weapon.visible=living

func respawn()->void:
	position=_server_position if Rules.inside_city(_server_position) else Rules.spawn_points()[0]
	velocity=Vector3.ZERO
