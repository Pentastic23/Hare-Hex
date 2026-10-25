# game_state.gd  (autoload "GameState")
extends Node

# Run-wide state: round number, the campaign level being played, the run seed, stage math and
# shared rules. Per-player state (gold, level, XP, HP, streaks, items, shop) lives in PlayerState:
# GameState.me is the local player, GameState.players everyone in the run (just me for now).

const MAX_HP := 100
const INTEREST_STEP := 10
const INTEREST_CAP := 5
const TOTAL_STAGES := 7
const FIRST_STAGE_ROUNDS := 3
const ROUNDS_PER_STAGE := 6
const XP_TABLE := {1: 2, 2: 2, 3: 6, 4: 10, 5: 20, 6: 36, 7: 56, 8: 80, 9: 100}   # XP to go from each level to the next; max level 10
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
	10: [5, 10, 20, 35, 30],
}

# Overall round numbers whose PREP start drops a free item (items v2: 14 a run): 1-2, 1-3; 2-2, 2-4,
# 2-6; 3-2, 3-4, 3-6; 4-3, 4-6; 5-3, 5-6; 6-3, 6-6.
const ITEM_DROP_ROUNDS := [2, 3, 5, 7, 9, 11, 13, 15, 18, 21, 24, 27, 30, 33]
# Rounds that also hand out Tinker's Tongs (free play and async PvP only): the end of stages 3 and 5.
const TONGS_ROUNDS := [15, 27]
const SPECIAL_DROP_CHANCE := 0.3   # from stage 3, a drop is a special item this often
const MENU_SCENE := "res://scenes/menu.tscn"

var me: PlayerState                    # the local player
var players: Array[PlayerState] = []   # everyone in this run (lobbies later); players[0] == me

var round_number := 1
var run_level: CampaignLevel = null    # the campaign level being played; null = free play
var run_campaign: Campaign = null      # campaign that run_level belongs to (for "next level")
var run_carry: Dictionary = {}         # chapter run state to load into the next level (GameManager.make_carry)
var run_carried := false               # this level continued a chapter run (board carried over)
var launched_from_menu := false        # the main menu chose this run, so Game Manager's Debug Level is ignored
var ghost_mode := false                # async PvP: free-play rules, opponents are saved boards (ghosts); set by the menu
var run_seed := 0                      # seeds GameManager.rng and each player's rng for this run
var next_seed := 0                     # set before a run to replay it exactly (tests, PvP); 0 = random

func _init():
	me = PlayerState.new()
	players = [me]

func total_rounds() -> int:
	if run_level != null and not run_level.waves.is_empty():
		return run_level.waves.size()   # campaign: one round per wave
	return FIRST_STAGE_ROUNDS + (TOTAL_STAGES - 1) * ROUNDS_PER_STAGE   # 39

func stage() -> int:
	return stage_for(round_number)

func round_in_stage() -> int:
	return round_in_stage_for(round_number)

# The stage of round r (free-play numbering: 3 rounds in stage 1, then 6 per stage). The lobby server
# keeps its own round, so the rules take it as an argument.
@warning_ignore("integer_division")
static func stage_for(r: int) -> int:
	if r <= FIRST_STAGE_ROUNDS:
		return 1
	return 2 + (r - FIRST_STAGE_ROUNDS - 1) / ROUNDS_PER_STAGE

static func round_in_stage_for(r: int) -> int:
	if r <= FIRST_STAGE_ROUNDS:
		return r
	return (r - FIRST_STAGE_ROUNDS - 1) % ROUNDS_PER_STAGE + 1

@warning_ignore("integer_division")
func rounds_in_current_stage() -> int:
	return FIRST_STAGE_ROUNDS if stage() == 1 else ROUNDS_PER_STAGE

func is_final_round() -> bool:
	return round_number >= total_rounds()

# Round income before a player's interest and streak (PlayerState.total_income_for_round adds those).
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

func odds_for_level(l: int) -> Array:
	return SHOP_ODDS[clampi(l, 1, 9)]

func damage_for_loss(enemy_star_total: int) -> int:
	var base := 5.0 * stage()
	if run_level != null and run_level.loss_damage > 0:
		base = run_level.loss_damage   # campaign: rounds restart each level, so the level sets the stakes
	return roundi(base + 0.25 * enemy_star_total)

func reset():
	round_number = 1
	for p in players:
		p.reset()

# Starts a run: free play when lvl is null, otherwise that campaign level. If run_carry holds a
# chapter run for this level, the local player's gold, level, XP and HP come from it (plus the
# level's start_heal); otherwise the level's start modifiers apply. Returns the carry used (empty
# if none) so GameManager can rebuild the board, bench and items. run_level / run_campaign survive reset().
#
# A carry with a valid "mid" block (SaveGame.mid_level) is a save from partway through this level: the
# run keeps that save's seed and round, and the start heal is not given again (it was, when the level
# began). GameManager restores the rest of it (_restore_mid) and resumes the saved phase.
func begin_run(lvl: CampaignLevel = null, campaign: Campaign = null) -> Dictionary:
	run_level = lvl
	run_campaign = campaign
	var carry: Dictionary = {}
	if lvl != null and str(run_carry.get("level", "")) == String(lvl.id):
		carry = run_carry
	run_carry = {}
	var mid := SaveGame.mid_level(carry, total_rounds())
	if carry.has("mid") and mid.is_empty():
		carry.erase("mid")   # unreadable or from another build: start the level from its carried state
	if not mid.is_empty():
		next_seed = int(mid.seed)
	run_seed = next_seed if next_seed != 0 else (randi() | 1)
	next_seed = 0
	for p in players:
		p.rng.seed = hash([run_seed, p.id])   # each player's shop rolls differently, all from one seed
	run_carried = not carry.is_empty()
	if run_carried:
		me.start_hp = int(carry.get("max_hp", MAX_HP))
	else:
		me.start_hp = lvl.player_hp if lvl != null else MAX_HP
	reset()
	if run_carried:
		me.gold = int(carry.get("gold", 0))
		me.level = int(carry.get("player_level", 1))
		me.xp = int(carry.get("xp", 0))
		me.player_hp = int(carry.get("hp", me.start_hp))
		if mid.is_empty():
			me.heal(lvl.start_heal)
		else:
			round_number = int(mid.round)
	elif lvl != null:
		me.gold = lvl.start_gold
		me.level = lvl.start_level
		me.player_hp = lvl.player_hp
	Events.xp_changed.emit(me.level, me.xp, me.xp_needed())
	return carry

# Switches to the run scene. The main menu has usually loaded it in the background (Preload); if it
# isn't done yet, a "Loading..." card shows (two frames, so it is drawn) and the rest is waited for.
func change_to_run() -> void:
	if not Preload.is_ready(Preload.RUN_SCENE):
		var here := get_tree().current_scene
		if here != null:
			var card := Label.new()
			card.text = "Loading..."
			card.add_theme_font_override("font", HudStyle.number_font())
			card.add_theme_font_size_override("font_size", 40)
			card.add_theme_color_override("font_color", HudStyle.GOLD)
			card.set_anchors_preset(Control.PRESET_CENTER)
			var layer := CanvasLayer.new()
			layer.layer = 90
			layer.add_child(card)
			here.add_child(layer)   # freed with the scene it covers
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().change_scene_to_packed(Preload.scene(Preload.RUN_SCENE))

# Leaves the current run for the main menu. A campaign chapter run stays saved (during PREP it is saved
# as it is now; mid-fight, as the fight began), so the menu's Continue resumes it there.
func go_to_menu():
	get_tree().call_group("game_manager", "save_mid_run")   # before reset() wipes the state
	LobbyNet.leave()   # out of a lobby (in a game still running, the seat stays, idle, until you rejoin)
	get_tree().paused = false
	ghost_mode = false
	run_level = null
	run_campaign = null
	run_carry = {}
	reset()
	get_tree().change_scene_to_file(MENU_SCENE)
