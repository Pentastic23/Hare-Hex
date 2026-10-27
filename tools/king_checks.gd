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
	var own_king: King = board.kings[0]
	var foe_king: King = board.kings[1]
	chk("in prep your king faces the camera and theirs faces you", is_equal_approx(own_king.rest_yaw(), PI) and is_equal_approx(foe_king.rest_yaw(), PI))
	gm._enter(Events.Phase.COMBAT)
	chk("when the fight starts your king turns to face the enemy", own_king.fighting and is_equal_approx(own_king.rest_yaw(), 0.0) and own_king._turn != null and own_king._turn.is_running())
	gm.resolve_combat()
	chk("after the fight it turns back to the camera", not own_king.fighting and is_equal_approx(own_king.rest_yaw(), PI))
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
	await _skin_checks()
	await _power_checks()
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

func _ud(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

# A run with `skin` as your king's run power, from a clean state.
func _with_power(skin: StringName) -> PlayerState:
	SaveGame.set_king_skin(String(skin))
	await load_main()
	var p := GameState.me
	p.king_state = {}
	return p

func _skin_checks():
	print("--- king skins: models and attacks")
	var models := true
	for id in KingSkins.ORDER:
		if id != &"shadow" and KingSkins.model(id) == null:
			models = false
	chk("every skin but the Shadow King has its own baked model", models and KingSkins.ORDER.size() == 9)
	await load_main()
	var k: King = board.kings[0]
	k.set_skin(&"shadow", &"dragon")
	chk("the Shadow King wears the opposing king's model, in shadow", k.body.mesh == KingSkins.model(&"dragon") and k.body.material_override == King.shadow_mat())
	k.set_skin(&"merchant", &"dragon")
	chk("any other skin wears its own model", k.body.mesh == KingSkins.model(&"merchant") and k.shape == &"merchant")
	var foe := _unit("guardian", board.enemy_order[0], 1)
	var fired := k.fired
	k.strike(foe)
	chk("a strike plays an animation (wind-up and lunge)", k.animating())
	await get_tree().create_timer(King.WIND_UP + King.LUNGE + 0.05).timeout
	chk("the skin's shot leaves at the lunge", k.fired == fired + 1)
	await get_tree().create_timer(King.RECOVER + 0.5).timeout
	chk("the king settles back where it stood", not k.animating() and k.body.position.is_equal_approx(Vector3(0, 0.01, 0)) and is_equal_approx(k.body.rotation.y, k.rest_yaw()))
	SaveGame.set_king_skin("merchant")
	await load_main()
	chk("your pick is your run power in free play", GameState.me.king == &"merchant" and board.kings[0].skin == &"merchant")
	SaveGame.set_king_skin("lion")
	await load_main()
	chk("the Golden Lion has no run power (its effect is in the fight)", GameState.me.king == &"")

func _power_checks():
	print("--- king run powers")
	var p := await _with_power(&"merchant")
	p.gold = 75
	chk("Merchant King: interest is capped at 7", p.interest_gold() == 7 and KingPowers.interest_cap(p) == 7)
	p.king = &""
	chk("... 5 without it", p.interest_gold() == 5)

	p = await _with_power(&"gambler")
	var lucks := {}
	for r in range(2, 40):
		KingPowers.prep_start(gm.rules, r, false)
		lucks[float(p.king_state.luck)] = true
	chk("Gambler King: the luck changes from round to round (worse and better)", lucks.size() >= 4 and lucks.keys().min() < 0.0 and lucks.keys().max() > 0.0, str(lucks.keys()))
	p.level = 5
	p.king_state.luck = 2.0
	var odds := p.shop_odds()
	var total := 0.0
	for o in odds:
		total += float(o)
	chk("... a JACKPOT rolls with level 7 odds", odds == GameState.odds_for_level(7).map(func(x): return float(x)) and is_equal_approx(total, 100.0), str(odds))
	p.king_state.luck = -0.75
	odds = p.shop_odds()
	chk("... bad luck blends towards a lower level's odds", float(odds[0]) > float(GameState.odds_for_level(5)[0]) and float(odds[0]) < float(GameState.odds_for_level(4)[0]), str(odds))
	var seq := []
	for run in 2:
		p.rng.seed = 77
		var one := []
		for r in range(2, 12):
			KingPowers.prep_start(gm.rules, r, false)
			one.append(p.king_state.luck)
		seq.append(one)
	chk("... the same seed rolls the same luck", seq[0] == seq[1])

	p = await _with_power(&"necromancer")
	for n in ["knight", "archer", "militia"]:
		var u := board.make_unit(_ud(n), gm.unit_scene)
		board.put_on_bench(u, board.first_free_bench())
		board.sell_unit(u)
	chk("Necromancer King: selling stores memories and souls", int(p.king_state.souls) == 3 and p.king_state.memories.size() == 3)
	var bench_before := board.bench.filter(func(u): return u != null).size()
	KingPowers.prep_start(gm.rules, 5, false)
	var raised: Array = board.bench.filter(func(u): return u != null)
	chk("... 3 souls bring back a free copy of a sold unit", raised.size() == bench_before + 1 and int(p.king_state.souls) == 0, "%d -> %d" % [bench_before, raised.size()])

	p = await _with_power(&"explorer")
	KingPowers.prep_start(gm.rules, 2, false)
	chk("Explorer King: a quest appears in round 2", p.king_state.get("quests", []).size() == 1)
	p.king_state.quests = [{"id": "rich", "state": "open"}]
	p.gold = 55
	KingPowers.check(gm.rules)
	chk("... completing it gives a relic", p.king_state.quests[0].state == "done" and p.king_state.get("relics", []).size() == 1)
	p.king_state.quests = [{"id": "no_reroll", "state": "open"}]
	p.level = 3
	p.gold = 20
	p.shop_locked = false
	gm.rules.reroll()
	chk("... rerolling before level 7 fails 'reach level 7 without rerolling'", p.king_state.quests[0].state == "failed")
	p.king_state.relics = ["compass", "drum"]
	var g0 := p.gold
	KingPowers.prep_start(gm.rules, 4, false)
	chk("... relics: the Compass pays 1 gold a round", p.gold == g0 + 1)
	chk("... the War Drum speeds up your units in every fight", is_equal_approx(float(KingPowers.fight_start(gm.rules, []).get("as", 0.0)), 0.10))
	p.king_state.quests = [{"id": "five", "state": "open"}]
	p.king_state.fight_units = 5
	KingPowers.fight_end(gm.rules, true)
	chk("... 'win with exactly 5 units' completes on such a win", p.king_state.quests[0].state == "done")

	p = await _with_power(&"chaos")
	KingPowers.prep_start(gm.rules, 3, false)
	chk("Chaos King: no proclamation on odd rounds", str(p.king_state.decree) == "")
	var seen := {}
	var last := ""
	var repeats := false
	for r in range(2, 60, 2):
		KingPowers.prep_start(gm.rules, r, false)
		var d := str(p.king_state.decree)
		repeats = repeats or d == last
		last = d
		seen[d] = true
	chk("... every other round a proclamation, never the same twice running", seen.size() == KingPowers.DECREES.size() and not seen.has("") and not repeats, str(seen.keys()))
	p.king_state.discount = 3
	p.gold = 20
	var dear: UnitData = null
	for d in gm.roster:
		if d.cost >= 2:
			dear = d
			break
	chk("... Royal Discount: units cost 1 less", p.price(dear) == dear.cost - 1)
	gm.rules.buy(dear, true, false)
	chk("... for the next 3 units only", int(p.king_state.discount) == 2 and p.gold == 20 - (dear.cost - 1))
	p.king_state.fight_fx = {"shield": 0.2}
	var fx := KingPowers.fight_start(gm.rules, [])
	KingPowers.fight_end(gm.rules, true)
	chk("... Iron Decree shields your units for one fight", is_equal_approx(float(fx.get("shield", 0.0)), 0.2) and p.king_state.fight_fx.is_empty())

	p = await _with_power(&"dragon")
	p.gold = 65
	KingPowers.prep_start(gm.rules, 5, false)
	chk("Dragon King: gold above 50 goes into the hoard", p.gold == 50 and int(p.king_state.hoard) == 15)
	var items_before := p.items.size()
	p.gold = 56
	KingPowers.prep_start(gm.rules, 6, false)
	chk("... it grows and pays out treasure as it fills (an item at 20)", int(p.king_state.hoard) == 22 and p.items.size() == items_before + 1, "hoard %d" % int(p.king_state.hoard))
	p.gold = 10
	KingPowers.fight_start(gm.rules, [])
	chk("... a fight started under 20 gold collapses it: half comes back", int(p.king_state.hoard) == 0 and p.gold == 21)

	p = await _with_power(&"fate")
	KingPowers.prep_start(gm.rules, 1, true)
	chk("Fate King: no prophecy in the opening", p.king_state.get("offer", []).is_empty())
	KingPowers.prep_start(gm.rules, 2, false)
	var offer: Array = p.king_state.get("offer", []).duplicate()
	chk("... three prophecies offered after it", offer.size() == 3)
	KingPowers.fight_start(gm.rules, [])
	chk("... not chosen before a fight: the first is taken", str(p.king_state.get("prophecy", "")) == str(offer[0]) and p.king_state.offer.is_empty())
	p.king_state.prophecy = "level9"
	p.level = 9
	var g1 := p.gold
	KingPowers.check(gm.rules)
	chk("... fulfilled: reach level 9 pays 40 gold", bool(p.king_state.get("fulfilled", false)) and p.gold == g1 + 40)
	p.king_state.prophecy = "legend"
	chk("... a lasting prophecy reward reaches every fight", is_equal_approx(float(KingPowers.fight_start(gm.rules, []).get("hp", 0.0)), 0.3))

	p = await _with_power(&"shadow")
	p.gold = 50
	p.level = 6
	var pool_before: Dictionary = gm.shared_pool.remaining.duplicate()
	var state := p.rng.state
	var peek := KingPowers.peek_shop(gm.rules)
	chk("Shadow King: peeking at the next reroll changes nothing", gm.shared_pool.remaining == pool_before and p.rng.state == state and peek.size() == 5)
	gm.rules.reroll()
	chk("... and the reroll offers exactly what it showed", Array(p.shop_offers) == peek, "%s vs %s" % [peek.map(func(d): return d.display_name), Array(p.shop_offers).map(func(d): return d.display_name)])
	var foes := KingPowers.peek_enemy(gm)
	var real: EnemyBoard = gm.opponents.board_for_round(GameState.round_number)
	chk("... the coming random enemies are the ones it showed", foes.map(func(f): return f[0]) == real.units.map(func(bu): return bu.unit) and not foes.is_empty())
	var left_dock = main.find_child("LeftDock", true, false)
	left_dock.show_tab("king")
	await frames(3)
	chk("... the King tab shows the forbidden knowledge", left_dock.king.summary().contains("Shadow King") and left_dock.king.body.get_child_count() > 4)
	p = await _with_power(&"fate")
	KingPowers.prep_start(gm.rules, 2, false)
	await frames(3)
	left_dock = main.find_child("LeftDock", true, false)
	chk("a prophecy to choose opens the King tab, with a badge", left_dock.tab == "king" and left_dock.king.pending() == 1)
	var chosen: String = p.king_state.offer[1]
	gm.choose_prophecy(1)
	chk("... choosing one sets it", str(p.king_state.get("prophecy", "")) == chosen and left_dock.king.pending() == 0)
	left_dock.show_tab("synergies")
	SaveGame.set_king_skin("lion")
