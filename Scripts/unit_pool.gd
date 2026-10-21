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
	return int(pow(3, star - 1))

func count(d: UnitData) -> int:
	return remaining.get(d, 0)

func take(d: UnitData) -> bool:
	if count(d) <= 0:
		return false
	remaining[d] -= 1
	return true

func give_back(d: UnitData, copies := 1):
	if remaining.has(d):
		remaining[d] = mini(remaining[d] + copies, COPIES_PER_COST.get(d.cost, 0))

# Random unit of this cost, weighted by copies left. Null if none are left.
func pick(cost: int) -> UnitData:
	var total := 0
	for key in remaining:
		var d: UnitData = key
		if d.cost == cost:
			total += remaining[d]
	if total <= 0:
		return null
	var r := randi() % total
	for key in remaining:
		var d: UnitData = key
		if d.cost != cost:
			continue
		r -= remaining[d]
		if r < 0:
			return d
	return null
