# async_checks.gd
# Dev tool, not part of the game: checks async PvP's online ghosts and rules. The ghost service
# (SnapshotServer: health, uploads checked against the roster, the API key, finding candidates, keeping them
# on disk, the rate limit), the online store over real HTTP on this machine (upload, prefetch, pick, the
# fallback to local ghosts when the service is down), a ghost-mode run against the service (its boards go
# up, an online ghost that arrives during PREP is announced), trophies and lives (no HP), 10 trophies and
# the end screen's Endless mode, the end of endless, Start fight in campaign chapters, and fast forward
# (the same fight at 1x and 3x, the clock back to normal after it).
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/async_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway save, settings, snapshot and server folders.

extends Node

const PORT := 18910
const DEAD_PORT := 18911    # nothing listens here
const SERVER_DIR := "user://async_test_server"
const LOCAL_DIR := "user://async_test_snapshots"

var fails := 0
var main: Node
var gm
var board: Board

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func U(n: String) -> UnitData:
	for path in ["res://tres/%s.tres" % n, "res://tres/units/%s.tres" % n]:
		if ResourceLoader.exists(path):
			return load(path)
	return null

func wipe(path: String):
	var abs := ProjectSettings.globalize_path(path)
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

# Waits up to `n` frames for `cond` to hold.
func until(cond: Callable, n := 300) -> bool:
	for i in n:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()

func load_main(seed := 0, ghost := false, level: CampaignLevel = null):
	if main != null:
		main.free()
		await frames(1)
	GameState.run_level = level
	GameState.run_campaign = null
	GameState.run_carry = {}
	GameState.next_seed = seed
	GameState.ghost_mode = ghost
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await frames(2)

# A board snapshot as a ghost-mode run records it: `n` Knights at level `level` in `round`.
func ghost(run: String, round: int, level: int, balance: String, n := 1, trophies := 2) -> Dictionary:
	var units := []
	for i in n:
		units.append({"unit": "Knight", "star": 1, "coord": [3 - i, 3], "items": []})
	return {"version": BoardSnapshot.VERSION, "balance": balance, "created": 1, "run": run, "round": round, "stage": "1-%d" % round,
		"player_level": level, "hp": 100, "trophies": trophies, "losses": 1, "name": "Tester", "board": {"name": "Tester", "units": units}}

func post(server: SnapshotServer, s, key := "", addr := "a") -> Array:
	var headers := {"x-api-key": key} if key != "" else {}
	return server.handle("POST", "/v1/snapshots", headers, s if s is String else JSON.stringify(s), addr)

func _run():
	SaveGame.path = "user://async_test_save.json"
	Settings.path = "user://async_test_settings.cfg"
	Settings.load_settings()
	Settings.fight_speed = 1
	Settings.show_top_bar = true   # (your own settings may have it folded)
	LocalSnapshotStore.root = LOCAL_DIR
	OnlineConfig.enabled = true
	OnlineConfig.url_override = ""
	wipe(SERVER_DIR)
	wipe(LOCAL_DIR)
	var probe := load("res://scenes/main.tscn").instantiate() as Node
	var balance := BoardSnapshot.balance_hash(probe.get_node("Game Manager").unit_pool, [])
	probe.free()

	print("--- the ghost service")
	var srv := SnapshotServer.new()
	srv.log_requests = false
	add_child(srv)
	srv.data_dir = SERVER_DIR
	srv._load_roster()
	srv._load_store()
	var health: Array = srv.handle("GET", "/v1/health", {}, "")
	chk("health answers", health[0] == 200 and health[1].ok and health[1].api == SnapshotServer.API)
	var ok := post(srv, ghost("runA", 3, 3, balance))
	chk("a good snapshot is stored", ok[0] == 201 and str(ok[1].get("id", "")) != "" and srv.count() == 1, str(ok))
	var bad_unit := ghost("runB", 3, 3, balance)
	bad_unit.board.units[0].unit = "Not A Unit"
	var too_many := ghost("runB", 3, 1, balance, 3)
	var off_half := ghost("runB", 3, 3, balance)
	off_half.board.units[0].coord = [3, 5]
	var bad_item := ghost("runB", 3, 3, balance)
	bad_item.board.units[0].items = ["no_such_item"]
	var refused := [post(srv, bad_unit), post(srv, too_many), post(srv, off_half), post(srv, bad_item), post(srv, "{not json"), post(srv, {"version": 1})]
	chk("junk is refused: unknown unit, too many units for the level, off the enemy half, unknown item, not JSON, not a snapshot",
		refused.all(func(r): return r[0] == 400) and srv.count() == 1, str(refused.map(func(r): return r[1].get("error", ""))))
	var named := ghost("runN", 4, 3, balance)
	named.name = "  A very long name that goes on and on  "
	named.created = 5
	post(srv, named)
	var stored: Dictionary = srv.find(4, 10, "", "", 5)[0]
	chk("the server cleans what it keeps (name length, its own time, an id)", stored.name.length() <= LobbyProtocol.NAME_MAX and int(stored.created) > 1000000 and str(stored.id) != "" and stored.trophies == 2)
	var free_play := ghost("runF", 4, 3, balance)
	free_play.erase("trophies")
	free_play.erase("losses")
	post(srv, free_play)
	chk("a free-play board stays without trophies", srv.find(4, 10, "", "", 10).filter(func(s): return s.run == "runF" and not s.has("trophies")).size() == 1)

	post(srv, ghost("runC", 3, 3, "older"))
	post(srv, ghost("runD", 2, 2, balance))
	post(srv, ghost("runE", 3, 6, balance, 1))
	var found: Array = srv.handle("GET", "/v1/snapshots?round=3&level=4&balance=%s&exclude=runD&limit=10" % balance, {}, "")[1].snapshots
	var runs := found.map(func(s): return s.run)
	chk("finding: rounds 2-4, not above the level, not the asking run, today's balance first",
		runs.has("runA") and runs.has("runC") and not runs.has("runD") and not runs.has("runE") and runs.find("runC") > runs.find("runA"), str(runs))
	var keyed := SnapshotServer.new()
	keyed.log_requests = false
	add_child(keyed)
	keyed.data_dir = SERVER_DIR + "_keyed"
	keyed.api_key = "sesame"
	keyed._load_roster()
	chk("with a key, uploads need it", post(keyed, ghost("k", 1, 1, balance))[0] == 401 and post(keyed, ghost("k", 1, 1, balance), "sesame")[0] == 201)
	keyed.queue_free()
	wipe(SERVER_DIR + "_keyed")
	var again := SnapshotServer.new()
	again.data_dir = SERVER_DIR
	again._load_roster()
	again._load_store()
	chk("snapshots survive a restart (read back from disk)", again.count() == srv.count(), "%d vs %d" % [again.count(), srv.count()])
	again.free()
	var codes := []
	for i in SnapshotServer.RATE + 1:
		codes.append(srv.handle("GET", "/v1/health", {}, "", "flood")[0])
	chk("one address can't flood it", codes[0] == 200 and codes[-1] == 429)
	srv.queue_free()

	print("--- the online store over HTTP")
	wipe(SERVER_DIR)
	srv = SnapshotServer.new()
	srv.log_requests = false
	add_child(srv)
	chk("the service listens", srv.start(PORT, SERVER_DIR))
	var url := "http://127.0.0.1:%d" % PORT
	var store := HttpSnapshotStore.new(url, "", self, LocalSnapshotStore.new())
	store.submit(ghost("netA", 5, 4, balance))
	chk("an upload reaches the service", await until(func(): return store.sent == 1) and srv.count() == 1)
	chk("and a local copy is kept", LocalSnapshotStore.new().count(5) == 1)
	var got := []
	store.fetched.connect(func(r): got.append(r))
	store.prefetch(5, 4, balance, "me")
	chk("prefetch brings this round's ghosts", await until(func(): return got.has(5)) and store.has_batch(5) and store.status == "ok", store.status)
	wipe(LOCAL_DIR)
	var rng := RandomNumberGenerator.new()
	var pick := store.fetch(5, 4, balance, rng, "me")
	chk("fetch picks the online ghost", pick.get("run") == "netA" and bool(pick.get("_online", false)))
	chk("never your own run", store.fetch(5, 4, balance, rng, "netA").is_empty())
	var down := HttpSnapshotStore.new("http://127.0.0.1:%d" % DEAD_PORT, "", self, LocalSnapshotStore.new())
	LocalSnapshotStore.new().submit(ghost("localL", 6, 4, balance))
	down.prefetch(6, 4, balance, "me")
	chk("with the service down, prefetch gives up", await until(func(): return down.status.begins_with("offline"), 600), down.status)
	chk("and fetch falls back to the local ghosts", down.fetch(6, 4, balance, rng, "me").get("run") == "localL")
	down.submit(ghost("localM", 7, 4, balance))
	await until(func(): return down._outbox.size() == 1, 600)
	chk("a failed upload waits to be retried", down._outbox.size() == 1 and down.sent == 0)

	print("--- a ghost-mode run against the service")
	wipe(LOCAL_DIR)
	OnlineConfig.url_override = url
	await load_main(4242, true)
	chk("async PvP uses the online store when an address is set", gm.snapshot_store is HttpSnapshotStore)
	var before := srv.count()
	if gm.phase == Events.Phase.PREP:
		gm.end_prep_early()
	if gm.fighting:
		gm.resolve_combat()
	chk("the board that fought went up to the service", await until(func(): return srv.count() == before + 1), "%d -> %d" % [before, srv.count()])
	var up: Dictionary = srv.find(1, 10, "", "x", 50).filter(func(s): return s.run == str(GameState.run_seed)).front() if srv.find(1, 10, "", "x", 50).any(func(s): return s.run == str(GameState.run_seed)) else {}
	chk("with its trophies and losses", up.has("trophies") and up.has("losses"), str(up.keys()))
	# A new run with nothing on this PC: its opening ghost can only come from the service, and may land
	# after PREP began; it is announced when it does.
	wipe(LOCAL_DIR)
	srv.add(ghost("someone", 1, 1, gm.balance_hash))
	await load_main(5151, true)
	var row_of := func(): return main.get_node("UI/Standings").opponent_row()
	chk("an online ghost is announced for the opening", await until(func(): return row_of.call() != null and row_of.call().name_text.begins_with("Ghost of")), row_of.call().name_text if row_of.call() else "no row")
	chk("its row shows its lives, not HP", row_of.call() != null and row_of.call().max_hp == GameState.ASYNC_LIVES)
	OnlineConfig.url_override = ""
	srv.stop()
	srv.queue_free()

	print("--- trophies and lives")
	OnlineConfig.enabled = false
	await load_main(9090, true)
	chk("offline, async PvP uses the local store", gm.snapshot_store is LocalSnapshotStore)
	var me := GameState.me
	var hp := me.player_hp
	var gold := me.gold
	gm.runner.fighting = true
	gm._end_combat(true, 0)
	await frames(2)
	chk("a win is a trophy and a gold", me.trophies == 1 and me.losses == 0 and me.gold >= gold + 1)
	gm.runner.fighting = true
	gm._end_combat(false, 3)
	await frames(2)
	chk("a loss costs a life, never HP", me.losses == 1 and me.lives_left() == 9 and me.player_hp == hp)
	var you: StandingRow = main.get_node("UI/Standings").you_row()
	chk("your standings row shows lives out of 10", you != null and you.hp == 9 and you.max_hp == 10)
	var tracker = main.get_node("UI/TopBar").rounds
	chk("the top bar counts trophies", tracker.stage_label.text == "TROPHIES" and tracker.count_label.text == "1/10" and tracker.pips.states.size() == 10, "%s %s %d" % [tracker.stage_label.text, tracker.count_label.text, tracker.pips.states.size()])
	GameState.round_number = 45
	chk("async PvP has no last round", not GameState.is_final_round())
	me.trophies = 9
	var won := [false]
	var on_won := func(): won[0] = true
	Events.run_won.connect(on_won)
	gm.runner.fighting = true
	gm._end_combat(true, 0)
	await frames(2)
	Events.run_won.disconnect(on_won)
	var end = main.get_node("UI/End Screen")
	chk("10 trophies wins the run", won[0] and gm.game_over and me.trophies == 10)
	chk("the end screen offers Endless mode", end.visible and end.title.text == "VICTORY" and end.next_button.visible and end.next_button.text == "Endless mode")
	chk("the best result is saved", SaveGame.async_best() == 10)
	var round_was := GameState.round_number
	end.next_button.pressed.emit()
	await frames(2)
	chk("Endless mode goes on to the next round", not gm.game_over and me.endless and not end.visible and gm.phase == Events.Phase.PREP and GameState.round_number == round_was + 1)
	chk("the top bar says ENDLESS", tracker.stage_label.text == "ENDLESS" and tracker.count_label.text == "10")
	gm.runner.fighting = true
	gm._end_combat(true, 0)
	await frames(2)
	chk("endless keeps counting trophies", me.trophies == 11 and not gm.game_over)
	me.losses = 9
	var lost := [false]
	var on_lost := func(): lost[0] = true
	Events.run_lost.connect(on_lost)
	gm.runner.fighting = true
	gm._end_combat(false, 1)
	await frames(2)
	Events.run_lost.disconnect(on_lost)
	chk("the 10th loss ends endless mode", lost[0] and gm.game_over and end.visible and end.title.text == "ENDLESS OVER" and SaveGame.async_best() == 11)
	await load_main(9191, true)
	me = GameState.me
	me.losses = 9
	gm.runner.fighting = true
	gm._end_combat(false, 1)
	await frames(2)
	end = main.get_node("UI/End Screen")
	chk("10 losses before 10 trophies is a defeat, without Endless mode", gm.game_over and end.title.text == "DEFEAT" and not end.next_button.visible)

	print("--- Start fight and fast forward")
	var ch1: CampaignLevel = load("res://tres/campaign/levels/ch1_l1.tres")
	await load_main(1234, false, ch1)
	var timer = main.get_node("UI/TopBar").timer
	await frames(2)
	chk("a chapter level has no prep timer: START FIGHT instead", gm.manual_start and gm.prep_left >= gm.UNTIMED - 1.0 and timer.start_button.visible)
	chk("and the speed button", timer.speed_button.visible and timer.speed_button.text == "1x")
	var sigs := []
	var ticks_frames := []
	for speed in [1, 3]:
		await load_main(1234, false, ch1)
		gm.set_fight_speed(speed)
		var k := board.make_unit(U("knight"), gm.unit_scene)
		board.put_on_tile(k, board.open_player_tiles(GameState.me.level)[0])
		var a := board.make_unit(U("archer"), gm.unit_scene)
		board.put_on_tile(a, board.open_player_tiles(GameState.me.level)[1])
		gm.end_prep_early()
		var scale_seen := Engine.time_scale
		var n := 0
		while gm.fighting and n < 5000:
			await get_tree().physics_frame
			n += 1
		sigs.append("won=%s ticks=%d k=%.3f/%.3f a=%.3f/%.3f" % [GameState.me.last_combat_won, gm.combat_ticks, k.damage_dealt, k.damage_taken, a.damage_dealt, a.damage_taken])
		ticks_frames.append([gm.combat_ticks, n, scale_seen])
	chk("the same fight at 1x and 3x", sigs[0] == sigs[1] and ticks_frames[0][0] > 30, "%s | %s" % sigs)
	chk("3x takes about a third of the frames", ticks_frames[1][1] * 2 < ticks_frames[0][1], str(ticks_frames))
	chk("the clock runs 3x during the fight and normal after it", is_equal_approx(ticks_frames[1][2], 3.0) and is_equal_approx(Engine.time_scale, 1.0) and is_equal_approx(ticks_frames[0][2], 1.0))
	chk("the speed is remembered", Settings.fight_speed == 3)
	await load_main(55, false)
	await frames(2)
	timer = main.get_node("UI/TopBar").timer
	chk("free play keeps its prep timer and has no fast forward", not gm.manual_start and gm.fight_speed == 1 and not timer.speed_button.visible and not timer.start_button.visible)
	gm.set_fight_speed(3)
	chk("and can't be fast-forwarded", gm.fight_speed == 1)
	await load_main(56, false, load("res://tres/campaign/tutorial.tres"))
	chk("the tutorial keeps its own Start fight (no fast forward)", not gm.manual_start and not gm.can_fast_forward())

	main.free()
	await frames(1)
	OnlineConfig.enabled = true
	GameState.ghost_mode = false
	GameState.run_level = null
	Engine.time_scale = 1.0
	wipe(SERVER_DIR)
	wipe(LOCAL_DIR)
	LocalSnapshotStore.root = ""
	for p in [SaveGame.path, Settings.path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
