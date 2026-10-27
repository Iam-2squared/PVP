extends RefCounted
## Tall stone-base / white-core / slender-spire palace with walkable interiors.
const Volume=preload("res://scripts/voxel/volume.gd")
const LEVELS: Array[float]=[3.0,9.0,15.0,21.0,27.0,33.0]
const STONE:=4
const LIGHT:=5
const DARK:=6
const BLUE:=7
const SKY_BLUE:=8
const WOOD:=9
const DARK_WOOD:=10
const GOLD:=17
const CREAM:=20
const RED:=21
const IRON:=22
const BRASS:=23
const GLASS:=27
const FIRE:=28
var _v: Variant
var _floors: Array=[]
var _rooms: Array[Dictionary]=[]
var _doors: Array[Dictionary]=[]
var _stairs: Array[Dictionary]=[]
var _routes: Array[Dictionary]=[]
var _landmarks: Array[Dictionary]=[]
var _lights: Array[Dictionary]=[]
var _furnishings: Array[Dictionary]=[]

func build(volume: Variant,interior_volumes: Array=[]) -> Dictionary:
	_v=volume
	_floors.clear()
	_rooms.clear()
	_doors.clear()
	_stairs.clear()
	_routes.clear()
	_landmarks.clear()
	_lights.clear()
	_furnishings.clear()
	for level in LEVELS:
		var inside=Volume.new()
		_floors.append(inside)
		interior_volumes.append({"volume":inside,"level":level,"title":"王城 %dm階"%int(level),"kind":"floor","bounds":AABB(Vector3(-43,level-0.5,-135),Vector3(86,15,75))})
	_foundation()
	_lower_castle()
	_white_core()
	_towers_and_spires()
	_facade()
	_floor_plates()
	_divisions_and_ceilings()
	_staircases()
	_furnish()
	_final_openings()
	_metadata()
	_disjoint_components()
	var count:=0
	for inside in _floors: count+=inside.cells.size()
	return {"bounds":AABB(Vector3(-43,2,-135),Vector3(86,93,74)),"entry":Vector3(0,3.15,-68),"floor_levels":LEVELS,"upper_tower_levels":[27.0,33.0],"highest_point":94.0,"rooms":_rooms,"doors":_doors,"stairs":_stairs,"route_waypoints":_routes,"landmarks":_landmarks,"lights":_lights,"furnishings":_furnishings,"interior_voxels":count,"room_count":_rooms.size(),"viewpoints":[
		{"id":"palace_front","title":"王城・尖塔の全景","position":Vector3(0,2.15,-8),"yaw_degrees":0.0,"pitch_degrees":24.0},
		{"id":"palace_court","title":"王城・尖頭門","position":Vector3(0,2.15,-51),"yaw_degrees":0.0,"pitch_degrees":15.0},
		{"id":"palace_hall","title":"王城・大広間","position":Vector3(8,3.15,-87),"yaw_degrees":0.0,"pitch_degrees":10.0},
		{"id":"palace_throne","title":"王城・謁見の間","position":Vector3(8,3.15,-114),"yaw_degrees":45.0,"pitch_degrees":4.0},
		{"id":"palace_library","title":"王城・図書室","position":Vector3(28,9.15,-105),"yaw_degrees":0.0,"pitch_degrees":4.0},
		{"id":"palace_bedroom","title":"王城・王の私室","position":Vector3(-12,15.15,-125),"yaw_degrees":-90.0,"pitch_degrees":0.0},
		{"id":"palace_observatory","title":"王城・展望バルコニー","position":Vector3(0,33.15,-79),"yaw_degrees":180.0,"pitch_degrees":-4.0}],"research_features":["Tokyo Cinderella Castle: low polygonal stone base, tiered white core and slender white-gold highest spire","Neuschwanstein: ceremonial arcade","Chambord: independent stairs","Himeji: timber frames","Nintendo/Team-Kyo: furnished voxel interiors"]}

func _box(v: Variant,a: Vector3,b: Vector3,id: int) -> void:
	var lo:=Vector3i(roundi(a.x*2),roundi(a.y*2),roundi(a.z*2))
	var hi:=Vector3i(roundi(b.x*2),roundi(b.y*2),roundi(b.z*2))
	if hi.x>lo.x and hi.y>lo.y and hi.z>lo.z: v.box(lo,hi,id)

func _clear(v: Variant,a: Vector3,b: Vector3) -> void:
	_box(v,a,b,0)

func _floor(v: Variant,x0: float,x1: float,z0: float,z1: float,y: float,id: int=STONE) -> void:
	_box(v,Vector3(x0,y-0.5,z0),Vector3(x1,y,z1),id)

func _shell(v: Variant,x0: float,x1: float,z0: float,z1: float,low: float,high: float,id: int=STONE) -> void:
	_box(v,Vector3(x0,low,z0),Vector3(x0+1,high,z1),id)
	_box(v,Vector3(x1-1,low,z0),Vector3(x1,high,z1),id)
	_box(v,Vector3(x0,low,z0),Vector3(x1,high,z0+1),id)
	_box(v,Vector3(x0,low,z1-1),Vector3(x1,high,z1),id)

func _foundation() -> void:
	# Raised stone follows the footprint; the forecourt shares the city paving.
	for rect in [Rect2(-18,-132,36,56),Rect2(-38,-112,21,32),Rect2(-34,-130,17,22),Rect2(17,-118,21,38),Rect2(-9,-83,18,17)]:
		_box(_v,Vector3(rect.position.x,2,rect.position.y),Vector3(rect.end.x,2.5,rect.end.y),DARK)
	for i in range(2):
		_box(_v,Vector3(-7+i*0.5,2+i*0.5,-67.5-i),Vector3(7-i*0.5,2.5+i*0.5,-64.5-i),STONE if i==0 else LIGHT)

func _cornice(x0: float,x1: float,z0: float,z1: float,y: float,id: int=LIGHT) -> void:
	for z in [z0,z1-0.5]: _box(_v,Vector3(x0-0.5,y,z-0.5),Vector3(x1+0.5,y+0.5,z+1),id)
	for x in [x0,x1-0.5]: _box(_v,Vector3(x-0.5,y,z0),Vector3(x+1,y+0.5,z1),id)

func _crenels(x0: float,x1: float,z: float,y: float) -> void:
	_box(_v,Vector3(x0,y,z),Vector3(x1,y+0.5,z+0.5),LIGHT)
	for x in range(roundi(x0),roundi(x1),2): _box(_v,Vector3(x,y+0.5,z),Vector3(x+1,y+1.5,z+0.5),LIGHT)

func _lower_castle() -> void:
	_shell(_v,-18,18,-121,-76,3,21)
	_shell(_v,-18,18,-132,-118,3,21)
	_shell(_v,-38,-17,-112,-80,3,15)
	_shell(_v,-34,-17,-130,-108,3,21)
	_shell(_v,17,38,-118,-80,3,21)
	_hip(_v,-39,-16,-113,-79,15,9)
	_hip(_v,-35,-16,-131,-107,21,10)
	_hip(_v,16,39,-119,-79,21,12)
	_hip(_v,-19,19,-133,-120,21,10)
	_shell(_v,-9,9,-83,-66,3,15,LIGHT)
	_gable(_v,-10,10,-84,-65.5,15,17)
	for y in [8.0,14.0,20.0]: _cornice(-18,18,-121,-76,y)
	_cornice(-38,-17,-112,-80,14)
	_cornice(-34,-17,-130,-108,20)
	_cornice(17,38,-118,-80,20)
	_cornice(-18,18,-132,-118,20)
	_floor(_v,-17,17,-120,-77,21,LIGHT)
	for z in [-120.0,-77.5]: _crenels(-17,17,z,21)
	for x in [-17.0,16.5]:
		_box(_v,Vector3(x,21,-120),Vector3(x+0.5,22,-77),LIGHT)
		for z in range(-120,-77,2): _box(_v,Vector3(x,22,z),Vector3(x+0.5,22.5,z+1),LIGHT)

func _white_core() -> void:
	_shell(_v,-12,12,-112,-82,21,43,CREAM)
	for y in [26.0,32.0,38.0,42.5]: _cornice(-12,12,-112,-82,y)
	_hip(_v,-13,13,-113,-81,43,14)
	for cx in [-7.0,0.0,7.0]:
		_shell(_v,cx-1.5,cx+1.5,-89,-85,45,49,LIGHT)
		_gable(_v,cx-2,cx+2,-89.5,-84.5,49,3)
		_window_z(_v,cx,-85.5,46,1.5,2)
	_floor(_v,-6,6,-84,-77,33,LIGHT)
	_rail(_v,Vector3(-6,33,-77),Vector3(6,33,-77),LIGHT)
	for x in [-6.0,6.0]:
		_rail(_v,Vector3(x,33,-82),Vector3(x,33,-77),LIGHT)
		_box(_v,Vector3(x-0.5,30,-82),Vector3(x+0.5,33,-79),STONE)
		_box(_v,Vector3(x-0.5,31,-79),Vector3(x+0.5,33,-78),STONE)
	for side in [-1,1]:
		for z in [-109.0,-88.0]:
			var x: float=side*11.5
			_box(_v,Vector3(x-0.75,21,z-0.75),Vector3(x+0.75,43,z+0.75),LIGHT)
			_box(_v,Vector3(x-1,38,z-1),Vector3(x+1,39,z+1),GOLD)
			_spire(x,z,1.5,43,9,CREAM,true)

func _oct(x: float,z: float,r: float) -> bool:
	return absf(x)<=r and absf(z)<=r and absf(x)+absf(z)<=r*1.41421356

func _ring(cx: float,cz: float,r: float,low: float,high: float,id: int,thickness: float=1.0) -> void:
	for ix in range(floori((cx-r-0.5)*2),ceili((cx+r+0.5)*2)):
		for iz in range(floori((cz-r-0.5)*2),ceili((cz+r+0.5)*2)):
			var dx:=ix*0.5+0.25-cx
			var dz:=iz*0.5+0.25-cz
			if _oct(dx,dz,r) and not _oct(dx,dz,maxf(0.0,r-thickness)):
				_box(_v,Vector3(ix*0.5,low,iz*0.5),Vector3(ix*0.5+0.5,high,iz*0.5+0.5),id)

func _spire(cx: float,cz: float,r: float,base: float,rise: float,id: int=BLUE,golden: bool=false) -> void:
	for step in range(roundi(rise*2)):
		var y:=base+step*0.5
		var radius:=r*(1.0-(step+0.5)/(rise*2))
		_ring(cx,cz,radius,y,y+0.5,SKY_BLUE if id==BLUE and step%14==0 else id,0.75)
		if golden and step%8==0: _ring(cx,cz,radius+0.25,y,y+0.5,GOLD,0.5)
	_box(_v,Vector3(cx-0.25,base+rise-1,cz-0.25),Vector3(cx+0.25,base+rise+1,cz+0.25),GOLD)

func _tower(cx: float,cz: float,r: float,base: float,top: float,roof: float,body_id: int=STONE,white_tip: bool=false) -> void:
	if base==3:
		_ring(cx,cz,r+0.5,2,2.5,DARK,r+1)
		_ring(cx,cz,r+0.5,2.5,3,STONE,r+1)
	_ring(cx,cz,r,base,top,body_id)
	if body_id==STONE:
		var stone_top:=minf(top-5,17)
		_ring(cx,cz,r,base,stone_top,DARK)
		for course in range(5,floori(stone_top),3): _ring(cx,cz,r,course,course+0.5,STONE)
	for h in [top-5.0,top-1.5]:
		_ring(cx,cz,r+0.75,h,h+0.5,LIGHT)
		_ring(cx,cz,r+1,h+0.5,h+1,LIGHT)
	for i in range(8):
		var angle:=i*TAU/8
		var p:=Vector3(cx+cos(angle)*(r-0.25),top-5.5,cz+sin(angle)*(r-0.25))
		_box(_v,p+Vector3(-0.5,0,-0.5),p+Vector3(0.5,2,0.5),LIGHT)
	_spire(cx,cz,r+0.5,top,roof,CREAM if white_tip else BLUE,white_tip)
	for y in [base+3.0,top-8.0]:
		if y>top-3: continue
		for side in [-1,1]:
			_window_z(_v,cx,cz+side*(r-0.5),y,1.5,3)
			_window_x(_v,cx+side*(r-0.5),cz,y,1.5,3)

func _towers_and_spires() -> void:
	for side in [-1,1]:
		_tower(side*13,-78,5,3,22,18)
		_tower(side*32,-83,4.5,3,17,15)
		_tower(side*29,-123,4.5,3,23,16)
		_tower(side*13,-109,3.5,21,42 if side<0 else 39,22,CREAM)
		_tower(side*12,-88,3.0,21,35,20,CREAM)
	_tower(5,-94,4.5,31,68,25,CREAM,true)
	_ring(5,-94,3.5,69,73,CREAM,0.5)
	for side in [-1,1]: _box(_v,Vector3(5+side*3.5-0.25,46,-94.25),Vector3(5+side*3.5+0.25,66,-93.75),GOLD)
	_tower(-8,-100,3.5,37,50,26,CREAM)
	for dx in [-2.5,2.5]:
		for dz in [-2.5,2.5]: _spire(5+dx,-94+dz,0.75,68,8,CREAM,true)

func _gable(v: Variant,x0: float,x1: float,z0: float,z1: float,base: float,rise: float) -> void:
	var middle: float=(x0+x1)*0.5
	var half: float=(x1-x0)*0.5
	for ix in range(roundi(x0*2),roundi(x1*2)):
		var x:=ix*0.5
		var y:=snappedf(base+rise*(1.0-absf(x+0.25-middle)/half),0.5)
		_box(v,Vector3(x,y-0.5,z0),Vector3(x+0.5,y+0.5,z1),SKY_BLUE if floori(y*2)%12==0 else BLUE)
		for z in [z0,z1-0.5]: _box(v,Vector3(x,base,z),Vector3(x+0.5,y,z+0.5),LIGHT)
	_box(v,Vector3(middle-0.5,base+rise,z0-0.5),Vector3(middle+0.5,base+rise+0.5,z1+0.5),GOLD)

func _hip(v: Variant,x0: float,x1: float,z0: float,z1: float,base: float,rise: float) -> void:
	# All four faces slope in blue; there is no broad, blank triangular end wall.
	var half:=minf((x1-x0)*0.5,(z1-z0)*0.5)
	for ix in range(roundi(x0*2),roundi(x1*2)):
		for iz in range(roundi(z0*2),roundi(z1*2)):
			var x:=ix*0.5
			var z:=iz*0.5
			var inset:=minf(minf(x+0.25-x0,x1-x-0.25),minf(z+0.25-z0,z1-z-0.25))
			var y:=snappedf(base+rise*inset/half,0.5)
			_box(v,Vector3(x,y-0.5,z),Vector3(x+0.5,y+0.5,z+0.5),SKY_BLUE if floori(y*2)%12==0 else BLUE)

func _window_z(v: Variant,cx: float,z: float,bottom: float,width: float,height: float) -> void:
	_clear(v,Vector3(cx-width*0.5,bottom,z-1),Vector3(cx+width*0.5,bottom+height-1,z+1))
	_clear(v,Vector3(cx-width*0.5+0.5,bottom+height-1,z-1),Vector3(cx+width*0.5-0.5,bottom+height,z+1))
	_box(v,Vector3(cx-width*0.5+0.5,bottom+0.5,z),Vector3(cx+width*0.5-0.5,bottom+height-0.5,z+0.5),GLASS)
	_box(v,Vector3(cx-0.25,bottom,z-0.5),Vector3(cx+0.25,bottom+height,z),LIGHT)
	_box(v,Vector3(cx-width*0.5-0.5,bottom-0.5,z-1),Vector3(cx+width*0.5+0.5,bottom,z+1),LIGHT)

func _window_x(v: Variant,x: float,cz: float,bottom: float,width: float,height: float) -> void:
	_clear(v,Vector3(x-1,bottom,cz-width*0.5),Vector3(x+1,bottom+height-1,cz+width*0.5))
	_clear(v,Vector3(x-1,bottom+height-1,cz-width*0.5+0.5),Vector3(x+1,bottom+height,cz+width*0.5-0.5))
	_box(v,Vector3(x,bottom+0.5,cz-width*0.5+0.5),Vector3(x+0.5,bottom+height-0.5,cz+width*0.5-0.5),GLASS)
	_box(v,Vector3(x-0.5,bottom,cz-0.25),Vector3(x,bottom+height,cz+0.25),LIGHT)
	_box(v,Vector3(x-1,bottom-0.5,cz-width*0.5-0.5),Vector3(x+1,bottom,cz+width*0.5+0.5),LIGHT)

func _facade() -> void:
	for y in [4.0,10.0,16.0]:
		for x in [-12.0,-6.0,6.0,12.0]: _window_z(_v,x,-131.5,y,2.5,3.5)
		for z in [-125.0,-115.0,-105.0,-85.0]:
			if z<-108: _window_x(_v,-33.5,z,y,2.5,3.5)
			elif y<15: _window_x(_v,-37.5,z,y,2.5,3.5)
		for z in [-112.0,-104.0,-94.0,-85.0]: _window_x(_v,37.5,z,y,2.5,3.5)
	for y in [22.0,28.0,34.0,39.0]:
		for x in [-7.0,0.0,7.0]:
			_window_z(_v,x,-82.5,y,2.5,3.5)
			_window_z(_v,x,-111.5,y,2.5,3.5)
		for side in [-1,1]:
			for z in [-105.0,-98.0,-87.0]: _window_x(_v,side*11.5,z,y,2.5,3.5)
	for side in [-1,1]:
		for z in [-112.0,-100.0,-88.0]:
			var x: float=side*38
			_box(_v,Vector3(x-1,3,z-1),Vector3(x+1,7,z+1),DARK)
			_box(_v,Vector3(x-0.75,7,z-0.75),Vector3(x+0.75,15 if side<0 else 20,z+0.75),LIGHT)
			_box(_v,Vector3(x-1,14 if side<0 else 19,z-1),Vector3(x+1,15 if side<0 else 20,z+1),LIGHT)
		for z in [-107.0,-92.0]:
			var x: float=side*31
			_gable(_v,x-2.5,x+2.5,z-2,z+2,22 if side>0 else 16,5)
	for side in [-1,1]:
		_box(_v,Vector3(side*5.5-0.5,3,-67),Vector3(side*5.5+0.5,11,-64.5),CREAM)
		for i in range(6):
			var x: float=side*(5.0-i*0.5)
			_box(_v,Vector3(x-0.5,10+i*0.5,-67),Vector3(x+0.5,11+i*0.5,-64.5),CREAM)
	_clock_face(_v,Vector3(0,24,-65),5)
	_crest(_v,Vector3(0,16,-65),4)
	for x in [-8.5,8.0]:
		_box(_v,Vector3(x,3,-67),Vector3(x+0.5,20,-65),LIGHT)
		_spire(x+0.25,-66,0.75,20,8,CREAM,true)
	for side in [-1,1]: _banner(_v,Vector3(side*20,7,-78.5),2,7)

func _clock_face(v: Variant,c: Vector3,width: float) -> void:
	var r:=width*0.5
	for ix in range(roundi(-r*2),roundi(r*2)):
		for iy in range(roundi(-r*2),roundi(r*2)):
			var d:=Vector2(ix*0.5+0.25,iy*0.5+0.25).length()
			if d<r: _box(v,c+Vector3(ix*0.5,iy*0.5,0),c+Vector3(ix*0.5+0.5,iy*0.5+0.5,0.5),GOLD if d>r-0.5 else GLASS)
	_box(v,c+Vector3(0,0,0.5),c+Vector3(0.5,r-0.5,1),CREAM)
	_box(v,c+Vector3(-r+1,0,0.5),c+Vector3(0.5,0.5,1),CREAM)

func _door_z(v: Variant,id: String,x: float,z: float,y: float,width: float=3,height: float=3.5) -> void:
	_clear(v,Vector3(x-width*0.5,y,z-1.5),Vector3(x+width*0.5,y+height-1,z+1.5))
	_clear(v,Vector3(x-width*0.5+0.5,y+height-1,z-1.5),Vector3(x+width*0.5-0.5,y+height,z+1.5))
	_doors.append({"id":id,"position":Vector3(x,y+0.15,z),"level":y,"width":width,"height":height})

func _door_x(v: Variant,id: String,x: float,z: float,y: float,width: float=3,height: float=3.5) -> void:
	_clear(v,Vector3(x-1.5,y,z-width*0.5),Vector3(x+1.5,y+height-0.5,z+width*0.5))
	_clear(v,Vector3(x-1.5,y+height-0.5,z-width*0.5+0.5),Vector3(x+1.5,y+height,z+width*0.5-0.5))
	_doors.append({"id":id,"position":Vector3(x,y+0.15,z),"level":y,"width":width,"height":height})

func _floor_plates() -> void:
	for i in range(LEVELS.size()):
		var v: Variant=_floors[i]
		var y: float=LEVELS[i]
		if i<3:
			_floor(v,-33,-18,-129,-109,y,WOOD if i>0 else STONE)
			_floor(v,18,37,-117,-81,y,WOOD if i>0 else STONE)
			_floor(v,-17,17,-131,-119,y,WOOD if i>0 else STONE)
		if i<2: _floor(v,-37,-18,-111,-81,y,WOOD if i>0 else STONE)
		if i==0 or i==3: _floor(v,-17,17,-120,-77,y,LIGHT)
		elif i==1:
			_floor(v,-17,-13,-120,-77,y,LIGHT)
			_floor(v,13,17,-120,-77,y,LIGHT)
			_floor(v,-17,17,-97,-91,y,LIGHT)
			_floor(v,-17,17,-120,-116,y,LIGHT)
		elif i==2:
			_floor(v,-17,17,-104,-77,y,LIGHT)
			_floor(v,-17,-13,-120,-104,y,LIGHT)
			_floor(v,13,17,-120,-104,y,LIGHT)
			_floor(v,-17,17,-120,-116,y,LIGHT)
		else: _floor(v,-11,11,-111,-83,y,LIGHT)
		if i==0: _floor(v,-8,8,-82,-67,y,LIGHT)
		if i==2: _floor(v,-8,8,-82,-67,y,WOOD)
		if i>0: _clear(v,Vector3(-4.5,y-1,-111),Vector3(4.5,y+0.5,-97))
		if i==1: _clear(v,Vector3(-36,y-1,-100),Vector3(-27,y+0.5,-86))
		if i in [1,2]: _clear(v,Vector3(28,y-1,-103),Vector3(37,y+0.5,-89))
		if i==2: _clear(v,Vector3(24,y-1,-116),Vector3(33,y+0.5,-106))
	_box(_floors[0],Vector3(-1.5,2.5,-99),Vector3(1.5,3,-67),RED)
	for x in [-2.0,1.5]: _box(_floors[0],Vector3(x,2.5,-99),Vector3(x+0.5,3,-67),GOLD)

func _divisions_and_ceilings() -> void:
	for i in range(3):
		var v: Variant=_floors[i]
		var y: float=LEVELS[i]
		_box(v,Vector3(18,y,-103.5),Vector3(37,y+5.5,-103),LIGHT)
		_box(v,Vector3(18,y,-89),Vector3(37,y+5.5,-88.5),LIGHT)
		if i<2: _box(v,Vector3(-37,y,-101.5),Vector3(-18,y+5.5,-101),LIGHT)
		_box(v,Vector3(-33,y,-113.5),Vector3(-18,y+5.5,-113),LIGHT)
		for rect in [Rect2(-33,-129,15,15),Rect2(-17,-131,34,10)]: _coffer(v,rect,y,5.5)
		if i!=1: _coffer(v,Rect2(18,-117,19,13),y,5.5)
		if i<2: _coffer(v,Rect2(-37,-111,19,9),y,5.5)
		_coffer(v,Rect2(18,-88,19,7),y,5.5)
	_box(_floors[2],Vector3(-0.25,15,-131),Vector3(0.25,20.5,-121),LIGHT)
	for z in [-115.0,-87.0]: _arch(_floors[0],z,3,28,15)
	for side in [-1,1]:
		var x: float=side*13
		_rail(_floors[1],Vector3(x,9,-115),Vector3(x,9,-98))
		_rail(_floors[1],Vector3(x,9,-90),Vector3(x,9,-78))
		_rail(_floors[2],Vector3(x,15,-115),Vector3(x,15,-105))
		_banner(_floors[0],Vector3(side*16,5,-112),2,7,true)
		_banner(_floors[0],Vector3(side*16,5,-85),2,7,true)
	for x in [24.0,33.0]: _rail(_floors[2],Vector3(x,15,-116),Vector3(x,15,-106))
	for z in [-116.0,-106.0]: _rail(_floors[2],Vector3(24,15,z),Vector3(33,15,z))
	for i in [3,4,5]:
		for z in [-108.0,-96.0,-85.0]: _box(_floors[i],Vector3(-10,LEVELS[i]+5,z-0.25),Vector3(10,LEVELS[i]+5.5,z+0.25),DARK_WOOD)

func _coffer(v: Variant,r: Rect2,y: float,height: float) -> void:
	for z in range(ceili(r.position.y+1),floori(r.end.y),4):
		_box(v,Vector3(r.position.x,y+height-0.5,z-0.25),Vector3(r.end.x,y+height,z+0.25),DARK_WOOD)
		for x in [r.position.x,r.end.x-0.5]:
			_box(v,Vector3(x,y,z-0.5),Vector3(x+0.5,y+height,z+0.5),WOOD)
			_box(v,Vector3(x-0.25,y+height-1.5,z-0.5),Vector3(x+0.75,y+height-0.5,z+0.5),DARK_WOOD)
	for x in range(ceili(r.position.x+2),floori(r.end.x),4): _box(v,Vector3(x-0.25,y+height-0.5,r.position.y),Vector3(x+0.25,y+height,r.end.y),DARK_WOOD)
	for z in [r.position.y,r.end.y-0.5]: _box(v,Vector3(r.position.x,y,z),Vector3(r.end.x,y+0.5,z+0.5),DARK_WOOD)

func _arch(v: Variant,z: float,y: float,width: float,height: float) -> void:
	var r:=width*0.5-1
	for side in [-1,1]:
		var x: float=side*r
		_box(v,Vector3(x-0.5,y,z-0.5),Vector3(x+0.5,y+height-5,z+0.5),CREAM)
	for ix in range(roundi(-r*2),roundi(r*2)):
		var x:=ix*0.5
		var arch_y:=snappedf(y+height-5+5*(1.0-absf(x+0.25)/r),0.5)
		_box(v,Vector3(x,arch_y,z-0.5),Vector3(x+0.5,arch_y+0.5,z+0.5),LIGHT)

func _rail(v: Variant,a: Vector3,b: Vector3,id: int=BRASS) -> void:
	var length:=a.distance_to(b)
	var d: Vector3=(b-a).normalized()
	for i in range(ceili(length*2)):
		var p:=a+d*i*0.5
		_box(v,p+Vector3(-0.25,0.75,-0.25),p+Vector3(0.25,1.25,0.25),id)
		if i%4==0: _box(v,p+Vector3(-0.25,0,-0.25),p+Vector3(0.25,1,0.25),id)

func _u_stair(v: Variant,x0: float,z0: float,base: float) -> Array[Vector3]:
	var south:=z0+10.0
	var north:=south-6.0
	_floor(v,x0+0.5,x0+7.5,south,south+4,base,LIGHT)
	for step in range(6):
		var y:=base+(step+1)*0.5
		var z:=south-(step+1)
		_box(v,Vector3(x0+0.5,base-0.5,z),Vector3(x0+3.5,y,z+1),STONE)
		_box(v,Vector3(x0+0.5,y-0.5,z),Vector3(x0+3.5,y,z+1),LIGHT)
	_floor(v,x0+0.5,x0+7.5,north-3,north,base+3,LIGHT)
	for step in range(6):
		var y:=base+3+(step+1)*0.5
		var z:=north+step
		_box(v,Vector3(x0+4.5,base+2.5,z),Vector3(x0+7.5,y,z+1),STONE)
		_box(v,Vector3(x0+4.5,y-0.5,z),Vector3(x0+7.5,y,z+1),LIGHT)
	_floor(v,x0+0.5,x0+7.5,south,south+4,base+6,LIGHT)
	for step in range(6):
		var z:=south-(step+1)
		var y:=base+(step+1)*0.5
		_box(v,Vector3(x0+0.5,y,z),Vector3(x0+1,y+1,z+1),BRASS)
		var rz:=north+step
		var ry:=base+3+(step+1)*0.5
		_box(v,Vector3(x0+7,ry,rz),Vector3(x0+7.5,ry+1,rz+1),BRASS)
	return [Vector3(x0+2,base+0.15,south+1.5),Vector3(x0+2,base+3.15,north-1.5),Vector3(x0+6,base+3.15,north-1.5),Vector3(x0+6,base+6.15,south+1.5)]

func _staircases() -> void:
	var main_points: Array[Vector3]=[]
	for i in range(5): main_points.append_array(_u_stair(_floors[i],-4.5,-111,LEVELS[i]))
	_stairs.append({"id":"royal_stair","title":"中央王宮階段","levels":LEVELS,"width":3.0,"step_height":0.5,"step_depth":1.0,"waypoints":main_points})
	_routes.append({"id":"royal_stair","points":main_points})
	var west:=_u_stair(_floors[0],-36,-100,3)
	_stairs.append({"id":"west_stair","title":"西館階段","levels":[3,9],"width":3.0,"step_height":0.5,"step_depth":1.0,"waypoints":west})
	_routes.append({"id":"west_stair","points":west})
	var east: Array[Vector3]=[]
	for i in range(2): east.append_array(_u_stair(_floors[i],28,-103,LEVELS[i]))
	_stairs.append({"id":"east_stair","title":"図書塔階段","levels":[3,9,15],"width":3.0,"step_height":0.5,"step_depth":1.0,"waypoints":east})
	_routes.append({"id":"east_stair","points":east})

func _furnish() -> void:
	for i in range(3): _box(_floors[0],Vector3(-5+i*0.5,3+i*0.5,-120),Vector3(5-i*0.5,3.5+i*0.5,-115-i*0.5),LIGHT)
	_throne(_floors[0],Vector3(0,4.5,-118))
	_crest(_floors[0],Vector3(0,10,-120),5)
	for x in [-9.0,9.0]: _candelabra(_floors[0],Vector3(x,3,-115))
	_hearth(_floors[0],Vector3(-34,3,-108))
	_long_table(_floors[0],Vector3(-26,3,-106),6)
	for x in [-30.0,-24.0]:
		_chest(_floors[0],Vector3(x,3,-83))
		_box(_floors[0],Vector3(x-1,3,-126),Vector3(x+1,4,-122),WOOD)
		for z in [-125.5,-124.0,-122.5]: _box(_floors[0],Vector3(x,4,z),Vector3(x+0.5,6,z+0.5),IRON)
	for x in [-8.0,0.0,8.0]: _long_table(_floors[0],Vector3(x,3,-126),6)
	for x in [22.0,31.0]:
		for z in [-112.0,-108.0]: _box(_floors[0],Vector3(x,3,z),Vector3(x+3,4,z+0.75),WOOD)
	_box(_floors[0],Vector3(24,3,-116),Vector3(32,4,-114),LIGHT)
	_desk(_floors[0],Vector3(26,3,-84))
	_bookcase(_floors[1],Vector3(27,9,-116),16)
	_bookcase_side(_floors[1],Vector3(36,9,-111),9,false)
	_long_table(_floors[1],Vector3(28,9,-110),6)
	_bookcase(_floors[1],Vector3(-26,9,-110),16)
	_desk(_floors[1],Vector3(-25,9,-105))
	_long_table(_floors[1],Vector3(0,9,-126),7)
	_bed(_floors[1],Vector3(-28,9,-122))
	_desk(_floors[1],Vector3(-24,9,-117))
	_desk(_floors[1],Vector3(24,9,-84))
	_bed(_floors[2],Vector3(-28,15,-122))
	_bed(_floors[2],Vector3(-8,15,-127))
	_desk(_floors[2],Vector3(8,15,-126))
	_bookcase(_floors[2],Vector3(8,15,-130),12)
	_desk(_floors[2],Vector3(8,15,-87))
	_long_table(_floors[3],Vector3(-7,21,-94),8)
	_bookcase(_floors[3],Vector3(0,21,-110),16)
	_desk(_floors[4],Vector3(-7,27,-87))
	_chest(_floors[5],Vector3(-9,33,-85))

func _final_openings() -> void:
	# The external terrace plate must leave the central stair shaft open too.
	_clear(_v,Vector3(-4.5,20.5,-111),Vector3(4.5,21.5,-97))
	var components: Array=[_v]
	components.append_array(_floors)
	for v in components:
		for z in [-66.5,-76.5,-82.5]: _door_z(v,"front_%d"%int(z),0,z,3,8,10)
		for y in [3.0,9.0,15.0]:
			_door_x(v,"west_rear_%d"%int(y),-17.5,-115,y,3,3.5)
			if y<15: _door_x(v,"west_service_%d"%int(y),-17.5,-106,y,3,3.5)
			for side in [-1,1]:
				for z in [-108.0,-85.0]:
					if side<0 and y==15: continue
					_door_x(v,"wing_%d_%d_%d"%[side,int(y),int(z)],side*17.5,z,y,3,3.5)
			for x in [-10.0,10.0]:
				_door_z(v,"rear_%d_%d"%[int(x),int(y)],x,-119.5,y,3,3.5)
				_door_z(v,"rear_inner_%d_%d"%[int(x),int(y)],x,-121,y,3,3.5)
			_door_z(v,"west_north_%d"%int(y),-22,-109.5,y,3,3.5)
			_door_z(v,"west_room_%d"%int(y),-22,-113.25,y,3,3.5)
			_door_z(v,"east_chapel_%d"%int(y),22,-103.25,y,3,3.5)
			_door_z(v,"east_reception_%d"%int(y),22,-88.75,y,3,3.5)
			if y<15: _door_z(v,"west_kitchen_%d"%int(y),-22,-101.25,y,3,3.5)
		for y in [21.0,27.0,33.0]:
			if y!=27: _door_z(v,"high_balcony_%d"%int(y),0,-82.5,y,3,4)
			if y==21: _door_x(v,"upper_west_%d"%int(y),-11.5,-94,y,3,3.5)
		_door_z(v,"clock_gallery",0,-66,15,3,4)
		_door_z(v,"clock_gallery_rear",0,-82.5,15,3,4)
		_door_z(v,"spire_chamber",5,-89.5,33,3,3.5)
	var unique: Dictionary={}
	for door in _doors: unique[door.id]=door
	_doors.assign(unique.values())

func _room(id: String,title: String,level: float,p: Vector3,b: AABB) -> void:
	_rooms.append({"id":id,"title":title,"level":level,"position":p,"bounds":b})
	_landmarks.append({"id":"palace_"+id,"title":title,"position":p,"kind":"palace"})
	_lights.append({"position":p+Vector3(0,3.5,0),"color":Color("ffe1ad"),"range":10.0,"energy":0.5})

func _metadata() -> void:
	_room("forecourt","王城前庭",2,Vector3(0,2.15,-54),AABB(Vector3(-15,2,-64),Vector3(30,8,18)))
	_room("great_hall","王城大広間",3,Vector3(8,3.15,-90),AABB(Vector3(-12,3,-98),Vector3(24,12,20)))
	_room("throne","謁見の間",3,Vector3(8,3.15,-113),AABB(Vector3(-12,3,-120),Vector3(24,18,13)))
	_room("guard","近衛詰所",3,Vector3(-23,3.15,-85),AABB(Vector3(-37,3,-88),Vector3(19,6,7)))
	_room("armory","王城武器庫",3,Vector3(-21,3.15,-122),AABB(Vector3(-33,3,-129),Vector3(15,6,15)))
	_room("kitchen","王城厨房",3,Vector3(-21,3.15,-106),AABB(Vector3(-37,3,-111),Vector3(19,6,9)))
	_room("banquet","大食堂",3,Vector3(-13,3.15,-126),AABB(Vector3(-17,3,-131),Vector3(34,6,10)))
	_room("chapel","王城礼拝堂",3,Vector3(21,3.15,-110),AABB(Vector3(18,3,-117),Vector3(19,6,13)))
	_room("reception","応接室",3,Vector3(21,3.15,-85),AABB(Vector3(18,3,-88),Vector3(19,6,7)))
	_room("library","王立図書室",9,Vector3(21,9.15,-110),AABB(Vector3(18,9,-117),Vector3(19,12,13)))
	_room("archive","文書保管室",9,Vector3(-21,9.15,-106),AABB(Vector3(-37,9,-111),Vector3(19,6,9)))
	_room("council","評議の間",9,Vector3(-10,9.15,-126),AABB(Vector3(-17,9,-131),Vector3(34,6,10)))
	_room("guestrooms","来賓の客室",9,Vector3(-21,9.15,-122),AABB(Vector3(-33,9,-129),Vector3(15,6,15)))
	_room("study","執務室",9,Vector3(21,9.15,-85),AABB(Vector3(18,9,-88),Vector3(19,6,7)))
	_room("gallery","大広間回廊",9,Vector3(-15,9.15,-105),AABB(Vector3(-17,9,-116),Vector3(4,6,38)))
	_room("bedrooms","王族の寝室",15,Vector3(-21,15.15,-122),AABB(Vector3(-33,15,-129),Vector3(15,6,15)))
	_room("royal_bedroom","王の私室",15,Vector3(-12,15.15,-125),AABB(Vector3(-17,15,-131),Vector3(16,6,10)))
	_room("royal_study","王の書斎",15,Vector3(12,15.15,-125),AABB(Vector3(1,15,-131),Vector3(16,6,10)))
	_room("map_room","王国地図室",15,Vector3(12,15.15,-89),AABB(Vector3(4,15,-97),Vector3(13,6,19)))
	_room("upper_hall","星冠の間",21,Vector3(-7,21.15,-86),AABB(Vector3(-11,21,-111),Vector3(22,6,28)))
	_room("observatory","主塔展望室",33,Vector3(-7,33.15,-89),AABB(Vector3(-11,33,-98),Vector3(22,10,15)))
	_routes.append({"id":"royal_axis","points":[Vector3(0,2.15,-63),Vector3(0,3.15,-69),Vector3(0,3.15,-89),Vector3(8,3.15,-96),Vector3(8,3.15,-113)]})
	for y in [3.0,9.0,15.0]:
		_routes.append({"id":"east_rooms_%d"%int(y),"points":[Vector3(15,y+0.15,-108),Vector3(21,y+0.15,-108)]})
		_routes.append({"id":"rear_rooms_%d"%int(y),"points":[Vector3(-15,y+0.15,-115),Vector3(-10,y+0.15,-118),Vector3(-10,y+0.15,-122)]})
	for y in [3.0,9.0]: _routes.append({"id":"west_rooms_%d"%int(y),"points":[Vector3(-15,y+0.15,-106),Vector3(-21,y+0.15,-106)]})
	_routes.append({"id":"observatory_balcony","points":[Vector3(-7,33.15,-97),Vector3(-7,33.15,-85),Vector3(0,33.15,-85),Vector3(0,33.15,-79)]})

func _disjoint_components() -> void:
	for index in range(_floors.size()):
		var v: Variant=_floors[index]
		for cell in v.cells.keys():
			var occupied: bool=_v.cells.has(cell)
			if not occupied:
				for previous in range(index):
					if _floors[previous].cells.has(cell):
						occupied=true
						break
			if occupied: v.cells.erase(cell)

func _crest(v: Variant,c: Vector3,width: float) -> void:
	var half:=width*0.5
	_box(v,c+Vector3(-half,0,0),c+Vector3(half,width,0.5),GOLD)
	_box(v,c+Vector3(-half+0.5,0.5,0.5),c+Vector3(half-0.5,width-0.5,1),BLUE)
	_box(v,c+Vector3(-0.5,1,1),c+Vector3(0.5,width-1,1.5),CREAM)
	_box(v,c+Vector3(-half+1,width*0.5,1),c+Vector3(half-1,width*0.5+0.5,1.5),CREAM)

func _banner(v: Variant,c: Vector3,width: float,height: float,sideways: bool=false) -> void:
	if sideways: _box(v,c+Vector3(-0.25,0,-width*0.5),c+Vector3(0.25,height,width*0.5),RED)
	else:
		_box(v,c+Vector3(-width*0.5,0,0),c+Vector3(width*0.5,height,0.5),BLUE)
		_box(v,c+Vector3(-0.5,1,0.5),c+Vector3(0.5,height-1,1),GOLD)

func _long_table(v: Variant,c: Vector3,length: float=10.0) -> void:
	_furnishings.append({"kind":"table","position":c,"length":length})
	var half: float=snappedf(maxf(length,4),1.0)*0.5
	_box(v,c+Vector3(-1.5,0.5,-half),c+Vector3(1.5,1,half),WOOD)
	_box(v,c+Vector3(-0.5,0.5,-half),c+Vector3(0.5,1,half),RED)
	for x in [-1.5,1.0]:
		for z in [-half,half-0.5]:
			_box(v,c+Vector3(x,0,z),c+Vector3(x+0.5,0.5,z+0.5),DARK_WOOD)
	for side in [-1.0,1.0]:
		var x: float=side*2.5
		_box(v,c+Vector3(x,0,-half+0.5),c+Vector3(x+0.5,0.5,half-0.5),WOOD)
		_box(v,c+Vector3(x,0.5,-half+0.5),c+Vector3(x+0.5,1.5,half-0.5),DARK_WOOD)

func _bed(v: Variant,c: Vector3) -> void:
	_furnishings.append({"kind":"bed","position":c})
	_box(v,c+Vector3(-1,0,-1.5),c+Vector3(1,0.5,1.5),DARK_WOOD)
	_box(v,c+Vector3(-0.5,0.5,-1),c+Vector3(0.5,1,1),31)
	_box(v,c+Vector3(-0.5,0.5,-1),c+Vector3(0.5,1,0.5),RED)
	_box(v,c+Vector3(-0.5,1,0.5),c+Vector3(0.5,1.5,1),31)
	_box(v,c+Vector3(-1,0.5,1),c+Vector3(1,1.5,1.5),WOOD)
	_box(v,c+Vector3(-1,0.5,-1.5),c+Vector3(1,1,-1),WOOD)
	for x in [-1.0,0.5]:
		for z in [-1.5,1.0]:
			_box(v,c+Vector3(x,0,z),c+Vector3(x+0.5,3,z+0.5),WOOD)
			_box(v,c+Vector3(x,3,z),c+Vector3(x+0.5,3.5,z+0.5),GOLD)
	for z in [-1.5,1.0]:
		_box(v,c+Vector3(-1,2.5,z),c+Vector3(1,3,z+0.5),DARK_WOOD)
	for x in [-1.0,0.5]:
		_box(v,c+Vector3(x,2.5,-1),c+Vector3(x+0.5,3,1),DARK_WOOD)
	_box(v,c+Vector3(-0.5,2.5,-1),c+Vector3(0.5,3,1),26)

func _bookcase(v: Variant,c: Vector3,width: float=5.0) -> void:
	_furnishings.append({"kind":"bookcase","position":c,"width":width})
	var w: float=snappedf(maxf(width,3),1)
	var half:=w*0.5
	_box(v,c+Vector3(-half,0,-0.5),c+Vector3(half,4,0),DARK_WOOD)
	for x in [-half,half-0.5]:
		_box(v,c+Vector3(x,0,-0.5),c+Vector3(x+0.5,4,0.5),WOOD)
	for y in [0.0,1.5,3.0,3.5]:
		_box(v,c+Vector3(-half,y,-0.5),c+Vector3(half,y+0.5,0.5),WOOD)
	var colors: Array[int]=[29,21,26,30,25]
	for row in range(2):
		for i in range(roundi((w-1)*2)):
			var x: float=-half+0.5+i*0.5
			var y: float=0.5+row*1.5
			var h:=0.5 if i%5==2 else 1.0
			var material: int=colors[(i/2+row*2)%colors.size()]
			_box(v,c+Vector3(x,y,0),c+Vector3(x+0.5,y+h,0.5),material)

func _bookcase_side(v: Variant,c: Vector3,depth: float,east: bool) -> void:
	var half: float=snappedf(depth,1)*0.5
	var back0: float=-0.5 if east else 0.0
	var book0: float=0.0 if east else -0.5
	_box(v,c+Vector3(back0,0,-half),c+Vector3(back0+0.5,4,half),DARK_WOOD)
	for y in [0.0,1.5,3.0,3.5]:
		_box(v,c+Vector3(-0.5,y,-half),c+Vector3(0.5,y+0.5,half),WOOD)
	for z in [-half,half-0.5]:
		_box(v,c+Vector3(-0.5,0,z),c+Vector3(0.5,4,z+0.5),WOOD)
	var colors: Array[int]=[29,21,26,30,25]
	for row in range(2):
		for i in range(roundi((depth-1)*2)):
			var z: float=-half+0.5+i*0.5
			var y: float=0.5+row*1.5
			_box(v,c+Vector3(book0,y,z),c+Vector3(book0+0.5,y+1,z+0.5),colors[(i/2+row*2)%colors.size()])

func _desk(v: Variant,c: Vector3) -> void:
	_furnishings.append({"kind":"desk","position":c})
	_box(v,c+Vector3(-2,0.5,-1),c+Vector3(2,1,1),WOOD)
	for x in [-2.0,1.0]:
		_box(v,c+Vector3(x,0,-1),c+Vector3(x+1,0.5,1),DARK_WOOD)
	_box(v,c+Vector3(-0.5,0,1.5),c+Vector3(0.5,0.5,2.5),WOOD)
	_box(v,c+Vector3(-0.5,0.5,2),c+Vector3(0.5,1.5,2.5),DARK_WOOD)
	_box(v,c+Vector3(-0.5,0.5,1.5),c+Vector3(0.5,1,2),RED)

func _throne(v: Variant,c: Vector3) -> void:
	_furnishings.append({"kind":"throne","position":c})
	_box(v,c+Vector3(-1.5,0,-1),c+Vector3(1.5,0.5,1.5),GOLD)
	_box(v,c+Vector3(-1,0.5,-0.5),c+Vector3(1,1,1),RED)
	for x in [-1.5,1.0]:
		_box(v,c+Vector3(x,0.5,-1),c+Vector3(x+0.5,2,1.5),GOLD)
	_box(v,c+Vector3(-1.5,0.5,-1),c+Vector3(1.5,4.5,-0.5),GOLD)
	_box(v,c+Vector3(-1,1,-0.5),c+Vector3(1,4,0),RED)
	_box(v,c+Vector3(-0.5,2.5,0),c+Vector3(0.5,3.5,0.5),CREAM)
	_box(v,c+Vector3(-1,4.5,-1),c+Vector3(1,5,0),GOLD)
	_box(v,c+Vector3(-0.5,5,-1),c+Vector3(0.5,5.5,0),GOLD)

func _hearth(v: Variant,c: Vector3) -> void:
	_furnishings.append({"kind":"hearth","position":c})
	_box(v,c+Vector3(-2.5,0,-1.5),c+Vector3(2.5,4.5,1.5),DARK)
	_clear(v,c+Vector3(-1.5,0.5,-2),c+Vector3(1.5,3.5,1))
	_box(v,c+Vector3(-3,3.5,-1.5),c+Vector3(3,4,2),LIGHT)
	_box(v,c+Vector3(-1,4.5,0.5),c+Vector3(1,5.5,1.5),STONE)
	_box(v,c+Vector3(-1.5,0,-1),c+Vector3(1.5,0.5,1),WOOD)
	_box(v,c+Vector3(-1,0.5,-0.5),c+Vector3(1,1,0.5),FIRE)
	_box(v,c+Vector3(-0.5,1,-0.5),c+Vector3(0.5,1.5,0.5),FIRE)
	_box(v,c+Vector3(-1.5,3,0),c+Vector3(1.5,3.5,0.5),IRON)
	_box(v,c+Vector3(0,2,0),c+Vector3(0.5,3,0.5),IRON)
	_box(v,c+Vector3(-1,1,-1),c+Vector3(1,2,1),IRON)
	_clear(v,c+Vector3(-0.5,1.5,-0.5),c+Vector3(0.5,2.5,0.5))
	_box(v,c+Vector3(-0.5,1,-0.5),c+Vector3(0.5,1.5,0.5),25)

func _chest(v: Variant,c: Vector3) -> void:
	_box(v,c+Vector3(-1,0,-0.5),c+Vector3(1,1,0.5),WOOD)
	_box(v,c+Vector3(-1,1,-0.5),c+Vector3(1,1.5,0.5),DARK_WOOD)
	for x in [-1.0,0.5]:
		_box(v,c+Vector3(x,0,-0.5),c+Vector3(x+0.5,1.5,0.5),IRON)
	_box(v,c+Vector3(0,0.5,-1),c+Vector3(0.5,1,-0.5),GOLD)

func _candelabra(v: Variant,c: Vector3) -> void:
	_furnishings.append({"kind":"candelabra","position":c})
	_box(v,c+Vector3(-0.5,0,-0.5),c+Vector3(1,0.5,1),BRASS)
	_box(v,c+Vector3(0,0.5,0),c+Vector3(0.5,2,0.5),BRASS)
	_box(v,c+Vector3(-1,1.5,0),c+Vector3(1.5,2,0.5),BRASS)
	for x in [-1.0,0.0,1.0]:
		_box(v,c+Vector3(x,2,0),c+Vector3(x+0.5,2.5,0.5),31)
		_box(v,c+Vector3(x,2.5,0),c+Vector3(x+0.5,3,0.5),FIRE)
