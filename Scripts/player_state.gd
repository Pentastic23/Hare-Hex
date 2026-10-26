# player_state.gd
class_name PlayerState extends RefCounted

# Everything that belongs to one player in a run: gold, level, XP, HP, streaks, items, shop.
# GameState.me is the local player; a lobby will hold one PlayerState per player in
# GameState.players. Only the local player's changes reach the HUD (through Events).
# Run-wide things (round number, campaign level, seed, stage math) stay in GameState.

var id := 0
var display_name := "You"
var is_local := true

var gold := 2:
	set(v):
		gold = v
		if is_local:
			Events.gold_changed.emit(gold)
var level := 1
var xp := 0
var player_hp := 100:
	set(v):
		player_hp = maxi(v, 0)
		if is_local:
			Events.hp_changed.emit(player_hp)
var start_hp := 100   # HP this run started with; also the cap for HP packs
var win_streak := 0
var loss_streak := 0
var items: Array[ItemData] = []    # unequipped items this player owns
var dropped := {}                 # item id -> times dropped this run (rare items drop at most once)
var free_rerolls := 0             # rerolls left this round that cost nothing (Merchant's Ledger)
var cheap_shop := false            # round 1-1: 1-cost units only
var opening := false               # the PvP opening (round 1 of async PvP and lobbies): a free unit, the shop shut, nothing moves
# Async PvP: a won fight is a trophy and a lost one costs a life (no HP). GameState.ASYNC_TROPHIES wins the
# run; after that the player may go on in endless mode until the last of GameState.ASYNC_LIVES lives is gone.
var trophies := 0:
	set(v):
		trophies = v
		if is_local:
			Events.trophies_changed.emit(trophies, losses)
var losses := 0:
	set(v):
		losses = v
		if is_local:
			Events.trophies_changed.emit(trophies, losses)
var endless := false

# Shop and results (the shared unit pool itself is run-wide, in GameManager).
var shop_offers: Array[UnitData] = []   # unbought offers; taken from the pool until the next roll
var shop_locked := false                # locked: the shop keeps its offers into the next round
var shop_has_rolled := false
var shop_rolls := 0                     # shops rolled this run (a lobby client refills its slots only on a new roll)
var last_combat_won := false
var rng := RandomNumberGenerator.new()  # this player's shop and item drops; seeded per run

# Back to a fresh run's starting values (the caller applies campaign modifiers or a carry after).
func reset():
	gold = 2
	level = 1
	xp = 0
	player_hp = start_hp
	win_streak = 0
	loss_streak = 0
	cheap_shop = false
	opening = false
	trophies = 0
	losses = 0
	endless = false
	items.clear()
	dropped.clear()
	free_rerolls = 0
	shop_offers.clear()
	shop_locked = false
	shop_has_rolled = false
	last_combat_won = false
	if is_local:
		Events.items_changed.emit()
		Events.streak_changed.emit(0, 0)

func lives_left() -> int:
	return maxi(GameState.ASYNC_LIVES - losses, 0)

func xp_needed() -> int:
	return GameState.XP_TABLE.get(level, 999999)

func add_xp(n: int):
	xp += n
	while GameState.XP_TABLE.has(level) and xp >= xp_needed():
		xp -= xp_needed()
		level += 1
	if is_local:
		Events.xp_changed.emit(level, xp, xp_needed())

func max_board_units() -> int:
	return level

@warning_ignore("integer_division")
func interest_gold() -> int:
	return mini(gold / GameState.INTEREST_STEP, GameState.INTEREST_CAP)

func total_income_for_round(r: int) -> int:
	return GameState.base_income_for_round(r) + interest_gold() + streak_bonus()

func record_result(won: bool):
	last_combat_won = won
	if won:
		win_streak += 1
		loss_streak = 0
	else:
		loss_streak += 1
		win_streak = 0
	if is_local:
		Events.streak_changed.emit(win_streak, loss_streak)

func streak_bonus() -> int:
	var s: int = maxi(win_streak, loss_streak)
	if s >= 5: return 3
	if s == 4: return 2
	if s >= 2: return 1
	return 0

# HP packs: restore HP, never above the run's starting HP.
func heal(amount: int):
	if amount > 0:
		player_hp = mini(player_hp + amount, start_hp)
