extends RefCounted
## Static trade and household stories on real building frontages. All geometry
## is solid voxel-shaped detail merged by DetailBuilder. The few townsfolk are
## static block silhouettes in these meshes; no actor nodes, simulation or lights.
## Local -Z is the house front. Every ground prop reserves its entire footprint
## against the road's 2.25m walking spine and every home's 2.5m entrance route.

const MAX_BOXES := 1200
const GRID := 0.125
const WALK_HALF := 1.125
const ENTRY_HALF := 1.25

var _details: Variant
var _volume: Variant
var _houses: Array[Dictionary] = []
var _roads: Array[PackedVector2Array] = []
var _entries: Array[PackedVector2Array] = []
var _footprints: Array[PackedVector2Array] = []
var _occupied: Array[PackedVector2Array] = []
var _activity_sites: Array[Dictionary] = []
var _boxes := 0
var _solid_boxes := 0
var _stats: Dictionary = {}

func dress(details: Variant, houses: Array, streets: Array, volume: Variant = null) -> Dictionary:
	_details = details
	_volume = volume
	_houses.clear()
	_roads.clear()
	_entries.clear()
	_footprints.clear()
	_occupied.clear()
	_activity_sites.clear()
	_boxes = 0
	_solid_boxes = 0
	_stats = {"handcarts": 0, "produce_displays": 0, "goods_stacks": 0,
		"frontage_canopies": 0, "trade_signs": 0, "work_racks": 0,
		"featured_corners": [], "walking_spine_width_m": WALK_HALF * 2.0,
		"entry_keepout_width_m": ENTRY_HALF * 2.0, "static_figures": 0}
	for value: Variant in houses:
		if value is Dictionary and value.has("centre"):
			var house: Dictionary = value
			_houses.append(house)
			var origin: Vector3 = house["centre"]
			var angle := float(house.get("orientation", 0.0))
			var depth := float(house.get("depth", 6.0))
			_footprints.append(_rectangle(origin, Vector2(float(house.get("width", 5.0)), depth), angle))
			_entries.append(_rectangle(_world(house, Vector3(0, 0, -depth * 0.5 - 0.875)), Vector2(ENTRY_HALF * 2.0, 3.75), angle))
	for street: Dictionary in streets:
		var points: Variant = street.get("planar", PackedVector2Array())
		if points.size() == 0:
			var world_points: Variant = street.get("points", PackedVector3Array())
			var planar := PackedVector2Array()
			for p: Vector3 in world_points:
				planar.append(Vector2(p.x, p.z))
			points = planar
		for i in range(points.size() - 1):
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			if a.distance_squared_to(b) < 0.001:
				continue
			var tangent := (b - a).normalized()
			var normal := Vector2(-tangent.y, tangent.x) * WALK_HALF
			_roads.append(PackedVector2Array([a - tangent * WALK_HALF + normal,
				b + tangent * WALK_HALF + normal, b + tangent * WALK_HALF - normal,
				a - tangent * WALK_HALF - normal]))
	# A few recognisable working corners carry most of the street activity.
	# The closest actual facade is selected; nothing is scattered onto vacant land.
	var corners := [
		{"id": "market_loading", "point": Vector2(-66, 26), "districts": ["market", "old_quarter", "main_avenue"]},
		{"id": "merchant_corner", "point": Vector2(-65, 66), "districts": ["old_quarter", "market"]},
		{"id": "workers_corner", "point": Vector2(99, 86), "districts": ["poor_quarter", "northeast"]},
		{"id": "gate_loading", "point": Vector2(12, 136), "districts": ["main_avenue", "poor_quarter", "old_quarter"]},
	]
	var featured: Dictionary = {}
	for corner: Dictionary in corners:
		var cluster := _closest_frontages(corner["point"], corner["districts"], 7)
		if cluster.is_empty():
			continue
		var centre: Vector3 = cluster[0]["centre"]
		_stats["featured_corners"].append({"id": corner["id"], "position": centre})
		for i in range(cluster.size()):
			var house: Dictionary = cluster[i]
			var key := str(house.get("id", house["centre"]))
			if featured.has(key):
				continue
			featured[key] = true
			var seed_value := int(house.get("seed", i))
			var side := -1.0 if posmod(seed_value, 2) == 0 else 1.0
			var district := str(house.get("district", "old_quarter"))
			var canopy_count := int(_stats["frontage_canopies"])
			if i < 3:
				_try_canopy(house, side, _cloth(district, seed_value))
			if i < 5:
				_trade_sign(house, side, posmod(seed_value, 4), _cloth(district, seed_value))
			if i < 2 and _stats["static_figures"] < 8 and int(_stats["frontage_canopies"]) > canopy_count:
				_try_static_figure(house, side)
			if i < 3 and _stats["handcarts"] < 9:
				_try_cart(house, -side, posmod(seed_value, 3))
			if i < 5:
				_try_display(house, side, district, seed_value)
			if i >= 4:
				_try_work_rack(house, side, seed_value)
	# A handful of outlying trades tie the denser feature corners into the city.
	# Domestic frontages deliberately do not receive the same kit of objects.
	for house: Dictionary in _houses:
		var key := str(house.get("id", house["centre"]))
		if featured.has(key):
			continue
		var seed_value := int(house.get("seed", 0))
		var district := str(house.get("district", ""))
		var kind := str(house.get("kind", "house"))
		var side := -1.0 if posmod(seed_value, 2) == 0 else 1.0
		if kind in ["blacksmith", "workshop", "warehouse", "weapon_shop", "shop", "inn"]:
			if _stats["trade_signs"] < 24:
				_trade_sign(house, side, 2 if kind in ["blacksmith", "workshop", "weapon_shop"] else 0, _cloth(district, seed_value))
			if _stats["handcarts"] < 9:
				_try_cart(house, -side, 2 if kind in ["blacksmith", "workshop"] else 1)
		elif district in ["poor_quarter", "old_quarter", "northwest"] and posmod(seed_value, 37) == 0:
			_try_work_rack(house, side, seed_value)
	# Life-size silhouettes stay beside the already selected trades. They share
	# the same near-only CPU mesh, carry no collision or runtime behaviour, and
	# reserve their visible arm/parcel extent as well as their feet.
	for site: Dictionary in _activity_sites:
		if _stats["static_figures"] >= 8:
			break
		_try_static_figure(site["house"], float(site["side"]))
	_stats["boxes"] = _boxes
	_stats["triangles"] = _boxes * 12
	_stats["aerial_structure_boxes"] = _solid_boxes
	_stats["ground_prop_footprints"] = _occupied.size()
	_stats["structural_collisions"] = _volume != null
	_stats["micro_detail_collisions"] = false
	_stats["cast_shadow"] = false
	return _stats.duplicate(true)

func _closest_frontages(point: Vector2, districts: Array, count: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for house: Dictionary in _houses:
		if str(house.get("district", "")) in districts:
			candidates.append(house)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector3 = a["centre"]
		var cb: Vector3 = b["centre"]
		return Vector2(ca.x, ca.z).distance_squared_to(point) < Vector2(cb.x, cb.z).distance_squared_to(point))
	if candidates.size() > count:
		candidates.resize(count)
	return candidates

func _cloth(district: String, seed_value: int) -> int:
	# Repeated pairs read as neighbourhood identity from the air.
	if district in ["poor_quarter", "old_quarter"]:
		return 19 if posmod(seed_value, 3) == 0 else 11
	if district == "market":
		return 21 if posmod(seed_value, 3) == 0 else 11
	if district in ["northwest", "northeast"]:
		return 26 if posmod(seed_value, 3) == 0 else 19
	return 26 if posmod(seed_value, 2) == 0 else 31

func _try_canopy(house: Dictionary, side: float, cloth: int) -> void:
	if _boxes + 18 > MAX_BOXES or _stats["frontage_canopies"] >= 14:
		return
	var width := float(house.get("width", 5.0))
	var x := side * (width * 0.5 - 0.875)
	var front := -float(house.get("depth", 6.0)) * 0.5
	var origin := _world(house, Vector3(x, 0, front - 0.6875))
	var rotation := float(house.get("orientation", 0.0))
	# The two posts reserve the edges; a continuous walking gap remains below.
	var posts: Array[PackedVector2Array] = []
	# A narrow shop has one outside post and a wall-fixed inner bracket. This
	# leaves the doorway below the fabric open even on the 4m terraces.
	var post_x: Array = [-0.6875, 0.6875] if width >= 6.0 else [side * 0.6875]
	for sx: float in post_x:
		var post := origin + Basis(Vector3.UP, rotation) * Vector3(sx, 0, -0.5)
		var polygon := _solid_footprint(post, Vector2(0.125, 0.125), rotation) if _volume != null else _rectangle(post, Vector2(0.25, 0.25), rotation)
		if not _clear(polygon):
			return
		posts.append(polygon)
	for polygon: PackedVector2Array in posts:
		_occupied.append(polygon)
	if _volume != null:
		for sx: float in post_x:
			_solid_box(origin, Vector3(sx, 1.25, -0.5), Vector3(0.125, 2.5, 0.125), 10, rotation)
		# Broad opaque roof courses survive the aerial view. The lowest course
		# begins 2.5m above ground, keeping a full-height passage underneath.
		_solid_box(origin, Vector3(0, 2.75, -0.25), Vector3(1.875, 0.5, 1.0), cloth, rotation)
		_solid_box(origin, Vector3(0, 3.0, 0.375), Vector3(1.875, 0.5, 0.5), cloth, rotation)
		_solid_box(origin, Vector3(0, 2.625, -0.5), Vector3(1.875, 0.125, 0.125), 10, rotation)
		_stats["frontage_canopies"] += 1
		_activity_sites.append({"house": house, "side": side})
		return
	for sx: float in post_x:
		_box(origin, Vector3(sx, 1.25, -0.5), Vector3(0.125, 2.5, 0.125), 10, rotation)
		_box(origin, Vector3(sx, 2.625, 0), Vector3(0.125, 0.125, 1.25), 9, rotation)
	_box(origin, Vector3(0, 2.625, -0.5), Vector3(1.625, 0.125, 0.125), 10, rotation)
	_box(origin, Vector3(0, 2.875, 0.5625), Vector3(1.75, 0.125, 0.125), 10, rotation)
	for row in range(4):
		var z := 0.375 - float(row) * 0.25
		var y := 2.875 - float(row) * 0.0625
		_box(origin, Vector3(0, y, z), Vector3(1.875, 0.125, 0.375), cloth, rotation)
	_box(origin, Vector3(0, 2.5, -0.625), Vector3(1.875, 0.25, 0.125), cloth, rotation)
	for sx in [-0.625, 0.0, 0.625]:
		_box(origin, Vector3(sx, 2.8125, 0), Vector3(0.125, 0.125, 1.25), 20 if cloth != 11 else 19, rotation)
	_stats["frontage_canopies"] += 1
	_activity_sites.append({"house": house, "side": side})

func _try_cart(house: Dictionary, side: float, load_kind: int) -> void:
	if _boxes + 42 > MAX_BOXES or _stats["handcarts"] >= 9:
		return
	var front := -float(house.get("depth", 6.0)) * 0.5
	var width := float(house.get("width", 5.0))
	var rotation := float(house.get("orientation", 0.0))
	# The long shafts run parallel to the facade, never out across the road.
	for x in [side * (width * 0.5 - 0.75), side * (width * 0.5 + 0.875)]:
		var origin := _world(house, Vector3(x, 0, front - 0.875))
		var cart_rotation := rotation + (PI if side < 0.0 else 0.0)
		var centre := origin + Basis(Vector3.UP, cart_rotation) * Vector3(0.375, 0, 0)
		var footprint := _solid_footprint(centre, Vector2(3.25, 1.625), cart_rotation) if _volume != null else _rectangle(centre, Vector2(3.25, 1.625), cart_rotation)
		if not _clear(footprint):
			continue
		_occupied.append(footprint)
		_structure(origin, Vector3(-0.25, 0.6875, 0), Vector3(1.75, 0.125, 1.0), 9, cart_rotation)
		for sz in [-0.5, 0.5]:
			_structure(origin, Vector3(-0.25, 0.9375, sz), Vector3(1.875, 0.375, 0.125), 19, cart_rotation)
			_structure(origin, Vector3(1.125, 0.625, sz), Vector3(1.75, 0.125, 0.125), 10, cart_rotation)
		for sx in [-1.0625, 0.5625]:
			_structure(origin, Vector3(sx, 0.9375, 0), Vector3(0.125, 0.375, 1.0), 9, cart_rotation)
		_structure(origin, Vector3(-0.3125, 0.375, 0), Vector3(0.125, 0.125, 1.5), 22, cart_rotation)
		_structure(origin, Vector3(1.625, 0.3125, 0), Vector3(0.125, 0.625, 0.125), 10, cart_rotation)
		for sz in [-0.6875, 0.6875]:
			# Block wheels show an axle, broad rim and a contrasting square hub.
			_structure(origin, Vector3(-0.3125, 0.375, sz), Vector3(0.625, 0.25, 0.125), 10, cart_rotation)
			_structure(origin, Vector3(-0.3125, 0.375, sz), Vector3(0.25, 0.75, 0.125), 10, cart_rotation)
			_structure(origin, Vector3(-0.3125, 0.375, sz), Vector3(0.125, 0.125, 0.25), 22, cart_rotation)
		if load_kind == 2:
			for sx in [-0.625, -0.125, 0.375]:
				_box(origin, Vector3(sx, 0.9375, 0), Vector3(0.25, 0.375, 0.75), 10, cart_rotation)
				_box(origin, Vector3(sx, 1.1875, 0), Vector3(0.125, 0.125, 0.75), 22, cart_rotation)
		else:
			for sx in [-0.625, 0.125]:
				_basket(origin, Vector3(sx, 0.75, 0), cart_rotation, 28 if load_kind == 0 else 18)
		_stats["handcarts"] += 1
		_activity_sites.append({"house": house, "side": side})
		return

func _try_display(house: Dictionary, side: float, district: String, seed_value: int) -> void:
	if _boxes + 28 > MAX_BOXES:
		return
	var half_width := float(house.get("width", 5.0)) * 0.5
	var front := -float(house.get("depth", 6.0)) * 0.5
	var rotation := float(house.get("orientation", 0.0))
	var produce := district in ["market", "old_quarter", "main_avenue"]
	var origin := Vector3.ZERO
	var placed := false
	# On a narrow terrace the useful frontage is between two entrances, just
	# beside the building corner. Try that strip before giving up the display.
	for x in [side * (half_width - 0.5625), side * (half_width - 0.125), side * (half_width + 0.375)]:
		origin = _world(house, Vector3(x, 0, front - (0.5 if produce else 0.4375)))
		var footprint_centre := origin + Basis(Vector3.UP, rotation) * Vector3(0, 0, 0 if produce else -0.0625)
		if _reserve(footprint_centre, Vector2(1.0, 0.875), rotation):
			placed = true
			break
	if not placed:
		return
	if produce:
		_open_crate(origin, rotation, 28 if posmod(seed_value, 3) == 0 else 18)
		_stats["produce_displays"] += 1
	else:
		for offset in [Vector3(-0.25, 0, -0.125), Vector3(0.25, 0, 0.125), Vector3(0, 0.5, 0)]:
			_box(origin, offset + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), 19, rotation)
			_box(origin, offset + Vector3(0, 0.5, 0), Vector3(0.375, 0.125, 0.375), 11, rotation)
			_box(origin, offset + Vector3(0, 0.3125, -0.3125), Vector3(0.125, 0.5, 0.125), 10, rotation)
		_stats["goods_stacks"] += 1

func _try_work_rack(house: Dictionary, side: float, seed_value: int) -> void:
	if _boxes + 12 > MAX_BOXES or _stats["work_racks"] >= 14:
		return
	var x := side * (float(house.get("width", 5.0)) * 0.5 - 0.625)
	var front := -float(house.get("depth", 6.0)) * 0.5
	var origin := _world(house, Vector3(x, 0, front - 0.4375))
	var rotation := float(house.get("orientation", 0.0))
	if not _reserve(origin, Vector2(1.125, 0.75), rotation):
		return
	# Chopped firewood or a carpenter's leaning offcuts, close against the wall.
	if posmod(seed_value, 2) == 0:
		for layer in range(3):
			for sx in [-0.3125, 0.1875]:
				_box(origin, Vector3(sx, 0.125 + float(layer) * 0.25, 0), Vector3(0.375, 0.25, 0.5), 10, rotation)
				_box(origin, Vector3(sx, 0.125 + float(layer) * 0.25, -0.3125), Vector3(0.25, 0.25, 0.125), 19, rotation)
	else:
		for i in range(4):
			var height := 1.0 + float(posmod(seed_value + i, 3)) * 0.375
			_box(origin, Vector3(-0.375 + float(i) * 0.25, height * 0.5, 0), Vector3(0.125, height, 0.25), 9 if i % 2 == 0 else 19, rotation)
		_box(origin, Vector3(0, 0.625, -0.1875), Vector3(1.0, 0.125, 0.125), 10, rotation)
	_stats["work_racks"] += 1
	_activity_sites.append({"house": house, "side": side})

func _try_static_figure(house: Dictionary, side: float) -> void:
	if _boxes + 16 > MAX_BOXES:
		return
	var seed_value := int(house.get("seed", 0))
	var district := str(house.get("district", "old_quarter"))
	var width := float(house.get("width", 5.0))
	var front := -float(house.get("depth", 6.0)) * 0.5
	var rotation := float(house.get("orientation", 0.0))
	for x in [side * (width * 0.5 - 0.1875), side * (width * 0.5 + 0.625), side * (width * 0.5 - 1.0)]:
		var origin := _world(house, Vector3(x, 0, front - 0.5))
		if not _reserve(origin, Vector2(0.875, 0.875), rotation):
			continue
		var coat := _cloth(district, seed_value)
		for sx in [-0.125, 0.125]:
			_box(origin, Vector3(sx, 0.0625, -0.0625), Vector3(0.125, 0.125, 0.25), 10, rotation)
			_box(origin, Vector3(sx, 0.4375, 0), Vector3(0.125, 0.625, 0.125), 22, rotation)
		_box(origin, Vector3(0, 0.8125, 0), Vector3(0.375, 0.25, 0.25), 22, rotation)
		_box(origin, Vector3(0, 1.125, 0), Vector3(0.375, 0.5, 0.25), coat, rotation)
		_box(origin, Vector3(0, 1.375, 0), Vector3(0.125, 0.125, 0.125), 12, rotation)
		_box(origin, Vector3(0, 1.5625, 0), Vector3(0.375, 0.375, 0.375), 12, rotation)
		_box(origin, Vector3(0, 1.75, 0.0625), Vector3(0.375, 0.125, 0.25), 10, rotation)
		for sx in [-0.25, 0.25]:
			_box(origin, Vector3(sx, 1.125, 0), Vector3(0.125, 0.5, 0.125), coat, rotation)
			_box(origin, Vector3(sx, 0.9375, -0.1875), Vector3(0.125, 0.125, 0.5), 12, rotation)
		if posmod(seed_value, 3) == 0:
			# Porter carrying a small slatted parcel close against the chest.
			_box(origin, Vector3(0, 1.0, -0.3125), Vector3(0.375, 0.375, 0.25), 19, rotation)
			for sx in [-0.125, 0.125]:
				_box(origin, Vector3(sx, 1.0, -0.40625), Vector3(0.0625, 0.375, 0.0625), 10, rotation)
		else:
			# A vendor's tray / craft worker's tool is deliberately understated.
			_box(origin, Vector3(0, 0.875, -0.25), Vector3(0.5, 0.125, 0.375), 9, rotation)
		_stats["static_figures"] += 1
		return

func _trade_sign(house: Dictionary, side: float, symbol: int, cloth: int) -> void:
	if _boxes + 20 > MAX_BOXES or _stats["trade_signs"] >= 24:
		return
	var width := float(house.get("width", 5.0))
	var front := -float(house.get("depth", 6.0)) * 0.5
	var origin := _world(house, Vector3(side * (width * 0.5 - 0.75), 0, front))
	var rotation := float(house.get("orientation", 0.0))
	_box(origin, Vector3(0, 3.375, -0.0625), Vector3(0.25, 0.625, 0.125), 10, rotation)
	_box(origin, Vector3(0, 3.5625, -0.4375), Vector3(0.125, 0.125, 0.875), 22, rotation)
	for sx in [-0.3125, 0.3125]:
		_box(origin, Vector3(sx, 3.25, -0.75), Vector3(0.125, 0.5, 0.125), 22, rotation)
	_box(origin, Vector3(0, 2.75, -0.75), Vector3(1.0, 0.75, 0.125), cloth, rotation)
	for y in [2.3125, 3.1875]:
		_box(origin, Vector3(0, y, -0.75), Vector3(1.125, 0.125, 0.25), 10, rotation)
	# A broad cream silhouette stays readable without text textures or decals.
	for sz in [-0.875, -0.625]:
		if symbol == 2: # Hammer / smith.
			_box(origin, Vector3(0, 2.6875, sz), Vector3(0.125, 0.5, 0.125), 20, rotation)
			_box(origin, Vector3(0.0625, 2.9375, sz), Vector3(0.5, 0.25, 0.125), 20, rotation)
		elif symbol == 1: # Loaf / provisioner.
			_box(origin, Vector3(0, 2.6875, sz), Vector3(0.625, 0.25, 0.125), 20, rotation)
			_box(origin, Vector3(0, 2.875, sz), Vector3(0.375, 0.125, 0.125), 20, rotation)
		elif symbol == 3: # Tailor's spool.
			_box(origin, Vector3(0, 2.75, sz), Vector3(0.25, 0.5, 0.125), 20, rotation)
			for y in [2.5, 3.0]:
				_box(origin, Vector3(0, y, sz), Vector3(0.5, 0.125, 0.125), 20, rotation)
		else: # Tankard / inn.
			_box(origin, Vector3(-0.0625, 2.75, sz), Vector3(0.375, 0.5, 0.125), 20, rotation)
			_box(origin, Vector3(0.25, 2.75, sz), Vector3(0.125, 0.25, 0.125), 20, rotation)
	_stats["trade_signs"] += 1

func _open_crate(origin: Vector3, rotation: float, produce: int) -> void:
	_box(origin, Vector3(0, 0.0625, 0), Vector3(0.875, 0.125, 0.75), 9, rotation)
	for sx in [-0.4375, 0.4375]:
		_box(origin, Vector3(sx, 0.3125, 0), Vector3(0.125, 0.5, 0.875), 19, rotation)
	for sz in [-0.375, 0.375]:
		_box(origin, Vector3(0, 0.3125, sz), Vector3(0.75, 0.5, 0.125), 9, rotation)
	for sx in [-0.25, 0.0, 0.25]:
		for sz in [-0.1875, 0.1875]:
			_box(origin, Vector3(sx, 0.5625, sz), Vector3(0.25, 0.25, 0.25), produce, rotation)
	_box(origin, Vector3(0, 0.75, 0), Vector3(0.25, 0.125, 0.25), produce, rotation)

func _basket(origin: Vector3, offset: Vector3, rotation: float, produce: int) -> void:
	_box(origin, offset + Vector3(0, 0.0625, 0), Vector3(0.5, 0.125, 0.625), 19, rotation)
	for sx in [-0.25, 0.25]:
		_box(origin, offset + Vector3(sx, 0.25, 0), Vector3(0.125, 0.25, 0.625), 19, rotation)
	for sz in [-0.25, 0.25]:
		_box(origin, offset + Vector3(0, 0.25, sz), Vector3(0.375, 0.25, 0.125), 9, rotation)
	for sx in [-0.125, 0.125]:
		_box(origin, offset + Vector3(sx, 0.375, 0), Vector3(0.25, 0.25, 0.375), produce, rotation)

func _world(house: Dictionary, local: Vector3) -> Vector3:
	var centre: Vector3 = house["centre"]
	return centre + Basis(Vector3.UP, float(house.get("orientation", 0.0))) * local

func _rectangle(centre: Vector3, size: Vector2, rotation: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var basis := Basis(Vector3.UP, rotation)
	for p in [Vector3(-size.x * 0.5, 0, -size.y * 0.5), Vector3(size.x * 0.5, 0, -size.y * 0.5),
		Vector3(size.x * 0.5, 0, size.y * 0.5), Vector3(-size.x * 0.5, 0, size.y * 0.5)]:
		var point: Vector3 = centre + basis * p
		result.append(Vector2(point.x, point.z))
	return result

func _reserve(centre: Vector3, size: Vector2, rotation: float) -> bool:
	var polygon := _rectangle(centre, size, rotation)
	if not _clear(polygon):
		return false
	_occupied.append(polygon)
	return true

func _solid_footprint(centre: Vector3, size: Vector2, rotation: float) -> PackedVector2Array:
	var polygon := _rectangle(centre, size, rotation)
	var minimum := polygon[0]
	var maximum := polygon[0]
	for point: Vector2 in polygon:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	minimum = Vector2(floorf(minimum.x * 2.0 + 0.0001), floorf(minimum.y * 2.0 + 0.0001)) * 0.5
	maximum = Vector2(ceilf(maximum.x * 2.0 - 0.0001), ceilf(maximum.y * 2.0 - 0.0001)) * 0.5
	return PackedVector2Array([minimum, Vector2(maximum.x, minimum.y), maximum, Vector2(minimum.x, maximum.y)])

func _structure(origin: Vector3, offset: Vector3, size: Vector3, material_id: int, rotation: float) -> void:
	if _volume != null:
		_solid_box(origin, offset, size, material_id, rotation)
	else:
		_box(origin, offset, size, material_id, rotation)

func _solid_box(origin: Vector3, offset: Vector3, size: Vector3, material_id: int, rotation: float) -> void:
	var centre := origin + Basis(Vector3.UP, rotation) * offset
	var footprint := _solid_footprint(centre, Vector2(size.x, size.z), rotation)
	var minimum := Vector3i(roundi(footprint[0].x * 2.0), floori((centre.y - size.y * 0.5) * 2.0 + 0.0001), roundi(footprint[0].y * 2.0))
	var maximum := Vector3i(roundi(footprint[2].x * 2.0), ceili((centre.y + size.y * 0.5) * 2.0 - 0.0001), roundi(footprint[2].y * 2.0))
	_volume.box(minimum, maximum, material_id)
	_solid_boxes += 1

func _clear(polygon: PackedVector2Array) -> bool:
	for collection: Array in [_roads, _entries, _footprints, _occupied]:
		for other: PackedVector2Array in collection:
			if not Geometry2D.intersect_polygons(polygon, other).is_empty():
				return false
	return true

func _box(origin: Vector3, offset: Vector3, size: Vector3, material_id: int, rotation: float) -> void:
	if _boxes >= MAX_BOXES:
		return
	_details.add_box(origin + Basis(Vector3.UP, rotation) * offset, size, material_id, rotation)
	_boxes += 1
