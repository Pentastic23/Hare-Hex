# keybinds_checks.gd
# Dev tool, not part of the game: checks the keybinds (keybinds.gd), the main menu's Keybinds screen and
# the keyboard / controller shortcuts in a run. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/keybinds_checks.tscn
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway keybinds, save and settings files.

extends Node

var fails := 0

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func frames(n := 2):
	for i in n:
		await get_tree().process_frame

func key(k: Key):
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await frames(1)
	await frames()

func pad(b: JoyButton):
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.pressed = down
		Input.parse_input_event(e)
		await frames(1)
	await frames()

func _ready():
	_run.call_deferred()

func _run():
	Keybinds.path = "user://keybinds_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Keybinds.path))
	Keybinds.load_binds()
	SaveGame.path = "user://keybinds_test_save.json"
	SaveGame.reset_progress()
	Settings.path = "user://keybinds_test_settings.cfg"
	Settings._loaded = true

	print("--- binds")
	chk("keyboard defaults: F sell, E Buy XP, D reroll, L lock, P planner", Keybinds.keys.sell_unit == KEY_F and Keybinds.keys.buy_xp == KEY_E and Keybinds.keys.reroll == KEY_D and Keybinds.keys.lock_shop == KEY_L and Keybinds.keys.team_planner == KEY_P)
	chk("controller defaults: A select, X inspect, Y sell, B back, LB / RB", Keybinds.pad.click == JOY_BUTTON_A and Keybinds.pad.inspect == JOY_BUTTON_X and Keybinds.pad.sell_unit == JOY_BUTTON_Y and Keybinds.pad.back == JOY_BUTTON_B and Keybinds.pad.buy_xp == JOY_BUTTON_LEFT_SHOULDER)
	chk("zoom keys keep their keypad variants by default", InputMap.action_get_events("kb_zoom_in").size() == 2)
	chk("Esc can't be bound", not Keybinds.set_key("buy_xp", KEY_ESCAPE) and Keybinds.keys.buy_xp == KEY_E)
	Keybinds.set_key("reroll", KEY_F)
	chk("binding a key that's in use swaps it (reroll F, sell gets D)", Keybinds.keys.reroll == KEY_F and Keybinds.keys.sell_unit == KEY_D)
	chk("the D-pad can't be bound (it moves the pointer)", not Keybinds.set_pad("buy_xp", JOY_BUTTON_DPAD_UP))
	Keybinds.set_pad("buy_xp", JOY_BUTTON_Y)
	chk("binding a pad button that's in use swaps it (Buy XP Y, sell gets LB)", Keybinds.pad.buy_xp == JOY_BUTTON_Y and Keybinds.pad.sell_unit == JOY_BUTTON_LEFT_SHOULDER)
	Keybinds._loaded = false
	Keybinds.load_binds()
	chk("binds are saved and load back", Keybinds.keys.reroll == KEY_F and Keybinds.pad.buy_xp == JOY_BUTTON_Y)
	chk("the pause menu's controller list follows them", Keybinds.pad_help().has(["Y", "Buy XP"]))
	Keybinds.reset_defaults()
	chk("Reset to defaults", Keybinds.keys.reroll == KEY_D and Keybinds.keys.sell_unit == KEY_F and Keybinds.pad.buy_xp == JOY_BUTTON_LEFT_SHOULDER)

	print("--- Keybinds screen in the main menu")
	var menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await frames(3)
	var open_btn: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if b.text == "Keybinds":
			open_btn = b
	chk("the main menu has a Keybinds button", open_btn != null)
	open_btn.pressed.emit()
	await frames()
	chk("it opens the Keybinds screen", menu.keybinds_panel.get_parent().visible and not menu.main_box.get_parent().visible)
	var grid: GridContainer = menu.keybinds_grid
	chk("keyboard tab: every rebindable action plus the fixed mouse / Esc rows", grid.get_child_count() == (Keybinds.KEY_ORDER.size() + Keybinds.FIXED_KEYS.size()) * 2, str(grid.get_child_count()))
	var sell_btn: Button = grid.get_node("sell_unit")
	chk("binds show their key", sell_btn.text == "F")
	sell_btn.pressed.emit()
	await frames()
	chk("clicking a bind waits for a key", menu._listening == "sell_unit" and (grid.get_node("sell_unit") as Button).text.begins_with("Press"))
	await key(KEY_K)
	chk("the next key becomes the bind", Keybinds.keys.sell_unit == KEY_K and (grid.get_node("sell_unit") as Button).text == "K" and menu._listening == "")
	(grid.get_node("buy_xp") as Button).pressed.emit()
	await frames()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(3)
	chk("Esc cancels waiting without closing the screen", menu._listening == "" and Keybinds.keys.buy_xp == KEY_E and menu.keybinds_panel.get_parent().visible)
	menu.keybinds_tabs["controller"].pressed.emit()
	await frames()
	chk("controller tab: every rebindable button plus the fixed sticks / triggers", grid.get_child_count() == (Keybinds.PAD_ORDER.size() + Keybinds.FIXED_PAD.size()) * 2)
	(grid.get_node("reroll") as Button).pressed.emit()
	await frames()
	await pad(JOY_BUTTON_X)
	chk("the next controller button becomes the bind (it doesn't inspect)", Keybinds.pad.reroll == JOY_BUTTON_X and Keybinds.pad.inspect == JOY_BUTTON_RIGHT_SHOULDER and (grid.get_node("reroll") as Button).text == "X")
	menu._show_panel(null)
	chk("Back to the main menu", not menu.keybinds_panel.get_parent().visible and menu.main_box.get_parent().visible)
	menu.queue_free()
	await frames()

	print("--- shortcuts in a run")
	GameState.run_level = null
	GameState.run_carry = {}
	var main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	await get_tree().create_timer(0.4).timeout
	var gm = main.get_node("Game Manager")
	var shop = main.get_node("UI/ShopPanel")
	var rig = main.get_node("CameraRig")
	var dock = main.get_node("UI/RightDock")
	GameState.me.gold = 50
	var g0 := GameState.me.gold
	await key(KEY_E)
	chk("E buys XP", GameState.me.gold == g0 - gm.BUY_XP_COST)
	var rolled := [0]
	Events.shop_rolled.connect(func(_o): rolled[0] += 1)
	await key(KEY_D)
	chk("D rerolls", rolled[0] == 1)
	await key(KEY_L)
	chk("L locks the shop", GameState.me.shop_locked)
	await key(KEY_D)
	chk("D does nothing while locked", rolled[0] == 1)
	await key(KEY_L)
	chk("L again unlocks it", not GameState.me.shop_locked)
	await key(KEY_P)
	chk("P opens the planner", dock.current == "planner")
	await key(KEY_P)
	rig.zoom = 0.7
	rig.pan = Vector3(1, 0, 1)
	await key(KEY_HOME)
	chk("Home resets the view", is_equal_approx(rig.zoom, 1.0) and rig.pan == Vector3.ZERO)
	await key(KEY_EQUAL)
	chk("= zooms in", rig.zoom < 1.0)
	Keybinds.set_key("buy_xp", KEY_B)
	var g1 := GameState.me.gold
	await key(KEY_E)
	chk("after rebinding Buy XP to B, E does nothing", GameState.me.gold == g1)
	await key(KEY_B)
	chk("and B buys XP", GameState.me.gold == g1 - gm.BUY_XP_COST)
	var g2 := GameState.me.gold
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	chk("the rebound pad button works in a run (RB now inspects; Buy XP stays on LB)", GameState.me.gold == g2)
	await pad(JOY_BUTTON_LEFT_SHOULDER)
	chk("LB buys XP", GameState.me.gold == g2 - gm.BUY_XP_COST)
	main.queue_free()

	Keybinds.reset_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Keybinds.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
