# snapshot_opponents.gd
class_name SnapshotOpponents extends OpponentProvider

# Async PvP: each round you fight a ghost, another run's board recorded at about the same point.
# The ghost is chosen when PREP starts (so the top bar can say who is coming) and kept for the fight.
# Ghosts recorded with today's balance (same BoardSnapshot.balance_hash) come first. With none, a ghost
# from an older balance version (before a stats or synergy change) still plays, as long as every unit
# and item on it still exists; it fights with today's stats and traits. With no ghost at all it falls
# back to random enemies.

var store: SnapshotStore
var fallback: OpponentProvider
var unit_roster: Array = []
var item_roster: Array = []
var balance := ""
var rng: RandomNumberGenerator
var run_id := ""

var _round := -1
var _snapshot: Dictionary = {}

func _init(snapshot_store: SnapshotStore, fallback_provider: OpponentProvider, units: Array, items: Array, balance_hash: String, run_rng: RandomNumberGenerator, current_run: String):
	store = snapshot_store
	fallback = fallback_provider
	unit_roster = units
	item_roster = items
	balance = balance_hash
	rng = run_rng
	run_id = current_run

func prepare(round_number: int) -> void:
	_round = round_number
	_snapshot = store.fetch(round_number, GameState.me.level, balance, rng, run_id)
	if _snapshot.is_empty():
		_snapshot = store.fetch(round_number, GameState.me.level, "", rng, run_id, still_playable)

# True when every unit and item on a ghost still exists, so it spawns whole with today's roster.
func still_playable(s: Dictionary) -> bool:
	var units: Array = s.get("board", {}).get("units", [])
	for e in units:
		if not (e is Dictionary) or EnemyBoard.lookup_unit(unit_roster, str(e.get("unit", ""))) == null:
			return false
		for id in e.get("items", []):
			if EnemyBoard.lookup_item(item_roster, StringName(str(id))) == null:
				return false
	return not units.is_empty()

# The ghost picked for the coming fight (BoardSnapshot format), or {} when random enemies stand in.
func current_snapshot() -> Dictionary:
	return _snapshot

func describe_next() -> String:
	if _snapshot.is_empty():
		return "Random enemies (no ghosts saved yet)"
	return BoardSnapshot.describe(_snapshot)

func board_for_round(round_number: int) -> EnemyBoard:
	if _round != round_number:
		prepare(round_number)
	if _snapshot.is_empty():
		return fallback.board_for_round(round_number)
	return BoardSnapshot.to_board(_snapshot, unit_roster, item_roster)
