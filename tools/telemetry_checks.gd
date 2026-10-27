# telemetry_checks.gd
# Dev tool, not part of the game: checks the testers' telemetry. The client (telemetry.gd: the install id,
# sessions, an unclean exit noticed on the next launch, the queue kept on disk, the first-launch notice,
# turning it off, batches that fit an upload), the events a real run sends (free play, the tutorial, async
# PvP: run_start, fight, run_end when the run is left), the service (POST /v1/events: what it keeps and
# refuses, the key, its own rate budget; /stats and /v1/stats closed without the stats key), the numbers
# TelemetryStats makes from a set of events, and an upload over real HTTP on this machine (and the queue
# kept while the service is down).
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/telemetry_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway telemetry, save, settings and server files.

extends Node

const PORT := 18912
const DEAD_PORT := 18913   # nothing listens here
const CFG := "user://telemetry_test.cfg"
const QUEUE := "user://telemetry_test_queue.json"
const SERVER_DIR := "user://telemetry_test_server"

var fails := 0
var main: Node
var gm

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func wipe(path: String):
	var abs := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs)
		return
	if not DirAccess.dir_exists_absolute(abs):
		return
	for d in DirAccess.get_directories_at(abs):
		wipe(path + "/" + d)
	for f in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs + "/" + f)
	DirAccess.remove_absolute(abs)

func frames(n := 1):
	for i in n:
		await get_tree().process_frame

func until(cond: Callable, n := 300) -> bool:
	for i in n:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()

# Queued events called `name` (newest last).
func events(name: String) -> Array:
	return Telemetry.queue.filter(func(e): return e.e == name)

func last(name: String) -> Dictionary:
	var list := events(name)
	return list.back().p if not list.is_empty() else {}

func load_main(level: CampaignLevel = null, ghost := false):
	await leave_main()
	GameState.run_level = level
	GameState.run_campaign = null
	GameState.run_carry = {}
	GameState.next_seed = 7
	GameState.ghost_mode = ghost
	GameState.reset()
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	await frames(2)

func leave_main():
	if main != null:
		main.queue_free()
		main = null
		await frames(2)

func ev(name: String, pid: String, t: int, p: Dictionary, sid := "s1") -> Dictionary:
	return {"e": name, "pid": pid, "sid": sid + pid, "t": t, "v": "0.1.7", "p": p}

func _run():
	SaveGame.path = "user://telemetry_test_save.json"
	Settings.path = "user://telemetry_test_settings.cfg"
	Settings.load_settings()
	LocalSnapshotStore.root = "user://telemetry_test_snapshots"
	OnlineConfig.enabled = false   # free play keeps its ghosts local; telemetry gets its own address below
	OnlineConfig.telemetry_override = ""
	for p in [CFG, QUEUE, SERVER_DIR, "user://telemetry_test_snapshots"]:
		wipe(p)
	var T := Telemetry

	print("--- the client")
	chk("off in headless runs by default", not T.active())
	T.cfg_path = CFG
	T.queue_path = QUEUE
	T.allowed = true
	T.start()
	var first_id: String = T.player_id
	var first_sid: String = T.session_id
	chk("a random install id is made", first_id.length() == 32 and events("session_start").size() == 1 and bool(last("session_start").get("first", false)), first_id)
	chk("events carry the id, session and build", T.queue[0].pid == first_id and T.queue[0].sid == first_sid and str(T.queue[0].v) != "")
	chk("the first launch asks for the notice", T.needs_notice())
	T._save_queue()
	T.start()   # a second launch without _exit_tree in between: the first one "crashed"
	chk("the id is kept between launches", T.player_id == first_id and T.session_id != first_sid)
	chk("the queue is kept on disk", events("session_start").size() == 2 and not bool(last("session_start").get("first", true)))
	chk("an unclean exit is noticed on the next launch", events("unclean_exit").size() == 1 and str(last("unclean_exit").get("prev_session", "")) == first_sid, str(last("unclean_exit")))
	T.notice_seen(true)
	chk("the notice shows once", not T.needs_notice() and T.enabled)
	T._exit_tree()   # a clean exit
	chk("a clean exit ends the session", events("session_end").size() == 1)
	T.start()
	chk("no unclean exit after a clean one", events("unclean_exit").size() == 1)

	print("--- a free-play run")
	await load_main()
	var start := last("run_start")
	chk("run_start says free play", str(start.get("mode", "")) == "free" and str(start.get("run", "")) != "" and int(start.get("round", 0)) == 1, str(start))
	gm.end_prep_early()
	chk("a fight is reported", await until(func(): return not events("fight").is_empty(), 600))
	var fight := last("fight")
	chk("the fight has its round, result and prep time", int(fight.get("round", 0)) == 1 and fight.has("won") and fight.has("prep_secs") and str(fight.get("run", "")) == str(start.run), str(fight))
	var rounds_before: int = GameState.round_number
	await leave_main()
	var end := last("run_end")
	chk("leaving the run ends it as quit", str(end.get("result", "")) == "quit" and str(end.get("run", "")) == str(start.run) and int(end.get("round", 0)) == rounds_before, str(end))
	chk("run_end carries the length, fights and frame rate fields", end.has("secs") and int(end.get("fights", 0)) == 1 and end.has("fps_avg") and end.has("comp") and end.has("traits"))

	print("--- the tutorial and async PvP")
	await load_main(load("res://tres/campaign/tutorial.tres"))
	chk("run_start says tutorial", str(last("run_start").get("mode", "")) == "tutorial")
	chk("the first tutorial step is reported", not events("tutorial_step").is_empty() and int(last("tutorial_step").get("step", -1)) == 0 and str(last("tutorial_step").get("title", "")) != "")
	var tut = main.get_node("UI").find_child("TutorialPanel", true, false)
	if tut != null:
		tut._advance()
	chk("the next step reports the time on the one before", int(last("tutorial_step").get("step", -1)) == 1 and last("tutorial_step").has("prev_secs"), str(last("tutorial_step")))
	await leave_main()
	chk("leaving the tutorial says on which step", int(last("run_end").get("tutorial_step", -1)) == 1 and str(last("run_end").get("mode", "")) == "tutorial")
	await load_main(null, true)
	chk("run_start says async", str(last("run_start").get("mode", "")) == "async")
	await leave_main()

	print("--- turning it off")
	var n_before: int = T.queue.size()
	T.set_enabled(false)
	T.track("menu", {"screen": "test"})
	chk("off drops the queue and keeps nothing", n_before > 0 and T.queue.is_empty() and not FileAccess.file_exists(QUEUE) and not T.active())
	T.set_enabled(true)
	T.menu_opened("settings")
	chk("on again, events are kept", T.queue.size() == 1 and str(last("menu").get("screen", "")) == "settings")
	for i in 400:
		T.track("menu", {"screen": "x".repeat(200)})
	var batch: Array = T.take_batch()
	chk("a batch fits one upload", batch.size() < 400 and JSON.stringify({"events": batch}).length() <= T.BATCH_BYTES + 64 and batch.size() <= T.BATCH_MAX, "%d events" % batch.size())
	T.track("menu", {"screen": "y".repeat(T.EVENT_MAX)})
	chk("an oversized event is cut down", bool(last("menu").get("too_big", false)))
	T.queue.clear()

	print("--- the service")
	var srv := SnapshotServer.new()
	srv.log_requests = false
	add_child(srv)
	srv.data_dir = SERVER_DIR
	srv._load_roster()
	var good := [ev("session_start", "aaaa", 100, {"os": "Windows"}), ev("menu", "aaaa", 101, {"screen": "king"}),
		ev("hack", "aaaa", 102, {}), ev("menu", "bad id!", 103, {}), ev("menu", "aaaa", 104, {"x": "z".repeat(SnapshotServer.MAX_EVENT)})]
	var r: Array = srv.handle("POST", "/v1/events", {}, JSON.stringify({"events": good}))
	chk("good events are stored, junk skipped", r[0] == 201 and int(r[1].stored) == 2 and srv.events_stored == 2, str(r))
	var today := "%s/events/%s.jsonl" % [SERVER_DIR, Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()))]
	var lines := FileAccess.get_file_as_string(today).split("\n", false)
	chk("one JSON line per event in today's file, with the server's time", lines.size() == 2 and (JSON.parse_string(lines[0]) as Dictionary).has("rt"))
	chk("not JSON is refused", srv.handle("POST", "/v1/events", {}, "nope")[0] == 400)
	var many := []
	for i in SnapshotServer.MAX_EVENTS + 1:
		many.append(ev("menu", "aaaa", 1, {}))
	chk("too many events in one upload are refused", srv.handle("POST", "/v1/events", {}, JSON.stringify({"events": many}))[0] == 400)
	srv.api_key = "k"
	var body := JSON.stringify({"events": [good[1]]})
	chk("with a key set, uploads need it", srv.handle("POST", "/v1/events", {}, body)[0] == 401 and srv.handle("POST", "/v1/events", {"x-api-key": "k"}, body)[0] == 201)
	srv.api_key = ""
	var limited := false
	for i in SnapshotServer.EVENT_RATE + 1:
		limited = srv.handle("POST", "/v1/events", {}, body, "busy")[0] == 429
	chk("telemetry has a rate budget of its own", limited and srv.handle("GET", "/v1/health", {}, "", "busy")[0] == 200)
	chk("stats answer this machine without a stats key", srv.handle("GET", "/v1/stats", {}, "", "127.0.0.1")[0] == 200 and srv.handle("GET", "/v1/stats", {}, "", "8.8.8.8")[0] == 401)
	srv.stats_key = "s"
	var page: Array = srv.handle("GET", "/stats?key=s&days=7", {}, "", "8.8.8.8")
	chk("with a stats key, only the key opens them", srv.handle("GET", "/stats", {}, "", "127.0.0.1")[0] == 401 and page[0] == 200 and page.size() == 3 and str(page[2]).begins_with("text/html"))
	chk("the stats page is a whole page", str(page[1]).begins_with("<!doctype html>") and str(page[1]).contains("Modes") and str(page[1]).ends_with("</html>"))
	var json: Array = srv.handle("GET", "/v1/stats?key=s", {}, "", "8.8.8.8")
	chk("the JSON stats count the stored events", json[0] == 200 and int(json[1].overview.players) == 1 and int(json[1].overview.events) >= 3, str(json[1].get("overview", {})))
	var raw: Array = srv.handle("GET", "/v1/events?key=s&days=7", {}, "", "8.8.8.8")
	var raw_lines := str(raw[1]).split("\n", false)
	chk("the raw events download as JSON lines, one per stored event", raw[0] == 200 and str(raw[2]).begins_with("application/x-ndjson") \
		and raw_lines.size() == srv.events_stored and (JSON.parse_string(raw_lines[0]) as Dictionary).has("pid"), "%d lines, %d stored" % [raw_lines.size(), srv.events_stored])
	chk("the raw events need the stats key too", srv.handle("GET", "/v1/events", {}, "", "127.0.0.1")[0] == 401 and srv.handle("GET", "/v1/events?key=x", {}, "", "8.8.8.8")[0] == 401)
	srv.stats_key = ""

	print("--- the numbers")
	var E := [
		ev("session_start", "A", 1000, {"gpu": "Card X"}), ev("session_start", "B", 1000, {"gpu": "Card Y"}),
		ev("tutorial_step", "A", 1001, {"step": 0, "title": "Welcome"}), ev("tutorial_step", "A", 1011, {"step": 1, "title": "Buy", "prev_secs": 10.0}),
		ev("tutorial_step", "A", 1031, {"step": 2, "title": "Place", "prev_secs": 20.0}),
		ev("run_start", "A", 1000, {"run": "t1", "mode": "tutorial"}), ev("run_end", "A", 1040, {"run": "t1", "mode": "tutorial", "result": "quit", "round": 2, "tutorial_step": 2, "secs": 40}),
		ev("tutorial_step", "B", 1001, {"step": 0, "title": "Welcome"}), ev("tutorial_step", "B", 1031, {"step": 1, "title": "Buy", "prev_secs": 30.0}),
		ev("run_start", "A", 2000, {"run": "c1", "mode": "campaign", "level": "ch1_l1"}), ev("run_end", "A", 2600, {"run": "c1", "mode": "campaign", "level": "ch1_l1", "result": "lost", "round": 3, "secs": 600, "fps_avg": 50.0}),
		ev("run_start", "B", 2000, {"run": "c2", "mode": "campaign", "level": "ch1_l1"}), ev("run_end", "B", 2900, {"run": "c2", "mode": "campaign", "level": "ch1_l1", "result": "won", "round": 5, "secs": 900, "fps_avg": 25.0}),
		ev("run_start", "A", 3000, {"run": "f1", "mode": "free"}), ev("run_end", "A", 3100, {"run": "f1", "mode": "free", "result": "quit", "round": 5, "secs": 100}),
		ev("run_start", "A", 4000, {"run": "f2", "mode": "free"}), ev("run_end", "A", 5000, {"run": "f2", "mode": "free", "result": "lost", "round": 12, "secs": 1000}),
		ev("run_start", "B", 6000, {"run": "f3", "mode": "free"}),   # never ended: a crash
		ev("unclean_exit", "B", 7000, {"where": "run", "mode": "free", "round": 4, "phase": "fight"}),
		ev("menu", "A", 1, {"screen": "king"}), ev("menu", "B", 1, {"screen": "king"}),
	]
	for i in 3:
		E.append(ev("fight", "A", 2100 + i, {"mode": "campaign", "level": "<b>ch1_l1</b>", "round": 3, "won": i == 0, "prep_secs": 40.0}))
	var S := TelemetryStats.summarize(E)
	var mode := func(m: String) -> Dictionary:
		for row in S.modes:
			if row.mode == m:
				return row
		return {}
	var free: Dictionary = mode.call("free")
	chk("free play: 3 runs by 2 testers, 1 came back", free.runs == 3 and free.players == 2 and free.repeat_players == 1, str(free))
	chk("free play: 1 lost, 1 left, 1 never ended", free.lost == 1 and free.quit == 1 and free.unknown == 1)
	chk("where free play runs end, by round", (free.ends as Array).size() == 3 and (free.ends as Array).any(func(e): return int(e.round) == 12 and int(e.lost) == 1), str(free.ends))
	var camp: Dictionary = mode.call("campaign")
	chk("campaign: win rate 50%", is_equal_approx(camp.win_rate, 0.5) and camp.runs == 2)
	chk("campaign levels: ch1_l1 cleared once in two", S.levels.size() == 1 and S.levels[0].level == "ch1_l1" and is_equal_approx(S.levels[0].clear_rate, 0.5))
	chk("the tutorial funnel: 2, 2, 1 testers", S.tutorial.size() == 3 and S.tutorial[0].players == 2 and S.tutorial[1].players == 2 and S.tutorial[2].players == 1, str(S.tutorial))
	chk("time on a step comes from the next step", is_equal_approx(S.tutorial[0].avg_secs, 20.0) and is_equal_approx(S.tutorial[1].avg_secs, 20.0))
	chk("the tutorial step people left at", S.tutorial[2].left_here == 1)
	chk("the hardest fight: round 3 at 33%", S.hardest.size() == 1 and int(S.hardest[0].round) == 3 and is_equal_approx(S.hardest[0].win_rate, 1.0 / 3.0) and is_equal_approx(S.hardest[0].avg_prep, 40.0))
	chk("crashes say where", S.crashes.size() == 1 and str(S.crashes[0].where).contains("round 4"))
	chk("frame rate by graphics card, slowest first", S.gpus.size() == 2 and S.gpus[0].gpu == "Card Y")
	chk("menu screens: king opened by 2", S.menu.size() == 1 and S.menu[0].opens == 2 and S.menu[0].players == 2)
	var html := TelemetryStats.html(S)
	chk("the page escapes what the game sent", not html.contains("<b>ch1_l1</b>") and html.contains("&lt;b&gt;ch1_l1"))
	chk("the page has every section", ["Modes", "Where runs end", "Campaign levels", "Hardest fights", "Tutorial", "Stability", "Testers"].all(func(s): return html.contains(s)))
	chk("no events, no errors", TelemetryStats.html(TelemetryStats.summarize([])).contains("Nothing yet"))

	print("--- uploading over HTTP")
	chk("the service listens", srv.start(PORT, SERVER_DIR))
	T.queue.clear()
	T.sent = 0
	T.flush()
	chk("no address: events wait on this PC", T.status == "waiting for a server")
	for i in 5:
		T.menu_opened("upload_%d" % i)
	OnlineConfig.telemetry_override = "http://127.0.0.1:%d" % PORT
	var stored_before := srv.events_stored
	T.flush()
	chk("the queue goes up", await until(func(): return T.queue.is_empty() and T.sent == 5, 600), T.status)
	chk("the service stored them", srv.events_stored == stored_before + 5 and T.status == "ok")
	OnlineConfig.telemetry_override = "http://127.0.0.1:%d" % DEAD_PORT
	T.menu_opened("offline")
	T.flush()
	chk("with the service down, events are kept", await until(func(): return T.status.begins_with("offline"), 900) and T.queue.size() == 1, T.status)
	chk("and it waits longer before trying again", T._backoff > T.FLUSH_EVERY)

	OnlineConfig.telemetry_override = ""
	OnlineConfig.enabled = true
	T.allowed = false
	T.queue.clear()
	srv.stop()
	for p in [CFG, QUEUE, SERVER_DIR, "user://telemetry_test_snapshots", "user://telemetry_test_save.json", "user://telemetry_test_settings.cfg"]:
		wipe(p)
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
