# random_opponents.gd
class_name RandomOpponents extends OpponentProvider

# Free play: the original random enemies. Count follows the player's unit cap (with a
# chance of one more or one less), cost is limited early, strength grows each round.
# Units are placed automatically; no stars, items or synergies (keeps free-play balance as it was).

var roster: Array[UnitData] = []
var base_scale := 0.6
var scale_per_round := 0.08
var variation_chance := 0.3
var rng: RandomNumberGenerator   # the run's seeded RNG, so a seed replays the same enemies

func _init(unit_roster: Array[UnitData], base: float, per_round: float, variation: float, run_rng: RandomNumberGenerator):
	roster = unit_roster
	base_scale = base
	scale_per_round = per_round
	variation_chance = variation
	rng = run_rng

func board_for_round(round_number: int) -> EnemyBoard:
	var b := EnemyBoard.new()
	b.display_name = "Random"
	b.use_synergies = false
	b.stat_scale = base_scale + scale_per_round * (round_number - 1)
	if roster.is_empty():
		return b
	var count := maxi(GameState.me.max_board_units(), 1)
	if rng.randf() < variation_chance:
		count += 1 if rng.randf() < 0.5 else -1
	count = maxi(count, 1)   # GameManager also caps it at the open enemy tiles
	var max_cost := 1 + int(round_number / 3.0)
	var options := roster.filter(func(x): return x != null and x.cost <= max_cost)
	if options.is_empty():
		options = roster
	for i in count:
		var bu := BoardUnit.new()
		bu.unit = options[rng.randi_range(0, options.size() - 1)]
		b.units.append(bu)
	return b
