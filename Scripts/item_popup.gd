# item_popup.gd
class_name ItemPopup extends Control

# New items in the middle of the screen (Events.items_received: drops, a king's reward, the tutorial's
# hand-outs). Each item is a card (its icon in a well edged in the item's colour, its name under it); a
# few at once stand side by side. The cards pop in one after another with a white flash, pulse and bob for
# a few seconds, then fly off to the left box (where the Items tab lists them) and fade. More items while
# one batch shows wait their turn. Reduce motion: they fade in, hold and fade out in place. Visual only.
# GameManager adds it to the UI.

const CARD := 76.0          # the well's side
const SLOT := 150.0         # from one card to the next: room for its name (NAME_W) and a gap
const NAME_W := 136.0       # a name wraps to two lines past this
const HOLD := 2.4           # seconds the cards stay up, pulsing
const STAGGER := 0.12       # between one card popping in and the next
const ROW_Y := 0.42         # the cards' centre, as a share of the screen height

var shown := 0              # batches shown (tests)
var _queue: Array = []      # batches waiting: Array[ItemData] each
var _busy := false
var _cards: Array[Control] = []
var _header: Label

func _ready() -> void:
	name = "ItemPopup"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 32   # over the other panels and the tutorial's dim (it never takes the mouse)
	process_mode = Node.PROCESS_MODE_ALWAYS   # it plays on while a tutorial card pauses the game
	_header =HudStyle.number(30, HudStyle.GOLD)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_color_override("font_shadow_color", HudStyle.LIP)
	_header.add_theme_constant_override("shadow_offset_y", 3)
	_header.add_theme_constant_override("shadow_offset_x", 0)
	_header.visible = false
	add_child(_header)
	Events.items_received.connect(show_items)

func show_items(items: Array) -> void:
	var list := items.filter(func(i): return i is ItemData)
	if list.is_empty():
		return
	_queue.append(list)
	if not _busy:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	shown += 1
	var list: Array = _queue.pop_front()
	_clear()
	Sfx.play(&"unlock")
	var view := get_viewport_rect().size
	var n := list.size()
	var cy := view.y * ROW_Y
	var width := n * SLOT - (SLOT - CARD)   # cards SLOT apart, so their names never meet
	_header.text = "NEW ITEM" if n == 1 else "NEW ITEMS"
	_header.size = Vector2(view.x, 0)
	_header.position = Vector2(0, cy - CARD * 0.5 - 52)
	_header.visible = true
	_header.modulate.a = 0.0
	var ht := _header.create_tween()
	ht.tween_property(_header, "modulate:a", 1.0, 0.2)
	ht.tween_interval(HOLD + STAGGER * n)
	ht.tween_property(_header, "modulate:a", 0.0, 0.3)
	var end := HOLD + STAGGER * n + 0.9   # the last card has flown off by then
	for i in n:
		var card := _card(list[i])
		card.position = Vector2(view.x * 0.5 - width * 0.5 + i * SLOT, cy - CARD * 0.5)
		add_child(card)
		_cards.append(card)
		_animate(card, i * STAGGER, HOLD + (n - 1 - i) * STAGGER)
	var t := create_tween()
	t.tween_interval(end)
	t.tween_callback(_next)

func _clear() -> void:
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()

# One item: its icon in a well edged in its colour (a square of its colour with no icon yet), a white
# flash over it, and its name under it.
func _card(item: ItemData) -> Control:
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size = Vector2(CARD, CARD)
	card.pivot_offset = card.size * 0.5
	var well := DockKit.well(Vector2(CARD, CARD), item.color, 3)
	well.size = card.size
	card.add_child(well)
	var tex := DockKit.item_icon(item)
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(8, 8)
	icon.size = Vector2(CARD - 16, CARD - 16)
	if tex == null:
		var sq := ColorRect.new()
		sq.color = item.color
		sq.position = Vector2(CARD * 0.25, CARD * 0.25)
		sq.size = Vector2(CARD * 0.5, CARD * 0.5)
		sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(sq)
	card.add_child(icon)
	var flash := ColorRect.new()
	flash.name = "Flash"
	flash.color = Color(1, 1, 1, 0.0)
	flash.size = card.size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(flash)
	var label := HudStyle.caps(11, HudStyle.INK)
	label.text = item.display_name.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(NAME_W, 0)
	label.size = Vector2(NAME_W, 0)
	label.position = Vector2(-(NAME_W - CARD) * 0.5, CARD + 6)
	label.add_theme_color_override("font_shadow_color", HudStyle.LIP)
	label.add_theme_constant_override("shadow_offset_y", 2)
	card.add_child(label)
	return card

# Pops in after `delay`, flashes, pulses and bobs for `hold`, then flies to the left box and fades.
func _animate(card: Control, delay: float, hold: float) -> void:
	var flash := card.get_node("Flash") as ColorRect
	card.modulate.a = 0.0
	var t := card.create_tween()
	t.tween_interval(delay)
	if Settings.reduce_motion:
		t.tween_property(card, "modulate:a", 1.0, 0.2)
		t.tween_interval(hold)
		t.tween_property(card, "modulate:a", 0.0, 0.3)
		t.tween_callback(card.queue_free)
		return
	card.scale = Vector2(0.1, 0.1)
	card.rotation = -0.5
	t.tween_property(card, "modulate:a", 1.0, 0.08)
	t.parallel().tween_property(card, "scale", Vector2(1.25, 1.25), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(card, "rotation", 0.08, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(flash, "color:a", 0.85, 0.08)
	t.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(card, "rotation", 0.0, 0.18)
	t.parallel().tween_property(flash, "color:a", 0.0, 0.3)
	# Flashing while it waits: brighter and back, a little bob, about every half second.
	var beats := maxi(int(hold / 0.5), 1)
	var y0 := card.position.y
	for b in beats:
		t.tween_property(card, "modulate", Color(1.6, 1.5, 1.2, 1.0), 0.25).set_trans(Tween.TRANS_SINE)
		t.parallel().tween_property(card, "position:y", y0 - 5.0, 0.25).set_trans(Tween.TRANS_SINE)
		t.parallel().tween_property(flash, "color:a", 0.25, 0.25)
		t.tween_property(card, "modulate", Color.WHITE, 0.25).set_trans(Tween.TRANS_SINE)
		t.parallel().tween_property(card, "position:y", y0, 0.25).set_trans(Tween.TRANS_SINE)
		t.parallel().tween_property(flash, "color:a", 0.0, 0.25)
	t.tween_property(card, "position", _dock_spot(), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(card, "scale", Vector2(0.3, 0.3), 0.45).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(card, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
	t.tween_callback(card.queue_free)

# Where the cards fly to: the left box's tab bar (its Items tab), else the top left corner.
func _dock_spot() -> Vector2:
	var dock := get_tree().get_first_node_in_group("left_dock") as Control
	if dock == null:
		var p := get_parent()
		dock = p.get_node_or_null("LeftDock") as Control if p != null else null
	if dock != null and dock.is_visible_in_tree():
		return dock.global_position + Vector2(40, 10) - global_position
	return Vector2(24, 24)
