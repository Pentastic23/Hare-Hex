# game_manager.gd
extends Node

var phase: int = Events.Phase.PREP
var fighting := false
var combat_time := 0.0
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
const REROLL_COST := 2
const BUY_XP_COST := 4
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
const COMBAT_TICK := 1.0 / 60.0   # seconds of fight per tick
const COMBAT_MAX_TICKS := 3600    # 60 s; reaching it counts as a loss
var combatants: Array[Unit] = []  # fixed acting order for the current fight (_combat_order)
var combat_ticks := 0
var prep_left := 0.0   # seconds of PREP left; 0 when not in PREP
var rng := RandomNumberGenerator.new()   # run RNG (seeded): random enemies and placement. Shop and drops use GameState.me.rng.
var shared_pool: UnitPool



func _on_unit_bought(d: UnitData):
	if game_over: return
	# Outside PREP a purchase only goes to the bench: no merges while units are fighting.
	var in_prep := phase == Events.Phase.PREP
	var slot = board.first_free_bench()
	if slot == -1 and not (in_prep and board.would_complete_merge(d)): return
	GameState.me.gold -= d.cost
	GameState.me.shop_offers.erase(d)   # stays out of the pool; it's ours now
	var u := unit_scene.instantiate() as Unit
	board.get_node("Units").add_child(u)
	u.setup(d, 0)
	if slot != -1:
		board.put_on_bench(u, slot)
	else:
		board.merge_pending_unit(u)
		return
	if in_prep:
		board.merge_all()   # merges that were skipped during combat run at the next PREP start

func _enter(p: int):
	if game_over: return
	phase = p
	Events.phase_changed.emit(p)
	match p:
		Events.Phase.PREP:
			GameState.me.gold += GameState.me.total_income_for_round(GameState.round_number) + item_income()   # + Coin Purses on the board
			GameState.me.free_rerolls = item_free_rerolls()   # Merchant's Ledger
			_drop_item()
			board.merge_all()
			GameState.me.cheap_shop = (GameState.round_number == 1 and not GameState.run_carried)
			Events.round_changed.emit(GameState.stage(), GameState.round_in_stage())
			Music.play("boss" if is_boss_round() else "game")   # Final Struggle for the boss round, else Aspiration Woods
			if opponents != null:
				opponents.prepare(GameState.round_number)   # async PvP picks this round's ghost now
				Events.opponent_announced.emit(opponents.describe_next())
			if not GameState.me.shop_locked or not GameState.me.shop_has_rolled:
				roll_shop()
			prep_left = float(prep_time)   # counted down in _process, so the timer label can show it and pausing stops it
		Events.Phase.COMBAT:
			start_combat()
		Events.Phase.RESULT:
			if GameState.me.player_hp <= 0:
				_lose_run()
				return
			if GameState.is_final_round():
				# A campaign level is only complete if the final wave is beaten.
				if GameState.run_level != null and not GameState.me.last_combat_won:
					_lose_run()
				else:
					_win_run()
				return
			GameState.round_number += 1
			GameState.me.add_xp(2)
			_enter(Events.Phase.PREP)

			
func _ready():
	add_to_group("game_manager")   # shop_slot.gd finds us by group; the node name has a space
	Settings.ensure_loaded()
	Settings.apply_light(get_node_or_null("../DirectionalLight3D") as DirectionalLight3D)   # shadows (Settings > Graphics)
	_begin_run()
	Events.unit_bought.connect(_on_unit_bought)
	Events.unit_sold.connect(_on_unit_sold)
	Events.reroll_pressed.connect(_on_reroll)
	Events.buy_xp_pressed.connect(_on_buy_xp)
	await get_tree().process_frame
	_enter(Events.Phase.PREP)

# Sets up free play or the campaign level: run modifiers, shop roster, opponent provider, and the
# player's carried board when this level continues a chapter run.
func _begin_run():
	if only_units_with_models:
		var modelled: Array[UnitData] = []
		for d in unit_pool:
			if d != null and d.model != null:
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
	roster = unit_pool
	if lvl != null and not lvl.allowed_units.is_empty():
		roster = lvl.allowed_units
	if lvl != null and lvl.prep_time > 0:
		prep_time = lvl.prep_time
	shared_pool = UnitPool.new(roster)
	if not carry.is_empty():
		_restore_carry(carry)
	if lvl != null:
		for problem in lvl.validate():
			push_warning(problem)
		opponents = WaveOpponents.new(lvl.waves, lvl.enemy_stat_mult)
	else:
		opponents = RandomOpponents.new(unit_pool, enemy_base_scale, enemy_scale_per_round, enemy_variation_chance, rng)
	snapshot_store = null
	if lvl == null:
		# Free play and async PvP record the player's board at every fight; campaign levels don't.
		snapshot_store = LocalSnapshotStore.new()
		balance_hash = BoardSnapshot.balance_hash(unit_pool, item_roster)
		if GameState.ghost_mode:
			opponents = SnapshotOpponents.new(snapshot_store, opponents, unit_pool, item_roster, balance_hash, rng, str(GameState.run_seed))

# Saves the board that is about to fight, so other runs (and this player's later runs) can meet it as a ghost.
func _record_snapshot():
	if snapshot_store == null:
		return
	var fighters: Array = snapshot.keys().filter(func(u): return is_instance_valid(u))
	if fighters.is_empty():
		return
	snapshot_store.submit(BoardSnapshot.capture(fighters, {
		"name": GameState.me.display_name,
		"run": str(GameState.run_seed),
		"round": GameState.round_number,
		"stage": "%d-%d" % [GameState.stage(), GameState.round_in_stage()],
		"level": GameState.me.level,
		"hp": GameState.me.player_hp,
		"balance": balance_hash,
	}))

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
		var u := unit_scene.instantiate() as Unit
		board.get_node("Units").add_child(u)
		u.setup(d, 0)
		var star := clampi(int(e.get("star", 1)), 1, 3)
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

func set_shop_locked(on: bool):
	GameState.me.shop_locked = on
	Events.shop_lock_changed.emit(on)

func roll_shop():
	if roster.is_empty(): return
	GameState.me.shop_has_rolled = true
	_return_offers()
	var offers: Array = []
	for i in 5:
		var tier: int = 1 if GameState.me.cheap_shop else _pick_cost_tier()
		var d: UnitData = _random_unit_of_cost(tier)
		if d != null and shared_pool.take(d):
			offers.append(d)
			GameState.me.shop_offers.append(d)
	Events.shop_rolled.emit(offers)

func _drop_item():
	if item_roster.is_empty():
		return
	var me := GameState.me
	var dropped := false
	if GameState.item_drop_rounds().has(GameState.round_number):
		var item := pick_drop(drop_stage(), me.rng, me.dropped)
		if item != null:
			me.items.append(item)
			me.dropped[item.id] = int(me.dropped.get(item.id, 0)) + 1
			dropped = true
	if GameState.run_level == null and GameState.TONGS_ROUNDS.has(GameState.round_number):
		var tongs := EnemyBoard.lookup_item(item_roster, &"tinkers_tongs")
		if tongs != null:
			me.items.append(tongs)
			dropped = true
	if dropped:
		Events.items_changed.emit()

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

# One random drop for `stage` (items v2): basic items, and from stage 3 a SPECIAL_DROP_CHANCE of a
# special one (weighted by drop_weight, only those whose min_stage has come; synergy benders at most
# once a run). Tinker's Tongs never drop at random. Uses the player's seeded RNG.
func pick_drop(stage: int, rng: RandomNumberGenerator, dropped: Dictionary) -> ItemData:
	var basic: Array = item_roster.filter(func(i): return i != null and i.kind == &"basic" and i.min_stage <= stage)
	var special: Array = item_roster.filter(func(i): return i != null and i.is_special() and i.drop_weight > 0.0 and i.min_stage <= stage and not (i.kind == &"bender" and dropped.has(i.id)))
	var pool := basic
	if stage >= 3 and not special.is_empty() and rng.randf() < GameState.SPECIAL_DROP_CHANCE:
		pool = special
	if pool.is_empty():
		return null
	var total := 0.0
	for i in pool:
		total += i.drop_weight
	var roll := rng.randf() * total
	for i in pool:
		roll -= i.drop_weight
		if roll < 0.0:
			return i
	return pool.back()

# Gold the items on your board pay each round (Coin Purse; items v2).
func item_income() -> int:
	var n := 0
	for u in board.all_player_units():
		if u.coord.x >= 0:
			for it in u.items:
				n += it.gold_per_round
	return n

# Free rerolls this round from items on your board (Merchant's Ledger: the first reroll is free).
func item_free_rerolls() -> int:
	var n := 0
	for u in board.all_player_units():
		if u.coord.x >= 0:
			for it in u.items:
				n = maxi(n, it.free_rerolls)
	return n

func _return_offers():
	for d in GameState.me.shop_offers:
		shared_pool.give_back(d)
	GameState.me.shop_offers.clear()

func _on_unit_sold(d: UnitData, star: int, _refund: int):
	shared_pool.give_back(d, UnitPool.copies_in(star))

func _pick_cost_tier() -> int:
	var odds: Array = GameState.odds_for_level(GameState.me.level)
	var r := GameState.me.rng.randf() * 100.0   # the player's own shop RNG
	var acc := 0.0
	for i in odds.size():
		acc += odds[i]
		if r < acc:
			return i + 1
	return 1

func _random_unit_of_cost(tier: int) -> UnitData:
	var d := shared_pool.pick(tier, GameState.me.rng)
	if d != null:
		return d
	# No copies left at this cost: fall back to the nearest cost that has some.
	for off in range(1, 6):
		for t in [tier - off, tier + off]:
			d = shared_pool.pick(t, GameState.me.rng)
			if d != null:
				return d
	return null

func _on_reroll():
	var me := GameState.me
	var free := me.free_rerolls > 0
	if me.shop_locked or phase != Events.Phase.PREP or (not free and me.gold < REROLL_COST): return   # unlock to reroll
	if free:
		me.free_rerolls -= 1   # Merchant's Ledger
		Events.gold_changed.emit(me.gold)   # the reroll price on the shop bar updates
	else:
		me.gold -= REROLL_COST
	GameState.me.cheap_shop = false
	roll_shop()

func _on_buy_xp():
	if game_over or GameState.me.gold < BUY_XP_COST: return
	GameState.me.gold -= BUY_XP_COST
	GameState.me.add_xp(4)


func start_combat():
	# Safety: if somehow over the limit, send the extras back to the bench.
	var over := board.units_on_board() - GameState.me.max_board_units()
	if over > 0:
		for t in board.tiles.values():
			if over <= 0: break
			var bu: Unit = t.occupant
			if bu != null and bu.team == 0:
				var slot := board.first_free_bench()
				if slot == -1: break
				board.detach(bu)
				board.put_on_bench(bu, slot)
				over -= 1
	# Free board slots are filled from the bench (leftmost first), before the snapshot, so they stay on the board.
	board.auto_fill(GameState.me.max_board_units())
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
	Synergies.apply(mine)
	_record_resonances(mine)
	_spawn_enemies()
	for n in units_node.get_children():
		var u := n as Unit
		if u and u.coord.x >= 0:
			u.begin_combat()
	combatants = _combat_order()
	combat_ticks = 0
	combat_time = 0.0
	fighting = true

# Fixed acting order for a fight: each side sorted by tile (row, then column), then interleaved
# player/enemy so neither side always acts first. Node order never matters.
func _combat_order() -> Array[Unit]:
	var sides := [[], []]
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u != null and u.data != null and u.coord.x >= 0 and not u.is_queued_for_deletion():
			sides[clampi(u.team, 0, 1)].append(u)
	for side in sides:
		side.sort_custom(func(a, b): return Board.tile_order(a.coord) < Board.tile_order(b.coord))
	var order: Array[Unit] = []
	for i in maxi(sides[0].size(), sides[1].size()):
		for side in sides:
			if i < side.size():
				order.append(side[i])
	return order

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
func _physics_process(_delta):
	if fighting:
		combat_tick()

func combat_tick():
	combat_ticks += 1
	combat_time = combat_ticks * COMBAT_TICK
	for u in combatants:
		if is_instance_valid(u) and not u.dead and u.coord.x >= 0:
			u.combat_step(COMBAT_TICK)
	var alive_p := 0
	var alive_e := 0
	var enemy_stars := 0
	for u in combatants:
		if not is_instance_valid(u) or u.dead or u.coord.x < 0:
			continue
		if u.team == 0:
			alive_p += 1
		else:
			alive_e += 1
			enemy_stars += u.star
	if alive_p == 0 or alive_e == 0 or combat_ticks >= COMBAT_MAX_TICKS:
		_end_combat(alive_e == 0 and alive_p > 0, enemy_stars)

# Runs the current fight to the end immediately (tests now; a PvP server or replays later).
func resolve_combat() -> bool:
	while fighting:
		combat_tick()
	return GameState.me.last_combat_won

# Fisher-Yates with the run's seeded RNG (Array.shuffle uses the global one).
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _end_combat(player_won: bool, enemy_stars: int):
	if not fighting: return
	fighting = false
	GameState.me.last_combat_won = player_won
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u and u.team == 1:
			u.leave_fight(not player_won)   # frees it; a falling or cheering model stays a moment longer
	for t in board.tiles.values():
		t.occupant = null
	for u in snapshot:
		if is_instance_valid(u):
			u.end_combat(player_won)
			board.put_on_tile(u, snapshot[u])
	GameState.me.record_result(player_won)
	if player_won:
		GameState.me.gold += 1
		if current_board != null:
			GameState.me.heal(current_board.hp_reward)   # campaign HP pack for beating this wave
	else:
		GameState.me.player_hp -= GameState.damage_for_loss(enemy_stars)
	Events.combat_ended.emit(player_won)
	_enter(Events.Phase.RESULT)

# The PREP countdown. Fights have their own fixed ticks (_physics_process); this only runs the
# preparation timer, and stops while the tree is paused.
func _process(delta):
	if phase != Events.Phase.PREP or game_over or prep_left <= 0.0:
		return
	prep_left -= delta
	if prep_left <= 0.0:
		prep_left = 0.0
		_enter(Events.Phase.COMBAT)

# Ends PREP now instead of waiting for the timer (the tutorial's Start fight button).
func end_prep_early():
	if game_over or phase != Events.Phase.PREP:
		return
	prep_left = 0.0
	_enter(Events.Phase.COMBAT)

# The boss round gets the boss music: a chapter level's last wave (the tutorial has no boss) or
# free play's (and async PvP's) final round.
func is_boss_round() -> bool:
	if GameState.round_number != GameState.total_rounds():
		return false
	return GameState.run_level == null or _in_chapter(GameState.run_level)

# True when the level is part of a campaign chapter (the tutorial isn't), so chapter runs apply.
func _in_chapter(lvl: CampaignLevel) -> bool:
	return lvl != null and GameState.run_campaign != null and GameState.run_campaign.chapter_of(lvl) != null

func _lose_run():
	game_over = true
	fighting = false
	if _in_chapter(GameState.run_level):
		# Roguelite: losing ends the chapter run; the chapter restarts from its first level.
		GameState.run_carry = {}
		SaveGame.clear_chapter_run()
	Events.run_lost.emit()

func _win_run():
	game_over = true
	fighting = false
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
