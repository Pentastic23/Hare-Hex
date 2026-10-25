# theme_shots.gd
# Dev tool, not part of the game: renders the board in each of the 10 themes (with a few units on it)
# and saves one contact sheet. Needs a real window (not --headless), because headless runs draw nothing:
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/theme_shots.tscn -- <output.png>
# Without a path it writes user://theme_shots.png.

extends Node

const SHOT := Vector2i(576, 324)   # each shot at half the game's size
const COLS := 2

func _ready():
	_run.call_deferred()

func _run():
	get_window().size = Vector2i(1152, 648)
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://theme_shots.png"
	var level := int(args[1]) if args.size() > 1 else 8   # board level: 8 = the full board, 1 = the first round
	var shots: Array[Image] = []
	for id in BoardThemes.ORDER:
		GameState.run_level = null
		GameState.run_carry = {}
		GameState.next_seed = 7
		var main: Node = load("res://scenes/main.tscn").instantiate()
		main.get_node("Game Manager").prep_time = 9999
		add_child(main)
		for i in 3:
			await get_tree().process_frame
		var board: Board = main.get_node("Board")
		GameState.me.level = level
		board.refresh_unlocks(level, false)
		board.apply_theme(id, 7)
		var units := ["knight", "archer", "mage", "guardian", "berserker"]
		for i in units.size():
			for team in 2:
				var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
				board.get_node("Units").add_child(u)
				u.setup(load("res://tres/%s.tres" % units[i]), team)
				if team == 0:
					board.put_on_tile(u, board.player_order[i])
				else:
					board.put_enemy_on_tile(u, board.enemy_order[i])
		for i in 12:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_BILINEAR)
		shots.append(img)
		print("shot: ", id)
		main.queue_free()
		await get_tree().process_frame
	var rows := ceili(shots.size() / float(COLS))
	var sheet := Image.create_empty(SHOT.x * COLS, SHOT.y * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s := shots[i]
		s.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(s, Rect2i(Vector2i.ZERO, SHOT), Vector2i((i % COLS) * SHOT.x, (i / COLS) * SHOT.y))
	sheet.save_png(out)
	print("sheet -> ", out)
	get_tree().quit()
