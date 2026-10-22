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
		chk("menu shows the title AZTactics", texts.has("AZTactics"))
		chk("menu buttons: Campaign, Free Play, Settings, Quit", find_button(scene(), "Campaign") != null and find_button(scene(), "Free Play") != null and find_button(scene(), "Settings") != null and find_button(scene(), "Quit") != null)
		chk("no saved run: Continue hidden", find_button(scene(), "Continue") == null)
		chk("sections: SINGLE PLAYER and PVP", texts.has("SINGLE PLAYER") and texts.has("PVP"))
		chk("new player: Tutorial says start here", find_button(scene(), "Tutorial") != null and find_button(scene(), "Tutorial").text.contains("start here"))
		var menu_h: float = scene().main_box.get_combined_minimum_size().y
		chk("menu fits a 648 px tall window", menu_h <= 620, "height %d" % menu_h)

		# Live PvP is still a placeholder with an info panel
		var async_btn := find_button(scene(), "Async PvP")
		chk("Async PvP is a real button now (no 'coming soon')", async_btn != null and not async_btn.text.contains("coming soon") and async_btn.tooltip_text.contains("ghost"))
		press("Live PvP")
		await get_tree().process_frame
		var info = scene().info_panel
		chk("Live PvP opens its coming-soon panel", info.get_parent().visible and info.get_child(0).get_node("Title").text == "Live PvP" and find_button(scene(), "Free Play") == null)
		press("Back")
		await get_tree().process_frame
		chk("Back returns to the menu", find_button(scene(), "Free Play") != null)

		# Async PvP starts a free-play run against ghosts (isolated snapshot folder: nothing of yours is touched)
		LocalSnapshotStore.root = "user://menu_test_snapshots"
		press("Async PvP")
		await wait(0.5)
		chk("Async PvP starts a ghost-mode free-play run", scene().name == "Main" and GameState.ghost_mode and GameState.run_level == null and scene().get_node("Game Manager").opponents is SnapshotOpponents)
		chk("its standings show who it will fight", scene().get_node("UI/Standings").opponent_row() != null)
		GameState.go_to_menu()   # the real way out of a run, which clears ghost mode
		await wait(0.4)
		chk("back in the menu, ghost mode is off", not GameState.ghost_mode)
		press("Free Play")
		await wait(0.5)
		chk("Free Play is not ghost mode", not GameState.ghost_mode and scene().get_node("Game Manager").opponents is RandomOpponents)
		await to_menu()
		LocalSnapshotStore.root = ""

		# Tutorial starts the tutorial level
		press("Tutorial")
		await wait(0.5)
		chk("Tutorial starts the tutorial with its step panel", scene().name == "Main" and GameState.run_level != null and GameState.run_level.id == &"tutorial" and scene().get_node("UI/TutorialPanel").visible)
		SaveGame.record_level_complete(&"tutorial", 100)
		await to_menu()
		chk("after finishing it, Tutorial says done", find_button(scene(), "Tutorial").text.contains("done"))
		SaveGame.reset_progress()
		await to_menu()

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
		chk("campaign panel lists all 9 levels: first open, the rest locked", rows.size() == 9 and rows[0].ends_with("Not completed") and rows.slice(1).all(func(r): return r.ends_with("Locked")), " | ".join(rows).left(200))
		var heads := Array(texts).filter(func(t): return t in ["The Borderlands", "The Ashen Frontier", "The Shattered Sky"])
		chk("three chapter headings in order", heads == ["The Borderlands", "The Ashen Frontier", "The Shattered Sky"], str(heads))
		var panel_h: float = scene().campaign_panel.get_child(0).get_combined_minimum_size().y
		chk("campaign panel scrolls and still fits a 648 px window", scene().campaign_panel.get_child(0).find_child("Scroll", true, false) != null and panel_h <= 620, "height %d" % panel_h)
		var starts := scene().find_children("*", "Button", true, false).filter(func(b): return b.text.begins_with("Start "))
		chk("Start buttons: chapter 1 open, chapters 2 and 3 locked", starts.size() == 3 and not starts[0].disabled and starts[1].disabled and starts[2].disabled)
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
		chk("level 1 shows completed with best HP; level 2 unlocked", rows[0].ends_with("Completed, best 90 HP") and rows[1].ends_with("Not completed") and rows[2].ends_with("Locked"), " | ".join(rows).left(200))
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
