# menu_checks.gd
# Dev tool, not part of the game: drives the main menu, pause menu and end screen through real
# scene changes. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/menu_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway save and settings files.

extends Node


class Driver extends Node:
	var fails := 0
	func chk(name: String, cond: bool, detail := ""):
		print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
		if not cond:
			fails += 1
	func wait(t: float):
		await get_tree().create_timer(t, true).timeout
	func scene() -> Node:
		return get_tree().current_scene
	func find_button(root: Node, prefix: String) -> Button:
		for c in root.find_children("*", "Button", true, false):
			if c.text.begins_with(prefix) and c.is_visible_in_tree():
				return c
		return null
	func labels(root: Node) -> PackedStringArray:
		var out: PackedStringArray = []
		for c in root.find_children("*", "Label", true, false):
			if c.is_visible_in_tree():
				out.append(c.text)
		return out
	func press(prefix: String) -> bool:
		var b := find_button(scene(), prefix)
		if b == null:
			print("   (no visible button starting with '%s')" % prefix)
			return false
		b.pressed.emit()
		return true
	func esc():
		var e := InputEventAction.new()
		e.action = "ui_cancel"
		e.pressed = true
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
	func to_menu():
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
		await wait(0.4)

	func run():
		SaveGame.path = "user://menu_test_save.json"
		SaveGame.reset_progress()
		Settings.path = "user://menu_test_settings.cfg"
		var l1: CampaignLevel = load("res://tres/campaign/levels/ch1_l1.tres")
		var l2: CampaignLevel = load("res://tres/campaign/levels/ch1_l2.tres")

		await to_menu()
		var texts := labels(scene())
		chk("menu shows the title AzSurvivors", texts.has("AzSurvivors"))
		chk("menu buttons: Campaign, Free Play, Settings, Quit", find_button(scene(), "Campaign") != null and find_button(scene(), "Free Play") != null and find_button(scene(), "Settings") != null and find_button(scene(), "Quit") != null)
		chk("no saved run: Continue hidden", find_button(scene(), "Continue") == null)

		press("Free Play")
		await wait(0.5)
		var gm = scene().get_node("Game Manager")
		chk("Free Play starts free play", scene().name == "Main" and GameState.run_level == null and gm.opponents is RandomOpponents and GameState.launched_from_menu)

		# Esc pauses, Esc resumes
		await esc()
		var pm = scene().get_node("UI/PauseMenu")
		chk("Esc pauses and shows the pause menu", get_tree().paused and pm.visible)
		var round_before := GameState.round_number
		await wait(1.0)
		chk("paused: nothing advances", GameState.round_number == round_before and get_tree().paused)
		await esc()
		chk("Esc again resumes", not get_tree().paused and not pm.visible)
		await esc()
		press("Main menu")
		await wait(0.5)
		chk("pause menu -> Main menu returns to the menu, unpaused", scene().name == "MainMenu" and not get_tree().paused and GameState.run_level == null)

		# Campaign panel
		press("Campaign")
		await get_tree().process_frame
		await get_tree().process_frame
		texts = labels(scene())
		var rows := Array(texts).filter(func(t): return t.begins_with("  "))
		chk("campaign panel lists 3 levels: first open, others locked", rows.size() == 3 and rows[0].ends_with("Not completed") and rows[1].ends_with("Locked") and rows[2].ends_with("Locked"), " | ".join(rows))
		await esc()
		chk("Esc closes the campaign panel", find_button(scene(), "Free Play") != null)
		press("Campaign")
		await get_tree().process_frame
		press("Start The Borderlands")
		await wait(0.5)
		gm = scene().get_node("Game Manager")
		chk("Start chapter begins level 1 fresh", GameState.run_level == l1 and not GameState.run_carried and gm.opponents is WaveOpponents and GameState.me.player_hp == 100)

		# End screen has Main menu
		var es = scene().get_node("UI/End Screen")
		chk("end screen has a Main menu button", es.menu_button != null and es.menu_button.text == "Main menu")

		# Continue a saved run
		SaveGame.record_level_complete(&"ch1_l1", 90)
		SaveGame.set_chapter_run({"level": "ch1_l2", "hp": 90, "max_hp": 100, "gold": 20, "player_level": 3, "xp": 2, "items": ["quick_bow"], "units": [{"unit": "Knight", "star": 2, "items": ["iron_belt"], "coord": [3, 4]}, {"unit": "Cleric", "star": 1, "items": [], "bench": 1}]})
		await to_menu()
		var cont := find_button(scene(), "Continue")
		chk("saved run: Continue shows level and HP", cont != null and cont.text == "Continue: Shadows in the Wood (90 HP)", cont.text if cont else "missing")
		press("Campaign")
		await get_tree().process_frame
		await get_tree().process_frame
		rows = Array(labels(scene())).filter(func(t): return t.begins_with("  "))
		chk("level 1 shows completed with best HP; level 2 unlocked", rows[0].ends_with("Completed, best 90 HP") and rows[1].ends_with("Not completed") and rows[2].ends_with("Locked"), " | ".join(rows))
		await esc()
		press("Continue")
		await wait(0.5)
		var units: Array = scene().get_node("Board").all_player_units()
		chk("Continue loads level 2 with the saved board", GameState.run_level == l2 and GameState.run_carried and GameState.me.player_hp == 100 and units.size() == 2 and GameState.me.items.size() == 1, "hp %d units %d" % [GameState.me.player_hp, units.size()])

		# Starting a chapter over a saved run asks first
		await to_menu()
		press("Campaign")
		await get_tree().process_frame
		press("Start The Borderlands")
		await get_tree().process_frame
		var dlg: ConfirmationDialog = scene().confirm
		chk("starting over a saved run asks for confirmation", dlg.visible and dlg.dialog_text.contains("abandons your current run at Shadows in the Wood"), dlg.dialog_text)
		dlg.confirmed.emit()
		await wait(0.5)
		chk("confirming clears the saved run and starts level 1", GameState.run_level == l1 and not GameState.run_carried and SaveGame.chapter_run().is_empty())

		# Settings
		await to_menu()
		press("Settings")
		await get_tree().process_frame
		var vs: CheckBox = null
		for c in scene().find_children("*", "CheckBox", true, false):
			if c.text == "VSync":
				vs = c
		var before := Settings.vsync
		vs.button_pressed = not before
		Settings._loaded = false
		Settings.vsync = before   # forget the in-memory value, read it back from disk
		Settings.load_settings()
		chk("settings: VSync change saved to disk", Settings.vsync == (not before))
		press("Reset campaign progress")
		await get_tree().process_frame
		scene().confirm.confirmed.emit()
		chk("reset progress clears completed levels", not SaveGame.is_level_complete(&"ch1_l1"))

		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
		# Debug Level is ignored once the menu has chosen a run
		GameState.launched_from_menu = true
		GameState.run_level = null
		var m = load("res://scenes/main.tscn").instantiate()
		m.get_node("Game Manager").debug_level = l1
		add_child(m)
		await wait(0.3)
		chk("menu choice beats Debug Level", GameState.run_level == null and m.get_node("Game Manager").opponents is RandomOpponents)
		print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
		get_tree().quit()

func _ready():
	var d := Driver.new()
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(d)
	d.ready.connect(d.run)
