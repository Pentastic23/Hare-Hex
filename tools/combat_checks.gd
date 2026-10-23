# combat_checks.gd
# Dev tool, not part of the game: checks that combat and the run RNG are deterministic.
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/combat_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. "-- realtime" instead plays the fixed test fight in
# real time (physics ticks) and prints its SIGNATURE line, so runs at different --fixed-fps values
# can be compared from the command line.

extends Node

var fails := 0
var main: Node
var gm
var board: Board

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func load_main(seed := 0):
	if main != null:
		main.free()
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = seed
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999   # the test starts fights itself
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await get_tree().process_frame
	await get_tree().process_frame

func U(n: String) -> UnitData:
	return load("res://tres/%s.tres" % n)

func I(n: String) -> ItemData:
	return load("res://tres/items/%s.tres" % n)

# A fixed fight: three player units (one 2-star with items) against a four-unit wave.
func setup_fight():
	GameState.me.level = 5
	board.refresh_unlocks(5, false)
	var picks := [["knight", 2, ["longsword", "iron_belt"]], ["archer", 1, []], ["mage", 1, ["mana_charm"]]]
	for i in picks.size():
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(U(picks[i][0]), 0)
		if picks[i][1] > 1:
			u.set_star(picks[i][1])
		var its: Array[ItemData] = []
		for n in picks[i][2]:
			its.append(I(n))
		u.set_items(its)
		board.put_on_tile(u, board.player_order[i])
	var wave := EnemyBoard.new()
	wave.display_name = "Test wave"
	wave.stat_scale = 0.9
	for e in [["thief", Vector2i(3, 3), 1], ["assassin", Vector2i(4, 3), 1], ["archer", Vector2i(3, 2), 1], ["guardian", Vector2i(4, 2), 2]]:
		var bu := BoardUnit.new()
		bu.unit = U(e[0])
		bu.coord = e[1]
		bu.star = e[2]
		wave.units.append(bu)
	var waves: Array[EnemyBoard] = [wave]
	gm.opponents = WaveOpponents.new(waves, 1.0)

func signature() -> String:
	var parts: PackedStringArray = ["won=%s ticks=%d" % [GameState.me.last_combat_won, gm.combat_ticks]]
	for u in gm.combatants:
		parts.append("%s%d@%d,%d dealt=%.3f taken=%.3f" % [u.data.display_name, u.team, u.coord.x, u.coord.y, u.damage_dealt, u.damage_taken])
	return " | ".join(parts)

func _run():
	SaveGame.path = "user://combat_test_save.json"
	if "realtime" in OS.get_cmdline_user_args():
		await load_main(12345)
		setup_fight()
		gm.start_combat()
		await Events.combat_ended
		print("SIGNATURE ", signature())
		get_tree().quit()
		return

	print("--- the same fight, resolved three times")
	var sigs: PackedStringArray = []
	for i in 3:
		await load_main(12345)
		setup_fight()
		gm.start_combat()
		gm.resolve_combat()
		sigs.append(signature())
	print("  ", sigs[0].left(160), " ...")
	chk("identical result, ticks and per-unit damage every time", sigs[0] == sigs[1] and sigs[1] == sigs[2])
	chk("the fight actually happened", gm.combat_ticks > 30 and sigs[0].contains("dealt="))
	print("SIGNATURE ", sigs[0])

	print("--- real time matches instant resolution")
	await load_main(12345)
	setup_fight()
	gm.start_combat()
	await Events.combat_ended
	var live_sig := signature()   # now: enemy units are freed at the end of this frame
	await get_tree().process_frame   # let GameManager finish _end_combat before the next check frees the scene
	chk("physics-driven fight == resolve_combat()", live_sig == sigs[0], live_sig.left(120))

	print("--- node order doesn't matter")
	await load_main(12345)
	setup_fight()
	# Reverse the scene order of all units: acting order and targeting must not change.
	var units_node := board.get_node("Units")
	var kids := units_node.get_children()
	for i in kids.size():
		units_node.move_child(kids[i], 0)
	gm.start_combat()
	gm.resolve_combat()
	chk("reversed node order gives the same fight", signature() == sigs[0])

	print("--- target ties")
	await load_main(12345)
	GameState.me.level = 5
	board.refresh_unlocks(5, false)
	var me := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(me)
	me.setup(U("knight"), 0)
	board.put_on_tile(me, Vector2i(3, 4))
	var foes: Array[Unit] = []
	for c in [Vector2i(4, 3), Vector2i(3, 3)]:   # both 1 tile away
		var e := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(e)
		e.setup(U("thief"), 1)
		board.put_enemy_on_tile(e, c)
		foes.append(e)
	var first := board.nearest_enemy(me)
	board.get_node("Units").move_child(foes[1], 0)
	board.get_node("Units").move_child(foes[0], 0)
	chk("equal distance: the lower tile wins, whatever the node order", first.coord == Vector2i(3, 3) and board.nearest_enemy(me) == first)

	print("--- seeded run RNG")
	var runs := []
	for s in [777, 777, 778]:
		await load_main(s)
		var shops := []
		var enemies := []
		var drops := []
		for r in 5:
			GameState.round_number = r + 1
			gm.roll_shop()
			shops.append(GameState.me.shop_offers.map(func(d): return d.display_name))
			enemies.append(gm.opponents.board_for_round(r + 1).units.map(func(b): return b.unit.display_name))
			drops.append(gm.item_roster[GameState.me.rng.randi_range(0, gm.item_roster.size() - 1)].id)
		runs.append(str([shops, enemies, drops]))
	chk("same seed: same shops, random enemies and drops", runs[0] == runs[1])
	chk("different seed: different results", runs[0] != runs[2])

	print("--- per-player state")
	await load_main(4242)
	var other := PlayerState.new()
	other.id = 1
	other.is_local = false
	other.display_name = "Rival"
	GameState.players.append(other)
	var gold_events := [0]
	var count_gold := func(_g): gold_events[0] += 1
	Events.gold_changed.connect(count_gold)
	other.gold = 99
	chk("another player's gold change doesn't reach the HUD", gold_events[0] == 0 and GameState.me.gold != 99)
	GameState.me.gold = 7
	chk("the local player's does", gold_events[0] == 1)
	Events.gold_changed.disconnect(count_gold)
	GameState.next_seed = 4242
	GameState.begin_run(null, null)
	chk("each player gets their own shop RNG from the one run seed", GameState.me.rng.seed != other.rng.seed and GameState.run_seed == 4242)
	other.gold = 50
	other.add_xp(10)
	other.items.append(I("longsword"))
	GameState.round_number = 9
	GameState.reset()
	chk("GameState.reset() resets every player and the round", other.gold == 2 and other.level == 1 and other.items.is_empty() and GameState.round_number == 1)
	other.loss_streak = 4
	chk("streaks and income are per player", other.streak_bonus() == 2 and GameState.me.streak_bonus() == 0)
	GameState.players.erase(other)

	print("--- empty board slots are filled from the bench when a fight starts")
	await load_main(21)
	GameState.me.level = 4
	board.refresh_unlocks(4, false)
	var mk := func(n: String) -> Unit:
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(U(n), 0)
		return u
	var kn: Unit = mk.call("knight")
	board.put_on_tile(kn, board.player_order[0])
	var gu: Unit = mk.call("guardian")
	var ar: Unit = mk.call("archer")
	var dr: Unit = mk.call("dragon")
	var be: Unit = mk.call("berserker")
	board.put_on_bench(gu, 1)
	board.put_on_bench(ar, 3)
	board.put_on_bench(dr, 5)
	board.put_on_bench(be, 7)
	var open_rows: Array = []
	for key in board.tiles:
		var c: Vector2i = key
		if board.is_player_side(c) and board.is_unlocked(c) and board.tiles[c].occupant == null:
			open_rows.append(c.y)
	gm.start_combat()
	chk("the board fills up to the cap (4), leftmost bench units first", board.units_on_board() == 4 and gu.coord.x >= 0 and ar.coord.x >= 0 and dr.coord.x >= 0 and be.coord.x < 0 and board.bench[7] == be, "%s %s %s %s" % [gu.coord, ar.coord, dr.coord, be.coord])
	chk("melee goes to the front row, ranged to the back", gu.coord.y == open_rows.min() and ar.coord.y == open_rows.max() and ar.coord.y > gu.coord.y, "open rows %s, guardian %s, archer %s" % [open_rows, gu.coord, ar.coord])
	var ar_tile := ar.coord
	gm.resolve_combat()
	await get_tree().process_frame
	chk("auto-placed units stay on the board after the fight", ar.coord == ar_tile and gu.coord.x >= 0 and board.units_on_board() == 4)
	GameState.round_number = 2
	gm.start_combat()
	chk("a full board takes nobody from the bench", be.coord.x < 0 and board.units_on_board() == 4)
	gm.resolve_combat()
	await get_tree().process_frame

	print("--- synergy tiers (docs/synergies-v2.md)")
	await load_main(31)
	GameState.me.level = 10
	board.refresh_unlocks(10, false)
	var team_of := func(names: Array) -> Array:
		var out: Array = []
		for n in names:
			out.append(bare(n))
		return out
	var casters: Array = team_of.call(["cleric", "apprentice", "sprite", "sparkcaller", "mage", "ice_mage", "runesmith", "lich", "archmage"])
	var fx: Dictionary = Synergies.effects_for(casters)
	chk("9 Casters: Archmagi +90% damage and every 3rd attack crits (plus +10% from the 3 Arcane among them)", is_equal_approx(fx[casters[4]].get("dmg", 0.0), 1.0) and int(fx[casters[4]].get("crit", 0)) == 3, str(fx[casters[4]]))
	chk("tiers don't stack: 5 Order units get +50% HP, not 15+25+35+50", is_equal_approx(Synergies.effects_for(team_of.call(["knight", "militia", "guardian", "warlord", "herald"])).values()[0].get("hp", 0.0), 0.5))
	chk("Lich King gives every Undead a revive", is_equal_approx(Synergies.effects_for([bare("deathlord"), bare("ghoul")]).values()[1].get("revive", 0.0), 0.3))
	chk("every trait's tooltip lists one line per tier", Synergies.tooltip("Warrior").split("\n").size() == 5 and Synergies.tooltip("Warrior", 7).contains("> 7:"))

	print("--- synergy mechanics, one at a time")
	await load_main(32)
	GameState.me.level = 10
	board.refresh_unlocks(10, false)
	var a: Unit = place("knight", Vector2i(3, 4))
	var t: Unit = place("knight", Vector2i(3, 3), 1)
	a.apply_synergy({})
	t.apply_synergy({"shield": 0.5})
	a.begin_combat()
	t.begin_combat()
	var full := t.max_hp()
	var took := t.take_damage(100.0, a, true)
	chk("a shield absorbs damage before HP, and counts as damage dealt", is_equal_approx(t.health, full) and is_equal_approx(t.shield, full * 0.5 - 100.0) and is_equal_approx(took, 100.0))
	t.apply_synergy({"revive": 0.3})
	t.begin_combat()
	t.take_damage(full * 5.0, a, true)
	chk("revive: the first killing blow leaves 30% HP", not t.dead and t.revived and is_equal_approx(t.health, full * 0.3))
	t.take_damage(full * 5.0, a, true)
	chk("revive works once", t.dead)
	t = place("knight", Vector2i(2, 3), 1)
	t.apply_synergy({"dodge": 2})
	t.begin_combat()
	var misses: Array = []
	for i in 4:
		misses.append(t.dodges_next())
	chk("dodge: every 2nd attack misses", misses == [false, true, false, true], str(misses))
	t.apply_synergy({})
	t.begin_combat()
	a.apply_synergy({"crit": 2})
	a.begin_combat()
	var hp0 := t.health
	a._attack(t)
	var hit1 := hp0 - t.health
	a._attack(t)
	var hit2 := hp0 - hit1 - t.health
	chk("crit: every 2nd attack deals double", is_equal_approx(hit2, hit1 * 2.0), "%.1f then %.1f" % [hit1, hit2])
	t.begin_combat()
	a.apply_synergy({"curse": 0.25})
	a.begin_combat()
	a._attack(t)
	var cursed_hit := full - t.health
	t.begin_combat()
	t.apply_curse(0.25)
	var before := t.health
	t.take_damage(100.0, a, true)
	chk("curse: the target takes 25% more damage", is_equal_approx(before - t.health, 125.0) and t.curse_on == 0.25 and cursed_hit > 0.0)
	t.begin_combat()
	a.apply_synergy({"burn": 0.05})
	a.begin_combat()
	a._attack(t)
	var after_hit := t.health
	for i in 240:   # 4 s of ticks: the burn lasts 3
		t._tick_effects(gm.COMBAT_TICK)
	chk("burn: 5% of max HP per second for 3 s", absf((after_hit - t.health) - full * 0.05 * 3.0) < full * 0.01 and t.burn_left <= 0.0, "%.1f burned" % (after_hit - t.health))
	t.begin_combat()
	var normal := t.attack_interval()
	t.apply_chill(0.5)
	chk("chill: attack interval doubles at 50%", is_equal_approx(t.attack_interval(), normal * 2.0))
	for i in 150:
		t._tick_effects(gm.COMBAT_TICK)
	chk("chill wears off after 2 s", is_equal_approx(t.attack_interval(), normal))
	t.begin_combat()
	a.apply_synergy({"execute": 0.2, "kill_heal": 0.3})
	a.begin_combat()
	a.health = a.max_hp() * 0.5
	t.health = t.max_hp() * 0.2
	a._attack(t)
	chk("execute: a target left below 20% dies, and the kill heals 30%", t.dead and is_equal_approx(a.health, a.max_hp() * 0.8))
	a.apply_synergy({"ramp": 0.1, "ramp_max": 2})
	a.begin_combat()
	var base_iv := a.attack_interval()
	var t2: Unit = place("guardian", Vector2i(4, 3), 1)
	t2.begin_combat()
	for i in 3:
		a._attack(t2)
	chk("ramp: +10% attack speed per attack, capped at 2 stacks", a.ramp_stacks == 2 and is_equal_approx(a.attack_interval(), base_iv / 1.2))
	a.apply_synergy({"regen": 0.1})
	a.begin_combat()
	a.health = a.max_hp() * 0.5
	for i in 60:
		a._tick_effects(gm.COMBAT_TICK)
	chk("regen: 10% of max HP per second", absf(a.health - a.max_hp() * 0.6) < 1.0)

	print("--- a fight full of mechanics is still deterministic")
	var msigs: PackedStringArray = []
	for i in 2:
		await load_main(4242)
		GameState.me.level = 10
		board.refresh_unlocks(10, false)
		var mine_names := ["imp", "thief", "sprite", "minstrel", "faerie_queen", "pyromancer", "sparkcaller", "ice_mage", "frost_queen", "phoenix"]
		for k in mine_names.size():
			place(mine_names[k], board.player_order[k])
		var wave := EnemyBoard.new()
		for e in [["skeleton", Vector2i(1, 3)], ["ghoul", Vector2i(2, 3)], ["necromancer", Vector2i(3, 2)], ["plague_doctor", Vector2i(4, 2)], ["deathlord", Vector2i(3, 3)], ["reaper", Vector2i(4, 3)], ["assassin", Vector2i(5, 3)], ["nightblade", Vector2i(2, 2)]]:
			var bu := BoardUnit.new()
			bu.unit = UD(e[0])
			bu.coord = e[1]
			wave.units.append(bu)
		var waves: Array[EnemyBoard] = [wave]
		gm.opponents = WaveOpponents.new(waves, 1.0)
		gm.start_combat()
		gm.resolve_combat()
		msigs.append(signature())
		await get_tree().process_frame
	chk("same result twice (tricksters, burns, chills, revives, executes, crits)", msigs[0] == msigs[1], msigs[0].left(120))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

# A unit data by file name, from tres/ or tres/units/.
func UD(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

# A unit of `team` on a tile (player or enemy side), ready for a test.
func place(n: String, c: Vector2i, team := 0) -> Unit:
	var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(u)
	u.setup(UD(n), team)
	if team == 0:
		board.put_on_tile(u, c)
	else:
		board.put_enemy_on_tile(u, c)
	return u

# A unit that isn't on any tile (for trait maths).
func bare(n: String) -> Unit:
	var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(u)
	u.setup(UD(n), 0)
	return u
