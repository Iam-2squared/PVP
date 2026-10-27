extends RefCounted
## Permanent, physical shopfront signs. Boards and large pictograms share the
## town's voxel mesh; the eight names are baked, flat glyph ArrayMeshes.
## Text is fixed to the facade, never a camera-facing overlay or live label.

const FONT = preload("res://assets/fonts/ui.otf")
const TITLES := {
	"adventurers_guild":"冒険者ギルド", "blacksmith":"鍛冶屋",
	"weapon_shop":"武器店", "tavern":"灯火の酒場", "apothecary":"薬屋",
	"inn":"東の宿屋", "town_hall":"市庁舎", "church":"王都の教会",
}
const ICONS := {
	"adventurers_guild":"crossed_swords", "blacksmith":"hammer_anvil",
	"weapon_shop":"sword", "tavern":"mug", "apothecary":"mortar",
	"inn":"bed", "town_hall":"crown", "church":"cross",
}

var _v: Variant
var _basis := Basis.IDENTITY
var _origin := Vector3.ZERO
var _text_materials: Dictionary = {}

func build(volume: Variant, _details: Variant, buildings: Array) -> Node3D:
	_v = volume
	var root := Node3D.new()
	root.name = "FacilitySigns"
	var metadata: Array[Dictionary] = []
	var captures: Array[Dictionary] = []
	var triangles := 0
	for building: Dictionary in buildings:
		var id := str(building.get("id", ""))
		if not TITLES.has(id): continue
		var entry: Vector3 = building["entrance"]
		var front: Vector3 = building.get("front_direction", Basis(Vector3.UP, float(building.get("orientation", 0.0))) * Vector3.FORWARD)
		front.y = 0
		front = front.normalized()
		var angle := atan2(front.x, front.z)
		_basis = Basis(Vector3.UP, angle)
		var width := minf(float(building.get("width", 7.0)) - 0.5, 8.0)
		var height := 2.0
		var y := 6.25
		var board_color := 20
		var frame_color := 10
		var text_color := Color("30291f")
		match id:
			"adventurers_guild":
				width = 11.5
				height = 2.5
				y = 8.5
				board_color = 7
				frame_color = 17
				text_color = Color("f3de9b")
			"blacksmith":
				width = 7.0
				board_color = 22
				frame_color = 23
				text_color = Color("f7d9a4")
			"tavern":
				width = 8.5
				y = 8.25
				board_color = 25
				text_color = Color("fff0ce")
			"apothecary":
				board_color = 26
				text_color = Color("f4ead2")
			"church":
				width = 8.0
				y = 9.75
				frame_color = 17
			"town_hall":
				width = 8.0
				frame_color = 23
		# Civic entrances are on the facade; house entrances are 1m outside.
		# Both mounts therefore remain outside the shell, with no foot-level post
		# or sign support in any of the advertised entrance corridors.
		var facade_offset := 0.65 if building.has("front_direction") else -0.35
		# The guild's deep portico projects 3m beyond the actual door. Mount
		# the sign ahead of that roof's front face, so its gable cannot hide it.
		if id == "adventurers_guild": facade_offset = 3.65
		_origin = (Vector3(entry.x, y, entry.z) + front * facade_offset).snapped(Vector3.ONE * 0.5)
		_board(width, height, board_color, frame_color)
		var text := _name_mesh(str(TITLES[id]), width - 1.0, height - 0.65, text_color)
		text.name = "FacilityText_" + id
		text.rotation.y = angle
		var bounds := text.mesh.get_aabb()
		text.position = _origin + _basis * Vector3(-bounds.get_center().x, -bounds.get_center().y, 0.57)
		text.visibility_range_end = 200.0
		text.visibility_range_end_margin = 12.0
		text.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(text)
		triangles += text.mesh.get_faces().size() / 3
		var icon := str(ICONS[id])
		if id == "adventurers_guild":
			_guild_badge(height * 0.5 + 3.0)
		elif id == "blacksmith":
			_forge_badge(height * 0.5 + 2.25)
		else:
			_small_badge(icon, width * 0.5 - 1.2, height * 0.5 + 1.6)
		metadata.append({"id":id, "title":str(TITLES[id]), "kind":building.get("kind", "shop"), "entrance":entry, "position":_origin, "front_direction":front, "width":width, "height":height, "text_node":str(text.name), "icon_kind":icon})
		if id == "adventurers_guild":
			captures.append({"id":"guild_sign", "title":"冒険者ギルドの看板", "position":entry+front*18, "target":_origin+Vector3.UP*1.5})
		elif id == "blacksmith":
			captures.append({"id":"blacksmith_sign", "title":"鍛冶屋の看板", "position":entry+front*5, "target":_origin+Vector3.UP})
	root.set_meta("facility_signs", metadata)
	root.set_meta("sign_count", metadata.size())
	root.set_meta("text_triangles", triangles)
	root.set_meta("capture_viewpoints", captures)
	return root

func _name_mesh(title: String, width: float, height: float, color: Color) -> MeshInstance3D:
	var glyphs := TextMesh.new()
	glyphs.font = FONT
	glyphs.text = title
	glyphs.font_size = 32
	glyphs.pixel_size = 0.04
	glyphs.curve_step = 2.0
	glyphs.depth = 0.0
	var size := glyphs.get_aabb().size
	var factor := minf(width / maxf(size.x, 0.01), height / maxf(size.y, 0.01))
	var mesh := ArrayMesh.new()
	# Bake the outlines now. Runtime scenes need neither font layout nor live
	# TextMesh reconstruction, and the same glyph geometry exports to GLB.
	for surface in range(glyphs.get_surface_count()):
		var arrays := glyphs.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()): vertices[i] *= factor
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var key := color.to_html()
	if not _text_materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.resource_name = "PaintedSignLetters_" + key
		_text_materials[key] = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _text_materials[key]
	return instance

func _box(local: Vector3, size: Vector3, color: int) -> void:
	var a := _origin + _basis * (local - size * 0.5)
	var b := _origin + _basis * (local + size * 0.5)
	var lo := a.min(b)
	var hi := a.max(b)
	_v.box(Vector3i(roundi(lo.x*2),roundi(lo.y*2),roundi(lo.z*2)), Vector3i(roundi(hi.x*2),roundi(hi.y*2),roundi(hi.z*2)), color)

func _board(width: float, height: float, color: int, frame: int) -> void:
	# Solid backing reaches z=0.5; glyphs sit 7cm in front of that face.
	_box(Vector3.ZERO, Vector3(width, height, 1.0), color)
	for side in [-1.0,1.0]:
		_box(Vector3(side*(width*0.5+0.25),0,0),Vector3(0.5,height+1,1),frame)
		_box(Vector3(0,side*(height*0.5+0.25),0),Vector3(width+0.5,0.5,1),frame)
	# Short iron hangers tie the ornamental board back into the actual facade.
	for x in [-width*0.35,width*0.35]:
		_box(Vector3(x,height*0.5+0.75,-0.25),Vector3(0.5,1.5,1),22)

func _guild_badge(y: float) -> void:
	# A five-metre heraldic shield and paired blades read as a guild landmark
	# even when the name below is too far away to read.
	for i in range(8):
		var span := 4.5 if i >= 3 else 1.5+float(i)
		_box(Vector3(0,y-2+float(i)*0.5,0),Vector3(span,0.5,1),17)
		_box(Vector3(0,y-2+float(i)*0.5,0.5),Vector3(maxf(span-1,0.5),0.5,0.5),7)
	for direction in [-1.0,1.0]:
		for i in range(9):
			var x: float = (-2.0+float(i)*0.5)*direction
			_box(Vector3(x,y-1.5+float(i)*0.5,1),Vector3(0.5,0.5,0.5),20)
		_box(Vector3(direction*-1.75,y-1.25,1.0),Vector3(1.5,0.5,0.5),17)
		_box(Vector3(direction*-2.25,y-2.0,1.0),Vector3(0.5,1,0.5),10)
	# Crowning parchment seal, visibly distinct from the weapon shop's one blade.
	_box(Vector3(0,y+2.25,0),Vector3(2.5,0.5,1),17)
	_box(Vector3(0,y+2.75,0),Vector3(0.5,0.5,1),17)

func _forge_badge(y: float) -> void:
	_box(Vector3(0,y,0),Vector3(4.5,4.5,0.5),23)
	_box(Vector3(0,y,0.5),Vector3(3.5,3.5,0.5),22)
	# Anvil: long table, projecting horn, narrow waist and splayed foot.
	_box(Vector3(0,y-0.5,1),Vector3(3.0,0.5,0.5),20)
	_box(Vector3(-1.75,y-0.5,1),Vector3(0.5,0.5,0.5),17)
	_box(Vector3(0.25,y-1.0,1),Vector3(1.0,0.5,0.5),20)
	_box(Vector3(0.25,y-1.5,1),Vector3(2.0,0.5,0.5),20)
	# Raised hammer poised over the anvil.
	for i in range(4): _box(Vector3(-0.5+float(i)*0.5,y+float(i)*0.5,1),Vector3(0.5,0.5,0.5),9)
	_box(Vector3(1.0,y+1.5,1),Vector3(2.0,1.0,0.5),17)
	for side in [-1.0,1.0]: _box(Vector3(side*2,y+2.5,0),Vector3(0.5,1.0,0.5),28)

func _small_badge(icon: String, x: float, y: float) -> void:
	_box(Vector3(x,y,0),Vector3(3.0,3.0,0.5),10)
	_box(Vector3(x,y,0.5),Vector3(2.0,2.0,0.5),17)
	match icon:
		"sword":
			_box(Vector3(x,y+0.5,1),Vector3(0.5,2,0.5),20)
			_box(Vector3(x,y-0.25,1),Vector3(1.5,0.5,0.5),22)
			_box(Vector3(x,y-0.75,1),Vector3(0.5,0.5,0.5),10)
		"mug":
			_box(Vector3(x-0.25,y-0.25,1),Vector3(1.0,1.5,0.5),20)
			_box(Vector3(x-0.25,y+0.75,1),Vector3(1.5,0.5,0.5),31)
			_box(Vector3(x+0.75,y,1),Vector3(0.5,1,0.5),20)
			_box(Vector3(x+0.5,y-0.75,1),Vector3(1,0.5,0.5),20)
		"mortar":
			_box(Vector3(x,y-0.5,1),Vector3(1.5,0.5,0.5),26)
			_box(Vector3(x,y,1),Vector3(2.0,0.5,0.5),26)
			for i in range(3): _box(Vector3(x-0.5+float(i)*0.5,y+float(i)*0.5,1),Vector3(0.5,0.5,0.5),20)
		"bed":
			_box(Vector3(x,y-0.25,1),Vector3(2,0.5,0.5),7)
			_box(Vector3(x-0.75,y+0.25,1),Vector3(0.5,1.5,0.5),20)
			_box(Vector3(x-0.25,y+0.25,1),Vector3(0.5,0.5,0.5),20)
		"cross":
			_box(Vector3(x,y,1),Vector3(0.5,2.5,0.5),20)
			_box(Vector3(x,y+0.5,1),Vector3(2,0.5,0.5),20)
		"crown":
			_box(Vector3(x,y-0.5,1),Vector3(2,0.5,0.5),7)
			for dx in [-0.75,0.0,0.75]: _box(Vector3(x+dx,y+0.25,1),Vector3(0.5,1,0.5),7)
