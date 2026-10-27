extends RefCounted
## Flat, mutually exclusive city surfaces. Boolean clipping happens only while
## baking. Each material is one merged mesh, including its roads and courtyards.
## No textures, per-paving-stone nodes, raised road plates, or overlapping floors.

const GROUND_Y := 2.03
const CITY_HALF := 160.0
const CELL_SIZE := 2.0
const TERRACE_RESERVE := Rect2(-62,-152,124,134)

var _layers: Array[Dictionary] = []
var _bins: Dictionary = {}
var _buffers: Dictionary = {}
var _triangles := 0
var _subdivisions := 0
var _discarded_sliver_area := 0.0
var _shader: Shader

func build(town_data: Dictionary, _palace_data: Dictionary = {}) -> Node3D:
	_layers.clear()
	_bins.clear()
	_buffers.clear()
	_triangles = 0
	_subdivisions = 0
	_discarded_sliver_area = 0.0
	_shader = _surface_shader()
	var regions: Array = town_data.get("ground_regions", _default_regions())
	if regions.is_empty(): regions = _default_regions()
	for region: Dictionary in regions:
		if str(region.get("kind", "")) in ["park", "sand"]: continue
		_add_region(region)
	# Older residential yards have broad damp and bare-soil patches, not a
	# random paving checkerboard. Streets subsequently cut cleanly through them.
	_add_residential_wear()
	for royal_pass in [false,true]:
		for street: Dictionary in town_data.get("streets", []):
			if _is_royal_street(street) == royal_pass: _add_street(street)
	# A park is green to its boundary; its light footpaths occupy a small area.
	var green_ids: Dictionary = {}
	for region: Dictionary in regions:
		if str(region.get("kind", "")) != "park": continue
		_add_region(region)
		green_ids[str(region.get("id", ""))] = true
		if region.has("bounds") and region["bounds"] is Rect2:
			_add_park_paths(region["bounds"])
	for park: Dictionary in town_data.get("parks", []):
		var id := str(park.get("id", ""))
		if green_ids.has(id) or id.begins_with("royal_"): continue
		var bounds: Variant = park.get("bounds")
		if not bounds is AABB: continue
		var rect := Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
		if rect.intersects(TERRACE_RESERVE): continue
		_add_rectangle(rect,"park")
		_add_park_paths(rect)
	var has_sand := false
	for region: Dictionary in regions:
		if str(region.get("kind", "")) != "sand": continue
		_add_region(region)
		has_sand = true
	if not has_sand:
		_add_rectangle(Rect2(-116,-104,41,36),"sand")
	var city := _city_polygon()
	var count := int(CITY_HALF * 2.0 / CELL_SIZE)
	for iz in range(count):
		for ix in range(count):
			var rect := Rect2(Vector2(-CITY_HALF + ix*CELL_SIZE,-CITY_HALF + iz*CELL_SIZE),Vector2.ONE*CELL_SIZE)
			var centre := rect.get_center()
			var diagonal_limit := CITY_HALF * sqrt(2.0)
			if absf(centre.x)+absf(centre.y)>diagonal_limit+CELL_SIZE: continue
			var candidates: Array = _bins.get(Vector2i(ix,iz),[])
			var cell := _rectangle_polygon(rect)
			var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(cell,city)
			for polygon: PackedVector2Array in clipped:
				_partition(polygon,candidates,0)
	var result := Node3D.new()
	result.name = "DistrictGroundSurfaces"
	for kind: String in _buffers:
		_emit_mesh(result,kind,_buffers[kind])
	var stats := {
		"surface_meshes":result.get_child_count(),"triangles":_triangles,
		"flat_surface_y":GROUND_Y,"collision_top":2.0,"overlapping_floor_plates":false,
		"training_surface":"sand","park_surface":"full_green_lawn",
		"materials":_buffers.keys(),"boolean_layers":_layers.size(),
		"adaptive_subdivisions":_subdivisions,"discarded_sliver_area":_discarded_sliver_area,"textures":0,
	}
	result.set_meta("surface_stats",stats)
	print("DISTRICT_SURFACES ",JSON.stringify(stats))
	return result

func _default_regions() -> Array:
	return [
		{"id":"northwest","kind":"military","bounds":Rect2(-145,-145,81,137)},
		{"id":"northeast","kind":"civic","bounds":Rect2(64,-145,81,137)},
		{"id":"west_guild","kind":"cobble","bounds":Rect2(-145,-65,81,73)},
		{"id":"east_civic","kind":"cobble","bounds":Rect2(8,8,137,38)},
		{"id":"market","kind":"market","bounds":Rect2(-120,12,66,35)},
		{"id":"southwest","kind":"old_quarter","bounds":Rect2(-145,46,137,100)},
		{"id":"southeast","kind":"poor_quarter","bounds":Rect2(8,46,137,100)},
		{"id":"east_park","kind":"park","bounds":Rect2(29,10,33,27)},
		{"id":"southwest_green","kind":"park","bounds":Rect2(-61,70,24,22)},
		{"id":"church_green","kind":"park","bounds":Rect2(110,-100,21,37)},
		{"id":"training_yard","kind":"sand","bounds":Rect2(-116,-104,41,36)},
	]

func _add_region(region: Dictionary) -> void:
	var kind := str(region.get("kind","court"))
	if not _styles().has(kind): kind = "cobble"
	if region.has("polygon"):
		_add_layer(PackedVector2Array(region["polygon"]),kind)
	elif region.has("bounds") and region["bounds"] is Rect2:
		_add_rectangle(region["bounds"],kind)

func _add_street(street: Dictionary) -> void:
	var points := PackedVector2Array()
	if street.has("planar"):
		points = street["planar"]
	else:
		for point: Vector3 in street.get("points",PackedVector3Array()):
			points.append(Vector2(point.x,point.z))
	if points.size()<2: return
	var width := maxf(float(street.get("width",4.0)),2.0)
	var district := str(street.get("district",""))
	var is_royal := _is_royal_street(street)
	for i in range(points.size()-1):
		var start := points[i]
		var finish := points[i+1]
		if start.distance_to(finish)<0.05: continue
		var centre := (start+finish)*0.5
		var is_market := not is_royal and (district in ["market","old_quarter","southwest"] or (centre.x < -30.0 and centre.y>8.0))
		var is_poor := not is_royal and not is_market and (district in ["residential","poor","poor_quarter"] or (centre.x>8.0 and centre.y>46.0))
		var border := "main_border" if is_royal else ("dirt" if is_poor else "road_edge")
		var fill := "main_avenue" if is_royal else ("poor_road" if is_poor else ("market_road" if is_market else "cobble_road"))
		var side := (finish-start).normalized().orthogonal()
		_add_segment(start,finish,width+1.2,border,0.5)
		_add_segment(start,finish,width,fill,0.5)
		if is_royal and width>=9.0:
			# Paired narrow bronze stone inlays make the cardinal avenues legible.
			var offset := side*(width*0.5-1.0)
			_add_segment(start+offset,finish+offset,0.22,"inlay",0.55)
			_add_segment(start-offset,finish-offset,0.22,"inlay",0.55)

func _is_royal_street(street: Dictionary) -> bool:
	return str(street.get("id","")) in ["south_royal","west_royal","east_royal","royal_garden_axis","plaza_west_arc","plaza_east_arc"] or str(street.get("district","")) in ["royal","avenue","main_avenue"]

func _add_residential_wear() -> void:
	for side in [-1.0,1.0]:
		for row in range(4):
			for column in range(4):
				var serial := row*4+column
				if serial%3==1: continue
				var centre := Vector2(side*(24.0+column*28.0+float(row%2)*5.0),58.0+row*24.0)
				var radius := Vector2(4.0+float(serial%3),2.0+float(serial%2))
				var polygon := PackedVector2Array()
				for i in range(7):
					var angle := TAU*float(i)/7.0
					var ripple := 0.86+0.14*sin(float(i*7+serial))
					polygon.append(centre+Vector2(cos(angle),sin(angle))*radius*ripple)
				_add_layer(polygon,"damp" if serial%2==0 else "dirt")
	# A few long rusty drainage stains follow the workshop edge.
	for x in [-113.0,-94.0,-74.0]:
		_add_rectangle(Rect2(x,42.0,1.1,5.0),"rust")

func _add_park_paths(rect: Rect2) -> void:
	var c := rect.get_center()
	_add_rectangle(Rect2(rect.position.x,c.y-0.85,rect.size.x,1.7),"park_path")
	# Small green squares need only a single footpath.
	if rect.size.x>25.0 and rect.size.y>22.0:
		_add_rectangle(Rect2(c.x-0.7,rect.position.y,1.4,rect.size.y),"park_path")

func _add_segment(start: Vector2, finish: Vector2, width: float, kind: String, extend: float) -> void:
	var direction := (finish-start).normalized()
	var n := direction.orthogonal()*width*0.5
	var a := start-direction*extend
	var b := finish+direction*extend
	_add_layer(PackedVector2Array([a+n,a-n,b-n,b+n]),kind)

func _add_rectangle(rect: Rect2, kind: String) -> void:
	_add_layer(_rectangle_polygon(rect),kind,rect)

func _add_layer(polygon: PackedVector2Array,kind: String, rect := Rect2()) -> void:
	if polygon.size()<3: return
	if Geometry2D.is_polygon_clockwise(polygon): polygon.reverse()
	var bounds := _bounds(polygon)
	var layer := {"polygon":polygon,"kind":kind,"bounds":bounds,"rectangle":rect}
	var index := _layers.size()
	_layers.append(layer)
	var first := Vector2i(floori((bounds.position.x+CITY_HALF)/CELL_SIZE),floori((bounds.position.y+CITY_HALF)/CELL_SIZE))
	var last := Vector2i(floori((bounds.end.x+CITY_HALF)/CELL_SIZE),floori((bounds.end.y+CITY_HALF)/CELL_SIZE))
	var count := int(CITY_HALF*2.0/CELL_SIZE)
	for z in range(maxi(first.y,0),mini(last.y,count-1)+1):
		for x in range(maxi(first.x,0),mini(last.x,count-1)+1):
			var key := Vector2i(x,z)
			if not _bins.has(key): _bins[key]=[]
			_bins[key].append(index)

func _partition(polygon: PackedVector2Array,candidates: Array,depth: int) -> void:
	var patches: Array[Dictionary] = [{"polygon":polygon,"kind":"court"}]
	for candidate: int in candidates:
		var layer: Dictionary = _layers[candidate]
		var cutter: PackedVector2Array = layer["polygon"]
		var next: Array[Dictionary] = []
		for patch: Dictionary in patches:
			var source: PackedVector2Array = patch["polygon"]
			var source_bounds := _bounds(source)
			if not source_bounds.intersects(layer["bounds"]):
				next.append(patch)
				continue
			var rect: Rect2 = layer["rectangle"]
			if rect.has_area() and rect.encloses(source_bounds):
				next.append({"polygon":source,"kind":layer["kind"]})
				continue
			var intersections: Array[PackedVector2Array] = Geometry2D.intersect_polygons(source,cutter)
			if intersections.is_empty():
				next.append(patch)
				continue
			var remaining: Array[PackedVector2Array] = Geometry2D.clip_polygons(source,cutter)
			# A tiny feature entirely within one cell can leave a hole. Smaller
			# cells eliminate that case before triangulation; no hole is filled.
			var has_hole := false
			for rem: PackedVector2Array in remaining:
				if Geometry2D.is_polygon_clockwise(rem): has_hole=true
			if has_hole and depth<7:
				_subdivide(polygon,candidates,depth)
				return
			for rem: PackedVector2Array in remaining:
				if not Geometry2D.is_polygon_clockwise(rem):
					next.append({"polygon":rem,"kind":patch["kind"]})
			for part: PackedVector2Array in intersections:
				next.append({"polygon":part,"kind":layer["kind"]})
		patches = next
	for patch: Dictionary in patches:
		_append_polygon(patch["polygon"],patch["kind"])

func _subdivide(polygon: PackedVector2Array,candidates: Array,depth: int) -> void:
	_subdivisions += 1
	var bounds := _bounds(polygon)
	var half := bounds.size*0.5
	for y in range(2):
		for x in range(2):
			var cell := _rectangle_polygon(Rect2(bounds.position+Vector2(x,y)*half,half))
			for part: PackedVector2Array in Geometry2D.intersect_polygons(polygon,cell):
				_partition(part,candidates,depth+1)

func _append_polygon(polygon: PackedVector2Array,kind: String) -> void:
	if polygon.size()<3: return
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		var area := 0.0
		for i in range(polygon.size()): area += polygon[i].cross(polygon[(i+1)%polygon.size()])
		_discarded_sliver_area += absf(area)*0.5
		return
	if not _buffers.has(kind):
		_buffers[kind] = {"positions":PackedVector3Array(),"normals":PackedVector3Array(),"indices":PackedInt32Array()}
	var data: Dictionary = _buffers[kind]
	var positions: PackedVector3Array = data["positions"]
	var normals: PackedVector3Array = data["normals"]
	var triangles: PackedInt32Array = data["indices"]
	var offset := positions.size()
	for point: Vector2 in polygon:
		positions.append(Vector3(point.x,GROUND_Y,point.y))
		normals.append(Vector3.UP)
	for index: int in indices: triangles.append(offset+index)
	data["positions"] = positions
	data["normals"] = normals
	data["indices"] = triangles
	_triangles += indices.size()/3

func _emit_mesh(parent: Node3D,kind: String,data: Dictionary) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["positions"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var style: Array = _styles().get(kind,_styles()["court"])
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("base_color",style[0])
	material.set_shader_parameter("surface_kind",style[1])
	material.set_shader_parameter("wear",style[2])
	var visual := MeshInstance3D.new()
	visual.name = "Ground_"+kind
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.set_meta("glb_albedo",style[0])
	visual.set_meta("ground_material",kind)
	parent.add_child(visual)

func _styles() -> Dictionary:
	# Color, shader pattern (stone / earth / grass), degree of age.
	return {
		"court":[Color("b5ae95"),0,0.18],
		"military":[Color("938b72"),0,0.38],
		"civic":[Color("b2af9b"),0,0.20],
		"cobble":[Color("969385"),0,0.40],
		"market":[Color("aa8b5d"),0,0.60],
		"old_quarter":[Color("827760"),0,0.72],
		"poor_quarter":[Color("686d60"),0,0.90],
		"main_border":[Color("958767"),0,0.14],
		"main_avenue":[Color("c9c0a3"),0,0.10],
		"inlay":[Color("8d7447"),0,0.14],
		"road_edge":[Color("827b65"),0,0.50],
		"market_road":[Color("b5996b"),0,0.57],
		"cobble_road":[Color("aaa594"),0,0.40],
		"poor_road":[Color("858575"),0,0.87],
		"dirt":[Color("716148"),1,0.65],
		"damp":[Color("525c48"),0,0.95],
		"rust":[Color("8b6745"),1,0.80],
		"sand":[Color("c7aa6b"),1,0.18],
		"park":[Color("477c35"),2,0.15],
		"park_path":[Color("c7b88c"),1,0.15],
	}

func _surface_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform vec4 base_color : source_color = vec4(0.6,0.6,0.5,1.0);
uniform int surface_kind = 0;
uniform float wear = 0.4;
varying vec2 ground_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0)),f.x),f.y);
}
void vertex() { ground_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
 vec2 p=ground_position;
 float broad=noise(p*0.075);
 float fine=noise(p*1.8);
 vec3 color=base_color.rgb;
 if(surface_kind==0) {
  float row=floor(p.y/0.72);
  vec2 tile=vec2((p.x+mod(row,2.0)*0.60)/1.20,p.y/0.72);
  vec2 edge=min(fract(tile),1.0-fract(tile));
  vec2 aa=max(fwidth(tile),vec2(0.001));
  float joint=1.0-min(smoothstep(0.018,0.018+aa.x,edge.x),smoothstep(0.025,0.025+aa.y,edge.y));
  float detail=1.0-smoothstep(0.35,0.95,max(aa.x,aa.y));
  float stone=hash(floor(tile));
  color*=1.0+(stone-0.5)*0.09*detail;
  color=mix(color,color*0.62,joint*detail*(0.22+wear*0.36));
  float stain=smoothstep(0.53,0.84,broad)*wear;
  color=mix(color,color*vec3(0.67,0.72,0.58),stain*0.43);
  float crack=1.0-smoothstep(0.008,0.025+max(aa.x,aa.y),abs(fract(tile.x*0.37+tile.y*0.61+stone)-0.48));
  color*=1.0-crack*step(0.91,stone)*wear*detail*0.22;
 } else if(surface_kind==1) {
  color*=0.94+0.085*broad+0.025*fine;
 } else {
  color*=0.86+broad*0.21+fine*0.045;
 }
 ALBEDO=color;
 ROUGHNESS=1.0;
}
"""
	return shader

func _city_polygon() -> PackedVector2Array:
	var a := CITY_HALF
	var b := a*(sqrt(2.0)-1.0)
	return PackedVector2Array([Vector2(-b,-a),Vector2(b,-a),Vector2(a,-b),Vector2(a,b),Vector2(b,a),Vector2(-b,a),Vector2(-a,b),Vector2(-a,-b)])

func _rectangle_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0],Vector2.ZERO)
	for point: Vector2 in polygon: result = result.expand(point)
	return result
