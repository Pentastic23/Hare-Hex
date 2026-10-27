# game_manager.gd
extends Node

var phase: int = Events.Phase.PREP
# The fight on the visible board (combat_runner.gd). The fields below read and write it, so the HUD
# and the tests can keep using gm.fighting, gm.combatants, gm.combat_ticks...
var runner: CombatRunner
var fighting: bool:
	get: return runner != null and runner.fighting
	set(v):
		if runner != null:
			runner.fighting = v
var combat_time: float:
	get: return runner.time if runner != null else 0.0
var snapshot := {}   # Unit -> Vector2i
var snapshot_store: SnapshotStore   # async PvP boards; null in campaign levels
var balance_hash := ""              # BoardSnapshot.balance_hash of the roster and items
var unit_scene: PackedScene = preload("res://scenes/unit.tscn")
@export var prep_time := 30   # seconds of PREP; a campaign level can override it (prep_time > 0)
@onready var board: Board = $"../Board"
@export var unit_pool: Array[UnitData] = []
# TEMPORARY while the unit models are tested: only units with a model (UnitData.model) are used, in
# the shop, the planner and free-play enemies. Turn off (or delete) once every unit has a model.
@export var only_units_with_models := false
@export var item_roster: Array[ItemData] = []   # items that can drop; also resolves ids when loading saves
@export_range(0.0, 1.0) var enemy_variation_chance := 0.3   # 30% of rounds get +1 or -1
const REROLL_COST := PlayerRules.REROLL_COST
const BUY_XP_COST := PlayerRules.BUY_XP_COST
@export var enemy_base_scale := 0.6        # round 1 enemies are 60% strength
@export var enemy_scale_per_round := 0.08  # +8% each round
var game_over := false
# Plays this campaign level instead of free play when main.tscn is run directly (F6 in the editor),
# for testing. Ignored when the game was started from the main menu.
@export var debug_level: CampaignLevel
# With Debug Level set, launching the game continues a saved chapter run in the same chapter.
@export var continue_saved_run := true
const DEFAULT_CAMPAIGN := "res://tres/campaign/campaign.tres"
var roster: Array[UnitData] = []   # units the shop can offer: unit_pool, or the level's allowed_units
var opponents: OpponentProvider
var current_board: EnemyBoard      # the enemy board of the current/last fight (for its hp_reward)
const COMBAT_TICK := CombatRunner.TICK            # seconds of fight per tick
const COMBAT_MAX_TICKS := CombatRunner.MAX_TICKS  # 60 s; reaching it counts as a loss
var combatants: Array[Unit]:   # fixed acting order for the current fight
	get: return runner.combatants if runner != null else _no_units
var new_summons: Array[Unit]:
	get: return runner.new_summons if runner != null else _no_units
var zones: Array:   # ground effects from abilities this fight (add_zone)
	get: return runner.zones if runner != null else []
var combat_ticks: int:
	get: return runner.ticks if runner != null else 0
var _no_units: Array[Unit] = []
var prep_left := 0.0   # seconds of PREP left; 0 when not in PREP
# Seconds between a fight's end and the next PREP (the fallers and the victory dance finish first). Headless
# runs (the check suites, the bot) skip it.
var result_pause := 0.0 if DisplayServer.get_name() == "headless" else 3.0
# Async PvP and campaign chapter levels: no prep timer, the player presses Start fight (the top bar). Round 1
# of async PvP is the opening instead: a free unit already on the board, the shop shut, and the fight starts
# by itself. The same modes can fast forward fights (fight_speed).
var manual_start := false
# Fast forward: fight ticks per physics frame (1, 2 or 3; Settings.fight_speed). The fight is the same at any
# speed (it is a fixed number of fixed ticks); Engine.time_scale follows it during a fight so the animations,
# effects and the fall of the dead keep pace.
var fight_speed := 1
const MAX_FIGHT_SPEED := 3
var ghost_rng := RandomNumberGenerator.new()   # async PvP ghost picks (seeded from the run; online ghosts arrive at any time, so not the run RNG)
var prep_length := 0.0   # how long this PREP started out (the top bar's track)
const UNTIMED := 1000000.0      # prep_left / prep_time of a prep that waits for Start fight
const OPENING_PREP := 4.0       # seconds before the opening fight starts by itself
var _result_timer: Timer
var _replay_wave := false   # the coming PREP fights a lost final wave again (no new item drop)
var rng := RandomNumberGenerator.new()   # run RNG (seeded): random enemies and placement. Shop and drops use GameState.me.rng.
var shared_pool: UnitPool
var rules: PlayerRules   # the local player's actions and round economy (player_rules.gd), shared with the lobby server
var lobby: LobbyGame   # lobby mode (LobbyNet.in_lobby()): this scene shows a lobby game, see lobby_game.gd
var _resume := {}   # the "mid" block of the saved chapter run being resumed; {} = the level starts normally



func _on_unit_bought(d: UnitData):
	if lobby != null:
		lobby.buy(d)
		return
	if game_over: return
	# Outside PREP a purchase only goes to the bench: no merges while units are fighting.
	rules.buy(d, phase == Events.Phase.PREP, false)

func _enter(p: int):
	if game_over: return
	phase = p
	Events.phase_changed.emit(p)
	match p:
		Events.Phase.PREP:
			# Income (+ Coin Purses), free rerolls (Merchant's Ledger), the item drop, merges, the shop: PlayerRules.
			var opening := is_opening()
			rules.start_prep(GameState.round_number, GameState.round_number == 1 and not GameState.run_carried, opening, not _replay_wave)
			_replay_wave = false
			Events.round_changed.emit(GameState.stage(), GameState.round_in_stage())
			Music.play("boss" if is_boss_round() else "game")   # Final Struggle for the boss round, else Aspiration Woods
			if opponents != null:
				opponents.prepare(GameState.round_number)   # async PvP picks this round's ghost now
				Events.opponent_announced.emit(opponents.describe_next())
			_dress_kings()   # the ghost's king, and a Shadow King takes its shape
			_open_foe_half()
			# counted down in _process, so the timer label can show it and pausing stops it
			prep_length = OPENING_PREP if opening else (UNTIMED if manual_start else float(prep_time))
			prep_left = prep_length
			_write_mid("prep")   # a chapter run is saved at the start of every PREP...
		Events.Phase.COMBAT:
			_write_mid("combat")   # ...and of every fight, with the board as it fights (so quitting can't dodge a loss)
			start_combat()
		Events.Phase.RESULT:
			if GameState.ghost_mode:   # async PvP: trophies and lives, not HP
				var me := GameState.me
				if me.losses >= GameState.ASYNC_LIVES:
					_lose_run()
					return
				if me.trophies >= GameState.ASYNC_TROPHIES and not me.endless:
					_win_run()   # the end screen offers endless mode (continue_endless)
					return
			if GameState.me.player_hp <= 0:
				_lose_run()
				return
			if GameState.is_final_round():
				# A campaign level is only complete once its final wave is beaten: lost with HP left, the
				# final wave comes again next round (HP is what runs out, not the level). The tutorial also
				# waits for its last step (tutorial.gd finished()): until then its last wave comes again.
				var tut = get_tree().get_first_node_in_group("tutorial")
				var steps_left: bool = tut != null and tut.is_visible_in_tree() and not tut.finished()
				if GameState.run_level != null and (not GameState.me.last_combat_won or steps_left):
					_replay_wave = true
					Events.notice.emit("FINISH THE TUTORIAL STEPS" if steps_left and GameState.me.last_combat_won else "THE LAST WAVE COMES AGAIN", HudStyle.GOLD)
					if result_pause > 0.0:
						_result_timer.start(result_pause)
					else:
						_next_round()
					return
				_win_run()
				return
			if result_pause > 0.0:
				_result_timer.start(result_pause)   # a child Timer: it stops while paused and goes with the scene
			else:
				_next_round()

# Round 1 of async PvP is the opening (PlayerRules.start_prep): a free unit on the board, no shop, and the
# fight starts by itself. Lobbies have the same opening, run by the server.
func is_opening() -> bool:
	return GameState.ghost_mode and GameState.round_number == 1 and not GameState.run_carried

func _next_round() -> void:
	if game_over or phase != Events.Phase.RESULT:
		return
	if not _replay_wave:
		GameState.round_number += 1   # (a lost final wave is fought again: same round)
	GameState.me.add_xp(2)
	_enter(Events.Phase.PREP)

			
func _ready():
	add_to_group("game_manager")   # shop_slot.gd finds us by group; the node name has a space
	_result_timer = Timer.new()
	_result_timer.one_shot = true
	_result_timer.timeout.connect(_next_round)
	add_child(_result_timer)
	runner = CombatRunner.new(board)
	runner.on_finish = func(alive: Array, _stars: Array): _end_combat(alive[1] == 0 and alive[0] > 0, alive[1])
	runner.gold_sink = func(team: int, amount: int):
		if team == 0:
			GameState.me.gold += amount   # your Pickpocket kills; enemy boards earn nothing
	Settings.ensure_loaded()
	Settings.apply_light(get_node_or_null("../DirectionalLight3D") as DirectionalLight3D)   # shadows (Settings > Graphics)
	var ui := get_node_or_null("../UI")
	if ui != null:
		ui.add_child.call_deferred(ItemPopup.new())   # new items pop up mid-screen (item_popup.gd)
	if LobbyNet.in_lobby():
		lobby = LobbyGame.new(self)
		Events.unit_bought.connect(_on_unit_bought)
		Events.reroll_pressed.connect(_on_reroll)
		Events.buy_xp_pressed.connect(_on_buy_xp)
		await get_tree().process_frame   # the HUD is ready
		lobby.begin()
		return
	_begin_run()
	Events.unit_bought.connect(_on_unit_bought)
	Events.reroll_pressed.connect(_on_reroll)
	Events.buy_xp_pressed.connect(_on_buy_xp)
	await get_tree().process_frame
	if _resume.is_empty():
		_enter(Events.Phase.PREP)
	else:
		_resume_run()   # a mid-level save: back into its PREP or fight

# Sets up free play or the campaign level: run modifiers, shop roster, opponent provider, and the
# player's carried board when this level continues a chapter run.
func _begin_run():
	if only_units_with_models:
		var modelled: Array[UnitData] = []
		for d in unit_pool:
			if d != null and d.has_model():
				modelled.append(d)
		unit_pool = modelled
	var camp := GameState.run_campaign
	if camp == null and ResourceLoader.exists(DEFAULT_CAMPAIGN):
		camp = load(DEFAULT_CAMPAIGN)
	var lvl := GameState.run_level
	if lvl == null and debug_level != null and not GameState.launched_from_menu:
		lvl = debug_level
		var saved := SaveGame.chapter_run()
		if continue_saved_run and not saved.is_empty() and camp != null:
			var saved_level := camp.find_level(StringName(str(saved.get("level", ""))))
			if saved_level != null and camp.chapter_of(saved_level) == camp.chapter_of(lvl):
				lvl = saved_level
				GameState.run_carry = saved
				print("Continuing the saved chapter run at '%s'" % saved_level.display_name)
	if lvl != null and lvl.waves.is_empty():
		# Usually an empty "New CampaignLevel" in Debug Level instead of a loaded level file.
		push_warning("Campaign level '%s' has no waves, so it would have no enemies; playing free play instead. Set Debug Level to a level file, e.g. res://tres/campaign/levels/ch1_l1.tres." % lvl.display_name)
		lvl = null
	if lvl == null:
		camp = null
	var carry := GameState.begin_run(lvl, camp)
	rng.seed = GameState.run_seed
	board.apply_theme(BoardThemes.for_run(lvl, GameState.run_seed), GameState.run_seed)   # the level's biome (or one from the seed) and its scenery
	# Your king's run power (KingPowers) works in free play and async PvP; in a campaign level a king only
	# strikes (and the Golden Lion shields).
	GameState.me.king = KingSkins.selected() if lvl == null and KingSkins.is_run_power(KingSkins.selected()) else &""
	GameState.me.king_state = {}
	roster = unit_pool
	if lvl != null and not lvl.allowed_units.is_empty():
		roster = lvl.allowed_units
	if lvl != null and lvl.prep_time > 0:
		prep_time = lvl.prep_time
	shared_pool = UnitPool.new(roster)
	rules = PlayerRules.new(GameState.me, board, shared_pool, roster, item_roster)
	rules.drop_rounds = GameState.item_drop_rounds() if lvl == null or lvl.id != &"tutorial" else []   # the tutorial hands out its two items itself
	rules.tongs_rounds = GameState.TONGS_ROUNDS if lvl == null else ([GameState.CAMPAIGN_TONGS_ROUND] if _in_chapter(lvl) else [])   # Tongs: none in the tutorial
	rules.drop_stage_fixed = drop_stage() if lvl != null else 0
	manual_start = GameState.ghost_mode or _in_chapter(lvl)   # async PvP and chapter levels: no prep timer, the top bar's Start fight
	Settings.ensure_loaded()
	fight_speed = clampi(Settings.fight_speed, 1, MAX_FIGHT_SPEED) if can_fast_forward() else 1
	_resume = {}
	if not carry.is_empty():
		_restore_carry(carry)
		if carry.has("mid"):   # GameState.begin_run kept it, so it is valid
			_resume = carry.mid
			_restore_mid(_resume)
	if lvl != null:
		for problem in lvl.validate():
			push_warning(problem)
		opponents = WaveOpponents.new(lvl.waves, lvl.enemy_stat_mult)
	else:
		opponents = RandomOpponents.new(unit_pool, enemy_base_scale, enemy_scale_per_round, enemy_variation_chance, rng)
	snapshot_store = null
	if lvl == null:
		# Free play and async PvP record the player's board at every fight; campaign levels don't.
		# With the online ghost service set up (OnlineConfig) boards also go up to it and ghosts come from it.
		snapshot_store = OnlineConfig.make_store(self)
		balance_hash = BoardSnapshot.balance_hash(unit_pool, item_roster)
		if GameState.ghost_mode:
			ghost_rng.seed = hash([GameState.run_seed, "ghosts"])
			var ghosts := SnapshotOpponents.new(snapshot_store, opponents, unit_pool, item_roster, balance_hash, ghost_rng, str(GameState.run_seed))
			ghosts.ghost_changed.connect(_on_ghost_changed)
			opponents = ghosts
	_dress_kings()

# Saves the board that is about to fight, so other runs (and this player's later runs) can meet it as a ghost.
func _record_snapshot():
	if snapshot_store == null:
		return
	var fighters: Array = snapshot.keys().filter(func(u): return is_instance_valid(u))
	if fighters.is_empty():
		return
	var meta := {
		"name": OnlineConfig.player_name(),
		"run": str(GameState.run_seed),
		"round": GameState.round_number,
		"stage": "%d-%d" % [GameState.stage(), GameState.round_in_stage()],
		"level": GameState.me.level,
		"hp": GameState.me.player_hp,
		"balance": balance_hash,
		"king": String(KingSkins.selected()),   # the ghost's king looks like yours (a look only)
	}
	if GameState.ghost_mode:
		meta["trophies"] = GameState.me.trophies
		meta["losses"] = GameState.me.losses
	snapshot_store.submit(BoardSnapshot.capture(fighters, meta))

# What a chapter run carries into its next level; the save file stores the same dictionary.
# Units are stored by display_name, items by id; board units keep their tile, bench units their slot.
func make_carry(next_level: CampaignLevel) -> Dictionary:
	var units := []
	for u in board.all_player_units():
		var e := {"unit": u.data.display_name, "star": u.star, "items": u.items.map(func(i): return String(i.id))}
		if not u.item_stacks.is_empty():
			e["stacks"] = EnemyBoard._stacks_out(u.item_stacks)   # bound items keep their growth between levels
		var slot := board.bench.find(u)
		if slot != -1:
			e["bench"] = slot
		else:
			e["coord"] = [u.coord.x, u.coord.y]
		units.append(e)
	return {
		"level": String(next_level.id),
		"hp": GameState.me.player_hp,
		"max_hp": GameState.me.start_hp,
		"gold": GameState.me.gold,
		"player_level": GameState.me.level,
		"xp": GameState.me.xp,
		"items": GameState.me.items.map(func(i): return String(i.id)),
		"units": units,
	}

# Rebuilds the carried inventory, board and bench, and takes the owned copies out of the shared pool.
func _restore_carry(carry: Dictionary) -> void:
	for id in carry.get("items", []):
		var item := EnemyBoard.lookup_item(item_roster, StringName(str(id)))
		if item != null:
			GameState.me.items.append(item)
	Events.items_changed.emit()
	for e in carry.get("units", []):
		if not e is Dictionary:
			continue
		var d := EnemyBoard.lookup_unit(unit_pool, str(e.get("unit", "")))
		if d == null:
			push_warning("Carried unit '%s' is not in the roster; skipped" % e.get("unit", ""))
			continue
		var u := board.make_unit(d, unit_scene)
		var star := clampi(int(e.get("star", 1)), 1, Unit.MAX_STAR)
		if star > 1:
			u.set_star(star)
		var its: Array[ItemData] = []
		for id in e.get("items", []):
			var item := EnemyBoard.lookup_item(item_roster, StringName(str(id)))
			if item != null:
				its.append(item)
		if not its.is_empty():
			u.set_items(its)
			u.item_stacks = EnemyBoard.stacks_in(e.get("stacks", {}))
			u._recalc_items()
		u.health = u.max_hp()
		shared_pool.take_copies(d, UnitPool.copies_in(star))
		var c = e.get("coord", [-1, -1])
		var tile := Vector2i(int(c[0]), int(c[1])) if c is Array and c.size() == 2 else Vector2i(-1, -1)
		if e.has("bench") or not board.is_unlocked(tile) or not board.is_player_side(tile):
			var slot := int(e.get("bench", -1))
			if slot < 0 or slot >= Board.BENCH_SLOTS or board.bench[slot] != null:
				slot = board.first_free_bench()
			if slot == -1:
				push_warning("No room for carried unit %s; returned its items" % d.display_name)
				GameState.me.items.append_array(u.take_items())
				u.queue_free()
				continue
			board.put_on_bench(u, slot)
		else:
			board.put_on_tile(u, tile)   # falls back to the bench if the tile is taken

# --- mid-level saves (chapter levels only; the format is in save_game.gd) -----------------------------

# True while this run writes mid-level saves: a chapter level (not the tutorial, not free play) that
# isn't over.
func saves_mid_level() -> bool:
	var lvl := GameState.run_level
	return not game_over and lvl != null and lvl.id != &"" and _in_chapter(lvl)

# The saved chapter run as of now: the carry for this level plus the "mid" block. `phase_name`: "prep"
# or "combat" (written just before the fight starts, with the board that will fight).
func make_mid_save(phase_name: String) -> Dictionary:
	var me := GameState.me
	var save := make_carry(GameState.run_level)
	var pool := {}
	for key in shared_pool.remaining:
		pool[(key as UnitData).display_name] = int(shared_pool.remaining[key])
	var dropped := {}
	for id in me.dropped:
		dropped[String(id)] = int(me.dropped[id])
	save["mid"] = {
		"version": SaveGame.MID_VERSION,
		"round": GameState.round_number,
		"phase": phase_name,
		"seed": GameState.run_seed,
		"rng": str(rng.state),            # int64: as text, JSON numbers would round it
		"player_rng": str(me.rng.state),
		"win_streak": me.win_streak,
		"loss_streak": me.loss_streak,
		"last_won": me.last_combat_won,
		"dropped": dropped,
		"free_rerolls": me.free_rerolls,
		"cheap_shop": me.cheap_shop,
		"offers": me.shop_offers.map(func(d): return d.display_name),
		"locked": me.shop_locked,
		"rolled": me.shop_has_rolled,
		"pool": pool,
		"saved": int(Time.get_unix_time_from_system()),
	}
	return save

func _write_mid(phase_name: String) -> void:
	if saves_mid_level():
		SaveGame.set_chapter_run(make_mid_save(phase_name))

# Saves the run as it is now if it is in PREP (pause menu > Main menu, Quit game, closing the window).
# Mid-fight the save from the fight's start stands; between rounds there is nothing new to save.
func save_mid_run() -> void:
	if phase == Events.Phase.PREP and not fighting:
		_write_mid("prep")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_mid_run()

# Puts back what the carry doesn't hold (_restore_carry has rebuilt the units and items): RNG states,
# streaks, drops, the shop and the shared pool. GameState.begin_run already set the seed and round.
func _restore_mid(mid: Dictionary) -> void:
	var me := GameState.me
	rng.state = str(mid.rng).to_int()
	me.rng.state = str(mid.player_rng).to_int()
	me.win_streak = maxi(int(mid.get("win_streak", 0)), 0)
	me.loss_streak = maxi(int(mid.get("loss_streak", 0)), 0)
	me.last_combat_won = bool(mid.get("last_won", false))
	me.free_rerolls = maxi(int(mid.get("free_rerolls", 0)), 0)
	me.cheap_shop = bool(mid.get("cheap_shop", false))
	me.dropped.clear()
	var dropped = mid.get("dropped", {})
	if dropped is Dictionary:
		for id in dropped:
			me.dropped[StringName(str(id))] = int(dropped[id])
	# The pool as saved (it already excludes owned units and the shop's offers); keys keep the roster's
	# order, which UnitPool.pick depends on.
	var pool = mid.get("pool", {})
	for key in shared_pool.remaining:
		var d := key as UnitData
		if pool is Dictionary and pool.has(d.display_name):
			shared_pool.remaining[d] = clampi(int(pool[d.display_name]), 0, UnitPool.COPIES_PER_COST.get(d.cost, 0))
	me.shop_offers.clear()
	for n in mid.get("offers", []):
		var d := EnemyBoard.lookup_unit(roster, str(n))
		if d != null:
			me.shop_offers.append(d)
	me.shop_locked = bool(mid.get("locked", false))
	me.shop_has_rolled = bool(mid.get("rolled", not me.shop_offers.is_empty()))

# Resumes a mid-level save in its phase. "prep": that round's PREP without a second income, drop or shop
# roll, with a full timer. "combat": the fight replays from its start.
func _resume_run() -> void:
	var me := GameState.me
	var resume_phase := str(_resume.get("phase", "prep"))
	_resume = {}
	# The HUD may have read the state before it was restored: tell it everything once.
	Events.gold_changed.emit(me.gold)
	Events.hp_changed.emit(me.player_hp)
	Events.xp_changed.emit(me.level, me.xp, me.xp_needed())
	Events.streak_changed.emit(me.win_streak, me.loss_streak)
	Events.items_changed.emit()
	Events.shop_lock_changed.emit(me.shop_locked)
	if resume_phase == "combat":
		Events.round_changed.emit(GameState.stage(), GameState.round_in_stage())
		Music.play("boss" if is_boss_round() else "game")
		_enter(Events.Phase.COMBAT)
		return
	phase = Events.Phase.PREP
	Events.phase_changed.emit(phase)
	Events.round_changed.emit(GameState.stage(), GameState.round_in_stage())
	Music.play("boss" if is_boss_round() else "game")
	if opponents != null:
		opponents.prepare(GameState.round_number)
		Events.opponent_announced.emit(opponents.describe_next())
	Events.shop_rolled.emit(me.shop_offers.duplicate())
	prep_length = UNTIMED if manual_start else float(prep_time)
	prep_left = prep_length

# The two kings' looks: yours in your skin; the enemy's in the ghost's skin (async PvP ghosts record it),
# else the default. A Shadow King wears the enemy king's shape (visual only: in single player the enemy
# king never has a skin effect).
func _dress_kings() -> void:
	if board.kings.size() < 2:
		return
	var foe: StringName = KingSkins.DEFAULT
	if opponents is SnapshotOpponents:
		var k := StringName(str(opponents.current_snapshot().get("king", "")))
		if KingSkins.has(k):
			foe = k
	board.kings[1].set_skin(foe)
	board.kings[0].set_skin(KingSkins.selected(), foe)

# The Fate King's prophecy pick (the King tab).
func choose_prophecy(index: int) -> bool:
	return rules != null and KingPowers.choose_prophecy(rules, index)

func set_shop_locked(on: bool):
	if lobby != null:
		lobby.lock(on)
		return
	rules.set_locked(on)

func roll_shop():
	rules.roll_shop()

func _drop_item():
	rules.drop_item(GameState.round_number)

# The stage the drop table uses: the real stage in free play; in a campaign the chapter decides
# (chapter 1 = stage 2, chapter 2 = stage 4, chapter 3 = stage 6; the tutorial = stage 1).
func drop_stage() -> int:
	var lvl := GameState.run_level
	if lvl == null:
		return GameState.stage()
	var camp := GameState.run_campaign
	if camp != null:
		for i in camp.chapters.size():
			if camp.chapters[i] != null and camp.chapters[i].levels.has(lvl):
				return mini(2 + i * 2, 7)
	return 1

# One random drop for `stage` (PlayerRules.pick_drop).
func pick_drop(stage: int, drop_rng: RandomNumberGenerator, dropped: Dictionary) -> ItemData:
	return rules.pick_drop(stage, drop_rng, dropped)

# Gold the items on your board pay each round (Coin Purse; items v2).
func item_income() -> int:
	return rules.item_income() if rules != null else 0

# Free rerolls this round from items on your board (Merchant's Ledger).
func item_free_rerolls() -> int:
	return rules.item_free_rerolls()

func _on_reroll():
	if lobby != null:
		lobby.reroll()
		return
	if not rules.reroll():   # locked, the opening, or not enough gold
		Sfx.play(&"error")
		return
	Sfx.play(&"reroll")

func _on_buy_xp():
	if lobby != null:
		lobby.buy_xp()
		return
	if game_over: return
	if not rules.buy_xp():
		Sfx.play(&"error")
		return
	Sfx.play(&"xp")


func start_combat():
	# Over the cap: extras back to the bench; free board slots fill from the bench (leftmost first),
	# before the snapshot, so they stay on the board.
	rules.ready_board_for_fight()
	snapshot.clear()
	var units_node := board.get_node("Units")
	for n in units_node.get_children():
		var u := n as Unit
		if u and u.team == 0 and u.coord.x >= 0:
			snapshot[u] = u.coord
	for t in board.tiles.values():
		if t.occupant != null and (not is_instance_valid(t.occupant) or t.occupant.team == 1):
			t.occupant = null
	var mine: Array = []
	for u in snapshot:
		if is_instance_valid(u):
			mine.append(u)
	_record_snapshot()
	Synergies.apply(mine, KingPowers.fight_start(rules, mine))   # + the king's relics, decrees and prophecy
	_record_resonances(mine)
	_spawn_enemies()
	for n in units_node.get_children():
		var u := n as Unit
		if u and u.coord.x >= 0:
			u.begin_combat()
	runner.king_skins = [KingSkins.selected(), &""]   # your king's skin effect; the enemy king strikes but has no skin
	runner.king_levels = [GameState.me.level, GameState.me.level]
	runner.king_seed = hash([GameState.run_seed, GameState.round_number])
	runner.start()
	_apply_time_scale()

# Fixed acting order for a fight (CombatRunner.order).
func _combat_order() -> Array[Unit]:
	return runner.order()

func _spawn_enemies():
	current_board = opponents.board_for_round(GameState.round_number) if opponents != null else null
	spawn_board(current_board)

# Places an EnemyBoard on the open enemy tiles. Units with a coord go there, or to the nearest
# open tile if theirs is locked or taken; units without one are placed randomly. Units that
# don't fit (more units than open tiles) are skipped with a warning.
func spawn_board(def: EnemyBoard) -> Array[Unit]:
	var spawned: Array[Unit] = []
	if def == null:
		return spawned
	var free: Array[Vector2i] = []   # front-center first (board.enemy_order)
	for c in board.enemy_order:
		if board.is_unlocked(c) and board.tiles[c].occupant == null:
			free.append(c)
	var autos: Array[BoardUnit] = []
	var skipped := 0
	for bu in def.units:
		if bu == null or bu.unit == null:
			continue
		if bu.coord.x < 0:
			autos.append(bu)
		elif free.is_empty():
			skipped += 1
		else:
			var c := _nearest_free(bu.coord, free)
			free.erase(c)
			spawned.append(_spawn_enemy(bu, c, def.stat_scale))
	_shuffle(free)
	for bu in autos:
		if free.is_empty():
			skipped += 1
			continue
		spawned.append(_spawn_enemy(bu, free.pop_back(), def.stat_scale))
	if skipped > 0:
		push_warning("Enemy board '%s': %d unit(s) skipped, not enough open enemy tiles" % [def.display_name, skipped])
	if def.use_synergies:
		Synergies.apply(spawned)
		for u in spawned:
			u.health = u.max_hp()   # synergy HP bonuses raise max HP
	return spawned

func _nearest_free(target: Vector2i, free: Array[Vector2i]) -> Vector2i:
	var best := free[0]
	var best_d := Board.hex_distance(target, best)
	for c in free:
		var d := Board.hex_distance(target, c)
		if d < best_d:
			best_d = d
			best = c
	return best

func _spawn_enemy(bu: BoardUnit, c: Vector2i, scale: float) -> Unit:
	var u := unit_scene.instantiate() as Unit
	board.get_node("Units").add_child(u)
	u.setup(bu.unit, 1)
	u.stat_scale = scale
	if bu.star > 1:
		u.set_star(bu.star)
	if not bu.items.is_empty():
		u.set_items(bu.items)
		u.item_stacks = bu.stacks.duplicate()   # bound items keep their growth (ghosts, waves)
		u._recalc_items()
	u.health = u.max_hp()
	board.put_enemy_on_tile(u, c)
	return u

# Deterministic combat: one fixed-length tick per physics frame (60 per second by default),
# whatever the frame rate. The fight depends only on the two boards, not on timing.
# Fast forward runs more of the same ticks per frame, so it never changes how a fight goes.
func _physics_process(_delta):
	for i in fight_speed:
		if fighting:
			combat_tick()

# Fast forward is for async PvP and campaign chapter levels (the modes with Start fight).
func can_fast_forward() -> bool:
	return lobby == null and manual_start

# 1, 2 or 3; remembered (Settings.fight_speed). Takes effect at once, also mid-fight.
func set_fight_speed(speed: int) -> void:
	if not can_fast_forward():
		return
	fight_speed = clampi(speed, 1, MAX_FIGHT_SPEED)
	Settings.fight_speed = fight_speed
	Settings.save_settings()
	_apply_time_scale()
	Events.fight_speed_changed.emit(fight_speed)

# The visuals keep pace with a fast-forwarded fight; outside fights the clock runs at normal speed.
func _apply_time_scale() -> void:
	Engine.time_scale = float(fight_speed) if fighting and fight_speed > 1 else 1.0

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func combat_tick():
	runner.tick()

# Ground effects and summons from abilities (Abilities reaches the board's runner; these stay for callers).
func add_zone(kind: String, center: Vector2i, radius: int, secs: float, team: int, amount: float, by: Unit) -> void:
	runner.add_zone(kind, center, radius, secs, team, amount, by)

func add_summon(u: Unit) -> void:
	runner.add_summon(u)

func _tick_zones() -> void:
	runner._tick_zones()

# Runs the current fight to the end immediately (tests now; a PvP server or replays later).
func resolve_combat() -> bool:
	Sfx.muted += 1   # a whole fight in an instant: no sound
	while fighting:
		combat_tick()
	Sfx.muted -= 1
	return GameState.me.last_combat_won

# Fisher-Yates with the run's seeded RNG (Array.shuffle uses the global one).
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _end_combat(player_won: bool, enemy_alive: int):
	if not fighting: return
	runner.stop()
	_apply_time_scale()
	GameState.me.last_combat_won = player_won
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u and (u.team == 1 or u.summoned):
			u.leave_fight(not player_won and u.team == 1)   # frees it (summons too); a falling or cheering model stays a moment longer
	for t in board.tiles.values():
		t.occupant = null
	for u in snapshot:
		if is_instance_valid(u):
			u.end_combat(player_won)
			board.put_on_tile(u, snapshot[u])
	GameState.me.record_result(player_won)
	KingPowers.fight_end(rules, player_won)
	if GameState.ghost_mode:
		_end_async_fight(player_won, enemy_alive)
	elif player_won:
		GameState.me.gold += 1
		if current_board != null:
			GameState.me.heal(current_board.hp_reward)   # campaign HP pack for beating this wave
		Events.notice.emit("VICTORY  +1 GOLD", HudStyle.GOLD)
	else:
		var hp_before: int = GameState.me.player_hp
		GameState.me.player_hp -= GameState.damage_for_loss(enemy_alive)
		var lost: int = hp_before - GameState.me.player_hp
		var timed_out := runner.ticks >= COMBAT_MAX_TICKS
		# a fight is only won by wiping out the enemy: time running out, or both sides falling, is a loss too
		Events.notice.emit("%s  -%d HP" % ["TIME UP" if timed_out else ("BOTH SIDES FELL" if enemy_alive == 0 else "DEFEAT"), lost], HudStyle.RED)
	Events.combat_ended.emit(player_won)
	_enter(Events.Phase.RESULT)

# Async PvP: a win is a trophy (and the usual gold), a loss a life; HP is not used. The opening fight
# (round 1, a random free unit each) is a warm-up: it gives no trophy and costs no life.
func _end_async_fight(player_won: bool, enemy_alive: int) -> void:
	var me := GameState.me
	if GameState.round_number == 1 and not GameState.run_carried:
		if player_won:
			me.gold += 1
		Events.notice.emit("OPENING  %s" % ("VICTORY  +1 GOLD" if player_won else "NO LIFE LOST"), HudStyle.GOLD if player_won else HudStyle.MUTED)
		return
	if player_won:
		me.gold += 1
		me.trophies += 1
		Events.notice.emit("VICTORY  +1 TROPHY", HudStyle.GOLD)
	else:
		me.losses += 1
		var timed_out := runner.ticks >= COMBAT_MAX_TICKS
		Events.notice.emit("%s  -1 LIFE (%d LEFT)" % ["TIME UP" if timed_out else ("BOTH SIDES FELL" if enemy_alive == 0 else "DEFEAT"), me.lives_left()], HudStyle.RED)

# Async PvP after the 10th trophy: the end screen's Endless mode button. The run goes on with no trophy
# goal as sudden death: one life left, so the next loss ends it.
func continue_endless() -> void:
	if not GameState.ghost_mode or not game_over or phase != Events.Phase.RESULT or GameState.me.losses >= GameState.ASYNC_LIVES:
		return
	GameState.me.endless = true
	GameState.me.losses = GameState.ASYNC_LIVES - 1
	game_over = false
	Events.notice.emit("ENDLESS MODE", HudStyle.GOLD)
	_next_round()

# The enemy half opens as far as the ghost's own level (async PvP); with no ghost it follows yours.
func _open_foe_half() -> void:
	if not opponents is SnapshotOpponents:
		return
	var ghost: Dictionary = opponents.current_snapshot()
	board.foe_level = int(ghost.get("player_level", -1)) if not ghost.is_empty() else -1
	board.refresh_unlocks(GameState.me.level, true)

# An online ghost arrived after PREP began (SnapshotOpponents): announce the new opponent before the fight.
func _on_ghost_changed() -> void:
	if phase != Events.Phase.PREP or fighting or game_over:
		return
	Events.opponent_announced.emit(opponents.describe_next())
	_open_foe_half()
	_dress_kings()

# The PREP countdown. Fights have their own fixed ticks (_physics_process); this only runs the
# preparation timer, and stops while the tree is paused.
func _process(delta):
	if Preload.busy():
		Preload.collect()   # background loads started on the menu that finish during the run
	if lobby != null:   # the server's timer decides; this one only counts down for the top bar
		prep_left = maxf(prep_left - delta, 0.0) if phase == Events.Phase.PREP else 0.0
		return
	if phase != Events.Phase.PREP or game_over or prep_left <= 0.0:
		return
	prep_left -= delta
	if prep_left <= 0.0:
		prep_left = 0.0
		_enter(Events.Phase.COMBAT)

# Ends PREP now instead of waiting for the timer (the tutorial's Start fight button).
func end_prep_early():
	if lobby != null or game_over or phase != Events.Phase.PREP:
		return
	prep_left = 0.0
	_enter(Events.Phase.COMBAT)

# The boss round gets the boss music: a chapter level's last wave (the tutorial has no boss) or
# free play's (and async PvP's) final round.
func is_boss_round() -> bool:
	if GameState.ghost_mode:
		return GameState.me.endless   # async PvP: endless mode gets the boss music
	if GameState.round_number != GameState.total_rounds():
		return false
	return GameState.run_level == null or _in_chapter(GameState.run_level)

# True when the level is part of a campaign chapter (the tutorial isn't), so chapter runs apply.
func _in_chapter(lvl: CampaignLevel) -> bool:
	return lvl != null and GameState.run_campaign != null and GameState.run_campaign.chapter_of(lvl) != null

func _lose_run():
	game_over = true
	fighting = false
	if GameState.ghost_mode:
		SaveGame.record_async(GameState.me.trophies)
	if _in_chapter(GameState.run_level):
		# Roguelite: losing ends the chapter run; the chapter restarts from its first level.
		GameState.run_carry = {}
		SaveGame.clear_chapter_run()
	Events.run_lost.emit()

func _win_run():
	game_over = true
	fighting = false
	if GameState.ghost_mode:
		SaveGame.record_async(GameState.me.trophies)
	var lvl := GameState.run_level
	if lvl != null and lvl.id != &"":   # a level without an id can't be saved
		SaveGame.record_level_complete(lvl.id, GameState.me.player_hp, lvl.unlocks)
	if _in_chapter(lvl):   # levels outside a chapter (the tutorial) never touch the saved chapter run
		var nxt: CampaignLevel = GameState.run_campaign.next_in_chapter(lvl)
		if nxt != null:
			# The chapter run continues: carry the board into the next level and save it.
			GameState.run_carry = make_carry(nxt)
			SaveGame.set_chapter_run(GameState.run_carry)
		else:
			GameState.run_carry = {}
			SaveGame.clear_chapter_run()   # chapter complete
	Events.run_won.emit()

# Resonances your units bring into a fight are marked as discovered in the resonance book
# (saved as unlocks "resonance:<key>"; written once, only when something is new).
func _record_resonances(units: Array) -> void:
	var fresh := false
	for x in units:
		var u := x as Unit
		if u == null:
			continue
		for k in Resonance.keys_for(u.items):
			var id := StringName("resonance:" + k)
			if not SaveGame.has_unlock(id):
				SaveGame.add_unlock(id, false)
				fresh = true
	if fresh:
		SaveGame.save_game()
