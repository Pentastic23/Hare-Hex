# damage_meter.gd
extends VBoxContainer

# The Damage panel of the right box (right_dock.gd; DOCKS_SPEC "Damage panel"): damage each of your
# units dealt (or took) in the current fight, live during combat and kept as "last fight" until the
# next one starts. A Dealt | Taken switch picks the view. Rows: portrait, name, value, and a bar
# scaled to the top value (gold for dealt, sky blue for taken). Open/closed is remembered in
# Settings.show_damage_meter (the right box handles that).

const TAKEN_COLOR := HudStyle.YOU   # sky blue #6cc4ff
const DEALT_COLOR := HudStyle.GOLD

var show_taken := false
var caption: Label
var total_label: Label
var dealt_button: Button
var taken_button: Button
var rows: VBoxContainer
var _timer := 0.0
var _in_combat := false

func _ready():
	add_to_group("damage_meter")
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # only the switch takes clicks; the rest sits over the board
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	caption = HudStyle.caps(10, HudStyle.MUTED)
	(caption.get_theme_font("font") as FontVariation).spacing_glyph = 1   # tighter than the HUD caps: it shares the line with the total
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption.clip_text = true
	head.add_child(caption)
	total_label = HudStyle.number(16, HudStyle.MUTED)
	head.add_child(total_label)

	var seg := PanelContainer.new()
	seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seg.add_theme_stylebox_override("panel", DockKit.flat(DockKit.WELL, 3, Vector4(2, 2, 2, 2)))
	add_child(seg)
	var seg_row := HBoxContainer.new()
	seg_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seg_row.add_theme_constant_override("separation", 2)
	seg.add_child(seg_row)
	dealt_button = _seg_button("Dealt", "Damage your units dealt.")
	dealt_button.pressed.connect(set_view.bind(false))
	seg_row.add_child(dealt_button)
	taken_button = _seg_button("Taken", "Damage your units took.")
	taken_button.pressed.connect(set_view.bind(true))
	seg_row.add_child(taken_button)

	rows = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 6)
	add_child(rows)
	Events.phase_changed.connect(func(p):
		_in_combat = p == Events.Phase.COMBAT
		_refresh.call_deferred())   # deferred: combat units are set up right after the phase signal
	_refresh()

func set_view(taken: bool) -> void:
	show_taken = taken
	_refresh()

func _process(delta):
	if not is_visible_in_tree() or not _in_combat:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	_refresh()

# Your units in the current (or last) fight: GameManager's snapshot of the board at combat start.
func _units() -> Array:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return []
	return gm.snapshot.keys().filter(func(u): return is_instance_valid(u) and not u.is_queued_for_deletion())

func _refresh():
	if rows == null:
		return
	caption.text = "%s · DAMAGE %s" % ["THIS FIGHT" if _in_combat else "LAST FIGHT", "TAKEN" if show_taken else "DEALT"]
	_style_seg(dealt_button, not show_taken, DEALT_COLOR)
	_style_seg(taken_button, show_taken, TAKEN_COLOR)
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var list := _units()
	list.sort_custom(func(a, b): return _value(a) > _value(b))
	var top := 1.0
	var total := 0.0
	for u in list:
		top = maxf(top, _value(u))
		total += _value(u)
	total_label.text = str(roundi(total))
	for u in list:
		rows.add_child(_row(u, _value(u), top))
	if list.is_empty():
		var l := DockKit.wrapping(11, HudStyle.MUTED, 180)
		l.text = "No fights yet." if _no_fights_yet() else "No units fought."
		rows.add_child(l)

func _no_fights_yet() -> bool:
	var gm := get_tree().get_first_node_in_group("game_manager")
	return gm == null or (gm.phase == Events.Phase.PREP and GameState.round_number == 1)

func _value(u: Unit) -> float:
	return u.damage_taken if show_taken else u.damage_dealt

func _row(u: Unit, value: float, top: float) -> Control:
	var fallen: bool = u.dead and _in_combat
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	row.set_meta("unit", u)
	var pw := DockKit.portrait_well(u.data, 28, 13)
	if fallen:
		pw.modulate = Color(1, 1, 1, 0.45)   # fallen this fight
	row.add_child(pw)
	var mid := VBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 1)
	row.add_child(mid)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(line)
	var name_l := DockKit.text(12, HudStyle.MUTED if fallen else HudStyle.INK)
	name_l.text = "%s %s" % [u.data.display_name, "★".repeat(u.star)]
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	line.add_child(name_l)
	var num := HudStyle.number(18, HudStyle.MUTED if fallen else HudStyle.INK)
	num.text = str(roundi(value))
	line.add_child(num)
	var bar := DockKit.Bar.new(6)
	bar.set_value(value / top, TAKEN_COLOR if show_taken else DEALT_COLOR)
	mid.add_child(bar)
	return row

func _seg_button(label: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = Tip.wrap(tip)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 24)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

func _style_seg(b: Button, on: bool, line: Color) -> void:
	var s := DockKit.flat(DockKit.SELECTED if on else Color.TRANSPARENT, 2)
	if on:
		s.border_width_top = 2
		s.border_color = line
	var h := s.duplicate() as StyleBoxFlat
	if not on:
		h.bg_color = Color(1, 1, 1, 0.04)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_stylebox_override("hover_pressed", s)
	b.add_theme_stylebox_override("focus", DockKit.empty_box())
	b.add_theme_font_override("font", HudStyle.label_font())
	b.add_theme_font_size_override("font_size", 12)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, HudStyle.INK if on else HudStyle.MUTED)
