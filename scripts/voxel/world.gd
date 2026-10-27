extends Node3D
## Runtime data is baked with the geometry; no voxel generation is needed to play.

@export var landmarks: Array[Dictionary] = []
@export var city_vertices := PackedVector2Array()
@export var city_half_extent := 160.0
@export var stats: Dictionary = {}
@export var spawn_position := Vector3(0, 3.0, 152)
@export var palace_data: Dictionary = {}
@export var town_data: Dictionary = {}
@export var preview_locations: Array[Dictionary] = []
@export var house_count := 0
var _interiors: Array[Dictionary] = []
var _visibility_timer := 0.0

func _ready() -> void:
	set_meta("environment_preview", true)
	set_meta("world_extent", 320.0)
	for child in get_children():
		if str(child.name).begins_with("PalaceInterior_"):
			_interiors.append({"node":child,"level":float(child.get_meta("floor_y",3.0))})

func _process(delta: float) -> void:
	_visibility_timer -= delta
	if _visibility_timer>0.0 or _interiors.is_empty(): return
	_visibility_timer=0.2
	var player: Variant=get_parent().get("player")
	if not player is Node3D: return
	var p: Vector3=player.global_position
	var nearby:=Rect2(-72,-164,144,149).has_point(Vector2(p.x,p.z))
	var overview: bool=player.has_method("get_overview") and player.get_overview()
	for part in _interiors:
		part["node"].visible=nearby and not overview and absf(p.y+1.65-part["level"])<16.0

func get_spawn_position() -> Vector3:
	return spawn_position
