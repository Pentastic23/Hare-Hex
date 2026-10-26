# arena.gd
class_name Arena extends RefCounted

# A lobby fight, described as plain data (JSON-safe, sent over the network) and set up on a board.
# The lobby server runs every fight on its own hidden board; each client replays its own fight on the
# visible board from the very same description through the very same setup(), and gets the same fight
# (combat is deterministic: see combat_runner.gd). Items dropped onto fighting units are inputs at a
# fixed tick (schedule_input), applied identically on both sides.
#
# Fight description:
#   {"id": int, "round": int, "home": seat, "away": seat (-1: a PvE wave), "ghost": bool (away is a
#    copy of a seat that fights someone else this round: only home's result counts),
#    "home_name": str, "away_name": str, "home_level": int,
#    "enemy_open": [[x, y], ...]   tiles of the enemy half to open (enemy coords),
#    "home_units": [unit entry, ...]   coords on the home half (rows 4-7), as on home's own board,
#    "away_units": [unit entry, ...]   coords on the enemy half (rows 0-3): already mirrored,
#    "away_scale": float (a PvE wave's strength; 1.0 for players), "away_synergies": bool}
#   kings: "home_king" / "away_king" (KingSkins ids, "" for a PvE wave: it strikes but has no skin),
#    "away_level" (the away king's strike scales with it); the kings' picks are seeded from "id" and "round".
#   unit entry: {"uid": int, "unit": "<display name>", "star": int, "items": ["<item id>", ...],
#                "stacks": {"<item id>": int}, "coord": [x, y]}
#
# The home side is team 0, the away side team 1, on the server and on both clients. The away player's
# client shows the fight turned around (camera and colours), never different units.

const INPUT_DELAY := 15   # ticks between accepting a mid-fight item drop and applying it (0.25 s; covers LAN latency)

# A unit entry from a seat's unit (its coord or a mirrored one).
static func unit_entry(u: Unit, coord: Vector2i) -> Dictionary:
	var e := {"uid": u.uid, "unit": u.data.display_name, "star": u.star, "items": u.items.map(func(i): return String(i.id)), "coord": [coord.x, coord.y]}
	if not u.item_stacks.is_empty():
		e["stacks"] = EnemyBoard._stacks_out(u.item_stacks)
	return e

# The units a seat fights with: those on its board, in tile order. `mirror`: onto the enemy half.
static func board_entries(b: Board, mirror: bool) -> Array:
	var list: Array = []
	var units := b.all_player_units().filter(func(u): return u.coord.x >= 0)
	units.sort_custom(func(a, c): return Board.tile_order(a.coord) < Board.tile_order(c.coord))
	for u in units:
		list.append(unit_entry(u, BoardSnapshot.mirror(u.coord) if mirror else u.coord))
	return list

# A seat's bench (display only: the other player sees it on the far bench during the fight), with "bench"
# slots instead of coords.
static func bench_entries(b: Board) -> Array:
	var list: Array = []
	for i in b.bench.size():
		var u: Unit = b.bench[i]
		if u != null:
			var e := unit_entry(u, Vector2i(-1, -1))
			e.erase("coord")
			e["bench"] = i
			list.append(e)
	return list

# The enemy-half tiles to open for a player opponent: the mirror images of their own open tiles.
static func mirrored_open(level: int, b: Board) -> Array:
	var out: Array = []
	for c in b.open_player_tiles(level):
		var m := BoardSnapshot.mirror(c)
		out.append([m.x, m.y])
	return out

static func _coord(raw) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1])) if raw is Array and raw.size() == 2 else Vector2i(-1, -1)

# Clears the board's units and places the fight's two sides; returns {"home": Array[Unit], "away": Array[Unit]}
# (in the description's order: input indexes refer to these). Sources (seat, uid) are kept on each copy.
# Does not start the runner: the caller calls runner.start() (after its own setup, e.g. the viewer colours).
# keep_bench: a client's visible board keeps its own bench units (they stay usable during the fight);
# the units it had on tiles go (the server's state after the fight brings them back).
static func setup(b: Board, fight: Dictionary, unit_roster: Array, item_roster: Array, scene: PackedScene, keep_bench := false) -> Dictionary:
	clear(b, keep_bench)
	var enemy_open: Array[Vector2i] = []
	for raw in fight.get("enemy_open", []):
		enemy_open.append(_coord(raw))
	b.set_fight_unlocks(int(fight.get("home_level", 1)), enemy_open)
	var sides := {"home": [], "away": []}
	var home_seat := int(fight.get("home", -1))
	var away_seat := int(fight.get("away", -1))
	for side in ["home", "away"]:
		var team := 0 if side == "home" else 1
		var scale := 1.0 if side == "home" else float(fight.get("away_scale", 1.0))
		for e in fight.get(side + "_units", []):
			if not e is Dictionary:
				continue
			var d := EnemyBoard.lookup_unit(unit_roster, str(e.get("unit", "")))
			var c := _coord(e.get("coord"))
			if d == null or not b.tiles.has(c) or b.tiles[c].occupant != null:
				sides[side].append(null)   # keep the indexes lined up (never happens with a valid description)
				continue
			var u := scene.instantiate() as Unit
			b.get_node("Units").add_child(u)
			u.setup(d, team)
			u.stat_scale = scale
			u.source_uid = int(e.get("uid", -1))
			u.source_seat = (home_seat if team == 0 else away_seat) if not (team == 1 and bool(fight.get("ghost", false))) else -1
			var star := clampi(int(e.get("star", 1)), 1, 3)
			if star > 1:
				u.set_star(star)
			var its: Array[ItemData] = []
			for id in e.get("items", []):
				var item := EnemyBoard.lookup_item(item_roster, StringName(str(id)))
				if item != null:
					its.append(item)
			if not its.is_empty():
				u.set_items(its)
				u.item_stacks = EnemyBoard.stacks_in(e.get("stacks", {}))
				u._recalc_items()
			b.put_enemy_on_tile(u, c)   # occupancy only (works for either half)
			sides[side].append(u)
	var home: Array = sides.home.filter(func(u): return u != null)
	var away: Array = sides.away.filter(func(u): return u != null)
	Synergies.apply(home)
	if bool(fight.get("away_synergies", true)):
		Synergies.apply(away)
	for u in home + away:
		(u as Unit).begin_combat()
	return sides

# The kings of a fight (combat_runner.gd): their skins, levels and the seed of their picks, from the
# description, so the server and both clients see the same strikes and shields. Call before runner.start().
static func set_kings(runner: CombatRunner, fight: Dictionary) -> void:
	var skins: Array = []
	for side in ["home", "away"]:
		var id := StringName(str(fight.get(side + "_king", "")))
		skins.append(id if KingSkins.has(id) else &"")
	runner.king_skins = skins
	runner.king_levels = [int(fight.get("home_level", 1)), int(fight.get("away_level", fight.get("home_level", 1)))]
	runner.king_seed = hash([int(fight.get("id", 0)), int(fight.get("round", 0))])

# Frees every unit on the board (but the bench's, with keep_bench) and empties its tiles.
static func clear(b: Board, keep_bench := false) -> void:
	for n in b.get_node("Units").get_children():
		if keep_bench and n is Unit and b.bench.has(n):
			continue
		b.get_node("Units").remove_child(n)
		n.free()
	for t in b.tiles.values():
		t.occupant = null
	if not keep_bench:
		for i in b.bench.size():
			b.bench[i] = null

# An item dropped onto a fighting unit: {"tick": int, "side": "home" | "away", "index": int, "item": id}.
# Scheduled on the runner; a unit that has fallen by then gets nothing (the same on every machine).
static func schedule_input(runner: CombatRunner, sides: Dictionary, input: Dictionary, item_roster: Array) -> void:
	var list: Array = sides.get(str(input.get("side", "")), [])
	var index := int(input.get("index", -1))
	var item := EnemyBoard.lookup_item(item_roster, StringName(str(input.get("item", ""))))
	if index < 0 or index >= list.size() or list[index] == null or item == null:
		return
	var u: Unit = list[index]
	runner.schedule(int(input.get("tick", 0)), func():
		if is_instance_valid(u) and not u.dead:
			u.equip(item, true))

# The result of a finished fight: who won ("home", "away" or "draw": both still standing at the time
# limit, or both wiped out), the stars and units still standing on each side (units: loss damage) and the sources of the
# copies still alive on each side (their bound items grow).
static func result(sides: Dictionary, alive: Array, stars: Array) -> Dictionary:
	var winner := "draw"
	if alive[1] == 0 and alive[0] > 0:
		winner = "home"
	elif alive[0] == 0 and alive[1] > 0:
		winner = "away"
	var survivors := {"home": [], "away": []}
	for side in ["home", "away"]:
		for u in sides.get(side, []):
			if u != null and is_instance_valid(u) and not u.dead and u.source_uid >= 0:
				survivors[side].append(u.source_uid)
	return {"winner": winner, "home_stars": int(stars[0]), "away_stars": int(stars[1]), "home_alive": int(alive[0]), "away_alive": int(alive[1]), "survivors": survivors}
