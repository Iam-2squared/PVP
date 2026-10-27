extends RefCounted
## Runtime arena rules. The accepted city meshes are never regenerated.
const CITY_HALF := 160.0
const SPAWN_Y := 2.15
const GATE_HEIGHT := 13.0

static func spawn_points() -> Array[Vector3]:
	return [Vector3(0,SPAWN_Y,150),Vector3(-150,SPAWN_Y,0),Vector3(0,SPAWN_Y,-150),Vector3(150,SPAWN_Y,0)]

static func inside_city(point: Vector3,margin: float=3.0) -> bool:
	var limit:=CITY_HALF-margin
	return absf(point.x)<=limit and absf(point.z)<=limit and absf(point.x)+absf(point.z)<=CITY_HALF*sqrt(2.0)-margin

static func safe_position(point: Vector3,last_safe: Vector3,spawn_index: int=0) -> Vector3:
	if point.is_finite() and inside_city(point) and point.y>=1.0 and point.y<120.0: return point
	if last_safe.is_finite() and inside_city(last_safe) and last_safe.y>=1.0 and last_safe.y<120.0: return last_safe
	return spawn_points()[posmod(spawn_index,4)]

static func close_gates(world: Node3D) -> Node3D:
	var existing:=world.get_node_or_null("ArenaGateClosures")
	if existing!=null: return existing
	var root:=Node3D.new()
	root.name="ArenaGateClosures"
	var iron:=StandardMaterial3D.new()
	iron.albedo_color=Color("39464a")
	iron.roughness=0.9
	var bronze:=StandardMaterial3D.new()
	bronze.albedo_color=Color("a88a50")
	bronze.roughness=0.95
	for index in range(4):
		var gate:=Node3D.new()
		gate.name=["SouthGateClosed","WestGateClosed","NorthGateClosed","EastGateClosed"][index]
		gate.position=[Vector3(0,2,157),Vector3(-157,2,0),Vector3(0,2,-157),Vector3(157,2,0)][index]
		gate.rotation.y=PI*0.5 if index%2==1 else 0.0
		root.add_child(gate)
		var body:=StaticBody3D.new()
		body.name="GateBarrier"
		var shape:=CollisionShape3D.new()
		shape.position.y=GATE_HEIGHT*0.5
		var box:=BoxShape3D.new()
		box.size=Vector3(12.0,GATE_HEIGHT,1.0)
		shape.shape=box
		body.add_child(shape)
		gate.add_child(body)
		# A visible portcullis closes the existing stone arch at runtime.
		for x in range(-11,12):
			_gate_box(gate,Vector3(x*0.5,GATE_HEIGHT*0.5,0),Vector3(0.16,GATE_HEIGHT,0.26),iron)
		for y in [1.0,4.0,7.0,10.0,12.5]:
			_gate_box(gate,Vector3(0,y,0),Vector3(12,0.22,0.32),bronze)
		_merge_gate(gate,[iron,bronze])
	world.add_child(root)
	return root

static func _gate_box(parent:Node3D,at:Vector3,size:Vector3,material:Material)->void:
	var visual:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	visual.mesh=mesh
	visual.position=at
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)

static func _merge_gate(gate:Node3D,materials:Array)->void:
	# Two shared-material batches per gate, rather than a draw call per bar.
	var boxes:Array=[]
	for child in gate.get_children():
		if child is MeshInstance3D:boxes.append(child)
	for material:Material in materials:
		var tool:=SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(material)
		for box:MeshInstance3D in boxes:
			if box.material_override==material:tool.append_from(box.mesh,0,box.transform)
		var visual:=MeshInstance3D.new()
		visual.mesh=tool.commit()
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gate.add_child(visual)
	for box in boxes:
		gate.remove_child(box)
		box.free()
