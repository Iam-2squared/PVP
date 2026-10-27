extends RefCounted
## Bake exposed voxel surfaces into spatial chunks, merging coplanar faces.
## No per-voxel scene nodes, hidden interior triangles, or runtime build loops.

const CELL_SIZE := 0.5
const CHUNK_SIZE := 64
const CHUNK_SHIFT := 6
const MASK_AREA := CHUNK_SIZE * CHUNK_SIZE
const PALETTE := {
	1: "71954f", 2: "8a6748", 3: "587b42", 4: "b6b7aa",
	5: "d5d4c3", 6: "777f79", 7: "304d6c", 8: "487a9d",
	9: "9b7046", 10: "594330", 11: "d6bd89", 12: "bc9e6d",
	13: "858b7f", 14: "e2e6dc", 15: "458fa9", 16: "a69e88",
	17: "d9b15b", 18: "678358", 19: "a3845f", 20: "ece4cd"
}
const AXES := [Vector3i(1,0,0), Vector3i(0,1,0), Vector3i(0,0,1)]

var _volume: RefCounted
var _material: StandardMaterial3D
var _palette_colors: Dictionary = {}
var _quad_count := 0
var _exposed_faces := 0
var _chunk_count := 0

func build_meshes(volume: RefCounted) -> Node3D:
	var start := Time.get_ticks_msec()
	_volume = volume
	_quad_count = 0
	_exposed_faces = 0
	_chunk_count = 0
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	# Both normals and clockwise front faces are supplied explicitly below.
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.resource_name = "VoxelStoneAndWood"
	for id in PALETTE:
		_palette_colors[id] = Color(PALETTE[id])
	var chunks: Dictionary = {}
	for position: Vector3i in volume.cells:
		var coordinate := Vector3i(position.x >> CHUNK_SHIFT, position.y >> CHUNK_SHIFT, position.z >> CHUNK_SHIFT)
		if not chunks.has(coordinate):
			chunks[coordinate] = []
		chunks[coordinate].append(position)
	var coordinates: Array = chunks.keys()
	coordinates.sort_custom(func(a: Vector3i,b: Vector3i)->bool:
		if a.z != b.z: return a.z < b.z
		if a.x != b.x: return a.x < b.x
		return a.y < b.y)
	var root := Node3D.new()
	root.name = "VoxelFortifications"
	for coordinate: Vector3i in coordinates:
		var masks := _surface_masks(coordinate, chunks[coordinate])
		if masks.is_empty():
			continue
		var chunk := _build_chunk(coordinate, masks)
		if chunk != null:
			root.add_child(chunk)
			_chunk_count += 1
	var stats := {
		"voxels": volume.cells.size(), "chunks": _chunk_count,
		"quads": _quad_count, "triangles": _quad_count * 2,
		"exposed_faces_before_merge": _exposed_faces,
		"merged_face_ratio": snappedf(float(_exposed_faces) / maxf(_quad_count,1),0.01),
		"material_count": 1, "voxel_size": CELL_SIZE,
		"baked_vertex_ao": true, "ao_aware_merge": true, "build_ms": Time.get_ticks_msec()-start,
	}
	root.set_meta("mesh_stats",stats)
	print("VOXEL_MESH ",JSON.stringify(stats))
	_volume = null
	return root

func _surface_masks(coordinate: Vector3i, positions: Array) -> Dictionary:
	var masks: Dictionary = {}
	var origin := coordinate * CHUNK_SIZE
	for position: Vector3i in positions:
		var local := position-origin
		var material_id: int = _volume.cells[position]
		for axis in range(3):
			var u := (axis+1)%3
			var v := (axis+2)%3
			for side in range(2):
				var sign_value := side*2-1
				if _volume.cells.has(position + AXES[axis]*sign_value):
					continue
				var plane := local[axis] + side
				var key := (axis*2+side)*(CHUNK_SIZE+1)+plane
				if not masks.has(key):
					var mask := PackedInt32Array()
					mask.resize(MASK_AREA)
					masks[key] = mask
				# Include corner occlusion in the merge key: a doorway's shadow
				# must not stretch across an otherwise featureless 16m wall.
				var ao_signature := _face_signature(position,axis,sign_value,u,v)
				masks[key][local[u]+local[v]*CHUNK_SIZE] = material_id | (ao_signature << 8)
				_exposed_faces += 1
	return masks

func _build_chunk(coordinate: Vector3i, masks: Dictionary) -> Node3D:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var keys: Array = masks.keys()
	keys.sort()
	for key: int in keys:
		var orientation: int = key/(CHUNK_SIZE+1)
		var axis: int = orientation/2
		var side: int = orientation%2
		var plane := key%(CHUNK_SIZE+1)
		var mask: PackedInt32Array = masks[key]
		var row := 0
		while row<CHUNK_SIZE:
			var column := 0
			while column<CHUNK_SIZE:
				var face_key := mask[column+row*CHUNK_SIZE]
				if face_key==0:
					column+=1
					continue
				var width := 1
				while column+width<CHUNK_SIZE and mask[column+width+row*CHUNK_SIZE]==face_key:
					width+=1
				var height := 1
				var can_extend := true
				while row+height<CHUNK_SIZE and can_extend:
					for offset in range(width):
						if mask[column+offset+(row+height)*CHUNK_SIZE]!=face_key:
							can_extend=false
							break
					if can_extend:
						height+=1
				for dy in range(height):
					for dx in range(width):
						mask[column+dx+(row+dy)*CHUNK_SIZE]=0
				_quad(axis,side,plane,column,row,width,height,face_key,positions,normals,colors,indices)
				column+=width
			row+=1
	if positions.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,_material)
	var node := Node3D.new()
	node.name="Chunk_%d_%d_%d"%[coordinate.x,coordinate.y,coordinate.z]
	node.position=Vector3(coordinate*CHUNK_SIZE)*CELL_SIZE
	var visual := MeshInstance3D.new()
	visual.name="Surface"
	visual.mesh=mesh
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(visual)
	var body := StaticBody3D.new()
	body.name="Solid"
	node.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name="Collision"
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision=true
	collision.shape=shape
	body.add_child(collision)
	return node

func _quad(axis: int,side: int,plane: int,start_u: int,start_v: int,width: int,height: int,face_key: int,positions: PackedVector3Array,normals: PackedVector3Array,colors: PackedColorArray,indices: PackedInt32Array) -> void:
	var u := (axis+1)%3
	var v := (axis+2)%3
	var sign_value := side*2-1
	var normal := Vector3(AXES[axis]*sign_value)
	var uv := [Vector2i(start_u,start_v),Vector2i(start_u+width,start_v),Vector2i(start_u+width,start_v+height),Vector2i(start_u,start_v+height)]
	var offset := positions.size()
	var base_color: Color=_palette_colors.get(face_key & 255,Color.MAGENTA)
	var ao_signature := face_key >> 8
	for i in range(4):
		var point := Vector3.ZERO
		point[axis]=plane
		point[u]=uv[i].x
		point[v]=uv[i].y
		positions.append(point*CELL_SIZE)
		normals.append(normal)
		var ao := 1.0-float((ao_signature >> (i*2)) & 3)*0.13
		var direction_shade := 0.82 if axis==1 and side==0 else 1.0
		colors.append(Color(base_color.r*ao*direction_shade,base_color.g*ao*direction_shade,base_color.b*ao*direction_shade,1.0))
	# Godot considers clockwise winding front-facing. Normals remain outward.
	if side==1:
		indices.append_array(PackedInt32Array([offset,offset+3,offset+2,offset,offset+2,offset+1]))
	else:
		indices.append_array(PackedInt32Array([offset,offset+1,offset+2,offset,offset+2,offset+3]))
	_quad_count+=1

func _face_signature(position: Vector3i,axis: int,sign_value: int,u: int,v: int) -> int:
	var result := 0
	for i in range(4):
		var sign_u := 1 if i==1 or i==2 else -1
		var sign_v := 1 if i>=2 else -1
		result |= _corner_occlusion(position,axis,sign_value,u,v,sign_u,sign_v) << (i*2)
	return result

func _corner_occlusion(position: Vector3i,axis: int,sign_value: int,u: int,v: int,sign_u: int,sign_v: int) -> int:
	var outside: Vector3i = position+AXES[axis]*sign_value
	var a: Vector3i = AXES[u]*sign_u
	var b: Vector3i = AXES[v]*sign_v
	var side_a := int(_volume.cells.has(outside+a))
	var side_b := int(_volume.cells.has(outside+b))
	var corner := int(_volume.cells.has(outside+a+b))
	return 3 if side_a==1 and side_b==1 else side_a+side_b+corner
