extends RefCounted
## Small voxel-shaped dressing baked into CPU ArrayMeshes, never MultiMeshes.
## add_box positions are centres. Prop positions are bottom-centre anchors.
## All rotation_y arguments are radians; an unrotated sign faces local -Z.
## Call finish() once a district's dressing has been added, then discard builder.
## The caller assigns scene owners recursively before packing a baked scene.

const Mesher = preload("res://scripts/voxel/mesher.gd")
const CHUNK_SIZE := 32.0
const GRID := 0.125
const DRAW_DISTANCE := 90.0
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const CLOTH_COLORS := [31, 21, 26, 25, 29]

class DetailChunk extends RefCounted:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

var _chunks: Dictionary = {}
var _colors: Dictionary = {}
var _box_count := 0

func _init() -> void:
	for id: int in Mesher.PALETTE:
		_colors[id] = Color(Mesher.PALETTE[id])

func add_box(pos: Vector3, size: Vector3, material_id: int, rotation_y: float = 0.0) -> void:
	if not pos.is_finite() or not size.is_finite() or not is_finite(rotation_y):
		return
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	var coordinate := Vector3i(floori(pos.x / CHUNK_SIZE), floori(pos.y / CHUNK_SIZE), floori(pos.z / CHUNK_SIZE))
	if not _chunks.has(coordinate):
		_chunks[coordinate] = DetailChunk.new()
	var chunk: DetailChunk = _chunks[coordinate]
	var centre := pos - Vector3(coordinate) * CHUNK_SIZE
	var basis := Basis(Vector3.UP, rotation_y)
	var color: Color = _colors.get(material_id, Color.MAGENTA)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for side in range(2):
			var sign_value := float(side * 2 - 1)
			var normal: Vector3 = basis * AXES[axis] * sign_value
			var offset := chunk.vertices.size()
			for corner in range(4):
				var point := Vector3.ZERO
				point[axis] = size[axis] * 0.5 * sign_value
				point[u] = size[u] * (0.5 if corner == 1 or corner == 2 else -0.5)
				point[v] = size[v] * (0.5 if corner >= 2 else -0.5)
				chunk.vertices.append(centre + basis * point)
				chunk.normals.append(normal)
				chunk.colors.append(color.darkened(0.15) if axis == 1 and side == 0 else color)
			# Clockwise front faces, with explicit outward normals, as in mesher.gd.
			if side == 1:
				chunk.indices.append_array(PackedInt32Array([offset, offset + 3, offset + 2, offset, offset + 2, offset + 1]))
			else:
				chunk.indices.append_array(PackedInt32Array([offset, offset + 1, offset + 2, offset, offset + 2, offset + 3]))
	_box_count += 1

func add_voxel_line(a: Vector3, b: Vector3, thickness: float = GRID, color: int = 10, sag: float = 0.6) -> void:
	if not a.is_finite() or not b.is_finite() or not is_finite(thickness) or not is_finite(sag):
		return
	var width := maxf(GRID, snappedf(thickness, GRID))
	# The path is quantised to connected cubes. Repeated cells are emitted once.
	var steps := clampi(ceili((a.distance_to(b) + absf(sag) * 2.0) / (width * 0.45)), 1, 4096)
	var visited: Dictionary = {}
	for i in range(steps + 1):
		var p := _rope_point(a, b, float(i) / float(steps), sag)
		var cell := Vector3i(roundi(p.x / width), roundi(p.y / width), roundi(p.z / width))
		if visited.has(cell):
			continue
		visited[cell] = true
		add_box(Vector3(cell) * width, Vector3.ONE * width, color)

func clothesline(a: Vector3, b: Vector3, seed_value: int) -> void:
	if not a.is_finite() or not b.is_finite():
		return
	add_voxel_line(a, b)
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	# Three recognisable garments need a 2.75m horizontal span. Short spans
	# remain useful as bare ropes without squeezing overlapping clothes into them.
	if span < 2.75:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := rng.randi_range(3, clampi(floori(span / 0.875), 3, 5))
	var rotation_y := _line_rotation(a, b)
	for i in range(count):
		var t := float(i + 1) / float(count + 1)
		var anchor := _rope_point(a, b, t, 0.6) - Vector3.UP * GRID
		var color: int = CLOTH_COLORS[rng.randi_range(0, CLOTH_COLORS.size() - 1)]
		var kind := posmod(i + seed_value, 3)
		_garment(anchor, rotation_y, color, kind)
		for x in [-0.1875, 0.1875]:
			_local_box(anchor, Vector3(x, GRID, 0), Vector3(GRID, GRID * 2.0, GRID), 9, rotation_y)

func bunting(a: Vector3, b: Vector3, seed_value: int = 0, sag: float = 0.35) -> void:
	if not a.is_finite() or not b.is_finite() or not is_finite(sag):
		return
	add_voxel_line(a, b, GRID, 10, sag)
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	if span < 0.875:
		return
	var count := clampi(floori(span / 0.875), 1, 24)
	var rotation_y := _line_rotation(a, b)
	for i in range(count):
		var anchor := _rope_point(a, b, float(i + 1) / float(count + 1), sag)
		var color: int = CLOTH_COLORS[posmod(i + seed_value, CLOTH_COLORS.size())]
		# Three narrowing block courses make a pennant rather than a flat quad.
		_local_box(anchor, Vector3(0, -0.125, 0), Vector3(0.625, 0.25, GRID), color, rotation_y)
		_local_box(anchor, Vector3(0, -0.375, 0), Vector3(0.375, 0.25, GRID), color, rotation_y)
		_local_box(anchor, Vector3(0, -0.5625, 0), Vector3(GRID, GRID, GRID), color, rotation_y)

func lantern(pos: Vector3, rotation_y: float = 0.0) -> void:
	# A warm opaque core and open iron cage: no light, glass or alpha material.
	_local_box(pos, Vector3(0, 0.375, 0), Vector3(0.25, 0.375, 0.25), 28, rotation_y)
	_local_box(pos, Vector3(0, 0.125, 0), Vector3(0.375, GRID, 0.375), 22, rotation_y)
	_local_box(pos, Vector3(0, 0.625, 0), Vector3(0.5, GRID, 0.5), 22, rotation_y)
	_local_box(pos, Vector3(0, 0.75, 0), Vector3(0.25, GRID, 0.25), 22, rotation_y)
	for x in [-0.1875, 0.1875]:
		for z in [-0.1875, 0.1875]:
			_local_box(pos, Vector3(x, 0.375, z), Vector3(GRID, 0.375, GRID), 22, rotation_y)
	_local_box(pos, Vector3(0, 0.875, 0), Vector3(GRID, 0.25, GRID), 22, rotation_y)
	_local_box(pos, Vector3(0, 1.0, 0.25), Vector3(GRID, GRID, 0.625), 22, rotation_y)
	_local_box(pos, Vector3(0, 0.75, 0.5), Vector3(GRID, 0.625, GRID), 22, rotation_y)

func barrel(pos: Vector3, rotation_y: float = 0.0) -> void:
	# Stepped shoulders and intersecting narrow slabs give a blocky round body.
	for layer in range(8):
		var width := 0.625 if layer == 0 or layer == 7 else (0.75 if layer == 1 or layer == 6 else 0.875)
		var y := float(layer) * GRID + GRID * 0.5
		_local_box(pos, Vector3(0, y, 0), Vector3(width, GRID, width - GRID * 2.0), 9, rotation_y)
		_local_box(pos, Vector3(0, y, 0), Vector3(width - GRID * 2.0, GRID, width), 9, rotation_y)
	for y in [0.25, 0.75]:
		for side in [-1.0, 1.0]:
			_local_box(pos, Vector3(0, y, side * 0.375), Vector3(0.625, GRID, GRID), 22, rotation_y)
			_local_box(pos, Vector3(side * 0.375, y, 0), Vector3(GRID, GRID, 0.625), 22, rotation_y)
	for x in [-0.1875, 0.0625, 0.3125]:
		_local_box(pos, Vector3(x, 1.0, 0), Vector3(GRID, GRID, 0.625), 19, rotation_y)
	_local_box(pos, Vector3(0, 1.0625, 0), Vector3(0.625, GRID, GRID), 10, rotation_y)

func crate(pos: Vector3, rotation_y: float = 0.0) -> void:
	for y in [0.0625, 0.8125]:
		_local_box(pos, Vector3(0, y, 0), Vector3(0.875, GRID, 0.875), 9, rotation_y)
	for side in [-1.0, 1.0]:
		_local_box(pos, Vector3(side * 0.375, 0.4375, 0), Vector3(GRID, 0.625, 0.875), 19, rotation_y)
		_local_box(pos, Vector3(0, 0.4375, side * 0.375), Vector3(0.625, 0.625, GRID), 9, rotation_y)
		for x in [-0.375, 0.375]:
			_local_box(pos, Vector3(x, 0.4375, side * 0.4375), Vector3(GRID, 0.875, GRID), 10, rotation_y)
		var basis := Basis(Vector3.UP, rotation_y)
		add_voxel_line(pos + basis * Vector3(-0.3125, 0.125, side * 0.5), pos + basis * Vector3(0.3125, 0.75, side * 0.5), GRID, 10, 0.0)

func logpile(pos: Vector3, rotation_y: float = 0.0) -> void:
	for row in range(3):
		for column in range(3 - row):
			var x := (float(column) - float(2 - row) * 0.5) * 0.375
			var y := 0.125 + float(row) * 0.25
			_local_box(pos, Vector3(x, y, 0), Vector3(0.25, 0.25, 1.5), 10, rotation_y)
			for side in [-1.0, 1.0]:
				_local_box(pos, Vector3(x, y, side * 0.75), Vector3(0.25, 0.25, GRID), 19, rotation_y)
				_local_box(pos, Vector3(x, y, side * 0.825), Vector3(GRID, GRID, GRID), 11, rotation_y)

func sign(pos: Vector3, symbol: String = "mug", rotation_y: float = 0.0) -> void:
	_local_box(pos, Vector3(0, 0.5, 0), Vector3(1.125, 0.75, GRID), 25, rotation_y)
	for y in [0.125, 0.875]:
		_local_box(pos, Vector3(0, y, 0), Vector3(1.25, GRID, 0.25), 10, rotation_y)
	for x in [-0.5625, 0.5625]:
		_local_box(pos, Vector3(x, 0.5, 0), Vector3(GRID, 0.625, 0.25), 10, rotation_y)
	for x in [-0.375, 0.375]:
		_local_box(pos, Vector3(x, 1.0625, 0), Vector3(GRID, 0.25, GRID), 22, rotation_y)
	_local_box(pos, Vector3(0, 1.25, 0.1875), Vector3(1.0, GRID, 0.5), 22, rotation_y)
	# Icons are shallow solid silhouettes on both sides of the signboard.
	for side in [-1.0, 1.0]:
		_sign_icon(pos, symbol, rotation_y, side * 0.125)

func bucket(pos: Vector3, rotation_y: float = 0.0) -> void:
	_local_box(pos, Vector3(0, 0.0625, 0), Vector3(0.375, GRID, 0.375), 10, rotation_y)
	for side in [-1.0, 1.0]:
		_local_box(pos, Vector3(side * 0.1875, 0.25, 0), Vector3(GRID, 0.375, 0.5), 19, rotation_y)
		_local_box(pos, Vector3(0, 0.25, side * 0.1875), Vector3(0.25, 0.375, GRID), 9, rotation_y)
		_local_box(pos, Vector3(side * 0.25, 0.5625, 0), Vector3(GRID, 0.375, GRID), 22, rotation_y)
	_local_box(pos, Vector3(0, 0.75, 0), Vector3(0.625, GRID, GRID), 22, rotation_y)

func bench(pos: Vector3, rotation_y: float = 0.0) -> void:
	_local_box(pos, Vector3(0, 0.5, 0), Vector3(1.75, GRID, 0.5), 9, rotation_y)
	_local_box(pos, Vector3(0, 0.875, 0.25), Vector3(1.75, 0.25, GRID), 19, rotation_y)
	for x in [-0.625, 0.625]:
		_local_box(pos, Vector3(x, 0.25, 0), Vector3(0.25, 0.5, 0.5), 10, rotation_y)
		_local_box(pos, Vector3(x, 0.75, 0.25), Vector3(GRID, 0.5, GRID), 10, rotation_y)

func finish() -> Node3D:
	var root := Node3D.new()
	root.name = "TownMicroDetails"
	var material := StandardMaterial3D.new()
	material.resource_name = "VoxelMicroDetailPalette"
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	var coordinates: Array = _chunks.keys()
	coordinates.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z: return a.z < b.z
		if a.x != b.x: return a.x < b.x
		return a.y < b.y)
	for coordinate: Vector3i in coordinates:
		var chunk: DetailChunk = _chunks[coordinate]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = chunk.vertices
		arrays[Mesh.ARRAY_NORMAL] = chunk.normals
		arrays[Mesh.ARRAY_COLOR] = chunk.colors
		arrays[Mesh.ARRAY_INDEX] = chunk.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var visual := MeshInstance3D.new()
		visual.name = "DetailChunk_%d_%d_%d" % [coordinate.x, coordinate.y, coordinate.z]
		visual.position = Vector3(coordinate) * CHUNK_SIZE
		visual.mesh = mesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_begin = 0.0
		visual.visibility_range_end = DRAW_DISTANCE
		root.add_child(visual)
	root.set_meta("detail_stats", {
		"boxes": _box_count, "chunks": _chunks.size(), "triangles": _box_count * 12,
		"material_count": 1 if _box_count > 0 else 0, "grid_m": GRID,
		"chunk_size_m": CHUNK_SIZE, "visibility_range_m": DRAW_DISTANCE,
		"cpu_array_mesh": true, "collisions": false, "cast_shadow": false,
	})
	return root

func _rope_point(a: Vector3, b: Vector3, t: float, sag: float) -> Vector3:
	return a.lerp(b, t) - Vector3.UP * (4.0 * sag * t * (1.0 - t))

func _line_rotation(a: Vector3, b: Vector3) -> float:
	var direction := b - a
	return atan2(-direction.z, direction.x)

func _local_box(origin: Vector3, offset: Vector3, size: Vector3, color: int, rotation_y: float) -> void:
	add_box(origin + Basis(Vector3.UP, rotation_y) * offset, size, color, rotation_y)

func _garment(anchor: Vector3, rotation_y: float, color: int, kind: int) -> void:
	if kind == 0:
		# T-shirt: neck opening, stepped shoulders, distinct sleeves and a hem.
		_local_box(anchor, Vector3(0, -0.4375, 0), Vector3(0.5, 0.625, GRID), color, rotation_y)
		for side in [-1.0, 1.0]:
			_local_box(anchor, Vector3(side * 0.3125, -0.25, 0), Vector3(0.25, 0.25, GRID), color, rotation_y)
			_local_box(anchor, Vector3(side * 0.1875, -0.0625, 0), Vector3(GRID, GRID, GRID), color, rotation_y)
		_local_box(anchor, Vector3(0, -0.75, GRID * 0.5), Vector3(0.5, GRID, GRID), color, rotation_y)
	elif kind == 1:
		# Trousers: a continuous waistband, two thighs, and a visible leg gap.
		_local_box(anchor, Vector3(0, -0.125, 0), Vector3(0.625, 0.25, GRID), color, rotation_y)
		for side in [-1.0, 1.0]:
			_local_box(anchor, Vector3(side * 0.1875, -0.5625, 0), Vector3(0.25, 0.625, GRID), color, rotation_y)
			_local_box(anchor, Vector3(side * 0.1875, -0.875, GRID * 0.5), Vector3(0.25, GRID, GRID), color, rotation_y)
	else:
		# Folded cloth: raised top fold and unequal hanging corners.
		_local_box(anchor, Vector3(0, -0.4375, 0), Vector3(0.625, 0.875, GRID), color, rotation_y)
		_local_box(anchor, Vector3(0, -0.0625, GRID), Vector3(0.625, GRID, GRID), 31, rotation_y)
		_local_box(anchor, Vector3(-0.125, -0.9375, 0), Vector3(0.375, GRID, GRID), color, rotation_y)

func _sign_icon(pos: Vector3, symbol: String, rotation_y: float, z: float) -> void:
	match symbol:
		"sword":
			_local_box(pos, Vector3(0, 0.625, z), Vector3(GRID, 0.375, GRID), 14, rotation_y)
			_local_box(pos, Vector3(0, 0.375, z), Vector3(0.5, GRID, GRID), 23, rotation_y)
			_local_box(pos, Vector3(0, 0.25, z), Vector3(GRID, 0.25, GRID), 22, rotation_y)
		"anvil":
			_local_box(pos, Vector3(0, 0.3125, z), Vector3(0.5, GRID, GRID), 22, rotation_y)
			_local_box(pos, Vector3(0, 0.5, z), Vector3(0.25, 0.25, GRID), 22, rotation_y)
			_local_box(pos, Vector3(0, 0.6875, z), Vector3(0.625, GRID, GRID), 22, rotation_y)
			_local_box(pos, Vector3(0.375, 0.6875, z), Vector3(0.25, GRID, GRID), 22, rotation_y)
		"book":
			_local_box(pos, Vector3(0, 0.5, z), Vector3(0.5, 0.5, GRID), 29, rotation_y)
			_local_box(pos, Vector3(0.0625, 0.5, z * 1.75), Vector3(0.125, 0.375, GRID), 31, rotation_y)
		_:
			_local_box(pos, Vector3(-0.0625, 0.4375, z), Vector3(0.375, 0.375, GRID), 31, rotation_y)
			_local_box(pos, Vector3(0.25, 0.4375, z), Vector3(GRID, 0.375, GRID), 23, rotation_y)
			for y in [0.3125, 0.5625]:
				_local_box(pos, Vector3(0.125, y, z), Vector3(0.25, GRID, GRID), 23, rotation_y)
			_local_box(pos, Vector3(-0.0625, 0.6875, z), Vector3(0.5, GRID, GRID), 20, rotation_y)
