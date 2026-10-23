# team_planner.gd
extends VBoxContainer

# The Planner panel of the right box (right_dock.gd; DOCKS_SPEC "Planner panel"; P toggles it):
# pick the units you're aiming for. Cost tabs 1-5 above a 5-column grid of that cost's units
# (portrait, a cost-colour strip, "x2" when owned, a gold outline and check when planned), the
# count planned at that cost, and the planned team's synergies as chips. Planned units are
# highlighted in the shop (shop_slot.gd). The plan is saved (SaveGame.team_plan) by unit name.

const COLUMNS := 5
const GAP := 4
const INNER_WIDTH := 216.0   # the right box (236) minus its 10 px padding each side

var cost := 1                 # the cost tab shown
var cost_tabs: Array[Button] = []
var grid: GridContainer
var summary_label: Label
var planned_label: Label      # "9 units planned"
var chips: HFlowContainer     # planned synergies
var _tile_side := 40.0

func _ready():
	add_to_group("team_planner")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 3)
	add_child(tabs)
	for c in range(1, 6):
		var content := HBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 4)
		var sw := ColorRect.new()
		sw.color = DockKit.COST_COLORS[c]
		sw.custom_minimum_size = Vector2(7, 7)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(sw)
		content.add_child(DockKit.tab_label(str(c), 12))
		var b := DockKit.tab(content, 26)
		b.tooltip_text = Tip.wrap("%d-gold units" % c)
		b.pressed.connect(show_cost.bind(c))
		tabs.add_child(b)
		cost_tabs.append(b)
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	add_child(grid)
	summary_label = DockKit.text(12)
	add_child(summary_label)
	var div := ColorRect.new()
	div.color = DockKit.LINE
	div.custom_minimum_size = Vector2(0, 1)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(div)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var caps := HudStyle.caps(10, HudStyle.MUTED)
	caps.text = "PLANNED SYNERGIES"
	caps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caps)
	planned_label = DockKit.text(10, HudStyle.MUTED)
	head.add_child(planned_label)
	chips = HFlowContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	add_child(chips)
	# keep the "owned" counts current while the panel is open
	for s in [Events.unit_bought, Events.unit_sold, Events.phase_changed]:
		s.connect(func(_a = null, _b = null, _c = null):
			if is_visible_in_tree():
				_rebuild.call_deferred())

func _dock():
	return get_tree().get_first_node_in_group("right_dock")

# Kept for other scripts and checks: the right box decides what is open.
func open():
	var d = _dock()
	if d != null:
		d.open_panel("planner")

func close():
	var d = _dock()
	if d != null and d.current == "planner":
		d.close_panel()

func toggle():
	var d = _dock()
	if d != null:
		d.toggle_panel("planner")

func is_open() -> bool:
	var d = _dock()
	return d != null and d.current == "planner"

func show_cost(c: int) -> void:
	cost = c
	_rebuild()

# The units the shop can offer this run (a campaign level may limit them).
func _roster() -> Array:
	var gm := get_tree().get_first_node_in_group("game_manager")
	var list: Array = gm.roster.duplicate() if gm != null else []
	list.sort_custom(func(a, b): return a.cost < b.cost or (a.cost == b.cost and a.display_name < b.display_name))
	return list

func _owned_counts() -> Dictionary:
	var counts := {}
	var board := get_tree().get_first_node_in_group("board") as Board
	if board != null:
		for u in board.all_player_units():
			counts[u.data.display_name] = int(counts.get(u.data.display_name, 0)) + 1
	return counts

func _set_plan(names: Array):
	SaveGame.set_team_plan(names)
	Events.team_plan_changed.emit()
	_rebuild()

func toggle_unit(unit_name: String):
	var plan: Array = SaveGame.team_plan().duplicate()
	if plan.has(unit_name):
		plan.erase(unit_name)
	else:
		plan.append(unit_name)
	_set_plan(plan)

func clear_plan():
	_set_plan([])

func _rebuild():
	for i in cost_tabs.size():
		var on := i + 1 == cost
		DockKit.set_tab_active(cost_tabs[i], on, DockKit.SELECTED)
		var s := DockKit.flat(DockKit.SELECTED if on else DockKit.WELL)
		if on:
			s.border_width_top = 2
			s.border_color = DockKit.COST_COLORS[i + 1]
		cost_tabs[i].add_theme_stylebox_override("normal", s)
		cost_tabs[i].add_theme_stylebox_override("hover", s if on else DockKit.flat(DockKit.WELL.lightened(0.06)))
		cost_tabs[i].add_theme_stylebox_override("pressed", s)
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var plan: Array = SaveGame.team_plan()
	var owned := _owned_counts()
	var roster := _roster()
	_tile_side = floorf((INNER_WIDTH - GAP * (COLUMNS - 1)) / COLUMNS)
	var at_cost := roster.filter(func(d): return d.cost == cost)
	var planned_here := 0
	for d in at_cost:
		var on: bool = plan.has(d.display_name)
		if on:
			planned_here += 1
		grid.add_child(_tile(d, on, int(owned.get(d.display_name, 0))))
	summary_label.text = "%d of %d planned at %d gold" % [planned_here, at_cost.size(), cost]
	var planned_data := roster.filter(func(d): return plan.has(d.display_name))
	planned_label.text = "%d unit%s planned" % [planned_data.size(), "" if planned_data.size() == 1 else "s"]
	for c in chips.get_children():
		chips.remove_child(c)
		c.queue_free()
	for e in chip_entries(planned_data):
		var active: bool = e[2]
		chips.add_child(DockKit.chip(e[0] + " " + e[1], DockKit.CHIP_ACTIVE if active else DockKit.WELL, HudStyle.GOLD if active else HudStyle.MUTED, 11, DockKit.GOLD_EDGE if active else Color.TRANSPARENT))
	if planned_data.is_empty():
		var l := DockKit.wrapping(11, HudStyle.MUTED, 180)
		l.text = "Click units to plan a team. Planned units get a star in the shop."
		chips.add_child(l)

# [tag, "count/threshold", active] for the planned team, most units first. The threshold is the next
# one not reached yet, or the top tier once it's maxed (as before).
func chip_entries(datas: Array) -> Array:
	var counts := Synergies.count_data(datas)
	var tags: Array = counts.keys().filter(func(t): return Synergies.DEFS.has(t))
	tags.sort_custom(func(a, b):
		var aa := Synergies.active_tier(a, counts[a]) >= 0
		var ab := Synergies.active_tier(b, counts[b]) >= 0
		if aa != ab:
			return aa
		return counts[a] > counts[b] or (counts[a] == counts[b] and a < b))
	var out: Array = []
	for t in tags:
		var n: int = counts[t]
		out.append([t, "%d/%d" % [n, Synergies.next_threshold(t, n)], Synergies.active_tier(t, n) >= 0])
	return out

func _tile(d: UnitData, planned: bool, have: int) -> Button:
	var side := _tile_side
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(side, side)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_meta("unit", d.display_name)
	var tags: PackedStringArray = []
	for t in d.tags:
		tags.append(String(t))
	b.tooltip_text = Tip.wrap("%s (%d gold)\n%s\nClick to %s the plan." % [d.display_name, d.cost, ", ".join(tags), "remove from" if planned else "add to"])
	var s := DockKit.flat(DockKit.WELL)
	s.set_border_width_all(2 if planned else 1)
	s.border_color = HudStyle.GOLD if planned else DockKit.LINE
	var h := s.duplicate() as StyleBoxFlat
	h.bg_color = DockKit.WELL.lightened(0.06)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.pressed.connect(toggle_unit.bind(d.display_name))
	var tex := DockKit.portrait(d)
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.position = Vector2(2, 2)
		r.size = Vector2(side - 4, side - 7)
		b.add_child(r)
	else:
		var l := HudStyle.number(18, HudStyle.MUTED)
		l.text = d.label()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = Vector2.ZERO
		l.size = Vector2(side, side - 3)
		b.add_child(l)
	var strip := ColorRect.new()
	strip.color = DockKit.COST_COLORS.get(d.cost, HudStyle.NEUTRAL)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = Vector2(1, side - 4)
	strip.size = Vector2(side - 2, 3)
	b.add_child(strip)
	if planned:
		var check := ColorRect.new()
		check.color = HudStyle.GOLD
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		check.position = Vector2(side - 12, 2)
		check.size = Vector2(10, 10)
		b.add_child(check)
		var tick := DockKit.PixelIcon.new("check", DockKit.DARK_TEXT, 10)
		tick.position = check.position
		tick.size = check.size
		b.add_child(tick)
	if have > 0:
		var x := HudStyle.number(14, HudStyle.INK)
		x.text = "×%d" % have
		x.add_theme_color_override("font_outline_color", DockKit.WELL)
		x.add_theme_constant_override("outline_size", 4)
		x.position = Vector2(3, 0)
		b.add_child(x)
	return b

# For checks: the tile for a unit name in the current cost tab, or null.
func tile_for(unit_name: String) -> Button:
	for c in grid.get_children():
		if not c.is_queued_for_deletion() and c.get_meta("unit", "") == unit_name:
			return c
	return null
