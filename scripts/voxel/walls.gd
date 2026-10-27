extends RefCounted
## A half-metre voxel fortress: regular octagonal plan, hollow towers, arched
## gatehouses, a continuous wall walk, and one usable stair from the interior.
## This generator only describes solid cells; exposed-face greedy meshing is
## performed by the shared volume, so there is no node for every little block.

const BASE_Y := 4
const WALK_Y := 32
const HALF := 256
const CORNER := 106
const STONE := 4
const LIGHT := 5
const DARK := 6
const BLUE := 7
const BLUE_LIGHT := 8
const WOOD := 9
const WOOD_DARK := 10
const GOLD := 17
const MOSS := 18
const CREAM := 20

var _v: Variant
var _writes := 0
var _columns := 0
var _vertices := PackedVector2Array([
	Vector2(-106,-256),Vector2(106,-256),Vector2(256,-106),Vector2(256,106),
	Vector2(106,256),Vector2(-106,256),Vector2(-256,106),Vector2(-256,-106)])


func build(volume: Variant) -> Dictionary:
	_v = volume
	_writes = 0
	_columns = 0
	for i in range(8):
		_wall_span(_vertices[i], _vertices[(i + 1) % 8])
	for i in range(8):
		var p := _vertices[i]
		_tower(roundi(p.x), roundi(p.y), 12, 48, true)
		var toward_previous := (_vertices[(i + 7) % 8] - p).normalized()
		var toward_next := (_vertices[(i + 1) % 8] - p).normalized()
		_tower_passage(p, toward_previous, 13)
		_tower_passage(p, toward_next, 13)

	var gate_data := [
		{"id":"north_gate", "title":"北門", "c":Vector2i(0,-256), "t":Vector2i(1,0), "n":Vector2i(0,-1)},
		{"id":"east_gate", "title":"東門", "c":Vector2i(256,0), "t":Vector2i(0,1), "n":Vector2i(1,0)},
		{"id":"south_gate", "title":"南門", "c":Vector2i(0,256), "t":Vector2i(-1,0), "n":Vector2i(0,1)},
		{"id":"west_gate", "title":"西門", "c":Vector2i(-256,0), "t":Vector2i(0,-1), "n":Vector2i(-1,0)}]
	var gates: Array[Dictionary] = []
	for gate in gate_data:
		_gatehouse(gate["c"], gate["t"], gate["n"])
		var center: Vector2i = gate["c"]
		gates.append({"id":gate["id"], "title":gate["title"], "position":Vector3(center.x * 0.5, 2.0, center.y * 0.5), "kind":"gate"})
	_stair()
	var vertices_world := PackedVector2Array()
	for p in _vertices:
		vertices_world.append(p * 0.5)
	return {
		"city_vertices":vertices_world,
		"gates":gates,
		"stairs":{
			"bottom":Vector3(-123.75,2.0,18.0),
			"top":Vector3(-123.75,16.0,46.0),
			"width":2.5,"step_height":0.5,"step_depth":1.0},
		"wall_walk_height":16.0,
		"corner_towers":8,"gatehouses":4,"gate_towers":8,
		"wall_columns":_columns,"voxel_writes":_writes}


func _put(x: int,y: int,z: int, material: int) -> void:
	_v.set_voxel(Vector3i(x,y,z),material)
	_writes += 1


func _column(x: int,z: int,y0: int,y1: int,material: int) -> void:
	if y1 <= y0:
		return
	_v.box(Vector3i(x,y0,z),Vector3i(x+1,y1,z+1),material)
	_writes += y1-y0


func _erase_column(x: int,z: int,y0: int,y1: int) -> void:
	_v.erase_box(Vector3i(x,y0,z),Vector3i(x+1,y1,z+1))


func _wall_span(a: Vector2,b: Vector2) -> void:
	var tangent := (b-a).normalized()
	var outward := Vector2(tangent.y,-tangent.x)
	var length := a.distance_to(b)
	var min_x := floori(minf(a.x,b.x))-7
	var max_x := ceili(maxf(a.x,b.x))+7
	var min_z := floori(minf(a.y,b.y))-7
	var max_z := ceili(maxf(a.y,b.y))+7
	for x in range(min_x,max_x):
		for z in range(min_z,max_z):
			var p := Vector2(x+0.5,z+0.5)
			var t := (p-a).dot(tangent)
			if t < 0 or t > length:
				continue
			var distance := (p-a).dot(outward)
			var d := absf(distance)
			if d > 6.3:
				continue
			# A broad, stepped plinth gives the wall real weight at ground level.
			if d <= 5.0:
				_column(x,z,BASE_Y,BASE_Y+2,DARK)
			if d <= 4.0:
				_column(x,z,BASE_Y+2,BASE_Y+4,STONE)
			if d <= 3.0:
				_columns += 1
				_column(x,z,BASE_Y+4,WALK_Y,STONE)
				_column(x,z,BASE_Y+4,BASE_Y+5,LIGHT)
				_column(x,z,WALK_Y-3,WALK_Y-2,LIGHT)
				_column(x,z,WALK_Y-1,WALK_Y,DARK)
				if d > 2.0:
					# Large masonry courses remain mergeable; no per-voxel noise.
					for y in range(BASE_Y+5,WALK_Y-3,3):
						var course := floori(float(y)/3.0)
						var block_index := floori((t+float(course%2)*3.0)/6.0)
						var hash_value := posmod(block_index*13+course*7,23)
						if hash_value == 2 or hash_value == 3:
							_column(x,z,y,mini(y+3,WALK_Y-3),LIGHT)
						elif hash_value == 14:
							_column(x,z,y,mini(y+3,WALK_Y-3),DARK)
					_column(x,z,WALK_Y,WALK_Y+2,STONE)
					if posmod(floori(t/3.0),2)==0:
						_column(x,z,WALK_Y+2,WALK_Y+5,LIGHT)
					# Arrow loops are recesses, not flat painted windows.
					if distance > 2.3 and posmod(floori(t),28)==12:
						_erase_column(x,z,18,23)
				if d > 2.5 and posmod(floori(t/9.0)+floori(float(x)/5.0),17)==0:
					_column(x,z,BASE_Y+2,BASE_Y+4,MOSS)
			# The outer buttresses taper through three steps into the wall body.
			if distance > 3.0 and fposmod(t+4.0,28.0)<4.0:
				if distance < 6.0:
					_column(x,z,BASE_Y+2,12,DARK)
				if distance < 5.0:
					_column(x,z,12,19,STONE)
				if distance < 4.0:
					_column(x,z,19,25,LIGHT)


func _inside_oct(x: float,z: float,radius: int) -> bool:
	return absf(x)<=radius and absf(z)<=radius and absf(x)+absf(z)<=float(radius)*1.41421356


func _tower(cx: int,cz: int,radius: int,top: int,corner_tower: bool) -> void:
	for x in range(cx-radius-2,cx+radius+2):
		for z in range(cz-radius-2,cz+radius+2):
			var dx := float(x)+0.5-cx
			var dz := float(z)+0.5-cz
			if _inside_oct(dx,dz,radius+2):
				_column(x,z,BASE_Y,BASE_Y+3,DARK)
			if not _inside_oct(dx,dz,radius):
				continue
			var outer_ring := not _inside_oct(dx,dz,radius-3)
			if outer_ring:
				_column(x,z,BASE_Y+3,top,STONE)
				_column(x,z,BASE_Y+5,BASE_Y+6,LIGHT)
				_column(x,z,top-5,top-3,LIGHT)
				_column(x,z,top-2,top,DARK)
				if posmod(floori((dx+dz)/4.0),7)==2:
					_column(x,z,12,15,LIGHT)
				# Deep, narrow arrow slits on four faces of the tower.
				if ((absf(dx)<1.0 and absf(dz)>radius-2.0) or (absf(dz)<1.0 and absf(dx)>radius-2.0)):
					_erase_column(x,z,20,25)
			# The accessible floor meets the wall walk, not an isolated upper room.
			_column(x,z,WALK_Y-1,WALK_Y,DARK)
			_column(x,z,top-2,top-1,STONE)
	# A stepped eave and a faceted blue roof are made entirely of voxel cells.
	for layer in range(radius+2):
		var r := radius+2-layer
		var y := top+layer
		for x in range(cx-r,cx+r):
			for z in range(cz-r,cz+r):
				if _inside_oct(x+0.5-cx,z+0.5-cz,r):
					var material := BLUE_LIGHT if layer%5==0 else BLUE
					_put(x,y,z,material)
	_v.box(Vector3i(cx-1,top+radius+1,cz-1),Vector3i(cx+1,top+radius+4,cz+1),GOLD)
	if corner_tower:
		# Broad crest panels, set into the upper tower rather than floating signs.
		for side in [-1,1]:
			_v.box(Vector3i(cx-2,top-12,cz+side*(radius-1)),Vector3i(cx+2,top-5,cz+side*(radius-1)+1),BLUE)
			_v.box(Vector3i(cx-1,top-10,cz+side*(radius-1)-1),Vector3i(cx+1,top-7,cz+side*(radius-1)+2),CREAM)


func _tower_passage(center: Vector2,direction: Vector2,radius: int) -> void:
	var normal := Vector2(-direction.y,direction.x)
	for x in range(floori(center.x)-radius,ceili(center.x)+radius):
		for z in range(floori(center.y)-radius,ceili(center.y)+radius):
			var p := Vector2(x+0.5,z+0.5)-center
			if p.dot(direction)>=-1.0 and absf(p.dot(normal))<2.0:
				_erase_column(x,z,WALK_Y,WALK_Y+6)


func _gatehouse(center: Vector2i,tangent: Vector2i,normal: Vector2i) -> void:
	# A deep gate passage, upper gallery, side turrets, and a block-stepped arch.
	for u in range(-13,13):
		for n in range(-7,8):
			var p := center+tangent*u+normal*n
			if abs(u)>=10 or abs(n)>=5:
				_column(p.x,p.y,BASE_Y,39,STONE)
				_column(p.x,p.y,8,10,LIGHT)
				_column(p.x,p.y,35,37,LIGHT)
			_column(p.x,p.y,WALK_Y-1,WALK_Y,DARK)
			# The arch has a squared masonry surround with a true round opening.
			if absf(float(u)+0.5)<9.0:
				var crown := 14+floori(sqrt(maxf(0.0,81.0-pow(float(u)+0.5,2))))
				_erase_column(p.x,p.y,BASE_Y,crown)
				if abs(n)>=5:
					_column(p.x,p.y,crown,crown+2,LIGHT)
			if abs(u)>=10 and abs(n)<2:
				_erase_column(p.x,p.y,WALK_Y,WALK_Y+6)
			# Window recesses in the room above the arch.
			if (u>=-8 and u<=-6) or (u>=5 and u<=7):
				if abs(n)>=5:
					_erase_column(p.x,p.y,27,31)
			if n==7 and (u==-12 or u==11):
				_column(p.x,p.y,BASE_Y+8,BASE_Y+11,GOLD)
	# The raised central roof reads as a gatehouse, not another wall segment.
	for layer in range(9):
		var half_depth := 9-layer
		for u in range(-15,15):
			for n in range(-half_depth,half_depth+1):
				var p := center+tangent*u+normal*n
				_put(p.x,39+layer,p.y,BLUE_LIGHT if layer%4==0 else BLUE)
	for side in [-1,1]:
		var p: Vector2i = center+tangent*side*19
		_tower(p.x,p.y,8,41,false)
		_tower_passage(Vector2(p),Vector2(tangent),10)
		_tower_passage(Vector2(p),Vector2(-tangent),10)
	# The raised portcullis sits above head height; its depth and lattice make
	# the opening read as a defended city gate without obstructing the passage.
	for u in [-8,-4,0,4,8]:
		var p: Vector2i = center+tangent*u+normal*8
		_column(p.x,p.y,22,30,WOOD_DARK)
	for y in [24,28]:
		for u in range(-9,10):
			var p: Vector2i = center+tangent*u+normal*9
			_put(p.x,y,p.y,WOOD)
	# Tall but simple heraldic banners frame the entry, with a clear central path.
	for side in [-1,1]:
		for u_offset in range(-2,3):
			var p: Vector2i = center+tangent*(side*12+u_offset)+normal*8
			_column(p.x,p.y,22,32,BLUE)
			if abs(u_offset)<=0:
				_column(p.x,p.y,24,29,CREAM)
			if (u_offset+side)%2==0:
				_put(p.x,21,p.y,BLUE)


func _stair() -> void:
	# 28 half-metre risers, one-metre treads: a walkable 1:2 military stair.
	var start_z := 36
	for step in range(WALK_Y-BASE_Y):
		var top := BASE_Y+step+1
		var z := start_z+step*2
		_v.box(Vector3i(-251,BASE_Y,z),Vector3i(-244,top,z+2),STONE)
		_v.box(Vector3i(-250,top-1,z),Vector3i(-245,top,z+2),DARK)
		# Continuous low side rails follow the slope instead of blocking treads.
		_column(-251,z,top,top+2,LIGHT)
		_column(-251,z+1,top,top+2,LIGHT)
		_column(-245,z,top,top+2,LIGHT)
		_column(-245,z+1,top,top+2,LIGHT)
	# The top platform overlaps the inner edge of the wall walk.
	_v.box(Vector3i(-258,WALK_Y-1,90),Vector3i(-244,WALK_Y,96),DARK)
	# A clean opening through the inner parapet gives access to the deck.
	_v.erase_box(Vector3i(-254,WALK_Y,90),Vector3i(-250,WALK_Y+6,96))
