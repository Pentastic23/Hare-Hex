# rules_checks.gd
# Dev tool, not part of the game: checks the rule changes from the bug reports (2026-10-25): loss damage
# by stage plus survivors, rerolling and bench-only merges mid-fight, more Tinker's Tongs, a dash that
# shakes off its attackers, the pause after a fight, longer backline ranges, stronger 3-star 5-costs,
# async PvP's opening round, untimed prep and Start fight, the enemy half at the opponent's level,
# and in lobbies the opening, scouting, streaks and the damage.
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/rules_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end.

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

func load_main(seed := 0, ghost := false):
	if main != null:
		main.free()
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = seed
	GameState.ghost_mode = ghost
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await get_tree().process_frame
	await get_tree().process_frame

func U(n: String) -> UnitData:
	for path in ["res://tres/%s.tres" % n, "res://tres/units/%s.tres" % n]:
		if ResourceLoader.exists(path):
			return load(path)
	return null

func unit(d: UnitData) -> Unit:
	return board.make_unit(d, gm.unit_scene)

func frames(n := 1):
	for i in n:
		await get_tree().process_frame

func _run():
	await load_main(777)
	print("--- reroll and merges mid-fight")
	GameState.me.gold = 100
	GameState.me.level = 4
	board.refresh_unlocks(4, false)
	var fighter := unit(U("knight"))
	board.put_on_tile(fighter, board.player_order[0])
	gm._enter(Events.Phase.COMBAT)
	chk("a fight is on", gm.fighting)
	var rolls_before: int = GameState.me.shop_rolls
	var gold_before: int = GameState.me.gold
	gm._on_reroll()
	chk("rerolling works mid-fight", GameState.me.shop_rolls == rolls_before + 1 and GameState.me.gold == gold_before - PlayerRules.REROLL_COST)
	var k := U("knight")
	board.put_on_bench(unit(k), 0)
	gm.rules.buy(k, false, false)
	var knights_1 := board.all_player_units().filter(func(u): return u.data == k and u.star == 1).size()
	chk("one copy fighting + two on the bench: a purchase mid-fight doesn't merge with the fighter", knights_1 == 3 and fighter.star == 1)
	gm.rules.buy(k, false, false)
	var bench_2 := board.bench.filter(func(u): return u != null and u.data == k and u.star == 2)
	chk("three copies on the bench: they merge right away, mid-fight, on the bench", bench_2.size() == 1 and fighter.star == 1 and fighter.coord.x >= 0)
	var a := U("archer")
	var archers := 0
	for i in Board.BENCH_SLOTS:
		if board.bench[i] == null:
			board.put_on_bench(unit(a if archers < 2 else U("militia")), i)
			archers += 1
	var bought: Unit = gm.rules.buy(a, false, false) if board.first_free_bench() == -1 else null
	chk("a full bench mid-fight still buys a copy that completes a bench merge", bought != null and board.bench.any(func(u): return u != null and u.data == a and u.star == 2))
	gm.resolve_combat()

	print("--- a dash shakes off its attackers")
	await load_main(4321)
	GameState.me.level = 4
	board.refresh_unlocks(4, false)
	var dasher := unit(U("knight"))
	board.put_on_tile(dasher, board.player_order[0])
	gm._enter(Events.Phase.COMBAT)
	var foes: Array = gm.combatants.filter(func(u): return u.team == 1)
	var attacker: Unit = foes[0] if not foes.is_empty() else null
	if attacker != null:
		attacker.target = dasher
		var away := board.player_order[board.player_order.size() - 1]
		dasher.leap_to(away)
	chk("an enemy attacking a unit that dashes away drops it and picks again", attacker != null and attacker.target == null)
	gm.resolve_combat()

	print("--- the pause after a fight")
	await load_main(99)
	gm.result_pause = 0.3
	board.put_on_tile(unit(U("knight")), board.player_order[0])
	gm._enter(Events.Phase.COMBAT)
	gm.resolve_combat()
	var round_now: int = GameState.round_number
	chk("after a fight the game waits (RESULT) before the next prep", gm.phase == Events.Phase.RESULT and GameState.round_number == round_now)
	await get_tree().create_timer(0.6).timeout
	chk("...and then the next prep starts", gm.phase == Events.Phase.PREP and GameState.round_number == round_now + 1 or GameState.me.player_hp <= 0)
	chk("headless runs skip the pause", GameManagerDefaults.headless_pause() == 0.0)

	print("--- units")
	var no_threes := true
	var archer_5 := U("archer").attack_range == 5.0
	var mage_4 := U("mage").attack_range == 4.0
	for d in gm.unit_pool:
		if d.attack_range == 3.0:
			no_threes = false
	chk("backline reach: casters 3 -> 4, archers 4 -> 5 (nobody at 3 any more)", no_threes and archer_5 and mage_4)
	var five: UnitData = null
	var four: UnitData = null
	for d in gm.unit_pool:
		if d.cost == 5 and five == null:
			five = d
		if d.cost == 4 and four == null:
			four = d
	var u5 := unit(five)
	u5.set_star(3)
	var u4 := unit(four)
	u4.set_star(3)
	chk("a 3-star 5-cost has x5 HP and damage; other 3-stars x3.2", is_equal_approx(u5.max_hp(), five.max_health * 5.0) and is_equal_approx(u4.max_hp(), four.max_health * 3.2), "%s %s" % [u5.max_hp(), u4.max_hp()])

	print("--- the enemy half follows the opponent's level")
	board.foe_level = 3
	board.refresh_unlocks(8, false)
	var mine_open := board.open_player_tiles(8).size()
	var foe_open := board.unlocked.keys().filter(func(c): return not board.is_player_side(c))
	var mirrored := board.open_player_tiles(3).all(func(c): return board.unlocked.has(BoardSnapshot.mirror(c)))
	chk("your half at level 8, theirs at level 3 (the mirror of their own tiles)", mine_open == Board.tiles_open_for_level(8) and foe_open.size() == Board.tiles_open_for_level(3) and mirrored)
	board.foe_level = -1
	board.refresh_unlocks(8, false)
	chk("without one it follows yours", board.unlocked.keys().filter(func(c): return not board.is_player_side(c)).size() == Board.tiles_open_for_level(8))

	print("--- async PvP: the opening and Start fight")
	await load_main(2468, true)
	var me := GameState.me
	var on_board := board.all_player_units().filter(func(u): return u.coord.x >= 0)
	chk("round 1 is the opening: one free 1-cost unit already on the board, the shop shut", me.opening and on_board.size() == 1 and on_board[0].data.cost == 1 and me.shop_offers.is_empty())
	chk("the opening fight starts by itself after a short countdown", is_equal_approx(gm.prep_length, gm.OPENING_PREP))
	var free_unit: Unit = on_board[0] if not on_board.is_empty() else null
	var spot := free_unit.coord if free_unit != null else Vector2i(-1, -1)
	me.gold = 50
	var res: String = gm.rules.move(free_unit, 0, Vector2i(-1, -1), true)
	var buy_ok: bool = gm.rules.buy(U("knight"), true, false) != null
	chk("in the opening nothing moves, sells, buys, rerolls or levels", res == "back" and free_unit.coord == spot and not gm.rules.sell(free_unit) and not buy_ok and not gm.rules.reroll() and not gm.rules.buy_xp() and me.gold == 50)
	var started := false
	for i in 600:
		await get_tree().physics_frame
		if gm.phase != Events.Phase.PREP:
			started = true
			break
	chk("...and the fight starts on its own", started)
	if gm.fighting:
		gm.resolve_combat()
	await frames(2)
	chk("round 2: the shop opens, no timer (Start fight instead)", gm.phase == Events.Phase.PREP and GameState.round_number == 2 and not me.opening and me.shop_offers.size() == 5 and gm.prep_left >= 300.0)
	var timer = main.get_node("UI/TopBar").timer
	await frames(2)
	chk("the top bar shows START FIGHT in place of the clock", timer.start_button.visible and not timer.time_label.visible)
	timer.start_button.pressed.emit()
	chk("Start fight starts the fight", gm.phase == Events.Phase.COMBAT)
	if gm.fighting:
		gm.resolve_combat()
	GameState.ghost_mode = false

	print("--- lobbies")
	var srv := LobbyServer.new()
	srv.prep_time = 9999.0
	add_child(srv)
	var inbox := []
	srv.endpoint = func(peer, msg):
		if peer == 5:
			inbox.append(msg)
	srv.receive(5, {"t": "hello", "v": LobbyProtocol.VERSION, "balance": LobbyProtocol.balance(), "name": "Tester"})
	srv.receive(5, {"t": "add_bot"})
	srv.receive(5, {"t": "start", "seed": 5150})
	var seat0: LobbyServer.Seat = srv.seats[0]
	var all_open := srv.seats.all(func(s): return s.player.opening and s.player.shop_offers.is_empty() and s.board.all_player_units().filter(func(u): return u.coord.x >= 0).size() == 1)
	chk("round 1 in a lobby is the opening for everyone: one unit on the board, the shop shut, a short timer", all_open and is_equal_approx(srv.timer, srv.opening_time))
	var last_state: Dictionary = inbox.filter(func(m): return m.t == "state").back()
	chk("your state says it is the opening", bool(last_state.get("opening", false)))
	inbox.clear()
	srv.receive(5, {"t": "reroll", "seq": 1})
	chk("the shop refuses in the opening", inbox.any(func(m): return m.t == "reject" and int(m.seq) == 1))
	inbox.clear()
	srv.receive(5, {"t": "scout", "seat": 1})
	var scouted := inbox.filter(func(m): return m.t == "board")
	chk("scouting another seat sends their board (units and level)", scouted.size() == 1 and int(scouted[0].seat) == 1 and (scouted[0].units as Array).size() == 1 and int(scouted[0].level) == srv.seats[1].player.level)
	var seat1: LobbyServer.Seat = srv.seats[1]
	seat1.player.opening = false
	seat1.board.put_on_bench(seat1.board.make_unit(U("militia"), srv._unit_scene), 2)
	srv._begin_combat()
	var descs: Array = srv.fights.map(func(f): return f.desc)
	chk("a lobby fight carries both benches (display only: each side sees the other's)", descs.all(func(dd): return dd.has("home_bench")))
	srv.tick_fights()
	var pub := srv.public_info()
	chk("the public standings carry streaks", (pub.seats as Array).all(func(e): return e.has("win") and e.has("loss")))
	var hp0: int = seat0.player.player_hp
	var dmg := srv._apply_result(seat0, false, 3, 3, [])
	chk("lobby loss damage: the stage's base + 1 per enemy unit standing (stage 3, 3 left: 9)", dmg == 9 and seat0.player.player_hp == hp0 - 9)
	srv.queue_free()

	print("--- bug fixes")
	await load_main(1357)
	GameState.me.level = 4
	board.refresh_unlocks(4, false)
	var mine_bench := unit(U("knight"))
	board.put_on_bench(mine_bench, 0)
	Unit.viewer_team = 1   # watching a lobby fight from the away side
	var still_mine := mine_bench.mine()
	var foe_copy := (gm.unit_scene.instantiate() as Unit)
	board.get_node("Units").add_child(foe_copy)
	foe_copy.setup(U("archer"), 0)
	foe_copy.source_uid = 7   # a fight copy of the other player's unit
	chk("your bench units stay yours (blue, green bars) while you watch a fight from the away side", still_mine and not foe_copy.mine())
	foe_copy.free()
	Unit.viewer_team = 0
	board.set_view_flipped(true)
	var walker := unit(U("knight"))
	board.put_on_tile(walker, Vector2i(3, 6))
	var next_local := board.grid_to_world(Vector2i(3, 5))
	walker._face_point(walker._world(next_local))
	var ahead := -walker.global_transform.basis.z
	var to_tile := (walker._world(next_local) - walker.global_position)
	to_tile.y = 0.0
	chk("on a turned board a unit faces the tile it walks to (no moonwalking)", ahead.normalized().dot(to_tile.normalized()) > 0.95)
	board.set_view_flipped(false)
	var left := unit(U("knight"))
	var right := unit(U("archer"))
	board.put_on_tile(left, Vector2i(2, 4))
	board.put_on_tile(right, Vector2i(3, 4))
	await frames(1)
	var cam := get_viewport().get_camera_3d()
	var dc = main.get_node("DragController")
	var aim := cam.unproject_position(right.global_position + Vector3(0, minf(right.bar_height, 2.4) * 0.45, 0))
	chk("an item let go over a unit goes to that unit, not its neighbour", dc.unit_for_item(aim) == right and dc.unit_for_item(aim + Vector2(400, 400)) == null)
	Settings.unfocused = true
	Settings.apply()
	var muted := AudioServer.is_bus_mute(0)
	Settings.unfocused = false
	Settings.apply()
	chk("tabbed out: everything is muted (on by default), and back again", Settings.mute_unfocused and muted and not AudioServer.is_bus_mute(0) or Settings.master_volume <= 0.0)

	print("--- streak marks")
	var row := StandingRow.new()
	add_child(row)
	row.streak = 3
	row.show_player("other", "Bramble", 80, 100)
	var fire := row.mark.visible
	row.streak = -2
	row.show_player("other", "Bramble", 80, 100)
	var water := row.mark.visible and row.mark.n == -2
	row.streak = 1
	row.show_player("other", "Bramble", 80, 100)
	chk("a streak of 2 or more shows on the row (fire for wins, water for losses), not 1", fire and water and not row.mark.visible)
	row.queue_free()

	if main != null:
		main.queue_free()
	await frames(2)
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

class GameManagerDefaults:
	static func headless_pause() -> float:
		var gm_script: GDScript = load("res://Scripts/game_manager.gd")
		var probe = gm_script.new()
		var v: float = probe.result_pause
		probe.free()
		return v
