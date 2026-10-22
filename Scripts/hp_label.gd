# hp_label.gd
extends Label

func _ready():
	# Bottom right, just above the shop bar, so the windows under the top-right buttons never cover it.
	# All four offsets are set, so the box is exactly 120x48 whatever the scene had before.
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(120, 48)
	offset_right = -24
	offset_left = -24 - 120
	offset_bottom = -96
	offset_top = -96 - 48
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 36)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.hp_changed.connect(_update)
	_update(GameState.player_hp)

func _update(hp: int):
	text = "HP %d" % hp
	var ratio := float(hp) / float(maxi(GameState.start_hp, 1))   # campaign levels can start below 100
	if ratio <= 0.25:
		modulate = Color(1.0, 0.35, 0.35)
	elif ratio <= 0.5:
		modulate = Color(1.0, 0.85, 0.3)
	else:
		modulate = Color.WHITE
