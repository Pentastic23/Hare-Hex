# odds_label.gd
extends Label

func _ready():
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 6)

	Events.xp_changed.connect(func(l, _x, _n): _update(l))
	await get_tree().process_frame
	_update(GameState.level)

func _update(level: int):
	var odds: Array = GameState.odds_for_level(level)
	var parts: PackedStringArray = []
	for i in odds.size():
		parts.append("%dg: %d%%" % [i + 1, odds[i]])
	text = "Shop odds   " + "   ".join(parts)
