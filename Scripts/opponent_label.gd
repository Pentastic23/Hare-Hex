# opponent_label.gd
extends Label

# TopBar: who the coming fight is against in async PvP ("vs Ghost of You (round 9, level 5, 74 HP)").
# Hidden in free play and the campaign, where GameManager announces nothing.

func _ready():
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	Events.opponent_announced.connect(func(t: String):
		text = "   vs %s" % t if t != "" else ""
		visible = t != "")
