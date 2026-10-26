# snapshot_store.gd
class_name SnapshotStore extends RefCounted

# Where async PvP boards are kept and found. LocalSnapshotStore keeps files on this PC; HttpSnapshotStore
# (Scripts/online/) talks to the online ghost service and keeps a local copy too. Nothing else in the game
# cares which one it is: OnlineConfig.make_store() picks.

# An online store emits this when ghosts for `round` have arrived (prefetch), so a provider that had to
# make do with a local ghost or random enemies can pick again before the fight.
signal fetched(round: int)

const LEVEL_SPREAD := 1   # a ghost within this many levels of the player counts as "near"

# Saves a snapshot (BoardSnapshot.capture() output).
func submit(_snapshot: Dictionary) -> void:
	pass

# A snapshot near `round` for a player at `player_level`, or {} if there is none. Only snapshots with
# the same `balance` hash qualify ("" = any balance version), never one from the run `exclude_run`
# (your own current run), and, when `accept` is given, only those it returns true for.
# `rng` is the run's seeded RNG, so the same seed picks the same ghost.
func fetch(_round: int, _player_level: int, _balance: String, _rng: RandomNumberGenerator, _exclude_run := "", _accept := Callable()) -> Dictionary:
	return {}

# Asks for ghosts of `round` ahead of time (an online store fetches them in the background and emits
# `fetched`). A local store has everything at hand already, so this does nothing.
func prefetch(_round: int, _player_level: int, _balance: String, _exclude_run := "") -> void:
	pass

# The ghost picking rule both stores share: the exact round first, then the round before and after.
# In a round, ghosts within LEVEL_SPREAD levels of the player are preferred; ghosts more than
# LEVEL_SPREAD levels above the player never qualify (more units than the enemy tiles open at this level).
static func choose(candidates: Array, round: int, player_level: int, balance: String, rng: RandomNumberGenerator, exclude_run := "", accept := Callable()) -> Dictionary:
	for r in [round, round - 1, round + 1]:
		if r < 1:
			continue
		var near: Array = []
		var any: Array = []
		for x in candidates:
			if not x is Dictionary:
				continue
			var s: Dictionary = x
			if int(s.get("round", 0)) != r or not BoardSnapshot.is_valid(s):
				continue
			if (balance != "" and str(s.balance) != balance) or str(s.run) == exclude_run:
				continue
			if accept.is_valid() and not accept.call(s):
				continue
			var level := int(s.player_level)
			if level > player_level + LEVEL_SPREAD:
				continue
			any.append(s)
			if absi(level - player_level) <= LEVEL_SPREAD:
				near.append(s)
		var pick := near if not near.is_empty() else any
		if not pick.is_empty():
			return pick[rng.randi_range(0, pick.size() - 1)]
	return {}
