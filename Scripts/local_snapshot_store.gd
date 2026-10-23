# local_snapshot_store.gd
class_name LocalSnapshotStore extends SnapshotStore

# Snapshots as JSON files, one folder per round:
#   user://snapshots/round_09/<created>_<run>_<n>.json   (Windows: %APPDATA%/Godot/app_userdata/<project>/snapshots)
# At most MAX_PER_ROUND per round; the oldest are deleted first. Your own past runs become your
# opponents, so the mode works offline from the first game.
#
# Headless runs (the test tools and the bot) use a different folder, so they never fill the real one.

const MAX_PER_ROUND := 50
const LEVEL_SPREAD := 1   # a ghost within this many levels of the player counts as "near"

static var root := ""     # tests point this somewhere else; "" = default_root()
var _counter := 0

static func default_root() -> String:
	return "user://snapshots_headless" if DisplayServer.get_name() == "headless" else "user://snapshots"

static func dir() -> String:
	return root if root != "" else default_root()

static func _bucket(round: int) -> String:
	return "%s/round_%02d" % [dir(), round]

# Files in a round's folder, oldest first (names start with the creation time).
func _files(round: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(_bucket(round)):
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out

func count(round: int) -> int:
	return _files(round).size()

func submit(snapshot: Dictionary) -> void:
	if not BoardSnapshot.is_valid(snapshot):
		return
	var round := int(snapshot.round)
	var bucket := _bucket(round)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bucket))
	_counter += 1
	var file := "%012d_%s_%d.json" % [int(snapshot.created), str(snapshot.run).validate_filename(), _counter]
	var path := "%s/%s" % [bucket, file]
	var tmp := path + ".tmp"   # written to a temp file first, so a crash can't leave half a snapshot
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("LocalSnapshotStore: can't write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(snapshot))
	f.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) != OK:
		push_warning("LocalSnapshotStore: can't move %s into place" % tmp)
		return
	var files := _files(round)
	while files.size() > MAX_PER_ROUND:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [bucket, files[0]]))
		files.remove_at(0)

func _read(round: int, file: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [_bucket(round), file]))
	if parsed is Dictionary and BoardSnapshot.is_valid(parsed):
		return parsed
	return {}   # unreadable or from another version: ignored, never deleted

func fetch(round: int, player_level: int, balance: String, rng: RandomNumberGenerator, exclude_run := "", accept := Callable()) -> Dictionary:
	for r in [round, round - 1, round + 1]:   # the exact round first, then its neighbours
		if r < 1:
			continue
		var near: Array = []
		var any: Array = []
		for file in _files(r):
			var s := _read(r, file)
			if s.is_empty() or (balance != "" and str(s.balance) != balance) or str(s.run) == exclude_run:
				continue
			if accept.is_valid() and not accept.call(s):
				continue
			var level := int(s.player_level)
			if level > player_level + LEVEL_SPREAD:
				continue   # too many units for the enemy tiles that are open at this level
			any.append(s)
			if absi(level - player_level) <= LEVEL_SPREAD:
				near.append(s)
		var candidates := near if not near.is_empty() else any
		if not candidates.is_empty():
			return candidates[rng.randi_range(0, candidates.size() - 1)]
	return {}
