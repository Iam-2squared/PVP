extends RefCounted
## Built-in character presentations, indexed by the same job IDs as home_data.gd.

const SCENES := {
	"warrior": {
		"male": preload("res://scenes/frontend/characters/warrior_male.tscn"),
		"female": preload("res://scenes/frontend/characters/warrior_female.tscn"),
	},
	"mage": {
		"male": preload("res://scenes/frontend/characters/mage_male.tscn"),
		"female": preload("res://scenes/frontend/characters/mage_female.tscn"),
	},
	"scout": {
		"male": preload("res://scenes/frontend/characters/scout_male.tscn"),
		"female": preload("res://scenes/frontend/characters/scout_female.tscn"),
	},
	"archer": {
		"male": preload("res://scenes/frontend/characters/archer_male.tscn"),
		"female": preload("res://scenes/frontend/characters/archer_female.tscn"),
	},
	"cleric": {
		"male": preload("res://scenes/frontend/characters/cleric_male.tscn"),
		"female": preload("res://scenes/frontend/characters/cleric_female.tscn"),
	},
	"artisan": {
		"male": preload("res://scenes/frontend/characters/artisan_male.tscn"),
		"female": preload("res://scenes/frontend/characters/artisan_female.tscn"),
	},
}


static func scene_for(job_id: String, female: bool = false) -> PackedScene:
	var variants: Dictionary = SCENES.get(job_id, SCENES["warrior"])
	return variants["female" if female else "male"]
