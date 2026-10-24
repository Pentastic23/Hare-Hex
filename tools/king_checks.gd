# king_checks.gd
# Dev tool, not part of the game: checks the two kings (king.gd): one extra hex left of each side of the
# board that follows the board as it grows, with a locked placeholder cylinder on it. Run from the
# project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/king_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway save and settings files.

extends Node

var fails := 0
var main: Node
var gm
var board: Board

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func frames(n := 2):
	for i in n:
		await get_tree().process_frame

func load_main():
	if main != null:
		main.free()
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 4242
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await frames(3)

# Nearest open tile of a side, from a world position (flat distance), and the leftmost open tile's x.
func nearest_open(team: int, p: Vector3) -> float:
	var best := INF
	for c in board.unlocked:
		if board.is_player_side(c) != (team == 0):
			continue
		var w := board.grid_to_world(c)
		best = minf(best, Vector2(p.x - w.x, p.z - w.z).length())
	return best

func leftmost_open(team: int) -> float:
	var best := INF
	for c in board.unlocked:
		if board.is_player_side(c) == (team == 0):
			best = minf(best, board.grid_to_world(c).x)
	return best

func _run():
	SaveGame.path = "user://king_test_save.json"
	SaveGame.reset_progress()
	Settings.path = "user://king_test_settings.cfg"
	Settings._loaded = true
	Settings.reduce_motion = false
	await load_main()
	var w := Board.HEX * sqrt(3.0)

	print("--- one king per side")
	chk("the board has two kings, player's first", board.kings.size() == 2 and board.kings[0].team == 0 and board.kings[1].team == 1)
	chk("king_of(team) finds them", board.king_of(0) == board.kings[0] and board.king_of(1) == board.kings[1] and board.king_of(2) == null)
	chk("both are in the 'kings' group, under the board's Kings node", get_tree().get_nodes_in_group("kings").size() == 2 and board.kings[0].get_parent() == board.get_node("Kings"))
	chk("each has a placeholder cylinder", board.kings.all(func(k): return k.body != null and k.body.mesh is CylinderMesh))
	chk("in the team colours (your blue, the enemy's orange)", (board.kings[0].body.material_override as StandardMaterial3D).albedo_color == Unit.RING_COLORS[0] and (board.kings[1].body.material_override as StandardMaterial3D).albedo_color == Unit.RING_COLORS[1])
	chk("the hex under each is dressed like a board tile (theme textures)", board.kings.all(func(k): return (k.get_node("MeshInstance3D") as MeshInstance3D).get_surface_override_material(0) != null))

	print("--- not units")
	chk("they aren't Units, and aren't in the Units node", board.kings.all(func(k): return not (k is Unit) and k.get_parent() != board.get_node("Units")))
	chk("no tile, bench slot or team count includes them", board.units_on_board() == 0 and board.all_player_units().is_empty() and board.bench.all(func(b): return b == null) and board.tiles.values().all(func(t): return t.occupant == null))
	chk("nothing to pick: no collision shapes (drags, sells and clicks pass through)", board.kings.all(func(k): return k.find_children("*", "CollisionObject3D", true, false).is_empty()))
	chk("both are locked", board.kings.all(func(k): return k.locked))

	print("--- at the left edge of the open board, growing with it")
	var last_x := [INF, INF]
	var ok_edge := true
	var ok_touch := true
	var ok_clear := true
	var detail := ""
	for level in range(1, 9):
		GameState.me.level = level
		board.refresh_unlocks(level, false)
		for team in 2:
			var k := board.kings[team]
			var left := leftmost_open(team)
			var near := nearest_open(team, k.position)
			if not (k.position.x < left):
				ok_edge = false
				detail += " L%d/t%d not left (%.2f vs %.2f)" % [level, team, k.position.x, left]
			if absf(near - w) > 0.01:
				ok_touch = false
				detail += " L%d/t%d nearest open tile %.2f away" % [level, team, near]
			if near < w - 0.01:
				ok_clear = false
			if k.position.x > last_x[team] + 0.001:
				ok_edge = false
				detail += " L%d/t%d moved right" % [level, team]
			last_x[team] = k.position.x
	chk("left of every open tile on its side, at every level 1-8", ok_edge, detail)
	chk("touching the board's edge (one hex from the nearest open tile)", ok_touch, detail)
	chk("never on an open tile", ok_clear)
	chk("full board: the player's king is left of row 5, the enemy's left of row 2", is_equal_approx(board.kings[0].position.x, board.grid_to_world(Vector2i(0, 5)).x - w) and is_equal_approx(board.kings[1].position.x, board.grid_to_world(Vector2i(0, 2)).x - w))
	chk("and stands in its own row (z of row 5 / row 2)", is_equal_approx(board.kings[0].position.z, Board.HEX * 1.5 * 5) and is_equal_approx(board.kings[1].position.z, Board.HEX * 1.5 * 2))
	board.refresh_unlocks(1, false)
	var p1 := board.kings[0].position
	board.refresh_unlocks(8, false)
	chk("it moved outwards as the board grew (level 1 -> 8)", board.kings[0].position.x < p1.x - w, "%s -> %s" % [p1, board.kings[0].position])
	chk("the two sides mirror: same level, same distance from the middle column row-wise",
		is_equal_approx(board.kings[0].position.x - board.grid_to_world(Vector2i(0, 5)).x, board.kings[1].position.x - board.grid_to_world(Vector2i(0, 2)).x))

	print("--- sliding")
	board.refresh_unlocks(1, false)
	var from_x: float = board.kings[0].position.x
	board.refresh_unlocks(8, true)
	chk("with animation it doesn't jump (still on its way right after)", absf(board.kings[0].position.x - board.king_spot(0).x) > 0.5 and is_equal_approx(board.kings[0].position.x, from_x))
	await get_tree().create_timer(King.SLIDE + 0.25).timeout
	chk("and arrives", board.kings[0].position.is_equal_approx(board.king_spot(0)) and board.kings[1].position.is_equal_approx(board.king_spot(1)))
	Settings.reduce_motion = true
	board.refresh_unlocks(1, true)
	chk("Reduce motion: it jumps at once", board.kings[0].position.is_equal_approx(board.king_spot(0)))
	Settings.reduce_motion = false

	print("--- they stay for good")
	await load_main()
	GameState.me.level = 5
	board.refresh_unlocks(5, false)
	for i in 3:
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(load("res://tres/%s.tres" % ["knight", "archer", "mage"][i]), 0)
		board.put_on_tile(u, board.player_order[i])
	var wave := EnemyBoard.new()
	wave.display_name = "Test wave"
	wave.stat_scale = 0.9
	for e in [["thief", Vector2i(3, 3), 1], ["guardian", Vector2i(4, 3), 1]]:
		var bu := BoardUnit.new()
		bu.unit = load("res://tres/%s.tres" % e[0])
		bu.coord = e[1]
		bu.star = e[2]
		wave.units.append(bu)
	var waves: Array[EnemyBoard] = [wave]
	gm.opponents = WaveOpponents.new(waves, 1.0)
	var spots := [board.kings[0].position, board.kings[1].position]
	gm.start_combat()
	gm.resolve_combat()
	chk("a whole fight leaves both kings where they were", board.kings.size() == 2 and board.kings.all(func(k): return is_instance_valid(k) and k.is_inside_tree()) and board.kings[0].position.is_equal_approx(spots[0]) and board.kings[1].position.is_equal_approx(spots[1]))
	chk("and the fight ignored them (only the five units fought)", gm.combatants.size() == 5)
	await get_tree().process_frame

	print("--- the theme")
	var before: Material = (board.kings[0].get_node("MeshInstance3D") as MeshInstance3D).get_surface_override_material(0)
	board.apply_theme(&"volcano")
	var after: Material = (board.kings[0].get_node("MeshInstance3D") as MeshInstance3D).get_surface_override_material(0)
	chk("changing the board theme re-skins the king hexes too", after != null and after != before)

	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

func _ready():
	_run.call_deferred()
