extends StaticBody3D
## A local training mannequin. No PvP, NPC or world-generation dependency.

signal damaged(amount: float, remaining: float)

@export var target_name: String = "練習標的"
@export var max_health: float = 100.0
var health: float = 100.0
var _visual: Node3D
var _label: Label3D
var _hit_material: StandardMaterial3D
var _flash_remaining: float = 0.0
var _respawn_remaining: float = 0.0
var _damage_label: Label3D


func _ready() -> void:
	add_to_group("practice_targets")
	collision_layer = 2
	collision_mask = 0
	health = max_health
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.72, 1.85, 0.45)
	collider.shape = shape
	collider.position.y = 0.925
	add_child(collider)
	_visual = Node3D.new()
	add_child(_visual)
	_hit_material = StandardMaterial3D.new()
	_hit_material.albedo_color = Color("b59168")
	_hit_material.roughness = 1.0
	_box(Vector3(0, 1.54, 0), Vector3(0.36, 0.36, 0.36), _hit_material)
	_box(Vector3(0, 1.03, 0), Vector3(0.46, 0.56, 0.28), _hit_material)
	_box(Vector3(-0.35, 1.1, 0), Vector3(0.18, 0.52, 0.20), _hit_material)
	_box(Vector3(0.35, 1.1, 0), Vector3(0.18, 0.52, 0.20), _hit_material)
	_box(Vector3(-0.14, 0.40, 0), Vector3(0.18, 0.70, 0.20), _hit_material)
	_box(Vector3(0.14, 0.40, 0), Vector3(0.18, 0.70, 0.20), _hit_material)
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color("534f46")
	_box(Vector3(0, 1.0, -0.152), Vector3(0.48, 0.10, 0.025), strap)
	_box(Vector3(0, 1.05, -0.17), Vector3(0.12, 0.28, 0.025), strap)
	_label = _make_label(2.12, 28)
	_damage_label = _make_label(2.55, 42)
	_damage_label.modulate = Color(1, 0.86, 0.58, 0)
	_update_label()


func take_damage(amount: float) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_flash_remaining = 0.15
	_hit_material.albedo_color = Color("efac93")
	_damage_label.text = "−%s" % ("%.1f" % amount).trim_suffix(".0")
	_damage_label.position.y = 2.4
	_damage_label.modulate.a = 1.0
	_update_label()
	damaged.emit(amount, health)
	if health <= 0.0:
		collision_layer = 0
		_respawn_remaining = 3.0
		_visual.rotation.z = 0.18
		_label.text = "%s · 復帰中" % target_name


func heal(amount: float) -> void:
	if health <= 0.0:
		return
	health = minf(max_health, health + amount)
	_update_label()


func _process(delta: float) -> void:
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash_remaining <= 0.0:
			_hit_material.albedo_color = Color("b59168")
	if is_instance_valid(_damage_label) and _damage_label.modulate.a > 0.0:
		_damage_label.modulate.a = maxf(0.0, _damage_label.modulate.a - delta * 1.15)
		_damage_label.position.y += delta * 0.4
	if _respawn_remaining > 0.0:
		_respawn_remaining -= delta
		if _respawn_remaining <= 0.0:
			health = max_health
			collision_layer = 2
			_visual.rotation = Vector3.ZERO
			_update_label()


func _update_label() -> void:
	if is_instance_valid(_label):
		_label.text = "%s\n%d / %d HP" % [target_name, int(health), int(max_health)]


func _box(pos: Vector3, dimensions: Vector3, material: Material) -> void:
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	piece.mesh = mesh
	piece.material_override = material
	piece.position = pos
	_visual.add_child(piece)


func _make_label(height: float, font_size_value: int) -> Label3D:
	var label := Label3D.new()
	label.position.y = height
	label.font_size = font_size_value
	label.pixel_size = 0.0035
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("d6dfdb")
	label.outline_size = 6
	label.no_depth_test = false
	if ResourceLoader.exists("res://assets/ui.otf"):
		label.font = load("res://assets/ui.otf")
	add_child(label)
	return label
