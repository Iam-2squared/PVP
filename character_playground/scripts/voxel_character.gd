extends Node3D
## Lightweight block figures. No kingdom/map imports or external character assets.
## Feet are at y=0, forward is -Z, and the full figure is approximately 1.8 m.

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _figure_material: StandardMaterial3D

var job_id := "warrior"
var female := false
var right_hand: Node3D
var left_hand: Node3D
var _body: Node3D
var _head: Node3D
var _right_arm: Node3D
var _left_arm: Node3D
var _right_leg: Node3D
var _left_leg: Node3D
var _cape: Node3D
var _clock := 0.0
var _attack_left := 0.0
var _strong := false
var _move_blend := 0.0

const COLORS := {
	"warrior": {"cloth": "6b4140", "dark": "453333", "trim": "c6ac70", "metal": "929da3"},
	"mage": {"cloth": "3e465e", "dark": "222733", "trim": "ac8cba", "metal": "b7b0bd"},
	"scout": {"cloth": "52664c", "dark": "344237", "trim": "b7a17a", "metal": "a2b2a9"},
	"archer": {"cloth": "716149", "dark": "414c3b", "trim": "d0b584", "metal": "9eaaa2"},
	"cleric": {"cloth": "d2cbb2", "dark": "657f83", "trim": "c7a458", "metal": "d7d9ce"},
	"artisan": {"cloth": "657a81", "dark": "674b36", "trim": "cea46b", "metal": "949f9e"},
}


func configure(new_job_id: String, is_female: bool) -> void:
	job_id = new_job_id if COLORS.has(new_job_id) else "warrior"
	female = is_female
	if is_inside_tree():
		_build()


func _ready() -> void:
	_build()


func _build() -> void:
	if _body != null:
		remove_child(_body)
		_body.queue_free()
	_cape = null
	_body = Node3D.new()
	_body.name = "BlockFigure"
	add_child(_body)
	var palette: Dictionary = COLORS[job_id]
	var cloth := String(palette["cloth"])
	var dark := String(palette["dark"])
	var trim := String(palette["trim"])
	var metal := String(palette["metal"])
	var skin := "ddb48f" if female else "c99d7a"
	var hair := "50382c" if female else "3e3029"
	if job_id == "mage":
		hair = "343038" if female else "55473d"
	elif job_id == "cleric":
		hair = "ad8a51" if female else "806343"
	var chest_width := 0.32 if female else 0.36
	var hip_width := 0.31 if female else 0.32
	_box(_body, Vector3(0, 0.83, 0), Vector3(hip_width, 0.21, 0.23), dark)
	_box(_body, Vector3(0, 1.13, 0), Vector3(chest_width, 0.43, 0.23), cloth)
	_box(_body, Vector3(0, 0.935, -0.005), Vector3(chest_width + 0.025, 0.07, 0.255), "594331")
	_box(_body, Vector3(0, 0.938, -0.143), Vector3(0.065, 0.07, 0.025), trim)
	_box(_body, Vector3(0, 1.405, 0), Vector3(0.13, 0.12, 0.13), skin)
	_head = _pivot(_body, "Head", Vector3(0, 1.43, 0))
	_box(_head, Vector3(0, 0.15, 0), Vector3(0.30, 0.30, 0.27), skin)
	# The square hair cap, stepped fringe, and back of the head preserve the voxel silhouette.
	_box(_head, Vector3(0, 0.31, 0.015), Vector3(0.325, 0.07, 0.30), hair)
	_box(_head, Vector3(0, 0.16, 0.135), Vector3(0.32, 0.27, 0.05), hair)
	_box(_head, Vector3(-0.12, 0.23, -0.125), Vector3(0.08, 0.13, 0.045), hair)
	_box(_head, Vector3(-0.04, 0.27, -0.13), Vector3(0.08, 0.07, 0.045), hair)
	_box(_head, Vector3(0.065, 0.28, -0.13), Vector3(0.13, 0.05, 0.045), hair)
	for x in [-0.07, 0.07]:
		_box(_head, Vector3(x, 0.145, -0.14), Vector3(0.035, 0.035, 0.016), "30343b")
	_box(_head, Vector3(0, 0.065, -0.14), Vector3(0.045, 0.016, 0.012), "9f6c55")
	if female:
		_box(_head, Vector3(0.145, 0.16, 0.025), Vector3(0.04, 0.21, 0.27), hair)
		_box(_head, Vector3(-0.145, 0.16, 0.025), Vector3(0.04, 0.21, 0.27), hair)
		_box(_head, Vector3(0.05, 0.24, 0.21), Vector3(0.12, 0.12, 0.14), trim)
		_box(_head, Vector3(0.05, 0.03, 0.24), Vector3(0.12, 0.32, 0.12), hair)
	_right_leg = _leg(0.105, "RightLeg", dark, "463a30")
	_left_leg = _leg(-0.105, "LeftLeg", dark, "463a30")
	_right_arm = _arm(0.255, "RightArm", cloth, skin)
	_left_arm = _arm(-0.255, "LeftArm", cloth, skin)
	right_hand = _pivot(_right_arm, "RightHand", Vector3(0, -0.53, -0.01))
	left_hand = _pivot(_left_arm, "LeftHand", Vector3(0, -0.53, -0.01))
	var weapon := create_weapon(job_id)
	weapon.name = "EquippedWeapon"
	right_hand.add_child(weapon)
	weapon.rotation_degrees = Vector3(-12, 0, -8)
	match job_id:
		"warrior":
			# Worn starter armor: small plates and leather, without a full helmet or large pauldrons.
			_box(_body, Vector3(0, 1.18, -0.132), Vector3(chest_width - 0.025, 0.28, 0.055), metal)
			_box(_body, Vector3(0, 1.18, -0.166), Vector3(0.045, 0.25, 0.02), "b4bcb8")
			for x in [-0.11, 0.11]:
				_box(_body, Vector3(x, 1.30, -0.171), Vector3(0.035, 0.035, 0.015), trim)
			_box(_right_arm, Vector3(0, -0.07, 0), Vector3(0.205, 0.13, 0.25), metal)
			_box(_left_arm, Vector3(0, -0.07, 0), Vector3(0.195, 0.11, 0.24), metal)
			_box(_right_leg, Vector3(0, -0.31, -0.085), Vector3(0.13, 0.14, 0.035), metal)
			_box(_left_leg, Vector3(0, -0.31, -0.085), Vector3(0.13, 0.14, 0.035), metal)
		"mage":
			_make_cape("22242b", 0.37, 0.76)
			_box(_body, Vector3(0, 0.79, 0), Vector3(0.35, 0.25, 0.26), cloth)
			_box(_body, Vector3(0, 1.16, -0.13), Vector3(0.045, 0.39, 0.022), trim)
			_box(_body, Vector3(0, 1.31, -0.15), Vector3(0.08, 0.08, 0.035), "a398bd")
			_box(_head, Vector3(0, 0.347, 0.01), Vector3(0.35, 0.035, 0.32), dark)
		"scout":
			_make_cape(dark, 0.32, 0.37)
			_box(_body, Vector3(0, 1.33, -0.07), Vector3(0.38, 0.12, 0.24), dark)
			_box(_body, Vector3(-0.10, 1.12, -0.135), Vector3(0.055, 0.35, 0.035), "796046")
			_box(_body, Vector3(0.21, 0.95, -0.02), Vector3(0.11, 0.16, 0.14), "796046")
			_box(_left_arm, Vector3(0, -0.36, 0), Vector3(0.15, 0.15, 0.18), dark)
		"archer":
			_make_cape(dark, 0.35, 0.42)
			_box(_body, Vector3(0.10, 1.13, -0.14), Vector3(0.055, 0.36, 0.035), dark)
			_box(_left_arm, Vector3(0, -0.35, 0), Vector3(0.155, 0.19, 0.18), "846246")
			_box(_body, Vector3(-0.17, 1.14, 0.22), Vector3(0.12, 0.47, 0.12), "67503b")
			for i in range(3):
				_box(_body, Vector3(-0.20 + i * 0.035, 1.45, 0.22), Vector3(0.014, 0.24, 0.014), "d0ba8b")
				_box(_body, Vector3(-0.20 + i * 0.035, 1.54, 0.22), Vector3(0.035, 0.06, 0.025), "d1d6c6")
		"cleric":
			_box(_body, Vector3(0, 0.73, 0), Vector3(0.35, 0.35, 0.26), cloth)
			for x in [-0.105, 0.105]:
				_box(_body, Vector3(x, 1.07, -0.145), Vector3(0.065, 0.55, 0.03), dark)
				_box(_body, Vector3(x, 0.81, -0.165), Vector3(0.07, 0.04, 0.018), trim)
			_box(_body, Vector3(0, 1.21, -0.14), Vector3(0.03, 0.16, 0.022), trim)
			_box(_body, Vector3(0, 1.23, -0.14), Vector3(0.11, 0.03, 0.022), trim)
		"artisan":
			_box(_body, Vector3(0, 1.10, -0.15), Vector3(0.28, 0.34, 0.045), dark)
			_box(_body, Vector3(0, 0.79, -0.13), Vector3(0.30, 0.30, 0.045), dark)
			for x in [-0.105, 0.105]:
				_box(_body, Vector3(x, 1.34, -0.125), Vector3(0.045, 0.18, 0.04), trim)
			_box(_body, Vector3(0, 1.03, -0.18), Vector3(0.14, 0.11, 0.03), "896748")
			_box(_head, Vector3(0, 0.265, -0.16), Vector3(0.31, 0.045, 0.035), "695039")
			for x in [-0.08, 0.08]:
				_box(_head, Vector3(x, 0.27, -0.185), Vector3(0.095, 0.085, 0.045), metal)
				_box(_head, Vector3(x, 0.27, -0.212), Vector3(0.065, 0.055, 0.012), "6e9699")
			_box(_body, Vector3(0.23, 0.94, 0), Vector3(0.12, 0.16, 0.16), dark)
			_box(_body, Vector3(-0.21, 0.94, -0.06), Vector3(0.035, 0.22, 0.035), metal)
	# Keep articulated pivots, but draw their static cubes as one colored mesh.
	_batch_blocks(_body)


func _leg(x: float, label: String, trouser: String, boot: String) -> Node3D:
	var leg := _pivot(_body, label, Vector3(x, 0.74, 0))
	_box(leg, Vector3(0, -0.27, 0), Vector3(0.13, 0.53, 0.15), trouser)
	_box(leg, Vector3(0, -0.56, -0.025), Vector3(0.15, 0.24, 0.21), boot)
	_box(leg, Vector3(0, -0.70, -0.055), Vector3(0.16, 0.08, 0.27), boot)
	return leg


func _arm(x: float, label: String, sleeve: String, skin: String) -> Node3D:
	var arm := _pivot(_body, label, Vector3(x, 1.35, 0))
	_box(arm, Vector3(0, -0.14, 0), Vector3(0.14, 0.30, 0.18), sleeve)
	_box(arm, Vector3(0, -0.385, 0), Vector3(0.11, 0.23, 0.13), skin)
	_box(arm, Vector3(0, -0.52, -0.01), Vector3(0.13, 0.14, 0.14), skin)
	return arm


func _make_cape(color: String, width: float, length: float) -> void:
	_cape = _pivot(_body, "ThinCape", Vector3(0, 1.36, 0.145))
	_box(_cape, Vector3(0, -length * 0.44, 0.025), Vector3(width, length * 0.88, 0.04), color)
	_box(_cape, Vector3(0, -length * 0.94, 0.045), Vector3(width + 0.035, length * 0.12, 0.04), color)
	_cape.rotation.x = -0.06


func animate(movement: float, delta: float, attacking: bool = false) -> void:
	if _body == null:
		return
	_clock += delta
	_move_blend = move_toward(_move_blend, clampf(movement, 0, 1), delta * 6)
	var stride := sin(_clock * 9.5) * _move_blend
	_right_leg.rotation.x = stride * 0.55
	_left_leg.rotation.x = -stride * 0.55
	_body.position.y = absf(sin(_clock * 9.5)) * _move_blend * 0.025
	_left_arm.rotation.x = stride * 0.40
	_right_arm.rotation.x = -stride * 0.40
	if _attack_left > 0:
		_attack_left = maxf(0, _attack_left - delta)
		var phase := 1.0 - _attack_left / 0.36
		var swing := sin(phase * PI)
		_right_arm.rotation.x = -1.4 * swing
		_right_arm.rotation.z = -0.3 * swing
		if job_id == "archer":
			_left_arm.rotation.x = -1.25 * swing
			_left_arm.rotation.y = -0.35 * swing
	else:
		_right_arm.rotation.z = lerpf(_right_arm.rotation.z, 0, minf(1, delta * 12))
		_left_arm.rotation.y = lerpf(_left_arm.rotation.y, 0, minf(1, delta * 12))
		if attacking:
			play_attack()
	if _cape != null:
		_cape.rotation.x = -0.06 - _move_blend * 0.12 + sin(_clock * 3) * 0.025
	_head.rotation.y = sin(_clock * 0.9) * 0.018 * (1 - _move_blend)


func play_attack(strong: bool = false) -> void:
	_attack_left = 0.36
	_strong = strong


func set_first_person(hidden: bool) -> void:
	if _body != null:
		_body.visible = not hidden


static func create_weapon(weapon_job_id: String) -> Node3D:
	var weapon := Node3D.new()
	weapon.name = "VoxelWeapon_" + weapon_job_id
	match weapon_job_id:
		"warrior", "scout":
			var blade_length := 0.57 if weapon_job_id == "warrior" else 0.29
			_box(weapon, Vector3(0, -0.015, 0), Vector3(0.055, 0.19, 0.055), "574433")
			_box(weapon, Vector3(0, 0.085, 0), Vector3(0.22 if weapon_job_id == "warrior" else 0.15, 0.045, 0.075), "b5a16d")
			_box(weapon, Vector3(0, 0.115 + blade_length * 0.5, 0), Vector3(0.075, blade_length, 0.035), "b5c4c8")
			_box(weapon, Vector3(-0.026, 0.115 + blade_length * 0.5, -0.021), Vector3(0.019, blade_length, 0.012), "dde4df")
			_box(weapon, Vector3(0, 0.125 + blade_length, 0), Vector3(0.04, 0.04, 0.035), "d3dcd8")
			_box(weapon, Vector3(0, -0.12, 0), Vector3(0.08, 0.04, 0.07), "b5a16d")
		"mage", "cleric":
			_box(weapon, Vector3(0, 0.05, 0), Vector3(0.045, 1.24, 0.045), "67513c")
			for y in [-0.07, 0.01, 0.09]:
				_box(weapon, Vector3(0, y, 0), Vector3(0.055, 0.035, 0.055), "a89368")
			if weapon_job_id == "mage":
				_box(weapon, Vector3(0, 0.70, 0), Vector3(0.17, 0.08, 0.12), "a99873")
				_box(weapon, Vector3(-0.075, 0.78, 0), Vector3(0.045, 0.15, 0.07), "a99873")
				_box(weapon, Vector3(0.075, 0.78, 0), Vector3(0.045, 0.15, 0.07), "a99873")
				_box(weapon, Vector3(0, 0.80, 0), Vector3(0.095, 0.15, 0.095), "c29d7a", true)
			else:
				_box(weapon, Vector3(0, 0.78, 0), Vector3(0.07, 0.29, 0.07), "d5bd81")
				_box(weapon, Vector3(0, 0.80, 0), Vector3(0.24, 0.07, 0.07), "d5bd81")
				_box(weapon, Vector3(0, 0.79, -0.05), Vector3(0.075, 0.075, 0.035), "bfd6d2", true)
		"archer":
			# A seven-step square-limbed bow with a fine cuboid string.
			_box(weapon, Vector3(0, 0, 0), Vector3(0.055, 0.25, 0.055), "68513b")
			for sign_y in [-1, 1]:
				_box(weapon, Vector3(0, sign_y * 0.21, -0.025), Vector3(0.05, 0.20, 0.055), "98734c")
				_box(weapon, Vector3(0, sign_y * 0.36, -0.075), Vector3(0.045, 0.13, 0.055), "98734c")
				_box(weapon, Vector3(0, sign_y * 0.455, -0.13), Vector3(0.04, 0.09, 0.06), "b29b6a")
			_box(weapon, Vector3(0, 0, -0.15), Vector3(0.009, 0.93, 0.009), "ded3b3")
			_box(weapon, Vector3(0, 0, -0.40), Vector3(0.014, 0.014, 0.61), "b9a87c")
			_box(weapon, Vector3(0, 0, -0.72), Vector3(0.045, 0.025, 0.065), "c9d1cc")
		"artisan":
			_box(weapon, Vector3(0, 0.12, 0), Vector3(0.055, 0.57, 0.055), "7e5a3a")
			_box(weapon, Vector3(0, 0.40, 0), Vector3(0.31, 0.17, 0.18), "909b9b")
			_box(weapon, Vector3(-0.17, 0.40, 0), Vector3(0.07, 0.19, 0.20), "bbc3bd")
			_box(weapon, Vector3(0, -0.015, 0), Vector3(0.065, 0.16, 0.065), "574231")
		_:
			# Empty weapon ID intentionally leaves only the player's fist.
			pass
	_batch_blocks(weapon)
	return weapon


static func _batch_blocks(part: Node3D) -> void:
	var boxes: Array[MeshInstance3D] = []
	for child in part.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			# Crystal emission is kept as a separate tiny mesh.
			if not child.material_override.emission_enabled:
				boxes.append(child)
		elif child is Node3D:
			_batch_blocks(child)
	if boxes.is_empty():
		return
	if _figure_material == null:
		_figure_material = StandardMaterial3D.new()
		_figure_material.vertex_color_use_as_albedo = true
		_figure_material.vertex_color_is_srgb = true
		_figure_material.roughness = 0.87
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_figure_material)
	for block in boxes:
		var arrays := block.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var color: Color = block.material_override.albedo_color
		for index in indices:
			surface.set_color(color)
			surface.set_normal((block.basis * normals[index]).normalized())
			surface.add_vertex(block.transform * vertices[index])
		part.remove_child(block)
		block.free()
	surface.index()
	var batch := MeshInstance3D.new()
	batch.name = "BatchedVoxelBlocks"
	batch.mesh = surface.commit()
	part.add_child(batch)


static func _pivot(parent: Node3D, label: String, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label
	pivot.position = pos
	parent.add_child(pivot)
	return pivot


static func _box(parent: Node3D, pos: Vector3, dimensions: Vector3, hex: String, glow: bool = false) -> MeshInstance3D:
	var key := str(dimensions)
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = dimensions
		_meshes[key] = mesh
	var material_key := hex + ("_glow" if glow else "")
	if not _materials.has(material_key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(hex)
		material.roughness = 0.87
		if glow:
			material.emission_enabled = true
			material.emission = Color(hex)
			material.emission_energy_multiplier = 0.35
		_materials[material_key] = material
	var block := MeshInstance3D.new()
	block.mesh = _meshes[key]
	block.material_override = _materials[material_key]
	block.position = pos
	parent.add_child(block)
	return block
