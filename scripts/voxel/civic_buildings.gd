extends RefCounted
## Independently placeable civic buildings. Local +Z is the public entrance.
## Positions use the shared 0.5m grid; the caller supplies the pavement at y=2.
## Build into world-space Volume/DetailBuilder instances; finish details in caller.
## Only the furnished ground rooms are advertised as enterable.

const STONE := 4
const LIGHT := 5
const DARK := 6
const BLUE := 7
const SKY := 8
const WOOD := 9
const TIMBER := 10
const PLASTER := 11
const GOLD := 17
const PLANK := 19
const CREAM := 20
const RED := 21
const IRON := 22
const BRASS := 23
const TILE := 24
const AMBER := 25
const TEAL := 26
const GLASS := 27
const FIRE := 28

var _v: Variant
var _details: Variant
var _center := Vector2.ZERO
var _q := 0
var _rooms: Array[Dictionary] = []
var _doors: Array[Dictionary] = []
var _routes: Array[Dictionary] = []

func build(v: Variant, details: Variant, kind: String, center: Vector2, quarter_turns: int = 0) -> Dictionary:
	if kind not in ["guild", "tavern", "church"]:
		push_error("Unknown civic building kind: " + kind)
		return {}
	if not center.is_finite():
		push_error("Civic building center must be finite")
		return {}
	_v = v
	_details = details
	_center = center.snapped(Vector2.ONE * 0.5)
	_q = posmod(quarter_turns, 4)
	_rooms.clear()
	_doors.clear()
	_routes.clear()
	var footprint := Vector2.ZERO
	var height := 0.0
	var entrance := Vector3.ZERO
	var storeys := 2
	match kind:
		"guild":
			footprint = Vector2(26, 23)
			height = 20.5
			entrance = Vector3(0, 2.15, 8.5)
			_guild()
		"tavern":
			footprint = Vector2(15, 16)
			height = 17.0
			entrance = Vector3(-2.5, 2.15, 6.5)
			_tavern()
		"church":
			footprint = Vector2(28, 39)
			height = 36.5
			entrance = Vector3(0, 2.15, 18.5)
			storeys = 1
			_church()
	var bounds := _world_bounds(Vector3(-footprint.x * 0.5, 2, -footprint.y * 0.5), Vector3(footprint.x * 0.5, height, footprint.y * 0.5))
	var entry := _world(entrance)
	return {
		"kind": kind, "centre": _center, "center": _center,
		"bounds": bounds, "footprint": Vector2(bounds.size.x, bounds.size.z),
		"local_footprint": footprint, "width": bounds.size.x, "depth": bounds.size.z,
		"height": bounds.size.y, "highest_point": height, "quarter_turns": _q, "rotation_y": float(_q) * PI * 0.5,
		"front_direction": _turn(Vector3.BACK, _q), "entry": entry, "entrance": entry,
		"enterable": true, "enterable_groundroom": _rooms[0],
		"ground_rooms": _rooms.duplicate(true), "rooms": _rooms.duplicate(true),
		"doors": _doors.duplicate(true), "route_waypoints": _routes.duplicate(true),
		"storeys": storeys, "upper_floors_enterable": false,
		"ground_top": 2.0, "adds_ground_plate": false,
		"roof_id": "blue_gabled_guild" if kind == "guild" else ("crossed_tile_tavern" if kind == "tavern" else "nave_transept_belltower"),
	}

func _turn(p: Vector3, turns: int) -> Vector3:
	match posmod(turns, 4):
		1: return Vector3(p.z, p.y, -p.x)
		2: return Vector3(-p.x, p.y, -p.z)
		3: return Vector3(-p.z, p.y, p.x)
	return p

func _world(p: Vector3) -> Vector3:
	return _turn(p, _q) + Vector3(_center.x, 0, _center.y)

func _world_bounds(lo: Vector3, hi: Vector3) -> AABB:
	var a := _world(lo)
	var b := _world(hi)
	return AABB(a.min(b), a.max(b) - a.min(b))

func _box(lo: Vector3, hi: Vector3, material: int) -> void:
	# Rotate boundary corners, not cell indices: negative half-open ranges remain exact.
	# Quantize before world rotation, so half-cell decorative offsets do not round
	# differently at positive and negative world coordinates.
	var a := _world(lo.snapped(Vector3.ONE * 0.5))
	var b := _world(hi.snapped(Vector3.ONE * 0.5))
	var minimum := a.min(b)
	var maximum := a.max(b)
	_v.box(Vector3i(roundi(minimum.x * 2), roundi(minimum.y * 2), roundi(minimum.z * 2)), Vector3i(roundi(maximum.x * 2), roundi(maximum.y * 2), roundi(maximum.z * 2)), material)

func _clear(lo: Vector3, hi: Vector3) -> void:
	_box(lo, hi, 0)

func _panel_box(origin: Vector3, lo: Vector3, hi: Vector3, face: int, material: int) -> void:
	var a := origin + _turn(lo, face)
	var b := origin + _turn(hi, face)
	_box(a.min(b), a.max(b), material)

func _detail_box(pos: Vector3, size: Vector3, material: int, local_rotation: float = 0.0) -> void:
	if _details != null:
		_details.add_box(_world(pos), size, material, local_rotation + float(_q) * PI * 0.5)

func _prop(kind: String, pos: Vector3, local_rotation: float = 0.0) -> void:
	if _details != null:
		_details.call(kind, _world(pos), local_rotation + float(_q) * PI * 0.5)

func _shell(lo: Vector3, hi: Vector3, material: int, thickness: float = 0.5) -> void:
	_box(lo, Vector3(hi.x, hi.y, lo.z + thickness), material)
	_box(Vector3(lo.x, lo.y, hi.z - thickness), hi, material)
	_box(lo, Vector3(lo.x + thickness, hi.y, hi.z), material)
	_box(Vector3(hi.x - thickness, lo.y, lo.z), hi, material)

func _gable(x0: float, x1: float, z0: float, z1: float, base: float, rise: float, color: int, along_x: bool = false) -> void:
	# Hollow, stepped roof skin with closed end gables, eaves and a ridge cap.
	var a := z0 if along_x else x0
	var b := z1 if along_x else x1
	var middle := (a + b) * 0.5
	var half := (b - a) * 0.5
	for i in range(roundi(a * 2), roundi(b * 2)):
		var p := float(i) * 0.5
		var top := snappedf(base + rise * (1.0 - absf(p + 0.25 - middle) / half), 0.5)
		var stripe := SKY if color == BLUE and posmod(int((top - base) * 2), 7) == 0 else color
		if along_x:
			_box(Vector3(x0, top, p), Vector3(x1, top + 0.5, p + 0.5), stripe)
			for x in [x0, x1 - 0.5]:
				_box(Vector3(x, base, p), Vector3(x + 0.5, top, p + 0.5), PLASTER if color == TILE else LIGHT)
		else:
			_box(Vector3(p, top, z0), Vector3(p + 0.5, top + 0.5, z1), stripe)
			for z in [z0, z1 - 0.5]:
				_box(Vector3(p, base, z), Vector3(p + 0.5, top, z + 0.5), PLASTER if color == TILE else LIGHT)
	var ridge_material := TIMBER if color == TILE else GOLD
	if along_x:
		_box(Vector3(x0, base + rise, middle - 0.5), Vector3(x1, base + rise + 0.5, middle + 0.5), ridge_material)
	else:
		_box(Vector3(middle - 0.5, base + rise, z0), Vector3(middle + 0.5, base + rise + 0.5, z1), ridge_material)

func _door(id: String, pos: Vector3, width: float, height: float, face: int = 0, depth: float = 2.0, record: bool = true) -> void:
	# Rectangular 3m clearance below a stepped pointed head. No closed door mesh.
	var rows := roundi(height * 2)
	for i in range(rows):
		var y := float(i) * 0.5
		var taper := maxf(0.0, y - (height - width * 0.5))
		var half := maxf(0.5, width * 0.5 - taper)
		_panel_box(pos, Vector3(-half, y, -depth * 0.5), Vector3(half, y + 0.5, depth * 0.5), face, 0)
	if record:
		_doors.append({"id": id, "position": _world(pos + Vector3.UP * 0.15), "width": width, "height": height, "normal": _turn(_turn(Vector3.BACK, face), _q)})

func _window(pos: Vector3, width: float, height: float, face: int = 0, colored: bool = false) -> void:
	# Stone reveal, narrow central mullion and opaque colored block panes.
	for i in range(roundi(height * 2)):
		var y := float(i) * 0.5
		var taper := maxf(0.0, y - (height - width * 0.75))
		var half := maxf(0.5, width * 0.5 - taper * 0.7)
		_panel_box(pos, Vector3(-half - 0.5, y, -0.75), Vector3(half + 0.5, y + 0.5, 0.75), face, LIGHT)
		_panel_box(pos, Vector3(-half, y, -1), Vector3(half, y + 0.5, 1), face, 0)
		var colors := [BLUE, RED, GOLD, TEAL]
		var pane: int = colors[posmod(floori(float(i) * 0.5), colors.size())] if colored else GLASS
		_panel_box(pos, Vector3(-half, y, -0.5), Vector3(half, y + 0.5, 0), face, pane)
		if width >= 2.0:
			_panel_box(pos, Vector3(-0.25, y, -0.5), Vector3(0.25, y + 0.5, 0.5), face, STONE)
	_panel_box(pos, Vector3(-width * 0.5 - 0.5, -0.5, -1), Vector3(width * 0.5 + 0.5, 0, 1), face, STONE)

func _frame(x0: float, x1: float, z0: float, z1: float, bottom: float, top: float) -> void:
	for y in [bottom, top - 0.5]:
		_box(Vector3(x0, y, z0), Vector3(x1, y + 0.5, z0 + 0.5), TIMBER)
		_box(Vector3(x0, y, z1 - 0.5), Vector3(x1, y + 0.5, z1), TIMBER)
		_box(Vector3(x0, y, z0), Vector3(x0 + 0.5, y + 0.5, z1), TIMBER)
		_box(Vector3(x1 - 0.5, y, z0), Vector3(x1, y + 0.5, z1), TIMBER)
	for x in [x0, x1 - 0.5]:
		for z in [z0, z1 - 0.5]:
			_box(Vector3(x, bottom, z), Vector3(x + 0.5, top, z + 0.5), TIMBER)

func _beams(x0: float, x1: float, z0: float, z1: float, y: float, spacing: float = 3.0) -> void:
	var z := z0
	while z <= z1:
		_box(Vector3(x0, y, z), Vector3(x1, y + 0.5, z + 0.5), TIMBER)
		z += spacing

func _table(center: Vector3, width: float, depth: float) -> void:
	_box(center + Vector3(-width * 0.5, 0.5, -depth * 0.5), center + Vector3(width * 0.5, 1, depth * 0.5), WOOD)
	for x in [-width * 0.5 + 0.5, width * 0.5 - 1.0]:
		for z in [-depth * 0.5 + 0.5, depth * 0.5 - 1.0]:
			_box(center + Vector3(x, 0, z), center + Vector3(x + 0.5, 0.5, z + 0.5), TIMBER)

func _chair(center: Vector3, turns: int = 0) -> void:
	_panel_box(center, Vector3(-0.5, 0, -0.5), Vector3(0.5, 0.5, 0.5), turns, WOOD)
	_panel_box(center, Vector3(-0.5, 0, -0.5), Vector3(0, 0.5, 0), turns, TIMBER)
	_panel_box(center, Vector3(0, 0, 0), Vector3(0.5, 0.5, 0.5), turns, TIMBER)
	_panel_box(center, Vector3(-0.5, 0.5, 0), Vector3(0.5, 1, 0.5), turns, PLANK)

func _bench(center: Vector3, width: float, turns: int = 0) -> void:
	_panel_box(center, Vector3(-width * 0.5, 0, -0.5), Vector3(width * 0.5, 0.5, 0.5), turns, WOOD)
	_panel_box(center, Vector3(-width * 0.5, 0.5, 0), Vector3(width * 0.5, 1, 0.5), turns, TIMBER)
	for x in [-width * 0.5, width * 0.5 - 0.5]:
		_panel_box(center, Vector3(x, 0, -0.5), Vector3(x + 0.5, 0.5, 0.5), turns, TIMBER)

func _room(id: String, title: String, point: Vector3, lo: Vector3, hi: Vector3) -> void:
	_rooms.append({"id": id, "title": title, "position": _world(point), "bounds": _world_bounds(lo, hi), "enterable": true, "floor_level": 2.0})

func _route(id: String, points: Array[Vector3]) -> void:
	var world_points: Array[Vector3] = []
	for point in points:
		world_points.append(_world(point))
	_routes.append({"id": id, "points": world_points})

func _guild() -> void:
	_shell(Vector3(-12, 2, -10.5), Vector3(12, 7.5, 8.5), LIGHT)
	# Jettied upper story, substantial carved beams, and three front gables.
	_box(Vector3(-12.5, 7.5, -11), Vector3(12.5, 8, 9), TIMBER)
	_shell(Vector3(-12.5, 8, -11), Vector3(12.5, 12.5, 9), CREAM)
	_frame(-12.5, 12.5, -11, 9, 8, 12.5)
	_beams(-11.5, 11.5, -9, 7, 7.0, 3.5)
	_gable(-13, 13, -11.5, 9.5, 12.5, 7, BLUE)
	for x in [-8.0, 0.0, 8.0]:
		_shell(Vector3(x - 2.5, 11.5, 7.5), Vector3(x + 2.5, 14.5, 10), LIGHT)
		_gable(x - 3, x + 3, 7.5, 10.5, 14.5, 3.5, BLUE)
		_window(Vector3(x, 12, 9.5), 1.5, 2.5)
	for side in [-1.0, 1.0]:
		for z in [-7.5, -2.5, 3.0]:
			_window(Vector3(side * 11.5, 3.5, z), 2, 3, 1)
			_window(Vector3(side * 12.0, 9, z), 2, 2.5, 1)
		for x in [4.5, 9.0]:
			_window(Vector3(side * x, 3.5, 8), 2, 3)
			_window(Vector3(side * x, 9, -10.5), 2, 2.5)
	# A deep open portico: four stone columns with bases, capitals and architrave.
	for x in [-5.5, -3.5, 3.5, 5.5]:
		_box(Vector3(x - 0.5, 2, 10), Vector3(x + 0.5, 2.5, 11), DARK)
		_box(Vector3(x - 0.25, 2.5, 10.25), Vector3(x + 0.25, 6, 10.75), LIGHT)
		_box(Vector3(x - 0.5, 6, 10), Vector3(x + 0.5, 6.5, 11), GOLD)
	_box(Vector3(-6.5, 6.5, 8), Vector3(6.5, 7, 11.5), STONE)
	_gable(-7, 7, 8, 11.5, 7, 2.5, BLUE)
	# A shield and crossed implements on the upper facade, independent of Disney.
	for i in range(6):
		var width := 3.0 if i < 4 else 3.0 - float(i - 3) * 0.5
		_box(Vector3(-width * 0.5, 9.5 + i * 0.5, 9), Vector3(width * 0.5, 10 + i * 0.5, 9.5), GOLD)
	_detail_box(Vector3(0, 11, 9.625), Vector3(2, 2, 0.125), BLUE)
	for i in range(5):
		var offset := (float(i) - 2) * 0.25
		_detail_box(Vector3(offset, 11 + offset, 9.75), Vector3(0.375, 0.375, 0.125), CREAM)
		_detail_box(Vector3(-offset, 11 + offset, 9.75), Vector3(0.375, 0.375, 0.125), CREAM)
	_door("guild_main", Vector3(0, 2, 8.25), 3, 4.5)
	# Reception desk, room for queues, and a wide central circulation aisle.
	_box(Vector3(-8, 2, -7.5), Vector3(8, 3, -6), WOOD)
	_box(Vector3(-8.5, 3, -8), Vector3(8.5, 3.5, -5.5), TIMBER)
	for x in [-5.5, 5.5]:
		_table(Vector3(x, 2, 0), 5, 2)
		_bench(Vector3(x, 2, -2), 4)
		_bench(Vector3(x, 2, 2), 4, 2)
	for x in [-10.5, 9.5]:
		_box(Vector3(x, 2, -8.5), Vector3(x + 1, 5.5, -3), TIMBER)
		for z in [-7.5, -6.0, -4.5]:
			_detail_box(Vector3(x + 0.5, 4, z), Vector3(0.25, 2.5, 0.25), IRON)
			_detail_box(Vector3(x + 0.5, 3.5, z), Vector3(0.75, 0.125, 0.375), GOLD)
	# Quest board: frame, parchment notes, and wooden feet.
	_box(Vector3(-10, 2, 5), Vector3(-9.5, 5, 5.5), TIMBER)
	_box(Vector3(-7, 2, 5), Vector3(-6.5, 5, 5.5), TIMBER)
	_detail_box(Vector3(-8.25, 4.25, 5.25), Vector3(4, 2.5, 0.25), TIMBER)
	for x in [-9.25, -8.0, -7.0]:
		_detail_box(Vector3(x, 4.25, 5.5), Vector3(0.75, 1.5, 0.125), CREAM)
	for x in [-2.25, 2.25]:
		_prop("lantern", Vector3(x, 4, 8.75), PI)
	_prop("crate", Vector3(10.25, 2, 6.75))
	_room("guild_hall", "冒険者ギルド・依頼受付", Vector3(0, 2.15, 0), Vector3(-11.5, 2, -10), Vector3(11.5, 7, 8))
	_route("guild_reception", [Vector3(0, 2.15, 11.5), Vector3(0, 2.15, 8.5), Vector3(0, 2.15, 2), Vector3(0, 2.15, -4)])
	_route("guild_quest_board", [Vector3(0, 2.15, 7), Vector3(0, 2.15, 5.75), Vector3(-5, 2.15, 5.75), Vector3(-8, 2.15, 6.5)])

func _tavern() -> void:
	# Two intersecting wings make an L, with an open gallery along the front.
	_shell(Vector3(-6.5, 2, -7), Vector3(1, 7, 6.5), PLASTER)
	_shell(Vector3(0.5, 2, -7), Vector3(6.5, 7, 0), PLASTER)
	_box(Vector3(-7, 7, -7.5), Vector3(1.5, 7.5, 7), TIMBER)
	_box(Vector3(0.5, 7, -7.5), Vector3(7, 7.5, 0.5), TIMBER)
	_shell(Vector3(-7, 7.5, -7.5), Vector3(1.5, 10.5, 7), PLASTER)
	_shell(Vector3(0.5, 7.5, -7.5), Vector3(7, 10.5, 0.5), PLASTER)
	_frame(-6.5, 1, -7, 6.5, 2, 7)
	_frame(0.5, 6.5, -7, 0, 2, 7)
	_frame(-7, 1.5, -7.5, 7, 7.5, 10.5)
	_frame(0.5, 7, -7.5, 0.5, 7.5, 10.5)
	_beams(-6, 0.5, -6, 5.5, 6.5, 2.5)
	_beams(1, 6, -6, -0.5, 6.5, 2.5)
	_gable(-7.5, 2, -8, 7.5, 10.5, 4.5, TILE)
	_gable(0.5, 7.5, -8, 1, 10.5, 4.5, TILE, true)
	# Narrow dormer and a crooked-looking stepped chimney break the roof planes.
	_shell(Vector3(-5, 10, 4.5), Vector3(-2, 12, 7), PLASTER)
	_gable(-5.5, -1.5, 4.5, 7.5, 12, 2, TILE)
	_box(Vector3(-6, 6, -6.5), Vector3(-4.5, 16, -5), STONE)
	_box(Vector3(-6.5, 16, -7), Vector3(-4, 16.5, -4.5), DARK)
	for x in [-6.0, -5.0]:
		_box(Vector3(x, 16.5, -6.5), Vector3(x + 0.5, 17, -5), STONE)
	for z in [-4.0, 0.5, 4.0]:
		_window(Vector3(-6.25, 3.5, z), 1.5, 2, 1)
	for x in [2.5, 5.0]:
		_window(Vector3(x, 3.5, -6.75), 1.5, 2)
		_window(Vector3(x, 8, 0.25), 1.5, 2)
	for x in [-5.5, -0.5]:
		_window(Vector3(x, 8, 6.75), 1.5, 2)
	_window(Vector3(6.25, 3.5, -3.5), 2, 2, 1)
	_window(Vector3(6.5, 8, -3.5), 2, 2, 1)
	# Projecting gallery. Posts stay outside the central doorway and its approach.
	_box(Vector3(-6.5, 7, 6.5), Vector3(1, 7.5, 8), TIMBER)
	for x in [-6.0, 0.5]:
		_box(Vector3(x - 0.25, 2, 7.25), Vector3(x + 0.25, 10, 7.75), TIMBER)
		_detail_box(Vector3(x, 4, 7.5), Vector3(0.125, 0.125, 0.125), GOLD)
	for x in [-6.0, -5.0, -4.0, -3.0, -2.0, -1.0, 0.0]:
		_detail_box(Vector3(x, 8, 7.75), Vector3(0.125, 1, 0.125), TIMBER)
	_detail_box(Vector3(-2.75, 8.5, 7.75), Vector3(7.5, 0.125, 0.25), WOOD)
	# Half-timbered diagonal braces are stepped short blocks, not a texture.
	for i in range(5):
		var t := float(i) * 0.5
		_box(Vector3(-6.5 + t, 7.5 + t, 6.5), Vector3(-6 + t, 8 + t, 7), TIMBER)
		_box(Vector3(-1.0 - t, 7.5 + t, 6.5), Vector3(-0.5 - t, 8 + t, 7), TIMBER)
	# Clear the shared wing wall after framing; a 3m side passage serves the snug.
	_clear(Vector3(0, 2, -3), Vector3(1.5, 5.5, 0))
	_door("tavern_main", Vector3(-2.5, 2, 6.25), 2.5, 4)
	_door("tavern_snug", Vector3(0.75, 2, -1.5), 3, 3.5, 1)
	# Tables keep the long aisle at x=-2.5 open; the counter sits behind the turn.
	for z in [-1.0, 3.0]:
		_table(Vector3(-5, 2, z), 2, 2)
		_chair(Vector3(-5, 2, z + 1.75))
		_chair(Vector3(-5, 2, z - 1.75), 2)
	_box(Vector3(-1, 2, -6), Vector3(0.5, 3, -3.5), WOOD)
	_box(Vector3(-1.5, 3, -6.5), Vector3(0.75, 3.5, -3.25), TIMBER)
	for z in [-5.5, -4.25]:
		_prop("barrel", Vector3(1.75, 2, z))
	_prop("barrel", Vector3(5.5, 2, -1.25))
	_prop("barrel", Vector3(5.5, 3, -1.25))
	_table(Vector3(4.25, 2, -5), 2.5, 2)
	_chair(Vector3(4.25, 2, -3.25))
	_chair(Vector3(4.25, 2, -6.5), 2)
	# Open hearth, stone hood and raised embers, away from the passage.
	_box(Vector3(-6, 2, -6.5), Vector3(-4, 2.5, -4.5), DARK)
	_box(Vector3(-6, 2.5, -6.5), Vector3(-5.5, 5, -4.5), STONE)
	_box(Vector3(-4.5, 2.5, -6.5), Vector3(-4, 5, -4.5), STONE)
	_box(Vector3(-6, 4.5, -6.5), Vector3(-4, 5.5, -4.5), STONE)
	_detail_box(Vector3(-5, 2.625, -5.75), Vector3(1.25, 0.25, 0.75), FIRE)
	# A large two-sided mug sign plus an existing small projecting sign prop.
	_detail_box(Vector3(0, 5.0, 7.75), Vector3(2, 1.75, 0.25), TIMBER)
	_detail_box(Vector3(0, 5.0, 7.9), Vector3(1.75, 1.5, 0.125), AMBER)
	for z in [7.625, 7.9]:
		_detail_box(Vector3(-0.125, 4.95, z), Vector3(0.875, 1.0, 0.125), CREAM)
		_detail_box(Vector3(-0.125, 5.5, z), Vector3(1.125, 0.25, 0.125), CREAM)
		_detail_box(Vector3(0.625, 4.95, z), Vector3(0.25, 0.75, 0.125), GOLD)
		_detail_box(Vector3(0.375, 5.2, z), Vector3(0.5, 0.25, 0.125), GOLD)
		_detail_box(Vector3(0.375, 4.7, z), Vector3(0.5, 0.25, 0.125), GOLD)
	if _details != null:
		_details.sign(_world(Vector3(-6.75, 4, 7.125)), "mug", float(_q) * PI * 0.5 + PI * 0.5)
	for x in [-4.0, -1.0]:
		_prop("lantern", Vector3(x, 3.75, 6.75), PI)
	_room("tavern_taproom", "酒場・カウンターと客席", Vector3(-2.5, 2.15, 1), Vector3(-6, 2, -6.5), Vector3(0.5, 6.5, 6))
	_room("tavern_snug", "酒場・奥の客席", Vector3(3.5, 2.15, -1.75), Vector3(1, 2, -6.5), Vector3(6, 6.5, -0.5))
	_route("tavern_counter", [Vector3(-2.5, 2.15, 8), Vector3(-2.5, 2.15, 6.5), Vector3(-2.5, 2.15, 1), Vector3(-2.5, 2.15, -4.5)])
	_route("tavern_snug", [Vector3(-2.5, 2.15, 2), Vector3(-2.5, 2.15, -1.75), Vector3(3.5, 2.15, -1.75)])

func _church() -> void:
	# A high nave, lower projecting transepts, recessed chancel and front belfry.
	_shell(Vector3(-7, 2, -15), Vector3(7, 17, 15), LIGHT, 1)
	_shell(Vector3(-13.5, 2, -5.5), Vector3(-6, 12, 5.5), LIGHT, 1)
	_shell(Vector3(6, 2, -5.5), Vector3(13.5, 12, 5.5), LIGHT, 1)
	_shell(Vector3(-5.5, 2, -19), Vector3(5.5, 14, -12), CREAM, 1)
	_shell(Vector3(-4, 2, 10), Vector3(4, 28, 18.5), STONE, 1)
	_gable(-8, 8, -15.5, 15.5, 17, 6, BLUE)
	_gable(-14, -6, -6, 6, 12, 5, BLUE, true)
	_gable(6, 14, -6, 6, 12, 5, BLUE, true)
	_gable(-6, 6, -19.5, -12, 14, 5, BLUE)
	# A steep four-sided belfry cap, built as narrowing hollow voxel courses.
	for i in range(16):
		var radius := 4.5 * (1.0 - float(i) / 16.0)
		var y := 28 + float(i) * 0.5
		var lo := snappedf(-radius, 0.5)
		var hi := snappedf(radius, 0.5)
		_shell(Vector3(lo, y, 14.25 + lo), Vector3(hi, y + 0.5, 14.25 + hi), BLUE)
	_box(Vector3(-0.5, 35.5, 13.75), Vector3(0.5, 36.5, 14.75), GOLD)
	# Stepped buttresses expose the depth of the wall rather than painted edges.
	for side in [-1.0, 1.0]:
		for z in [-12.5, -7.5, 7.5, 12.0]:
			var x: float = side * 7.5
			_box(Vector3(x - 0.75, 2, z - 0.75), Vector3(x + 0.75, 8, z + 0.75), DARK)
			_box(Vector3(x - 0.5, 8, z - 0.5), Vector3(x + 0.5, 12, z + 0.5), STONE)
			_box(Vector3(x - 0.25, 12, z - 0.5), Vector3(x + 0.25, 15, z + 0.5), LIGHT)
		for z in [-10, 9.5]:
			_window(Vector3(side * 6.5, 5, z), 2.5, 8.5, 1, true)
		_window(Vector3(side * 13, 4, 0), 3.5, 7, 1, true)
		for z in [-16.5, -13.5]:
			_window(Vector3(side * 5, 5, z), 2, 6, 1, true)
	_window(Vector3(0, 6, -18.5), 4, 6.5, 0, true)
	# Front tower ring courses and deep belfry openings on all four faces.
	for y in [2.0, 8.0, 18.0, 24.0, 27.5]:
		_shell(Vector3(-4.5, y, 9.5), Vector3(4.5, y + 0.5, 19), DARK if y == 2 else LIGHT)
	# The ring courses are shells above the entrance, preserving the tower void.
	_clear(Vector3(-3, 2, 11), Vector3(3, 28, 17.5))
	for face in range(4):
		var at := Vector3(0, 23.5, 14.25) + _turn(Vector3(0, 0, 4), face)
		_door("church_belfry_%d" % face, at, 2.5, 3.5, face, 2, false)
		_panel_box(at, Vector3(-1.5, -0.5, -1), Vector3(1.5, 0, 1), face, LIGHT)
	_window(Vector3(0, 11, 18), 2, 7)
	for side in [-1.0, 1.0]:
		_window(Vector3(side * 3.5, 11, 14.25), 2, 7, 1)
	# The visible bell is solid and cheap; no runtime light or dynamic body.
	_detail_box(Vector3(0, 27, 14.25), Vector3(5, 0.375, 0.5), TIMBER)
	_detail_box(Vector3(0, 26.25, 14.25), Vector3(0.5, 1.5, 0.5), IRON)
	_detail_box(Vector3(0, 25.5, 14.25), Vector3(1, 0.75, 1), BRASS)
	_detail_box(Vector3(0, 25, 14.25), Vector3(1.75, 0.375, 1.75), GOLD)
	# Free ground-level connections are cut through both overlapping shells.
	_clear(Vector3(-7.5, 2, -4), Vector3(7.5, 8, 4))
	_clear(Vector3(-4, 2, -15.5), Vector3(4, 9, -11.5))
	_clear(Vector3(-3, 2, 9.5), Vector3(3, 7, 15.5))
	_door("church_main", Vector3(0, 2, 18), 3, 6, 0, 3)
	# Deep layered archivolts and a pointed ornamental canopy above the portal.
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 2.5 - 0.5, 2, 18.5), Vector3(side * 2.5 + 0.5, 7.5, 19.5), LIGHT)
	for i in range(5):
		var inset := float(i) * 0.5
		for side in [-1.0, 1.0]:
			var x: float = side * (2.5 - inset)
			_box(Vector3(x - 0.25, 7.5 + inset, 18.5), Vector3(x + 0.25, 8 + inset, 19.5), CREAM)
	# Internal columns and high transverse ribs frame the clear central aisle.
	for z in [-10.5, -5.5, 5.5, 10.5]:
		for x in [-4.5, 4.5]:
			_box(Vector3(x - 0.5, 2, z - 0.5), Vector3(x + 0.5, 2.5, z + 0.5), DARK)
			_box(Vector3(x - 0.25, 2.5, z - 0.25), Vector3(x + 0.25, 14.5, z + 0.25), LIGHT)
			_box(Vector3(x - 0.5, 14.5, z - 0.5), Vector3(x + 0.5, 15, z + 0.5), GOLD)
		for i in range(18):
			var x := -4.5 + float(i) * 0.5
			var rise := 4.5 - absf(x)
			_box(Vector3(x, 15 + rise * 0.5, z - 0.25), Vector3(x + 0.5, 15.5 + rise * 0.5, z + 0.25), TIMBER)
	_beams(-6, 6, -13, 13, 16, 5)
	for z in [-8.0, -4.5, 2.5, 6.0, 9.5]:
		for x in [-4.0, 4.0]:
			_bench(Vector3(x, 2, z), 3, 0)
	# The altar has its own apse-like chancel, patterned block window and candles.
	_box(Vector3(-2.5, 2, -17), Vector3(2.5, 3, -15), LIGHT)
	_box(Vector3(-3, 3, -17.5), Vector3(3, 3.5, -14.5), CREAM)
	for x in [-2.0, 2.0]:
		_detail_box(Vector3(x, 3.875, -16), Vector3(0.125, 0.75, 0.125), GOLD)
		_detail_box(Vector3(x, 4.375, -16), Vector3(0.125, 0.25, 0.125), FIRE)
	for x in [-11, 11]:
		_table(Vector3(x, 2, -3.5), 2, 2)
	for x in [-2.0, 2.0]:
		_prop("lantern", Vector3(x, 4.5, 18.75), PI)
	_room("church_nave", "教会・身廊", Vector3(0, 2.15, 4), Vector3(-6, 2, -14), Vector3(6, 16, 14))
	_room("church_chancel", "教会・祭壇前", Vector3(0, 2.15, -13), Vector3(-4.5, 2, -18), Vector3(4.5, 13.5, -12))
	_room("church_west_transept", "教会・西袖廊", Vector3(-10, 2.15, 0), Vector3(-12.5, 2, -4.5), Vector3(-6, 11.5, 4.5))
	_room("church_east_transept", "教会・東袖廊", Vector3(10, 2.15, 0), Vector3(6, 2, -4.5), Vector3(12.5, 11.5, 4.5))
	_route("church_altar", [Vector3(0, 2.15, 19.5), Vector3(0, 2.15, 18), Vector3(0, 2.15, 12), Vector3(0, 2.15, 0), Vector3(0, 2.15, -13)])
	_route("church_west", [Vector3(0, 2.15, 0), Vector3(-10, 2.15, 0)])
	_route("church_east", [Vector3(0, 2.15, 0), Vector3(10, 2.15, 0)])
