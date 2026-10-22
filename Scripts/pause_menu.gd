# pause_menu.gd
extends Control

# Esc during a run: pauses the game (prep timer, combat, dragging) and offers Resume, Main menu
# and Quit. Not available once the run has ended (the end screen has its own buttons).

var panel_style: StyleBox = preload("res://tres/panel_style.tres")

func _ready():
	add_to_group("pause_menu")   # the top-right Menu button opens it
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the tree is paused
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(title)
	_button(box, "Resume", close)
	var to_menu := _button(box, "Main menu", func(): GameState.go_to_menu())
	to_menu.tooltip_text = "Campaign: your run continues from the start of this level."
	if OS.get_name() != "Web":
		_button(box, "Quit game", func(): get_tree().quit())

func _input(event):
	if not event.is_action_pressed("ui_cancel"):
		return
	var planner := get_tree().get_first_node_in_group("team_planner")
	if visible:
		close()
	elif planner != null and planner.visible:
		planner.close()   # Esc closes the team planner before it opens the pause menu
	elif _can_pause():
		open()
	else:
		return
	get_viewport().set_input_as_handled()

func _can_pause() -> bool:
	var gm := get_tree().get_first_node_in_group("game_manager")
	return gm != null and not gm.game_over

func open():
	visible = true
	get_tree().paused = true

func close():
	visible = false
	get_tree().paused = false

func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
