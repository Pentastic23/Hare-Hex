# item_bar.gd
extends PanelContainer

const SLOT := Vector2(52, 52)

@onready var grid: GridContainer = $Grid

func _ready():
	Events.items_changed.connect(_rebuild)
	_rebuild()

func _rebuild():
	for c in grid.get_children():
		c.queue_free()
	for i in GameState.items.size():
		grid.add_child(_make_button(GameState.items[i], i))
	visible = not GameState.items.is_empty()   # hidden when the inventory is empty

func _make_button(item: ItemData, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	b.text = item.display_name.substr(0, 2).to_upper()
	b.tooltip_text = "%s\n%s" % [item.display_name, item.description]
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_stylebox_override("normal", _style(item.color))
	b.add_theme_stylebox_override("hover", _style(item.color.lightened(0.2)))
	b.add_theme_stylebox_override("pressed", _style(item.color.darkened(0.2)))
	b.set_meta("item_index", index)   # index into GameState.items; used when dragging
	return b

func _style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = Color(1.0, 0.85, 0.3)
	return s
