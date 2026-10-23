# item_bar.gd
extends VBoxContainer

# The Items tab of the left box (left_dock.gd; DOCKS_SPEC "Items tab"): one row per item type you
# own (icon in a well with an edge in the item's colour, name, description, "x2" for duplicates),
# then a hint. Press a row and drag onto a unit to equip it: the row emits
# Events.item_drag_started(index into GameState.me.items) and drag_controller.gd does the rest, as
# before. The item's icon (and name) follows the mouse while dragging.

const ICON := 34.0
const SLOT := 38.0

var list: VBoxContainer
var hint: Label
var resonance_list: VBoxContainer   # "Knight: Flurry, Bulwark", one line per unit with a resonance
var book_button: Button
var book: PanelContainer           # all 16 resonances (toggle_book)
var _ghost: PanelContainer   # follows the mouse while an item is being dragged: the icon and its name
var _ghost_icon: TextureRect
var _ghost_name: Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	list = VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 4)
	add_child(list)
	hint = DockKit.wrapping(11, HudStyle.MUTED, 180)
	add_child(hint)
	# Resonance (items v2): what is active on your units, and the book with all 16.
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var cap := HudStyle.caps(10, HudStyle.MUTED)
	cap.text = "RESONANCE"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cap)
	book_button = DockKit.secondary_button("Book")
	book_button.custom_minimum_size = Vector2(56, 24)
	book_button.add_theme_font_size_override("font_size", 11)
	book_button.focus_mode = Control.FOCUS_NONE
	book_button.tooltip_text = Tip.wrap("Every resonance: two items with different elements on one unit switch one on. Ones you have used are marked.")
	book_button.pressed.connect(toggle_book)
	head.add_child(book_button)
	resonance_list = VBoxContainer.new()
	resonance_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resonance_list.add_theme_constant_override("separation", 2)
	add_child(resonance_list)
	Events.items_changed.connect(_rebuild)
	Events.phase_changed.connect(func(_p): _rebuild())
	Events.unit_bought.connect(func(_d): _rebuild.call_deferred())
	Events.unit_sold.connect(func(_d, _s, _r): _rebuild.call_deferred())
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
	_fill_resonances()

func _row(item: ItemData, n: int, index: int) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_DRAG
	row.add_theme_stylebox_override("panel", DockKit.flat(DockKit.ROW, 3, Vector4(4, 4, 4, 6)))
	row.tooltip_text = Tip.wrap(item_tip(item))
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
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_theme_constant_override("separation", 5)
	mid.add_child(name_row)
	var name_l := DockKit.text(12)
	name_l.text = item.display_name
	name_row.add_child(name_l)
	if item.element != &"":   # resonance element tag
		var tag := DockKit.chip(String(item.element).to_upper(), DockKit.WELL, Resonance.ELEMENT_COLORS.get(item.element, HudStyle.MUTED), 9)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(tag)
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
		# The item's icon in a small well with its name under it; ignores the mouse so it never
		# blocks the drop target under the pointer.
		_ghost = PanelContainer.new()
		_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ghost.z_index = 10
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 2)
		_ghost.add_child(v)
		_ghost_icon = TextureRect.new()
		_ghost_icon.custom_minimum_size = Vector2(44, 44)
		_ghost_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_ghost_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_ghost_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_ghost_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_ghost_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_ghost_icon)
		_ghost_name = DockKit.text(10, HudStyle.INK)
		_ghost_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(_ghost_name)
		_ui_root().add_child(_ghost)
	_ghost_icon.texture = DockKit.item_icon(item)
	_ghost_name.text = item.display_name
	var s := DockKit.flat(Color(DockKit.WELL, 0.9), 3, Vector4(4, 6, 4, 6))
	s.border_width_bottom = 3
	s.border_color = item.color
	_ghost.add_theme_stylebox_override("panel", s)
	_ghost.reset_size()
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

# An item's tooltip: name, what it does, and (for elements) what it resonates with.
func item_tip(item: ItemData) -> String:
	var lines: PackedStringArray = [item.display_name, item.description]
	if item.element != &"":
		lines.append("%s. With another element on the same unit:" % String(item.element))
		for e in Resonance.ELEMENTS:
			if e != item.element:
				lines.append("+ %s: %s" % [e, Resonance.describe(Resonance.key(item.element, e))])
	lines.append("Drag onto a unit to use it." if item.kind == &"remover" else "Drag onto a unit to equip it.")
	return "\n".join(lines)

# One line per unit of yours with an active resonance ("Knight: Flurry, Bulwark").
func _fill_resonances() -> void:
	if resonance_list == null:
		return
	for c in resonance_list.get_children():
		resonance_list.remove_child(c)
		c.queue_free()
	var board := get_tree().get_first_node_in_group("board") as Board if is_inside_tree() else null
	var any := false
	if board != null:
		for u in board.all_player_units():
			var keys := Resonance.keys_for(u.items)
			if keys.is_empty():
				continue
			any = true
			var names: PackedStringArray = []
			for k in keys:
				names.append(Resonance.def(k).get("name", k))
			var l := DockKit.wrapping(11, HudStyle.INK, 180)
			l.text = "%s%s: %s" % [u.data.display_name, " (bench)" if u.coord.x < 0 else "", ", ".join(names)]
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			var tips: PackedStringArray = []
			for k in keys:
				tips.append(Resonance.describe(k))
			if Resonance.has_crystal(u.items):
				tips.append("Resonance Crystal: twice as strong")
			l.tooltip_text = Tip.wrap("\n".join(tips))
			resonance_list.add_child(l)
	if not any:
		var none := DockKit.wrapping(11, DockKit.DIM_TEXT, 180)
		none.text = "None yet. Two items with different elements on one unit make one."
		resonance_list.add_child(none)
	if book != null and book.visible:
		_fill_book()

func toggle_book() -> void:
	if book == null:
		book = HudPlate.new()
		book.setup_plate(10, 14, 12, DockKit.PANEL_FILL)
		book.set_edge(HudStyle.EDGE_GOLD)
		book.mouse_filter = Control.MOUSE_FILTER_STOP
		book.visible = false
		_ui_root().add_child(book)
	book.visible = not book.visible
	if book.visible:
		_fill_book()
		_center_book.call_deferred()

func _center_book() -> void:
	book.reset_size()
	book.position = ((book.get_viewport_rect().size - book.size) / 2.0).round()

# The resonance book: all 15 pairs and Prism, the elements, the effect, and whether you have used it.
func _fill_book() -> void:
	for c in book.get_children():
		book.remove_child(c)
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	book.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := HudStyle.number(26, HudStyle.GOLD)
	title.text = "Resonance book"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var found := 0
	var keys: Array = Resonance.PAIRS.keys() + ["Prism"]
	for k in keys:
		if SaveGame.has_unlock(StringName("resonance:" + k)):
			found += 1
	var count := HudStyle.number(18, HudStyle.MUTED)
	count.text = "%d / %d found" % [found, keys.size()]
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for k in keys:
		var known := SaveGame.has_unlock(StringName("resonance:" + k))
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", DockKit.flat(DockKit.ROW_ACTIVE if known else DockKit.ROW, 3, Vector4(4, 8, 5, 8)))
		cell.custom_minimum_size = Vector2(330, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		cell.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 5)
		v.add_child(top)
		var n := DockKit.text(12, HudStyle.GOLD if known else HudStyle.INK)
		n.text = ("✓ " if known else "") + str(Resonance.def(k).get("name", k))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(n)
		var elems: Array = ["3 elements"] if k == "Prism" else k.split("+")
		for e in elems:
			top.add_child(DockKit.chip(String(e).to_upper(), DockKit.WELL, Resonance.ELEMENT_COLORS.get(StringName(e), HudStyle.MUTED), 9))
		var d := DockKit.text(11, HudStyle.MUTED)
		d.text = str(Resonance.def(k).get("text", ""))
		v.add_child(d)
		grid.add_child(cell)
	var close := DockKit.secondary_button("Close")
	close.custom_minimum_size = Vector2(140, 34)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): book.visible = false)
	box.add_child(close)
	book.reset_size()
