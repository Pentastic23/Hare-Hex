# snapshot_opponents.gd
class_name SnapshotOpponents extends OpponentProvider

# Async PvP: each round you fight a ghost, another run's board recorded at about the same point.
# The ghost is chosen when PREP starts (so the top bar can say who is coming) and kept for the fight.
# Ghosts recorded with today's balance (same BoardSnapshot.balance_hash) come first. With none, a ghost
# from an older balance version (before a stats or synergy change) still plays, as long as every unit
# and item on it still exists; it fights with today's stats and traits. With no ghost at all it falls
# back to random enemies.
#
# With the online store (HttpSnapshotStore) ghosts are asked for a round ahead (prefetch). If this round's
# online ghosts arrive after PREP began and the pick so far was only a local ghost or random enemies, it
# picks again and emits ghost_changed, so GameManager can announce the new opponent before the fight.

signal ghost_changed

var store: SnapshotStore
var fallback: OpponentProvider
var unit_roster: Array = []
var item_roster: Array = []
var balance := ""
var rng: RandomNumberGenerator
var run_id := ""

var _round := -1
var _snapshot: Dictionary = {}
var _locked := false   # the fight has begun (board_for_round): the ghost can't change any more

func _init(snapshot_store: SnapshotStore, fallback_provider: OpponentProvider, units: Array, items: Array, balance_hash: String, run_rng: RandomNumberGenerator, current_run: String):
	store = snapshot_store
	fallback = fallback_provider
	unit_roster = units
	item_roster = items
	balance = balance_hash
	rng = run_rng
	run_id = current_run
	store.fetched.connect(_on_fetched)
	store.prefetch(1, 1, balance, run_id)   # the opening comes a moment after the run starts
	store.prefetch(2, 1, balance, run_id)

func prepare(round_number: int) -> void:
	_round = round_number
	_locked = false
	_pick()
	store.prefetch(round_number + 1, GameState.me.level, balance, run_id)   # next round's, while this one is played

func _pick() -> void:
	_snapshot = store.fetch(_round, GameState.me.level, balance, rng, run_id)
	if _snapshot.is_empty():
		_snapshot = store.fetch(_round, GameState.me.level, "", rng, run_id, still_playable)

func _on_fetched(round_number: int) -> void:
	if _locked or round_number != _round or bool(_snapshot.get("_online", false)):
		return
	var before := _snapshot
	_pick()
	if _snapshot != before:
		ghost_changed.emit()

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
	_locked = true
	if _snapshot.is_empty():
		return fallback.board_for_round(round_number)
	return BoardSnapshot.to_board(_snapshot, unit_roster, item_roster)
