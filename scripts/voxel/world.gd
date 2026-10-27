extends Node3D
## Runtime data is baked with the geometry; no voxel generation is needed to play.

@export var landmarks: Array[Dictionary] = []
@export var city_vertices := PackedVector2Array()
@export var city_half_extent := 128.0
@export var stats: Dictionary = {}
@export var spawn_position := Vector3(0, 3.0, 152)
var house_count := 0

func _ready() -> void:
	set_meta("environment_preview", true)
	set_meta("world_extent", 320.0)

func get_spawn_position() -> Vector3:
	return spawn_position
