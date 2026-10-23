# gamepad_checks.gd
# Dev tool, not part of the game: plays a free-play run with simulated controller input
# (InputEventJoypadButton / JoypadMotion) and checks the pointer, buying, dragging, inspecting,
# selling, the menu and planner buttons, Buy XP / Reroll, zoom, pan and the shop lock. Run from the
# project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/gamepad_checks.tscn
# Prints PASS/FAIL per check and RESULT at the end. Uses a throwaway save and settings file.

extends Node

var fails := 0
var main: Node
var gm
var board: Board
var cam: Camera3D
var gp

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func frames(n := 2):
	for i in n:
		await get_tree().process_frame

func button(b: JoyButton, down: bool):
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)
	await frames()

func press(b: JoyButton):
	await button(b, true)
	await button(b, false)

func axis(a: JoyAxis, v: float):
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	await frames(1)

# Points with the pad (as if the stick had brought it there).
func point(p: Vector2):
	gp.active = true
	gp.move_cursor_to(p)
	await frames()

func screen_of(u: Node3D) -> Vector2:
	return cam.unproject_position(u.global_position + Vector3(0, 0.4, 0))

func centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func _ready():
	_run.call_deferred()

func _run():
	SaveGame.path = "user://pad_test_save.json"
	SaveGame.reset_progress()
	SaveGame.set_team_plan([])
	Settings.path = "user://pad_test_settings.cfg"
	Keybinds.path = "user://gamepad_checks_keybinds.cfg"   # default binds, whatever the player has set
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Keybinds.path))
	Keybinds.load_binds()
	Settings._loaded = true
	Settings.show_damage_meter = true
	Settings.dock_collapsed = false
	Settings.dock_tab = "synergies"
	GameState.run_level = null
	GameState.run_carry = {}
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	cam = get_viewport().get_camera_3d()
	await get_tree().create_timer(0.4).timeout
	gp = get_node("/root/GamepadControls")
	chk("the GamepadControls autoload is running", gp != null)
	chk("the pad no longer drives Godot's UI focus (A, B, D-pad taken off ui_*)", not InputMap.action_get_events("ui_accept").any(func(e): return e is InputEventJoypadButton) and not InputMap.action_get_events("ui_cancel").any(func(e): return e is InputEventJoypadButton) and not InputMap.action_get_events("ui_left").any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion))
	var shop = main.get_node("UI/ShopPanel")
	var insp = main.get_node("UI/UnitInspector")
	var rig = main.get_node("CameraRig")
	var dock = main.get_node("UI/RightDock")
	GameState.me.gold = 60
	GameState.me.level = 4
	board.refresh_unlocks(4, false)
	Events.gold_changed.emit(60)

	print("--- pointer")
	await point(Vector2(400, 300))
	var p0: Vector2 = get_tree().root.get_mouse_position()
	await axis(JOY_AXIS_LEFT_X, 1.0)
	await get_tree().create_timer(0.25).timeout
	await axis(JOY_AXIS_LEFT_X, 0.0)
	var p1: Vector2 = get_tree().root.get_mouse_position()
	chk("the left stick moves the pointer", p1.x > p0.x + 50.0 and absf(p1.y - p0.y) < 2.0, "%s -> %s" % [p0, p1])
	await axis(JOY_AXIS_LEFT_Y, 0.1)
	await get_tree().create_timer(0.2).timeout
	chk("a small tilt inside the dead zone doesn't", get_tree().root.get_mouse_position().is_equal_approx(p1))
	await axis(JOY_AXIS_LEFT_Y, 0.0)
	await button(JOY_BUTTON_DPAD_DOWN, true)
	await get_tree().create_timer(0.2).timeout
	await button(JOY_BUTTON_DPAD_DOWN, false)
	var p2: Vector2 = get_tree().root.get_mouse_position()
	chk("the D-pad nudges it slowly", p2.y > p1.y + 10.0 and p2.y < p1.y + 120.0, "%s -> %s" % [p1, p2])
	await point(Vector2(-50, 9000))
	var vs: Vector2 = get_tree().root.get_visible_rect().size
	var pe: Vector2 = get_tree().root.get_mouse_position()
	chk("the pointer stays on screen", pe.x >= 0.0 and pe.y <= vs.y, str(pe))

	print("--- buying, placing, inspecting, selling")
	var slot = shop.slots.filter(func(s): return s.offer != null)[0]
	var name: String = slot.offer.display_name
	await point(centre(slot))
	await press(JOY_BUTTON_A)
	var mine := board.bench.filter(func(u): return u != null and u.data.display_name == name)
	chk("A on a shop card buys it", slot.offer == null and mine.size() == 1, name)
	var u: Unit = mine[0]
	var target: Vector2i = board.player_order[0]
	await point(screen_of(u))
	await button(JOY_BUTTON_A, true)
	var to := cam.unproject_position(board.grid_to_world(target))
	for s in range(1, 9):
		await point(screen_of(u).lerp(to, float(s) / 8.0))
	await point(to)
	await button(JOY_BUTTON_A, false)
	chk("holding A drags the unit onto the board", u.coord == target, "coord %s" % u.coord)
	await point(screen_of(u))
	await press(JOY_BUTTON_X)
	chk("X inspects the unit under the pointer", insp.visible and insp.shown == u)
	await press(JOY_BUTTON_B)
	chk("B closes the inspector", not insp.visible and dock.current != "menu" and not get_tree().paused)
	await press(JOY_BUTTON_B)
	chk("B with nothing open doesn't open the menu", dock.current != "menu" and not get_tree().paused)
	var gold_before := GameState.me.gold
	await point(screen_of(u))
	await press(JOY_BUTTON_Y)
	await frames(3)
	chk("Y sells the unit under the pointer", not is_instance_valid(u) or u.is_queued_for_deletion() or not board.all_player_units().has(u), "gold %d -> %d" % [gold_before, GameState.me.gold])
	chk("and pays for it", GameState.me.gold > gold_before)

	print("--- shop buttons")
	var g0 := GameState.me.gold
	var xp0 := GameState.me.xp + GameState.me.level * 1000
	await press(JOY_BUTTON_LEFT_SHOULDER)
	chk("LB buys XP", GameState.me.gold == g0 - gm.BUY_XP_COST and GameState.me.xp + GameState.me.level * 1000 > xp0)
	var rolled := [0]
	Events.shop_rolled.connect(func(_o): rolled[0] += 1)
	var g1 := GameState.me.gold
	await press(JOY_BUTTON_RIGHT_SHOULDER)
	chk("RB rerolls", rolled[0] == 1 and GameState.me.gold == g1 - gm.REROLL_COST)
	await press(JOY_BUTTON_LEFT_STICK)
	chk("L3 locks the shop", GameState.me.shop_locked and shop.lock_button.button_pressed)
	await press(JOY_BUTTON_LEFT_STICK)
	chk("L3 again unlocks it", not GameState.me.shop_locked)

	print("--- planner and menu")
	await press(JOY_BUTTON_BACK)
	chk("Back opens the team planner", dock.current == "planner")
	var tile = dock.planner.grid.get_child(0)
	await point(centre(tile))
	await press(JOY_BUTTON_A)
	chk("A on a planner tile plans the unit", SaveGame.team_plan().size() == 1, str(SaveGame.team_plan()))
	await press(JOY_BUTTON_B)
	chk("B closes the planner", dock.current != "planner" and not get_tree().paused)
	await press(JOY_BUTTON_START)
	chk("Start opens the menu and pauses", dock.current == "menu" and get_tree().paused)
	chk("the menu lists the controller buttons when a pad is connected (none in this test, so hidden)", dock.menu.pad_help != null and dock.menu.pad_help.visible == not Input.get_connected_joypads().is_empty())
	await point(centre(dock.menu.resume_button))
	await press(JOY_BUTTON_A)
	chk("A on Resume resumes (the pad works while paused)", dock.current != "menu" and not get_tree().paused)
	await press(JOY_BUTTON_START)
	await press(JOY_BUTTON_B)
	chk("B closes the menu too", dock.current != "menu" and not get_tree().paused)

	print("--- view")
	rig.zoom = 1.0
	rig._zoom_now = 1.0
	rig.pan = Vector3.ZERO
	rig._place()
	await axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await get_tree().create_timer(0.3).timeout
	await axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	chk("RT zooms in", rig.zoom < 0.9, str(rig.zoom))
	var z: float = rig.zoom
	await axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await get_tree().create_timer(0.15).timeout
	await axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	chk("LT zooms out", rig.zoom > z, "%s -> %s" % [z, rig.zoom])
	rig.zoom = rig.ZOOM_MIN
	rig._zoom_now = rig.ZOOM_MIN
	rig._place()
	var pan0: Vector3 = rig.pan
	await axis(JOY_AXIS_RIGHT_X, 1.0)
	await get_tree().create_timer(0.25).timeout
	await axis(JOY_AXIS_RIGHT_X, 0.0)
	chk("the right stick pans the view", rig.pan.distance_to(pan0) > 0.05, "%s -> %s" % [pan0, rig.pan])
	await press(JOY_BUTTON_RIGHT_STICK)
	chk("R3 resets the view", is_equal_approx(rig.zoom, 1.0) and rig.pan == Vector3.ZERO)

	print("--- mouse takes over")
	var m := InputEventMouseMotion.new()
	m.position = get_tree().root.get_final_transform() * Vector2(700, 200)
	m.global_position = m.position
	m.relative = Vector2(30, 0)
	Input.parse_input_event(m)
	await frames(3)
	chk("moving the real mouse hands the pointer back to it", not gp.active and gp.cursor.distance_to(Vector2(700, 200)) < 2.0, str(gp.cursor))

	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
