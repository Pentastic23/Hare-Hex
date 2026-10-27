# king_powers.gd
class_name KingPowers

# The kings' run powers (king_skins.gd: every skin but the Golden Lion, whose effect is in the fight).
# A player's power is PlayerState.king (set by GameManager in free play and async PvP; "" in a campaign,
# the tutorial and lobbies) and its run state is PlayerState.king_state (cleared by reset()). PlayerRules
# calls in at the start of each PREP (prep_start), on rerolls, buys and Buy XP; Board on a sale (on_sell);
# GameManager when a fight starts (fight_start: returns team effects for Synergies.apply) and ends
# (fight_end). Everything random uses the player's own seeded RNG, so a seed replays the same run.
# Fights stay deterministic: team effects are applied at fight start like synergies.
#
# What each does (numbers below):
#   merchant     The King's Tax: interest cap +2.
#   gambler      Loaded Dice: each PREP the shop odds shift, as if you were `luck` levels higher or lower.
#   necromancer  Memorial Hall: a sale stores a memory and souls (its stars); every SOULS_PER_MEMORY souls a
#                free 1-star copy of a remembered unit (weighted by how often you sold it) goes to the bench.
#   explorer     Uncharted Territory: quests appear on QUEST_ROUNDS (up to MAX_QUESTS open); each done one
#                gives a relic (RELICS), a lasting run bonus.
#   chaos        Royal Proclamations: every DECREE_EVERY rounds a random decree for that round (never the
#                same twice running).
#   dragon       Hoard: at each PREP gold above HOARD_LINE goes into the hoard, which grows HOARD_GROWTH a
#                round (at most HOARD_GROWTH_MAX) and pays HOARD_REWARDS once each as it fills. A fight started
#                with less than HOARD_FLOOR gold collapses it: half comes back as gold.
#   fate         Threads of Destiny: at the first PREP after the opening, PROPHECY_CHOICES prophecies are
#                offered (choose_prophecy; the first is taken if a fight starts first); fulfil it for its payoff.
#   shadow       Forbidden Knowledge: nothing changes; the King tab shows peek_shop / peek_enemy and the rules.

const MERCHANT_INTEREST := 2

# [shift in levels, weight, name]
const LUCK := [[-1.5, 15, "Cold dice"], [-0.75, 20, "Bad luck"], [0.0, 10, "Even odds"], [0.5, 25, "A good roll"], [1.0, 15, "Lucky streak"], [2.0, 15, "JACKPOT"]]

const SOULS_PER_MEMORY := 3

const HOARD_LINE := 50
const HOARD_FLOOR := 20
const HOARD_GROWTH := 0.1
const HOARD_GROWTH_MAX := 5
# [treasure in the hoard, reward, text]
const HOARD_REWARDS := [[20, "item", "an item"], [40, "special", "a special item"], [70, "cost4", "a free 4-cost unit"], [100, "cost5", "a free 5-cost unit"]]

const DECREE_EVERY := 2
const DISCOUNT_BUYS := 3
const DECREES := {
	"discount": {"name": "Royal Discount", "text": "Your next 3 units this round cost 1 gold less."},
	"market": {"name": "Open Market", "text": "The shop refreshes for free: 3 free rerolls this round."},
	"gift": {"name": "Royal Gift", "text": "An extra item, now."},
	"academy": {"name": "Royal Academy", "text": "Double XP this round: the round's XP again, and Buy XP gives 8."},
	"banner": {"name": "War Banner", "text": "Your units fight the next fight with +25% attack speed."},
	"iron": {"name": "Iron Decree", "text": "Your units start the next fight with a shield of 20% of their max HP."},
	"treasury": {"name": "Royal Treasury", "text": "+4 gold from the treasury."},
}

const QUEST_ROUNDS := [2, 6, 11, 17, 23]
const MAX_QUESTS := 3
const QUESTS := {
	"five": "Win a fight with exactly 5 units on the board.",
	"no_reroll": "Reach level 7 without rerolling.",
	"traits": "Fight with 3 active traits.",
	"streak": "Win 3 fights in a row.",
	"rich": "Start a round with 50 gold.",
	"three_star": "Make a 3-star unit.",
	"armed": "Give one unit 3 items.",
}
# Relics: lasting bonuses for the rest of the run (fx: team effects every fight; others in prep_start / now).
const RELICS := {
	"compass": {"name": "Wayfinder's Compass", "text": "+1 gold every round."},
	"spyglass": {"name": "Spyglass", "text": "1 free reroll every round."},
	"boots": {"name": "Seven-League Boots", "text": "+2 XP every round."},
	"idol": {"name": "Golden Idol", "text": "Your units +10% HP.", "fx": {"hp": 0.10}},
	"drum": {"name": "War Drum", "text": "Your units +10% attack speed.", "fx": {"as": 0.10}},
	"lantern": {"name": "Miner's Lantern", "text": "Your units start fights with a 10% shield.", "fx": {"shield": 0.10}},
	"map": {"name": "Treasure Map", "text": "A special item, now."},
}

const PROPHECY_CHOICES := 3
const PROPHECIES := {
	"level9": {"text": "Reach level 9.", "reward": "+40 gold."},
	"legend": {"text": "Make a 3-star 5-cost unit.", "reward": "Your units +30% HP and damage for the rest of the run.", "fx": {"hp": 0.3, "dmg": 0.3}},
	"streak10": {"text": "Win 10 fights in a row.", "reward": "Your units +25% attack speed for the rest of the run.", "fx": {"as": 0.25}},
	"traits7": {"text": "Fight with 7 active traits.", "reward": "Two special items."},
	"stars3": {"text": "Have three 3-star units at once.", "reward": "+30 gold and a special item."},
}

const LOG_LINES := 4   # recent events shown in the King tab

static func on(p: PlayerState, id: StringName) -> bool:
	return p != null and p.king == id

static func _st(p: PlayerState) -> Dictionary:
	return p.king_state

# --- what the rest of the game asks ----------------------------------------------------------------

static func interest_cap(p: PlayerState) -> int:
	return GameState.INTEREST_CAP + (MERCHANT_INTEREST if on(p, &"merchant") else 0)

# The shop odds (% per cost 1-5) the player rolls with: their level's, shifted by the Gambler's luck.
static func odds(p: PlayerState) -> Array:
	if not on(p, &"gambler") or float(_st(p).get("luck", 0.0)) == 0.0:
		return GameState.odds_for_level(p.level)
	return blended_odds(float(p.level) + float(_st(p).luck))

# Odds for a level that may be fractional (between two rows of the table).
static func blended_odds(level: float) -> Array:
	var l := clampf(level, 1.0, 10.0)
	var lo := floori(l)
	var hi := mini(lo + 1, 10)
	var t := l - lo
	var a: Array = GameState.SHOP_ODDS[lo]
	var b: Array = GameState.SHOP_ODDS[hi]
	var out := []
	for i in a.size():
		out.append(lerpf(float(a[i]), float(b[i]), t))
	return out

# What unit `d` costs this player now (the Chaos King's Royal Discount).
static func price(p: PlayerState, d: UnitData) -> int:
	if d == null:
		return 0
	if on(p, &"chaos") and int(_st(p).get("discount", 0)) > 0:
		return maxi(d.cost - 1, 1)
	return d.cost

static func xp_per_buy(p: PlayerState, base: int) -> int:
	return base * (2 if on(p, &"chaos") and _st(p).get("decree", "") == "academy" else 1)

# A purchase went through at `paid` gold.
static func on_buy(p: PlayerState, d: UnitData, paid: int) -> void:
	if on(p, &"chaos") and d != null and paid < d.cost:
		_st(p).discount = maxi(int(_st(p).get("discount", 0)) - 1, 0)
		_changed(p)

static func on_reroll(p: PlayerState) -> void:
	if on(p, &"explorer") and p.level < 7:
		for q in _st(p).get("quests", []):
			if q.id == "no_reroll" and q.state == "open":
				q.state = "failed"
				_log(p, "Quest failed: " + QUESTS.no_reroll)
				_notice(p, "QUEST FAILED", HudStyle.RED)
	_changed(p)

# A unit was sold (Board.sell_unit): the Necromancer remembers it.
static func on_sell(p: PlayerState, d: UnitData, star: int) -> void:
	if not on(p, &"necromancer") or d == null:
		return
	var s := _st(p)
	if not s.has("memories"):
		s.memories = {}
	s.memories[d] = int(s.memories.get(d, 0)) + 1
	s.souls = int(s.get("souls", 0)) + maxi(star, 1)
	_changed(p)

# --- the start of a round (PlayerRules.start_prep, after income and free rerolls, before drops and the shop) ---

static func prep_start(r: PlayerRules, round_number: int, opening: bool) -> void:
	var p := r.player
	if p == null or p.king == &"":
		return
	var s := _st(p)
	match p.king:
		&"gambler":
			s.luck = 0.0
			s.luck_name = ""
			if not opening:
				var roll := _weighted(p.rng, LUCK)
				s.luck = float(roll[0])
				s.luck_name = str(roll[2])
				var better: bool = roll[0] > 0.0
				_log(p, "Loaded Dice: %s (odds as level %s)." % [roll[2], _level_text(p.level + float(roll[0]))])
				if absf(float(roll[0])) >= 1.0:
					_notice(p, "LOADED DICE: " + str(roll[2]).to_upper(), HudStyle.GOLD if better else HudStyle.RED)
		&"necromancer":
			if int(s.get("souls", 0)) >= SOULS_PER_MEMORY and not s.get("memories", {}).is_empty():
				_raise_memory(r)
		&"dragon":
			_hoard_round(r)
		&"chaos":
			s.decree = ""
			s.discount = 0
			s.fight_fx = {}
			if not opening and round_number % DECREE_EVERY == 0:
				_proclaim(r, round_number)
		&"explorer":
			for id in s.get("relics", []):
				match id:
					"compass":
						p.gold += 1
					"spyglass":
						p.free_rerolls += 1
					"boots":
						r.add_xp(2)
			if not opening and QUEST_ROUNDS.has(round_number):
				_new_quest(p)
		&"fate":
			if not opening and str(s.get("prophecy", "")) == "" and s.get("offer", []).is_empty():
				var ids := PROPHECIES.keys()
				_shuffle(ids, p.rng)
				s.offer = ids.slice(0, PROPHECY_CHOICES)
				_log(p, "Choose your prophecy in the King tab.")
				_notice(p, "CHOOSE YOUR PROPHECY", KingSkins.colour(&"fate"))
	check(r)
	_changed(p)

# A fight starts (GameManager.start_combat, before Synergies.apply): checks, and the effects every unit of
# yours gets this fight (synergy effect keys, merged into the synergies).
static func fight_start(r: PlayerRules, units: Array) -> Dictionary:
	var p := r.player
	if p == null or p.king == &"":
		return {}
	var s := _st(p)
	s.fight_units = units.size()
	s.fight_traits = active_traits(units)
	if on(p, &"fate") and str(s.get("prophecy", "")) == "" and not s.get("offer", []).is_empty():
		choose_prophecy(r, 0)   # not chosen in time: the first thread is taken
	if on(p, &"dragon") and int(s.get("hoard", 0)) > 0 and p.gold < HOARD_FLOOR:
		var back := floori(int(s.hoard) / 2.0)
		_log(p, "The hoard collapsed: %d of %d gold came back." % [back, int(s.hoard)])
		_notice(p, "THE HOARD COLLAPSES  +%d GOLD" % back, HudStyle.RED)
		s.hoard = 0
		p.gold += back
	check(r)
	var fx := {}
	if on(p, &"chaos"):
		_merge(fx, s.get("fight_fx", {}))
	if on(p, &"explorer"):
		for id in s.get("relics", []):
			_merge(fx, RELICS[id].get("fx", {}))
	if on(p, &"fate") and bool(s.get("fulfilled", false)):
		_merge(fx, PROPHECIES[s.prophecy].get("fx", {}))
	_changed(p)
	return fx

static func fight_end(r: PlayerRules, won: bool) -> void:
	var p := r.player
	if p == null or p.king == &"":
		return
	var s := _st(p)
	if on(p, &"chaos"):
		s.fight_fx = {}   # the banner and the decree last one fight
	if on(p, &"explorer") and won and int(s.get("fight_units", 0)) == 5:
		_complete_quest(r, "five")
	check(r)
	_changed(p)

static func choose_prophecy(r: PlayerRules, index: int) -> bool:
	var p := r.player
	var s := _st(p)
	var offer: Array = s.get("offer", [])
	if not on(p, &"fate") or index < 0 or index >= offer.size() or str(s.get("prophecy", "")) != "":
		return false
	s.prophecy = offer[index]
	s.offer = []
	_log(p, "Prophecy: " + PROPHECIES[s.prophecy].text)
	check(r)
	_changed(p)
	return true

# Quests and the prophecy: anything fulfilled now pays out.
static func check(r: PlayerRules) -> void:
	var p := r.player
	var s := _st(p)
	if on(p, &"explorer"):
		for q in s.get("quests", []):
			if q.state == "open" and _quest_met(r, q.id):
				_complete_quest(r, q.id)
	if on(p, &"fate") and str(s.get("prophecy", "")) != "" and not bool(s.get("fulfilled", false)) and _prophecy_met(r, s.prophecy):
		_fulfil(r)

# How many traits a team has active (a tier reached).
static func active_traits(units: Array) -> int:
	var n := 0
	var counts := Synergies.count(units)
	for tag in counts:
		if Synergies.active_tier(tag, int(counts[tag])) >= 0:
			n += 1
	return n

# --- the Necromancer ---------------------------------------------------------------------------------

static func _raise_memory(r: PlayerRules) -> void:
	var p := r.player
	var s := _st(p)
	var slot := r.board.first_free_bench()
	if slot == -1:
		return   # the bench is full: the memory waits
	var mem: Dictionary = s.memories
	var options := []
	for key in mem:
		var d: UnitData = key
		if r.pool.count(d) > 0:
			options.append([d, int(mem[d]), d.display_name])
	if options.is_empty():
		return
	options.sort_custom(func(a, b): return a[2] < b[2])   # a fixed order before the weighted pick
	var pick := _weighted(p.rng, options)
	var d: UnitData = pick[0]
	if not r.pool.take(d):
		return
	var u := r.board.make_unit(d, r.unit_scene)
	r.board.put_on_bench(u, slot)
	s.souls = int(s.souls) - SOULS_PER_MEMORY
	mem[d] = int(mem[d]) - 1
	if int(mem[d]) <= 0:
		mem.erase(d)
	s.raised = int(s.get("raised", 0)) + 1
	_log(p, "A memory returned: %s." % d.display_name)
	_notice(p, "A MEMORY RETURNS: " + d.display_name.to_upper(), KingSkins.colour(&"necromancer"))

# --- the Dragon --------------------------------------------------------------------------------------

static func _hoard_round(r: PlayerRules) -> void:
	var p := r.player
	var s := _st(p)
	var hoard := int(s.get("hoard", 0))
	if hoard > 0:
		hoard += mini(int(hoard * HOARD_GROWTH), HOARD_GROWTH_MAX)
	if p.gold > HOARD_LINE:
		var extra := p.gold - HOARD_LINE
		hoard += extra
		p.gold = HOARD_LINE
		_log(p, "%d gold went into the hoard." % extra)
	s.hoard = hoard
	if not s.has("claimed"):
		s.claimed = []
	for reward in HOARD_REWARDS:
		if hoard >= int(reward[0]) and not s.claimed.has(reward[0]):
			if _give(r, str(reward[1])):
				s.claimed.append(reward[0])
				_log(p, "The hoard paid out %s." % reward[2])
				_notice(p, "TREASURE: " + str(reward[2]).to_upper(), HudStyle.GOLD)

# The next treasure the hoard pays, or [] once all are paid.
static func next_treasure(p: PlayerState) -> Array:
	for reward in HOARD_REWARDS:
		if not _st(p).get("claimed", []).has(reward[0]):
			return reward
	return []

# --- the Chaos King ----------------------------------------------------------------------------------

static func _proclaim(r: PlayerRules, round_number: int) -> void:
	var p := r.player
	var s := _st(p)
	var ids := DECREES.keys().filter(func(k): return k != s.get("last", ""))
	var id: String = ids[p.rng.randi_range(0, ids.size() - 1)]
	s.decree = id
	s.last = id
	match id:
		"discount":
			s.discount = DISCOUNT_BUYS
		"market":
			p.free_rerolls += 3
		"gift":
			_give(r, "item", round_number)
		"academy":
			r.add_xp(2)
		"banner":
			s.fight_fx = {"as": 0.25}
		"iron":
			s.fight_fx = {"shield": 0.20}
		"treasury":
			p.gold += 4
	_log(p, "%s: %s" % [DECREES[id].name, DECREES[id].text])
	_notice(p, DECREES[id].name.to_upper(), KingSkins.colour(&"chaos"))

# --- the Explorer ------------------------------------------------------------------------------------

static func _new_quest(p: PlayerState) -> void:
	var s := _st(p)
	if not s.has("quests"):
		s.quests = []
	var open: int = s.quests.filter(func(q): return q.state == "open").size()
	if open >= MAX_QUESTS:
		return
	var seen: Array = s.quests.map(func(q): return q.id)
	var ids := QUESTS.keys().filter(func(k): return not seen.has(k) and not (k == "no_reroll" and p.level >= 7))
	if ids.is_empty():
		return
	var id: String = ids[p.rng.randi_range(0, ids.size() - 1)]
	s.quests.append({"id": id, "state": "open"})
	_log(p, "New quest: " + QUESTS[id])
	_notice(p, "A NEW QUEST", KingSkins.colour(&"explorer"))

static func _quest_met(r: PlayerRules, id: String) -> bool:
	var p := r.player
	match id:
		"no_reroll":
			return p.level >= 7
		"traits":
			return int(_st(p).get("fight_traits", 0)) >= 3
		"streak":
			return p.win_streak >= 3
		"rich":
			return p.gold >= 50
		"three_star":
			return _units_with(r, func(u): return u.star >= 3) >= 1
		"armed":
			return _units_with(r, func(u): return u.items.size() >= 3) >= 1
	return false   # "five" is checked when a fight ends

static func _complete_quest(r: PlayerRules, id: String) -> void:
	var p := r.player
	var s := _st(p)
	for q in s.get("quests", []):
		if q.id == id and q.state == "open":
			q.state = "done"
			var owned: Array = s.get("relics", [])
			var left := RELICS.keys().filter(func(k): return not owned.has(k))
			if left.is_empty():
				p.gold += 5
				_log(p, "Quest done: %s (+5 gold)" % QUESTS[id])
				return
			var relic: String = left[p.rng.randi_range(0, left.size() - 1)]
			owned.append(relic)
			s.relics = owned
			q.relic = relic
			if relic == "map":
				_give(r, "special")
			_log(p, "Quest done! Relic: %s (%s)" % [RELICS[relic].name, RELICS[relic].text])
			_notice(p, "RELIC: " + RELICS[relic].name.to_upper(), HudStyle.GOLD)
			return

# --- the Fate King -----------------------------------------------------------------------------------

static func _prophecy_met(r: PlayerRules, id: String) -> bool:
	var p := r.player
	match id:
		"level9":
			return p.level >= 9
		"legend":
			return _units_with(r, func(u): return u.star >= 3 and u.data.cost >= 5) >= 1
		"streak10":
			return p.win_streak >= 10
		"traits7":
			return int(_st(p).get("fight_traits", 0)) >= 7
		"stars3":
			return _units_with(r, func(u): return u.star >= 3) >= 3
	return false

static func _fulfil(r: PlayerRules) -> void:
	var p := r.player
	var s := _st(p)
	s.fulfilled = true
	match str(s.prophecy):
		"level9":
			p.gold += 40
		"traits7":
			_give(r, "special")
			_give(r, "special")
		"stars3":
			p.gold += 30
			_give(r, "special")
	_log(p, "The prophecy came true! " + PROPHECIES[s.prophecy].reward)
	_notice(p, "THE PROPHECY IS FULFILLED", HudStyle.GOLD)

# --- the Shadow King ---------------------------------------------------------------------------------

# The five units your next reroll will offer, if nothing changes before it: the roll is simulated on the
# player's RNG and the pool, then both are put back exactly as they were.
static func peek_shop(r: PlayerRules) -> Array:
	var p := r.player
	if r.roster.is_empty() or r.pool == null:
		return []
	var state := p.rng.state
	var cheap := p.cheap_shop
	p.cheap_shop = false   # a reroll always rolls the full shop
	var held := p.shop_offers.duplicate()
	for d in held:
		r.pool.give_back(d)
	var picked := []
	for i in 5:
		var d: UnitData = r._random_unit_of_cost(r._pick_cost_tier())
		if d != null and r.pool.take(d):
			picked.append(d)
	for d in picked:
		r.pool.give_back(d)
	for d in held:
		r.pool.take(d)
	p.cheap_shop = cheap
	p.rng.state = state
	return picked

# The coming enemy's units (UnitData, star) if it can be known: a ghost, or the random enemies the run RNG
# will roll if nothing changes. The RNGs are put back.
static func peek_enemy(gm: Node) -> Array:
	if gm == null or gm.opponents == null:
		return []
	var b: EnemyBoard = null
	var o = gm.opponents
	if o is SnapshotOpponents and not o.current_snapshot().is_empty():
		b = BoardSnapshot.to_board(o.current_snapshot(), o.unit_roster, o.item_roster)
	else:
		var src = o.fallback if o is SnapshotOpponents else o
		if src is RandomOpponents:
			var state: int = gm.rng.state
			b = src.board_for_round(GameState.round_number)
			gm.rng.state = state
	if b == null:
		return []
	var out := []
	for bu in b.units:
		if bu != null and bu.unit != null:
			out.append([bu.unit, maxi(bu.star, 1)])
	return out

# --- helpers -----------------------------------------------------------------------------------------

# Hands out a reward: "item" (a drop for the stage), "special" (a special item), "cost4" / "cost5" (a free
# unit of that cost to the bench). False if it couldn't be given now (no bench room, nothing left).
static func _give(r: PlayerRules, what: String, round_number := -1) -> bool:
	var p := r.player
	match what:
		"item", "special":
			var item: ItemData
			if what == "item":
				item = r.pick_drop(r.drop_stage(round_number if round_number > 0 else GameState.round_number), p.rng, p.dropped)
			else:
				item = _special(r)
			if item == null:
				return false
			p.dropped[item.id] = int(p.dropped.get(item.id, 0)) + 1
			var got: Array[ItemData] = [item]
			p.receive(got)
			return true
		"cost4", "cost5":
			var slot := r.board.first_free_bench()
			var d := r.pool.pick(5 if what == "cost5" else 4, p.rng)
			if slot == -1 or d == null or not r.pool.take(d):
				return false
			r.board.put_on_bench(r.board.make_unit(d, r.unit_scene), slot)
			return true
	return false

static func _special(r: PlayerRules) -> ItemData:
	var p := r.player
	var choices := r.item_roster.filter(func(i): return i != null and i.is_special() and i.drop_weight > 0.0 and not (i.once_a_run() and p.dropped.has(i.id)))
	if choices.is_empty():
		return null
	var total := 0.0
	for i in choices:
		total += i.drop_weight
	var roll := p.rng.randf() * total
	for i in choices:
		roll -= i.drop_weight
		if roll < 0.0:
			return i
	return choices.back()

static func _units_with(r: PlayerRules, test: Callable) -> int:
	var n := 0
	for u in r.board.all_player_units():
		if u.data != null and not u.summoned and test.call(u):
			n += 1
	return n

# Picks one of `rows` ([value, weight, ...]) by weight with `rng`.
static func _weighted(rng: RandomNumberGenerator, rows: Array) -> Array:
	var total := 0
	for row in rows:
		total += int(row[1])
	var roll := rng.randi_range(0, maxi(total - 1, 0))
	for row in rows:
		roll -= int(row[1])
		if roll < 0:
			return row
	return rows.back()

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

static func _merge(into: Dictionary, fx: Dictionary) -> void:
	for k in fx:
		into[k] = float(into.get(k, 0.0)) + float(fx[k])

static func _level_text(l: float) -> String:
	l = clampf(l, 1.0, 10.0)
	return str(int(l)) if is_equal_approx(l, roundf(l)) else "%.1f" % l

static func _log(p: PlayerState, line: String) -> void:
	var s := _st(p)
	if not s.has("log"):
		s.log = []
	s.log.append(line)
	while s.log.size() > LOG_LINES:
		s.log.pop_front()

static func _notice(p: PlayerState, text: String, colour: Color) -> void:
	if p.is_local:
		Events.notice.emit(text, colour)

static func _changed(p: PlayerState) -> void:
	if p.is_local:
		Events.king_changed.emit()
