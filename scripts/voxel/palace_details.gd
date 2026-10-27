extends RefCounted
## Fine, solid block details. Each floor stays a separate, culled CPU mesh.
const Details=preload("res://scripts/voxel/detail_builder.gd")
var _builders: Dictionary={}

func build(description: Dictionary) -> Array[Node3D]:
	_builders.clear()
	for furnishing in description.get("furnishings",[]):
		var p: Vector3=furnishing["position"]
		var d=_builder(p.y)
		match str(furnishing["kind"]):
			"table": _table(d,p,float(furnishing.get("length",10.0)),_table_purpose(description,p))
			"desk": _writing(d,p)
			"bookcase": _shelf(d,p,float(furnishing.get("width",5.0)))
			"bed": _curtains(d,p)
			"hearth": _hearth(d,p)
			"throne": _regalia(d,p)
	for room in description.get("rooms",[]):
		var id: String=room.get("id","")
		if id in ["forecourt","observatory","gallery","armory","guard"]: continue
		var bounds: AABB=room["bounds"]
		var p:=bounds.get_center()
		var level: float=float(room.get("level",bounds.position.y))
		var height: float=maxf(bounds.size.y-0.5,2.5)
		_chandelier(_builder(level),Vector3(p.x,level+height,p.z),id in ["great_hall","throne","chapel"])
	var result: Array[Node3D]=[]
	for level in _builders:
		var node: Node3D=_builders[level].finish()
		node.name="PalaceInterior_Details_%d"%int(level)
		node.set_meta("floor_y",float(level))
		result.append(node)
	return result

func _builder(level: float):
	var floor_y:=floorf((level-3.0)/6.0)*6.0+3.0
	if not _builders.has(floor_y): _builders[floor_y]=Details.new()
	return _builders[floor_y]

func _box(d,c: Vector3,s: Vector3,color: int) -> void:
	d.add_box(c,s,color)

func _candle(d,p: Vector3,height: float=0.5) -> void:
	_box(d,p+Vector3(0,0.0625,0),Vector3(0.375,0.125,0.375),23)
	_box(d,p+Vector3(0,height*0.5+0.125,0),Vector3(0.125,height,0.125),31)
	_box(d,p+Vector3(0,height+0.1875,0),Vector3(0.125,0.125,0.125),28)

func _goblet(d,p: Vector3) -> void:
	_box(d,p+Vector3(0,0.03125,0),Vector3(0.25,0.0625,0.25),23)
	_box(d,p+Vector3(0,0.15625,0),Vector3(0.125,0.1875,0.125),23)
	_box(d,p+Vector3(0,0.28125,0),Vector3(0.25,0.125,0.25),23)
	_box(d,p+Vector3(0,0.35,0),Vector3(0.125,0.0625,0.125),21)

func _table_purpose(description: Dictionary,p: Vector3) -> String:
	for room in description.get("rooms",[]):
		if absf(float(room.get("level",0.0))-p.y)>1.5: continue
		var bounds: AABB=room["bounds"]
		if not bounds.has_point(p+Vector3.UP*0.25): continue
		var id: String=room["id"]
		if id in ["library","archive","study","royal_study"]: return "reading"
		if id in ["council","map_room"]: return "map"
	return "dining"

func _open_book(d,p: Vector3) -> void:
	_box(d,p+Vector3.UP*0.0625,Vector3(0.625,0.125,0.625),29)
	for side in [-1.0,1.0]:
		_box(d,p+Vector3(side*0.15625,0.15625,0),Vector3(0.25,0.0625,0.5),20)
		for line in range(3):
			_box(d,p+Vector3(side*0.15625,0.203125,-0.125+float(line)*0.125),Vector3(0.15625,0.03125,0.03125),10)

func _table(d,p: Vector3,length: float,purpose: String) -> void:
	for z in range(-floori(length*0.5)+1,floori(length*0.5),2):
		for side in [-1.0,1.0]:
			var q:=p+Vector3(side*0.875,1.04,z+0.5)
			if purpose=="reading":
				_open_book(d,q)
			else:
				_box(d,q,Vector3(0.5,0.0625,0.5),29)
				_box(d,q+Vector3.UP*0.04,Vector3(0.375,0.0625,0.375),20)
				if purpose=="dining": _box(d,q+Vector3(0,0.125,0),Vector3(0.25,0.125,0.125),25)
				_goblet(d,q+Vector3(-side*0.2,0.02,0.5))
		_candle(d,p+Vector3(0,1.05,z+0.25),0.375)
	if purpose=="reading":
		_open_book(d,p+Vector3(0,1.0,0))
		return
	if purpose=="map":
		_box(d,p+Vector3(0,1.0625,0),Vector3(1.5,0.125,1.75),20)
		for i in range(7):
			_box(d,p+Vector3(sin(float(i))*0.375,1.15625,-0.75+float(i)*0.25),Vector3(0.125,0.0625,0.25),29)
		for x in [-0.75,0.75]: _box(d,p+Vector3(x,1.125,0),Vector3(0.125,0.125,2),9)
		return
	# A raised serving platter and individual bread/fruit blocks.
	_box(d,p+Vector3(0,1.0625,0),Vector3(0.75,0.125,0.75),23)
	for i in range(4):
		var x:=float(i%2)*0.25-0.125
		var z:=float(i/2)*0.25-0.125
		_box(d,p+Vector3(x,1.21875,z),Vector3(0.1875,0.1875,0.1875),25 if i%2==0 else 21)

func _writing(d,p: Vector3) -> void:
	var paper:=p+Vector3(-1.125,1.04,0)
	_box(d,paper,Vector3(0.625,0.0625,0.75),31)
	for i in range(4):
		_box(d,paper+Vector3(0,0.04,-0.25+float(i)*0.125),Vector3(0.375 if i<3 else 0.25,0.03125,0.03125),10)
	for x in [-0.3,0.3]:
		_box(d,paper+Vector3(x,0.0625,0),Vector3(0.125,0.125,0.875),20)
	_box(d,p+Vector3(1.25,1.09375,-0.25),Vector3(0.125,0.1875,0.125),22)
	d.add_voxel_line(p+Vector3(1.25,1.1875,-0.25),p+Vector3(1.5,1.7,-0.375),0.125,31,0.0)
	_candle(d,p+Vector3(-1.5,1.05,-0.625),0.5)
	for i in range(3):
		_box(d,p+Vector3(0.875,1.0625+float(i)*0.125,0.5),Vector3(0.625,0.125,0.5),[29,21,26][i])
		_box(d,p+Vector3(0.875,1.0625+float(i)*0.125,0.76),Vector3(0.5,0.0625,0.03125),20)

func _shelf(d,p: Vector3,width: float) -> void:
	for y in [0.4,1.9,3.4]:
		for i in range(maxi(1,int(width/1.5))):
			var x: float=-width*0.5+0.75+float(i)*1.5
			_box(d,p+Vector3(x,y,0.56),Vector3(0.375,0.125,0.0625),23)

func _curtains(d,p: Vector3) -> void:
	for side in [-1.0,1.0]:
		for j in range(3):
			_box(d,p+Vector3(side*0.95,2.5-float(j)*0.25,-0.875-float(j)*0.125),Vector3(0.125,0.5+float(j)*0.5,0.375),26)
		_box(d,p+Vector3(side*0.875,1.375,-1.25),Vector3(0.25,0.125,0.5),23)
		_box(d,p+Vector3(side*0.5,2.875,0),Vector3(0.125,0.125,2.0),17)
	for x in [-0.5,0.0,0.5]:
		_box(d,p+Vector3(x,3.125,-1.25),Vector3(0.25,0.125,0.25),17)

func _hearth(d,p: Vector3) -> void:
	for x in [-0.75,-0.375,0.0,0.375,0.75]:
		_box(d,p+Vector3(x,0.5625,-0.5),Vector3(0.25,0.125,0.75),10)
		_box(d,p+Vector3(x,0.8125,-0.5),Vector3(0.125,0.375,0.25),28)
	for x in [-1.0,1.0]:
		d.add_voxel_line(p+Vector3(x,2.0,0),p+Vector3(x,3.25,0),0.125,22,0)
	for i in range(4):
		var q:=p+Vector3(-2.375+float(i)*0.5,3.875,1.0)
		_box(d,q,Vector3(0.125,0.125,0.75),22)
		_box(d,q+Vector3(0,-0.375,-0.375),Vector3(0.25,0.5,0.125),22)

func _regalia(d,p: Vector3) -> void:
	for x in [-0.75,-0.375,0.0,0.375,0.75]:
		_box(d,p+Vector3(x,4.25,0.0625),Vector3(0.125,0.25,0.125),21 if x!=0 else 27)
	for side in [-1.0,1.0]:
		_box(d,p+Vector3(side*1.25,2.125,0.25),Vector3(0.25,0.25,0.5),23)

func _chandelier(d,p: Vector3,large: bool) -> void:
	var radius:=1.5 if large else 1.0
	d.add_voxel_line(p,p-Vector3.UP*1.125,0.125,22,0)
	var centre:=p-Vector3.UP*1.25
	for i in range(8):
		var angle:=float(i)*TAU/8.0
		var a:=centre+Vector3(cos(angle),0,sin(angle))*radius
		var next:=float(i+1)*TAU/8.0
		var b:=centre+Vector3(cos(next),0,sin(next))*radius
		d.add_voxel_line(a,b,0.125,23,0)
		if i%2==0: d.add_voxel_line(p-Vector3.UP*0.5,a,0.125,22,0)
		_candle(d,a+Vector3.UP*0.0625,0.375)
