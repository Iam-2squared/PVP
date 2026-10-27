extends RefCounted
## Offline generation only. Edit the source, then run tools/bake_voxel_world.gd.

const World = preload("res://scripts/voxel/world.gd")
const Terrain = preload("res://scripts/voxel/terrain.gd")
const Volume = preload("res://scripts/voxel/volume.gd")
const Walls = preload("res://scripts/voxel/walls.gd")
const Mesher = preload("res://scripts/voxel/mesher.gd")

func build() -> Node3D:
	var world = World.new()
	world.name = "VoxelKingdom"
	world.set_meta("environment_preview", true)
	world.set_meta("world_extent", 320.0)
	var terrain = Terrain.new()
	var ground: Node3D = terrain.build()
	world.add_child(ground)
	_ocean_horizon(world)
	var volume = Volume.new()
	var description: Dictionary = Walls.new().build(volume)
	var walls: Node3D = Mesher.new().build_meshes(volume)
	walls.name = "Fortifications"
	world.add_child(walls)
	world.city_vertices = description.get("city_vertices", PackedVector2Array())
	world.landmarks.assign(description.get("gates", []))
	world.stats = {
		"terrain": ground.get_meta("terrain_stats", {}),
		"walls": walls.get_meta("mesh_stats", {}),
		"design": description,
		"voxel_size_m": 0.5
	}
	world.spawn_position = Vector3(0, terrain.height_at(0, 152) + 0.15, 152)
	volume.cells.clear()
	return world

func _ocean_horizon(world: Node3D) -> void:
	var ocean := MeshInstance3D.new()
	ocean.name = "OceanHorizon"
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000,3000)
	ocean.mesh = plane
	ocean.position.y = -0.03
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("24637e")
	material.roughness = 0.7
	material.metallic_specular = 0.1
	ocean.material_override = material
	world.add_child(ocean)
