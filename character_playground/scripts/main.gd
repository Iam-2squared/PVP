extends Node3D
## Composition root for a self-contained character lab. No map imports.
const CHARACTER = preload("res://scripts/voxel_character.gd")
const CONTROLLER = preload("res://scripts/play_controller.gd")
const COMBAT = preload("res://scripts/combat_system.gd")
const TARGET = preload("res://scripts/practice_target.gd")
const HUD = preload("res://scripts/play_hud.gd")
const SELECT = preload("res://scripts/character_select.gd")

var player: CharacterBody3D
var combat: Node3D
var hud: CanvasLayer
var selector: CanvasLayer
var preview: Node3D
var preview_camera: Camera3D
var showroom: Node3D
var training: Node3D
var gallery: Array[Node3D] = []
var current_job := "warrior"
var current_female := false
var _preview_time := 0.0
var _status_time := 0.0
# Keep the callback alive while JavaScript owns the listener.
var _pointer_lock_callback: JavaScriptObject

func _ready() -> void:
	Input.emulate_mouse_from_touch = false
	_build_environment()
	_build_showroom()
	_build_training()
	player = CONTROLLER.new()
	player.name = "Player"
	add_child(player)
	combat = COMBAT.new()
	combat.name = "Combat"
	combat.camera = player.camera
	add_child(combat)
	player.combat = combat
	hud = HUD.new()
	hud.name = "PlayHUD"
	add_child(hud)
	player.hud = hud
	hud.attack_tapped.connect(player.attack_tap)
	hud.skill_tapped.connect(player.skill_tap)
	hud.jump_requested.connect(player.queue_jump)
	hud.selection_requested.connect(open_selection)
	hud.equipment_toggled.connect(player.toggle_equipment)
	player.selection_requested.connect(open_selection)
	combat.attack_fired.connect(player.animate_attack)
	combat.feedback.connect(hud.show_feedback)
	selector = SELECT.new()
	selector.name = "CharacterSelect"
	add_child(selector)
	selector.preview_changed.connect(_preview_changed)
	selector.play_requested.connect(start_play)
	open_selection()
	if OS.has_feature("web"):
		_pointer_lock_callback = JavaScriptBridge.create_callback(_on_web_pointer_lock)
		JavaScriptBridge.get_interface("document").addEventListener("pointerlockchange", _pointer_lock_callback)
	print("PLAYGROUND_READY")

func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("26383f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c0d5de")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -25, 0)
	sun.light_color = Color("ffe6c2")
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_color = Color("a9d3df")
	fill.light_energy = 0.22
	add_child(fill)

func _build_showroom() -> void:
	showroom = Node3D.new()
	showroom.name = "CharacterShowroom"
	showroom.position = Vector3(80, 0, 0)
	add_child(showroom)
	_box(showroom, Vector3(0, -0.25, 0), Vector3(80, 0.3, 80), Color("273a41"))
	_box(showroom, Vector3(0, -0.06, 0), Vector3(2.7, 0.24, 2.7), Color("455b61"))
	_box(showroom, Vector3(0, 0.065, 0), Vector3(2.55, 0.025, 2.55), Color("394a50"))
	for x in [-1.3, 1.3]:
		_box(showroom, Vector3(x, 0.085, 0), Vector3(0.025, 0.02, 2.6), Color("c7b580"))
	for z in [-1.3, 1.3]:
		_box(showroom, Vector3(0, 0.085, z), Vector3(2.6, 0.02, 0.025), Color("c7b580"))
	# Small staggered blocks suggest a studio, not a game-map production area.
	for i in 7:
		_box(showroom, Vector3((i - 3) * 1.4, -0.1, -3.8), Vector3(0.9, 0.5 + (i % 3) * 0.3, 0.9), Color("30464d"))
	preview_camera = Camera3D.new()
	preview_camera.name = "ShowroomCamera"
	preview_camera.position = Vector3(3.1, 2.1, 5.1)
	preview_camera.fov = 32
	showroom.add_child(preview_camera)
	preview_camera.look_at(showroom.global_position + Vector3(0, 1.0, 0))

func _build_training() -> void:
	training = Node3D.new()
	training.name = "IsolatedTrainingFloor"
	add_child(training)
	_box(training, Vector3(0, -0.2, -3.0), Vector3(24, 0.4, 32), Color("596e72"), true)
	# Inlaid lanes are reference marks only. This project never generates the kingdom.
	for x in [-4.5, -1.5, 1.5, 4.5]:
		_box(training, Vector3(x, 0.006, -1), Vector3(0.025, 0.012, 24), Color("637b7e"))
	for z in range(-12, 11, 2):
		_box(training, Vector3(0, 0.009, z), Vector3(9, 0.012, 0.025), Color("788985"))
	for x in [-11.8, 11.8]:
		_box(training, Vector3(x, 0.4, -3), Vector3(0.35, 0.8, 32), Color("4a636a"), true)
	for z in [-18.8, 12.8]:
		_box(training, Vector3(0, 0.4, z), Vector3(24, 0.8, 0.35), Color("4a636a"), true)
	var positions := [Vector3(0, 0, 2.5), Vector3(-3, 0, -4), Vector3(3, 0, -9)]
	for i in positions.size():
		var target := TARGET.new()
		target.name = "PracticeTarget%d" % (i + 1)
		target.target_name = ["近接の標的", "中距離の標的", "遠距離の標的"][i]
		target.position = positions[i]
		training.add_child(target)
		_box(training, positions[i] + Vector3(0, 0.018, 0), Vector3(1.4, 0.035, 1.4), Color("607879"))
	# An actual obstacle allows players to check that shots do not travel through walls.
	_box(training, Vector3(6, 1.0, -4), Vector3(2.5, 2, 0.35), Color("556d73"), true)
	_sign(training, "CHARACTER  /  12 VOXEL FIGURES", Vector3(0, 3.05, -16), 42)
	_sign(training, "練習フィールド  ·  標的は3秒で復帰", Vector3(0, 2.5, -16), 30)
	for index in 12:
		var job: String = SELECT.ORDER[index % 6]
		var female := index >= 6
		var figure := CHARACTER.new()
		figure.configure(job, female)
		figure.position = Vector3((index % 6 - 2.5) * 2.2, 0.18, -14 - (2.1 if female else 0.0))
		figure.rotation.y = PI
		training.add_child(figure)
		gallery.append(figure)
		_box(training, figure.position - Vector3(0, 0.08, 0), Vector3(1.4, 0.16, 1.3), Color("566f73"))
		_sign(training, SELECT.JOBS[job].name + (" / 女" if female else " / 男"), figure.position + Vector3(0, 2.02, 0), 20)

func _box(parent: Node3D, at: Vector3, dimensions: Vector3, color: Color, collidable: bool = false) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	if collidable:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var solid := BoxShape3D.new()
		solid.size = dimensions
		shape.shape = solid
		body.position = at
		body.add_child(shape)
		parent.add_child(body)

func _sign(parent: Node3D, text: String, at: Vector3, font_size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = load("res://assets/ui.otf")
	label.font_size = font_size
	label.pixel_size = 0.006
	label.position = at
	label.modulate = Color("e3dfc9")
	label.outline_size = 3
	label.no_depth_test = false
	parent.add_child(label)

func open_selection() -> void:
	player.set_active(false)
	combat.enabled = false
	hud.blocked = true
	training.visible = false
	showroom.visible = true
	preview_camera.current = true
	selector.open(current_job, current_female)

func _preview_changed(job: String, female: bool) -> void:
	current_job = job
	current_female = female
	if is_instance_valid(preview):
		preview.free()
	preview = CHARACTER.new()
	preview.configure(job, female)
	preview.position.y = 0.08
	preview.rotation.y = PI + 0.15
	showroom.add_child(preview)
	_preview_time = 0.0

func start_play(job: String, female: bool) -> void:
	current_job = job
	current_female = female
	selector.close()
	showroom.visible = false
	training.visible = true
	player.configure(job, female)
	player.respawn()
	combat.configure(job, true)
	combat.enabled = true
	hud.blocked = false
	player.camera.current = true
	player.set_active(true)
	hud.show_feedback("左スティックで移動  ·  攻撃を2回押すと ×1.2")
	_update_status()
	print("PLAYGROUND_PLAY ", job, " female=", female)

func _update_status() -> void:
	hud.set_status(SELECT.JOBS[current_job].name + (" / 女" if current_female else " / 男"), combat.health, combat.mana, player.equipped)
	hud.set_skill(combat.get_skill_name(), combat.get_cooldown())
	if not player.active:
		return
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, player.camera.global_position - player.camera.global_basis.z * 35.0, 3)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_method("take_damage"):
		hud.set_target(hit.collider.target_name, hit.collider.health, hit.collider.max_health)
	else:
		hud.set_target("", 0, 100)

func _process(delta: float) -> void:
	if is_instance_valid(selector) and selector.is_open and is_instance_valid(preview):
		_preview_time += delta
		preview.rotation.y = PI + 0.15 + sin(_preview_time * 0.45) * 0.35
		preview.animate(0.0, delta)
	for figure in gallery:
		if training.visible:
			figure.animate(0.0, delta)
	_status_time += delta
	if _status_time > 0.08 and is_instance_valid(hud):
		_status_time = 0.0
		_update_status()


func _on_web_pointer_lock(_arguments: Array) -> void:
	# Browsers consume Escape before it reaches Godot. They also grant lock
	# asynchronously: a fast start->menu can finish locking after the menu opened.
	if not is_instance_valid(player):
		return
	var document := JavaScriptBridge.get_interface("document")
	if document.pointerLockElement == null:
		if player.active:
			open_selection.call_deferred()
	elif not player.active:
		document.exitPointerLock()
