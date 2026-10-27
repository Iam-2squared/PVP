extends RefCounted
## Static voxel landscape: metre-wide columns on a shared 0.5 m grid.
## Only exposed surfaces are generated. Equal-height/equal-colour tops and
## consecutive cliff faces are merged before the scene is baked.

const EXTENT := 320
const WIDTH := EXTENT * 2
const CELL := 1.0
const STEP := 0.5
const CHUNK := 64
const SEA := 0.0
const RELIEF_SAMPLE := 2.0

const GRASS := 0
const GRASS_LIGHT := 1
const GRASS_DARK := 2
const SAND := 3
const SAND_LIGHT := 4
const ROCK := 5
const ROCK_LIGHT := 6
const EARTH := 7
const GRAVEL := 8
const SAND_ROCK := 9

const COLORS := [
	Color("71934d"), Color("7d9e55"), Color("648747"),
	Color("d3b477"), Color("dfc48a"), Color("777c78"),
	Color("92958a"), Color("96764f"), Color("aa9978"), Color("ad8a60")
]
const WATER_COLORS := [Color("66bdb7"), Color("369da9"), Color("247d94"), Color("24637e")]

var _heights := PackedInt32Array()
var _types := PackedByteArray()
var _material: StandardMaterial3D
var _water_material: StandardMaterial3D
var _root: Node3D
var _land_triangles := 0
var _water_triangles := 0
var _land_chunks := 0
var _max_height := 0.0
var _top_triangles := 0
var _side_triangles := 0

var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _solid_faces := PackedVector3Array()


func height_at(x: float, z: float) -> float:
	var ix := floori(x + EXTENT)
	var iz := floori(z + EXTENT)
	if not _heights.is_empty() and ix >= 0 and iz >= 0 and ix < WIDTH and iz < WIDTH:
		return float(_heights[iz * WIDTH + ix]) * STEP
	return _height_steps(x, z) * STEP


func build() -> Node3D:
	var started := Time.get_ticks_msec()
	_root = Node3D.new()
	_root.name = "VoxelLandscape"
	_land_triangles = 0
	_water_triangles = 0
	_land_chunks = 0
	_max_height = 0.0
	_top_triangles = 0
	_side_triangles = 0
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	_water_material = StandardMaterial3D.new()
	_water_material.vertex_color_use_as_albedo = true
	_water_material.vertex_color_is_srgb = true
	_water_material.roughness = 0.48
	_water_material.metallic_specular = 0.2
	_sample_columns()
	for cz in range(0, WIDTH, CHUNK):
		for cx in range(0, WIDTH, CHUNK):
			_build_land_chunk(cx, cz)
	_build_water()
	_add_details()
	var statistics := {
		"land_triangles": _land_triangles,
		"top_triangles": _top_triangles,
		"side_triangles": _side_triangles,
		"water_triangles": _water_triangles,
		"land_chunks": _land_chunks,
		"max_height": _max_height,
		"horizontal_grid": CELL,
		"height_step": STEP,
		"generation_ms": Time.get_ticks_msec() - started,
	}
	_root.set_meta("terrain_stats", statistics)
	print("VOXEL_TERRAIN ", JSON.stringify(statistics))
	return _root


func _sample_columns() -> void:
	_heights.resize(WIDTH * WIDTH)
	_types.resize(WIDTH * WIDTH)
	for iz in range(WIDTH):
		var z := float(iz - EXTENT) + 0.5
		for ix in range(WIDTH):
			var x := float(ix - EXTENT) + 0.5
			var h := _height_steps(x, z)
			var index := iz * WIDTH + ix
			_heights[index] = h
			_types[index] = _top_type(x, z, h * STEP)
			_max_height = maxf(_max_height, h * STEP)


func _coast_distance(x: float, z: float) -> float:
	var east := 191.0 + 12.0 * sin(z * 0.018) + 6.0 * sin(z * 0.043 + 0.8) - x
	var south := 199.0 + 10.0 * sin(x * 0.019 + 1.0) + 6.0 * sin(x * 0.047) - z
	var diagonal := (306.0 + 11.0 * sin((x - z) * 0.025) - x - z) / sqrt(2.0)
	return minf(east, minf(south, diagonal))


func _plateau_distance(x: float, z: float) -> float:
	return maxf(maxf(absf(x), absf(z)) - 136.0, (absf(x) + absf(z) - 192.33) / sqrt(2.0))


func _desert_weight(x: float, z: float) -> float:
	return smoothstep(145.0 + 11.0 * sin(x * 0.012), 220.0 + 11.0 * sin(x * 0.012), -z) * smoothstep(-118.0, -35.0, x)


func _path_distance(x: float, z: float) -> float:
	var distance := 999.0
	if x < -126.0 and x > -285.0:
		distance = minf(distance, absf(z - sin((-x - 128.0) * 0.028) * 5.0))
	if x > 126.0 and x < 182.0:
		distance = minf(distance, absf(z - sin((x - 128.0) * 0.032) * 3.0))
	if z < -126.0 and z > -305.0:
		distance = minf(distance, absf(x - sin((-z - 128.0) * 0.023) * 7.0))
	if z > 126.0 and z < 188.0:
		distance = minf(distance, absf(x + (z - 128.0) * 0.08))
	return distance


func _height_steps(x: float, z: float) -> int:
	var coast := _coast_distance(x, z)
	if coast < 0.0:
		# Sea bed is only used to choose water colours. It is not a collision floor.
		return -maxi(1, mini(24, floori(-coast * 0.35) + 1))
	var plateau := _plateau_distance(x, z)
	if plateau < 0.0 or (absf(x) < 9.0 and z > 125.0 and z < 160.0):
		return 4
	# Broad mountain/dune terraces share a 2 m sampling cadence. Their vertical
	# relief remains on the 0.5 m voxel grid, while coasts and the gate approaches
	# retain 1 m sampling. This removes tiny surface ripples, not landmark shapes.
	if RELIEF_SAMPLE > 1.0 and plateau > 12.0 and coast > 20.0:
		x = floorf(x / RELIEF_SAMPLE) * RELIEF_SAMPLE + RELIEF_SAMPLE * 0.5
		z = floorf(z / RELIEF_SAMPLE) * RELIEF_SAMPLE + RELIEF_SAMPLE * 0.5
		plateau = _plateau_distance(x, z)
	var outside := smoothstep(0.0, 36.0, plateau)
	var shore := smoothstep(0.0, 18.0, coast)
	var west := smoothstep(151.0, 235.0, -x)
	var ridge_x := -252.0 + 21.0 * sin(z * 0.012) + 9.0 * sin(z * 0.033)
	var ridge_width := 86.0 + 12.0 * sin(z * 0.014)
	var ridge_mass := pow(maxf(0.0, 1.0 - absf(x - ridge_x) / ridge_width), 1.15)
	var ridge_peaks := 25.0 + 21.0 * (0.5 + 0.5 * sin(z * 0.023 + 0.7)) + 9.0 * (0.5 + 0.5 * cos(z * 0.049 - x * 0.011))
	var ravine := 1.0 - 0.55 * exp(-pow((z - 38.0 - 9.0 * sin(x * 0.025)) / 14.0, 2.0))
	var mountains := ridge_mass * ridge_peaks * ravine * west
	var foothills := maxf(0.0, sin(x * 0.025 + z * 0.008) * 1.7 + cos(z * 0.023 - x * 0.011) * 1.4) * smoothstep(138.0, 194.0, -x)
	var desert := _desert_weight(x, z)
	var dunes := 1.8 + 1.6 * sin(x * 0.042 + z * 0.014) + 1.0 * sin(z * 0.027 - x * 0.011)
	var sandstone := 8.0 * smoothstep(0.45, 0.79, sin(x * 0.023 + z * 0.009) * cos(z * 0.022))
	var rolling := maxf(0.0, sin(x * 0.017) * cos(z * 0.021) * 1.4)
	var height := (2.0 + (mountains + foothills + rolling + desert * (maxf(0.0, dunes) + sandstone)) * outside) * shore
	# A narrow natural shelf from each gate makes exploration readable and playable.
	if _path_distance(x, z) < 3.5:
		var gentle := 2.0 + outside * (mountains * 0.56 + desert * maxf(0.0, dunes) * 0.45)
		height = lerpf(height, gentle * shore, 0.72)
	return maxi(1, roundi(height / STEP))


func _top_type(x: float, z: float, height: float) -> int:
	var coast := _coast_distance(x, z)
	var desert := _desert_weight(x, z)
	var macro := floori(x / 6.0) * 13 + floori(z / 6.0) * 7
	if coast < 13.0:
		return SAND_LIGHT if macro % 5 == 0 else SAND
	if _path_distance(x, z) < 2.5:
		return GRAVEL
	if height > 23.0:
		return ROCK_LIGHT if (floori(height / 3.0) + floori(x / 9.0)) % 4 == 0 else ROCK
	if desert > 0.6:
		if height > 8.0:
			return SAND_ROCK
		return SAND_LIGHT if macro % 4 == 0 else SAND
	if desert > 0.2:
		return SAND if macro % 4 == 0 else GRASS
	if height > 12.0:
		return ROCK if macro % 5 < 2 else GRASS_DARK
	if macro % 9 == 0:
		return GRASS_LIGHT
	if macro % 11 == 0:
		return GRASS_DARK
	return GRASS


func _h(ix: int, iz: int) -> int:
	if ix < 0 or iz < 0 or ix >= WIDTH or iz >= WIDTH:
		return 0
	return maxi(0, _heights[iz * WIDTH + ix])


func _clear_arrays() -> void:
	_positions = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	_solid_faces = PackedVector3Array()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color, solid: bool = true) -> void:
	var start := _positions.size()
	_positions.append_array(PackedVector3Array([a, b, c, d]))
	for i in range(4):
		_normals.append(normal)
		_colors.append(color)
	_indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
	if solid:
		_solid_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))


func _build_land_chunk(cx: int, cz: int) -> void:
	_clear_arrays()
	var visited := PackedByteArray()
	visited.resize(CHUNK * CHUNK)
	for lz in range(CHUNK):
		for lx in range(CHUNK):
			var local_index := lz * CHUNK + lx
			if visited[local_index] != 0:
				continue
			var ix := cx + lx
			var iz := cz + lz
			var h := _h(ix, iz)
			if h <= 0:
				continue
			var kind := _types[iz * WIDTH + ix]
			var length := 1
			while lx + length < CHUNK and visited[local_index + length] == 0 and _h(ix + length, iz) == h and _types[iz * WIDTH + ix + length] == kind:
				length += 1
			var depth := 1
			var extend := true
			while lz + depth < CHUNK and extend:
				for dx in range(length):
					if visited[(lz + depth) * CHUNK + lx + dx] != 0 or _h(ix + dx, iz + depth) != h or _types[(iz + depth) * WIDTH + ix + dx] != kind:
						extend = false
						break
				if extend:
					depth += 1
			for dz in range(depth):
				for dx in range(length):
					visited[(lz + dz) * CHUNK + lx + dx] = 1
			var x := float(ix - EXTENT)
			var z := float(iz - EXTENT)
			var y := h * STEP
			_quad(Vector3(x,y,z), Vector3(x+length,y,z), Vector3(x+length,y,z+depth), Vector3(x,y,z+depth), Vector3.UP, COLORS[kind])
	# Cliff strips are merged horizontally when their two levels match.
	var top_count := _indices.size() / 3
	_top_triangles += top_count
	for direction in range(4):
		_build_sides(cx, cz, direction)
	_side_triangles += _indices.size() / 3 - top_count
	if _positions.is_empty():
		return
	var mesh := _make_mesh()
	var instance := MeshInstance3D.new()
	instance.name = "Land_%d_%d" % [cx / CHUNK, cz / CHUNK]
	instance.mesh = mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(instance)
	_land_triangles += _indices.size() / 3
	_land_chunks += 1
	if not _solid_faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "Ground_%d_%d" % [cx / CHUNK, cz / CHUNK]
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_solid_faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		_root.add_child(body)


func _build_sides(cx: int, cz: int, direction: int) -> void:
	# Greedy on the full vertical face plane, not only equal-height strips.
	# A tall face can share its overlapping rows with a shorter neighbour.
	for row in range(CHUNK):
		var highs := PackedInt32Array()
		var lows := PackedInt32Array()
		var kinds := PackedInt32Array()
		highs.resize(CHUNK)
		lows.resize(CHUNK)
		kinds.resize(CHUNK)
		var minimum := 10000
		var maximum := 0
		for column in range(CHUNK):
			var ix := cx + (row if direction < 2 else column)
			var iz := cz + (column if direction < 2 else row)
			var nx := ix + (1 if direction == 0 else -1 if direction == 1 else 0)
			var nz := iz + (1 if direction == 2 else -1 if direction == 3 else 0)
			highs[column] = _h(ix, iz)
			lows[column] = _h(nx, nz)
			kinds[column] = _types[iz * WIDTH + ix]
			if highs[column] > lows[column]:
				minimum = mini(minimum, lows[column])
				maximum = maxi(maximum, highs[column])
		if maximum <= minimum:
			continue
		var rows := maximum - minimum
		var mask := PackedInt32Array()
		mask.resize(rows * CHUNK)
		mask.fill(-1)
		for column in range(CHUNK):
			for y in range(lows[column], highs[column]):
				mask[(y - minimum) * CHUNK + column] = _side_color_id(y, highs[column], kinds[column])
		for y in range(rows):
			var column := 0
			while column < CHUNK:
				var index := y * CHUNK + column
				var kind := mask[index]
				if kind < 0:
					column += 1
					continue
				var length := 1
				while column + length < CHUNK and mask[index + length] == kind:
					length += 1
				var height := 1
				var extend := true
				while y + height < rows and extend:
					for dx in range(length):
						if mask[(y + height) * CHUNK + column + dx] != kind:
							extend = false
							break
					if extend:
						height += 1
				for dy in range(height):
					for dx in range(length):
						mask[(y + dy) * CHUNK + column + dx] = -1
				var x := cx - EXTENT + (row if direction < 2 else column)
				var z := cz - EXTENT + (column if direction < 2 else row)
				_side_rect(x,z,length,(y+minimum)*STEP,(y+minimum+height)*STEP,kind,direction)
				column += length


func _side_color_id(y: int, high: int, kind: int) -> int:
	if kind == SAND or kind == SAND_LIGHT or kind == SAND_ROCK:
		return 4 if floori(float(y)/8.0)%3 != 0 else 5
	if kind == ROCK or kind == ROCK_LIGHT:
		return 2 if floori(float(y)/8.0)%3 != 0 else 3
	return 1 if y >= high-1 else 0


func _side_rect(x: int,z: int,length: int,lo: float,hi: float,kind: int,direction: int) -> void:
	var palette := [Color("8b7351"),Color("8d8555"),Color("83877c"),Color("6b716b"),Color("c1a371"),Color("b29463")]
	var color: Color=palette[kind]
	match direction:
		0:
			_quad(Vector3(x+1,lo,z),Vector3(x+1,lo,z+length),Vector3(x+1,hi,z+length),Vector3(x+1,hi,z),Vector3.RIGHT,color)
		1:
			_quad(Vector3(x,lo,z+length),Vector3(x,lo,z),Vector3(x,hi,z),Vector3(x,hi,z+length),Vector3.LEFT,color)
		2:
			_quad(Vector3(x+length,lo,z+1),Vector3(x,lo,z+1),Vector3(x,hi,z+1),Vector3(x+length,hi,z+1),Vector3.BACK,color)
		3:
			_quad(Vector3(x,lo,z),Vector3(x+length,lo,z),Vector3(x+length,hi,z),Vector3(x,hi,z),Vector3.FORWARD,color)


func _make_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _water_kind(ix: int, iz: int) -> int:
	var h := _heights[iz * WIDTH + ix]
	if h > 0:
		return -1
	if h > -3:
		return 0
	if h > -9:
		return 1
	if h > -17:
		return 2
	return 3


func _build_water() -> void:
	_clear_arrays()
	var visited := PackedByteArray()
	visited.resize(WIDTH * WIDTH)
	for iz in range(WIDTH):
		for ix in range(WIDTH):
			var index := iz * WIDTH + ix
			if visited[index] != 0:
				continue
			var kind := _water_kind(ix, iz)
			if kind < 0:
				continue
			var length := 1
			while ix+length < WIDTH and visited[index+length] == 0 and _water_kind(ix+length,iz) == kind:
				length += 1
			var depth := 1
			var extend := true
			while iz+depth < WIDTH and extend:
				for dx in range(length):
					if visited[(iz+depth)*WIDTH+ix+dx] != 0 or _water_kind(ix+dx,iz+depth) != kind:
						extend = false
						break
				if extend:
					depth += 1
			for dz in range(depth):
				for dx in range(length):
					visited[(iz+dz)*WIDTH+ix+dx] = 1
			var x := float(ix-EXTENT)
			var z := float(iz-EXTENT)
			_quad(Vector3(x,SEA,z),Vector3(x+length,SEA,z),Vector3(x+length,SEA,z+depth),Vector3(x,SEA,z+depth),Vector3.UP,WATER_COLORS[kind],false)
	var water := MeshInstance3D.new()
	water.name = "VoxelSea"
	water.mesh = _make_mesh()
	water.material_override = _water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(water)
	_water_triangles = _indices.size() / 3


func _add_details() -> void:
	# Small shared block silhouettes break the meadow's edge without a prop forest.
	var groups: Dictionary = {}
	for iz in range(0, WIDTH, 9):
		for ix in range(0, WIDTH, 9):
			var x := float(ix-EXTENT) + 0.5
			var z := float(iz-EXTENT) + 0.5
			if _plateau_distance(x,z) < 6.0 or _coast_distance(x,z) < 20.0 or _path_distance(x,z) < 6.0:
				continue
			var hash_value := absi(ix * 173 + iz * 397 + ix * iz * 11)
			if hash_value % 13 != 0:
				continue
			var h := height_at(x,z)
			var key := Vector2i(floori(x/64.0),floori(z/64.0))
			if not groups.has(key):
				groups[key] = []
			var size_value := Vector3(1.0,0.5,1.0) if h < 18 else Vector3(2.0,1.0,1.5)
			var color := Color("53773e") if _desert_weight(x,z)<0.4 and h<18 else Color("a38d66") if h<18 else Color("787d72")
			groups[key].append({"position":Vector3(x,h+size_value.y*0.5,z),"size":size_value,"color":color})
	for key in groups:
		var parts: Array=groups[key]
		# Keep CPU-owned mesh data: the headless renderer cannot serialize a
		# MultiMesh transform buffer reliably. Five faces per isolated accent;
		# the bottom face touching the terrain is omitted.
		_clear_arrays()
		for part: Dictionary in parts:
			var p: Vector3=part["position"]
			var half_size: Vector3=part["size"]*0.5
			var a := p-half_size
			var b := p+half_size
			var color: Color=part["color"]
			_quad(Vector3(a.x,b.y,a.z),Vector3(b.x,b.y,a.z),Vector3(b.x,b.y,b.z),Vector3(a.x,b.y,b.z),Vector3.UP,color,false)
			_quad(Vector3(b.x,a.y,a.z),Vector3(b.x,a.y,b.z),Vector3(b.x,b.y,b.z),Vector3(b.x,b.y,a.z),Vector3.RIGHT,color,false)
			_quad(Vector3(a.x,a.y,b.z),Vector3(a.x,a.y,a.z),Vector3(a.x,b.y,a.z),Vector3(a.x,b.y,b.z),Vector3.LEFT,color,false)
			_quad(Vector3(b.x,a.y,b.z),Vector3(a.x,a.y,b.z),Vector3(a.x,b.y,b.z),Vector3(b.x,b.y,b.z),Vector3.BACK,color,false)
			_quad(Vector3(a.x,a.y,a.z),Vector3(b.x,a.y,a.z),Vector3(b.x,b.y,a.z),Vector3(a.x,b.y,a.z),Vector3.FORWARD,color,false)
		var instance := MeshInstance3D.new()
		instance.name="GroundAccents_%d_%d"%[key.x,key.y]
		instance.mesh=_make_mesh()
		instance.material_override=_material
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(instance)
