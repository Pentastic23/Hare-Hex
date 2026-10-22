# hud_plate.gd
class_name HudPlate extends PanelContainer

# One plate of the combat HUD: a dark semi-opaque fill, a 2 px lit top edge (its colour carries the
# state) and a hard 3 px shadow straight down. StyleBoxFlat's own shadow is blurred, so _draw adds
# the lip under the panel.

var _style: StyleBoxFlat
var _lip: StyleBoxFlat

# Padding in px: top, left/right, bottom (as in the spec).
func setup_plate(pad_top: int, pad_side: int, pad_bottom: int, fill := HudStyle.FILL) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = fill
	_style.border_width_top = 2
	_style.border_color = HudStyle.EDGE
	_style.set_corner_radius_all(3)
	_style.content_margin_top = pad_top + 2
	_style.content_margin_left = pad_side
	_style.content_margin_right = pad_side
	_style.content_margin_bottom = pad_bottom
	add_theme_stylebox_override("panel", _style)
	_lip = StyleBoxFlat.new()
	_lip.bg_color = HudStyle.LIP
	_lip.corner_radius_bottom_left = 3
	_lip.corner_radius_bottom_right = 3

func set_edge(c: Color) -> void:
	if _style != null and _style.border_color != c:
		_style.border_color = c

func set_fill(c: Color) -> void:
	if _style != null and _style.bg_color != c:
		_style.bg_color = c

func edge() -> Color:
	return _style.border_color if _style != null else HudStyle.EDGE

func _draw():
	if _lip != null:
		draw_style_box(_lip, Rect2(0, size.y, size.x, 3))
