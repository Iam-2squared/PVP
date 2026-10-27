extends Node3D

const Player = preload("res://scripts/player_controller.gd")
var world: Node3D
var player: CharacterBody3D

func _ready() -> void:
	_lighting()
	var scene: PackedScene = load("res://generated/kingdom.scn")
	if scene == null:
		push_error("Baked world missing. Run: godot --headless --path . --script res://tools/bake_voxel_world.gd")
		return
	world = scene.instantiate()
	add_child(world)
	player = Player.new()
	player.name = "Player"
	player.world = world
	add_child(player)
	player.position = world.get_spawn_position()
	print("VOXEL_WORLD_READY ",JSON.stringify(world.stats))

func _lighting() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("649fc7")
	sky_material.sky_horizon_color = Color("d0dfdf")
	sky_material.ground_bottom_color = Color("73885f")
	sky_material.ground_horizon_color = Color("d0dfdf")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d3e2ed")
	environment.ambient_light_energy = 0.30
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color("b9d0d9")
	environment.fog_density = 0.00010
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-43, -28, 0)
	sun.light_color = Color("fff5e5")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_split_1 = 0.15
	sun.shadow_bias = 0.18
	sun.shadow_normal_bias = 2.0
	add_child(sun)
