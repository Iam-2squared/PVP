extends RefCounted
## Offline generation only. Edit the source, then run tools/bake_voxel_world.gd.

const World = preload("res://scripts/voxel/world.gd")
const Terrain = preload("res://scripts/voxel/terrain.gd")
const Volume = preload("res://scripts/voxel/volume.gd")
const Walls = preload("res://scripts/voxel/walls.gd")
const Mesher = preload("res://scripts/voxel/mesher.gd")

func build(stage: String = "town") -> Node3D:
	var world = World.new()
	world.name = "VoxelKingdom"
	world.set_meta("environment_preview", true)
	world.set_meta("world_extent", 320.0)
	var terrain = Terrain.new()
	var ground: Node3D = terrain.build()
	world.add_child(ground)
	var volume = Volume.new()
	var description: Dictionary = Walls.new().build(volume)
	var walls: Node3D = Mesher.new().build_meshes(volume)
	walls.name = "Fortifications"
	world.add_child(walls)
	world.city_vertices = description.get("city_vertices", PackedVector2Array())
	world.city_half_extent = 160.0
	world.landmarks.assign(description.get("gates", []))
	world.stats = {
		"stage": stage,
		"terrain": ground.get_meta("terrain_stats", {}),
		"walls": walls.get_meta("mesh_stats", {}),
		"design": description,
		"voxel_size_m": 0.5
	}
	world.spawn_position = Vector3(0, terrain.height_at(0, 186) + 0.15, 186)
	world.preview_locations.append({"id":"south_gate","title":"南・戴冠門","position":world.spawn_position,"yaw_degrees":0.0,"pitch_degrees":14.0})
	var stair: Dictionary=description.get("stairs",{})
	if stair.has("top"):
		world.preview_locations.append({"id":"wall_walk","title":"城壁上の歩廊","position":stair["top"]+Vector3.UP*0.15,"yaw_degrees":0.0,"pitch_degrees":-4.0})
	volume.cells.clear()
	if stage == "palace" or stage == "town":
		_build_palace(world)
	if stage == "town":
		_build_town(world)
	return world

func _build_palace(world: Node3D) -> void:
	var palace = load("res://scripts/voxel/palace.gd").new()
	var exterior = Volume.new()
	var interiors: Array = []
	var info: Dictionary = palace.build(exterior, interiors)
	var outside: Node3D = Mesher.new().build_meshes(exterior)
	outside.name = "RoyalPalaceExterior"
	world.add_child(outside)
	world.stats["palace_exterior"] = outside.get_meta("mesh_stats", {})
	exterior.cells.clear()
	var floor_stats: Array = []
	for i in range(interiors.size()):
		var part = interiors[i]
		var floor_volume = part.get("volume") if part is Dictionary else part
		var floor_node: Node3D = Mesher.new().build_meshes(floor_volume)
		floor_node.name = "PalaceInterior_%d" % i
		var levels: Array=info.get("floor_levels",[3.0,9.0,15.0,21.0,27.0,33.0])
		var floor_y: float=float(part.get("level",levels[mini(i,levels.size()-1)])) if part is Dictionary else float(levels[mini(i,levels.size()-1)])
		floor_node.set_meta("floor_y",floor_y)
		_disable_shadows(floor_node)
		world.add_child(floor_node)
		floor_stats.append(floor_node.get_meta("mesh_stats", {}))
		floor_volume.cells.clear()
	world.palace_data = info
	world.stats["palace_interiors"] = floor_stats
	world.stats["palace"] = info
	var detail_parts: Array=load("res://scripts/voxel/palace_details.gd").new().build(info)
	var dressing_stats: Array=[]
	for part: Node3D in detail_parts:
		world.add_child(part)
		dressing_stats.append(part.get_meta("detail_stats",{}))
	world.stats["palace_details"]=dressing_stats
	world.landmarks.append_array(info.get("landmarks", []))
	world.preview_locations.append_array(info.get("viewpoints", []))

func _build_town(world: Node3D) -> void:
	var town = load("res://scripts/voxel/town.gd").new()
	var volume = Volume.new()
	var info: Dictionary = town.build(volume)
	# District floors form one nonoverlapping surface at the city base height.
	# Keep the simple stone fallback only for earlier construction stages.
	var ground: Node3D=world.get_node("LevelKingdomGround")
	var fallback:=ground.get_node_or_null("ContinuousCityPaving")
	if fallback!=null:
		ground.remove_child(fallback)
		fallback.free()
	var surfaces: Node3D=load("res://scripts/voxel/district_surfaces.gd").new().build(info,world.palace_data)
	world.add_child(surfaces)
	world.stats["district_surfaces"]=surfaces.get_meta("surface_stats",{})
	world.stats["terrain"]["city_paving"]="district_materials"
	world.stats["terrain"]["land_triangles"]=12
	world.stats["terrain"]["land_chunks"]=1
	var node: Node3D = Mesher.new().build_meshes(volume)
	# Keep city assets independent and small; chunk-local transforms stay intact.
	var districts: Dictionary={}
	for chunk in node.get_children():
		var north: bool=chunk.position.z<0.0
		var west: bool=chunk.position.x<0.0
		var district: String=("North" if north else "South")+("West" if west else "East")
		if not districts.has(district):
			var group:=Node3D.new()
			group.name="TownDistrict"+district
			world.add_child(group)
			districts[district]=group
		node.remove_child(chunk)
		districts[district].add_child(chunk)
	world.town_data = info
	world.house_count = int(info.get("house_count", 0))
	world.stats["town"] = info
	world.stats["town_mesh"] = node.get_meta("mesh_stats", {})
	node.free()
	world.landmarks.append_array(info.get("landmarks", []))
	world.preview_locations.append_array(info.get("viewpoints", []))
	volume.cells.clear()
	if town.has_method("take_details"):
		var details: Node3D=town.take_details()
		if details!=null:
			world.add_child(details)
			world.stats["town_details"]=details.get_meta("detail_stats",{})

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _disable_shadows(child)
