# damage_meter.gd
extends PanelContainer

# Window under the top-right button bar (Damage button): damage each of your units dealt (or took)
# in the current fight, live during combat and kept as "last fight" until the next one starts.
# Click the header to switch view. Open/closed is remembered in Settings.show_damage_meter.

const BAR_W := 120.0
const ROW_H := 18.0
const DEALT_COLOR := Color(0.95, 0.55, 0.25)
const TAKEN_COLOR := Color(0.45, 0.65, 1.0)

var show_taken := false
var enabled := true
var header: Button
var rows: VBoxContainer
var _timer := 0.0
var _in_combat := false

func _ready():
	add_to_group("damage_meter")
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # only the header takes clicks; the rest sits over the board
	Settings.ensure_loaded()
	enabled = Settings.show_damage_meter
	visible = enabled
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	header = Button.new()
	header.flat = true
	header.focus_mode = Control.FOCUS_NONE
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	header.tooltip_text = Tip.wrap("Click to switch between damage dealt and damage taken.")
	header.pressed.connect(func():
		show_taken = not show_taken
		_refresh())
	box.add_child(header)
	rows = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 3)
	box.add_child(rows)
	Events.phase_changed.connect(func(p):
		_in_combat = p == Events.Phase.COMBAT
		_refresh.call_deferred())   # deferred: combat units are set up right after the phase signal
	_refresh()

# The Damage button. Remembered between sessions.
func set_enabled(on: bool):
	enabled = on
	visible = on
	Settings.show_damage_meter = on
	Settings.save_settings()
	_refresh()

func _process(delta):
	if not visible or not _in_combat:
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
	if header == null:
		return
	var title := "Damage taken" if show_taken else "Damage dealt"
	header.text = "%s%s  (switch)" % [title, "" if _in_combat else ", last fight"]
	for c in rows.get_children():
		c.queue_free()
	var list := _units()
	list.sort_custom(func(a, b): return _value(a) > _value(b))
	var top := 1.0
	for u in list:
		top = maxf(top, _value(u))
	for u in list:
		rows.add_child(_row(u, _value(u), top))
	if list.is_empty():
		var l := Label.new()
		l.text = "No fights yet." if _no_fights_yet() else "No units fought."
		l.add_theme_font_size_override("font_size", 14)
		rows.add_child(l)

func _no_fights_yet() -> bool:
	var gm := get_tree().get_first_node_in_group("game_manager")
	return gm == null or (gm.phase == Events.Phase.PREP and GameState.round_number == 1)

func _value(u: Unit) -> float:
	return u.damage_taken if show_taken else u.damage_dealt

func _row(u: Unit, value: float, top: float) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "%s %s" % [u.data.display_name, "*".repeat(u.star)]
	label.custom_minimum_size = Vector2(96, ROW_H)
	label.add_theme_font_size_override("font_size", 14)
	if u.dead and _in_combat:
		label.modulate = Color(0.6, 0.6, 0.6)   # fallen this fight
	row.add_child(label)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.4)
	bar_bg.custom_minimum_size = Vector2(BAR_W, ROW_H - 4)
	bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.color = TAKEN_COLOR if show_taken else DEALT_COLOR
	bar.size = Vector2(BAR_W * value / top, ROW_H - 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar)
	row.add_child(bar_bg)
	var num := Label.new()
	num.text = str(roundi(value))
	num.custom_minimum_size = Vector2(44, ROW_H)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.add_theme_font_size_override("font_size", 14)
	row.add_child(num)
	return row
