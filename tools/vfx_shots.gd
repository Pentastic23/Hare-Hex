# vfx_shots.gd
# Dev tool, not part of the game: starts a fight full of casters (everyone at full mana) and saves
# frames from it as one sheet, to look at the spell effects. Needs a real window (not --headless):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/vfx_shots.tscn -- <output.png> [theme]

extends Node

const SHOT := Vector2i(576, 324)
const TIMES := [0.15, 0.45, 0.9, 1.6, 2.6, 3.8]

func _ready():
	_run.call_deferred()

func UD(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

func _run():
	get_window().size = Vector2i(1152, 648)
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://vfx_shots.png"
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 11
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	for i in 3:
		await get_tree().process_frame
	var gm = main.get_node("Game Manager")
	var board: Board = main.get_node("Board")
	if args.size() > 1:
		board.apply_theme(StringName(args[1]))
	GameState.me.level = 9
	board.refresh_unlocks(9, false)
	var mine := ["frost_giant", "pyromancer", "sparkcaller", "paladin", "bard", "mage", "dragon", "necromancer", "phoenix"]
	for i in mine.size():
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(UD(mine[i]), 0)
		u.mana = u.data.max_mana
		board.put_on_tile(u, board.player_order[i])
	var wave := EnemyBoard.new()
	wave.display_name = "Casters"
	for e in [["guardian", Vector2i(3, 3)], ["ice_mage", Vector2i(4, 2)], ["faerie_queen", Vector2i(2, 2)], ["archdemon", Vector2i(3, 1)], ["frost_queen", Vector2i(5, 1)], ["treant", Vector2i(4, 3)], ["shadowfist", Vector2i(2, 3)]]:
		var bu := BoardUnit.new()
		bu.unit = UD(e[0])
		bu.coord = e[1]
		wave.units.append(bu)
	var waves: Array[EnemyBoard] = [wave]
	gm.opponents = WaveOpponents.new(waves, 1.0)
	gm.start_combat()
	for u in gm.combatants:
		u.mana = u.data.max_mana
	var shots: Array[Image] = []
	var t0 := Time.get_ticks_msec()
	for t in TIMES:
		while Time.get_ticks_msec() - t0 < t * 1000.0:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBA8)
		shots.append(img)
	var sheet := Image.create_empty(SHOT.x * 2, SHOT.y * 3, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, SHOT), Vector2i((i % 2) * SHOT.x, (i / 2) * SHOT.y))
	sheet.save_png(out)
	print("sheet -> ", out)
	get_tree().quit()
