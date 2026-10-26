# save_game.gd
class_name SaveGame extends RefCounted

# Campaign progress, unlocks and the chapter run in progress, stored as JSON in user:// (on Windows:
# %APPDATA%/Godot/app_userdata/Azerothtactics/save.json). Static so it needs no autoload;
# loads on first use.
#
# Format (version 2):
#   { "version": 2,
#     "completed_levels": { "<level id>": { "best_hp": int, "times": int, "first_completed": unix } },
#     "unlocks": [ "<id>", ... ],
#     "chapter_run": {} or the carried state at the start of the next level (see GameManager.make_carry),
#     "team_plan": [ "<unit display name>", ... ],
#     "team_comps": [ { "name": str, "units": [ "<unit display name>", ... ] }, ... ],   (saved plans, the planner's Comps)
#     "king": "<king skin id>" }   (the chosen king; "" = not picked yet)
# Version 1 files (no chapter_run) and files without team_plan load fine.
#
# Mid-level saves: while a chapter level is being played, chapter_run is rewritten at the start of every
# PREP, at the start of every fight, and when you leave during PREP (pause menu, quit, closing the window).
# It is then the carry for the level being played (hp, gold, units... as they are now) plus a "mid" block
# (GameManager.make_mid_save):
#   "mid": { "version": 1, "round": int, "phase": "prep" | "combat", "seed": int,
#            "rng": "<GameManager.rng state>", "player_rng": "<GameState.me.rng state>",   (strings: int64)
#            "win_streak": int, "loss_streak": int, "last_won": bool, "dropped": { "<item id>": int },
#            "free_rerolls": int, "cheap_shop": bool, "offers": [ "<unit name>", ... ], "locked": bool,
#            "rolled": bool, "pool": { "<unit name>": copies left }, "saved": unix }
# "prep" resumes into that round's PREP (same shop, a full timer, no second income); "combat" replays the
# fight from its start with the same board, which gives the same result (fights are deterministic).
# Losing clears chapter_run; winning the level replaces it with the next level's carry (no "mid").

const VERSION := 2
const DEFAULT_PATH := "user://save.json"

static var path := DEFAULT_PATH   # tests point this elsewhere
static var _data := {}
static var _loaded := false

static func data() -> Dictionary:
	if not _loaded:
		load_game()
	return _data

static func _defaults() -> Dictionary:
	return {"version": VERSION, "completed_levels": {}, "unlocks": [], "chapter_run": {}, "team_plan": [], "team_comps": [], "king": "", "async_best": 0}

static func load_game() -> void:
	_data = _defaults()
	_loaded = true
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("SaveGame: can't open %s (%s); using an empty save" % [path, FileAccess.get_open_error()])
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		# Keep the unreadable file next to the save so progress isn't silently lost.
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".corrupt"))
		push_warning("SaveGame: %s is unreadable; copied to .corrupt and starting fresh" % path)
		return
	_data = _migrate(parsed)

# Brings older or hand-edited saves up to the current format, dropping anything malformed.
static func _migrate(d: Dictionary) -> Dictionary:
	var out := _defaults()
	var levels = d.get("completed_levels", {})
	if levels is Dictionary:
		for id in levels:
			var e = levels[id]
			if e is Dictionary:
				out.completed_levels[str(id)] = {
					"best_hp": int(e.get("best_hp", 0)),
					"times": int(e.get("times", 1)),
					"first_completed": int(e.get("first_completed", 0)),
				}
	var unlocks = d.get("unlocks", [])
	if unlocks is Array:
		for u in unlocks:
			var s := str(int(u)) if u is float and u == floorf(u) else str(u)   # JSON reads 7 back as 7.0
			if not out.unlocks.has(s):
				out.unlocks.append(s)
	var run = d.get("chapter_run", {})
	if run is Dictionary and run.has("level") and run.has("units"):
		out.chapter_run = run
	var plan = d.get("team_plan", [])
	if plan is Array:
		for n in plan:
			if not out.team_plan.has(str(n)):
				out.team_plan.append(str(n))
	var comps = d.get("team_comps", [])
	if comps is Array:
		for c in comps:
			if c is Dictionary and c.get("units") is Array:
				out.team_comps.append({"name": str(c.get("name", "Comp")), "units": (c.units as Array).map(func(n): return str(n))})
	out.king = str(d.get("king", ""))
	out.async_best = maxi(int(d.get("async_best", 0)), 0)
	return out

# Writes to a temp file first, then swaps it in, so a crash mid-write can't destroy the save.
static func save_game() -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: can't write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data(), "\t"))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		push_warning("SaveGame: can't replace %s (%s)" % [path, error_string(err)])
		return false
	return true

static func is_level_complete(id: StringName) -> bool:
	return data().completed_levels.has(String(id))

static func best_hp(id: StringName) -> int:
	var e = data().completed_levels.get(String(id))
	return int(e.best_hp) if e is Dictionary else 0

static func record_level_complete(id: StringName, hp_left: int, unlocks: Array = []) -> void:
	var levels: Dictionary = data().completed_levels
	var key := String(id)
	if levels.has(key):
		levels[key].best_hp = maxi(int(levels[key].best_hp), hp_left)
		levels[key].times = int(levels[key].times) + 1
	else:
		levels[key] = {"best_hp": hp_left, "times": 1, "first_completed": int(Time.get_unix_time_from_system())}
	for u in unlocks:
		add_unlock(StringName(str(u)), false)
	save_game()

static func has_unlock(id: StringName) -> bool:
	return data().unlocks.has(String(id))

static func add_unlock(id: StringName, write := true) -> void:
	if not has_unlock(id):
		data().unlocks.append(String(id))
		if write:
			save_game()

# Team planner: display names of the units the player is aiming for.
# The chosen king skin (KingSkins): "" until the player has picked one (the menu then asks).
static func king_skin() -> String:
	return data().king

static func set_king_skin(id: String) -> void:
	data().king = id
	save_game()

# Async PvP: the most trophies a run has reached (endless runs count on past 10).
static func async_best() -> int:
	return int(data().get("async_best", 0))

# Keeps the best async PvP result; true when this one beat it.
static func record_async(trophies: int) -> bool:
	if trophies <= async_best():
		return false
	data().async_best = trophies
	save_game()
	return true

static func team_plan() -> Array:
	return data().team_plan

static func set_team_plan(names: Array) -> void:
	data().team_plan = names.duplicate()
	save_game()

# Saved team comps (the planner's Comps row): [{name, units}], at most MAX_COMPS; the newest last.
const MAX_COMPS := 8
static func team_comps() -> Array:
	return data().team_comps

# Saves `units` as a comp called `comp_name` (one with that name is replaced). Returns its index.
static func save_comp(comp_name: String, units: Array) -> int:
	var comps: Array = data().team_comps
	for i in comps.size():
		if comps[i].name == comp_name:
			comps[i].units = units.duplicate()
			save_game()
			return i
	if comps.size() >= MAX_COMPS:
		comps.pop_front()
	comps.append({"name": comp_name, "units": units.duplicate()})
	save_game()
	return comps.size() - 1

static func delete_comp(i: int) -> void:
	var comps: Array = data().team_comps
	if i >= 0 and i < comps.size():
		comps.remove_at(i)
		save_game()

# The chapter run in progress: what the player carries into level `level`. Empty = none.
static func chapter_run() -> Dictionary:
	return data().chapter_run

static func set_chapter_run(carry: Dictionary) -> void:
	data().chapter_run = carry
	save_game()

# The "mid" block of a saved chapter run when it is one this build can resume (version, a round within
# the level's `total_rounds`, a known phase, the RNG states); {} otherwise.
const MID_VERSION := 1
static func mid_level(run: Dictionary, total_rounds: int) -> Dictionary:
	var mid = run.get("mid")
	if not mid is Dictionary or int(mid.get("version", 0)) != MID_VERSION:
		return {}
	var r := int(mid.get("round", 0))
	if r < 1 or r > total_rounds or not str(mid.get("phase", "")) in ["prep", "combat"]:
		return {}
	for key in ["seed", "rng", "player_rng", "pool"]:
		if not mid.has(key):
			return {}
	return mid

static func clear_chapter_run() -> void:
	if not data().chapter_run.is_empty():
		data().chapter_run = {}
		save_game()

# Wipes progress (for a future "reset progress" button, and tests).
static func reset_progress() -> void:
	var plan: Array = data().team_plan   # the team plan is a preference, not progress: keep it
	var king: String = data().king   # so is the chosen king
	var comps: Array = data().team_comps   # and the saved comps
	_data = _defaults()
	_data.team_plan = plan
	_data.team_comps = comps
	_data.king = king
	_loaded = true
	save_game()
