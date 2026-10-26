# bar_shots.gd
# Dev tool, not part of the game: units on the board with their health and mana bars, star marks and item
# icons (no items, one, three; hurt, shielded, full mana; an enemy), close up. Needs a real window:
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/bar_shots.tscn -- <out.png> [zoom]

extends Node

func _ready():
	_run.call_deferred()

func _ud(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

func _run():
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit)   # never hang on a script error
	get_window().size = Vector2i(1152, 648)
	Settings.path = "user://bar_shots_settings.cfg"   # never the player's own files
	SaveGame.path = "user://bar_shots_save.json"
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://bar_shots.png"
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 5
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	for i in 4:
		await get_tree().process_frame
	(main.get_node("UI") as CanvasLayer).visible = false
	var board: Board = main.get_node("Board")
	GameState.me.level = 8
	board.refresh_unlocks(8, false)
	var items := ["longsword", "iron_belt", "heros_blade"]
	var specs := [["knight", Vector2i(2, 4), 0, 3, 1.0, 0.0, 0.3], ["mage", Vector2i(3, 4), 0, 1, 0.55, 1.0, 0.0], ["archer", Vector2i(4, 4), 0, 0, 0.8, 0.5, 0.0],
		["dragon", Vector2i(3, 3), 1, 0, 0.7, 0.2, 0.0], ["guardian", Vector2i(2, 3), 1, 2, 0.35, 0.6, 0.15]]
	for sp in specs:
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(_ud(sp[0]), sp[2])
		if sp[2] == 0:
			board.put_on_tile(u, sp[1])
		else:
			board.put_enemy_on_tile(u, sp[1])
		if sp[0] == "knight":
			u.set_star(2)
		for i in sp[3]:
			u.equip(load("res://tres/items/%s.tres" % items[i]))
		u.health = u.max_hp() * sp[4]
		u.mana = u.data.max_mana * sp[5]
		u.shield = u.max_hp() * sp[6]
	var rig = main.get_node("CameraRig")
	rig.zoom = float(args[1]) if args.size() > 1 else rig.ZOOM_MIN
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var k := get_viewport().get_final_transform().get_scale()
	img = img.get_region(Rect2i(Vector2i(Vector2(340, 110) * k), Vector2i(Vector2(400, 240) * k)))   # the units, close up
	img.resize(1200, 720, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("bars -> ", out)
	get_tree().quit()
