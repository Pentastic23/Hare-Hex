# telemetry.gd  (autoload "Telemetry")
extends Node

# Anonymous gameplay stats from testers, so the developer can see which modes get played, finished and
# replayed, and where players get stuck (docs/telemetry.md). Events go to the online service the ghosts use
# (SnapshotServer: POST /v1/events; its /stats page sums them up, TelemetryStats). Until that service is
# hosted (OnlineConfig.telemetry_url() is "") they wait in a capped queue on disk and go up once it is.
#
# Sent: a random install id (made on first launch, not tied to anything), the build, OS, graphics card,
# screen size and language; the modes and levels played, how far each run got and how it ended, each
# fight's result and how long prep took, tutorial steps reached, menu screens opened, the frame rate in runs,
# and whether the last session closed cleanly. Never names, files, chat, or anything typed.
# The player can turn it off (Settings > Privacy): the queue is dropped and nothing more is kept or sent.
# Off in the editor (unless run with `-- --telemetry`) and in headless runs (the checks turn it on themselves).

const CFG := "user://telemetry.cfg"
const QUEUE_FILE := "user://telemetry_queue.json"
const QUEUE_MAX := 3000         # events kept while no service answers (about 30 runs); the oldest go first
const BATCH_BYTES := 24 * 1024  # per upload, under the service's MAX_BODY (32 KB)
const BATCH_MAX := 100          # SnapshotServer.MAX_EVENTS
const EVENT_MAX := 4000         # bytes of one event's properties (SnapshotServer.MAX_EVENT)
const FLUSH_EVERY := 30.0       # seconds between uploads
const BACKLOG_EVERY := 2.0      # ... while a backlog is going up
const RETRY_MAX := 600.0        # the longest wait after failed uploads
const TIMEOUT := 10.0
const FPS_SKIP := 3             # the first seconds of a run (loading) don't count towards its frame rate

var cfg_path := CFG              # tests point these elsewhere
var queue_path := QUEUE_FILE
var allowed := false             # this build may collect at all (not the editor, not headless)
var enabled := true              # the player's choice (Settings > Privacy)
var notice_shown := false        # the first-launch notice was seen
var player_id := ""
var session_id := ""
var queue: Array = []
var sent := 0                    # events the service took (tests, the Privacy tab)
var status := ""                 # "" / "ok" / "waiting for a server" / "offline: ..." (the Privacy tab)
var _started := false
var _session_msec := 0
var _session_runs := 0
var _flush_in := 5.0
var _backoff := FLUSH_EVERY
var _busy := false
var _dirty := false
var _save_in := 10.0
var _run := {}                   # the run being played (run_started .. run_end)
var _prep_msec := 0
var _hp_at_fight := 0
var _tut_step := -1
var _step_msec := 0
var _fps_sum := 0.0
var _fps_n := 0
var _fps_low := 0.0
var _fps_t := 0.0
var _fps_seen := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps uploading while a run is paused
	var forced := "--telemetry" in OS.get_cmdline_user_args()
	allowed = forced or (not OS.has_feature("editor") and DisplayServer.get_name() != "headless")
	if allowed:
		start()

# Loads the id and the player's choice, notes an unclean end of the last session, starts this one.
# Tests call it again after pointing the paths elsewhere.
func start() -> void:
	_started = true
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	enabled = bool(cfg.get_value("telemetry", "enabled", true))
	notice_shown = bool(cfg.get_value("telemetry", "notice_shown", false))
	player_id = str(cfg.get_value("telemetry", "id", ""))
	var first := player_id == ""
	if first:
		player_id = _random_id(16)
	var sessions := int(cfg.get_value("telemetry", "sessions", 0)) + 1
	cfg.set_value("telemetry", "id", player_id)
	cfg.set_value("telemetry", "sessions", sessions)
	session_id = _random_id(12)
	_session_msec = Time.get_ticks_msec()
	_session_runs = 0
	_run = {}
	queue = _load_queue() if enabled else []
	if enabled and bool(cfg.get_value("last", "running", false)):
		# The last session never reached _exit_tree: a crash, a freeze that was force-quit, or power loss.
		var last := {"prev_session": str(cfg.get_value("last", "sid", "")), "where": str(cfg.get_value("last", "where", "menu")),
			"mode": str(cfg.get_value("last", "mode", "")), "level": str(cfg.get_value("last", "level", "")),
			"round": int(cfg.get_value("last", "round", 0)), "phase": str(cfg.get_value("last", "phase", "")),
			"minutes": snappedf((int(cfg.get_value("last", "at", 0)) - int(cfg.get_value("last", "began", 0))) / 60.0, 0.1)}
		track("unclean_exit", last)
	cfg.set_value("last", "running", true)
	cfg.set_value("last", "sid", session_id)
	cfg.set_value("last", "began", int(Time.get_unix_time_from_system()))
	cfg.save(cfg_path)
	_remember("menu")
	var screen := DisplayServer.screen_get_size()
	track("session_start", {"first": first, "sessions": sessions, "os": OS.get_name(), "os_version": OS.get_version().left(40),
		"gpu": RenderingServer.get_video_adapter_name().left(80), "screen": "%dx%d" % [screen.x, screen.y],
		"locale": OS.get_locale_language(), "pad": not Input.get_connected_joypads().is_empty(), "touch": DisplayServer.is_touchscreen_available()})
	for pair in [[Events.phase_changed, _on_phase], [Events.combat_ended, _on_fight], [Events.run_won, _on_won], [Events.run_lost, _on_lost]]:
		if not (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).connect(pair[1])
	_flush_in = 3.0

func active() -> bool:
	return allowed and enabled and _started

# Queues one event. `props` must be JSON-friendly; an oversized one is replaced by a marker.
func track(event: String, props := {}) -> void:
	if not active():
		return
	if JSON.stringify(props).length() > EVENT_MAX:
		props = {"too_big": true, "run": props.get("run", "")}
	queue.append({"e": event, "t": int(Time.get_unix_time_from_system()), "pid": player_id, "sid": session_id, "v": version(), "p": props})
	if not _busy:
		while queue.size() > QUEUE_MAX:
			queue.pop_front()
	_dirty = true

static func version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else "dev"

# --- the player's choice ------------------------------------------------------------------------------

# True while the first-launch notice should show (main menu).
func needs_notice() -> bool:
	return allowed and _started and not notice_shown

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		queue.clear()
		_run = {}
		DirAccess.remove_absolute(ProjectSettings.globalize_path(queue_path))
	_save_cfg({"enabled": on})

func notice_seen(keep_on: bool) -> void:
	notice_shown = true
	_save_cfg({"notice_shown": true})
	if not keep_on:
		set_enabled(false)

# What the Privacy tab says about where the stats go.
func status_text() -> String:
	if not allowed:
		return "Off in this build"
	if not enabled:
		return "Off"
	var url := OnlineConfig.telemetry_url()
	if url == "":
		return "Kept on this PC (%d waiting)" % queue.size()
	if status.begins_with("offline"):
		return "Server not answering (%d waiting)" % queue.size()
	return "On, %d sent this session" % sent

# --- runs -----------------------------------------------------------------------------------------

# GameManager calls this once a run (any mode) is set up. Ends with run_end: won, lost, placed (lobby),
# disconnected, or quit when the run scene goes away first (menu, restart, closing the game).
func run_started(gm: Node) -> void:
	if not active():
		return
	_finish_run("quit")
	var lvl := GameState.run_level
	var chapter: CampaignChapter = GameState.run_campaign.chapter_of(lvl) if lvl != null and GameState.run_campaign != null else null
	_run = {"run": _random_id(10), "mode": mode_of(gm), "level": str(lvl.id) if lvl != null else "", "chapter": str(chapter.id) if chapter != null else "",
		"msec": Time.get_ticks_msec(), "fights": 0, "wins": 0, "ended": false, "endless": false, "gm": gm}
	_fps_sum = 0.0
	_fps_n = 0
	_fps_low = 0.0
	_fps_seen = 0
	_prep_msec = Time.get_ticks_msec()
	_session_runs += 1
	var resumed := ""
	if gm.get("_resume") is Dictionary and not (gm.get("_resume") as Dictionary).is_empty():
		resumed = "mid_level"
	elif GameState.run_carried:
		resumed = "carried"
	var board = gm.get("board")
	track("run_start", {"run": _run.run, "mode": _run.mode, "level": _run.level, "chapter": _run.chapter, "resumed": resumed,
		"round": GameState.round_number, "king": str(KingSkins.selected()), "theme": str(board.theme) if board != null else "",
		"players": GameState.players.size() if gm.get("lobby") != null else 1})
	if not gm.tree_exiting.is_connected(_on_run_scene_exit):
		gm.tree_exiting.connect(_on_run_scene_exit)
	_remember("run")

# A lobby game ended for you: `place` of `of` (lobby_game.gd), or "disconnected" (place 0).
func lobby_ended(place: int, of: int) -> void:
	_finish_run("placed" if place > 0 else "disconnected", {"place": place, "of": of})

func tutorial_step(i: int, title: String) -> void:
	if not active():
		return
	var props := {"step": i, "title": title.left(60), "run": str(_run.get("run", ""))}
	if i > 0 and i == _tut_step + 1:
		props["prev_secs"] = snappedf((Time.get_ticks_msec() - _step_msec) / 1000.0, 0.1)
	_tut_step = i
	_step_msec = Time.get_ticks_msec()
	track("tutorial_step", props)

func menu_opened(screen: String) -> void:
	track("menu", {"screen": screen})

static func mode_of(gm: Node) -> String:
	if gm != null and gm.get("lobby") != null:
		return "lobby"
	if GameState.run_level != null:
		return "tutorial" if GameState.run_level.id == &"tutorial" else "campaign"
	return "async" if GameState.ghost_mode else "free"

func _on_phase(p: int) -> void:
	if _run.is_empty():
		return
	if p == Events.Phase.PREP:
		_prep_msec = Time.get_ticks_msec()
		if bool(_run.ended) and GameState.ghost_mode:   # async PvP's endless mode carries on after the win
			_run.ended = false
			_run.endless = true
			track("endless", {"run": _run.run, "round": GameState.round_number, "trophies": GameState.me.trophies})
	elif p == Events.Phase.COMBAT:
		_run["prep_secs"] = snappedf((Time.get_ticks_msec() - _prep_msec) / 1000.0, 0.1)
		_hp_at_fight = GameState.me.player_hp
	_remember("run", p)

func _on_fight(won: bool) -> void:
	if _run.is_empty() or bool(_run.ended):
		return
	_run.fights += 1
	if won:
		_run.wins += 1
	var me := GameState.me
	var gm = _gm()
	var props := {"run": _run.run, "mode": _run.mode, "level": _run.level, "round": GameState.round_number, "won": won,
		"hp": me.player_hp, "hp_lost": maxi(_hp_at_fight - me.player_hp, 0), "gold": me.gold, "player_level": me.level,
		"units": _board_units().size(), "prep_secs": float(_run.get("prep_secs", 0.0))}
	if gm != null and gm.get("runner") != null:
		props["secs"] = snappedf(int(gm.runner.ticks) * CombatRunner.TICK, 0.1)
	if _run.mode == "async":
		props["trophies"] = me.trophies
		props["losses"] = me.losses
	track("fight", props)

func _on_won() -> void:
	_finish_run("won")

func _on_lost() -> void:
	_finish_run("lost")

func _on_run_scene_exit() -> void:
	_finish_run("quit")
	_run = {}
	_remember("menu")

func _finish_run(result: String, extra := {}) -> void:
	if _run.is_empty() or bool(_run.ended):
		return
	_run.ended = true
	var me := GameState.me
	var units := _board_units()
	var comp: Array = []
	for u in units:
		comp.append("%s %d" % [u.data.display_name, u.star])
	var traits: Array = []
	var counts := Synergies.count(units)
	for tag in counts:
		var tier := Synergies.active_tier(tag, int(counts[tag]))
		if tier >= 0:
			traits.append("%s %d" % [tag, int(counts[tag])])
	var props := {"run": _run.run, "mode": _run.mode, "level": _run.level, "chapter": _run.chapter, "result": result,
		"round": GameState.round_number, "stage": "%d-%d" % [GameState.stage(), GameState.round_in_stage()],
		"secs": roundi((Time.get_ticks_msec() - int(_run.msec)) / 1000.0), "fights": _run.fights, "wins": _run.wins,
		"hp": me.player_hp, "player_level": me.level, "gold": me.gold, "comp": comp, "traits": traits, "endless": _run.endless,
		"fps_avg": snappedf(_fps_sum / _fps_n, 0.1) if _fps_n > 0 else 0.0, "fps_low": snappedf(_fps_low, 0.1)}
	if _run.mode == "async":
		props["trophies"] = me.trophies
		props["losses"] = me.losses
	if _run.mode == "tutorial":
		props["tutorial_step"] = _tut_step
	props.merge(extra, true)
	track("run_end", props)
	_save_queue()
	_flush_in = minf(_flush_in, 1.0)

func _gm() -> Node:
	var gm = _run.get("gm")
	return gm if gm != null and is_instance_valid(gm) else null

# Your units on the board (not the bench), while the run scene is still there.
func _board_units() -> Array:
	var out: Array = []
	var gm := _gm()
	if gm == null or not gm.is_inside_tree():
		return out
	var board = gm.get("board")
	if board == null or not is_instance_valid(board):
		return out
	for u in (board as Board).all_player_units():
		if u.coord.x >= 0 and u.mine():
			out.append(u)
	return out

# --- the session --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active():
		return
	if not _run.is_empty() and not bool(_run.ended):
		_fps_t += delta
		if _fps_t >= 1.0:
			_fps_t = 0.0
			_fps_seen += 1
			if _fps_seen > FPS_SKIP and not get_tree().paused and not Settings.unfocused:
				var fps := Engine.get_frames_per_second()
				_fps_sum += fps
				_fps_n += 1
				_fps_low = fps if _fps_low == 0.0 else minf(_fps_low, fps)
	_save_in -= delta
	if _save_in <= 0.0:
		_save_in = 10.0
		if _dirty:
			_save_queue()
	_flush_in -= delta
	if _flush_in <= 0.0:
		flush()

func _exit_tree() -> void:
	if not active():
		return
	_finish_run("quit")
	track("session_end", {"secs": roundi((Time.get_ticks_msec() - _session_msec) / 1000.0), "runs": _session_runs})
	_save_queue()   # sent on the next launch
	_save_cfg({}, {"running": false, "at": int(Time.get_unix_time_from_system())})

# Where the player is, so an unclean exit can say where it happened (next launch).
func _remember(where: String, phase := -1) -> void:
	if not active():
		return
	var names := {Events.Phase.PREP: "prep", Events.Phase.COMBAT: "fight", Events.Phase.RESULT: "result"}
	_save_cfg({}, {"where": where, "mode": str(_run.get("mode", "")), "level": str(_run.get("level", "")),
		"round": GameState.round_number if where == "run" else 0, "phase": names.get(phase, ""), "at": int(Time.get_unix_time_from_system())})

func _save_cfg(telemetry: Dictionary, last := {}) -> void:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	for k in telemetry:
		cfg.set_value("telemetry", k, telemetry[k])
	for k in last:
		cfg.set_value("last", k, last[k])
	cfg.save(cfg_path)

# --- uploading ------------------------------------------------------------------------------------

# Sends the oldest events (one batch) if a service is set up. Runs every FLUSH_EVERY seconds by itself.
func flush() -> void:
	_flush_in = _backoff
	if _busy or not active():
		return
	var url := OnlineConfig.telemetry_url()
	if url == "":
		status = "waiting for a server"
		return
	if queue.is_empty():
		return
	var batch := take_batch()
	if batch.is_empty():
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var key := OnlineConfig.snapshot_key()
	if key != "":
		headers.append("X-Api-Key: " + key)
	_busy = true
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _data: PackedByteArray):
		req.queue_free()
		_busy = false
		var c := code if result == HTTPRequest.RESULT_SUCCESS else 0
		if c == 200 or c == 201 or c == 400 or c == 413:
			queue = queue.slice(batch.size())   # taken, or refused for good (sending it again won't help)
			while queue.size() > QUEUE_MAX:
				queue.pop_front()
			_dirty = true
			if c == 200 or c == 201:
				sent += batch.size()
				status = "ok"
			else:
				status = "refused: HTTP %d" % c
			_backoff = FLUSH_EVERY
			_flush_in = BACKLOG_EVERY if not queue.is_empty() else FLUSH_EVERY
		else:   # unreachable, busy or rate-limited: wait longer each time
			status = "offline: " + ("no answer" if c == 0 else "HTTP %d" % c)
			_backoff = minf(_backoff * 2.0, RETRY_MAX)
			_flush_in = _backoff)
	var err := req.request(url + "/v1/events", headers, HTTPClient.METHOD_POST, JSON.stringify({"events": batch}))
	if err != OK:
		req.queue_free()
		_busy = false
		status = "offline: " + error_string(err)

# The oldest events that fit in one upload.
func take_batch() -> Array:
	var out: Array = []
	var bytes := 16
	for e in queue:
		var n := JSON.stringify(e).length() + 1
		if out.size() >= BATCH_MAX or (bytes + n > BATCH_BYTES and not out.is_empty()):
			break
		out.append(e)
		bytes += n
	return out

func _save_queue() -> void:
	_dirty = false
	if not enabled:
		return
	var f := FileAccess.open(queue_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(queue))
		f.close()

func _load_queue() -> Array:
	if not FileAccess.file_exists(queue_path):
		return []
	var q = JSON.parse_string(FileAccess.get_file_as_string(queue_path))
	if not q is Array:
		return []
	return (q as Array).filter(func(e): return e is Dictionary and e.has("e")).slice(-QUEUE_MAX)

static func _random_id(n: int) -> String:
	var bytes := Crypto.new().generate_random_bytes(n)
	return bytes.hex_encode()
