extends SceneTree
## Physics-backed regression checks for the independent character playground.
## Run: godot --headless --path character_playground --fixed-fps 60 --script res://tools/test_playground.gd

const CHARACTER = preload("res://scripts/voxel_character.gd")
const COMBAT = preload("res://scripts/combat_system.gd")
const TARGET = preload("res://scripts/practice_target.gd")
const CONTROLLER = preload("res://scripts/play_controller.gd")
const HUD = preload("res://scripts/play_hud.gd")
var checks: Array[Dictionary] = []
var fixture: Node3D
var combat: Node3D
var camera: Camera3D
var target: StaticBody3D


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	checks.append({"passed": ok, "description": description})
	print("%s %s" % ["PASS" if ok else "FAIL", description])


func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func reset_target(distance: float = 2.0) -> void:
	target.position = Vector3(0, 0, -distance)
	target.health = 1000.0
	target.collision_layer = 2


func run() -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	current_scene = fixture
	camera = Camera3D.new()
	camera.position.y = 1.4
	fixture.add_child(camera)
	combat = COMBAT.new()
	combat.camera = camera
	fixture.add_child(combat)
	target = TARGET.new()
	target.max_health = 1000.0
	fixture.add_child(target)
	reset_target()
	await frames(2)
	for job: String in COMBAT.JOBS:
		for female: bool in [false, true]:
			var model: Node3D = CHARACTER.new()
			model.configure(job, female)
			fixture.add_child(model)
			var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
			var vertices := 0
			for visual: MeshInstance3D in meshes:
				for surface in visual.mesh.get_surface_count():
					vertices += visual.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
			check(vertices >= 300 and is_instance_valid(model.right_hand) and is_instance_valid(model.left_hand), "%s %s: articulated voxel figure" % [job, "female" if female else "male"])
			var before: Transform3D = model.right_hand.global_transform
			model.animate(1.0, 0.12)
			model.play_attack(false)
			model.animate(1.0, 0.12, true)
			check(not model.right_hand.global_transform.is_equal_approx(before), "%s %s: walk/attack animation moves hand" % [job, "female" if female else "male"])
			model.free()
		reset_target()
		combat.configure(job)
		await frames(2)
		check(combat.request_attack(false), "%s: accepts normal attack" % job)
		check(not combat.request_attack(false), "%s: cooldown prevents duplicate attack" % job)
		await frames(22)
		var normal_damage: float = 1000.0 - target.health
		check(is_equal_approx(normal_damage, float(COMBAT.JOBS[job].damage)), "%s: basic attack actually damages target" % job)
		var normal_range: float = combat.last_range
		reset_target()
		combat.configure(job)
		await frames(2)
		combat.request_attack(true)
		await frames(22)
		check(is_equal_approx(1000.0 - target.health, normal_damage * 1.2), "%s: strong attack deals exactly 1.2x" % job)
		check(is_equal_approx(combat.last_range, normal_range), "%s: strong attack keeps normal range" % job)
		reset_target(40.0)
		combat.configure(job)
		await frames(2)
		combat.request_attack(true)
		await frames(150)
		check(is_equal_approx(target.health, 1000.0), "%s: attack cannot exceed its range" % job)
		reset_target(1.3)
		combat.configure(job, false)
		await frames(2)
		combat.request_attack(false)
		check(is_equal_approx(1000.0 - target.health, COMBAT.UNARMED_DAMAGE), "%s: unequipped attack punches" % job)
		reset_target(1.3)
		combat.configure(job, false)
		combat.request_attack(true)
		check(is_equal_approx(1000.0 - target.health, COMBAT.UNARMED_DAMAGE * 1.2), "%s: unequipped strong punch is 1.2x" % job)
		check(not combat.use_skill(), "%s: unarmed skill is blocked" % job)
		reset_target()
		combat.configure(job)
		combat.health = 40.0
		await frames(2)
		check(combat.use_skill(), "%s: job skill accepted" % job)
		check(not combat.use_skill(), "%s: skill cooldown enforced" % job)
		check(combat.mana < 100.0, "%s: skill consumes provisional MP" % job)
		await frames(30)
		check(combat.health > 40.0 if job == "cleric" else target.health < 1000.0, "%s: skill produces actual healing/damage" % job)
	# World obstruction applies to all melee attacks and swept projectiles.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.1)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1, -1)
	fixture.add_child(wall)
	await frames(2)
	for job: String in COMBAT.JOBS:
		reset_target()
		combat.configure(job)
		combat.request_attack(true)
		await frames(30)
		check(is_equal_approx(target.health, 1000.0), "%s: wall blocks basic attack" % job)
		combat.configure(job)
		combat.use_skill()
		await frames(30)
		check(is_equal_approx(target.health, 1000.0), "%s: wall blocks offensive skill" % job)
	wall.queue_free()
	await frames(2)
	# Input arbitration belongs to the real controller, never to a test double.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100, 0.2, 100)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.1
	fixture.add_child(floor_body)
	var hud: CanvasLayer = HUD.new()
	fixture.add_child(hud)
	var player: CharacterBody3D = CONTROLLER.new()
	player.hud = hud
	player.combat = combat
	player.position = Vector3(5, 0.05, 5)
	fixture.add_child(player)
	player.active = true
	combat.camera = player.camera
	combat.configure("warrior")
	await frames(5)
	var shots: int = combat.shots_fired
	player.attack_tap()
	check(combat.shots_fired == shots, "single tap waits for double window before firing")
	await frames(5)
	player.attack_tap()
	check(combat.shots_fired == shots + 1 and is_equal_approx(combat.last_damage, 21.6), "double tap immediately fires exactly one strong attack")
	await frames(35)
	check(combat.shots_fired == shots + 1, "double tap never leaks a delayed normal attack")
	player.attack_tap()
	await frames(20)
	check(combat.shots_fired == shots + 2 and is_equal_approx(combat.last_damage, 18.0), "single tap resolves as exactly one normal attack")
	await frames(20)
	player.attack_tap()
	player.cancel_input()
	await frames(20)
	check(combat.shots_fired == shots + 2, "opening menu/focus cancellation clears pending attack")
	combat.configure("warrior")
	player.skill_tap()
	await frames(20)
	check(is_equal_approx(combat.mana, 100.0), "single skill tap selects without casting")
	player.skill_tap()
	await frames(5)
	player.skill_tap()
	check(is_equal_approx(combat.mana, 85.0), "double skill tap casts once without earlier selection")
	var start_z: float = player.position.z
	Input.action_press("lab_forward")
	await frames(30)
	Input.action_release("lab_forward")
	check(player.position.z < start_z - 1.0, "WASD action actually moves physics character")
	await frames(20)
	var floor_y: float = player.position.y
	player.queue_jump()
	await frames(10)
	check(player.position.y > floor_y + 0.3, "jump button launches grounded character")
	await frames(70)
	check(player.is_on_floor(), "jump lands on collision floor")
	combat.configure("warrior")
	hud.attack_tapped.connect(player.attack_tap)
	var rects: Dictionary = hud._control_rects()
	var stick_rect: Rect2 = rects.stick
	var attack_rect: Rect2 = rects.attack
	var stick_down := InputEventScreenTouch.new()
	stick_down.index = 0
	stick_down.position = stick_rect.get_center()
	stick_down.pressed = true
	hud._input(stick_down)
	var stick_drag := InputEventScreenDrag.new()
	stick_drag.index = 0
	stick_drag.position = stick_rect.get_center() + Vector2(0, -40)
	hud._input(stick_drag)
	check(hud.move_vector.y < -0.3, "native touch joystick owns first finger")
	var touch_shots: int = combat.shots_fired
	for tap_index in 2:
		var attack_down := InputEventScreenTouch.new()
		attack_down.index = 1
		attack_down.position = attack_rect.get_center()
		attack_down.pressed = true
		hud._input(attack_down)
		var attack_up := InputEventScreenTouch.new()
		attack_up.index = 1
		attack_up.position = attack_down.position
		attack_up.pressed = false
		hud._input(attack_up)
		await frames(3)
	check(combat.shots_fired == touch_shots + 1 and is_equal_approx(combat.last_damage, 21.6), "second finger double tap fires one strong attack while moving")
	check(hud.move_vector.y < -0.3, "attack release does not steal joystick finger")
	var stick_up := InputEventScreenTouch.new()
	stick_up.index = 0
	stick_up.position = stick_drag.position
	stick_up.pressed = false
	hud._input(stick_up)
	check(hud.move_vector.is_zero_approx(), "joystick release clears movement")
	player.attack_tap()
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	var focus_shots: int = combat.shots_fired
	await frames(20)
	check(combat.shots_fired == focus_shots and player._attack_pending < 0.0, "window focus loss cancels pending tap")
	var menu_events := {"count": 0}
	player.selection_requested.connect(func() -> void: menu_events.count += 1)
	for key in [KEY_TAB, KEY_ESCAPE]:
		var menu_key := InputEventKey.new()
		menu_key.physical_keycode = key
		menu_key.keycode = key
		menu_key.pressed = true
		Input.parse_input_event(menu_key)
		await frames(2)
	check(menu_events.count == 2, "Tab and Escape reach controller before GUI focus navigation")
	player.active = false
	player.free()
	hud.free()
	var failures: int = checks.filter(func(entry: Dictionary) -> bool: return not entry.passed).size()
	var result := {"passed": failures == 0, "total": checks.size(), "failures": failures, "checks": checks}
	var output := FileAccess.open("res://docs/headless-results.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(result, "\t") + "\n")
		output.close()
	print("PLAYGROUND_TEST_RESULTS " + JSON.stringify({"total": checks.size(), "failures": failures}))
	fixture.free()
	await process_frame
	quit(0 if failures == 0 else 1)
