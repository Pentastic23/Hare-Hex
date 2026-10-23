# pause_menu.gd
extends VBoxContainer

# The Menu panel of the right box (right_dock.gd; DOCKS_SPEC "Menu panel"; Esc opens it): "Paused",
# Resume, Main menu, Quit game. While it is open the game is paused (prep timer, combat, dragging) and
# the screen behind the HUD is dimmed; the right box does both. Not available once the run has ended
# (the end screen has its own buttons).

var resume_button: Button
var menu_button: Button
var quit_button: Button
var pad_help: Control       # controller buttons, while a pad is connected

func _ready():
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the tree is paused
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var title := HudStyle.number(30, HudStyle.INK)
	title.text = "Paused"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := DockKit.text(11, HudStyle.MUTED)
	hint.text = "Esc to resume"
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint)
	resume_button = DockKit.primary_button("Resume")
	resume_button.pressed.connect(close)
	add_child(resume_button)
	menu_button = DockKit.secondary_button("Main menu")
	menu_button.pressed.connect(func(): GameState.go_to_menu())
	add_child(menu_button)
	var note := DockKit.wrapping(11, HudStyle.MUTED, 180)
	note.text = "In a campaign, your run continues from the start of this level."
	add_child(note)
	quit_button = DockKit.secondary_button("Quit game")
	quit_button.pressed.connect(func(): get_tree().quit())
	quit_button.visible = OS.get_name() != "Web"
	add_child(quit_button)
	pad_help = _pad_help()
	add_child(pad_help)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			var old := pad_help
			pad_help = _pad_help()   # rebuilt each time: binds can change in the main menu
			add_child(pad_help)
			old.queue_free()
			pad_help.visible = not Input.get_connected_joypads().is_empty())

# Controller buttons (gamepad_controls.gd), shown while a pad is connected.
func _pad_help() -> Control:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	var div := ColorRect.new()
	div.color = DockKit.LINE
	div.custom_minimum_size = Vector2(0, 1)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(div)
	var cap := HudStyle.caps(10, HudStyle.MUTED)
	cap.text = "CONTROLLER"
	v.add_child(cap)
	var g := GridContainer.new()
	g.columns = 2
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 1)
	v.add_child(g)
	for pair in Keybinds.pad_help():   # follows the main menu's Keybinds
		var k := DockKit.text(10, HudStyle.GOLD)
		k.text = pair[0]
		g.add_child(k)
		var t := DockKit.text(10, HudStyle.MUTED)
		t.text = pair[1]
		g.add_child(t)
	v.visible = false
	return v

func _dock():
	return get_tree().get_first_node_in_group("right_dock")

func _can_pause() -> bool:
	var gm := get_tree().get_first_node_in_group("game_manager")
	return gm != null and not gm.game_over

# Kept for other scripts and checks: the right box opens the panel and pauses.
func open():
	var d = _dock()
	if d != null:
		d.open_panel("menu")

func close():
	var d = _dock()
	if d != null and d.current == "menu":
		d.close_panel()

func is_open() -> bool:
	var d = _dock()
	return d != null and d.current == "menu"
