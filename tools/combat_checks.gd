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
	chk("physics-driven fight == resolve_combat()", signature() == sigs[0], signature().left(120))

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

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
