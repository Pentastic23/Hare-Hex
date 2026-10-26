# lobby_bot.gd
class_name LobbyBot extends RefCounted

# A simple lobby opponent: plays a seat through the same PlayerRules a player's requests go through.
# Once per PREP it levels up on a schedule, buys what helps (copies it already has first, then units
# its level can afford), keeps some gold for interest later on, sells bench filler when the bench is
# full, and puts items on its strongest units. Deterministic: no randomness of its own (the shop's
# RNG still varies the game), so a seeded lobby of bots replays exactly.

const KEEP_GOLD_FROM := 9   # from this round on it keeps 10 gold (interest) unless leveling

static func take_turn(rules: PlayerRules, round_number: int) -> void:
	var p := rules.player
	var keep := 10 if round_number >= KEEP_GOLD_FROM else 0
	@warning_ignore("integer_division")
	var target_level := clampi(2 + round_number / 3, 1, 9)
	while p.level < target_level and p.gold >= PlayerRules.BUY_XP_COST + keep:
		if not rules.buy_xp():
			break
	for pass_i in 4:
		_buy_round(rules, keep)
		if pass_i < 3 and p.gold >= 20 + keep:
			rules.reroll()
	while p.gold >= 50 and p.level < 9:   # rich: level up rather than sit on gold
		if not rules.buy_xp():
			break
	_equip_items(rules)

static func _count(rules: PlayerRules, d: UnitData) -> int:
	return rules.board.all_player_units().filter(func(u): return u.data == d).size()

static func _buy_round(rules: PlayerRules, keep: int) -> void:
	var p := rules.player
	@warning_ignore("integer_division")
	var max_cost := clampi(1 + p.level / 2, 1, 5)
	var offers := p.shop_offers.duplicate()
	offers.sort_custom(func(a, b): return _count(rules, a) > _count(rules, b) or (_count(rules, a) == _count(rules, b) and a.cost > b.cost))
	for d in offers:
		var owned := _count(rules, d)
		if p.gold - d.cost < (0 if owned > 0 else keep):
			continue
		if owned == 0 and d.cost > max_cost:
			continue
		if rules.board.first_free_bench() == -1 and not rules.board.would_complete_merge(d):
			_sell_filler(rules)
		rules.buy(d, true)

# Bench full: sells the cheapest bench unit that isn't part of a pair.
static func _sell_filler(rules: PlayerRules) -> void:
	var worst: Unit = null
	for u in rules.board.bench:
		if u == null:
			continue
		if _count(rules, u.data) >= 2:
			continue
		if worst == null or u.data.cost * u.star < worst.data.cost * worst.star:
			worst = u
	if worst != null:
		rules.sell(worst)

# Items (not the Tongs) onto the board's strongest units with room.
static func _equip_items(rules: PlayerRules) -> void:
	var p := rules.player
	var units := rules.board.all_player_units().filter(func(u): return u.coord.x >= 0)
	units.sort_custom(func(a, b): return a.data.cost * a.star > b.data.cost * b.star or (a.data.cost * a.star == b.data.cost * b.star and Board.tile_order(a.coord) < Board.tile_order(b.coord)))
	for item in p.items.duplicate():
		if item.kind == &"remover":
			continue
		for u in units:
			if u.can_take(item) and rules.equip(u, item, true):
				break
