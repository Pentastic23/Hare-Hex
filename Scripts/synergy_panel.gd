# synergy_panel.gd
extends VBoxContainer

# The Synergies tab of the left box (left_dock.gd; DOCKS_SPEC "Synergies tab"): one row per tag on
# your board, active first, then by count. Each row: the count in a hexagon (gold = every tier
# reached, darker gold = some, slate = none), the name, the tier numbers on the right, and for active
# rows the current effect underneath. Refreshes a few times a second while the run plays.

const ROW_GAP := 4
const MAX_LIST_H := 360.0   # then the list scrolls

var board: Board
var scroll: ScrollContainer
var list: VBoxContainer
var empty_label: Label
var active_count := 0       # active synergies (the tab badge)
var total_count := 0        # tags on the board
var _timer := 0.0
var _last_sig := ""

func _ready():
	board = get_tree().get_first_node_in_group("board") as Board
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	list = VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", ROW_GAP)
	scroll.add_child(list)
	empty_label = DockKit.wrapping(11, HudStyle.MUTED, 180)
	empty_label.text = "Put units on the board to see their synergies."
	add_child(empty_label)
	_refresh()

func _process(delta):
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	_refresh()

func counts() -> Dictionary:
	if board == null:
		return {}
	var units: Array = []
	for u in board.all_player_units():
		if u.coord.x >= 0:
			units.append(u)
	return Synergies.count(units)

func _refresh():
	var c := counts()
	var sig := str(c)
	if sig == _last_sig:
		return
	_last_sig = sig
	for r in list.get_children():
		list.remove_child(r)
		r.queue_free()
	var tags: Array = c.keys().filter(func(t): return Synergies.DEFS.has(t))
	tags.sort_custom(func(a, b):
		var ta := Synergies.active_tier(a, c[a])
		var tb := Synergies.active_tier(b, c[b])
		if (ta >= 0) != (tb >= 0):
			return ta >= 0
		if c[a] != c[b]:
			return c[a] > c[b]
		return a < b)
	active_count = 0
	total_count = tags.size()
	for tag in tags:
		var n: int = c[tag]
		var t := Synergies.active_tier(tag, n)
		if t >= 0:
			active_count += 1
		list.add_child(_row(tag, n, t))
	empty_label.visible = tags.is_empty()
	scroll.visible = not tags.is_empty()
	_fit.call_deferred()

# The scroll area is as tall as its rows, up to MAX_LIST_H.
func _fit():
	if not is_instance_valid(list):
		return
	scroll.custom_minimum_size.y = minf(list.get_combined_minimum_size().y, MAX_LIST_H)

func _row(tag: String, n: int, tier: int) -> Control:
	var thresholds: Array = Synergies.DEFS[tag]["thresholds"]
	var active := tier >= 0
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS   # for the tooltip; clicks pass through
	row.add_theme_stylebox_override("panel", DockKit.flat(DockKit.ROW_ACTIVE if active else Color.TRANSPARENT, 3, Vector4(4, 4, 4, 6)))
	row.tooltip_text = Tip.wrap(Synergies.tooltip(tag, n))
	row.set_meta("tag", tag)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	row.add_child(h)
	var hex := DockKit.HexBadge.new()
	hex.set_count(n, 0 if not active else (2 if tier == thresholds.size() - 1 else 1))
	h.add_child(hex)
	var mid := VBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 1)
	h.add_child(mid)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 3)
	mid.add_child(top)
	var name_l := DockKit.text(12, HudStyle.INK if active else HudStyle.MUTED)
	name_l.text = tag
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_l)
	for th in thresholds:
		var reached: bool = n >= int(th)
		top.add_child(DockKit.chip(str(th), HudStyle.GOLD if reached else DockKit.ROW, DockKit.DARK_TEXT if reached else DockKit.DIM_TEXT, 11))
	if active:
		var eff := DockKit.wrapping(11, HudStyle.MUTED, 140)
		eff.text = DockKit.effect_text(tag, tier)
		mid.add_child(eff)
	return row

# For checks: the tag names in display order.
func shown_tags() -> Array:
	return list.get_children().filter(func(r): return not r.is_queued_for_deletion()).map(func(r): return r.get_meta("tag"))
