extends RefCounted
## Flat cleared ground and a collision base shared by all construction stages.
## Town replaces ContinuousCityPaving with district_surfaces.gd at the same level.

const EXTENT := 320
const GROUND_Y := 2.0
const CITY_HALF := 160.0
const STONE := Color("aaa99e")
const EARTH := Color("a19070")

func height_at(_x: float,_z: float) -> float:
	return GROUND_Y

func build() -> Node3D:
	var result:=Node3D.new()
	result.name="LevelKingdomGround"
	var material:=StandardMaterial3D.new()
	material.albedo_color=EARTH
	material.roughness=1.0
	_exterior_ground(result,material)
	var body:=StaticBody3D.new()
	body.name="LevelGroundCollision"
	body.position.y=GROUND_Y-1.0
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(EXTENT*2,2.0,EXTENT*2)
	collision.shape=shape
	body.add_child(collision)
	result.add_child(body)
	_city_paving(result)
	var statistics:={"land_triangles":20,"land_chunks":2,"water_triangles":0,"max_height":GROUND_Y,"min_height":GROUND_Y,"city_paving":"stage_fallback_replaced_by_town_districts","exterior":"cleared_level_ground","horizontal_grid":0.5,"height_step":0.5}
	result.set_meta("terrain_stats",statistics)
	print("VOXEL_TERRAIN ",JSON.stringify(statistics))
	return result

func _exterior_ground(parent: Node3D,material: Material) -> void:
	var a:=CITY_HALF
	var b:=a*(sqrt(2.0)-1.0)
	var e:=float(EXTENT)
	var polygons: Array=[
		[Vector2(-e,-e),Vector2(e,-e),Vector2(e,-a),Vector2(-e,-a)],
		[Vector2(-e,a),Vector2(e,a),Vector2(e,e),Vector2(-e,e)],
		[Vector2(-e,-a),Vector2(-a,-a),Vector2(-a,a),Vector2(-e,a)],
		[Vector2(a,-a),Vector2(e,-a),Vector2(e,a),Vector2(a,a)],
		[Vector2(-a,-a),Vector2(-b,-a),Vector2(-a,-b)],
		[Vector2(b,-a),Vector2(a,-a),Vector2(a,-b)],
		[Vector2(a,b),Vector2(a,a),Vector2(b,a)],
		[Vector2(-a,b),Vector2(-b,a),Vector2(-a,a)]
	]
	var positions:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var indices:=PackedInt32Array()
	for polygon in polygons:
		var offset:=positions.size()
		for point in polygon:
			positions.append(Vector3(point.x,GROUND_Y,point.y))
			normals.append(Vector3.UP)
		for i in range(1,polygon.size()-1):
			indices.append_array(PackedInt32Array([offset,offset+i,offset+i+1]))
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual:=MeshInstance3D.new()
	visual.name="ClearedExteriorGround"
	visual.mesh=mesh
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)

func _city_paving(parent: Node3D) -> void:
	var a:=CITY_HALF
	var b:=a*(sqrt(2.0)-1.0)
	var polygon:=[Vector2(-b,-a),Vector2(b,-a),Vector2(a,-b),Vector2(a,b),Vector2(b,a),Vector2(-b,a),Vector2(-a,b),Vector2(-a,-b)]
	var positions:=PackedVector3Array([Vector3(0,GROUND_Y,0)])
	var normals:=PackedVector3Array([Vector3.UP])
	var colors:=PackedColorArray([STONE])
	var indices:=PackedInt32Array()
	for point in polygon:
		positions.append(Vector3(point.x,GROUND_Y,point.y))
		normals.append(Vector3.UP)
		colors.append(STONE)
	for i in range(8):
		indices.append_array(PackedInt32Array([0,i+1,(i+1)%8+1]))
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var shader:=Shader.new()
	# Anti-aliased joints fade in distant views. No tile nodes or textures.
	shader.code="""shader_type spatial;
render_mode diffuse_burley, specular_disabled;
varying vec2 paving_position;
void vertex() { paving_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
 vec2 p=paving_position;
 float row=floor(p.y);
 p.x+=mod(row,2.0);
 vec2 cell=vec2(p.x*0.5,p.y);
 vec2 edge=min(fract(cell),1.0-fract(cell));
 vec2 aa=max(fwidth(cell),vec2(0.001));
 vec2 inside=smoothstep(vec2(0.008),vec2(0.008)+aa,edge);
 float joint=1.0-min(inside.x,inside.y);
 ALBEDO=mix(vec3(0.53,0.52,0.47),vec3(0.45,0.44,0.40),joint*0.45);
 ROUGHNESS=1.0;
}
"""
	var material:=ShaderMaterial.new()
	material.shader=shader
	var visual:=MeshInstance3D.new()
	visual.name="ContinuousCityPaving"
	visual.mesh=mesh
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.set_meta("glb_albedo",STONE)
	parent.add_child(visual)
