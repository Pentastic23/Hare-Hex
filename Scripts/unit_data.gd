# unit_data.gd
class_name UnitData extends Resource

@export var display_name: String
@export var short_name := ""   # 2-3 letters on the unit's body; empty = the first two letters of the name
@export var max_health := 100.0
@export var max_mana := 60.0
@export var start_mana := 0.0
@export var attack_damage := 10.0
@export var armor := 0.0          # flat: physical damage taken x 100 / (100 + armor)
@export var magic_resist := 0.0   # flat: magic damage taken, the same way
@export var attack_range := 2.0
@export var attacks_per_second := 1.0
@export var move_speed := 3.0
@export var ability: Ability
@export var cost := 1
@export var tags: Array[StringName] = []
# The unit's model scene (scenes/models/*.tscn), stored as a path so loading a unit's data (the roster,
# every campaign wave) doesn't load its 3D model; `model` loads it on first use, and Preload warms
# them in the background on the main menu.
@export_file("*.tscn") var model_path := ""
var model: PackedScene:
	get:
		return load(model_path) as PackedScene if model_path != "" else null

func has_model() -> bool:
	return model_path != ""

# What shows on the unit's capsule. Every unit has its own (tools/roster_checks keeps them unique).
func label() -> String:
	return short_name if short_name != "" else display_name.substr(0, 2).to_upper()
