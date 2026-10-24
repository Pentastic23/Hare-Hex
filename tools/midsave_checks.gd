# midsave_checks.gd
# Dev tool, not part of the game: checks mid-level saves (a chapter run saved partway through a level;
# format in save_game.gd, code in GameManager: make_mid_save / _restore_mid / _resume_run). The main
# check plays a level with a scripted bot, saves in the middle of a PREP, reloads the save file and
# plays on with the same bot: every round of the resumed run must match the uninterrupted one. Run
# from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/midsave_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses a throwaway save file.

extends Node

var fails := 0
var main: Node
var gm
var board: Board
var camp: Campaign

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func L(n: String) -> CampaignLevel:
	return load("res://tres/campaign/levels/%s.tres" % n)

func frames(n := 3):
	for i in n:
		await get_tree().process_frame

# Starts `level` as the menu would: carry = a saved chapter run (or {}), seed = GameState.next_seed.
func start(level: CampaignLevel, carry: Dictionary, seed := 777):
	if main != null:
		main.free()
	GameState.ghost_mode = false
	GameState.run_level = level
	GameState.run_campaign = camp if level != null else null
	GameState.run_carry = carry
	GameState.launched_from_menu = true
	GameState.next_seed = seed
	GameState.reset()
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	add_child(main)
	gm = main.get_node("Game Manager")
	gm.prep_time = 9999
	board = main.get_node("Board")
	await frames()

func saved() -> Dictionary:
	return SaveGame.chapter_run()

func mid() -> Dictionary:
	var m = saved().get("mid", {})
	return m if m is Dictionary else {}

# Reads the save back from disk, as a new game session would (JSON numbers come back as floats).
func from_disk() -> Dictionary:
	SaveGame._loaded = false
	return SaveGame.chapter_run().duplicate(true)

# A fixed shopping routine: buy what it can afford (bench permitting), reroll once with 6+ gold and
# buy again, then Buy XP with 8+ gold. Only reads the game state, so the same state gives the same turn.
func bot_turn() -> void:
	var me := GameState.me
	for pass_i in 2:
		for d in me.shop_offers.duplicate():
			if me.gold >= d.cost and board.first_free_bench() != -1:
				Events.unit_bought.emit(d)
		if pass_i == 0 and me.gold >= 6:
			Events.reroll_pressed.emit()
	if me.gold >= 8:
		Events.buy_xp_pressed.emit()

# Everything a round depends on, as one string.
func sig() -> String:
	var me := GameState.me
	var units := []
	for u in board.all_player_units():
		units.append("%s*%d@%d,%d/b%d%s" % [u.data.display_name, u.star, u.coord.x, u.coord.y, board.bench.find(u), str(u.items.map(func(i): return String(i.id)))])
	units.sort()
	var pool := []
	for k in gm.shared_pool.remaining:
		pool.append(gm.shared_pool.remaining[k])
	return JSON.stringify([GameState.round_number, me.gold, me.player_hp, me.level, me.xp, me.win_streak, me.loss_streak,
		me.free_rerolls, me.cheap_shop, me.shop_locked, me.shop_offers.map(func(d): return d.display_name),
		me.items.map(func(i): return String(i.id)), units, pool, str(me.dropped)])

# Plays on to the end of the level (or `rounds` fights): fight, then the bot's turn in each new PREP.
# The first PREP's turn is skipped when `skip_first` (already played before a save). Returns one entry per round.
func play_on(skip_first: bool, rounds := 99) -> Array:
	var log := []
	var skip := skip_first
	for i in rounds:
		if gm.game_over:
			break
		if not skip:
			bot_turn()
		skip = false
		log.append("prep " + sig())
		gm.end_prep_early()
		var won: bool = gm.resolve_combat()
		log.append("fight %s over=%s" % [won, gm.game_over])
	return log

func _run():
	SaveGame.path = "user://midsave_test_save.json"
	SaveGame.reset_progress()
	Settings.path = "user://midsave_test_settings.cfg"
	Settings._loaded = true
	camp = load("res://tres/campaign/campaign.tres")
	var l1 := L("ch1_l1")
	var l2 := L("ch1_l2")

	print("--- written as you play")
	await start(l1, {})
	chk("a fresh chapter level saves at its first PREP", str(saved().get("level", "")) == "ch1_l1" and int(mid().get("round", 0)) == 1 and mid().get("phase") == "prep")
	chk("the save is a full carry too (the menu reads hp and level from it)", saved().has("hp") and saved().has("gold") and saved().has("units") and int(saved().hp) == GameState.me.player_hp)
	chk("RNG states are kept as text (JSON would round a 64-bit number)", mid().get("rng") is String and mid().get("player_rng") is String and str(mid().rng) == str(gm.rng.state))
	chk("the seed and the whole shared pool are in it", int(mid().get("seed", 0)) == GameState.run_seed and (mid().get("pool", {}) as Dictionary).size() == gm.shared_pool.remaining.size())
	bot_turn()
	var bought := board.all_player_units().size()
	get_tree().call_group("game_manager", "save_mid_run")   # what the pause menu (Main menu, Quit game) does
	chk("leaving during PREP saves the board as it is now", bought > 0 and saved().units.size() == bought and int(saved().gold) == GameState.me.gold, "%d units" % bought)
	var u0: Unit = board.all_player_units()[0]   # something changes...
	board.sell_unit(u0)
	gm._notification(NOTIFICATION_WM_CLOSE_REQUEST)                 # ...and the window is closed
	chk("closing the window during PREP saves too", saved().units.size() == bought - 1)
	gm.end_prep_early()
	chk("the fight's start is saved, with the board that fights", mid().get("phase") == "combat" and int(mid().round) == 1 and gm.fighting)
	var before_fight := JSON.stringify(saved())
	gm.save_mid_run()
	chk("leaving mid-fight keeps the save from the fight's start", JSON.stringify(saved()) == before_fight)
	gm.resolve_combat()
	chk("the next PREP saves round 2", int(mid().get("round", 0)) == 2 and mid().phase == "prep")

	print("--- a resumed run plays exactly like the uninterrupted one")
	await start(l1, {})
	play_on(false, 2)   # rounds 1 and 2
	bot_turn()          # round 3's shopping, then leave mid-PREP
	gm.save_mid_run()
	var carry := from_disk()   # the file as it is right now
	var at_save := sig()
	var round_at_save: int = GameState.round_number
	var a := play_on(true)
	var a_end := [GameState.me.player_hp, gm.game_over, str(saved().get("level", "")), saved().has("mid")]

	await start(l1, carry, 4242)   # a different seed asked for: the save's own seed must win
	chk("resumes at the saved round, in PREP", GameState.round_number == round_at_save and gm.phase == Events.Phase.PREP and not gm.fighting, "round %d" % GameState.round_number)
	chk("with the saved seed, not a new one", GameState.run_seed == int(carry.mid.seed))
	chk("exactly the saved state: board, bench, items, gold, shop, pool, streaks (no second income, drop or roll)", sig() == at_save, "" if sig() == at_save else "\n  saved   %s\n  resumed %s" % [at_save, sig()])
	chk("the shop shows the saved offers", GameState.me.shop_offers.size() == (carry.mid.offers as Array).size())
	chk("a full PREP timer", is_equal_approx(gm.prep_left, float(gm.prep_time)))
	var b := play_on(true)
	var b_end := [GameState.me.player_hp, gm.game_over, str(saved().get("level", "")), saved().has("mid")]
	var first_diff := -1
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			first_diff = i
			break
	chk("every following round matches (%d entries)" % a.size(), a.size() == b.size() and first_diff == -1 and a.size() >= 2,
		"" if first_diff == -1 else "\n  first difference at %d:\n  A %s\n  B %s" % [first_diff, a[first_diff], b[first_diff]])
	chk("and the level ends the same way", a_end == b_end, "%s vs %s" % [a_end, b_end])

	print("--- quitting mid-fight replays that fight")
	SaveGame.clear_chapter_run()
	await start(l1, {})
	bot_turn()
	gm.end_prep_early()   # the fight begins: saved
	var fight_save := from_disk()
	var won_a: bool = gm.resolve_combat()
	var after_a := sig()
	await start(l1, fight_save)
	chk("a save from a fight resumes straight into that fight", gm.phase == Events.Phase.COMBAT and gm.fighting and GameState.round_number == 1)
	var won_b: bool = gm.resolve_combat()
	chk("with the same result and the same next round", won_a == won_b and sig() == after_a, "" if sig() == after_a else "%s/%s\n  %s\n  %s" % [won_a, won_b, after_a, sig()])

	print("--- cleaned up when the level ends")
	gm.fighting = true
	GameState.round_number = GameState.total_rounds()
	gm._end_combat(true, 0)
	chk("winning the level replaces the save with the next level's start (no mid block)", str(saved().get("level", "")) == "ch1_l2" and not saved().has("mid"))
	gm.save_mid_run()
	chk("nothing more is written once the level is over", not saved().has("mid"))
	await start(l2, from_disk())
	chk("the next level saves itself as it is played", str(saved().get("level", "")) == "ch1_l2" and int(mid().get("round", 0)) == 1)
	GameState.me.player_hp = 1
	gm.fighting = true
	gm._end_combat(false, 0)
	chk("a defeat clears the chapter run", saved().is_empty())
	gm.save_mid_run()
	chk("and leaving after it writes nothing", saved().is_empty())

	print("--- old, broken and other runs")
	var bad := {"level": "ch1_l2", "hp": 50, "max_hp": 100, "gold": 7, "player_level": 3, "xp": 0, "items": [], "units": [], "mid": {"version": 99, "round": 3}}
	await start(l2, bad)
	chk("an unreadable mid block is ignored: the level starts from the carry (round 1, arrival heal)", GameState.round_number == 1 and GameState.me.player_hp == 60, "round %d hp %d" % [GameState.round_number, GameState.me.player_hp])
	chk("and a good save replaces it", int(mid().get("version", 0)) == SaveGame.MID_VERSION)
	var past_end := {"level": "ch1_l2", "hp": 50, "max_hp": 100, "gold": 7, "player_level": 3, "xp": 0, "items": [], "units": [], "mid": {"version": 1, "round": 99, "phase": "prep", "seed": 5, "rng": "1", "player_rng": "1", "pool": {}}}
	chk("a round past the level's end isn't resumed", SaveGame.mid_level(past_end, l2.waves.size()).is_empty())
	SaveGame.clear_chapter_run()
	await start(null, {})
	gm.save_mid_run()
	chk("free play never writes a chapter run", saved().is_empty())
	await start(load("res://tres/campaign/tutorial.tres") if ResourceLoader.exists("res://tres/campaign/tutorial.tres") else null, {})
	gm.save_mid_run()
	chk("nor does the tutorial", saved().is_empty())

	print("--- the menu")
	var menu_script = load("res://Scripts/main_menu.gd")
	var plain := {"level": "ch1_l2", "hp": 90}
	chk("Continue at a level's start: name and HP", menu_script.continue_text(l2, plain) == "Continue: %s (90 HP)" % l2.display_name, menu_script.continue_text(l2, plain))
	var partway := {"level": "ch1_l2", "hp": 72, "mid": {"version": 1, "round": 3, "phase": "prep", "seed": 5, "rng": "1", "player_rng": "1", "pool": {}}}
	chk("Continue partway through: the wave too", menu_script.continue_text(l2, partway) == "Continue: %s, wave 3/%d (72 HP)" % [l2.display_name, l2.waves.size()], menu_script.continue_text(l2, partway))

	main.queue_free()
	SaveGame.clear_chapter_run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

func _ready():
	_run.call_deferred()
