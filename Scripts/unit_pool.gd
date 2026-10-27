# unit_pool.gd
class_name UnitPool extends RefCounted

# Copies of each unit in the shared pool, by cost.
const COPIES_PER_COST := {1: 30, 2: 25, 3: 18, 4: 10, 5: 9}

var remaining := {}   # UnitData -> int

func _init(roster: Array[UnitData]):
	for d in roster:
		if d != null:
			remaining[d] = COPIES_PER_COST.get(d.cost, 0)

static func copies_in(star: int) -> int:
	return int(pow(3, mini(star, 3) - 1))   # a 4-star (ascended, not merged) is still the 9 copies of its 3-star

func count(d: UnitData) -> int:
	return remaining.get(d, 0)

func take(d: UnitData) -> bool:
	if count(d) <= 0:
		return false
	remaining[d] -= 1
	return true

# Removes copies the player already owns (a board carried into a new campaign level).
func take_copies(d: UnitData, copies: int) -> void:
	if remaining.has(d):
		remaining[d] = maxi(remaining[d] - copies, 0)

func give_back(d: UnitData, copies := 1):
	if remaining.has(d):
		remaining[d] = mini(remaining[d] + copies, COPIES_PER_COST.get(d.cost, 0))

# Random unit of this cost, weighted by copies left. Null if none are left.
func pick(cost: int, rng: RandomNumberGenerator) -> UnitData:
	var total := 0
	for key in remaining:
		var d: UnitData = key
		if d.cost == cost:
			total += remaining[d]
	if total <= 0:
		return null
	var r := rng.randi_range(0, total - 1)   # seeded run RNG, so shops replay from a seed
	for key in remaining:
		var d: UnitData = key
		if d.cost != cost:
			continue
		r -= remaining[d]
		if r < 0:
			return d
	return null
