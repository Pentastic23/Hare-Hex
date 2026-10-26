# inspector_shots.gd
# Dev tool, not part of the game: opens the unit inspector on a few units (an ally with items and a
# synergy, a caster, a 2-star enemy) in a free-play run and saves them side by side, cropped to the panel.
# Needs a real window (not --headless):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/inspector_shots.tscn -- <out.png>

extends Node

const CROP := Vector2i(300, 560)   # the bottom-right corner of a 1152 x 648 window

func _ready():
	_run.call_deferred()

func _ud(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

func _run():
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit)   # never hang on a script error
	get_window().size = Vector2i(1152, 648)
	Settings.path = "user://inspector_shots_settings.cfg"   # never the player's own files
	SaveGame.path = "user://inspector_shots_save.json"
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://inspector_shots.png"
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 5
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	for i in 4:
		await get_tree().process_frame
	var board: Board = main.get_node("Board")
	GameState.me.level = 6
	board.refresh_unlocks(6, false)
	var knight := _place(board, "knight", board.player_order[0], 0)
	_place(board, "militia", board.player_order[1], 0)
	knight.equip(load("res://tres/items/longsword.tres"))
	knight.equip(load("res://tres/items/iron_belt.tres"))
	knight.equip(load("res://tres/items/blood_fang.tres"))
	var mage := _place(board, "mage", board.player_order[2], 0)
	var foe := _place(board, "dragon", board.enemy_order[0], 1)
	foe.set_star(2)
	var insp = main.find_child("UnitInspector", true, false)
	var shots: Array[Image] = []
	for u in [knight, mage, foe]:
		insp.show_unit(u)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		print("%s: top %d, height %d" % [u.data.display_name, insp.get_global_rect().position.y, insp.size.y])
		var img := get_viewport().get_texture().get_image()
		var k := get_viewport().get_final_transform().get_scale()
		var r := Rect2i(Vector2i((Vector2(1152, 648) - Vector2(CROP)) * k), Vector2i(Vector2(CROP) * k))
		img = img.get_region(r)
		img.resize(CROP.x, CROP.y)
		img.convert(Image.FORMAT_RGBA8)
		shots.append(img)
	var sheet := Image.create_empty(CROP.x * shots.size(), CROP.y, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP), Vector2i(i * CROP.x, 0))
	sheet.save_png(out)
	print("inspector -> ", out)
	get_tree().quit()

func _place(board: Board, n: String, c: Vector2i, team: int) -> Unit:
	var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(u)
	u.setup(_ud(n), team)
	if team == 0:
		board.put_on_tile(u, c)
	else:
		board.put_enemy_on_tile(u, c)
	return u
