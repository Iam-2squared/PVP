extends Control
## Optional presentation slot. No dependency on the gameplay player or models.
## Models face +Z, stand at y=0 and should fit within a 2-unit height.

var _viewport: SubViewport
var _placeholder := true
var accent := Color("c7ac73")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	visibility_changed.connect(_sync_preview_processing)
	_sync_preview_processing()


func display_scene(scene: PackedScene, show_weapon: bool = true) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_viewport = null
	_placeholder = scene == null
	if scene != null:
		var container := SubViewportContainer.new()
		container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		container.stretch = true
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(container)
		_viewport = SubViewport.new()
		# Each card has its own stage; six models must not share a World3D.
		_viewport.own_world_3d = true
		_viewport.size = Vector2i(360, 420)
		_viewport.transparent_bg = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		container.add_child(_viewport)
		var stage := Node3D.new()
		_viewport.add_child(stage)
		var character := scene.instantiate()
		if character is Node3D:
			stage.add_child(character)
			if character.has_method("set_weapon_visible"):
				character.set_weapon_visible(show_weapon)
		else:
			character.free()
			_placeholder = true
			push_warning("Character slot expects a Node3D scene.")
		var camera := Camera3D.new()
		camera.position = Vector3(0, 1.2, 4.2)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.8
		stage.add_child(camera)
		camera.look_at(Vector3(0, 1.0, 0))
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-30, -30, 0)
		light.light_energy = 1.15
		stage.add_child(light)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color("d4deed")
		environment.environment.ambient_light_energy = 0.7
		stage.add_child(environment)
	_sync_preview_processing()
	queue_redraw()


func _sync_preview_processing() -> void:
	# The container already stops drawing its hidden viewport. Its Node3D
	# children still process unless explicitly paused, even while Home is hidden.
	if is_instance_valid(_viewport):
		_viewport.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED


func _draw() -> void:
	var center := size * Vector2(0.5, 0.49)
	var unit := minf(size.x * 0.27, size.y * 0.33)
	# Neutral outline denotes an empty slot, not a proposed character design.
	draw_arc(center, unit * 1.18, 0, TAU, 72, Color(accent, 0.10), 1.0, true)
	draw_arc(center, unit * 1.43, -PI * 0.82, PI * 0.82, 72, Color(accent, 0.06), 1.0, true)
	draw_ellipse_placeholder(center + Vector2(0, unit * 1.25), unit)
	if not _placeholder:
		return
	var ink := Color(accent, 0.26)
	draw_circle(center - Vector2(0, unit * 0.58), unit * 0.22, Color(accent, 0.06))
	draw_arc(center - Vector2(0, unit * 0.58), unit * 0.22, 0, TAU, 40, ink, 2, true)
	draw_line(center - Vector2(0, unit * 0.28), center + Vector2(0, unit * 0.37), ink, 2, true)
	for side in [-1, 1]:
		draw_line(center - Vector2(0, unit * 0.12), center + Vector2(side * unit * 0.40, unit * 0.22), ink, 2, true)
		draw_line(center + Vector2(0, unit * 0.37), center + Vector2(side * unit * 0.26, unit * 0.94), ink, 2, true)


func draw_ellipse_placeholder(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(65):
		var angle := TAU * i / 64.0
		points.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.16))
	draw_polyline(points, Color(accent, 0.25), 1.2, true)
