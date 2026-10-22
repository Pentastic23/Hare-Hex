# hud_buttons.gd
extends HBoxContainer

# Top-right button bar during a run: Damage (toggles the damage meter window under the bar),
# Planner (toggles the team planner, also P) and Menu (opens the pause menu, also Esc).
# Toggle buttons light up gold while their window is open.

const GOLD := Color(1.0, 0.85, 0.3)

var damage_button: Button
var planner_button: Button
var menu_button: Button

func _ready():
	add_theme_constant_override("separation", 6)
	damage_button = _button("Damage", "Show or hide the damage meter.")
	damage_button.toggle_mode = true
	damage_button.toggled.connect(func(on):
		var meter = _meter()
		if meter != null:
			meter.set_enabled(on))
	planner_button = _button("Planner", "Team planner (P): pick the units you're aiming for.")
	planner_button.toggle_mode = true
	planner_button.toggled.connect(func(on):
		var planner := get_tree().get_first_node_in_group("team_planner")
		if planner != null:
			if on:
				planner.open()
			else:
				planner.close())
	menu_button = _button("Menu", "Pause menu (Esc).")
	menu_button.pressed.connect(func():
		var pause := get_tree().get_first_node_in_group("pause_menu")
		if pause != null and pause._can_pause():
			pause.open())
	# Keep the toggles in step when the windows open or close some other way (P, Esc, Close).
	_sync.call_deferred()

func _process(_delta):
	_sync()

func _sync():
	var meter = _meter()
	if meter != null:
		damage_button.set_pressed_no_signal(meter.enabled)
	var planner := get_tree().get_first_node_in_group("team_planner")
	if planner != null:
		planner_button.set_pressed_no_signal(planner.visible)
	for b in [damage_button, planner_button]:
		b.modulate = GOLD if b.button_pressed else Color.WHITE

func _meter():
	return get_tree().get_first_node_in_group("damage_meter")

func _button(label: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = Tip.wrap(tip)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(84, 34)
	b.add_theme_font_size_override("font_size", 15)
	add_child(b)
	return b
