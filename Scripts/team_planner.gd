# team_planner.gd
extends PanelContainer

# Team planner (Plan button or P): pick the units you're aiming for. Planned units are
# highlighted in the shop (shop_slot.gd), the panel previews the planned team's synergies, and
# units you already own are marked. The plan is saved (SaveGame.team_plan) by unit name.

const GOLD := Color(1.0, 0.85, 0.3)
const GREY := Color(0.65, 0.65, 0.7)

var grid: GridContainer
var synergy_label: Label
var summary_label: Label
var _style_on: StyleBoxFlat
var _style_off: StyleBoxFlat

func _ready():
	add_to_group("team_planner")
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_style_on = _style(Color(0.25, 0.22, 0.1), GOLD)
	_style_off = _style(Color(0.15, 0.16, 0.2), Color(0.3, 0.3, 0.35))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Team planner"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Pick the units you're aiming for. They get a star in the shop."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", GREY)
	box.add_child(hint)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	summary_label = Label.new()
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(summary_label)
	synergy_label = Label.new()
	synergy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	synergy_label.custom_minimum_size = Vector2(560, 0)
	box.add_child(synergy_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var clear := Button.new()
	clear.text = "Clear plan"
	clear.custom_minimum_size = Vector2(140, 40)
	clear.pressed.connect(func(): _set_plan([]))
	buttons.add_child(clear)
	var close_button := Button.new()
	close_button.text = "Close (P)"
	close_button.custom_minimum_size = Vector2(140, 40)
	close_button.pressed.connect(close)
	buttons.add_child(close_button)
	# keep the "owned" counts current while the panel is open
	for s in [Events.unit_bought, Events.unit_sold, Events.phase_changed]:
		s.connect(func(_a = null, _b = null, _c = null):
			if visible:
				_rebuild.call_deferred())

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P and not get_tree().paused:
		toggle()
		get_viewport().set_input_as_handled()

func toggle():
	if visible:
		close()
	else:
		open()

func open():
	_rebuild()
	visible = true

func close():
	visible = false

# The units the shop can offer this run (a campaign level may limit them), cheapest first.
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

func _toggle_unit(unit_name: String):
	var plan: Array = SaveGame.team_plan().duplicate()
	if plan.has(unit_name):
		plan.erase(unit_name)
	else:
		plan.append(unit_name)
	_set_plan(plan)

func _rebuild():
	for c in grid.get_children():
		c.queue_free()
	var plan: Array = SaveGame.team_plan()
	var owned := _owned_counts()
	var planned_data := []
	for d in _roster():
		var on := plan.has(d.display_name)
		if on:
			planned_data.append(d)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(118, 64)
		var tags: PackedStringArray = []
		for t in d.tags:
			tags.append(String(t))
		var have := int(owned.get(d.display_name, 0))
		b.text = "%s%s\n%dg  %s" % ["* " if on else "", d.display_name, d.cost, ("owned x%d" % have) if have > 0 else ""]
		b.tooltip_text = "%s (%d gold)\n%s\nClick to %s the plan." % [d.display_name, d.cost, ", ".join(tags), "remove from" if on else "add to"]
		b.add_theme_font_size_override("font_size", 14)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, _style_on if on else _style_off)
		b.add_theme_color_override("font_color", GOLD if on else Color.WHITE)
		b.pressed.connect(_toggle_unit.bind(d.display_name))
		grid.add_child(b)
	var have_count := planned_data.filter(func(d): return owned.has(d.display_name)).size()
	summary_label.text = "Planned: %d units (%d owned)" % [planned_data.size(), have_count] if not planned_data.is_empty() else "No units planned yet."
	synergy_label.text = _synergy_text(planned_data)

func _synergy_text(datas: Array) -> String:
	if datas.is_empty():
		return ""
	var counts := Synergies.count_data(datas)
	var tags: Array = counts.keys().filter(func(t): return Synergies.DEFS.has(t))
	tags.sort_custom(func(a, b): return counts[a] > counts[b] or (counts[a] == counts[b] and a < b))
	var parts: PackedStringArray = []
	for t in tags:
		var n: int = counts[t]
		parts.append("%s %d/%d%s" % [t, n, Synergies.next_threshold(t, n), " (active)" if Synergies.active_tier(t, n) >= 0 else ""])
	return "Planned synergies: " + ",  ".join(parts)

func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	return s
