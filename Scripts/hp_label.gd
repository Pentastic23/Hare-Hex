# hp_label.gd
extends Label

func _ready():
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -24
	custom_minimum_size = Vector2(120, 48)
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
	if hp <= 25:
		modulate = Color(1.0, 0.35, 0.35)
	elif hp <= 50:
		modulate = Color(1.0, 0.85, 0.3)
	else:
		modulate = Color.WHITE
