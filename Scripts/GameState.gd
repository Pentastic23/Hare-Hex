# game_state.gd  (autoload "GameState")
extends Node

const MAX_HP := 100
const INTEREST_STEP := 10
const INTEREST_CAP := 5
const TOTAL_STAGES := 7
const FIRST_STAGE_ROUNDS := 3
const ROUNDS_PER_STAGE := 6
const XP_TABLE := {1: 2, 2: 2, 3: 6, 4: 10, 5: 20, 6: 36, 7: 56, 8: 80}
const SHOP_ODDS := {
	1: [100, 0, 0, 0, 0],
	2: [100, 0, 0, 0, 0],
	3: [75, 25, 0, 0, 0],
	4: [55, 30, 15, 0, 0],
	5: [45, 33, 20, 2, 0],
	6: [30, 40, 25, 5, 0],
	7: [19, 30, 35, 15, 1],
	8: [15, 20, 35, 25, 5],
	9: [10, 15, 30, 30, 15],
}

# Overall round numbers whose PREP start drops a free item: 1-2, 1-3, and the last round of stages 2-6.
const ITEM_DROP_ROUNDS := [2, 3, 9, 15, 21, 27, 33]

var items: Array[ItemData] = []   # unequipped items the player owns
var run_level: CampaignLevel = null    # the campaign level being played; null = free play
var run_campaign: Campaign = null      # campaign that run_level belongs to (for "next level")
var start_hp := MAX_HP                 # player HP this run started with; also the cap for HP packs
var run_carry: Dictionary = {}         # chapter run state to load into the next level (GameManager.make_carry)
var run_carried := false               # this level continued a chapter run (board carried over)
var launched_from_menu := false        # the main menu chose this run, so Game Manager's Debug Level is ignored

const MENU_SCENE := "res://scenes/menu.tscn"
var gold := 2:
	set(v):
		gold = v
		Events.gold_changed.emit(gold)
var level := 1
var round_number := 1
var xp := 0
var cheap_shop := false
var player_hp := MAX_HP:
	set(v):
		player_hp = maxi(v, 0)
		Events.hp_changed.emit(player_hp)


func xp_needed() -> int:
	return XP_TABLE.get(level, 999999)

func add_xp(n: int):
	xp += n
	while XP_TABLE.has(level) and xp >= xp_needed():
		xp -= xp_needed()
		level += 1
	Events.xp_changed.emit(level, xp, xp_needed())

func max_board_units() -> int:
	return level

func total_rounds() -> int:
	if run_level != null and not run_level.waves.is_empty():
		return run_level.waves.size()   # campaign: one round per wave
	return FIRST_STAGE_ROUNDS + (TOTAL_STAGES - 1) * ROUNDS_PER_STAGE   # 39

func stage() -> int:
	if round_number <= FIRST_STAGE_ROUNDS:
		return 1
	return 2 + (round_number - FIRST_STAGE_ROUNDS - 1) / ROUNDS_PER_STAGE

func round_in_stage() -> int:
	if round_number <= FIRST_STAGE_ROUNDS:
		return round_number
	return (round_number - FIRST_STAGE_ROUNDS - 1) % ROUNDS_PER_STAGE + 1

func rounds_in_current_stage() -> int:
	return FIRST_STAGE_ROUNDS if stage() == 1 else ROUNDS_PER_STAGE

func is_final_round() -> bool:
	return round_number >= total_rounds()

func base_income_for_round(r: int) -> int:
	return _standard_income(r) + (run_level.income_bonus if run_level != null else 0)

func item_drop_rounds() -> Array:
	if run_level != null and not run_level.item_drop_rounds.is_empty():
		return run_level.item_drop_rounds
	return ITEM_DROP_ROUNDS

@warning_ignore("integer_division")
func _standard_income(r: int) -> int:
	if r <= FIRST_STAGE_ROUNDS:
		if r == 1: return 0
		if r == 2: return 2
		return 3
	var idx := r - FIRST_STAGE_ROUNDS - 1
	var s := 2 + idx / ROUNDS_PER_STAGE
	var r_in := idx % ROUNDS_PER_STAGE + 1
	if s == 2 and r_in == 1:
		return 4
	return 5

@warning_ignore("integer_division")
func interest_gold() -> int:
	return mini(gold / INTEREST_STEP, INTEREST_CAP)

func total_income_for_round(r: int) -> int:
	return base_income_for_round(r) + interest_gold() + streak_bonus()


func odds_for_level(l: int) -> Array:
	return SHOP_ODDS[clampi(l, 1, 9)]

var win_streak := 0
var loss_streak := 0

func record_result(won: bool):
	if won:
		win_streak += 1
		loss_streak = 0
	else:
		loss_streak += 1
		win_streak = 0
	Events.streak_changed.emit(win_streak, loss_streak)

func streak_bonus() -> int:
	var s: int = maxi(win_streak, loss_streak)
	if s >= 5: return 3
	if s == 4: return 2
	if s >= 2: return 1
	return 0

func damage_for_loss(enemy_star_total: int) -> int:
	var base := 5.0 * stage()
	if run_level != null and run_level.loss_damage > 0:
		base = run_level.loss_damage   # campaign: rounds restart each level, so the level sets the stakes
	return roundi(base + 0.25 * enemy_star_total)

func reset():
	gold = 2
	level = 1
	xp = 0
	round_number = 1
	player_hp = MAX_HP
	win_streak = 0
	loss_streak = 0
	cheap_shop = false
	items.clear()
	Events.items_changed.emit()
	Events.streak_changed.emit(0, 0)

# Starts a run: free play when lvl is null, otherwise that campaign level. If run_carry holds a
# chapter run for this level, gold, level, XP and HP come from it (plus the level's start_heal);
# otherwise the level's start modifiers apply. Returns the carry used (empty if none) so
# GameManager can rebuild the board, bench and items. run_level / run_campaign survive reset().
func begin_run(lvl: CampaignLevel = null, campaign: Campaign = null) -> Dictionary:
	run_level = lvl
	run_campaign = campaign
	var carry: Dictionary = {}
	if lvl != null and str(run_carry.get("level", "")) == String(lvl.id):
		carry = run_carry
	run_carry = {}
	run_carried = not carry.is_empty()
	if run_carried:
		start_hp = int(carry.get("max_hp", MAX_HP))
	else:
		start_hp = lvl.player_hp if lvl != null else MAX_HP
	reset()
	if run_carried:
		gold = int(carry.get("gold", 0))
		level = int(carry.get("player_level", 1))
		xp = int(carry.get("xp", 0))
		player_hp = int(carry.get("hp", start_hp))
		heal(lvl.start_heal)
	elif lvl != null:
		gold = lvl.start_gold
		level = lvl.start_level
		player_hp = lvl.player_hp
	Events.xp_changed.emit(level, xp, xp_needed())
	return carry

# Leaves the current run for the main menu. A campaign chapter run stays saved as of the start of
# the current level, so the menu's Continue resumes it there.
func go_to_menu():
	get_tree().paused = false
	run_level = null
	run_campaign = null
	run_carry = {}
	reset()
	get_tree().change_scene_to_file(MENU_SCENE)

# HP packs: restore HP, never above the run's starting HP.
func heal(amount: int):
	if amount > 0:
		player_hp = mini(player_hp + amount, start_hp)
