# ability.gd
class_name Ability extends Resource

@export var ability_name := "Placeholder"
@export_multiline var description := "Does nothing yet."

# Override this in real abilities later.
func cast(caster: Unit, target: Unit) -> void:
	pass
