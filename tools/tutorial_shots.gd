# tutorial_shots.gd
# Dev tool, not part of the game: opens the tutorial and saves a picture of some of its steps, the card in
# the middle with the spotlight, and one as the strip at the top. Needs a real window (not --headless):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/tutorial_shots.tscn -- <folder>
# Writes <folder>/tutorial_<n>.png.

extends Node

func _ready():
	_run.call_deferred()

func _run():
	get_window().size = Vector2i(1152, 648)
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if not args.is_empty() else OS.get_user_data_dir()
	SaveGame.path = "user://tutorial_shots_save.json"
	Settings.path = "user://tutorial_shots_settings.cfg"
	Settings._loaded = true
	GameState.run_level = load("res://tres/campaign/tutorial.tres")
	GameState.run_campaign = load("res://tres/campaign/campaign.tres")
	GameState.run_carry = {}
	GameState.launched_from_menu = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.6).timeout
	var tut = main.get_node("UI/TutorialPanel")
	var board: Board = main.get_node("Board")
	var gm = main.get_node("Game Manager")
	# A unit on the board, so the steps that point at units have one.
	Events.unit_bought.emit(load("res://tres/knight.tres"))
	await get_tree().process_frame
	var u: Unit = board.all_player_units()[0]
	board.detach(u)
	board.put_on_tile(u, board.player_order[0])
	var shots := [[0, true], [2, true], [13, false], [6, true], [8, true], [10, true], [11, true], [16, true]]
	var n := 0
	for s in shots:
		tut._enter_step(s[0])
		if not s[1]:
			tut._set_explaining(false)
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("tutorial_%d.png" % n))
		n += 1
	print("saved %d shots to %s" % [n, dir])
	get_tree().paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	get_tree().quit()
