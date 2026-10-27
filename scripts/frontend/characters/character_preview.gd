extends Node3D
## Presentation adapter for the completed block characters. No gameplay/input state.
## The source model faces -Z. This wrapper faces +Z for CharacterSlot's camera.

const VoxelCharacter = preload("res://scripts/frontend/characters/voxel_character.gd")

@export_enum("warrior", "mage", "scout", "archer", "cleric", "artisan") var job_id := "warrior"
@export var female := false
var model: Node3D


func _ready() -> void:
	model = VoxelCharacter.new()
	model.name = "CharacterModel"
	model.configure(job_id, female)
	model.rotation.y = PI - 0.22
	add_child(model)


func _process(delta: float) -> void:
	if is_instance_valid(model):
		model.animate(0.0, delta)


func set_weapon_visible(enabled: bool) -> void:
	if is_instance_valid(model):
		var weapon := model.find_child("EquippedWeapon", true, false)
		if weapon is Node3D:
			weapon.visible = enabled
