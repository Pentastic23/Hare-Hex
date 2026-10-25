# load_profile.gd
# Dev tool, not part of the game: times what the player waits for. Prints how long the engine took to
# reach this scene (autoloads included), then loading and building the main menu, and starting a run
# (loading main.tscn and its _ready). Run it with a window for real numbers (headless skips GPU work):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/load_profile.tscn
# Add "-- detail" to time the biggest resources one by one (each in a fresh state is impossible in one
# process, so detail mode loads them before the scenes and the scene numbers then read as cached).

extends Node

func ms(t0: int) -> String:
	return "%7.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0)

func _ready():
	_run.call_deferred()

func frame():
	await get_tree().process_frame

func _run():
	print("engine start -> this scene: %d ms (autoloads included)" % Time.get_ticks_msec())
	if "deps" in OS.get_cmdline_user_args():
		_deps()
		get_tree().quit()
		return
	if "flow" in OS.get_cmdline_user_args():
		await _flow()
		get_tree().quit()
		return
	if "units" in OS.get_cmdline_user_args():
		await _units()
		get_tree().quit()
		return
	var detail := "detail" in OS.get_cmdline_user_args()
	if detail:
		_detail()
	SaveGame.path = "user://load_profile_save.json"

	var t := Time.get_ticks_usec()
	var menu_scene: PackedScene = load("res://scenes/menu.tscn")
	print("load menu.tscn            ", ms(t))
	t = Time.get_ticks_usec()
	var menu := menu_scene.instantiate()
	add_child(menu)
	print("menu instantiate + _ready ", ms(t))
	t = Time.get_ticks_usec()
	await frame()
	await frame()
	print("menu first two frames     ", ms(t))
	menu.queue_free()
	await frame()

	GameState.run_level = null
	GameState.run_carry = {}
	GameState.reset()
	t = Time.get_ticks_usec()
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	print("load main.tscn            ", ms(t))
	t = Time.get_ticks_usec()
	var main := main_scene.instantiate()
	print("main instantiate          ", ms(t))
	t = Time.get_ticks_usec()
	add_child(main)
	print("main _ready (run setup)   ", ms(t))
	t = Time.get_ticks_usec()
	await frame()
	await frame()
	print("main first two frames     ", ms(t))
	main.queue_free()
	await frame()

	GameState.run_level = load("res://tres/campaign/levels/ch2_l3.tres")
	GameState.reset()
	t = Time.get_ticks_usec()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await frame()
	print("second run (cached), campaign level ", ms(t))
	main.queue_free()
	await frame()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	get_tree().quit()

func _detail():
	var t := Time.get_ticks_usec()
	var units: Array = []
	for f in DirAccess.get_files_at("res://tres/units"):
		if f.ends_with(".tres"):
			units.append("res://tres/units/" + f)
	for f in DirAccess.get_files_at("res://tres"):
		if f.ends_with(".tres") and not f.begins_with("panel") and not f.begins_with("ui_"):
			units.append("res://tres/" + f)
	var t1 := Time.get_ticks_usec()
	for p in units:
		load(p)
	print("all %d unit .tres (with their models) %s" % [units.size(), ms(t1)])
	t1 = Time.get_ticks_usec()
	for f in DirAccess.get_files_at("res://textures/ui/portraits"):
		if f.ends_with(".png"):
			load("res://textures/ui/portraits/" + f)
	print("portraits                    ", ms(t1))
	t1 = Time.get_ticks_usec()
	for f in ["lost_kingdom", "aspiration_woods", "final_struggle"]:
		ResourceLoader.load("res://audio/music/%s.wav" % f, "", ResourceLoader.CACHE_MODE_IGNORE)
	print("the 3 music tracks (uncached) ", ms(t1))
	print("detail total                 ", ms(t))

# "-- deps": times each resource main.tscn and ui.tscn pull in, in the order they list them (fresh
# process, so each line is a first load; things already loaded by an earlier line read as cheap).
func _deps():
	for scene in ["res://scenes/ui.tscn", "res://scenes/main.tscn"]:
		var text := FileAccess.get_file_as_string(scene)
		var rx := RegEx.new()
		rx.compile(r'\[ext_resource type="(\w+)"[^\]]*path="([^"]+)"')
		var rows: Array = []
		for m in rx.search_all(text):
			var t := Time.get_ticks_usec()
			load(m.get_string(2))
			rows.append([(Time.get_ticks_usec() - t) / 1000.0, m.get_string(1), m.get_string(2)])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		var total := 0.0
		for r in rows:
			total += r[0]
		print("%s: %.0f ms over %d resources; slowest:" % [scene, total, rows.size()])
		for r in rows.slice(0, 12):
			print("  %7.1f ms  %-12s %s" % r)

# "-- units": spawns units on a live board the way a fight does, and times it (first spawn of each
# type includes loading its model; the second batch is the steady cost per unit).
func _units():
	GameState.run_level = null
	GameState.run_carry = {}
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	await frame()
	await frame()
	var board: Board = main.get_node("Board")
	var names := ["knight", "archer", "mage", "guardian", "berserker", "thief", "cleric", "hunter", "assassin", "dragon"]
	for batch in 2:
		var t := Time.get_ticks_usec()
		for n in names:
			var u := (load("res://scenes/unit.tscn") as PackedScene).instantiate() as Unit
			board.get_node("Units").add_child(u)
			u.setup(load("res://tres/%s.tres" % n), 1)
			u.begin_combat()
		var spawn := ms(t)
		t = Time.get_ticks_usec()
		await frame()
		print("batch %d: 10 units spawned %s, next frame %s" % [batch + 1, spawn, ms(t)])
	main.queue_free()
	await frame()

# "-- flow": what a player sees. The menu comes up and warms the run in the background; after a pause
# like a player's (or until it's done, at most 6 s) a mode is picked, timed from the click to the run
# drawing its second frame.
func _flow():
	SaveGame.path = "user://load_profile_save.json"
	var t := Time.get_ticks_usec()
	var menu := (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await frame()
	print("menu on screen            ", ms(t))
	t = Time.get_ticks_usec()
	await frame()
	await frame()
	var worst := 0
	var last := Time.get_ticks_usec()
	while Preload.busy() and Time.get_ticks_usec() - t < 6000000:
		await frame()
		worst = maxi(worst, Time.get_ticks_usec() - last)
		last = Time.get_ticks_usec()
	print("background warm-up        ", ms(t), "  (longest menu frame meanwhile: %.0f ms)" % (worst / 1000.0))
	t = Time.get_ticks_usec()
	worst = 0
	last = Time.get_ticks_usec()
	await frame()
	while not ShaderWarmup.done and Time.get_ticks_usec() - t < 10000000 and DisplayServer.get_name() != "headless":
		await frame()
		worst = maxi(worst, Time.get_ticks_usec() - last)
		last = Time.get_ticks_usec()
	print("shader warm-up            ", ms(t), "  (longest menu frame meanwhile: %.0f ms)" % (worst / 1000.0))
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.reset()
	t = Time.get_ticks_usec()
	var main := Preload.scene(Preload.RUN_SCENE).instantiate()
	menu.queue_free()
	add_child(main)
	await frame()
	await frame()
	print("pick a mode -> run drawn  ", ms(t))
	main.queue_free()
	await frame()
