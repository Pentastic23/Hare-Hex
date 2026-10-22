# item_bar.gd
extends PanelContainer

const SLOT := Vector2(52, 52)

@onready var grid: GridContainer = $Grid

var _ghost: Label   # follows the mouse while an item is being dragged
var header: Button  # folds the item grid open or closed (Settings.show_items)
var expanded := true

func _ready():
	# Header above the grid: move the grid into a VBox under a fold button.
	Settings.ensure_loaded()
	expanded = Settings.show_items
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	header = Button.new()
	header.flat = true
	header.focus_mode = Control.FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	header.add_theme_color_override("font_hover_color", Color.WHITE)
	header.tooltip_text = Tip.wrap("Show or hide your items.")
	header.pressed.connect(func():
		expanded = not expanded
		Settings.show_items = expanded
		Settings.save_settings()
		_apply_expanded())
	box.add_child(header)
	remove_child(grid)
	box.add_child(grid)
	Events.items_changed.connect(_rebuild)
	Events.item_drag_started.connect(_on_drag_started)
	Events.item_drag_ended.connect(_on_drag_ended)
	set_process(false)
	_rebuild()

func _process(_delta):
	_ghost.position = get_viewport().get_mouse_position() + Vector2(16, 16)

func _on_drag_started(index: int):
	if index < 0 or index >= GameState.me.items.size():
		return
	var item: ItemData = GameState.me.items[index]
	if _ghost == null:
		_ghost = Label.new()
		_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE   # must not block the drop target under the mouse
		_ghost.add_theme_color_override("font_outline_color", Color.BLACK)
		_ghost.add_theme_constant_override("outline_size", 6)
		get_parent().add_child(_ghost)
	_ghost.text = item.display_name
	_ghost.add_theme_stylebox_override("normal", _style(item.color))
	_ghost.visible = true
	set_process(true)

func _on_drag_ended():
	set_process(false)
	if _ghost != null:
		_ghost.visible = false

func _rebuild():
	for c in grid.get_children():
		c.queue_free()
	for i in GameState.me.items.size():
		grid.add_child(_make_button(GameState.me.items[i], i))
	visible = not GameState.me.items.is_empty()   # hidden when the inventory is empty
	_apply_expanded()

func _apply_expanded():
	grid.visible = expanded
	header.text = "Items  [-]" if expanded else "Items (%d)  [+]" % GameState.me.items.size()

func _make_button(item: ItemData, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	b.text = item.display_name.substr(0, 2).to_upper()
	b.tooltip_text = Tip.wrap("%s\n%s" % [item.display_name, item.description])
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_stylebox_override("normal", _style(item.color))
	b.add_theme_stylebox_override("hover", _style(item.color.lightened(0.2)))
	b.add_theme_stylebox_override("pressed", _style(item.color.darkened(0.2)))
	b.button_down.connect(Events.item_drag_started.emit.bind(index))   # index into GameState.me.items
	return b

func _style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = Color(1.0, 0.85, 0.3)
	return s
