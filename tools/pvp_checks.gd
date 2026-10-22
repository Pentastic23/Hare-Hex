# pvp_checks.gd
# Dev tool, not part of the game: headless checks for async PvP (ghost opponents): board mirroring,
# snapshots, the local store, the ghost provider and its fallback, the top bar label, and that a
# ghost fight is deterministic. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/pvp_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway snapshot, save and settings files.

extends Node

var fails := 0
var main: Node
var gm
var board: Board
const ROOT := "user://pvp_test_snapshots"

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func U(n: String) -> UnitData:
	return load("res://tres/%s.tres" % n)

func I(n: String) -> ItemData:
	return load("res://tres/items/%s.tres" % n)

func wipe(path: String):
	var abs := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for d in DirAccess.get_directories_at(abs):
		wipe(path + "/" + d)
	for f in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs + "/" + f)
	DirAccess.remove_absolute(abs)

func load_main(seed := 0, ghost := false):
	if main != null:
		main.free()
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = seed
	GameState.ghost_mode = ghost
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999   # the checks start fights themselves
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await get_tree().process_frame
	await get_tree().process_frame

# A player board: Knight (2 stars, 2 items) at (3,4), Archer at (4,4), Mage (1 item) at (2,5).
func place_player_units() -> Array:
	GameState.me.level = 5
	board.refresh_unlocks(5, false)
	var out := []
	var spec := [["knight", 2, ["longsword", "iron_belt"], Vector2i(3, 4)], ["archer", 1, [], Vector2i(4, 4)], ["mage", 1, ["mana_charm"], Vector2i(2, 5)]]
	for s in spec:
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(U(s[0]), 0)
		if s[1] > 1:
			u.set_star(s[1])
		var its: Array[ItemData] = []
		for n in s[2]:
			its.append(I(n))
		u.set_items(its)
		board.put_on_tile(u, s[3])
		out.append(u)
	return out

func meta(run: String, round: int, level: int, balance: String) -> Dictionary:
	return {"name": "You", "run": run, "round": round, "stage": "2-%d" % round, "level": level, "hp": 74, "balance": balance}

func signature() -> String:
	var parts: PackedStringArray = ["won=%s ticks=%d" % [GameState.me.last_combat_won, gm.combat_ticks]]
	for u in gm.combatants:
		parts.append("%s%d@%d,%d dealt=%.3f taken=%.3f" % [u.data.display_name, u.team, u.coord.x, u.coord.y, u.damage_dealt, u.damage_taken])
	return " | ".join(parts)

func _run():
	SaveGame.path = "user://pvp_test_save.json"
	LocalSnapshotStore.root = ROOT
	wipe(ROOT)

	print("--- mirroring")
	var rot_ok := true
	var dist_ok := true
	var all: Array[Vector2i] = []
	for y in Board.ROWS:
		for x in Board.COLS:
			all.append(Vector2i(x, y))
	for c in all:
		var m := BoardSnapshot.mirror(c)
		var p := Vector3(Board.HEX * sqrt(3.0) * (c.x + 0.5 * (c.y & 1)), 0, Board.HEX * 1.5 * c.y)
		var q := Vector3(Board.HEX * sqrt(3.0) * (m.x + 0.5 * (m.y & 1)), 0, Board.HEX * 1.5 * m.y)
		# a 180 degree turn about the board center: positions add up to a constant
		if not is_equal_approx(p.x + q.x, Board.HEX * sqrt(3.0) * 6.5) or not is_equal_approx(p.z + q.z, Board.HEX * 1.5 * 7.0):
			rot_ok = false
		for d in all:
			if Board.hex_distance(c, d) != Board.hex_distance(BoardSnapshot.mirror(c), BoardSnapshot.mirror(d)):
				dist_ok = false
	chk("mirroring is an exact 180 degree turn of the board", rot_ok)
	chk("it keeps hex distances (so neighbours stay neighbours)", dist_ok)
	chk("it is its own inverse and maps player rows 4-7 onto enemy rows 3-0", all.all(func(c): return BoardSnapshot.mirror(BoardSnapshot.mirror(c)) == c and (c.y >= 4) == (BoardSnapshot.mirror(c).y <= 3)))

	await load_main(111)
	var mine := place_player_units()
	var units: Array = gm.unit_pool
	var items: Array = gm.item_roster
	var balance: String = BoardSnapshot.balance_hash(units, items)

	print("--- snapshot")
	var snap := BoardSnapshot.capture(mine, meta("runA", 9, 5, balance))
	chk("snapshot is valid and records the metadata", BoardSnapshot.is_valid(snap) and snap.round == 9 and snap.player_level == 5 and snap.hp == 74 and snap.name == "You" and snap.balance == balance)
	var b := BoardSnapshot.to_board(JSON.parse_string(JSON.stringify(snap)), units, items)
	chk("snapshot survives JSON and rebuilds an enemy board of 3 units", b.units.size() == 3 and b.display_name == "Ghost of You" and b.use_synergies and is_equal_approx(b.stat_scale, 1.0))
	var knight_ghost: BoardUnit = b.units.filter(func(u): return u.unit.display_name == "Knight")[0]
	chk("stars, items and mirrored tile are kept (Knight (3,4) -> (3,3))", knight_ghost.star == 2 and knight_ghost.items.map(func(i): return i.id) == [&"longsword", &"iron_belt"] and knight_ghost.coord == Vector2i(3, 3))
	chk("every ghost unit stands on the enemy half", b.units.all(func(u): return u.coord.y <= 3))
	chk("balance hash is stable and 16 characters", balance == BoardSnapshot.balance_hash(units, items) and balance.length() == 16)
	var tweaked := (load("res://tres/knight.tres") as UnitData).duplicate() as UnitData
	tweaked.max_health += 1.0
	var changed := units.map(func(d): return tweaked if d.display_name == "Knight" else d)
	chk("any stat change changes the hash", BoardSnapshot.balance_hash(changed, items) != balance)
	chk("incomplete snapshots are rejected", not BoardSnapshot.is_valid({}) and not BoardSnapshot.is_valid({"version": 1}) and not BoardSnapshot.is_valid(BoardSnapshot.capture([], meta("x", 1, 1, balance))))

	print("--- local store")
	var store := LocalSnapshotStore.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	chk("empty store: nothing to fetch", store.fetch(9, 5, balance, rng).is_empty())
	store.submit(snap)
	chk("a submitted snapshot can be fetched for its round and level", store.fetch(9, 5, balance, rng).get("run") == "runA", str(store.count(9)))
	chk("wrong balance hash: not offered", store.fetch(9, 5, "other", rng).is_empty())
	chk("your own current run is never offered", store.fetch(9, 5, balance, rng, "runA").is_empty())
	chk("a neighbouring round is used when the exact one is empty", store.fetch(10, 5, balance, rng).get("run") == "runA" and store.fetch(8, 5, balance, rng).get("run") == "runA")
	chk("two rounds away: nothing", store.fetch(11, 5, balance, rng).is_empty())
	chk("a ghost from a much higher level never fits a lower-level player", store.fetch(9, 3, balance, rng).is_empty())
	chk("a ghost one level higher still does", not store.fetch(9, 4, balance, rng).is_empty())
	var low := BoardSnapshot.capture(mine, meta("runLow", 9, 3, balance))
	store.submit(low)
	var picks := {}
	for i in 12:
		picks[store.fetch(9, 3, balance, rng).get("run")] = true
	chk("close levels are preferred (a level 3 player meets the level 3 ghost)", picks.keys() == ["runLow"], str(picks.keys()))
	# unreadable and old-format files are skipped, not fatal
	var junk := FileAccess.open(ROOT + "/round_09/000000000001_junk_1.json", FileAccess.WRITE)
	junk.store_string("{ not json")
	junk.close()
	chk("a corrupt file in the folder is ignored", store.fetch(9, 5, balance, rng).get("run") == "runA")
	# pruning: only the newest MAX_PER_ROUND are kept per round
	for i in LocalSnapshotStore.MAX_PER_ROUND + 7:
		var s := BoardSnapshot.capture(mine, meta("bulk%d" % i, 20, 5, balance))
		s["created"] = 1000 + i
		store.submit(s)
	chk("pruned to the newest %d per round" % LocalSnapshotStore.MAX_PER_ROUND, store.count(20) == LocalSnapshotStore.MAX_PER_ROUND, str(store.count(20)))
	var runs := {}
	for i in 60:
		runs[store.fetch(20, 5, balance, rng).get("run")] = true
	chk("the oldest were the ones deleted", not runs.has("bulk0") and not runs.has("bulk6") and runs.keys().all(func(r): return int(str(r).substr(4)) >= 7))

	print("--- ghost provider")
	wipe(ROOT)
	var fb := RandomOpponents.new(units, 0.4, 0.05, 0.3, rng)
	var prov := SnapshotOpponents.new(store, fb, units, items, balance, rng, "me")
	prov.prepare(9)
	chk("no ghosts: it says so and falls back to random enemies", prov.describe_next().contains("no ghosts") and prov.board_for_round(9).display_name == "Random")
	store.submit(snap)
	prov.prepare(9)
	chk("with a ghost: describes it for the top bar", prov.describe_next() == "Ghost of You (round 9, level 5, 74 HP)", prov.describe_next())
	chk("and returns its board", prov.board_for_round(9).display_name == "Ghost of You" and prov.board_for_round(9).units.size() == 3)

	print("--- a ghost fight is deterministic")
	var sigs: PackedStringArray = []
	for i in 2:
		await load_main(222)
		place_player_units()
		var waves: Array[EnemyBoard] = [BoardSnapshot.to_board(snap, gm.unit_pool, gm.item_roster)]
		gm.opponents = WaveOpponents.new(waves, 1.0)
		gm.snapshot_store = null
		gm.start_combat()
		gm.resolve_combat()
		sigs.append(signature())
	chk("the same ghost fight twice gives an identical result", sigs[0] == sigs[1] and sigs[0].contains("dealt="), sigs[0].left(120))

	print("--- in the game: recording and the ghost mode")
	wipe(ROOT)
	await load_main(333, false)
	place_player_units()
	GameState.me.level = 5
	gm.start_combat()
	await get_tree().process_frame
	chk("free play records your board when a fight starts", LocalSnapshotStore.new().count(1) == 1, str(LocalSnapshotStore.new().count(1)))
	var saved := LocalSnapshotStore.new().fetch(1, 5, gm.balance_hash, rng)
	chk("the recorded snapshot holds your 3 units, mirrored", saved.board.units.size() == 3 and saved.run == str(GameState.run_seed) and saved.player_level == 5)

	await load_main(444, true)
	await get_tree().process_frame
	var row: StandingRow = main.get_node("UI/Standings").opponent_row()
	chk("ghost mode uses the ghost provider", GameState.ghost_mode and gm.opponents is SnapshotOpponents)
	chk("the standings name the opponent (no ghost for this level yet -> random)", row != null and row.name_text == "Random enemies" and row.vs_tag.visible, row.name_text if row else "no row")
	# a ghost saved by another run at round 1 now shows up in the next ghost run
	var other := BoardSnapshot.capture(place_player_units(), meta("otherrun", 1, 1, gm.balance_hash))
	other["player_level"] = 1
	LocalSnapshotStore.new().submit(other)
	await load_main(555, true)
	await get_tree().process_frame
	row = main.get_node("UI/Standings").opponent_row()
	chk("round 1 of the next ghost run shows the saved ghost in the standings, with its HP", row != null and row.name_text == "Ghost of You" and row.hp_lbl.text == str(int(other.get("hp", -1))), "%s %s" % [row.name_text, row.hp_lbl.text] if row else "no row")
	gm.start_combat()
	var ghosts := main.get_node("Board/Units").get_children().filter(func(n): return n is Unit and n.team == 1)
	chk("and the ghost's units are on the enemy half at their mirrored tiles", ghosts.size() >= 1 and ghosts.all(func(u): return u.coord.y <= 3))
	gm.resolve_combat()
	await get_tree().process_frame

	await load_main(666, false)
	chk("free play: the opponent row says Random enemies", main.get_node("UI/Standings").opponent_row().name_text == "Random enemies" and gm.opponents is RandomOpponents)
	GameState.ghost_mode = false

	wipe(ROOT)
	LocalSnapshotStore.root = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
