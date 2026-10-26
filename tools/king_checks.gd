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
	chk("each stands as its skin's voxel model (the Golden Lion)", board.kings.all(func(k): return k.body != null and k.body.mesh != null and k.body.mesh.resource_path.ends_with("/kings/lion.res")))
	chk("the enemy's in darker rival colours, each with an outline in its team colour", board.kings[0].body.material_override == null and board.kings[1].body.material_override != null and board.kings[0]._mats[0].albedo_color == Unit.RING_COLORS[0] and board.kings[1]._mats[0].albedo_color == Unit.RING_COLORS[1])
	chk("the hex under each is dressed like a board tile (the biome's voxel tile)", board.kings.all(func(k): return (k.get_node("MeshInstance3D") as MeshInstance3D).mesh.resource_path.contains("/base_")))

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
	var before: Mesh = (board.kings[0].get_node("MeshInstance3D") as MeshInstance3D).mesh
	board.apply_theme(&"volcano")
	var after: Mesh = (board.kings[0].get_node("MeshInstance3D") as MeshInstance3D).mesh
	chk("changing the board theme re-skins the king hexes too", after != null and after != before)


	print("--- what kings do in a fight")
	await load_main()
	var runner: CombatRunner = gm.runner
	GameState.me.level = 4
	board.refresh_unlocks(4, false)
	var mine: Array[Unit] = []
	var theirs: Array[Unit] = []
	for i in 3:
		mine.append(_unit("guardian", board.player_order[i], 0))
		theirs.append(_unit("guardian", board.enemy_order[i], 1))
	runner.king_skins = [KingSkins.DEFAULT, &""]
	runner.king_levels = [4, 4]
	runner.king_seed = 99
	runner.start()
	var before_mine := mine.map(func(u): return u.health + u.shield)
	var before_theirs := theirs.map(func(u): return u.health + u.shield)
	runner.ticks = CombatRunner.KING_PERIOD - 1
	runner._kings_act()
	var hit_theirs := 0
	var lost_theirs := 0.0
	for i in 3:
		var d: float = before_theirs[i] - (theirs[i].health + theirs[i].shield)
		if d > 0.01:
			hit_theirs += 1
			lost_theirs = d
	chk("your king strikes one random enemy unit for 30 + 10 per level (70 at level 4, before armour)", hit_theirs == 1 and lost_theirs > 0.0 and lost_theirs <= 70.0, "%d hit for %.1f" % [hit_theirs, lost_theirs])
	var shielded := mine.filter(func(u): return u.ab_shield > 0.0)
	chk("the Golden Lion shields one random ally: 35% of its max HP", shielded.size() == 1 and is_equal_approx(shielded[0].ab_shield, shielded[0].max_hp() * KingSkins.SHIELD_SHARE))
	chk("the enemy king strikes too, but has no skin effect (no shields on its side)", theirs.all(func(u): return u.ab_shield == 0.0))
	var hidden := theirs.filter(func(u): return not u.dead)
	for u in hidden:
		u.untargetable_left = 5.0
	var hp_hidden := hidden.map(func(u): return u.health)
	runner._kings_act()
	chk("a hidden unit can't be struck", hidden.map(func(u): return u.health) == hp_hidden)
	runner.stop()

	print("--- kings keep fights deterministic")
	var sigs: PackedStringArray = []
	for run in 2:
		await load_main()
		GameState.next_seed = 5
		GameState.me.level = 6
		board.refresh_unlocks(6, false)
		for i in 4:
			_unit(["knight", "archer", "mage", "cleric"][i], board.player_order[i], 0)
			_unit(["thief", "guardian", "hunter", "berserker"][i], board.enemy_order[i], 1)
		gm.runner.king_skins = [KingSkins.DEFAULT, &""]
		gm.runner.king_levels = [6, 6]
		gm.runner.king_seed = 1234
		gm.runner.start()
		while gm.runner.fighting and gm.runner.ticks < 2400:
			gm.runner.tick()
		var parts: PackedStringArray = ["ticks=%d" % gm.runner.ticks]
		for u in gm.runner.combatants:
			if is_instance_valid(u):
				parts.append("%s%d hp=%.2f sh=%.2f" % [u.data.display_name, u.team, u.health, u.shield])
		sigs.append(" | ".join(parts))
		gm.runner.stop()
	chk("the same fight with kings twice gives the same result", sigs[0] == sigs[1], sigs[0].left(120))
	var desc := {"id": 7, "round": 3, "home_level": 5, "away_level": 2, "home_king": "lion", "away_king": "nope"}
	var r := CombatRunner.new()
	Arena.set_kings(r, desc)
	chk("a lobby fight description sets both kings (unknown skins become none)", r.king_skins == [&"lion", &""] and r.king_levels == [5, 2] and r.king_seed == hash([7, 3]))
	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

func _ready():
	_run.call_deferred()

# A unit of `team` on a tile, ready to fight (no synergies).
func _unit(n: String, c: Vector2i, team: int) -> Unit:
	var p := "res://tres/units/%s.tres" % n
	var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(u)
	u.setup(load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n), team)
	board.put_enemy_on_tile(u, c)
	u.begin_combat()
	return u
