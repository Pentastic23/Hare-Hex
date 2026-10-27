# player_rules.gd
class_name PlayerRules extends RefCounted

# Everything one player can do between fights, and the start-of-round economy, for one player's board:
# buying, selling, moving units, rerolling, Buy XP, the shop lock, equipping items and Tinker's Tongs,
# income, item drops and shop rolls. Single player (GameManager, DragController) and the lobby server
# (one PlayerRules per seat) both go through here, so the two always play by the same rules.
#
# A PlayerRules is a context: whose state (`player`), which board, which shared pool, which rosters.
# Each action checks it is allowed (gold, room, phase, ownership) and returns false if not, so the
# lobby server can hand it a client's request as is. Sounds and HUD signals stay with the callers;
# only `player.is_local` state fires Events (PlayerState and Board do that).

var player: PlayerState
var board: Board
var pool: UnitPool
var roster: Array[UnitData] = []      # what the shop offers
var item_roster: Array[ItemData] = []  # what can drop; resolves item ids
var unit_scene: PackedScene = preload("res://scenes/unit.tscn")
var drop_rounds: Array = GameState.ITEM_DROP_ROUNDS   # rounds whose PREP start drops an item
var tongs_rounds: Array = GameState.TONGS_ROUNDS      # ... and Tinker's Tongs ([] in a campaign)
var drop_stage_fixed := 0   # campaign: the chapter decides the drop table (GameManager.drop_stage); 0 = by round

const REROLL_COST := 2
const BUY_XP_COST := 4
const XP_PER_BUY := 4

func _init(p: PlayerState = null, b: Board = null, shared: UnitPool = null, units: Array[UnitData] = [], items: Array[ItemData] = []):
	player = p
	board = b
	pool = shared
	roster = units
	item_roster = items
	if b != null:
		b.player = p
		b.pool = shared

# --- the start of a round ------------------------------------------------------------------------

# A PREP start: income (round, interest, streak, Coin Purses), free rerolls (Merchant's Ledger), the
# round's item drop, the merges skipped during the fight, the round-1 cheap shop, then a new shop unless
# it is locked. `cheap` = this round's shop offers 1-cost units only. `opening` = the PvP opening (round 1
# of async PvP and lobbies): no shop, a free unit on the board instead (give_opening_unit), and nothing can
# be bought, sold or moved until the next round. `drops` false: no item drop (a campaign level's lost final
# wave fought again). Returns true if an item dropped.
func start_prep(round_number: int, cheap: bool, opening := false, drops := true) -> bool:
	player.opening = opening
	player.gold += player.total_income_for_round(round_number) + item_income()
	player.free_rerolls = item_free_rerolls()
	KingPowers.prep_start(self, round_number, opening)   # the king's run power: luck, decrees, quests, the hoard...
	var dropped := drop_item(round_number) if drops else false   # (a replayed final wave drops nothing new)
	board.merge_all()
	player.cheap_shop = cheap
	if opening:
		return_offers()
		if player.is_local:
			Events.shop_rolled.emit([])
		give_opening_unit()
	elif not player.shop_locked or not player.shop_has_rolled:
		roll_shop()
	return dropped

# The opening's free unit: a random 1-cost unit from the shared pool (by the player's own RNG), put
# straight onto the board where it fights best.
func give_opening_unit() -> Unit:
	var d := pool.pick(1, player.rng)
	if d == null or not pool.take(d):
		return null
	var u := board.make_unit(d, unit_scene)
	board.put_on_tile(u, board.open_tile_for(d))
	return u

# Gold the items on the board pay each round (Coin Purse; items v2).
func item_income() -> int:
	var n := 0
	for u in board.all_player_units():
		if u.coord.x >= 0:
			for it in u.items:
				n += it.gold_per_round
	return n

# Free rerolls this round from items on the board (Merchant's Ledger: one each, so two Ledgers give two).
func item_free_rerolls() -> int:
	var n := 0
	for u in board.all_player_units():
		if u.coord.x >= 0:
			for it in u.items:
				n += it.free_rerolls   # each Ledger on the board adds its own
	return n

func drop_stage(round_number: int) -> int:
	return drop_stage_fixed if drop_stage_fixed > 0 else GameState.stage_for(round_number)

# The round's free item (drop_rounds), and Tinker's Tongs on tongs_rounds. True if anything dropped.
func drop_item(round_number: int) -> bool:
	if item_roster.is_empty():
		return false
	var dropped := false
	if drop_rounds.has(round_number):
		var item := pick_drop(drop_stage(round_number), player.rng, player.dropped)
		if item != null:
			player.items.append(item)
			player.dropped[item.id] = int(player.dropped.get(item.id, 0)) + 1
			dropped = true
	if tongs_rounds.has(round_number):
		var tongs := EnemyBoard.lookup_item(item_roster, &"tinkers_tongs")
		if tongs != null:
			player.items.append(tongs)
			dropped = true
	if dropped and player.is_local:
		Events.items_changed.emit()
	return dropped

# One random drop for `stage` (items v2): basic items, and from stage 3 a SPECIAL_DROP_CHANCE of a
# special one (weighted by drop_weight, only those whose min_stage has come; synergy benders at most
# once a run). Tinker's Tongs never drop at random. Uses the player's seeded RNG.
func pick_drop(stage: int, rng: RandomNumberGenerator, dropped: Dictionary) -> ItemData:
	var basic: Array = item_roster.filter(func(i): return i != null and i.kind == &"basic" and i.min_stage <= stage)
	var special: Array = item_roster.filter(func(i): return i != null and i.is_special() and i.drop_weight > 0.0 and i.min_stage <= stage and not (i.once_a_run() and dropped.has(i.id)))
	var choices := basic
	if stage >= 3 and not special.is_empty() and rng.randf() < GameState.SPECIAL_DROP_CHANCE:
		choices = special
	if choices.is_empty():
		return null
	var total := 0.0
	for i in choices:
		total += i.drop_weight
	var roll := rng.randf() * total
	for i in choices:
		roll -= i.drop_weight
		if roll < 0.0:
			return i
	return choices.back()

# --- the shop ------------------------------------------------------------------------------------

# Five new offers (the old ones go back to the pool), by the player's level odds, from the player's RNG.
func roll_shop() -> void:
	if roster.is_empty():
		return
	player.shop_has_rolled = true
	player.shop_rolls += 1
	return_offers()
	var offers: Array = []
	for i in 5:
		var tier: int = 1 if player.cheap_shop else _pick_cost_tier()
		var d: UnitData = _random_unit_of_cost(tier)
		if d != null and pool.take(d):
			offers.append(d)
			player.shop_offers.append(d)
	if player.is_local:
		Events.shop_rolled.emit(offers)

func return_offers() -> void:
	for d in player.shop_offers:
		pool.give_back(d)
	player.shop_offers.clear()

func _pick_cost_tier() -> int:
	var odds: Array = player.shop_odds()   # the level's odds (the Gambler King shifts them)
	var r := player.rng.randf() * 100.0   # the player's own shop RNG
	var acc := 0.0
	for i in odds.size():
		acc += odds[i]
		if r < acc:
			return i + 1
	return 1

func _random_unit_of_cost(tier: int) -> UnitData:
	var d := pool.pick(tier, player.rng)
	if d != null:
		return d
	# No copies left at this cost: fall back to the nearest cost that has some.
	for off in range(1, 6):
		for t in [tier - off, tier + off]:
			d = pool.pick(t, player.rng)
			if d != null:
				return d
	return null

# Buys offer `d` (one of player.shop_offers). Outside PREP it goes to the bench and merges only with copies
# on the bench (units fighting on the board are left alone; the rest merges at the next PREP start); with
# a full bench it is bought only when it completes such a merge. Returns the new unit, or null if it
# couldn't be bought. A unit consumed by an immediate merge is returned freed.
# `strict` (the lobby server): only an offer in the shop, and only with the gold for it. Single player
# leaves those checks to the shop button (tests buy any unit through Events.unit_bought).
func buy(d: UnitData, in_prep: bool, strict := true) -> Unit:
	var price := player.price(d)   # the Chaos King's Royal Discount can take 1 off
	if d == null or player.opening or (strict and (not player.shop_offers.has(d) or player.gold < price)):
		return null
	var slot := board.first_free_bench()
	if slot == -1 and not board.would_complete_merge(d, not in_prep):
		return null
	player.gold -= price
	KingPowers.on_buy(player, d, price)
	player.shop_offers.erase(d)   # stays out of the pool; it's the player's now
	var u := board.make_unit(d, unit_scene)
	if slot != -1:
		board.put_on_bench(u, slot)
		board.merge_all(not in_prep)
	else:
		board.merge_pending_unit(u, not in_prep)
	return u

# Rerolls: a free reroll first (Merchant's Ledger), else REROLL_COST gold. Any phase (also mid-fight);
# not while the shop is locked or in the opening.
func reroll() -> bool:
	var free := player.free_rerolls > 0
	if player.shop_locked or player.opening or (not free and player.gold < REROLL_COST):
		return false
	if free:
		player.free_rerolls -= 1
		if player.is_local:
			Events.gold_changed.emit(player.gold)   # the reroll price on the shop bar updates
	else:
		player.gold -= REROLL_COST
	player.cheap_shop = false
	roll_shop()
	KingPowers.on_reroll(player)   # the Explorer's no-reroll quest fails
	return true

func buy_xp() -> bool:
	if player.opening or player.gold < BUY_XP_COST:
		return false
	player.gold -= BUY_XP_COST
	add_xp(KingPowers.xp_per_buy(player, XP_PER_BUY))   # the Chaos King's Royal Academy doubles it
	KingPowers.check(self)
	return true

# XP for the player; a board that doesn't follow the local player's level by itself (the lobby
# server's hidden boards) opens its new tiles here.
func add_xp(n: int) -> void:
	player.add_xp(n)
	sync_unlocks()

func sync_unlocks() -> void:
	if not board.visual and board.is_inside_tree():
		board.refresh_unlocks(player.level, false)

func set_locked(on: bool) -> void:
	player.shop_locked = on
	if player.is_local:
		Events.shop_lock_changed.emit(on)

# --- units ---------------------------------------------------------------------------------------

# True if `u` is one of this player's units on this board (not a summon, not being freed).
func owns(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and u.team == 0 and not u.summoned and u.data != null and not u.is_queued_for_deletion() and u.get_parent() == board.get_node("Units")

func unit_by_uid(uid: int) -> Unit:
	for u in board.all_player_units():
		if u.uid == uid:
			return u
	return null

func sell(u: Unit) -> bool:
	if player.opening or not owns(u):
		return false
	board.sell_unit(u)
	return true

# Moves a unit to bench slot `bench_i`, or (bench_i == -1) to tile `tile`, swapping with whatever is
# there; anything not allowed puts it back where it was. Outside PREP only bench units move, and only
# within the bench. A move onto the board past the unit cap is refused (returns "limit"). Returns
# "ok", "limit" or "back" (nothing changed). Merges run after a move in PREP.
func move(u: Unit, bench_i: int, tile: Vector2i, in_prep: bool) -> String:
	if player.opening or not owns(u):   # the opening: the free unit stays where it is
		return "back"
	var ob := board.bench.find(u)
	var oc := u.coord
	if not in_prep and oc.x >= 0:
		return "back"   # fighting units stay put
	if bench_i >= Board.BENCH_SLOTS:
		bench_i = -1
	var to_tile := bench_i == -1 and in_prep and board.tiles.has(tile) and board.is_unlocked(tile) and board.is_player_side(tile)
	var result := "back"
	board.detach(u)   # u's origin slot is now free
	if bench_i >= 0:
		var other := board.bench[bench_i]
		if other:
			board.detach(other)
			_place_at(other, ob, oc)
		board.put_on_bench(u, bench_i)
		result = "ok"
	elif to_tile:
		var other: Unit = board.tiles[tile].occupant
		if other == null and ob != -1 and board.units_on_board() >= player.max_board_units():
			_place_at(u, ob, oc)
			result = "limit"
		else:
			if other:
				board.detach(other)
				_place_at(other, ob, oc)
			board.put_on_tile(u, tile)
			result = "ok"
	else:
		_place_at(u, ob, oc)
	if in_prep:
		board.merge_all()
	return result

func _place_at(u: Unit, ob: int, oc: Vector2i) -> void:
	if ob != -1:
		board.put_on_bench(u, ob)
	else:
		board.put_on_tile(u, oc)

# Equips inventory item `item` on unit `u` (in any phase; `fighting` = u is in a fight right now, so it
# keeps its health and mana and gains the boost on top). Tinker's Tongs instead take every item off
# the unit (PREP only). Returns false (the item stays in the inventory) if it isn't allowed.
func equip(u: Unit, item: ItemData, in_prep: bool, fighting := false) -> bool:
	var index := player.items.find(item)
	if index == -1 or not owns(u):
		return false
	if item.kind == &"remover":
		return use_tongs(u, item, in_prep)
	if not u.equip(item, fighting):
		return false
	player.items.remove_at(index)
	if player.is_local:
		Events.items_changed.emit()
	return true

# Tinker's Tongs (items v2): during PREP, every item on one unit goes back to the inventory (bound
# items lose their stacks) and the Tongs are used up. Nothing happens on a unit without items.
func use_tongs(u: Unit, tongs: ItemData, in_prep: bool) -> bool:
	if not in_prep or not owns(u) or u.dead or u.items.is_empty():
		return false
	var index := player.items.find(tongs)
	if index == -1:
		return false
	player.items.remove_at(index)
	player.items.append_array(u.take_items())
	u.health = u.max_hp()
	if player.is_local:
		Events.items_changed.emit()
	return true

# --- a fight starting ----------------------------------------------------------------------------

# Before a fight: units over the board cap go back to the bench (a safety net), then free board slots
# fill from the bench (Board.auto_fill).
func ready_board_for_fight() -> void:
	var over := board.units_on_board() - player.max_board_units()
	if over > 0:
		for t in board.tiles.values():
			if over <= 0:
				break
			var bu: Unit = t.occupant
			if bu != null and bu.team == 0:
				var slot := board.first_free_bench()
				if slot == -1:
					break
				board.detach(bu)
				board.put_on_bench(bu, slot)
				over -= 1
	board.auto_fill(player.max_board_units())
