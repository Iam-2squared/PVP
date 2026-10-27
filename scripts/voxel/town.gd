extends RefCounted
## Offline city layout. Streets reserve movement corridors in the common
## pavement; only parks and the royal gardens receive vegetation.

const House = preload("res://scripts/voxel/house_builder.gd")
const Civic = preload("res://scripts/voxel/civic_buildings.gd")
const Details = preload("res://scripts/voxel/detail_builder.gd")
const TARGET_HOUSES := 304
const FEET_Y := 2.15

var _v: Variant
var _details: Variant
var _detail_root: Node3D
var _houses: Array[Dictionary] = []
var _streets: Array[Dictionary] = []
var _routes: Array[Dictionary] = []
var _landmarks: Array[Dictionary] = []
var _viewpoints: Array[Dictionary] = []
var _parks: Array[Dictionary] = []
var _reserved: Array[Rect2] = []
var _plots: Array[Rect2] = []
var _road_polygons: Array[PackedVector2Array] = []
var _enterable: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _serial := 0
var _clotheslines := 0
var _flags := 0

func build(volume: Variant) -> Dictionary:
	_v = volume
	_details = Details.new()
	_houses.clear()
	_streets.clear()
	_routes.clear()
	_landmarks.clear()
	_viewpoints.clear()
	_parks.clear()
	_reserved.clear()
	_plots.clear()
	_road_polygons.clear()
	_enterable.clear()
	_serial = 0
	_clotheslines = 0
	_flags = 0
	_rng.seed = 20261027
	_street_plan()
	_reserve_major_areas()
	_civic_buildings()
	_featured_shops()
	_military_quarter()
	_market()
	_formal_gardens()
	_neighbourhood_parks()
	# The southwest gets a continuous, individually dressed shop frontage.
	for street in _streets:
		if street["district"] == "southwest":
			_frontages(street, 1)
	for street in _streets:
		if street["district"] in ["residential", "east", "north"]:
			_frontages(street, 0)
	_infill_blocks()
	_compact_infill()
	_street_dressing()
	_viewpoints.append_array([
		_walk_view("town_south_gate","南門から王都へ",Vector2(0,146),Vector3(0,20,-75)),
		_walk_view("southwest_shambles","商店街の張出し家並み",Vector2(-43,36),Vector3(-72,7,41)),
		_walk_view("residential_laundry","洗濯物の裏路地",Vector2(61,102.2),Vector3(77,6,105)),
	])
	_detail_root = _details.finish()
	var stats: Dictionary = _detail_root.get_meta("detail_stats", {}).duplicate()
	stats["clotheslines"] = _clotheslines
	stats["bunting_lines"] = _flags
	return {
		"house_count":_houses.size(), "houses":_houses.duplicate(true),
		"streets":_streets.duplicate(true), "route_waypoints":_routes.duplicate(true),
		"landmarks":_landmarks.duplicate(true), "viewpoints":_viewpoints.duplicate(true),
		"enterable_buildings":_enterable.duplicate(true), "parks":_parks.duplicate(true),
		"dressingstats":stats, "ground_top":2.0, "adds_road_plates":false,
		"capture_viewpoints":[{"id":"town_overview","position":Vector3(104,125,170),"target":Vector3(0,15,-15)}],
		"districts":["西の商店街", "南西の連棟街", "南東の住宅街", "東の公共区", "北の工房街"],
		"reserved_wall_stair_bases":[Vector2(-88,130),Vector2(-130,-88),Vector2(88,-130),Vector2(130,88)],
	}

func take_details() -> Node3D:
	var result := _detail_root
	_detail_root = null
	return result

func _street_plan() -> void:
	_street("south_royal", "南門大通り", 12, [Vector2(0,153),Vector2(0,35)], "main")
	_street("west_royal", "西門大通り", 10, [Vector2(-153,0),Vector2(-85,0),Vector2(-32,0),Vector2(0,0)], "main")
	_street("east_royal", "東門大通り", 10, [Vector2(0,0),Vector2(85,0),Vector2(153,0)], "main")
	_street("royal_garden_axis", "王城への庭園道", 12, [Vector2(0,-8),Vector2(0,-56)], "main")
	_street("plaza_west_arc", "噴水西の回り道", 7, [Vector2(0,35),Vector2(-10,28),Vector2(-10,14),Vector2(-10,0),Vector2(0,-8)], "main")
	_street("plaza_east_arc", "噴水東の回り道", 7, [Vector2(0,35),Vector2(10,28),Vector2(10,14),Vector2(10,0)], "main")
	_street("southwest_merchants", "曲がり角の商店街", 5, [Vector2(-18,28),Vector2(-39,37),Vector2(-63,31),Vector2(-75,46),Vector2(-96,49),Vector2(-107,67),Vector2(-86,79),Vector2(-61,75),Vector2(-42,92),Vector2(-21,101)], "southwest")
	_street("west_back_lane", "西の工房裏道", 3, [Vector2(-22,49),Vector2(-40,57),Vector2(-51,50),Vector2(-62,59),Vector2(-57,72)], "southwest")
	_street("southwest_residential", "南西の連棟路地", 4, [Vector2(-112,86),Vector2(-90,95),Vector2(-72,91),Vector2(-57,105),Vector2(-34,109),Vector2(-18,119)], "residential")
	_street("south_cross_lane", "南の横丁", 4, [Vector2(-76,126),Vector2(-51,123),Vector2(-27,131),Vector2(0,130),Vector2(24,128),Vector2(45,135),Vector2(65,132)], "residential")
	_street("southeast_loop", "南東の生活通り", 4.5, [Vector2(20,48),Vector2(45,51),Vector2(60,66),Vector2(88,70),Vector2(99,92),Vector2(77,105),Vector2(54,101),Vector2(24,116)], "residential")
	_street("east_back_lane", "東の細道", 3, [Vector2(17,74),Vector2(35,78),Vector2(46,90),Vector2(68,88),Vector2(78,73)], "residential")
	_street("west_wall_lane", "西壁沿いの巡回道", 4.5, [Vector2(-143,12),Vector2(-132,38),Vector2(-125,63),Vector2(-111,87),Vector2(-99,106),Vector2(-81,123)], "east")
	_street("east_wall_lane", "東壁沿いの巡回道", 4.5, [Vector2(142,12),Vector2(133,39),Vector2(121,65),Vector2(110,102)], "east")
	_street("cathedral_approach", "教会前の道", 7, [Vector2(26,0),Vector2(55,-12),Vector2(73,-31),Vector2(96,-50),Vector2(96,-56)], "east")
	_street("northeast_lane", "北東の職人通り", 4.5, [Vector2(72,-127),Vector2(77,-109),Vector2(72,-86),Vector2(65,-60),Vector2(76,-40),Vector2(101,-31),Vector2(106,-18),Vector2(128,-12),Vector2(143,-5)], "north")
	_street("northwest_lane", "北西の工房路地", 4.5, [Vector2(-72,-128),Vector2(-78,-112),Vector2(-67,-97),Vector2(-72,-72),Vector2(-62,-52)], "north")
	_street("garrison_access", "駐屯所と訓練場への道", 5, [Vector2(-143,0),Vector2(-126,-27),Vector2(-122,-53),Vector2(-122,-83),Vector2(-115,-83)], "main")
	_street("guild_access", "ギルドの正面道", 4, [Vector2(-91,0),Vector2(-91,-8),Vector2(-91,-11)], "main")
	_street("tavern_access", "酒場の横路地", 3.5, [Vector2(-82,47),Vector2(-88,42),Vector2(-90,28.5),Vector2(-94,28.5)], "main")
	_street("weapon_access", "武器店への小道", 3, [Vector2(-54,33),Vector2(-54,39)], "main")
	_street("forge_access", "鍛冶屋への小道", 3, [Vector2(-83,47),Vector2(-83,40)], "main")
	_street("apothecary_access", "薬屋への小道", 3, [Vector2(119,0),Vector2(119,-22)], "main")
	_street("inn_access", "宿屋への小道", 3.5, [Vector2(88,70),Vector2(102,63),Vector2(109,54)], "main")
	# Wall staircase pads stay connected to the same shared pavement.
	_street("southwest_stair_access", "南西城壁階段", 4, [Vector2(-76,126),Vector2(-82,130),Vector2(-88,130)], "main")
	_street("northwest_stair_access", "北西城壁階段", 4, [Vector2(-122,-83),Vector2(-130,-88)], "main")
	_street("northeast_stair_access", "北東城壁階段", 4, [Vector2(72,-127),Vector2(88,-130)], "main")
	_street("southeast_stair_access", "南東城壁階段", 4, [Vector2(121,65),Vector2(126,77),Vector2(130,88)], "main")

func _street(id: String, title: String, width: float, points: Array, district: String) -> void:
	var world_points := PackedVector3Array()
	var planar := PackedVector2Array()
	for p: Vector2 in points:
		world_points.append(Vector3(p.x,FEET_Y,p.y))
		planar.append(p)
	var data := {"id":id,"title":title,"width":width,"points":world_points,"planar":planar,"district":district}
	_streets.append(data)
	_routes.append({"id":id,"title":title,"width":width,"points":world_points})
	for i in range(planar.size()-1):
		var t := (planar[i+1]-planar[i]).normalized()
		var n := Vector2(-t.y,t.x) * (width*0.5+0.5)
		var a := planar[i]-t*(width*0.5+0.5)
		var b := planar[i+1]+t*(width*0.5+0.5)
		_road_polygons.append(PackedVector2Array([a+n,b+n,b-n,a-n]))

func _reserve_major_areas() -> void:
	_reserved.append(Rect2(-64,-150,128,139))
	_reserved.append(Rect2(-22,-6,44,40))
	_reserved.append(Rect2(-118,-107,45,42))
	_reserved.append(Rect2(-114,-55,34,34))
	_reserved.append(Rect2(-101,49,38,19))
	_reserved.append(Rect2(55,109,32,19))
	for p in [Vector2(-88,130),Vector2(-130,-88),Vector2(88,-130),Vector2(130,88)]:
		_reserved.append(Rect2(p-Vector2.ONE*6,Vector2.ONE*12))

func _civic_buildings() -> void:
	var civic := Civic.new()
	for spec in [
		{"id":"adventurers_guild","title":"冒険者ギルド","kind":"guild","c":Vector2(-91,-19.5),"q":0},
		{"id":"tavern","title":"灯火の酒場","kind":"tavern","c":Vector2(-100.5,26),"q":1},
		{"id":"church","title":"王都の教会","kind":"church","c":Vector2(96,-74.5),"q":0},
	]:
		var info: Dictionary = civic.build(_v,_details,spec["kind"],spec["c"],spec["q"])
		info["id"] = spec["id"]
		info["title"] = spec["title"]
		info["interior_point"] = info["enterable_groundroom"]["position"]
		var bounds: AABB = info["bounds"]
		_reserved.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(1.0))
		_enterable.append(info)
		_landmarks.append({"id":spec["id"],"title":spec["title"],"kind":spec["kind"],"position":info["entrance"],"bounds":bounds})
		for route in info["route_waypoints"]:
			_routes.append(route)

func _featured_shops() -> void:
	var specs := [
		{"id":"weapon_shop","title":"武器店","centreXZ":Vector2(-54,44),"width":7,"depth":8,"storeys":3,"orientation":0.0,"kind":"weapon_shop","enterable":true,"seed":41,"plaster_id":11},
		{"id":"blacksmith","title":"鍛冶屋","centreXZ":Vector2(-83,35),"width":8,"depth":8,"storeys":2,"orientation":PI,"kind":"blacksmith","enterable":true,"seed":42,"plaster_id":25},
		{"id":"apothecary","title":"薬屋","centreXZ":Vector2(119,-27),"width":6,"depth":8,"storeys":2,"orientation":PI,"kind":"shop","enterable":true,"seed":43,"plaster_id":31,"roof_id":7},
		{"id":"inn","title":"東の宿屋","centreXZ":Vector2(117,54),"width":10,"depth":10,"storeys":3,"orientation":PI*0.5,"kind":"inn","enterable":true,"seed":44,"plaster_id":20},
		{"id":"warehouse","title":"南の倉庫","centreXZ":Vector2(72,119),"width":16,"depth":12,"storeys":1,"orientation":0.0,"kind":"warehouse","seed":45,"detail_level":0},
		{"id":"town_hall","title":"市庁舎","centreXZ":Vector2(85,25),"width":16,"depth":14,"storeys":3,"orientation":PI*0.5,"kind":"council","enterable":true,"seed":46,"roof_id":7,"plaster_id":5},
	]
	for spec in specs:
		var info := _build_house(spec)
		var bounds: AABB = info["bounds"]
		_reserved.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(0.75))
		_landmarks.append({"id":spec["id"],"title":spec["title"],"kind":spec["kind"],"position":info["entrance"],"bounds":bounds})
		if info["enterable"]:
			_routes.append({"id":spec["id"]+"_interior","title":spec["title"],"width":2.0,"points":PackedVector3Array(info["route_waypoints"])})
	# These three homes demonstrate furnished interiors without opening every door.
	for i in range(3):
		var p := Vector2(28+float(i)*9,37)
		var info := _build_house({"id":"open_home_%d"%i,"centreXZ":p,"width":6,"depth":7,"storeys":2,"orientation":PI,"enterable":true,"seed":51+i,"plaster_id":[20,11,31][i]})
		var bounds: AABB = info["bounds"]
		_reserved.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(0.75))
		_street("open_home_%d_access"%i,"見学できる民家",2.5,[Vector2(p.x,50),Vector2(p.x,41.5)],"main")
		_routes.append({"id":"open_home_%d_interior"%i,"points":PackedVector3Array(info["route_waypoints"]),"width":2.0})
	_street("town_hall_access","市庁舎への道",4,[Vector2(62,0),Vector2(62,25),Vector2(77,25)],"main")

func _military_quarter() -> void:
	# The training yard keeps the common pavement, with no sand-coloured plate.
	var c := Vector3(-95.5,2,-86)
	for side in [-1.0,1.0]:
		for i in range(11):
			var z := -103.0+float(i)*3
			_box(Vector3(c.x+side*20,3,z),Vector3(0.5,2,0.5),9)
		_box(Vector3(c.x+side*20,2.75,-86),Vector3(0.5,0.5,31),10)
	for i in range(5):
		var p := Vector3(-109+float(i)*7,2,-101)
		_box(p+Vector3(0,1.5,0),Vector3(0.5,3,0.5),9)
		_box(p+Vector3(0,2,0),Vector3(2,2,0.5),11)
		_details.add_box(p+Vector3(0,2,-0.3125),Vector3(1.0,1.0,0.125),21)
		_details.add_box(p+Vector3(0,2,-0.4375),Vector3(0.375,0.375,0.125),20)
	for row in range(3):
		_box(Vector3(-95,2.25+float(row)*0.5,-69+float(row)*1.0),Vector3(28,0.5,1.0),9)
	_box(Vector3(-115.5,3.25,-83),Vector3(1,2.5,4),0)
	_build_house({"id":"barracks_west","centreXZ":Vector2(-105,-43),"width":12,"depth":9,"storeys":2,"roof_id":7,"kind":"barracks","seed":61,"detail_level":0})
	_build_house({"id":"barracks_east","centreXZ":Vector2(-88,-43),"width":10,"depth":9,"storeys":2,"roof_id":7,"kind":"barracks","seed":62,"detail_level":0})
	_landmarks.append({"id":"training_ground","title":"王国訓練場","kind":"training","position":Vector3(-113,FEET_Y,-84)})
	_landmarks.append({"id":"garrison","title":"駐屯所","kind":"garrison","position":Vector3(-97,FEET_Y,-35)})
	_street("garrison_front","駐屯所前の通り",4,[Vector2(-121,-33),Vector2(-97,-33),Vector2(-80,-33)],"main")
	_street("training_yard_inside","訓練場の通用口",3,[Vector2(-121,-83),Vector2(-112,-83),Vector2(-112,-92)],"main")

func _market() -> void:
	for row in range(2):
		for i in range(6):
			var p := Vector3(-96+float(i)*5.5,2,52+float(row)*12)
			if row==0 and i==0:
				p.x+=1.5 # Keep the southwest street's diagonal corner clear.
			var color := 21 if (i+row)%2==0 else 26
			_details.add_box(p+Vector3(0,0.875,0),Vector3(3.5,0.25,1.5),9)
			# Permanent roofs and supports remain visible in the city overview;
			# only produce and table details use the 90m dressing distance.
			for sx in [-1.75,1.75]:
				for sz in [-0.75,0.75]:
					_box(p+Vector3(sx,1.25,sz),Vector3(0.5,2.5,0.5),10)
			for strip in range(8):
				_box(p+Vector3(-1.75+float(strip)*0.5,2.75,0),Vector3(0.5,0.5,2),color if strip%2==0 else 31)
			for sx in [-1.5,1.5]:
				for sz in [-0.5,0.5]:
					_details.add_box(p+Vector3(sx,0.375,sz),Vector3(0.125,0.75,0.125),10)
			for item in range(5):
				_details.add_box(p+Vector3(-1.25+float(item)*0.625,1.125,0),Vector3(0.375,0.25,0.5),[25,11,28,26,21][(i+item)%5])
	_details.bunting(Vector3(-99,7,58),Vector3(-64,7,58),70)
	for x in [-99.0,-64.0]:
		_details.add_box(Vector3(x,4.5,58),Vector3(0.25,5,0.25),10)
	_flags+=1
	_landmarks.append({"id":"market","title":"商人たちの市場","kind":"market","position":Vector3(-82,FEET_Y,58)})
	_street("market_aisle","市場の通り抜け",4,[Vector2(-102,58),Vector2(-61,58)],"main")

func _frontages(street: Dictionary, detail_level: int) -> void:
	var points: PackedVector2Array = street["planar"]
	for segment in range(points.size()-1):
		var a := points[segment]
		var b := points[segment+1]
		var length := a.distance_to(b)
		var t := (b-a).normalized()
		var n := Vector2(-t.y,t.x)
		var angle := atan2(-t.y,t.x)
		for side in [-1.0,1.0]:
			var travelled := 4.0
			while travelled < length-4.0 and _houses.size()<TARGET_HOUSES:
				var count := 2 if _rng.randf()<0.5 else 3
				var width := 5.0
				var depth := 7.0 if detail_level>0 else 6.0
				var group_width := width*count
				if travelled+group_width>length-2.0:
					count=1
				var group: Array[Dictionary]=[]
				for i in range(count):
					var along := travelled+width*(float(i)+0.5)
					var c: Vector2 = a+t*along+n*side*(float(street["width"])*0.5+depth*0.5+2.0)
					var spec := _house_spec(c,width,depth,angle+(PI if side<0 else 0.0),detail_level)
					if street["district"]=="southwest":
						spec["kind"]="shop" if _rng.randf()<0.6 else "house"
					group.append(spec)
				_try_group(group)
				travelled+=width*count+3.0

func _infill_blocks() -> void:
	# Short connected rows become irregular blocks when cut by the reserved
	# winding streets, courtyards and landmarks. Alternating fronts face the
	# 3m cross alleys; every few homes a 2.5m passage connects those alleys.
	for pass_index in range(2):
		for row in range(25):
			if _houses.size()>=TARGET_HOUSES: return
			var z := -128.0+float(row)*11.0+float(pass_index)*5.5
			if z>140: continue
			var x := -140.0+float((row*7)%13)+float(pass_index)*3.0
			while x<138 and _houses.size()<TARGET_HOUSES:
				var count := 2 if (row+floori(x))%3==0 else 3
				var width := 5.0 if _rng.randf()<0.7 else 6.0
				var depth := 6.0 if row%3==0 else 7.0
				var angle := 0.0 if row%2==0 else PI
				var group: Array[Dictionary]=[]
				for i in range(count):
					group.append(_house_spec(Vector2(x+width*(float(i)+0.5),z),width,depth,angle,0 if absf(x)>60 or z<0 else 1))
				_try_group(group)
				x+=width*count+2.5

func _house_spec(c: Vector2,width: float,depth: float,angle: float,detail_level: int) -> Dictionary:
	_serial+=1
	return {"id":"town_house_%03d"%_serial,"centreXZ":c.snapped(Vector2.ONE*0.5),"width":width,"depth":depth,"storeys":2 if _rng.randf()<0.63 else 3,"orientation":angle,"seed":_serial+100,"plaster_id":[20,20,11,31,25][_rng.randi_range(0,4)],"roof_id":[24,24,25,24,7][_rng.randi_range(0,4)],"detail_level":detail_level,"kind":"house"}

func _compact_infill() -> void:
	# Narrow-fronted houses occupy the leftover triangular and corner plots;
	# they are attached in pairs where space permits, rather than scattered.
	for row in range(56):
		var z := -136.0+float(row)*5.0
		for column in range(57):
			if _houses.size()>=TARGET_HOUSES: return
			var c := Vector2(-140.0+float(column)*5.0+float(row%2)*2.5,z)
			for q in range(2):
				var angle:=float(q)*PI*0.5+(PI if row%2==0 else 0.0)
				var t:=Vector2(cos(angle),-sin(angle))
				var group: Array[Dictionary]=[]
				for i in range(2):
					group.append(_house_spec(c+t*float(i)*4.0,4,5,angle,0))
				_try_group(group)

func _try_group(group: Array[Dictionary]) -> void:
	var valid: Array[bool]=[]
	for spec in group:
		valid.append(_valid_plot(spec))
	for i in range(group.size()):
		if not valid[i] or _houses.size()>=TARGET_HOUSES: continue
		var spec: Dictionary=group[i]
		var angle:=float(spec["orientation"])
		var local_x:=Vector2(cos(angle),-sin(angle))
		spec["shared_left"]=false
		spec["shared_right"]=false
		for neighbour in [i-1,i+1]:
			if neighbour<0 or neighbour>=group.size() or not valid[neighbour]: continue
			var delta: Vector2=group[neighbour]["centreXZ"]-spec["centreXZ"]
			if delta.dot(local_x)<0: spec["shared_left"]=true
			else: spec["shared_right"]=true
		_build_house(spec)

func _valid_plot(spec: Dictionary) -> bool:
	var polygon := _plot_polygon(spec)
	for p in polygon:
		if absf(p.x)>145 or absf(p.y)>145 or absf(p.x)+absf(p.y)>207:
			return false
	var rect := _polygon_rect(polygon)
	for reserved in _reserved:
		if rect.intersects(reserved): return false
	for occupied in _plots:
		if rect.intersects(occupied): return false
	for road in _road_polygons:
		if not Geometry2D.intersect_polygons(polygon,road).is_empty(): return false
	return true

func _plot_polygon(spec: Dictionary) -> PackedVector2Array:
	var c: Vector2=spec["centreXZ"]
	var w:=float(spec["width"])*0.5
	var d:=float(spec["depth"])*0.5
	var angle:=float(spec.get("orientation",0.0))
	var t:=Vector2(cos(angle),-sin(angle))
	var n:=Vector2(sin(angle),cos(angle))
	return PackedVector2Array([c+t*(-w)+n*(-d-1.5),c+t*w+n*(-d-1.5),c+t*w+n*(d+0.75),c-t*w+n*(d+0.75)])

func _polygon_rect(polygon: PackedVector2Array) -> Rect2:
	var minimum:=polygon[0]
	var maximum:=polygon[0]
	for p in polygon:
		minimum=minimum.min(p)
		maximum=maximum.max(p)
	return Rect2(minimum,maximum-minimum)

func _build_house(spec: Dictionary) -> Dictionary:
	var info: Dictionary=House.new().build(_v,_details,spec)
	_houses.append(info)
	_plots.append(_polygon_rect(_plot_polygon(spec)))
	if info["enterable"]: _enterable.append(info)
	return info

func _street_dressing() -> void:
	# Garlands and laundry cross actual reserved alleys above head height.
	for street in _streets:
		if street["district"] not in ["southwest","residential"]: continue
		var points: PackedVector2Array=street["planar"]
		for i in range(points.size()-1):
			var a:=points[i]
			var b:=points[i+1]
			if a.distance_to(b)<9: continue
			var c:=a.lerp(b,0.5)
			var n:=Vector2(-(b-a).normalized().y,(b-a).normalized().x)
			var h:=7.5 if street["district"]=="southwest" else 6.25
			var anchor_a:=_rope_anchor(c,n,h)
			var anchor_b:=_rope_anchor(c,-n,h+0.25)
			if anchor_a.is_empty() or anchor_b.is_empty(): continue
			var p: Vector3=anchor_a["position"]
			var q: Vector3=anchor_b["position"]
			_details.add_box(p,Vector3(0.25,0.375,0.25),10)
			_details.add_box(q,Vector3(0.25,0.375,0.25),10)
			if street["district"]=="southwest":
				_details.bunting(p,q,100+i)
				_flags+=1
			else:
				_details.clothesline(p,q,200+i)
				_clotheslines+=1
	# Door-side clutter stays within each house's frontage, away from the
	# centreline and clear of all advertised entrances.
	for i in range(_houses.size()):
		var info: Dictionary=_houses[i]
		if i%4!=0 or info["enterable"]: continue
		var c: Vector3=info["centre"]
		var angle:=float(info["orientation"])
		var basis:=Basis(Vector3.UP,angle)
		var p:=c+basis*Vector3(float(info["width"])*0.32,0,-float(info["depth"])*0.5-0.375)
		if i%3==0: _details.logpile(p,angle)
		elif i%3==1: _details.bucket(p,angle)
		else: _details.crate(p,angle)

func _rope_anchor(c: Vector2,direction: Vector2,height: float) -> Dictionary:
	var nearest:=18.0
	var result: Dictionary={}
	for house in _houses:
		var centre: Vector3=house["centre"]
		var angle:=float(house["orientation"])
		var tangent:=Vector2(cos(angle),-sin(angle))
		var inward:=Vector2(sin(angle),cos(angle))
		var delta:=c-Vector2(centre.x,centre.z)
		var local_origin:=Vector2(delta.dot(tangent),delta.dot(inward))
		var local_direction:=Vector2(direction.dot(tangent),direction.dot(inward))
		var minimum:=Vector2(-float(house["width"])*0.5,-float(house["depth"])*0.5-0.5)
		var maximum:=Vector2(float(house["width"])*0.5,float(house["depth"])*0.5)
		var near:=0.0
		var far:=18.0
		var intersects:=true
		for axis in range(2):
			if absf(local_direction[axis])<0.0001:
				if local_origin[axis]<minimum[axis] or local_origin[axis]>maximum[axis]: intersects=false
				continue
			var a: float=(minimum[axis]-local_origin[axis])/local_direction[axis]
			var b: float=(maximum[axis]-local_origin[axis])/local_direction[axis]
			near=maxf(near,minf(a,b))
			far=minf(far,maxf(a,b))
		if not intersects or near>far or near<0.5 or near>=nearest: continue
		nearest=near
		var p:=c+direction*(near+0.125)
		result={"position":Vector3(p.x,height,p.y),"house_id":house["id"]}
	return result

func _formal_gardens() -> void:
	_parks.append_array([
		{"id":"royal_forecourt","title":"王の正式庭園","bounds":AABB(Vector3(-46,2,-57),Vector3(92,8,45))},
		{"id":"royal_west","title":"西の並木庭園","bounds":AABB(Vector3(-60,2,-145),Vector3(16,9,85))},
		{"id":"royal_east","title":"東の並木庭園","bounds":AABB(Vector3(44,2,-145),Vector3(16,9,85))},
	])
	for side in [-1.0,1.0]:
		for z in [-45.0,-24.0]:
			var c:=Vector3(side*28,2,z)
			for edge in [-1.0,1.0]:
				_box(c+Vector3(edge*11.75,0.25,0),Vector3(0.5,0.5,14),5)
				_box(c+Vector3(0,0.25,edge*6.75),Vector3(24,0.5,0.5),5)
			for sx in [-1.0,1.0]:
				for sz in [-1.0,1.0]:
					var q:=c+Vector3(sx*5.5,0,sz*3)
					_box(q+Vector3(0,0.25,0),Vector3(9,0.5,4),1)
					for edge in [-1.0,1.0]:
						_box(q+Vector3(edge*4.25,0.75,0),Vector3(0.5,0.5,4),3)
						_box(q+Vector3(0,0.75,edge*1.75),Vector3(8,0.5,0.5),3)
					for fx in [-2.5,0.0,2.5]:
						var f:=q+Vector3(fx,0.625,0)
						_details.add_box(f,Vector3(0.125,0.25,0.125),18)
						_details.add_box(f+Vector3(0,0.25,0),Vector3(0.375,0.25,0.125),21 if sz<0 else 28)
						_details.add_box(f+Vector3(0,0.25,0),Vector3(0.125,0.25,0.375),21 if sz<0 else 28)
		for z in [-51.0,-32.0,-15.0]: _tree(Vector3(side*43,2,z),5)
		for z in [-53.0,-34.0,-15.0]: _details.bench(Vector3(side*11,2,z),side*PI*0.5)
		for z in [-132.0,-113.0,-94.0,-75.0]:
			var p:=Vector3(side*52,2,z)
			_box(p+Vector3(0,0.25,0),Vector3(3,0.5,3),1)
			_tree(p+Vector3.UP*0.5,6)
	# Fountain is a small octagonal basin, not a plaza foundation plate.
	var f:=Vector3(0,2,14)
	for side in [-1.0,1.0]:
		_box(f+Vector3(side*2.5,0.25,0),Vector3(0.5,0.5,4),5)
		_box(f+Vector3(0,0.25,side*2.5),Vector3(4,0.5,0.5),5)
		for other in [-1.0,1.0]: _box(f+Vector3(side*2,0.25,other*2),Vector3(0.5,0.5,0.5),5)
	_details.add_box(f+Vector3(0,0.1875,0),Vector3(4.5,0.125,4.5),15)
	_box(f+Vector3(0,0.5,0),Vector3(1.5,1,1.5),5)
	_box(f+Vector3(0,1.75,0),Vector3(0.5,1.5,0.5),5)
	_box(f+Vector3(0,2.5,0),Vector3(2,0.5,2),5)
	_details.add_box(f+Vector3(0,2.8125,0),Vector3(1.5,0.125,1.5),27)
	_landmarks.append({"id":"central_plaza","title":"中央噴水広場","kind":"plaza","position":Vector3(7,FEET_Y,20)})
	_landmarks.append({"id":"royal_garden","title":"王の正式庭園","kind":"garden","position":Vector3(0,FEET_Y,-10)})
	_viewpoints.append(_walk_view("royal_garden","庭園から仰ぐ王城",Vector2(0,-10),Vector3(0,50,-99)))

func _neighbourhood_parks() -> void:
	for spec in [{"id":"east_park","c":Vector2(44,23),"size":Vector2(22,14)},{"id":"southwest_court","c":Vector2(-31,77),"size":Vector2(12,11)}]:
		var c: Vector2=spec["c"]
		var size: Vector2=spec["size"]
		var rect:=Rect2(c-size*0.5,size)
		_reserved.append(rect.grow(0.75))
		_parks.append({"id":spec["id"],"title":"街角の小公園","bounds":AABB(Vector3(rect.position.x,2,rect.position.y),Vector3(size.x,7,size.y))})
		for side in [-1.0,1.0]:
			var p:=Vector3(c.x+side*(size.x*0.5-3),2,c.y)
			_box(p+Vector3(0,0.25,0),Vector3(3,0.5,size.y-3),1)
			_tree(p,4.5)
			_details.bench(Vector3(c.x,2,c.y+side*(size.y*0.5-1.5)),0 if side<0 else PI)

func _tree(pos: Vector3,height: float) -> void:
	_box(pos+Vector3(0,height*0.35,0),Vector3(0.5,height*0.7,0.5),10)
	var radius:=2.0 if height<5.5 else 2.5
	_box(pos+Vector3(0,height*0.65,0),Vector3(radius*2,2.0,radius*1.5),3)
	_box(pos+Vector3(0,height*0.7,0),Vector3(radius*1.5,2.0,radius*2),1)
	_box(pos+Vector3(0,height*0.95,0),Vector3(radius,1.0,radius),18)

func _walk_view(id: String,title: String,p: Vector2,target: Vector3) -> Dictionary:
	var position:=Vector3(p.x,FEET_Y,p.y)
	var delta:=target-(position+Vector3.UP*1.65)
	return {"id":id,"title":title,"position":position,"yaw_degrees":rad_to_deg(atan2(-delta.x,-delta.z)),"pitch_degrees":rad_to_deg(atan2(delta.y,Vector2(delta.x,delta.z).length()))}

func _box(c: Vector3,size: Vector3,id: int) -> void:
	var lo:=c-size*0.5
	var hi:=c+size*0.5
	_v.box(Vector3i(floori(lo.x*2+0.0001),floori(lo.y*2+0.0001),floori(lo.z*2+0.0001)),Vector3i(ceili(hi.x*2-0.0001),ceili(hi.y*2-0.0001),ceili(hi.z*2-0.0001)),id)
