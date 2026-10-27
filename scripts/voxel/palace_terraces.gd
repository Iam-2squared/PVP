extends RefCounted
## The castle's new ceremonial approach. All surfaces use the same 0.5m grid
## as the palace; the generous 1.5m treads allow the player to climb naturally.
const STONE:=4
const LIGHT:=5
const DARK:=6
const GOLD:=17
const HEDGE:=18
const SOIL:=2
var _v: Variant

func build(volume: Variant) -> Dictionary:
	_v=volume
	var tiers: Array[Dictionary]=[
		{"id":"arrival_terrace","title":"王城・迎賓のテラス","half_width":62.0,"back":-146.0,"front":-18.0,"base":2.0,"level":6.0},
		{"id":"ceremonial_terrace","title":"王城・儀礼のテラス","half_width":55.0,"back":-143.0,"front":-34.0,"base":6.0,"level":10.0},
		{"id":"royal_terrace","title":"王城・王のテラス","half_width":47.0,"back":-140.0,"front":-50.0,"base":10.0,"level":14.0}]
	for tier in tiers: _terrace(tier)
	# Gardens are inset into proper stone planters, leaving broad paved courts.
	for side in [-1.0,1.0]:
		_planter(Vector3(side*31,6,-27),17,3)
		_planter(Vector3(side*30,10,-43),14,3)
		_planter(Vector3(side*28,14,-59),13,3)
		_planter(Vector3(side*43,14,-102),3,18)
	var flights: Array[Dictionary]=[
		{"start":-12.0,"base":2.0,"width":18.0},
		{"start":-30.0,"base":6.0,"width":16.0},
		{"start":-46.0,"base":10.0,"width":14.0}]
	# Cut every tier, coping and parapet before laying the tread surfaces.
	for flight in flights:
		var w: float=flight["width"]*0.5
		var z: float=flight["start"]
		var y: float=flight["base"]
		_box(Vector3(-w-0.5,y,z-12),Vector3(w+0.5,y+7,z),0)
	for flight in flights: _flight(flight)
	# Thin inlaid bands emphasize the shared axis without raising the paving.
	for court in [[6.0,-30.0,-24.0,10.0],[10.0,-46.0,-42.0,9.0],[14.0,-64.5,-58.0,8.0]]:
		for side in [-1.0,1.0]:
			var x: float=side*float(court[3])
			_box(Vector3(x-0.25,court[0]-0.5,court[1]),Vector3(x+0.25,court[0],court[2]),DARK)
	var points: Array[Vector3]=[Vector3(0,2.15,-10),Vector3(0,6.15,-26),Vector3(0,6.15,-28),Vector3(0,10.15,-44),Vector3(0,14.15,-61.5),Vector3(0,15.15,-69)]
	var terraces: Array[Dictionary]=[]
	for tier in tiers:
		terraces.append({"id":tier["id"],"title":tier["title"],"level":tier["level"],"bounds":AABB(Vector3(-tier["half_width"],tier["base"],tier["back"]),Vector3(tier["half_width"]*2,tier["level"]-tier["base"],tier["front"]-tier["back"]))})
	return {"bounds":AABB(Vector3(-62,2,-146),Vector3(124,14.5,135.5)),"terraces":terraces,"stairs":[{"id":"terrace_grand_stair","title":"王城大階段","levels":[2.0,6.0,10.0,14.0,15.0],"width":18.0,"flight_widths":[18.0,16.0,14.0],"step_height":0.5,"step_depth":1.5,"waypoints":points}],"route_waypoints":[{"id":"grand_stairs","points":points}],"landmarks":[{"id":"palace_arrival_terrace","title":"迎賓のテラス","position":Vector3(0,6.15,-27),"kind":"palace"},{"id":"palace_ceremonial_terrace","title":"儀礼のテラス","position":Vector3(0,10.15,-44),"kind":"palace"},{"id":"palace_royal_terrace","title":"王のテラス","position":Vector3(0,14.15,-61.5),"kind":"palace"}],"viewpoints":[{"id":"palace_terrace_arrival","title":"王城・迎賓のテラス","position":Vector3(18,6.15,-27),"yaw_degrees":-16.0,"pitch_degrees":22.0},{"id":"palace_terrace_ceremonial","title":"王城・儀礼のテラス","position":Vector3(-18,10.15,-44),"yaw_degrees":20.0,"pitch_degrees":21.0}]}

func _box(a: Vector3,b: Vector3,id: int) -> void:
	_v.box(Vector3i(roundi(a.x*2),roundi(a.y*2),roundi(a.z*2)),Vector3i(roundi(b.x*2),roundi(b.y*2),roundi(b.z*2)),id)

func _terrace(t: Dictionary) -> void:
	var w: float=t["half_width"]
	var back: float=t["back"]
	var front: float=t["front"]
	var base: float=t["base"]
	var top: float=t["level"]
	# Hollow retaining construction avoids a huge buried solid block. The paved
	# slab, edge walls and buttresses remain continuous solid walking geometry.
	_box(Vector3(-w,top-0.5,back),Vector3(w,top,front),STONE)
	_box(Vector3(-w,base,back),Vector3(w,top,back+1.5),DARK)
	for x in [-w,w-1.5]: _box(Vector3(x,base,back),Vector3(x+1.5,top,front),DARK)
	_box(Vector3(-w,base,front-1.5),Vector3(w,top,front-0.5),DARK)
	# Horizontal string courses and light coping separate the three elevations.
	for y in [base+0.5,top-1.0]:
		_box(Vector3(-w,y,front-1.5),Vector3(w,y+0.5,front),LIGHT)
		for x in [-w,w-0.5]: _box(Vector3(x,y,back),Vector3(x+0.5,y+0.5,front),LIGHT)
	_box(Vector3(-w,top-0.5,front-2),Vector3(w,top,front),LIGHT)
	for x in [-w,w-1]: _box(Vector3(x,top-0.5,back),Vector3(x+1,top,front),LIGHT)
	# Recessed blind arcades and pilasters articulate the exposed retaining face.
	for x in range(-int(w)+6,int(w)-4,8):
		if absf(x)<12: continue
		_blind_arch(float(x),front,base)
	for x in range(-int(w)+2,int(w),8):
		if absf(x)<11: continue
		_box(Vector3(x-0.75,base,front-2),Vector3(x+0.75,top,front),STONE)
		_box(Vector3(x-1,top-1,front-2),Vector3(x+1,top-0.5,front),LIGHT)
	# Balustrades, punctuated by carved piers, frame the courts and their drops.
	_rail(Vector3(-w+1,top,back+1),Vector3(-w+1,top,front-1))
	_rail(Vector3(w-1,top,back+1),Vector3(w-1,top,front-1))
	_rail(Vector3(-w+1,top,back+1),Vector3(w-1,top,back+1))
	_rail(Vector3(-w+1,top,front-1),Vector3(-11,top,front-1))
	_rail(Vector3(11,top,front-1),Vector3(w-1,top,front-1))
	for x in [-w+1,-11.0,11.0,w-1]: _pier(Vector3(x,top,front-1))

func _blind_arch(x: float,front: float,base: float) -> void:
	# A one-cell recess with a stepped arch leaves the retaining wall intact.
	_box(Vector3(x-2,base+0.5,front-1),Vector3(x+2,base+2.5,front),0)
	_box(Vector3(x-1.5,base+2.5,front-1),Vector3(x+1.5,base+3,front),0)
	for side in [-1.0,1.0]: _box(Vector3(x+side*2-0.25,base+0.5,front-1),Vector3(x+side*2+0.25,base+2.5,front-0.5),LIGHT)
	for span in [[-2.0,-1.5,2.5],[-1.5,-0.5,3.0],[-0.5,0.5,3.5],[0.5,1.5,3.0],[1.5,2.0,2.5]]:
		_box(Vector3(x+span[0],base+span[2]-0.5,front-1),Vector3(x+span[1],base+span[2],front-0.5),LIGHT)
	_box(Vector3(x-2.5,base,front-1.5),Vector3(x+2.5,base+0.5,front-0.5),STONE)

func _rail(a: Vector3,b: Vector3) -> void:
	var direction: Vector3=(b-a).normalized()
	var length:=a.distance_to(b)
	for i in range(ceili(length*2)+1):
		var p:=a+direction*minf(i*0.5,length)
		_box(p+Vector3(-0.25,1,-0.25),p+Vector3(0.25,1.5,0.25),LIGHT)
		if i%3==0:
			_box(p+Vector3(-0.25,0,-0.25),p+Vector3(0.25,1.25,0.25),LIGHT)
			_box(p+Vector3(-0.5,0,-0.5),p+Vector3(0.5,0.5,0.5),STONE)
		if i%16==0: _pier(p)

func _pier(p: Vector3) -> void:
	_box(p+Vector3(-0.75,0,-0.75),p+Vector3(0.75,0.5,0.75),LIGHT)
	_box(p+Vector3(-0.5,0.5,-0.5),p+Vector3(0.5,1.75,0.5),STONE)
	_box(p+Vector3(-0.75,1.5,-0.75),p+Vector3(0.75,2,0.75),LIGHT)
	_box(p+Vector3(-0.25,2,-0.25),p+Vector3(0.25,2.5,0.25),GOLD)

func _planter(p: Vector3,width: float,depth: float) -> void:
	var half:=Vector3(width*0.5,0,depth*0.5)
	_box(p-half,p+half+Vector3(0,0.5,0),LIGHT)
	_box(p-half+Vector3(0.5,0.5,0.5),p+half+Vector3(-0.5,0.75,-0.5),SOIL)
	_box(p-half+Vector3(1,0.5,1),p+half+Vector3(-1,1.5,-1),HEDGE)

func _flight(f: Dictionary) -> void:
	var width: float=f["width"]
	var start: float=f["start"]
	var base: float=f["base"]
	var half:=width*0.5
	for step in range(8):
		var z:=start-(step+1)*1.5
		var top:=base+(step+1)*0.5
		_box(Vector3(-half,base-0.5,z),Vector3(half,top,z+1.5),STONE)
		_box(Vector3(-half,top-0.5,z),Vector3(half,top,z+1.5),LIGHT)
		# A solid sculpted cheek and open balusters follow the exact tread levels.
		for side in [-1.0,1.0]:
			var x: float=side*(half+0.5)
			_box(Vector3(x-0.5,base-0.5,z),Vector3(x+0.5,top+0.5,z+1.5),STONE)
			_box(Vector3(x-0.5,top+1.5,z),Vector3(x+0.5,top+2,z+1.5),LIGHT)
			_box(Vector3(x-0.25,top+0.5,z+0.5),Vector3(x+0.25,top+1.5,z+1),LIGHT)
	for side in [-1.0,1.0]:
		_pier(Vector3(side*(half+0.5),base,start+0.5))
		_pier(Vector3(side*(half+0.5),base+4,start-12.5))
