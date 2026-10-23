# item_bar.gd
extends VBoxContainer

# The Items tab of the left box (left_dock.gd; DOCKS_SPEC "Items tab"): one row per item type you
# own (icon in a well with an edge in the item's colour, name, description, "x2" for duplicates),
# then a hint. Press a row and drag onto a unit to equip it: the row emits
# Events.item_drag_started(index into GameState.me.items) and drag_controller.gd does the rest, as
# before. A label follows the mouse while dragging.

const ICON := 34.0
const SLOT := 38.0

var list: VBoxContainer
var hint: Label
var _ghost: Label   # follows the mouse while an item is being dragged

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	list = VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 4)
	add_child(list)
	hint = DockKit.wrapping(11, HudStyle.MUTED, 180)
	add_child(hint)
	Events.items_changed.connect(_rebuild)
	Events.item_drag_started.connect(_on_drag_started)
	Events.item_drag_ended.connect(_on_drag_ended)
	set_process(false)
	_rebuild()

# Items owned, counting duplicates (the tab badge).
func count() -> int:
	return GameState.me.items.size()

# [item, how many, index of the first one] per item type, in the order they were picked up.
func groups() -> Array:
	var out: Array = []
	var seen := {}
	for i in GameState.me.items.size():
		var it: ItemData = GameState.me.items[i]
		if seen.has(it):
			out[seen[it]][1] += 1
		else:
			seen[it] = out.size()
			out.append([it, 1, i])
	return out

func _rebuild():
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var g := groups()
	for e in g:
		list.add_child(_row(e[0], e[1], e[2]))
	hint.text = "Drag an item onto a unit to equip it. Up to 3 per unit." if not g.is_empty() else "No items yet. Some fights drop one."

func _row(item: ItemData, n: int, index: int) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_DRAG
	row.add_theme_stylebox_override("panel", DockKit.flat(DockKit.ROW, 3, Vector4(4, 4, 4, 6)))
	row.tooltip_text = Tip.wrap("%s\n%s\nDrag onto a unit to equip it." % [item.display_name, item.description])
	row.set_meta("item", item)
	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			Events.item_drag_started.emit(index))
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	row.add_child(h)
	var slot := DockKit.well(Vector2(SLOT, SLOT), item.color, 3)
	h.add_child(slot)
	var tex := DockKit.item_icon(item)
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.custom_minimum_size = Vector2(ICON, ICON)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(r)
	else:
		var l := HudStyle.number(16, Color.WHITE)
		l.text = item.display_name.substr(0, 2).to_upper()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(l)
	var mid := VBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 0)
	h.add_child(mid)
	var name_l := DockKit.text(12)
	name_l.text = item.display_name
	mid.add_child(name_l)
	var desc := DockKit.wrapping(11, HudStyle.MUTED, 110)
	desc.text = item.description
	mid.add_child(desc)
	if n > 1:
		var x := HudStyle.number(20, HudStyle.INK)
		x.text = "×%d" % n
		x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(x)
	return row

func _process(_delta):
	_ghost.position = get_viewport().get_mouse_position() + Vector2(16, 16)

func _on_drag_started(index: int):
	if index < 0 or index >= GameState.me.items.size():
		return
	var item: ItemData = GameState.me.items[index]
	if _ghost == null:
		_ghost = Label.new()
		_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE   # must not block the drop target under the mouse
		_ghost.add_theme_font_override("font", HudStyle.label_font())
		_ghost.add_theme_font_size_override("font_size", 13)
		_ghost.add_theme_color_override("font_color", HudStyle.INK)
		_ghost.z_index = 10
		_ui_root().add_child(_ghost)
	_ghost.text = item.display_name
	var s := DockKit.flat(DockKit.WELL, 3, Vector4(4, 8, 4, 8))
	s.border_width_left = 3
	s.border_color = item.color
	_ghost.add_theme_stylebox_override("normal", s)
	_ghost.visible = true
	set_process(true)

func _on_drag_ended():
	set_process(false)
	if _ghost != null:
		_ghost.visible = false

# The UI CanvasLayer, so the ghost draws above the boxes and isn't clipped by them.
func _ui_root() -> Node:
	var n: Node = self
	while n != null and not (n is CanvasLayer):
		n = n.get_parent()
	return n if n != null else get_parent()
