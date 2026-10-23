# snapshot_store.gd
class_name SnapshotStore extends RefCounted

# Where async PvP boards are kept and found. LocalSnapshotStore keeps files on this PC; a later
# HttpSnapshotStore would call a web service instead. Nothing else in the game cares which one it is.

# Saves a snapshot (BoardSnapshot.capture() output).
func submit(_snapshot: Dictionary) -> void:
	pass

# A snapshot near `round` for a player at `player_level`, or {} if there is none. Only snapshots with
# the same `balance` hash qualify ("" = any balance version), never one from the run `exclude_run`
# (your own current run), and, when `accept` is given, only those it returns true for.
# `rng` is the run's seeded RNG, so the same seed picks the same ghost.
func fetch(_round: int, _player_level: int, _balance: String, _rng: RandomNumberGenerator, _exclude_run := "", _accept := Callable()) -> Dictionary:
	return {}
