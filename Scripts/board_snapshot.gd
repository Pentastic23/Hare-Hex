# board_snapshot.gd
class_name BoardSnapshot extends RefCounted

# A recorded player board for async PvP ("ghost" opponents). Plain data (JSON-safe), so it can be
# stored on disk now and uploaded later. The board is saved already mirrored onto the enemy half,
# in the EnemyBoard format, so a ghost spawns exactly like any other enemy board.
#
# {"version": 1, "balance": "<hash>", "created": unix, "run": "<run id>", "round": 9, "stage": "2-6",
#  "player_level": 5, "hp": 74, "name": "You", "board": EnemyBoard.to_dict()}
# plus, from async PvP runs, "trophies" and "losses" (fights won and lost so far), and from the online
# service an "id". Older snapshots without them still load.

const VERSION := 1

# A 180 degree turn of the board: (x, y) -> (6 - x, 7 - y). Rows 4-7 (player) land on rows 3-0
# (enemy). It keeps hex neighbours and distances (the odd-row offset flips with the row parity).
static func mirror(c: Vector2i) -> Vector2i:
	return Vector2i(Board.COLS - 1 - c.x, Board.ROWS - 1 - c.y)

# Hash of everything that decides how strong a unit is: unit and item stats, synergy table, star
# multipliers. A snapshot only fights games with the same hash, so a balance change never makes a
# ghost fight with stats it didn't have.
static func balance_hash(unit_roster: Array, item_roster: Array) -> String:
	var units := []
	for x in unit_roster:
		var d := x as UnitData
		if d == null:
			continue
		var tags := []
		for t in d.tags:
			tags.append(String(t))
		units.append([d.display_name, d.cost, d.max_health, d.max_mana, d.start_mana, d.attack_damage, d.attack_range, d.attacks_per_second, d.move_speed, tags])
	units.sort_custom(func(a, b): return a[0] < b[0])
	var items := []
	for x in item_roster:
		var it := x as ItemData
		if it == null:
			continue
		items.append([String(it.id), it.hp, it.dmg, it.attack_speed, it.mana, it.damage_reduction, it.lifesteal, it.effects, String(it.element), String(it.kind), it.stack_hp, it.stack_dmg, it.max_stacks, it.gold_per_round, it.free_rerolls, String(it.counts_twice)])
	items.sort_custom(func(a, b): return a[0] < b[0])
	var stars := [Unit.STAR_MULT[1], Unit.STAR_MULT[2], Unit.STAR_MULT[3], Unit.FIVE_COST_3STAR]
	var text := JSON.stringify([units, items, Synergies.DEFS, stars, Resonance.PAIRS, Resonance.PRISM, Abilities.DEFS], "", true)
	return text.sha256_text().left(16)

# meta: name, run, round, stage, level, hp, balance, and optionally trophies and losses. player_units: the units on the player's board.
static func capture(player_units: Array, meta: Dictionary) -> Dictionary:
	var board := EnemyBoard.new()
	board.display_name = str(meta.get("name", "You"))
	for x in player_units:
		var u := x as Unit
		if u == null or u.data == null or u.coord.x < 0:
			continue
		var bu := BoardUnit.new()
		bu.unit = u.data
		bu.star = u.star
		bu.coord = mirror(u.coord)
		for item in u.items:
			bu.items.append(item)
		bu.stacks = u.item_stacks.duplicate()
		board.units.append(bu)
	board.units.sort_custom(func(a, b): return Board.tile_order(a.coord) < Board.tile_order(b.coord))
	var out := {
		"version": VERSION,
		"balance": str(meta.get("balance", "")),
		"created": int(Time.get_unix_time_from_system()),
		"run": str(meta.get("run", "")),
		"round": int(meta.get("round", 1)),
		"stage": str(meta.get("stage", "")),
		"player_level": int(meta.get("level", 1)),
		"hp": int(meta.get("hp", 0)),
		"name": str(meta.get("name", "You")),
		"board": board.to_dict(),
	}
	if meta.has("trophies"):   # async PvP runs only
		out["trophies"] = int(meta.trophies)
		out["losses"] = int(meta.get("losses", 0))
	return out

static func is_valid(s: Dictionary) -> bool:
	if int(s.get("version", 0)) != VERSION:
		return false
	for key in ["balance", "run", "round", "player_level", "name", "board"]:
		if not s.has(key):
			return false
	var b = s.board
	return b is Dictionary and b.get("units", []) is Array and not b.get("units", []).is_empty()

# The ghost as an enemy board. Unknown units or items (removed since it was saved) are skipped by
# EnemyBoard.from_dict, which can't happen for a matching balance hash.
static func to_board(s: Dictionary, unit_roster: Array, item_roster: Array) -> EnemyBoard:
	var b := EnemyBoard.from_dict(s.get("board", {}), unit_roster, item_roster)
	b.display_name = "Ghost of %s" % str(s.get("name", "?"))
	b.stat_scale = 1.0       # player units fight at full strength
	b.use_synergies = true   # recomputed from the ghost's own units
	return b

# One-line description for the top bar.
static func describe(s: Dictionary) -> String:
	if s.has("trophies"):
		return "Ghost of %s (round %d, level %d, %d trophies, %d lives)" % [str(s.get("name", "?")), int(s.get("round", 0)), int(s.get("player_level", 0)), int(s.trophies), maxi(GameState.ASYNC_LIVES - int(s.get("losses", 0)), 0)]
	return "Ghost of %s (round %d, level %d, %d HP)" % [str(s.get("name", "?")), int(s.get("round", 0)), int(s.get("player_level", 0)), int(s.get("hp", 0))]
