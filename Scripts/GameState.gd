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

@warning_ignore("integer_division")
func base_income_for_round(r: int) -> int:
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
	return roundi(5.0 * stage() + 0.25 * enemy_star_total)

func reset():
	gold = 2
	level = 1
	xp = 0
	round_number = 1
	player_hp = MAX_HP
	win_streak = 0
	loss_streak = 0
	cheap_shop = false
	Events.streak_changed.emit(0, 0)
