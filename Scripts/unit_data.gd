# unit_data.gd
class_name UnitData extends Resource

@export var display_name: String
@export var short_name := ""   # 2-3 letters on the unit's body; empty = the first two letters of the name
@export var max_health := 100.0
@export var max_mana := 60.0
@export var start_mana := 0.0
@export var attack_damage := 10.0
@export var attack_range := 2.0
@export var attacks_per_second := 1.0
@export var move_speed := 3.0
@export var ability: Ability
@export var cost := 1
@export var tags: Array[StringName] = []
@export var model: PackedScene

# What shows on the unit's capsule. Every unit has its own (tools/roster_checks keeps them unique).
func label() -> String:
	return short_name if short_name != "" else display_name.substr(0, 2).to_upper()
