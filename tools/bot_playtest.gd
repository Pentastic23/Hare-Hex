# bot_playtest.gd
extends Node

# Dev tool, not part of the game. A greedy bot plays campaign levels several times and prints
# how often it completes each one, so difficulty changes can be checked in a minute.
# Run from the project folder (headless, fast-forwarded):
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/bot_playtest.tscn --fixed-fps 60
# Only some levels: add their paths after "--", e.g. ... --fixed-fps 60 -- res://tres/campaign/levels/ch1_l3.tres
# Free play: "-- free" plays FREE_PLAY_ROUNDS rounds of free play (a smoke test for the random enemies).
# Whole chapter: "-- chapter2" plays chapter 2 CHAPTER_RUNS times as real chapter runs (board, gold,
# level, items and HP carry from level to level; a defeat ends the run). "-- chapter" plays every
# chapter in turn. This is the main balance check.
# Single levels (the default) start fresh with each level's own start settings.
# The bot buys whatever it can afford, fills the board strongest-first, equips items on its
# strongest units and buys XP when it has 10+ gold. It never positions units cleverly, so a
# human should do better than its numbers. Progress is written to a throwaway save, not yours.

const LEVELS := [
	"res://tres/campaign/levels/ch1_l1.tres",
	"res://tres/campaign/levels/ch1_l2.tres",
	"res://tres/campaign/levels/ch1_l3.tres",
]
const RUNS_PER_LEVEL := 10
const PREP_TIME := 2   # seconds of (fast-forwarded) prep per round
const FREE_PLAY_ROUNDS := 15
const CHAPTER_RUNS := 12

var main: Node
var gm
var board: Board
var waves: PackedStringArray = []

func _ready():
	_run.call_deferred()

func _run():
	SaveGame.path = "user://bot_playtest_save.json"
	SaveGame.reset_progress()
	print("level                 complete  final HP per run              waves (W/L per wave)")
	var paths: Array = OS.get_cmdline_user_args()
	if paths.is_empty():
		paths = LEVELS
	for path in paths:
		if path == "free":
			await _play(null, FREE_PLAY_ROUNDS)
			print("Free play            reached round %d, HP %d, level %d, waves %s" % [GameState.round_number, GameState.me.player_hp, GameState.me.level, "".join(waves)])
			continue
		if path.begins_with("chapter"):
			var camp: Campaign = load("res://tres/campaign/campaign.tres")
			if path == "chapter":
				for ci in camp.chapters.size():
					await _chapter_runs(camp, ci)
			else:
				await _chapter_runs(camp, int(path.substr(7)) - 1)
			continue
		var level: CampaignLevel = load(path)
		var wins := 0
		var hps := []
		var patterns := []
		for i in RUNS_PER_LEVEL:
			await _play(level)
			if gm.game_over and GameState.me.player_hp > 0 and GameState.me.last_combat_won:
				wins += 1
			hps.append(GameState.me.player_hp)
			patterns.append("".join(waves))
		print("%-20s  %2d/%-2d     %-28s  %s" % [level.display_name, wins, RUNS_PER_LEVEL, str(hps), " ".join(patterns)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	SaveGame.path = SaveGame.DEFAULT_PATH
	SaveGame._loaded = false
	get_tree().quit()

func _chapter_runs(camp: Campaign, chapter_index: int):
	var chapter: CampaignChapter = camp.chapters[chapter_index]
	print("--- chapter %d: %s" % [chapter_index + 1, chapter.display_name])
	var first: CampaignLevel = chapter.levels[0]
	var cleared := {}
	var completed := 0
	for i in CHAPTER_RUNS:
		GameState.run_carry = {}
		var level := first
		var parts: PackedStringArray = []
		while level != null:
			await _play(level)
			var won: bool = gm.game_over and GameState.me.player_hp > 0 and GameState.me.last_combat_won
			parts.append("%s %s %d HP (lvl %d, %d units) [%s]" % [level.id, "WIN" if won else "LOSS", GameState.me.player_hp, GameState.me.level, board.all_player_units().size(), "".join(waves)])
			if not won:
				break
			cleared[level.id] = int(cleared.get(level.id, 0)) + 1
			if GameState.run_carry.is_empty():
				completed += 1
				break
			level = camp.find_level(StringName(str(GameState.run_carry.level)))
		print("run %2d: %s" % [i + 1, "  ->  ".join(parts)])
	var summary: PackedStringArray = []
	for lvl in chapter.levels:
		summary.append("%s cleared %d/%d" % [lvl.id, int(cleared.get(lvl.id, 0)), CHAPTER_RUNS])
	print("CHAPTER %d: completed %d/%d runs | %s" % [chapter_index + 1, completed, CHAPTER_RUNS, ", ".join(summary)])

func _play(level: CampaignLevel, max_rounds := 999):
	if main != null:
		main.free()
	GameState.run_level = level
	GameState.run_campaign = null
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = PREP_TIME
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	waves = []
	var on_phase := func(p):
		if p == Events.Phase.PREP:
			_bot_turn.call_deferred()
	var on_end := func(won):
		waves.append("W" if won else "L")
	Events.phase_changed.connect(on_phase)
	Events.combat_ended.connect(on_end)
	var frames := 0
	while not gm.game_over and GameState.round_number <= max_rounds and frames < 100000:
		await get_tree().process_frame
		frames += 1
	Events.phase_changed.disconnect(on_phase)
	Events.combat_ended.disconnect(on_end)

func _bot_turn():
	await get_tree().process_frame   # let income, drops and the shop roll happen first
	if gm.game_over:
		return
	for d in GameState.me.shop_offers.duplicate():
		var keep := 0 if GameState.round_number < 3 else 2
		if GameState.me.gold >= d.cost + keep and (board.first_free_bench() != -1 or board.would_complete_merge(d)):
			Events.unit_bought.emit(d)
	if GameState.me.gold >= 10:
		Events.buy_xp_pressed.emit()
	var strength := func(a, b): return a.data.cost * a.star > b.data.cost * b.star
	var bench_units: Array = board.bench.filter(func(u): return u != null)
	bench_units.sort_custom(strength)
	for u in bench_units:
		if board.units_on_board() >= GameState.me.max_board_units():
			break
		for c in board.player_order:
			if board.is_unlocked(c) and board.tiles[c].occupant == null:
				board.detach(u)
				board.put_on_tile(u, c)
				break
	var on_board: Array = board.all_player_units().filter(func(u): return u.coord.x >= 0)
	on_board.sort_custom(strength)
	for item in GameState.me.items.duplicate():   # each item onto the strongest unit that can take it (Tongs are never worn)
		for u in on_board:
			if u.can_take(item):
				main.get_node("DragController").equip_item_on(u, item)
				break
	if gm.manual_start:   # chapter levels have no prep timer: the bot presses Start fight
		gm.end_prep_early()
