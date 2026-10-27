extends RefCounted
## Permanent voxel royal gardens and a ceremonial multi-tier water monument.
## The symmetrical planting respects the two side stair arrivals and all roads.
const STONE := 4
const LIGHT := 5
const DARK := 6
const BLUE := 7
const WOOD := 10
const WATER := 15
const GOLD := 17
const LEAF := 18
const GLASS := 27
const FLOWER := 21
var _v: Variant
var _details: Variant
var _trees := 0
var _beds := 0

func build(volume: Variant,details: Variant) -> Dictionary:
	_v=volume
	_details=details
	_trees=0
	_beds=0
	_fountain(Vector2(0,14))
	var parks: Array[Dictionary]=[]
	var regions: Array[Dictionary]=[]
	# The palace's foreground is a civic garden, not another residential row.
	# Continuous clear ribbons remain at z=-8 (stairs) and z=0 (city crossing).
	for side in [-1.0,1.0]:
		var label: String="west" if side<0 else "east"
		var north:=Rect2(-38 if side<0 else 22,-16,16,5.5)
		var south_inner:=Rect2(-28.5 if side<0 else 24,5.5,4.5,4.5)
		var south_outer:=Rect2(-62 if side<0 else 33.5,5.5,28.5,4.5)
		for part in [{"suffix":"north","rect":north},{"suffix":"south_inner","rect":south_inner},{"suffix":"south_outer","rect":south_outer}]:
			var rect: Rect2=part["rect"]
			var id: String="royal_"+label+"_"+str(part["suffix"])
			parks.append({"id":id,"title":"王城前・紋章庭園","bounds":AABB(Vector3(rect.position.x,2,rect.position.y),Vector3(rect.size.x,9,rect.size.y))})
			regions.append({"id":id,"kind":"park","bounds":rect})
		# Small northern parterres leave x43..57 clear for the staircase.
		_formal_bed(Vector2(side*30,-13),Vector2(13,3.5))
		_tree(Vector3(side*30,2,-13),5.5)
		for x in [25.5,42.0,56.0]:
			_formal_bed(Vector2(side*x,7.5),Vector2(5 if x==25.5 else 7,4))
			_tree(Vector3(side*x,2,7.5),7.5 if x==42 else 6.5)
		# Benches face the fountain through the planting, not into walls.
		_details.bench(Vector3(side*22.5,2,8),-side*PI*0.5)
		_lamp(Vector3(side*20,2,-11.5))
		_lamp(Vector3(side*20,2,30))
	# Four broad cypress sentinels visually link the fountain to the side stairs.
	for side in [-1.0,1.0]:
		for z in [-13.0,8.0]:
			if z<0: _cypress(Vector3(side*39.5,2,z),7.5)
	# Ornamental paving is flush with the district-ground collision plane.
	for side in [-1.0,1.0]:
		for z in [2.0,26.0]:
			_compass(Vector3(side*15,2.05,z),1.25)
	var fountain_bounds:=AABB(Vector3(-11.5,2,2.5),Vector3(23,11.5,23))
	return {
		"reserved":[Rect2(-22,0,44,36),Rect2(-65,-18,130,28)],
		"parks":parks,"ground_regions":regions,
		"landmarks":[{"id":"central_plaza","title":"王冠の大噴水広場","kind":"plaza","position":Vector3(15.5,2.15,27)},
			{"id":"royal_garden","title":"王城前・紋章庭園","kind":"garden","position":Vector3(19,2.15,-8)}],
		"fountain":{"id":"royal_crown_fountain","title":"王冠の大噴水","center":Vector3(0,2,14),"bounds":fountain_bounds,"diameter_m":23.0,"basins":3,"cascade_spouts":8,"jets":8,"public_walkway":"perimeter","rim_probes":[Vector3(-11.25,2.5,14),Vector3(11.25,2.5,14),Vector3(0,2.5,2.75),Vector3(0,2.5,25.25)],"perimeter_route":[Vector3(0,2.15,32),Vector3(18,2.15,32),Vector3(18,2.15,-2),Vector3(-18,2.15,-2),Vector3(-18,2.15,32),Vector3(0,2.15,32)]},
		"viewpoints":[{"id":"royal_fountain","title":"王冠の大噴水と紋章庭園","position":Vector3(15.5,2.15,27),"yaw_degrees":50.0,"pitch_degrees":18.0}],
		"stats":{"trees":_trees,"formal_flower_beds":_beds,"fountain_diameter_m":23.0,"fountain_height_m":11.5,"gardens":parks.size(),"water_effects":"static_voxel_geometry"}
	}

func _fountain(center: Vector2) -> void:
	# Low, broad stepped stylobate: unlike a thin rim it reads from the skyline.
	_octagon(center,11.5,2,2.5,STONE)
	_octagon(center,11,2.5,3,LIGHT)
	_octagon(center,10.5,3,3.5,DARK)
	_octagon(center,10,3,3.5,LIGHT)
	_octagon(center,9.25,3,3.5,0)
	_octagon(center,9.25,2.5,3,WATER)
	# Four white rosettes and eight brass corner inserts articulate the rim.
	for index in range(8):
		var a:=TAU*float(index)/8.0
		var direction:=Vector2(sin(a),cos(a))
		var p:=center+direction*9.75
		_box(Vector3(p.x-0.5,3.5,p.y-0.5),Vector3(p.x+0.5,4,p.y+0.5),LIGHT)
		_details.add_box(Vector3(p.x,4.0625,p.y),Vector3(0.625,0.125,0.625),GOLD)
		# Block-carved masks feed inward jets into the wide lower basin.
		var lip:=center+direction*8.75
		_box(Vector3(lip.x-0.5,3,lip.y-0.5),Vector3(lip.x+0.5,4.5,lip.y+0.5),STONE)
		_box(Vector3(lip.x-0.5,4.25,lip.y-0.5),Vector3(lip.x+0.5,4.75,lip.y+0.5),LIGHT)
		var mouth:=Vector3(lip.x,4.5,lip.y)-Vector3(direction.x,0,direction.y)*0.5
		_details.add_box(mouth,Vector3(0.375,0.375,0.375),GOLD)
		_jet(mouth,Vector3(center.x+direction.x*5,3.125,center.y+direction.y*5),2.5,0.25,true)
	# Hollow basin shells are stepped octagons, each with visibly blue water.
	_octagon(center,2.75,3,4,STONE)
	_octagon(center,2.25,4,5,BLUE)
	_octagon(center,2.5,5,5.5,LIGHT)
	_octagon(center,3.5,5.5,6,LIGHT)
	_octagon(center,4.5,6,6.5,LIGHT)
	_octagon(center,4,6.5,7,LIGHT)
	_octagon(center,3.5,6.5,7,0)
	_octagon(center,3.5,6,6.5,WATER)
	# Gold collar and four arched buttresses around the central column.
	_octagon(center,1.5,6.5,7,GOLD)
	_octagon(center,1,7,8.5,LIGHT)
	_octagon(center,1.25,8.5,9,GOLD)
	_octagon(center,2,9,9.5,LIGHT)
	_octagon(center,2.75,9.5,10,LIGHT)
	_octagon(center,2.5,10,10.5,LIGHT)
	_octagon(center,2,10,10.5,0)
	_octagon(center,2,9.5,10,GLASS)
	_octagon(center,0.75,10,11.5,LIGHT)
	_octagon(center,1,11.5,12,GOLD)
	# The stylised blue-and-gold crown is a kingdom symbol, not a heavy statue.
	_octagon(center,1.5,12,12.5,BLUE)
	_octagon(center,1.5,12.5,13,GOLD)
	_octagon(center,1,12.5,13,0)
	for side in [-1.0,1.0]:
		_box(Vector3(center.x+side*1.25-0.25,13,center.y-0.25),Vector3(center.x+side*1.25+0.25,13.5,center.y+0.25),GOLD)
		_box(Vector3(center.x-0.25,13,center.y+side*1.25-0.25),Vector3(center.x+0.25,13.5,center.y+side*1.25+0.25),GOLD)
	# Eight cascades spill off the middle bowl; quantised streams are permanent.
	for index in range(8):
		var a:=TAU*float(index)/8.0
		var direction:=Vector2(sin(a),cos(a))
		var start:=Vector3(center.x+direction.x*3.75,6.5,center.y+direction.y*3.75)
		var end:=Vector3(center.x+direction.x*6.75,3.25,center.y+direction.y*6.75)
		_jet(start,end,1.0,0.5,false)
		var top_start:=Vector3(center.x+direction.x*2.25,10,center.y+direction.y*2.25)
		var top_end:=Vector3(center.x+direction.x*3,6.5,center.y+direction.y*3)
		_jet(top_start,top_end,0.25,0.25,true)
		# Surface ripples are opaque pale-blue inlays; no expensive transparency.
		var splash:=center+direction*6.75
		_details.add_box(Vector3(splash.x,3.0625,splash.y),Vector3(1.5,0.125,0.25),GLASS,a)
		_details.add_box(Vector3(splash.x,3.0625,splash.y),Vector3(0.25,0.125,1.5),GLASS,a)

func _octagon(center: Vector2,radius: float,bottom: float,top: float,id: int) -> void:
	var reach:=ceili(radius*2)
	var diagonal:=radius*sqrt(2.0)
	for row in range(-reach,reach):
		var z:=float(row)*0.5+0.25
		if absf(z)>radius: continue
		var half:=minf(radius,diagonal-absf(z))
		var half_cells:=floori(half*2)
		if half_cells<1: continue
		_box(Vector3(center.x-float(half_cells)*0.5,bottom,center.y+float(row)*0.5),Vector3(center.x+float(half_cells)*0.5,top,center.y+float(row+1)*0.5),id)

func _jet(a: Vector3,b: Vector3,arch: float,width: float,fine: bool) -> void:
	var count:=ceili((a.distance_to(b)+arch*2)/width)
	var cells: Dictionary={}
	for index in range(count+1):
		var t:=float(index)/float(count)
		var p:=a.lerp(b,t)+Vector3.UP*sin(t*PI)*arch
		var snapped:=Vector3(snappedf(p.x,width),snappedf(p.y,width),snappedf(p.z,width))
		if cells.has(snapped): continue
		cells[snapped]=true
		if fine: _details.add_box(snapped,Vector3.ONE*width,GLASS)
		else: _box(snapped-Vector3.ONE*width*0.5,snapped+Vector3.ONE*width*0.5,GLASS)

func _formal_bed(center: Vector2,size: Vector2) -> void:
	_beds+=1
	var a:=Vector3(center.x-size.x*0.5,2,center.y-size.y*0.5)
	var b:=Vector3(center.x+size.x*0.5,2.5,center.y+size.y*0.5)
	_box(a,b,LIGHT)
	_box(a+Vector3(0.5,0.5,0.5),b+Vector3(-0.5,0.5,-0.5),LEAF)
	# Repeating blossoms form designed bands along a hedge, not random specks.
	for i in range(maxi(1,floori(size.x/1.5))):
		var x:=center.x-size.x*0.5+1+float(i)*1.5
		for side in [-1.0,1.0]:
			_details.add_box(Vector3(x,3.125,center.y+side*maxf(0.25,size.y*0.5-1)),Vector3(0.375,0.25,0.375),FLOWER if i%2==0 else 28)

func _tree(p: Vector3,height: float) -> void:
	_trees+=1
	var crown:=height*0.68
	_box(p+Vector3(-0.5,0,-0.5),p+Vector3(0.5,crown,0.5),WOOD)
	for side in [-1.0,1.0]:
		_box(p+Vector3(side*1.5-0.25,crown*0.65,-0.25),p+Vector3(side*1.5+0.25,crown+0.5,0.25),WOOD)
	# Build an actual stepped leaf silhouette rather than three giant cuboids.
	# Small off-centre octagons make a rounded, readable voxel canopy.
	var bottom:=snappedf(height*0.45,0.5)
	var layers:=maxi(4,roundi((height-bottom)*2))
	for layer in range(layers):
		var t: float=(float(layer)+0.5)/float(layers)
		var radius: float=maxf(0.75,height*0.4*pow(sin(t*PI),0.45))
		var offset:=Vector2(0.5 if layer%3==0 else 0.0,0.5 if layer%4==1 else 0.0)
		var color: int=3 if t<0.3 else (1 if t<0.75 else LEAF)
		_octagon(Vector2(p.x,p.z)+offset,radius,p.y+bottom+layer*0.5,p.y+bottom+(layer+1)*0.5,color)

func _cypress(p: Vector3,height: float) -> void:
	_trees+=1
	_box(p+Vector3(-0.25,0,-0.25),p+Vector3(0.25,height*0.5,0.25),WOOD)
	for i in range(4):
		var width:=2.5-float(i)*0.5
		_box(p+Vector3(-width*0.5,1.5+i*1.5,-width*0.5),p+Vector3(width*0.5,minf(height,3.5+i*1.5),width*0.5),3 if i%2==0 else LEAF)

func _lamp(p: Vector3) -> void:
	_box(p+Vector3(-0.5,0,-0.5),p+Vector3(0.5,0.5,0.5),LIGHT)
	_box(p+Vector3(-0.25,0.5,-0.25),p+Vector3(0.25,3.5,0.25),DARK)
	_details.add_box(p+Vector3(0,3.875,0),Vector3(0.75,0.75,0.75),GOLD)
	_details.add_box(p+Vector3(0,4.375,0),Vector3(1,0.25,1),BLUE)

func _compass(p: Vector3,radius: float) -> void:
	_details.add_box(p,Vector3(radius*2,0.0625,0.25),GOLD,PI*0.25)
	_details.add_box(p,Vector3(radius*2,0.0625,0.25),GOLD,-PI*0.25)

func _box(a: Vector3,b: Vector3,id: int) -> void:
	_v.box(Vector3i(roundi(a.x*2),roundi(a.y*2),roundi(a.z*2)),Vector3i(roundi(b.x*2),roundi(b.y*2),roundi(b.z*2)),id)
