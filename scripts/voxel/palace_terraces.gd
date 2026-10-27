extends RefCounted
## The castle's new ceremonial approach. All surfaces use the same 0.5m grid
## as the palace. Broad upper flights visibly ascend toward the inner court.
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
	# Complete green parterres occupy the old central stair axis. The formal
	# approach now winds around each side, leaving all three central fronts intact.
	_planter(Vector3(0,6,-23.5),30,5)
	_planter(Vector3(0,10,-39.5),26,5)
	_planter(Vector3(0,14,-55.5),22,5)
	for side in [-1.0,1.0]:
		_planter(Vector3(side*43,14,-102),3,18)
		_tree(Vector3(side*59,6,-30))
		_tree(Vector3(side*51,10,-84))
	var flights: Array[Dictionary]=[]
	for side in [-1.0,1.0]:
		flights.append({"start":Vector3(side*50,2,-12),"direction":Vector3.FORWARD,"width":12.0})
		flights.append({"start":Vector3(side*47,6,-30),"direction":Vector3.FORWARD,"width":12.0})
		# Long upper flights rise from the outside toward the castle's center.
		# Their broad inner landings open directly into the entrance court.
		flights.append({"start":Vector3(side*47,10,-57),"direction":Vector3(-side,0,0),"width":12.0,"step_depth":3.0,"clear_before":7.0})
	# Remove only side corridors, including every wall, coping and rail layer.
	for flight in flights: _cut_flight(flight)
	for flight in flights: _flight(flight)
	var stairs: Array[Dictionary]=[]
	var routes: Array[Dictionary]=[]
	for side in [-1.0,1.0]:
		var side_name: String="west" if side<0 else "east"
		var points: Array[Vector3]=[
			Vector3(0,2.15,-8),Vector3(side*50,2.15,-8),Vector3(side*50,2.15,-10),
			Vector3(side*50,6.15,-26),Vector3(side*47,6.15,-27),
			Vector3(side*47,10.15,-44),Vector3(side*52.5,10.15,-45),
			Vector3(side*52.5,10.15,-57),Vector3(side*48.5,10.15,-57),
			Vector3(side*23,14.15,-57),Vector3(side*20.5,14.15,-57),
			Vector3(side*20.5,14.15,-61.5),Vector3(0,14.15,-61.5),Vector3(0,15.15,-69)]
		stairs.append({"id":"terrace_"+side_name+"_stair","title":"王城・西の回り階段" if side<0 else "王城・東の回り階段","levels":[2.0,6.0,10.0,14.0,15.0],"width":12.0,"step_height":0.5,"step_depths":[1.5,1.5,3.0],"waypoints":points,
			"upper_flight":{"bottom":Vector3(side*47,10.15,-57),"top":Vector3(side*23,14.15,-57),"inner_landing":Vector3(side*20.5,14.15,-57),"ascent_direction":Vector3(-side,0,0),"width":12.0,"run":24.0,"step_count":8,"step_height":0.5,"step_depth":3.0,"bounds":AABB(Vector3(23 if side>0 else -47,10,-63),Vector3(24,4,12))}})
		routes.append({"id":"terrace_approach_"+side_name,"points":points})
		# Flush stone bands and landing medallions show the winding route from above.
		_inlay(Vector3(side*50,6,-26),Vector3(side*47,6,-27))
		_inlay(Vector3(side*47,10,-44),Vector3(side*52.5,10,-45))
		_inlay(Vector3(side*52.5,10,-45),Vector3(side*52.5,10,-57))
		_inner_landing(side)
		_inlay(Vector3(side*20.5,14,-57),Vector3(side*20.5,14,-61.5))
		_inlay(Vector3(side*20.5,14,-61.5),Vector3(0,14,-61.5))
	var terraces: Array[Dictionary]=[]
	for tier in tiers:
		terraces.append({"id":tier["id"],"title":tier["title"],"level":tier["level"],"bounds":AABB(Vector3(-tier["half_width"],tier["base"],tier["back"]),Vector3(tier["half_width"]*2,tier["level"]-tier["base"],tier["front"]-tier["back"]))})
	return {
		"bounds":AABB(Vector3(-62,2,-146),Vector3(124,14.5,135.5)),
		"terraces":terraces,"stairs":stairs,"route_waypoints":routes,
		"landmarks":[
			{"id":"palace_arrival_terrace","title":"迎賓のテラス","position":Vector3(0,6.15,-27),"kind":"palace"},
			{"id":"palace_ceremonial_terrace","title":"儀礼のテラス","position":Vector3(0,10.15,-44),"kind":"palace"},
			{"id":"palace_royal_terrace","title":"王のテラス","position":Vector3(0,14.15,-61.5),"kind":"palace"}],
		"viewpoints":[
			{"id":"palace_terrace_arrival","title":"王城・迎賓のテラス","position":Vector3(20,6.15,-27),"yaw_degrees":-16.0,"pitch_degrees":22.0},
			{"id":"palace_terrace_ceremonial","title":"王城・儀礼のテラス","position":Vector3(-18,10.15,-44),"yaw_degrees":20.0,"pitch_degrees":21.0}]}

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
		_blind_arch(float(x),front,base)
	for x in range(-int(w)+2,int(w),8):
		_box(Vector3(x-0.75,base,front-2),Vector3(x+0.75,top,front),STONE)
		_box(Vector3(x-1,top-1,front-2),Vector3(x+1,top-0.5,front),LIGHT)
	# Balustrades, punctuated by carved piers, frame the courts and their drops.
	_rail(Vector3(-w+1,top,back+1),Vector3(-w+1,top,front-1))
	_rail(Vector3(w-1,top,back+1),Vector3(w-1,top,front-1))
	_rail(Vector3(-w+1,top,back+1),Vector3(w-1,top,back+1))
	_rail(Vector3(-w+1,top,front-1),Vector3(w-1,top,front-1))
	for x in [-w+1,0.0,w-1]: _pier(Vector3(x,top,front-1))

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
	_box(p-half+Vector3(0.5,0.5,0.5),p+half+Vector3(-0.5,1,-0.5),HEDGE)
	# Symmetrical gold flowers punctuate the low, clipped green surface.
	for side in [-1.0,1.0]:
		var x: float=p.x+side*(width*0.5-1.5)
		_box(Vector3(x-0.25,p.y+1,p.z-0.25),Vector3(x+0.25,p.y+1.5,p.z+0.25),GOLD)

func _tree(p: Vector3) -> void:
	_planter(p,5,5)
	_box(p+Vector3(-0.5,0.5,-0.5),p+Vector3(0.5,3.5,0.5),9)
	_box(p+Vector3(-1.5,2.5,-1.5),p+Vector3(1.5,4.5,1.5),HEDGE)
	_box(p+Vector3(-2,3,-1),p+Vector3(2,4,1),3)
	_box(p+Vector3(-1,3,-2),p+Vector3(1,4,2),3)
	_box(p+Vector3(-1,4.5,-1),p+Vector3(1,5.5,1),HEDGE)

func _cut_flight(f: Dictionary) -> void:
	var start: Vector3=f["start"]
	var direction: Vector3=f["direction"]
	var across:=Vector3(-direction.z,0,direction.x)
	var half: float=f["width"]*0.5+1.5
	var run: float=float(f.get("step_depth",1.5))*8
	var a:=start-direction*float(f.get("clear_before",0.0))-across*half
	var b:=start+direction*run+across*half
	_box(Vector3(minf(a.x,b.x),start.y,minf(a.z,b.z)),Vector3(maxf(a.x,b.x),start.y+8,maxf(a.z,b.z)),0)

func _flight(f: Dictionary) -> void:
	var start: Vector3=f["start"]
	var direction: Vector3=f["direction"]
	var across:=Vector3(-direction.z,0,direction.x)
	var half: float=f["width"]*0.5
	var depth: float=f.get("step_depth",1.5)
	var run:=depth*8
	for step in range(8):
		var near:=start+direction*(step*depth)
		var far:=near+direction*depth
		var top:=start.y+(step+1)*0.5
		_flight_box(near-across*half,far+across*half,start.y-0.5,top,STONE)
		_flight_box(near-across*half,far+across*half,top-0.5,top,LIGHT)
		for side in [-1.0,1.0]:
			var edge: Vector3=across*side*(half+0.5)
			_flight_box(near+edge-across*0.5,far+edge+across*0.5,start.y-0.5,top+0.5,STONE)
			_flight_box(near+edge-across*0.5,far+edge+across*0.5,top+1.5,top+2,LIGHT)
			var baluster: Vector3=(near+far)*0.5+edge
			_box(Vector3(baluster.x-0.25,top+0.5,baluster.z-0.25),Vector3(baluster.x+0.25,top+1.5,baluster.z+0.25),LIGHT)
	for side in [-1.0,1.0]:
		# Piers stay on the treads, leaving the lateral landing access clear.
		_pier(start+direction*0.5+across*side*(half+0.5))
		_pier(start+direction*(run+0.5)+across*side*(half+0.5)+Vector3.UP*4)

func _flight_box(a: Vector3,b: Vector3,low: float,high: float,id: int) -> void:
	_box(Vector3(minf(a.x,b.x),low,minf(a.z,b.z)),Vector3(maxf(a.x,b.x),high,maxf(a.z,b.z)),id)

func _inner_landing(side: float) -> void:
	# A broad, flush white court makes the stair's inward arrival unmistakable.
	# It has no transverse rail, pedestal or planting across the entrance path.
	var lo: float=16.0 if side>0 else -23.0
	_box(Vector3(lo,13.5,-62.5),Vector3(lo+7,14,-51.5),LIGHT)
	for x in [lo+0.5,lo+6.0]:
		_box(Vector3(x,13.5,-62.0),Vector3(x+0.5,14,-52.0),DARK)

func _inlay(a: Vector3,b: Vector3) -> void:
	var length:=a.distance_to(b)
	var direction: Vector3=(b-a).normalized()
	for i in range(ceili(length*2)+1):
		var p:=a+direction*minf(i*0.5,length)
		_box(p+Vector3(-0.75,-0.5,-0.75),p+Vector3(0.75,0,0.75),LIGHT)
	for p in [a,b]:
		_box(p+Vector3(-1,-0.5,-1),p+Vector3(1,0,1),DARK)
		_box(p+Vector3(-0.5,-0.5,-0.5),p+Vector3(0.5,0,0.5),LIGHT)
