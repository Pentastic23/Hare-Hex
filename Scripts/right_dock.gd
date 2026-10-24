# right_dock.gd
class_name RightDock extends VBoxContainer

# The right box (menagerie/hud/DOCKS_SPEC.md, "Right box"), top right: a tab bar [Damage] [Planner P]
# [Menu Esc] and one panel under it, one open at a time. Clicking a tab opens its panel, clicking the
# open tab closes it, opening one closes the others. P toggles the planner; Esc closes an open planner
# first, then opens the menu, and closes the menu again. The menu pauses the game and dims the screen
# behind the HUD. The damage panel is the resting one: it is remembered in Settings.show_damage_meter
# and comes back when the planner or the menu closes.
# Placement: top right (where the old button bar was); its panels draw over the HP standings, as the
# old damage meter did. Replaces TopRightBar, DamageMeter, TeamPlanner and PauseMenu; the panel
# contents are damage_meter.gd, team_planner.gd and pause_menu.gd.

const WIDTH := 236.0
const MARGIN := 10.0
const DIM := Color(0.039, 0.043, 0.067, 0.5)   # #0a0b11 at 50%
const STANDINGS_TOP := 129.0   # where the HP standings sit when no panel is open (hp_standings.gd TOP)
const STANDINGS_GAP := 8.0
const STANDINGS_MAX_TOP := 300.0   # never pushed further down: the bench, the sell zone and the inspector are below
const TUTORIAL_MAX_BOTTOM := 436.0   # the tutorial panel stays above the bench and the SELL tile (default camera)

const DamagePanel := preload("res://Scripts/damage_meter.gd")
const PlannerPanel := preload("res://Scripts/team_planner.gd")
const MenuPanel := preload("res://Scripts/pause_menu.gd")
const TutorialPanel := preload("res://Scripts/tutorial.gd")

var current := ""             # "", "damage", "planner" or "menu"
var tab_bar: HudPlate
var panel: HudPlate
var tabs := {}                # name -> Button
var damage                    # damage_meter.gd
var planner                   # team_planner.gd
var menu                      # pause_menu.gd
var dim: ColorRect
var _bar_lip: StyleBoxFlat

func _ready():
	add_to_group("right_dock")
	process_mode = Node.PROCESS_MODE_ALWAYS   # Esc and the menu work while the game is paused
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -MARGIN
	offset_left = -MARGIN - WIDTH
	offset_top = MARGIN
	custom_minimum_size.x = WIDTH
	Settings.ensure_loaded()

	tab_bar = HudPlate.new()
	tab_bar.setup_plate(2, 4, 0)
	_bar_lip = tab_bar._lip
	add_child(tab_bar)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	tab_bar.add_child(row)
	tabs["damage"] = _tab("Damage", "", "chart", "Damage your units dealt and took.")
	tabs["planner"] = _tab("Planner", "P", "grid", "Team planner (P): pick the units you're aiming for.")
	tabs["menu"] = _tab("Menu", "Esc", "lines", "Pause menu (Esc).")
	for k in ["damage", "planner", "menu"]:
		row.add_child(tabs[k])
		tabs[k].pressed.connect(toggle_panel.bind(k))

	panel = HudPlate.new()
	panel.setup_plate(8, 10, 10, DockKit.PANEL_FILL)
	panel.set_edge(Color.TRANSPARENT)
	add_child(panel)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stack)
	damage = DamagePanel.new()
	stack.add_child(damage)
	planner = PlannerPanel.new()
	stack.add_child(planner)
	menu = MenuPanel.new()
	stack.add_child(menu)

	dim = ColorRect.new()
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_dim.call_deferred()

	# The tutorial starts with the damage panel closed (without changing the saved choice), so its step
	# panel and the standings both fit above the bench.
	_show("damage" if Settings.show_damage_meter and not TutorialPanel.is_tutorial_run() else "")
	minimum_size_changed.connect(func(): _shrink.call_deferred())   # content grew or shrank

# The dim goes under the whole HUD: first child of the UI layer, so it only darkens the board.
func _add_dim():
	var ui := get_parent()
	ui.add_child(dim)
	ui.move_child(dim, 0)

func _exit_tree():
	if current == "menu" and is_inside_tree():
		get_tree().paused = false

func can_pause() -> bool:
	return menu._can_pause()

# Open a panel (closing whichever was open).
func open_panel(p: String) -> void:
	if p == "menu" and not can_pause():
		return
	if p == "damage":
		Settings.show_damage_meter = true
		Settings.save_settings()
	_show(p)

# Close the open panel. The damage panel comes back after the planner or the menu if it's switched on.
func close_panel() -> void:
	if current == "damage":
		Settings.show_damage_meter = false
		Settings.save_settings()
		_show("")
	else:
		_show("damage" if Settings.show_damage_meter else "")

func toggle_panel(p: String) -> void:
	if current == p:
		close_panel()
	else:
		open_panel(p)

func _show(p: String) -> void:
	var was := current
	current = p
	damage.visible = p == "damage"
	planner.visible = p == "planner"
	menu.visible = p == "menu"
	panel.visible = p != ""
	for k in tabs:
		DockKit.set_tab_active(tabs[k], k == p, DockKit.PANEL_FILL, true)
	tab_bar._lip = null if p != "" else _bar_lip   # the lip moves to the bottom of the open panel
	tab_bar.queue_redraw()
	if p == "planner":
		planner._rebuild()
	if p == "damage":
		damage._refresh()
	if p == "menu":
		get_tree().paused = LobbyNet.can_pause()   # a LAN game keeps going for everyone else
		dim.visible = true
		menu.resume_button.grab_focus.call_deferred()
	elif was == "menu":
		get_tree().paused = false
		dim.visible = false
	_shrink.call_deferred()

# A container keeps its size when its content gets smaller; snap back to the content. Down the right
# edge, under the box: the tutorial's step panel (tutorial level only), then the HP standings. A short
# open panel pushes them down instead of covering them; the standings hide under a tall one (the
# planner, a full damage list), and the tutorial panel never goes below TUTORIAL_MAX_BOTTOM, so it
# stays clear of the bench and the SELL tile (it then draws under the open panel).
func _shrink() -> void:
	reset_size()
	offset_right = -MARGIN
	offset_left = -MARGIN - WIDTH
	offset_top = MARGIN
	custom_minimum_size.x = WIDTH
	var y := MARGIN + get_combined_minimum_size().y + 3.0 + STANDINGS_GAP   # just under the box and its lip
	var tut := get_parent().get_node_or_null("TutorialPanel") as Control
	if tut != null and tut.visible:
		if not tut.minimum_size_changed.is_connected(_on_tutorial_resized):
			tut.minimum_size_changed.connect(_on_tutorial_resized)   # step text changes its height
		var h := tut.get_combined_minimum_size().y
		var top := minf(y, TUTORIAL_MAX_BOTTOM - h)
		tut.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		tut.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		tut.offset_right = -MARGIN
		tut.offset_left = -MARGIN - tut.get_combined_minimum_size().x
		tut.offset_top = top
		tut.offset_bottom = top + h
		y = top + h + 3.0 + STANDINGS_GAP
	var standings := get_parent().get_node_or_null("Standings") as Control
	if standings != null:
		var max_top := STANDINGS_MAX_TOP
		if tut != null and tut.visible:   # under the tutorial panel they may go lower, still ending above the bench
			max_top = maxf(max_top, TUTORIAL_MAX_BOTTOM - standings.get_combined_minimum_size().y)
		standings.offset_top = clampf(y, STANDINGS_TOP, max_top)
		standings.visible = y <= max_top   # under a tall panel they'd only peek out at the edge

func _on_tutorial_resized() -> void:
	_shrink.call_deferred()

func _input(event):
	if not event.is_action_pressed("ui_cancel"):
		return
	if current == "menu":
		close_panel()
	elif current == "planner":
		close_panel()   # Esc closes the planner before it opens the menu
	elif can_pause():
		open_panel("menu")
	else:
		return
	get_viewport().set_input_as_handled()

func _unhandled_input(event):
	if Keybinds.pressed(event, "team_planner") and not get_tree().paused:   # P by default
		toggle_panel("planner")
		get_viewport().set_input_as_handled()

func _tab(label: String, key: String, icon: String, tip: String) -> Button:
	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 3)
	content.add_child(DockKit.PixelIcon.new(icon, HudStyle.MUTED, 12))
	content.add_child(DockKit.tab_label(label, 12))
	if key != "":
		var k := DockKit.text(9, DockKit.DIM_TEXT)
		k.text = key
		k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var s := StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		s.set_border_width_all(1)
		s.border_color = HudStyle.EDGE
		s.set_corner_radius_all(2)
		s.content_margin_left = 2
		s.content_margin_right = 2
		k.add_theme_stylebox_override("normal", s)
		content.add_child(k)
	var b := DockKit.tab(content, 32)
	b.tooltip_text = Tip.wrap(tip)
	return b
