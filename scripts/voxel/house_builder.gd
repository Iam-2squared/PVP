extends RefCounted
## Offline house component; no streets, terrain plates or scene integration.
## centreXZ is Vector2(X,Z), orientation is radians, base_y defaults to 2m.
## shared_left/right suppress side projections and windows for attached houses.
## Geometry uses the 0.5m volume; near-only decoration uses DetailBuilder.
## Enterable homes require at least 6m width. The city terrain supplies their
## ground floor; include_ground_floor is only for isolated component previews.

var _v: Variant
var _details: Variant
var _origin := Vector3.ZERO
var _orientation := 0.0
var _basis := Basis.IDENTITY
var _width := 5.0
var _depth := 7.0
var _storeys := 2
var _shared_left := false
var _shared_right := false
var _seed := 0
var _kind := "house"
var _enterable := false
var _detail_level := 1

func build(volume: Variant, details: Variant, spec: Dictionary) -> Dictionary:
	_v = volume
	_details = details
	var centre: Variant = spec.get("centreXZ", spec.get("centre", Vector2.ZERO))
	_origin = Vector3(centre.x, float(spec.get("base_y", 2.0)), centre.y) if centre is Vector2 else Vector3(centre.x, float(spec.get("base_y", 2.0)), centre.z)
	_orientation = float(spec.get("orientation", 0.0))
	_basis = Basis(Vector3.UP, _orientation)
	_width = snappedf(maxf(float(spec.get("width", 5.0)), 4.0), 0.5)
	_depth = snappedf(maxf(float(spec.get("depth", 7.0)), 5.0), 0.5)
	_storeys = clampi(int(spec.get("storeys", 2)), 1, 3)
	_shared_left = bool(spec.get("shared_left", false))
	_shared_right = bool(spec.get("shared_right", false))
	_seed = int(spec.get("seed", 0))
	_kind = str(spec.get("kind", "house"))
	_enterable = bool(spec.get("enterable", spec.get("interior", false)))
	_detail_level = clampi(int(spec.get("detail_level", 1)), 0, 2)
	if _enterable:
		_width = maxf(_width, 6.0)
	var plaster := int(spec.get("plaster_id", 20))
	var roof_id := int(spec.get("roof_id", 24))
	var height := float(_storeys) * 3.0
	var overhang := 0.5 if _storeys > 1 else 0.0
	# Avoid a coplanar floor on top of the city's common paving.
	if bool(spec.get("include_ground_floor", false)):
		_box(Vector3(0, -0.25, 0), Vector3(_width, 0.5, _depth), 9)
	for floor_index in range(_storeys):
		var upper := floor_index > 0
		var depth := _depth + (overhang if upper else 0.0)
		var z := -overhang * 0.5 if upper else 0.0
		var y := float(floor_index) * 3.0
		var wall_id := plaster if upper else int(spec.get("ground_id", 5))
		_shell(Vector3(0, y + 1.5, z), _width, depth, 3.0, wall_id)
		if not upper:
			_shell(Vector3(0, 0.5, 0), _width, _depth, 1.0, 4)
		else:
			_box(Vector3(0, y - 0.25, z), Vector3(_width, 0.5, depth), 9)
		_timber(y, z - depth * 0.5, upper)
		for x in [-_width * 0.25, _width * 0.25]:
			if upper or absf(x) >= 1.25:
					_window(Vector3(snappedf(x, 0.5), y + 1.75, z - depth * 0.5), 0.0, upper)
		if upper and _detail_level > 0:
			_window(Vector3(0, y + 1.75, _depth * 0.5), PI, false)
			if not _shared_left:
				_window(Vector3(-_width * 0.5, y + 1.75, snappedf(_depth * 0.15, 0.5)), PI * 0.5, false)
			if not _shared_right:
				_window(Vector3(_width * 0.5, y + 1.75, snappedf(-_depth * 0.15, 0.5)), -PI * 0.5, false)
	_box(Vector3(0, height - 0.25, -overhang * 0.5), Vector3(_width, 0.5, _depth + overhang), 9)
	_entrance()
	_roof(height, roof_id, overhang)
	if _kind != "house":
		_shopfront()
	if _detail_level > 0 and bool(spec.get("bay_window", posmod(_seed, 5) == 0)) and _storeys > 1:
		_bay_window(3.0, -_depth * 0.5 - overhang)
	if _enterable:
		_interior()
	var half := Vector3(_width * 0.5 + 0.5, height + 4.5, _depth * 0.5 + 1.0)
	var bounds := _world_bounds(Vector3(0, (height + 4.5) * 0.5, -0.25), Vector3(half.x * 2.0, half.y, half.z * 2.0))
	return {
		"id": str(spec.get("id", "house_%d" % _seed)), "kind": _kind,
		"bounds": bounds, "centre": _origin, "width": _width, "depth": _depth,
		"storeys": _storeys, "orientation": _orientation, "roof_id": roof_id,
		"detail_level": _detail_level,
		"entrance": _world(Vector3(0, 0.15, -_depth * 0.5 - 1.0)),
		"entry": _world(Vector3(0, 0.15, -_depth * 0.5 - 1.0)),
		"interior_point": _world(Vector3(0, 0.15, -_depth * 0.25)),
		"route_waypoints": [_world(Vector3(0, 0.15, -_depth * 0.5 - 1.0)), _world(Vector3(0, 0.15, -_depth * 0.5 + 0.75)), _world(Vector3(0, 0.15, 0))] if _enterable else [],
		"enterable": _enterable, "shared_left": _shared_left, "shared_right": _shared_right,
	}

func _shell(c: Vector3, width: float, depth: float, height: float, id: int) -> void:
	for side in [-1.0, 1.0]:
		_box(c + Vector3(side * (width * 0.5 - 0.25), 0, 0), Vector3(0.5, height, depth), id)
		_box(c + Vector3(0, 0, side * (depth * 0.5 - 0.25)), Vector3(width, height, 0.5), id)

func _timber(y: float, front: float, upper: bool) -> void:
	var wood := 10
	for band_y in [y + 0.125, y + 2.875]:
		_detail(Vector3(0, band_y, front - 0.0625), Vector3(_width, 0.25, 0.125), wood)
	for x in [-_width * 0.5 + 0.125, 0.0, _width * 0.5 - 0.125]:
		if not upper and is_zero_approx(x):
			continue
		_detail(Vector3(x, y + 1.5, front - 0.0625), Vector3(0.25, 3.0, 0.125), wood)
	if upper and _detail_level > 0:
		for x in [-_width * 0.5 + 0.25, _width * 0.5 - 0.25]:
			# Braces live in the upper wall panels, clear of the window openings.
			var dx := 0.625 if x < 0 else -0.625
			_details.add_voxel_line(_world(Vector3(x, y + 0.375, front - 0.125)), _world(Vector3(x + dx, y + 1.0, front - 0.125)), 0.125, wood, 0.0)
		for x in [-_width * 0.35, _width * 0.35]:
			_box(Vector3(x, y - 0.25, front + 0.125), Vector3(0.5, 0.5, 0.5), 10)
	for side in [-1.0, 1.0]:
		if (side < 0 and _shared_left) or (side > 0 and _shared_right):
			continue
		_detail(Vector3(side * (_width * 0.5 + 0.0625), y + 0.125, 0), Vector3(0.125, 0.25, _depth), wood)
		_detail(Vector3(side * (_width * 0.5 + 0.0625), y + 1.5, 0), Vector3(0.125, 3.0, 0.25), wood)

func _window(p: Vector3, rotation_y: float, shutters: bool) -> void:
	var face := Basis(Vector3.UP, rotation_y)
	_box(p + face * Vector3(0, 0, 0.125), Vector3(1.0, 1.5, 0.75), 0, rotation_y)
	_detail(p + face * Vector3(0, 0, 0.3125), Vector3(1.0, 1.5, 0.125), 22, rotation_y)
	_detail(p + face * Vector3(0, 0.0625, 0.25), Vector3(0.75, 1.125, 0.125), 27, rotation_y)
	for side in [-1.0, 1.0]:
		_detail(p + face * Vector3(side * 0.5625, 0, -0.0625), Vector3(0.125, 1.75, 0.25), 10, rotation_y)
		if shutters:
			_detail(p + face * Vector3(side * 0.8125, 0, -0.125), Vector3(0.375, 1.5, 0.125), 26 if posmod(_seed, 3) == 0 else 9, rotation_y)
	_detail(p + face * Vector3(0, -0.8125, -0.125), Vector3(1.25, 0.125, 0.5), 5, rotation_y)
	_detail(p + face * Vector3(0, 0, 0.125), Vector3(0.125, 1.5, 0.125), 10, rotation_y)
	_detail(p + face * Vector3(0, -0.0625, 0.125), Vector3(1.0, 0.125, 0.125), 10, rotation_y)

func _entrance() -> void:
	var front := -_depth * 0.5
	_box(Vector3(0, 1.25, front + 0.25), Vector3(2.0, 2.5, 1.5), 0)
	if not _enterable:
		_box(Vector3(0, 1.25, front + 0.75), Vector3(2.0, 2.5, 0.5), 10)
		for x in [-0.5, 0.0, 0.5]:
			_detail(Vector3(x, 1.0, front + 0.4375), Vector3(0.125, 2.0, 0.125), 9)
		_detail(Vector3(0.4375, 1.0, front + 0.3125), Vector3(0.125, 0.125, 0.125), 23)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 1.25, 1.25, front - 0.25), Vector3(0.5, 2.5, 0.5), 5)
	_box(Vector3(0, 2.75, front - 0.25), Vector3(3.0, 0.5, 0.5), 10)
	_detail(Vector3(0, 2.6875, front - 0.375), Vector3(2.75, 0.125, 0.75), 9)
	_details.lantern(_world(Vector3(-1.375, 1.25, front - 0.375)), _orientation)

func _bay_window(y: float, front: float) -> void:
	var x := _width * 0.25 * (-1.0 if posmod(_seed, 2) == 0 else 1.0)
	_box(Vector3(x, y + 0.875, front - 0.25), Vector3(1.5, 0.5, 1.0), 10)
	_detail(Vector3(x, y + 1.625, front - 0.6875), Vector3(1.5, 1.0, 0.125), 27)
	for sx in [-0.6875, 0.0, 0.6875]:
		_detail(Vector3(x + sx, y + 1.625, front - 0.75), Vector3(0.125, 1.25, 0.125), 10)
	_box(Vector3(x, y + 2.375, front - 0.25), Vector3(2.0, 0.5, 1.0), 9)

func _shopfront() -> void:
	var front := -_depth * 0.5
	var x := -_width * 0.3
	_detail(Vector3(x, 0.9375, front - 0.375), Vector3(1.5, 0.125, 0.75), 9)
	for side in [-1.0, 1.0]:
		_detail(Vector3(x + side * 0.5625, 0.5, front - 0.375), Vector3(0.125, 0.875, 0.125), 10)
	for i in range(3):
		var color := 25 if _kind == "tavern" else (22 if _kind == "weapon_shop" or _kind == "blacksmith" else 11)
		_detail(Vector3(x - 0.5 + float(i) * 0.5, 1.125, front - 0.375), Vector3(0.25, 0.25, 0.25), color)
	var symbol := "mug" if _kind == "tavern" else ("anvil" if _kind == "blacksmith" or _kind == "workshop" else "sword")
	_details.sign(_world(Vector3(_width * 0.3, 2.0, front - 0.5)), symbol, _orientation)
	# A stepped fabric awning, with a short valance and two wall-side braces.
	for row in range(3):
		_detail(Vector3(x, 2.375 - float(row) * 0.125, front - 0.25 - float(row) * 0.25), Vector3(1.75, 0.125, 0.375), 21 if posmod(_seed, 2) == 0 else 26)
	_details.barrel(_world(Vector3(_width * 0.5 - 0.5, 0, front - 0.5)), _orientation)

func _interior() -> void:
	# A clear 2m central route remains from doorway into every featured room.
	var side_x := _width * 0.5 - 1.0
	if _kind == "tavern":
		_box(Vector3(side_x, 0.75, 0.5), Vector3(1.0, 1.5, _depth - 2.0), 9)
		for z in [-0.5, 1.5]:
			_detail(Vector3(-side_x, 0.75, z), Vector3(1.0, 0.125, 1.0), 9)
			_detail(Vector3(-side_x, 0.375, z), Vector3(0.25, 0.75, 0.25), 10)
			_details.bench(_world(Vector3(-side_x, 0, z + 0.75)), _orientation)
	elif _kind == "blacksmith" or _kind == "weapon_shop" or _kind == "workshop":
		_box(Vector3(side_x, 0.5, _depth * 0.25), Vector3(1.5, 1.0, 1.5), 6)
		_detail(Vector3(side_x, 1.125, _depth * 0.25), Vector3(1.25, 0.25, 0.625), 22)
		for z in [-0.5, 0.5, 1.5]:
			_detail(Vector3(-side_x, 1.25, z), Vector3(0.125, 1.5, 0.25), 14)
			_detail(Vector3(-side_x, 0.5, z), Vector3(0.5, 0.125, 0.25), 23)
		_details.logpile(_world(Vector3(side_x, 0, -_depth * 0.15)), _orientation)
	else:
		_box(Vector3(side_x - 0.25, 0.25, _depth * 0.2), Vector3(1.5, 0.5, 2.5), 9)
		_detail(Vector3(side_x - 0.25, 0.625, _depth * 0.2), Vector3(1.25, 0.25, 2.25), 31)
		_detail(Vector3(side_x - 0.25, 0.8125, _depth * 0.2 + 0.875), Vector3(1.0, 0.125, 0.5), 20)
		_details.bench(_world(Vector3(-side_x, 0, 1.0)), _orientation + PI * 0.5)
	_details.crate(_world(Vector3(-side_x, 0, _depth * 0.5 - 1.0)), _orientation)
	_details.lantern(_world(Vector3(side_x, 1.5, _depth * 0.5 - 0.625)), _orientation + PI)

func _roof(height: float, roof_id: int, overhang: float) -> void:
	var half_width := _width * 0.5
	var layers := ceili(half_width / 0.5)
	for layer in range(layers):
		var outer := half_width - float(layer) * 0.5
		for side in [-1.0, 1.0]:
			var x: float = side * (outer - 0.25)
			_box(Vector3(x, height + float(layer) * 0.5 + 0.25, -overhang * 0.5), Vector3(0.5, 0.5, _depth + overhang + 1.0), roof_id)
		# A solid triangular gable closes each end behind the thick roof courses.
		for z in [-_depth * 0.5 - overhang + 0.25, _depth * 0.5 - 0.25]:
			_box(Vector3(0, height + float(layer) * 0.5 + 0.25, z), Vector3(maxf(0.5, outer * 2.0 - 1.0), 0.5, 0.5), 20)
	_box(Vector3(0, height + float(layers) * 0.5, -overhang * 0.5), Vector3(0.5, 0.5, _depth + overhang + 1.5), 10)
	# Block chimney with a wider cap, offset from the ridge.
	var chimney_x := -_width * 0.25 if posmod(_seed, 2) == 0 else _width * 0.25
	var chimney_y := height + _width * 0.25 + 0.5
	_box(Vector3(chimney_x, chimney_y, _depth * 0.25), Vector3(1.0, 2.0, 1.0), 6)
	_box(Vector3(chimney_x, chimney_y + 1.0, _depth * 0.25), Vector3(1.5, 0.5, 1.5), 4)
	# One projecting roof window, three-dimensional cheeks and a stepped hood.
	if _detail_level > 0 and not (_shared_left and _shared_right):
		var z := snappedf(-_depth * 0.25, 0.5)
		var side := -1.0 if _shared_right else 1.0
		var x := side * (half_width - 0.75)
		_box(Vector3(x, height + 0.75, z), Vector3(1.5, 1.5, 1.5), 20)
		_window(Vector3(x + side * 0.75, height + 0.75, z), -PI * 0.5 * side, false)
		for row in range(2):
			_box(Vector3(x, height + 1.5 + float(row) * 0.5, z), Vector3(1.5 - float(row) * 0.5, 0.5, 2.0 - float(row) * 0.5), roof_id)

func _world(local: Vector3) -> Vector3:
	return _origin + _basis * local

func _detail(c: Vector3, size: Vector3, id: int, local_rotation: float = 0.0) -> void:
	_details.add_box(_world(c), size, id, _orientation + local_rotation)

func _world_bounds(c: Vector3, size: Vector3, local_rotation: float = 0.0) -> AABB:
	var b := _basis * Basis(Vector3.UP, local_rotation)
	var half := size * 0.5
	var extents := Vector3(absf(b.x.x) * half.x + absf(b.z.x) * half.z, half.y, absf(b.x.z) * half.x + absf(b.z.z) * half.z)
	return AABB(_world(c) - extents, extents * 2.0)

func _box(c: Vector3, size: Vector3, id: int, local_rotation: float = 0.0) -> void:
	var bounds := _world_bounds(c, size, local_rotation)
	var lo := Vector3i(floori(bounds.position.x * 2.0 + 0.0001), floori(bounds.position.y * 2.0 + 0.0001), floori(bounds.position.z * 2.0 + 0.0001))
	var hi := Vector3i(ceili(bounds.end.x * 2.0 - 0.0001), ceili(bounds.end.y * 2.0 - 0.0001), ceili(bounds.end.z * 2.0 - 0.0001))
	if absf(sin((_orientation + local_rotation) * 2.0)) < 0.0001:
		_v.box(lo, hi, id)
		return
	var inverse := (_basis * Basis(Vector3.UP, local_rotation)).inverse()
	var world_c := _world(c)
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var p := inverse * (Vector3(x, y, z) * 0.5 + Vector3.ONE * 0.25 - world_c)
				if absf(p.x) <= size.x * 0.5 + 0.001 and absf(p.y) <= size.y * 0.5 + 0.001 and absf(p.z) <= size.z * 0.5 + 0.001:
					_v.set_voxel(Vector3i(x, y, z), id)
