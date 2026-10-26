# odds_label.gd
extends HBoxContainer

# Shop odds, right above the shop bar: a small plate with an ODDS fold button and one chip per cost in
# its cost colour ("1 · 55%"; costs you can't roll yet are dimmed). Folded it is just the button; the
# choice is remembered (Settings.show_odds). Follows your level.

var plate: HudPlate
var fold_button: Button
var chips := []   # one Label per cost

func _ready():
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate = HudPlate.new()
	plate.setup_plate(3, 8, 4)
	add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	fold_button = Button.new()
	fold_button.name = "OddsFold"
	fold_button.flat = true
	fold_button.focus_mode = Control.FOCUS_NONE
	fold_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fold_button.add_theme_font_override("font", HudStyle.label_font())
	fold_button.add_theme_font_size_override("font_size", 10)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		fold_button.add_theme_color_override(k, HudStyle.MUTED)
	fold_button.pressed.connect(func(): set_open(not Settings.show_odds))
	row.add_child(fold_button)
	for cost in range(1, 6):
		var l := HudStyle.number(15, DockKit.COST_COLORS[cost])
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		chips.append(l)
	Settings.ensure_loaded()
	Events.xp_changed.connect(func(l, _x, _n): _update(l))
	_update(GameState.me.level)
	set_open(Settings.show_odds)

func set_open(on: bool) -> void:
	if Settings.show_odds != on:
		Settings.show_odds = on
		Settings.save_settings()
	for c in chips:
		c.visible = on
	fold_button.text = "ODDS  ‹" if on else "SHOP ODDS  ›"
	fold_button.tooltip_text = Tip.wrap("The chance of each cost in every shop slot at your level. Click to fold." if on else "Show the shop odds at your level.")

func _update(level: int):
	var odds: Array = GameState.odds_for_level(level)
	for i in chips.size():
		var p: int = odds[i] if i < odds.size() else 0
		var l: Label = chips[i]
		l.text = "%d·%d%%" % [i + 1, p]
		l.modulate.a = 1.0 if p > 0 else 0.35
		l.tooltip_text = Tip.wrap("%d-cost units: %d%% per slot at level %d." % [i + 1, p, level])
		l.mouse_filter = Control.MOUSE_FILTER_PASS

# The odds as one line (tests).
func summary() -> String:
	return " ".join(chips.map(func(l): return l.text))
