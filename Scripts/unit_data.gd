# unit_data.gd
class_name UnitData extends Resource

@export var display_name: String
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
