extends RefCounted
## Planned, compact octagonal capital: attached street walls, rear service alleys,
## coherent district palettes and public courts. All town feet remain at 2m.

const House = preload("res://scripts/voxel/house_builder.gd")
const Civic = preload("res://scripts/voxel/civic_buildings.gd")
const Details = preload("res://scripts/voxel/detail_builder.gd")
const TARGET_HOUSES := 580
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
var _ground_regions: Array[Dictionary] = []
var _reserved: Array[Rect2] = []
var _plots: Array[PackedVector2Array] = []
var _road_polygons: Array[PackedVector2Array] = []
var _enterable: Array[Dictionary] = []
var _serial := 0
var _clotheslines := 0
var _flags := 0
var _terraces := 0
var _block_rows := 0
var _corner_terraces := 0
var _roof_area := 0.0
var _life_stats: Dictionary = {}

func build(volume: Variant) -> Dictionary:
	_v = volume
	_details = Details.new()
	_houses.clear()
	_streets.clear()
	_routes.clear()
	_landmarks.clear()
	_viewpoints.clear()
	_parks.clear()
	_ground_regions.clear()
	_reserved.clear()
	_plots.clear()
	_road_polygons.clear()
	_enterable.clear()
	_serial = 0
	_clotheslines = 0
	_flags = 0
	_terraces = 0
	_block_rows = 0
	_corner_terraces = 0
	_roof_area = 0.0
	_life_stats.clear()
	_street_plan()
	_reserve_major_areas()
	_civic_buildings()
	_featured_shops()
	_military_quarter()
	_market()
	_formal_forecourt()
	_neighbourhood_parks()
	_royal_street_frontages()
	_planned_southern_blocks()
	_planned_northern_blocks()
	_perimeter_street_frontages()
	_octagonal_frontages()
	_street_dressing()
	if ResourceLoader.exists("res://scripts/voxel/street_life.gd"):
		var street_life = load("res://scripts/voxel/street_life.gd").new()
		_life_stats = street_life.dress(_details,_houses,_streets,_v)
	_viewpoints.append_array([
		_walk_view("town_south_gate","南門から王都へ",Vector2(0,146),Vector3(0,38,-75)),
		_walk_view("southwest_shambles","商店街の張出し家並み",Vector2(-65,46),Vector3(-104,7,46)),
		_walk_view("residential_laundry","洗濯物の裏路地",Vector2(65,96),Vector3(93,6,96)),
	])
	_detail_root = _details.finish()
	var stats: Dictionary = _detail_root.get_meta("detail_stats", {}).duplicate()
	stats["clotheslines"] = _clotheslines
	stats["bunting_lines"] = _flags
	stats["street_life"] = _life_stats
	var attached := 0
	var fronts := 0
	for house in _houses:
		if house.get("shared_left",false) or house.get("shared_right",false): attached += 1
		if int(house.get("detail_level",0)) > 0: fronts += 1
	return {
		"house_count":_houses.size(), "houses":_houses.duplicate(true),
		"streets":_streets.duplicate(true), "route_waypoints":_routes.duplicate(true),
		"landmarks":_landmarks.duplicate(true), "viewpoints":_viewpoints.duplicate(true),
		"enterable_buildings":_enterable.duplicate(true), "parks":_parks.duplicate(true),
		"ground_regions":_ground_regions.duplicate(true),
		"dressingstats":stats, "ground_top":2.0, "adds_road_plates":false,
		"layout_stats":{"terraces":_terraces,"block_rows":_block_rows,"corner_terraces":_corner_terraces,"attached_houses":attached,"featured_frontages":fronts,"roof_footprint_m2":snappedf(_roof_area,0.1),"planning":"courtyard street blocks clipped to the regular octagonal perimeter","rear_alleys_m":2.0},
		"capture_viewpoints":[{"id":"town_overview","position":Vector3(104,125,170),"target":Vector3(0,15,-15)}],
		"districts":["西の商店街", "南西の古い連棟街", "南東の職人住宅街", "東の公共区", "北の工房街"],
		"reserved_wall_stair_bases":[Vector2(-88,130),Vector2(-130,-88),Vector2(88,-130),Vector2(130,88)],
	}

func take_details() -> Node3D:
	var result := _detail_root
	_detail_root = null
	return result

func _street_plan() -> void:
	_street("south_royal","南門大通り",12,[Vector2(0,153),Vector2(0,35)],"main_avenue")
	_street("west_royal","西門大通り",10,[Vector2(-153,0),Vector2(0,0)],"main_avenue")
	_street("east_royal","東門大通り",10,[Vector2(0,0),Vector2(153,0)],"main_avenue")
	_street("plaza_west_arc","噴水西の回り道",7,[Vector2(0,35),Vector2(-10,28),Vector2(-10,0),Vector2(0,-10)],"main_avenue")
	_street("plaza_east_arc","噴水東の回り道",7,[Vector2(0,35),Vector2(10,28),Vector2(10,0),Vector2(0,-10)],"main_avenue")
	for z in [26.0,46.0,66.0,86.0,106.0,126.0,146.0]:
		var limit := minf(143.0,211.0-z)
		_street("south_cross_%d"%int(z),"南市街の横通り",4.5,[Vector2(-limit,z),Vector2(-8,z)],"old_quarter")
		_street("east_cross_%d"%int(z),"東市街の横通り",4.5,[Vector2(8,z),Vector2(limit,z)],"poor_quarter")
	for side in [-1.0,1.0]:
		for x in [31.0,65.0,99.0,133.0]:
			var limit := minf(146.0,211.0-x)
			_street("south_long_%d_%d"%[int(side),int(x)],"区画を結ぶ街路",4.5,[Vector2(side*x,0),Vector2(side*x,limit)],"old_quarter" if side<0 else "poor_quarter")
		# Two metre rear alleys separate the paired street-facing terraces.
		for z in [15.5,36.0,56.0,76.0,96.0,116.0,136.0]:
			var limit := minf(140.0,207.0-z)
			_street("rear_%d_%d"%[int(side),int(z)],"連棟の裏路地",2,[Vector2(side*9,z),Vector2(side*limit,z)],"old_quarter" if side<0 else "poor_quarter")
		for x in [70.0,106.0,137.0]:
			var north := -minf(137.0,211.0-x)
			_street("north_long_%d_%d"%[int(side),int(x)],"北街区の縦通り",4.5,[Vector2(side*x,-4),Vector2(side*x,north)],"northwest" if side<0 else "northeast")
		for z in [-10.0,-34.0,-54.0,-74.0,-94.0,-114.0,-134.0]:
			var limit := minf(143.0,211.0-absf(z))
			if limit>72:
				_street("north_cross_%d_%d"%[int(side),int(absf(z))],"北街区の横通り",4.5,[Vector2(side*67,z),Vector2(side*limit,z)],"northwest" if side<0 else "northeast")
	# The continuous ground patrol route follows the regular octagon corners.
	_street("octagon_patrol","八角城壁の内周路",4,[Vector2(-67,-146),Vector2(-148,-65),Vector2(-148,65),Vector2(-65,148),Vector2(65,148),Vector2(148,65),Vector2(148,-65),Vector2(67,-146)],"patrol")
	_street("north_service","王城裏の通り",4,[Vector2(-70,-140),Vector2(-64,-149),Vector2(64,-149),Vector2(70,-140)],"patrol")
	_street("north_gate_access","北門の接続路",4,[Vector2(0,-156),Vector2(0,-149)],"patrol")
	_street("guild_access","ギルドの正面道",4,[Vector2(-91,0),Vector2(-91,-8),Vector2(-91,-11)],"civic")
	_street("tavern_access","酒場の横路地",3,[Vector2(-109,26),Vector2(-109,17.5),Vector2(-112.5,17.5)],"market")
	_street("weapon_access","武器店への小道",3,[Vector2(-54,26),Vector2(-54,23)],"market")
	_street("forge_access","鍛冶屋への小道",3,[Vector2(-118,46),Vector2(-118,48)],"old_quarter")
	_street("apothecary_access","薬屋への小道",3,[Vector2(124,-10),Vector2(124,-17)],"northeast")
	_street("inn_access","宿屋への小道",3,[Vector2(99,56),Vector2(111,56)],"civic")
	_street("town_hall_access","市庁舎への道",4,[Vector2(65,0),Vector2(65,15),Vector2(77,15)],"civic")
	_street("church_approach","教会正面の道",5,[Vector2(96,-54),Vector2(96,-60.5)],"civic")
	_street("southwest_stair_access","南西城壁階段",4,[Vector2(-65,126),Vector2(-83,126),Vector2(-88,130)],"patrol")
	_street("northwest_stair_access","北西城壁階段",4,[Vector2(-137,-74),Vector2(-137,-79),Vector2(-130,-88)],"patrol")
	_street("northeast_stair_access","北東城壁階段",4,[Vector2(70,-134),Vector2(82,-134),Vector2(88,-130)],"patrol")
	_street("southeast_stair_access","南東城壁階段",4,[Vector2(133,66),Vector2(137,77),Vector2(130,88)],"patrol")

func _street(id: String,title: String,width: float,points: Array,district: String) -> void:
	# Local service streets stop at public buildings and the enclosed yard.
	# Each resulting piece remains linked by the surrounding cross streets.
	var obstacles: Array[Rect2] = []
	if id.begins_with("north_long") or id.begins_with("north_cross"):
		obstacles.assign([Rect2(-117,-105,43,40),Rect2(-105,-31,28,22),Rect2(-112,-49,36,12),Rect2(81,-101,30,43)])
	elif id.begins_with("rear_"):
		obstacles.assign([Rect2(-128,6,18,18),Rect2(-59,13,10,10),Rect2(76,6,19,19),Rect2(110,50,14,13),Rect2(-123,48,10,10),Rect2(28,10,35,27)])
	elif id=="south_long_-1_99":
		obstacles.assign([Rect2(-109,15,41,21)])
	if obstacles.is_empty():
		_write_street(id,title,width,points,district)
		return
	var serial := 0
	for i in range(points.size()-1):
		var fragments: Array[PackedVector2Array] = [PackedVector2Array([points[i],points[i+1]])]
		for obstacle in obstacles:
			var remaining: Array[PackedVector2Array] = []
			for fragment in fragments:
				remaining.append_array(_cut_segment(fragment[0],fragment[1],obstacle.grow(0.75)))
			fragments=remaining
		for fragment in fragments:
			if fragment[0].distance_to(fragment[1])<1.5: continue
			_write_street(id+"_part%d"%serial,title,width,Array(fragment),district)
			serial += 1

func _cut_segment(a: Vector2,b: Vector2,rect: Rect2) -> Array[PackedVector2Array]:
	var delta := b-a
	var near := 0.0
	var far := 1.0
	for axis in range(2):
		if absf(delta[axis])<0.0001:
			if a[axis]<rect.position[axis] or a[axis]>rect.end[axis]: return [PackedVector2Array([a,b])]
		else:
			var entry: float = (rect.position[axis]-a[axis])/delta[axis]
			var exit: float = (rect.end[axis]-a[axis])/delta[axis]
			near=maxf(near,minf(entry,exit))
			far=minf(far,maxf(entry,exit))
	if near>=far: return [PackedVector2Array([a,b])]
	var result: Array[PackedVector2Array] = []
	if near>0: result.append(PackedVector2Array([a,a+delta*near]))
	if far<1: result.append(PackedVector2Array([a+delta*far,b]))
	return result

func _write_street(id: String,title: String,width: float,points: Array,district: String) -> void:
	var world_points := PackedVector3Array()
	var planar := PackedVector2Array()
	for p: Vector2 in points:
		world_points.append(Vector3(p.x,FEET_Y,p.y))
		planar.append(p)
	_streets.append({"id":id,"title":title,"width":width,"points":world_points,"planar":planar,"district":district})
	_routes.append({"id":id,"title":title,"width":width,"points":world_points})
	for i in range(planar.size()-1):
		var t := (planar[i+1]-planar[i]).normalized()
		# Roof eaves may project over a street; walking clearance stays at ground.
		var n := Vector2(-t.y,t.x)*(width*0.5)
		var a := planar[i]-t*0.25
		var b := planar[i+1]+t*0.25
		_road_polygons.append(PackedVector2Array([a+n,b+n,b-n,a-n]))

func _reserve_major_areas() -> void:
	_reserved.append_array([
		Rect2(-64,-152,128,141),Rect2(-18,-10,36,45),
		Rect2(-116,-104,41,36),Rect2(-113,-50,37,17),
		Rect2(-108,16,39,20),
	])
	for p in [Vector2(-88,130),Vector2(-130,-88),Vector2(88,-130),Vector2(130,88)]:
		_reserved.append(Rect2(p-Vector2.ONE*5.5,Vector2.ONE*11))
	_ground_regions.append_array([
		{"id":"northwest","kind":"military","bounds":Rect2(-145,-145,81,137)},
		{"id":"northeast","kind":"civic","bounds":Rect2(64,-145,81,137)},
		{"id":"west_guild","kind":"cobble","bounds":Rect2(-145,-65,81,73)},
		{"id":"east_civic","kind":"cobble","bounds":Rect2(8,8,137,38)},
		{"id":"southwest","kind":"old_quarter","bounds":Rect2(-145,46,137,100)},
		{"id":"southeast","kind":"poor_quarter","bounds":Rect2(8,46,137,100)},
		{"id":"market","kind":"market","bounds":Rect2(-120,12,66,35)},
		{"id":"training_yard","kind":"sand","bounds":Rect2(-116,-104,41,36)},
	])

func _civic_buildings() -> void:
	var civic := Civic.new()
	for spec in [
		{"id":"adventurers_guild","title":"冒険者ギルド","kind":"guild","c":Vector2(-91,-19.5),"q":0},
		{"id":"tavern","title":"灯火の酒場","kind":"tavern","c":Vector2(-119,15),"q":1},
		{"id":"church","title":"王都の教会","kind":"church","c":Vector2(96,-80),"q":0},
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
		{"id":"weapon_shop","title":"武器店","centreXZ":Vector2(-54,18),"width":7,"depth":8,"storeys":3,"orientation":PI,"kind":"weapon_shop","enterable":true,"seed":41,"plaster_id":11,"district":"market"},
		{"id":"blacksmith","title":"鍛冶屋","centreXZ":Vector2(-118,53),"width":8,"depth":8,"storeys":2,"orientation":0.0,"kind":"blacksmith","enterable":true,"seed":42,"plaster_id":25,"district":"old_quarter","weathering":1},
		{"id":"apothecary","title":"薬屋","centreXZ":Vector2(124,-22),"width":6,"depth":8,"storeys":2,"orientation":PI,"kind":"shop","enterable":true,"seed":43,"plaster_id":31,"roof_id":7,"district":"northeast"},
		{"id":"inn","title":"東の宿屋","centreXZ":Vector2(117,56),"width":10,"depth":10,"storeys":3,"orientation":PI*0.5,"kind":"inn","enterable":true,"seed":44,"plaster_id":20,"district":"civic"},
		{"id":"town_hall","title":"市庁舎","centreXZ":Vector2(85,15),"width":16,"depth":14,"storeys":3,"orientation":PI*0.5,"kind":"council","enterable":true,"seed":46,"roof_id":7,"plaster_id":5,"district":"civic"},
	]
	for spec in specs:
		var info := _build_house(spec)
		var bounds: AABB = info["bounds"]
		_reserved.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(0.5))
		_landmarks.append({"id":spec["id"],"title":spec["title"],"kind":spec["kind"],"position":info["entrance"],"bounds":bounds})
		_routes.append({"id":spec["id"]+"_interior","title":spec["title"],"width":2.0,"points":PackedVector3Array(info["route_waypoints"])})
	for i in range(3):
		var p := Vector2([21.0,43.0,51.0][i],32)
		var info := _build_house({"id":"open_home_%d"%i,"centreXZ":p,"width":6,"depth":6,"storeys":2,"orientation":0.0,"enterable":true,"seed":51+i,"plaster_id":[20,11,31][i],"district":"main_avenue","detail_level":1})
		var bounds: AABB = info["bounds"]
		_reserved.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(0.25))
		_street("open_home_%d_access"%i,"見学できる民家",2,[Vector2(p.x,26),Vector2(p.x,28)],"civic")
		_routes.append({"id":"open_home_%d_interior"%i,"points":PackedVector3Array(info["route_waypoints"]),"width":2.0})

func _military_quarter() -> void:
	# The full training enclosure receives sand from district_surfaces.gd.
	var c := Vector3(-95.5,2,-86)
	for side in [-1.0,1.0]:
		for i in range(11):
			var z := -103.0+float(i)*3
			if side < 0 and (z < -92 or absf(z+83.0)<3.5): continue
			_box(Vector3(c.x+side*20,3,z),Vector3(0.5,2,0.5),9)
		if side < 0:
			_box(Vector3(c.x-20,2.75,-80.5),Vector3(0.5,0.5,20),10)
		else:
			_box(Vector3(c.x+20,2.75,-86),Vector3(0.5,0.5,31),10)
	# The training enclosure follows the same clipped octagon as its city
	# block, leaving a clear diagonal patrol lane outside the sand court.
	var corner_a := Vector2(-115.5,-92)
	var corner_b := Vector2(-104.5,-103)
	for step in range(32):
		var p := corner_a.lerp(corner_b,float(step)/31.0)
		_box(Vector3(p.x,2.75,p.y),Vector3(0.5,0.5,0.5),10)
	for step in range(6):
		var p := corner_a.lerp(corner_b,float(step)/5.0)
		_box(Vector3(p.x,3,p.y),Vector3(0.5,2,0.5),9)
	for i in range(5):
		var p := Vector3(-105+float(i)*7,2,-101)
		_box(p+Vector3(0,1.5,0),Vector3(0.5,3,0.5),9)
		_box(p+Vector3(0,2,0),Vector3(2,2,0.5),11)
		_details.add_box(p+Vector3(0,2,-0.3125),Vector3(1.0,1.0,0.125),21)
		_details.add_box(p+Vector3(0,2,-0.4375),Vector3(0.375,0.375,0.125),20)
	for row in range(3):
		_box(Vector3(-95,2.25+float(row)*0.5,-69+float(row)*1.0),Vector3(28,0.5,1.0),9)
	_box(Vector3(-115.5,3.25,-83),Vector3(1.5,2.5,5),0)
	_build_house({"id":"barracks_west","centreXZ":Vector2(-105,-43),"width":12,"depth":9,"storeys":2,"roof_id":7,"kind":"barracks","seed":61,"detail_level":0})
	_build_house({"id":"barracks_east","centreXZ":Vector2(-88,-43),"width":10,"depth":9,"storeys":2,"roof_id":7,"kind":"barracks","seed":62,"detail_level":0})
	_landmarks.append({"id":"training_ground","title":"王国訓練場","kind":"training","position":Vector3(-113,FEET_Y,-84)})
	_landmarks.append({"id":"garrison","title":"駐屯所","kind":"garrison","position":Vector3(-97,FEET_Y,-35)})
	_street("garrison_front","駐屯所前の通り",4,[Vector2(-121,-34),Vector2(-97,-34),Vector2(-80,-34)],"main")
	_street("training_yard_inside","訓練場の通用口",3,[Vector2(-121,-83),Vector2(-112,-83),Vector2(-112,-92)],"main")


func _market() -> void:
	for row in range(2):
		for i in range(6):
			var p := Vector3(-104+float(i)*5.5,2,18+float(row)*16)
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
	_details.bunting(Vector3(-108,7,27),Vector3(-73,7,27),70)
	for x in [-108.0,-73.0]:
		_details.add_box(Vector3(x,4.5,27),Vector3(0.25,5,0.25),10)
	_flags+=1
	_landmarks.append({"id":"market","title":"商人たちの市場","kind":"market","position":Vector3(-85,FEET_Y,26)})
	_street("market_aisle","市場の通り抜け",4,[Vector2(-109,26),Vector2(-60,26)],"main")


func _royal_street_frontages() -> void:
	# A symmetrical palace-facing street wall gives the E/W royal avenue
	# a formal frontage while leaving the 36m central approach entirely open.
	for side in [-1.0,1.0]:
		for run in range(2):
			var group: Array[Dictionary] = []
			for i in range(4):
				var x := 20.5+float(run)*22.5+float(i)*5.0
				group.append(_house_spec(Vector2(side*x,-8.5),5,5,PI,"main_avenue",1 if i==1 else 0))
			_try_terrace(group)

func _perimeter_street_frontages() -> void:
	# The previously empty strips beside the long western/eastern walls are
	# compact attached courts facing the same four neighbourhood cross roads.
	for side in [-1.0,1.0]:
		for half in [-1.0,1.0]:
			for run in range(2):
				var group: Array[Dictionary] = []
				for i in range(5):
					var z: float = half*(10.0+float(run)*27.5+float(i)*5.0)
					var x: float = side*(142.5 if half<0 else 140.0)
					var angle: float = side*PI*0.5
					var district := ("northwest" if side<0 else "northeast") if half<0 else ("old_quarter" if side<0 else "poor_quarter")
					group.append(_house_spec(Vector2(x,z),5,5 if half<0 else 6,angle,district,0))
				_try_terrace(group)

func _planned_southern_blocks() -> void:
	# Every pair faces its enclosing streets. Backs define the same continuous
	# two metre service alley throughout the district, rather than loose infill.
	for side in [-1.0,1.0]:
		for block in range(7):
			var centres := [11.0,20.0] if block==0 else [12.0+float(block)*20.0,20.0+float(block)*20.0]
			for row in range(2):
				var z: float = centres[row]
				var orientation := 0.0 if row==0 else PI
				for column in range(4):
					var lo: float = [8.5,34.0,68.0,102.0][column]
					var hi: float = [28.5,62.0,96.0,130.0][column]
					var district := "main_avenue" if column==0 else ("old_quarter" if side<0 else "poor_quarter")
					if side<0 and block<2: district="market"
					_place_block_row(side,lo,hi,z,orientation,district,column==0 or (side<0 and block<3))

func _planned_northern_blocks() -> void:
	for side in [-1.0,1.0]:
		for block in range(6):
			var north: float = [-34.0,-54.0,-74.0,-94.0,-114.0,-134.0][block]
			for row in range(2):
				var z := north+6.0+float(row)*8.0
				var orientation := 0.0 if row==0 else PI
				for column in range(2):
					var lo: float = [73.0,109.0][column]
					var hi: float = [103.0,134.0][column]
					_place_block_row(side,lo,hi,z,orientation,"northwest" if side<0 else "northeast",false)

func _place_block_row(side: float,lo: float,hi: float,z: float,angle: float,district: String,featured: bool) -> void:
	var before := _houses.size()
	var span := hi-lo
	var groups: Array[Dictionary] = []
	if span<22.0:
		groups.append({"start":lo,"count":4,"width":5.0})
	elif span<27.0:
		groups.append({"start":lo,"count":5,"width":5.0})
	else:
		# Two three-house terraces share a deliberate 2.5m cross passage.
		var start := snappedf(lo+(span-26.5)*0.5,0.5)
		groups.append({"start":start,"count":3,"width":4.0})
		groups.append({"start":start+14.5,"count":3,"width":4.0})
	for run in groups:
		var group: Array[Dictionary] = []
		for i in range(int(run["count"])):
			var x := float(run["start"])+(float(i)+0.5)*float(run["width"])
			group.append(_house_spec(Vector2(side*x,z),float(run["width"]),6.0,angle,district,1 if featured and i%3==0 else 0))
		_try_terrace(group)
	if _houses.size()>before: _block_rows += 1

func _octagonal_frontages() -> void:
	# Mathematically straight corner frontages complement the clipped blocks
	# wherever a continuous plot remains beside the crossing streets;
	# houses never rotate or scatter to occupy leftover individual gaps.
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			var tangent := Vector2(-sx,sz).normalized()
			var angle := atan2(-tangent.y,tangent.x)
			if sz<0: angle += PI
			var along := 3.0
			while along<98.0:
				var group: Array[Dictionary] = []
				for i in range(3):
					var c := Vector2(sx*136.0,sz*66.0)+tangent*(along+float(i)*4.0)
					var district := ("old_quarter" if sx<0 else "poor_quarter") if sz>0 else ("northwest" if sx<0 else "northeast")
					group.append(_house_spec(c,4,6,angle,district,0))
				var before := _houses.size()
				_try_terrace(group)
				if _houses.size()>before:
					_corner_terraces += 1
					along += 14.5
				else:
					along += 0.5

func _house_spec(c: Vector2,width: float,depth: float,angle: float,district: String,detail_level: int) -> Dictionary:
	_serial += 1
	# Variation is seeded by terrace/district, with continuous roof masses.
	var palette := [20,20,11,25]
	var roofs := [24,24,25,24]
	var weathering := 0
	var style := "workers"
	if district=="main_avenue" or district=="civic":
		palette=[31,20,31,5]
		roofs=[7,24,7,24]
		style="civic"
	elif district=="market":
		palette=[11,20,31,11]
		roofs=[24,24,25,24]
		style="merchant"
	elif district=="old_quarter":
		palette=[25,20,11,25]
		roofs=[25,25,24,25]
		weathering=1
	elif district=="poor_quarter":
		palette=[25,20,25,11]
		roofs=[25,25,24,9]
		weathering=2
		style="poor"
	elif district=="northeast":
		palette=[31,20,11,20]
		roofs=[7,7,24,7]
		style="civic"
	else:
		weathering=1
	var p := posmod(_serial,4)
	return {"id":"town_house_%03d"%_serial,"centreXZ":c.snapped(Vector2.ONE*0.5),"width":width,"depth":depth,"storeys":3 if district in ["main_avenue","market"] or _serial%7==0 else 2,"orientation":angle,"seed":_serial+100,"plaster_id":palette[p],"roof_id":roofs[posmod(floori(float(_serial)/3.0),4)],"detail_level":detail_level,"kind":"shop" if district=="market" and _serial%3==0 else "house","district":district,"district_style":style,"weathering":weathering}

func _try_terrace(group: Array[Dictionary]) -> void:
	var valid: Array[bool] = []
	for spec in group: valid.append(_valid_plot(spec))
	# Never create isolated leftover houses. A partial terrace remains a pair.
	for i in range(group.size()):
		if not valid[i]: continue
		var connected := (i>0 and valid[i-1]) or (i+1<group.size() and valid[i+1])
		if not connected: valid[i]=false
	var built := 0
	for i in range(group.size()):
		if not valid[i] or _houses.size()>=TARGET_HOUSES: continue
		var spec: Dictionary = group[i]
		var angle := float(spec["orientation"])
		var local_x := Vector2(cos(angle),-sin(angle))
		spec["shared_left"]=false
		spec["shared_right"]=false
		for neighbour in [i-1,i+1]:
			if neighbour<0 or neighbour>=group.size() or not valid[neighbour]: continue
			var delta: Vector2 = group[neighbour]["centreXZ"]-spec["centreXZ"]
			if delta.dot(local_x)<0: spec["shared_left"]=true
			else: spec["shared_right"]=true
		_build_house(spec)
		built += 1
	if built>0: _terraces += 1

func _valid_plot(spec: Dictionary) -> bool:
	var polygon := _plot_polygon(spec)
	for p in polygon:
		if absf(p.x)>145.0 or absf(p.y)>144.5 or absf(p.x)+absf(p.y)>207.0: return false
	for reserved in _reserved:
		var r := PackedVector2Array([reserved.position,Vector2(reserved.end.x,reserved.position.y),reserved.end,Vector2(reserved.position.x,reserved.end.y)])
		if not Geometry2D.intersect_polygons(polygon,r).is_empty(): return false
	for occupied in _plots:
		if not Geometry2D.intersect_polygons(polygon,occupied).is_empty(): return false
	for road in _road_polygons:
		if not Geometry2D.intersect_polygons(polygon,road).is_empty(): return false
	return true

func _plot_polygon(spec: Dictionary) -> PackedVector2Array:
	var c: Vector2 = spec["centreXZ"]
	var w := float(spec["width"])*0.5
	var d := float(spec["depth"])*0.5
	var angle := float(spec.get("orientation",0.0))
	var t := Vector2(cos(angle),-sin(angle))
	var n := Vector2(sin(angle),cos(angle))
	# Ground footprint includes entrance piers. Eaves occupy the air above it.
	return PackedVector2Array([c-t*w-n*(d+0.5),c+t*w-n*(d+0.5),c+t*w+n*d,c-t*w+n*d])

func _build_house(spec: Dictionary) -> Dictionary:
	var info: Dictionary = House.new().build(_v,_details,spec)
	info["district"]=spec.get("district","northwest")
	info["seed"]=spec.get("seed",0)
	info["plaster_id"]=spec.get("plaster_id",20)
	_houses.append(info)
	_plots.append(_plot_polygon(spec))
	_roof_area += float(info["width"])*(float(info["depth"])+(1.5 if int(info["storeys"])>1 else 1.0))
	if info["enterable"]: _enterable.append(info)
	return info

func _street_dressing() -> void:
	# Garlands and laundry cross actual reserved alleys above head height.
	for street in _streets:
		if street["district"] not in ["market","old_quarter","poor_quarter"]: continue
		var points: PackedVector2Array=street["planar"]
		for i in range(points.size()-1):
			var a:=points[i]
			var b:=points[i+1]
			if a.distance_to(b)<9: continue
			var c:=a.lerp(b,0.5)
			var n:=Vector2(-(b-a).normalized().y,(b-a).normalized().x)
			var h:=7.5 if street["district"]=="market" else 6.25
			var anchor_a:=_rope_anchor(c,n,h)
			var anchor_b:=_rope_anchor(c,-n,h+0.25)
			if anchor_a.is_empty() or anchor_b.is_empty(): continue
			var p: Vector3=anchor_a["position"]
			var q: Vector3=anchor_b["position"]
			_details.add_box(p,Vector3(0.25,0.375,0.25),10)
			_details.add_box(q,Vector3(0.25,0.375,0.25),10)
			if street["district"]=="market":
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


func _formal_forecourt() -> void:
	# The raised palace gardens are supplied by the terrace builder. This
	# ground-level forecourt stays open all the way to the first grand stair.
	var f := Vector3(0,2,14)
	for side in [-1.0,1.0]:
		_box(f+Vector3(side*2.5,0.25,0),Vector3(0.5,0.5,4),5)
		_box(f+Vector3(0,0.25,side*2.5),Vector3(4,0.5,0.5),5)
		for other in [-1.0,1.0]: _box(f+Vector3(side*2,0.25,other*2),Vector3(0.5,0.5,0.5),5)
	_details.add_box(f+Vector3(0,0.1875,0),Vector3(4.5,0.125,4.5),15)
	_box(f+Vector3(0,0.5,0),Vector3(1.5,1,1.5),5)
	_box(f+Vector3(0,1.75,0),Vector3(0.5,1.5,0.5),5)
	_box(f+Vector3(0,2.5,0),Vector3(2,0.5,2),5)
	_details.add_box(f+Vector3(0,2.8125,0),Vector3(1.5,0.125,1.5),27)
	for side in [-1.0,1.0]:
		for z in [47.0,87.0,127.0]:
			# Small identical plane-tree bays punctuate the formal avenue.
			_tree(Vector3(side*9.5,2,z),5.5)
	_landmarks.append({"id":"central_plaza","title":"中央噴水広場","kind":"plaza","position":Vector3(7,FEET_Y,20)})
	_landmarks.append({"id":"royal_garden","title":"王城の大階段","kind":"garden","position":Vector3(0,FEET_Y,-10)})
	_viewpoints.append(_walk_view("royal_garden","大階段から仰ぐ王城",Vector2(0,-10),Vector3(0,58,-99)))

func _neighbourhood_parks() -> void:
	for spec in [
		{"id":"east_park","title":"東の市民公園","rect":Rect2(29,10,33,27)},
		{"id":"southwest_green","title":"古街区の緑の広場","rect":Rect2(-61,70,24,22)},
		{"id":"church_green","title":"教会の薬草園","rect":Rect2(113,-100,21,37)},
	]:
		var rect: Rect2 = spec["rect"]
		_reserved.append(rect)
		_parks.append({"id":spec["id"],"title":spec["title"],"bounds":AABB(Vector3(rect.position.x,2,rect.position.y),Vector3(rect.size.x,8,rect.size.y))})
		_ground_regions.append({"id":spec["id"],"kind":"park","bounds":rect})
		if spec["id"]=="east_park":
			for p in [Vector2(39,15),Vector2(56,15),Vector2(39,33),Vector2(56,33)]: _tree(Vector3(p.x,2,p.y),5)
			_details.bench(Vector3(46,2,19),0)
			_details.bench(Vector3(46,2,32),PI)
		elif spec["id"]=="southwest_green":
			for p in [Vector2(-56,75),Vector2(-42,75),Vector2(-56,91),Vector2(-42,91)]: _tree(Vector3(p.x,2,p.y),5)
			_details.bench(Vector3(-49,2,78),0)
		else:
			for p in [Vector2(119,-99),Vector2(121,-84),Vector2(119,-66)]: _tree(Vector3(p.x,2,p.y),4.5)
			_details.bench(Vector3(122,2,-78),PI*0.5)

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
