# game_manager.gd
extends Node

var phase: int = Events.Phase.PREP
enum Phase { PREP, COMBAT, RESULT }
var fighting := false
var combat_time := 0.0
var snapshot := {}   # Unit -> Vector2i
var unit_scene: PackedScene = preload("res://Scenes/unit.tscn")
@export var prep_time := 10
@onready var board: Board = $"../Board"
@export var unit_pool: Array[UnitData] = []
@export_range(0.0, 1.0) var enemy_variation_chance := 0.3   # 30% of rounds get +1 or -1
const REROLL_COST := 2
const BUY_XP_COST := 4
@export var enemy_base_scale := 0.6        # round 1 enemies are 60% strength
@export var enemy_scale_per_round := 0.08  # +8% each round
var game_over := false



func _on_unit_bought(d: UnitData):
	var slot = board.first_free_bench()
	if slot == -1 and not board.would_complete_merge(d): return
	GameState.gold -= d.cost
	var u := preload("res://Scenes/unit.tscn").instantiate() as Unit
	board.get_node("Units").add_child(u)
	u.setup(d, 0)
	if slot != -1:
		board.put_on_bench(u, slot)
	else:
		board.merge_pending_unit(u)
		return
	board.merge_all()

func _enter(p: int):
	if game_over: return
	phase = p
	Events.phase_changed.emit(p)
	match p:
		Events.Phase.PREP:
			GameState.gold += GameState.total_income_for_round(GameState.round_number)
			board.merge_all()
			GameState.cheap_shop = (GameState.round_number == 1)
			Events.round_changed.emit(GameState.stage(), GameState.round_in_stage())
			roll_shop()
			await get_tree().create_timer(prep_time).timeout
			if game_over: return
			_enter(Events.Phase.COMBAT)
		Events.Phase.COMBAT:
			start_combat()
		Events.Phase.RESULT:
			if GameState.player_hp <= 0:
				_lose_run()
				return
			if GameState.is_final_round():
				_win_run()
				return
			GameState.round_number += 1
			GameState.add_xp(2)
			_enter(Events.Phase.PREP)

			
func _ready():
	Events.unit_bought.connect(_on_unit_bought)
	Events.reroll_pressed.connect(_on_reroll)
	Events.buy_xp_pressed.connect(_on_buy_xp)
	await get_tree().process_frame
	_enter(Events.Phase.PREP)

func roll_shop():
	if unit_pool.is_empty(): return
	var offers: Array = []
	for i in 5:
		var tier: int = 1 if GameState.cheap_shop else _pick_cost_tier()
		var d: UnitData = _random_unit_of_cost(tier)
		if d != null:
			offers.append(d)
	Events.shop_rolled.emit(offers)

func _pick_cost_tier() -> int:
	var odds: Array = GameState.odds_for_level(GameState.level)
	var r := randf() * 100.0
	var acc := 0.0
	for i in odds.size():
		acc += odds[i]
		if r < acc:
			return i + 1
	return 1

func _random_unit_of_cost(tier: int) -> UnitData:
	var options: Array = unit_pool.filter(func(x): return x != null and x.cost == tier)
	if not options.is_empty():
		return options.pick_random()
	# No unit at this cost yet: fall back to the nearest cost that exists.
	for off in range(1, 6):
		for t in [tier - off, tier + off]:
			options = unit_pool.filter(func(x): return x != null and x.cost == t)
			if not options.is_empty():
				return options.pick_random()
	return null

func _on_reroll():
	if phase != Events.Phase.PREP or GameState.gold < REROLL_COST: return
	GameState.gold -= REROLL_COST
	GameState.cheap_shop = false
	roll_shop()

func _on_buy_xp():
	if game_over or GameState.gold < BUY_XP_COST: return
	GameState.gold -= BUY_XP_COST
	GameState.add_xp(4)


func start_combat():
	# Safety: if somehow over the limit, send the extras back to the bench.
	var over := board.units_on_board() - GameState.max_board_units()
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
	Synergies.apply(mine)
	_spawn_enemies()
	for n in units_node.get_children():
		var u := unit_scene.instantiate() as Unit
		if u:
			u.begin_combat()
	combat_time = 0.0
	fighting = true

func _spawn_enemies():
	if unit_pool.is_empty(): return
	var spots: Array[Vector2i] = []
	for c in board.tiles:
		if not board.is_player_side(c) and board.is_unlocked(c):
			spots.append(c)
	spots.shuffle()
	var player_count := GameState.max_board_units()
	var count := maxi(player_count, 1)
	if randf() < enemy_variation_chance:
		count += 1 if randf() < 0.5 else -1
	count = clampi(count, 1, spots.size())
	for i in count:
		var u := unit_scene.instantiate() as Unit
		board.get_node("Units").add_child(u)
		var max_cost := 1 + int(GameState.round_number / 3.0)
		var options := unit_pool.filter(func(x): return x != null and x.cost <= max_cost)
		var d: UnitData = options.pick_random() if not options.is_empty() else unit_pool.pick_random()
		if d == null:
			u.queue_free()
			continue
		u.setup(d, 1)
		u.stat_scale = enemy_base_scale + enemy_scale_per_round * (GameState.round_number - 1)
		u.health = u.max_hp()
		if not board.put_enemy_on_tile(u, spots[i]):
			u.queue_free()
			continue

func _physics_process(delta):
	if not fighting: return
	combat_time += delta
	var alive_p := 0
	var alive_e := 0
	var enemy_stars := 0
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u == null or u.data == null or u.dead or u.coord.x < 0 or u.is_queued_for_deletion():
			continue
		u.combat_step(delta)
		if u.team == 0:
			alive_p += 1
		else:
			alive_e += 1
			enemy_stars += u.star
	if alive_p == 0 or alive_e == 0 or combat_time > 60.0:
		_end_combat(alive_e == 0 and alive_p > 0, enemy_stars)
	if alive_p == 0 or alive_e == 0 or combat_time > 60.0:
		_end_combat(alive_e == 0 and alive_p > 0, enemy_stars)

func _end_combat(player_won: bool, enemy_stars: int):
	if not fighting: return
	fighting = false
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u and u.team == 1:
			u.queue_free()
	for t in board.tiles.values():
		t.occupant = null
	for u in snapshot:
		if is_instance_valid(u):
			u.end_combat()
			board.put_on_tile(u, snapshot[u])
	GameState.record_result(player_won)
	if player_won:
		GameState.gold += 1
	else:
		GameState.player_hp -= GameState.damage_for_loss(enemy_stars)
	Events.combat_ended.emit(player_won)
	_enter(Events.Phase.RESULT)

func _lose_run():
	game_over = true
	fighting = false
	Events.run_lost.emit()

func _win_run():
	game_over = true
	fighting = false
	Events.run_won.emit()
