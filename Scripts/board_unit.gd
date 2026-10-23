# board_unit.gd
class_name BoardUnit extends Resource

# One enemy in an EnemyBoard: what it is, how strong, where it stands.

@export var unit: UnitData
@export_range(1, 3) var star := 1
@export var coord := Vector2i(-1, -1)   # enemy half (rows 0-3); (-1, -1) = place automatically
@export var items: Array[ItemData] = []
@export var stacks := {}   # bound items (items v2): item id -> stacks
