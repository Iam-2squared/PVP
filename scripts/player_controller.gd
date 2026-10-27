extends CharacterBody3D

const HUD_SCRIPT = preload("res://scripts/hud.gd")
const WALK_SPEED := 4.8
const RUN_SPEED := 7.2
const GRAVITY := 18.0
const JUMP_SPEED := 6.0
const MOUSE_SENSITIVITY := 0.0025
const TOUCH_SENSITIVITY := 0.0042
const STEP_HEIGHT := 0.55

var world: Node3D
var camera: Camera3D
var aerial_camera: Camera3D
var hud: CanvasLayer

var _pitch := 0.0
var _look_touch := -1
var _overview := false
var _capture_before_overview := false
var _jump_queued := false
var _debug_visible := false
var _weapon: Node3D
var _weapon_rest_position := Vector3(0.32, -0.38, -0.65)
var _attack_time := 0.0
var _attack_strength := 1.0
var _last_attack_ms := -1000
var _environment_preview := false
var _step_visual_offset := 0.0
var _world_extent := 470.0


func _ready() -> void:
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	safe_margin = 0.02
	_ensure_input_actions()
	if is_instance_valid(world):
		_environment_preview = bool(world.get_meta("environment_preview", false))
		_world_extent = float(world.get_meta("world_extent", 470.0))
	_create_body()
	_create_cameras()
	if not _environment_preview:
		_create_weapon()
	hud = HUD_SCRIPT.new()
	hud.player = self
	hud.world = world
	add_child(hud)
	hud.jump_requested.connect(_queue_jump)
	hud.attack_requested.connect(_attack)
	hud.overview_requested.connect(func(): set_overview(not _overview))
	# Every finger is tracked explicitly; mouse emulation supports only one.
	Input.emulate_mouse_from_touch = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _create_body() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)


func _create_cameras() -> void:
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.position.y = 1.65
	camera.fov = 76.0
	camera.near = 0.08
	camera.far = 1200.0
	camera.current = true
	add_child(camera)
	aerial_camera = Camera3D.new()
	aerial_camera.name = "OverviewCamera"
	aerial_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	aerial_camera.size = 320.0 if _environment_preview else 385.0
	aerial_camera.near = 0.2
	aerial_camera.far = 1500.0
	add_child(aerial_camera)
	aerial_camera.top_level = true
	aerial_camera.global_position = Vector3(0.0, 340.0, 270.0) if _environment_preview else Vector3(0.0, 460.0, 330.0)
	aerial_camera.look_at(Vector3(0,4,0) if _environment_preview else Vector3.ZERO, Vector3.UP)


func _create_weapon() -> void:
	_weapon = Node3D.new()
	_weapon.name = "PracticeSword"
	_weapon.position = _weapon_rest_position
	_weapon.rotation_degrees = Vector3(-18, -8, -24)
	camera.add_child(_weapon)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("b7c9d5")
	steel.metallic = 0.55
	steel.roughness = 0.35
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("c6a261")
	gold.metallic = 0.3
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color("49392e")
	_weapon_box(Vector3(0, 0.16, 0), Vector3(0.045, 0.58, 0.018), steel)
	_weapon_box(Vector3(0, -0.14, 0), Vector3(0.19, 0.035, 0.05), gold)
	_weapon_box(Vector3(0, -0.23, 0), Vector3(0.04, 0.16, 0.035), grip)
	var point := MeshInstance3D.new()
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.028
	tip.height = 0.11
	tip.radial_segments = 4
	point.mesh = tip
	point.material_override = steel
	point.position = Vector3(0, 0.505, 0)
	point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_weapon.add_child(point)


func _weapon_box(pos: Vector3, dimensions: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_weapon.add_child(part)


func _ensure_input_actions() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])


func _bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_M:
			set_overview(not _overview)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE, KEY_P:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_look_touch = -1
			get_viewport().set_input_as_handled()
		KEY_F3:
			_debug_visible = not _debug_visible
			if hud.has_method("set_debug"):
				hud.set_debug(_debug_visible)
			get_viewport().set_input_as_handled()
		KEY_R:
			respawn()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _overview:
		return
	if event is InputEventMouseMotion:
		if event.device != -1 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_rotate_look(event.relative, MOUSE_SENSITIVITY)
	elif event is InputEventMouseButton:
		if event.device == -1:
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if hud.is_ui_position(event.position):
				return
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_attack()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventScreenTouch:
		if event.pressed:
			if _look_touch == -1 and event.position.x > get_viewport().get_visible_rect().size.x * 0.35 and not hud.is_ui_position(event.position):
				_look_touch = event.index


func _input(event: InputEvent) -> void:
	# Once a finger owns the camera, crossing a HUD button must not steal it.
	if event is InputEventScreenDrag and event.index == _look_touch and not _overview:
		_rotate_look(event.relative, TOUCH_SENSITIVITY)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.index == _look_touch and not event.pressed:
		_look_touch = -1
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_look_touch = -1
		_jump_queued = false


func _rotate_look(relative: Vector2, sensitivity: float) -> void:
	rotate_y(-relative.x * sensitivity)
	_pitch = clampf(_pitch - relative.y * sensitivity, -1.3, 1.3)
	camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if _overview:
		velocity = Vector3.ZERO
		_jump_queued = false
		return
	var was_grounded := is_on_floor()
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var touch_vector: Vector2 = hud.get_move_vector()
	if touch_vector.length_squared() > 0.001:
		input_vector = touch_vector
	var movement := global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)
	movement.y = 0.0
	if movement.length_squared() > 1.0:
		movement = movement.normalized()
	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var acceleration := 24.0 if is_on_floor() else 10.0
	velocity.x = move_toward(velocity.x, movement.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, movement.z * speed, acceleration * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -0.2
	var jumping := (Input.is_action_just_pressed("jump") or _jump_queued) and is_on_floor()
	if jumping:
		velocity.y = JUMP_SPEED
	_jump_queued = false
	var horizontal_motion := Vector3(velocity.x, 0, velocity.z) * delta
	move_and_slide()
	# No additional casts on clear ground. Only a grounded body blocked by a wall
	# attempts the up/forward/down test, and every part uses the real capsule.
	if was_grounded and not jumping and velocity.y <= 0.1 and is_on_wall() and horizontal_motion.length_squared() > 0.000001:
		_try_step_up(horizontal_motion)
	var fall_limit := -1.8 if _environment_preview else -8.0
	if global_position.y < fall_limit or absf(global_position.x) > _world_extent or absf(global_position.z) > _world_extent:
		respawn()


func _try_step_up(horizontal_motion: Vector3) -> bool:
	if not is_on_floor() or velocity.y > 0.1:
		return false
	var start := global_transform
	# A low ceiling must not allow the capsule to be lifted through it.
	if test_move(start, Vector3.UP * STEP_HEIGHT):
		return false
	var raised := start
	raised.origin.y += STEP_HEIGHT
	# The capsule's center must clear a block edge before its downcast can find
	# the horizontal top, rather than the rounded capsule's steep edge contact.
	var forward_motion := horizontal_motion.normalized() * maxf(horizontal_motion.length(), 0.38)
	if test_move(raised, forward_motion):
		return false
	var forward := raised
	forward.origin += forward_motion
	var landing := KinematicCollision3D.new()
	if not test_move(forward, Vector3.DOWN * (STEP_HEIGHT + 0.08), landing):
		return false
	if landing.get_normal().y < cos(floor_max_angle):
		return false
	var destination := forward.origin + landing.get_travel()
	var rise := destination.y - start.origin.y
	# A downcast must find a genuine reachable step, not empty air or a drop.
	if rise < 0.015 or rise > STEP_HEIGHT + 0.005:
		return false
	global_position = destination
	velocity.y = -0.2
	_step_visual_offset = maxf(_step_visual_offset - rise, -STEP_HEIGHT)
	apply_floor_snap()
	return true


func _process(delta: float) -> void:
	_step_visual_offset = move_toward(_step_visual_offset, 0.0, delta * 4.0)
	if camera != null:
		camera.position.y = 1.65 + _step_visual_offset
	if _weapon == null:
		return
	if _attack_time > 0.0:
		_attack_time = maxf(0.0, _attack_time - delta)
		var phase := 1.0 - _attack_time / 0.32
		var swing := sin(phase * PI) * _attack_strength
		_weapon.position = _weapon_rest_position + Vector3(-0.33, 0.06, 0.07) * swing
		_weapon.rotation_degrees = Vector3(-18 + 70 * swing, -8, -24 + 80 * swing)
	else:
		_weapon.position = _weapon_rest_position
		_weapon.rotation_degrees = Vector3(-18, -8, -24)


func _queue_jump() -> void:
	_jump_queued = true


func _attack() -> void:
	if _overview or _weapon == null:
		return
	var now := Time.get_ticks_msec()
	_attack_strength = 1.12 if now - _last_attack_ms < 280 else 1.0
	_last_attack_ms = now
	_attack_time = 0.32


func set_overview(enabled: bool) -> void:
	if enabled == _overview:
		return
	_overview = enabled
	_look_touch = -1
	if enabled:
		_capture_before_overview = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		aerial_camera.current = true
	else:
		camera.current = true
		if _capture_before_overview:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _weapon != null:
		_weapon.visible = not enabled
	if hud.has_method("set_overview"):
		hud.set_overview(enabled)


func get_overview() -> bool:
	return _overview


func respawn() -> void:
	velocity = Vector3.ZERO
	_jump_queued = false
	_step_visual_offset = 0.0
	global_position = world.get_spawn_position() if is_instance_valid(world) and world.has_method("get_spawn_position") else Vector3(0.0, 1.2, 150.0)
	rotation.y = 0.0
	_pitch = 0.0
	camera.rotation.x = 0.0
