extends CharacterBody3D
## Only the controller owns tap recognition. No initial normal hit leaks into a double.
const CHARACTER = preload("res://scripts/voxel_character.gd")
const DOUBLE_WINDOW := 0.25
const WALK_SPEED := 4.8
const RUN_SPEED := 7.2
const JUMP_SPEED := 6.0
const GRAVITY := 18.0

var camera: Camera3D
var combat: Node3D
var hud: CanvasLayer
var active := false
var job_id := "warrior"
var female := false
var equipped := true
var _pitch := 0.0
var _attack_pending := -1.0
var _skill_pending := -1.0
var _look_touch := -1
var _jump_queued := false
var _weapon: Node3D
var _weapon_mount: Node3D
var _swing := 0.0
var _strong := false
var _bob := 0.0

signal selection_requested
signal equipment_changed(armed: bool)

func _ready() -> void:
	collision_layer = 4
	collision_mask = 3
	floor_snap_length = 0.25
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.position.y = 1.63
	camera.near = 0.045
	camera.far = 100.0
	camera.fov = 72.0
	add_child(camera)
	_weapon_mount = Node3D.new()
	_weapon_mount.position = Vector3(0.34, -0.38, -0.58)
	camera.add_child(_weapon_mount)
	_create_equipment()
	for binding in [["forward", KEY_W, KEY_UP], ["back", KEY_S, KEY_DOWN], ["left", KEY_A, KEY_LEFT], ["right", KEY_D, KEY_RIGHT], ["jump", KEY_SPACE], ["run", KEY_SHIFT]]:
		var action: String = "lab_" + binding[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in binding.slice(1):
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func configure(job: String, is_female: bool) -> void:
	job_id = job
	female = is_female
	equipped = true
	if is_instance_valid(_weapon_mount):
		_create_equipment()

func set_active(value: bool) -> void:
	active = value
	cancel_input()
	if not value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		velocity = Vector3.ZERO
	elif not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func cancel_input() -> void:
	_attack_pending = -1.0
	_skill_pending = -1.0
	_look_touch = -1
	_jump_queued = false
	if is_instance_valid(hud):
		hud.reset_input()

func attack_tap() -> void:
	if not active:
		return
	if _attack_pending >= 0.0:
		_attack_pending = -1.0
		combat.request_attack(true)
	else:
		_attack_pending = DOUBLE_WINDOW

func skill_tap() -> void:
	if not active:
		return
	if _skill_pending >= 0.0:
		_skill_pending = -1.0
		combat.use_skill()
	else:
		_skill_pending = DOUBLE_WINDOW

func queue_jump() -> void:
	if active:
		_jump_queued = true

func toggle_equipment() -> void:
	if not active:
		return
	_attack_pending = -1.0
	_skill_pending = -1.0
	equipped = not equipped
	combat.equipped = equipped
	combat.status_changed.emit()
	_create_equipment()
	equipment_changed.emit(equipped)

func respawn() -> void:
	position = Vector3(0, 0.1, 4.6)
	rotation = Vector3.ZERO
	_pitch = 0.0
	camera.rotation.x = 0.0
	velocity = Vector3.ZERO
	cancel_input()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and event.device != -1 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative, 0.0025)
	elif event is InputEventMouseButton and event.device != -1 and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hud.is_ui_position(event.position):
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		attack_tap()
	elif event is InputEventScreenTouch and event.pressed and _look_touch < 0:
		if event.position.x > get_viewport().get_visible_rect().size.x * 0.35 and not hud.is_ui_position(event.position):
			_look_touch = event.index

func _input(event: InputEvent) -> void:
	if not active:
		return
	# Capture menu keys before Control consumes Tab as ui_focus_next.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE, KEY_TAB:
				selection_requested.emit()
			KEY_E:
				toggle_equipment()
			KEY_Q:
				skill_tap()
			KEY_R:
				respawn()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag and event.index == _look_touch:
		_look(event.relative, 0.0042)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed and event.index == _look_touch:
		_look_touch = -1
		get_viewport().set_input_as_handled()

func _look(relative: Vector2, sensitivity: float) -> void:
	rotation.y -= relative.x * sensitivity
	_pitch = clampf(_pitch - relative.y * sensitivity, -1.35, 1.35)
	camera.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not active:
		return
	if _attack_pending >= 0.0:
		_attack_pending -= delta
		if _attack_pending < 0.0:
			combat.request_attack(false)
	if _skill_pending >= 0.0:
		_skill_pending -= delta
		if _skill_pending < 0.0:
			# First jobs have one skill; a single tap selects it without casting.
			hud.show_feedback("選択：" + combat.get_skill_name() + "  ·  2回タップで使用")
	var axis := Input.get_vector("lab_left", "lab_right", "lab_forward", "lab_back")
	if hud.move_vector.length_squared() > 0.001:
		axis = hud.move_vector
	var direction := transform.basis * Vector3(axis.x, 0, axis.y)
	var speed := RUN_SPEED if Input.is_action_pressed("lab_run") else WALK_SPEED
	velocity.x = move_toward(velocity.x, direction.x * speed, 25.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 25.0 * delta)
	if is_on_floor():
		velocity.y = -0.2
		if Input.is_action_just_pressed("lab_jump") or _jump_queued:
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	_jump_queued = false
	move_and_slide()
	if position.y < -5.0:
		respawn()

func animate_attack(strong: bool) -> void:
	_swing = 0.36
	_strong = strong

func _process(delta: float) -> void:
	if not active or not is_instance_valid(_weapon_mount):
		return
	_swing = maxf(0, _swing - delta)
	var phase := 1.0 - _swing / 0.36
	var pulse := sin(phase * PI) if _swing > 0 else 0.0
	_bob += delta * Vector2(velocity.x, velocity.z).length() * 2.2
	_weapon_mount.position = Vector3(0.34, -0.38 + sin(_bob) * 0.008, -0.58)
	_weapon_mount.rotation_degrees = Vector3(-12, -8, -12)
	# Double input keeps the same visual trajectory as a normal attack.
	if not equipped or job_id == "scout":
		_weapon_mount.position.z -= pulse * 0.26
	elif job_id in ["mage", "cleric", "archer"]:
		_weapon_mount.position.z += pulse * 0.12
		_weapon_mount.rotation_degrees.x -= pulse * 10.0
	else:
		_weapon_mount.rotation_degrees += Vector3(60, -28, 65) * pulse
		_weapon_mount.position.x -= pulse * 0.2

func _create_equipment() -> void:
	for child in _weapon_mount.get_children():
		child.free()
	_weapon = CHARACTER.create_weapon(job_id if equipped else "")
	_weapon.scale = Vector3.ONE * 0.78
	_weapon_mount.add_child(_weapon)
	var hand := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.105, 0.14, 0.12)
	hand.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ddb48f" if female else "c99d7a")
	material.roughness = 1.0
	hand.material_override = material
	hand.position.y = -0.06
	_weapon_mount.add_child(hand)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_input()
		# Stop held movement on focus loss; the character menu is a safe resume point.
		if active:
			selection_requested.emit()
