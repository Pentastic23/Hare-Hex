# abilities.gd
class_name Abilities

# The units' abilities (docs/abilities.md). A unit casts when its mana bar is full: Unit._cast calls
# Abilities.cast, which runs the unit's ability. DEFS holds each ability's name, text and numbers; the
# behaviour is the match in cast(). Deterministic: targets are picked by fixed rules (ties go to the
# lower tile, Board.tile_order), and timed effects (stuns, buffs, shields, queued hits) are stepped by
# the combat tick in unit.gd.
#
# Numbers: a plain number is an amount at 1 star (damage, healing, shield). It scales like stats,
# x1 / x1.8 / x3.2 by star (rounded to 5), and with an enemy's stat_scale; damage also with the
# caster's damage bonus. An array is the value at 1 / 2 / 3 stars as it is (percentages, seconds).
# In "text", {a} / {b} show the values: all three stars in the shop, the unit's star in the inspector.
# Units without an entry still cast the old placeholder (chunk 4 of the plan is not built yet).

const CAST_TIME := 0.5   # seconds a cast locks the caster (the skill clip; no attacks or moves)

const DEFS := {
	# 1-cost
	"Cleric": {"name": "Shepherd's Light", "a": 110, "text": "Heals the two allies with the lowest HP% for {a} each."},
	"Archer": {"name": "Fox Volley", "a": 90, "text": "Fires an arrow at each of the three nearest enemies for {a}."},
	"Knight": {"name": "Lion's Roar", "a": 180, "text": "Strikes the target for {a} and stuns it for 1 s."},
	"Militia": {"name": "Dig In", "a": 200, "text": "Gains a {a} shield for 4 s and taunts adjacent enemies for 2 s."},
	"Acolyte": {"name": "Little Prayer", "a": 150, "text": "Shields the ally with the lowest HP% for {a} for 4 s. What is left of the shield then heals them."},
	"Apprentice": {"name": "Hopping Bolt", "a": 120, "text": "A bolt hits the target for {a}, then hops to the nearest enemy not yet hit, twice, dealing 30% less each hop."},
	"Skeleton": {"name": "Gnaw", "a": 150, "text": "Bites the target for {a} and heals for half the damage dealt."},
	"Imp": {"name": "Sonic Screech", "a": 80, "text": "Enemies within 2 hexes take {a} and are chilled 30% for 3 s."},
	"Sprite": {"name": "Acorn Hex", "a": 120, "b": [2.0, 2.5, 3.0], "text": "Hits the target for {a} and silences it (no mana) for {b} s."},
	"Firebrand": {"name": "Flare Spin", "a": 110, "text": "Spins, dealing {a} to every adjacent enemy and burning them (3% of max HP per second for 3 s)."},
	"Frostling": {"name": "Snowball", "a": 130, "text": "Hits the target for {a}, chilling it and the enemies next to it by 30% for 3 s."},
	"Miner": {"name": "Pick Through", "a": 160, "text": "Strikes the target for {a}; it takes 15% more damage for 4 s."},
	"Initiate": {"name": "Monkey Barrage", "a": 35, "text": "Five quick strikes on the target for {a} each. They count as attacks, so on-hit effects apply."},
	# 2-cost
	"Guardian": {"name": "Shell Up", "text": "Takes 50% less damage for 3 s and taunts enemies within 2 hexes for 2 s."},
	"Bard": {"name": "Dawn Chorus", "b": [25, 35, 50], "text": "Allies within 2 hexes (the Bard too) gain {b}% attack speed for 4 s."},
	"Alchemist": {"name": "Tonic Flask", "a": 150, "text": "The ally with the lowest HP% heals {a} and gains 20% attack speed for 3 s."},
	"Ghoul": {"name": "Feast", "a": 180, "b": 200, "text": "Bites the target for {a}. If it is then below 30% HP, the Ghoul heals {b}."},
	"Sparkcaller": {"name": "Arc Lash", "a": 170, "text": "Hits every enemy in a line through the target, up to 3 hexes, for {a}."},
	"Frost Archer": {"name": "Piercing Icicle", "a": 220, "text": "Shoots the farthest enemy for {a} and chills it 40% for 3 s."},
	"Ironbeard": {"name": "Headbutt", "a": 150, "b": 150, "text": "Rams the target for {a}, stuns it for 1.5 s and gains a {b} shield for 4 s."},
	"Monk": {"name": "Bamboo Calm", "text": "Sits still for 1 s, heals 25% of its max HP, and its next attack stuns for 1 s."},
	"Cultist": {"name": "Blood Pact", "text": "Spends 10% of its HP: the two nearest enemies take 25% more damage for 4 s and burn (3% of max HP per second)."},
	# 3-cost
	"Mage": {"name": "Moonbolt Volley", "a": 90, "text": "Four bolts, one after another, each at the enemy with the lowest HP, for {a} each."},
	"Pyromancer": {"name": "Flame Pillar", "a": 220, "text": "Fire on the biggest cluster of enemies: {a} to each within 1 hex of it, and a double-strength burn for 4 s."},
	"Ice Mage": {"name": "Glacier Slam", "a": 180, "text": "Ice on the biggest cluster of enemies: {a} to each within 1 hex of it, stunned for 1.25 s."},
	"Dryad": {"name": "Eucalyptus Bloom", "a": 70, "text": "Heals every ally for {a} and gives them 1% regen per second for 4 s."},
	"Skald": {"name": "War Chant", "b": [20, 30, 45], "c": 150, "text": "Allies within 2 hexes gain {b}% damage for 4 s; the Skald gains a {c} shield for 4 s."},
	"Shadowfist": {"name": "Stink Cloud", "a": 120, "text": "Adjacent enemies take {a} and their next 2 attacks miss."},
	"Sunmonk": {"name": "Solar Palm", "a": 100, "text": "Three blows on the target for {a} each; the last one stuns for 1 s."},
	"Winter Knight": {"name": "Frozen Bulwark", "text": "Adjacent enemies are chilled 50% for 3 s, and it takes 25% less damage for 4 s."},
	# 4-cost
	"Berserker": {"name": "Bloodrage", "b": [60, 75, 100], "text": "For 5 s: {b}% attack speed and 30% omnivamp."},
	"Hunter": {"name": "Hunter's Mark", "a": 250, "text": "Shoots the enemy with the lowest HP for {a}; it takes 30% more damage from everyone for 5 s."},
	"Lich": {"name": "Death Roll", "a": 350, "text": "Seizes the target: stunned for 1.5 s while taking {a} over that time. The Lich heals 30% of it."},
	"Frost Giant": {"name": "Avalanche Stomp", "a": 150, "text": "Enemies within 2 hexes take {a} and are stunned for 1.5 s."},
	"Dwarf Gunner": {"name": "Quill Shot", "a": 200, "text": "Hits the target and every enemy next to it for {a}; they take 10% more damage for 4 s."},
	"Archmage": {"name": "Dazzling Display", "a": 220, "text": "Stuns enemies within 2 hexes for 1 s, then the three nearest take {a}."},
	"Herald": {"name": "Rallying Cry", "a": 100, "text": "Every ally takes 20% less damage and gains 15% attack speed for 4 s; Order allies also heal {a}."},
	"Hellknight": {"name": "Red Fury", "text": "Taunts enemies within 2 hexes for 2 s and gains 30% omnivamp and 20% less damage taken for 4 s."},
	# 5-cost
	"Dragon": {"name": "Dragonfire Breath", "a": 400, "b": 300, "text": "Breathes fire on the target and the hexes behind it: {a} and a burn. The Dragon gains a {b} shield for 4 s."},
	"Titan": {"name": "Earthquake", "a": 300, "text": "Stuns every enemy for 1 s; those within 2 hexes also take {a}."},
	# chunk 2: movement and stealth
	"Scout": {"name": "Hare's Hop", "a": 40, "text": "Leaps up to 2 hexes to the open hex farthest from enemies; its next 3 attacks deal {a} more damage."},
	"Nightblade": {"name": "Panther Pounce", "a": 220, "text": "Leaps next to the enemy with the lowest HP within 4 hexes and strikes it for {a}."},
	"Assassin": {"name": "Shadowstep", "a": 300, "text": "Teleports behind the enemy farthest away and strikes it for {a}."},
	"Warlord": {"name": "Rhino Charge", "a": 200, "text": "Charges up to 4 hexes towards the farthest enemy, stopping at the first unit in the way. Enemies next to its path take {a} and are stunned for 1 s."},
	"Nightstalker": {"name": "Moonlit Hunt", "a": 250, "text": "Vanishes for 2 s: it can't be targeted but keeps attacking. Its first attack after it reappears deals {a} more and always crits."},
	"Seraph": {"name": "Wings of Dawn", "a": 200, "text": "Heals every ally for {a}; the ally with the lowest HP% also can't be targeted for 1.5 s."},
	# chunk 3: summons and zones
	"Necromancer": {"name": "Raise Thrall", "a": 300, "b": 30, "text": "Raises a Bone Thrall ({a} HP, {b} damage) next to itself. One at a time: casting again heals it fully."},
	"Demonologist": {"name": "Pact Demon", "a": 350, "b": 40, "c": 150, "text": "Summons a Pact Demon ({a} HP, {b} damage) that explodes for {c} to adjacent enemies when it dies. Up to two; with two out, casting heals them fully."},
	"Beastmaster": {"name": "Jungle Call", "a": 250, "b": 35, "text": "Calls two jungle beasts ({a} HP, {b} damage, fast attacks). Casting again brings back any that died."},
	"Plague Doctor": {"name": "Miasma", "a": 50, "text": "A plague cloud on the biggest cluster of enemies for 4 s: enemies within 1 hex of it take {a} per second and 15% more damage."},
	"Druid": {"name": "Antler Grove", "b": [3, 4, 5], "text": "Grows a grove around itself for 4 s: allies within 1 hex of it regenerate {b}% of max HP per second."},
	"Runesmith": {"name": "Rune Ward", "a": 160, "b": 20, "text": "The two allies with the lowest HP% get a {a} shield and thorns for 4 s: attackers take {b} per hit."},
}

# Summons (chunk 3): the model they borrow, their attack speed and how many letters they show.
const SUMMONS := {
	"Bone Thrall": {"model": "res://tres/units/skeleton.tres", "aps": 0.7, "label": "BT"},
	"Pact Demon": {"model": "res://tres/units/imp.tres", "aps": 0.8, "label": "PD"},
	"Jungle Beast": {"model": "res://tres/units/initiate.tres", "aps": 1.1, "label": "JB"},
}
const SUMMON_SIZE := 0.8   # summons are a little smaller than real units

static var enabled := true   # tests turn casts off to check other mechanics on their own

static func has(d: UnitData) -> bool:
	return d != null and DEFS.has(d.display_name)

static func name_of(d: UnitData) -> String:
	return DEFS[d.display_name].name if has(d) else ""

# The ability's text with its numbers: star 0 shows all three stars ("110 / 200 / 350").
static func text(d: UnitData, star := 0) -> String:
	if not has(d):
		return ""
	var def: Dictionary = DEFS[d.display_name]
	var out: String = def.text
	for k in ["a", "b", "c"]:
		if def.has(k):
			out = out.replace("{%s}" % k, _shown(def[k], star))
	return out

# The ability as a tooltip paragraph (shop cards, planner tiles), all three stars; "" without one.
static func tooltip_line(d: UnitData) -> String:
	return "\n%s: %s" % [name_of(d), text(d)] if has(d) else ""

static func _shown(v, star: int) -> String:
	if star > 0:
		return _num(value_at(v, star))
	return " / ".join([_num(value_at(v, 1)), _num(value_at(v, 2)), _num(value_at(v, 3))])

static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(x)

# A value at a star: arrays as they are, plain numbers scaled like stats (rounded to 5).
static func value_at(v, star: int) -> float:
	if v is Array:
		return float(v[clampi(star, 1, 3) - 1])
	return snappedf(float(v) * Unit.STAR_MULT[clampi(star, 1, 3)], 5.0)

# This caster's amount for a key: scaled by star, and by stat_scale for plain numbers (enemies).
static func amt(u: Unit, key: String) -> float:
	var v = DEFS[u.data.display_name][key]
	return value_at(v, u.star) * (1.0 if v is Array else u.stat_scale)

# --- casting ------------------------------------------------------------------------------------

# Runs u's ability on its target t. Returns how long the cast locks u (CAST_TIME, longer for channels).
static func cast(u: Unit, t: Unit) -> float:
	var lock := CAST_TIME
	match u.data.display_name:
		"Cleric":
			for a in lowest_hp_allies(u, 2):
				a.heal(amt(u, "a"))
		"Archer":
			for e in nearest_enemies(u, u.coord, 3):
				hit(u, e, amt(u, "a"))
		"Knight":
			hit(u, t, amt(u, "a"))
			t.apply_stun(1.0)
		"Militia":
			u.add_timed_shield(amt(u, "a"), 4.0)
			for e in enemies_within(u, u.coord, 1):
				e.apply_taunt(u, 2.0)
		"Acolyte":
			for a in lowest_hp_allies(u, 1):
				a.add_timed_shield(amt(u, "a"), 4.0, true)
		"Apprentice":
			var dmg := amt(u, "a")
			var hit_list: Array[Unit] = [t]
			hit(u, t, dmg)
			var last := t
			for i in 2:
				var next: Unit = null
				for e in nearest_enemies(u, last.coord, 99):
					if not hit_list.has(e):
						next = e
						break
				if next == null:
					break
				dmg *= 0.7
				hit(u, next, dmg)
				hit_list.append(next)
				last = next
		"Skeleton":
			u.heal(hit(u, t, amt(u, "a")) * 0.5)
		"Imp":
			for e in enemies_within(u, u.coord, 2):
				hit(u, e, amt(u, "a"))
				e.apply_chill(0.3, 3.0)
		"Sprite":
			hit(u, t, amt(u, "a"))
			t.apply_silence(amt(u, "b"))
		"Firebrand":
			for e in enemies_within(u, u.coord, 1):
				hit(u, e, amt(u, "a"))
				e.apply_burn(0.03 * e.max_hp(), u)
		"Frostling":
			var around := enemies_within(u, t.coord, 1)
			hit(u, t, amt(u, "a"))
			for e in around:
				e.apply_chill(0.3, 3.0)
		"Miner":
			hit(u, t, amt(u, "a"))
			t.apply_curse(0.15, 4.0)
		"Initiate":
			var d := amt(u, "a")
			for i in 5:
				u.queue_action(0.1 * i, func(): _strike(u, d))
		"Guardian":
			u.add_buff("Shell Up", "dr", 0.5, 3.0)
			for e in enemies_within(u, u.coord, 2):
				e.apply_taunt(u, 2.0)
		"Bard":
			for a in allies_within(u, u.coord, 2):
				a.add_buff("Dawn Chorus", "as", amt(u, "b") / 100.0, 4.0)
		"Alchemist":
			for a in lowest_hp_allies(u, 1):
				a.heal(amt(u, "a"))
				a.add_buff("Tonic Flask", "as", 0.2, 3.0)
		"Ghoul":
			hit(u, t, amt(u, "a"))
			if t.dead or t.health < t.max_hp() * 0.3:
				u.heal(amt(u, "b"))
		"Sparkcaller":
			for e in enemies_in_line(u, t, 3):
				hit(u, e, amt(u, "a"))
		"Frost Archer":
			var far := farthest_enemy(u)
			if far != null:
				hit(u, far, amt(u, "a"))
				far.apply_chill(0.4, 3.0)
		"Ironbeard":
			hit(u, t, amt(u, "a"))
			t.apply_stun(1.5)
			u.add_timed_shield(amt(u, "b"), 4.0)
		"Monk":
			lock = 1.0
			u.next_attack_stun = 1.0
			u.queue_action(1.0, func(): u.heal(u.max_hp() * 0.25))
		"Cultist":
			u.health = maxf(1.0, u.health * 0.9)
			for e in nearest_enemies(u, u.coord, 2):
				e.apply_curse(0.25, 4.0)
				e.apply_burn(0.03 * e.max_hp(), u)
		"Mage":
			var d := amt(u, "a")
			for i in 4:
				u.queue_action(0.15 * i, func():
					var e := lowest_hp_enemy(u)
					if e != null:
						hit(u, e, d))
		"Pyromancer":
			var c := cluster(u)
			if c != null:
				for e in enemies_within(u, c.coord, 1):
					hit(u, e, amt(u, "a"))
					e.apply_burn(0.06 * e.max_hp(), u, 4.0)
		"Ice Mage":
			var c := cluster(u)
			if c != null:
				for e in enemies_within(u, c.coord, 1):
					hit(u, e, amt(u, "a"))
					e.apply_stun(1.25)
		"Dryad":
			for a in allies(u):
				a.heal(amt(u, "a"))
				a.add_buff("Eucalyptus Bloom", "regen", 0.01, 4.0)
		"Skald":
			for a in allies_within(u, u.coord, 2):
				a.add_buff("War Chant", "dmg", amt(u, "b") / 100.0, 4.0)
			u.add_timed_shield(amt(u, "c"), 4.0)
		"Shadowfist":
			for e in enemies_within(u, u.coord, 1):
				hit(u, e, amt(u, "a"))
				e.apply_blind(2)
		"Sunmonk":
			var d := amt(u, "a")
			for i in 3:
				var last := i == 2
				u.queue_action(0.2 * i, func():
					var e := u.target if is_instance_valid(u.target) and not u.target.dead else u.board.nearest_enemy(u)
					if e != null:
						hit(u, e, d)
						if last and not e.dead:
							e.apply_stun(1.0))
		"Winter Knight":
			for e in enemies_within(u, u.coord, 1):
				e.apply_chill(0.5, 3.0)
			u.add_buff("Frozen Bulwark", "dr", 0.25, 4.0)
		"Berserker":
			u.add_buff("Bloodrage", "as", amt(u, "b") / 100.0, 5.0)
			u.add_buff("Bloodrage vamp", "vamp", 0.3, 5.0)
		"Hunter":
			var e := lowest_hp_enemy(u)
			if e != null:
				hit(u, e, amt(u, "a"))
				e.apply_curse(0.3, 5.0)
		"Lich":
			lock = 1.5
			t.apply_stun(1.5)
			var d := amt(u, "a") / 6.0
			for i in 6:
				u.queue_action(0.25 * (i + 1), func():
					if not t.dead:
						u.heal(hit(u, t, d) * 0.3))
		"Frost Giant":
			for e in enemies_within(u, u.coord, 2):
				hit(u, e, amt(u, "a"))
				e.apply_stun(1.5)
		"Dwarf Gunner":
			for e in enemies_within(u, t.coord, 1):
				hit(u, e, amt(u, "a"))
				e.apply_curse(0.1, 4.0)
		"Archmage":
			for e in enemies_within(u, u.coord, 2):
				e.apply_stun(1.0)
			for e in nearest_enemies(u, u.coord, 3):
				hit(u, e, amt(u, "a"))
		"Herald":
			for a in allies(u):
				a.add_buff("Rallying Cry", "dr", 0.2, 4.0)
				a.add_buff("Rallying Cry speed", "as", 0.15, 4.0)
				if a.data.tags.has(&"Order"):
					a.heal(amt(u, "a"))
		"Hellknight":
			for e in enemies_within(u, u.coord, 2):
				e.apply_taunt(u, 2.0)
			u.add_buff("Red Fury", "vamp", 0.3, 4.0)
			u.add_buff("Red Fury guard", "dr", 0.2, 4.0)
		"Dragon":
			for e in enemies_in_cone(u, t):
				hit(u, e, amt(u, "a"))
				e.apply_burn(0.03 * e.max_hp(), u)
			u.add_timed_shield(amt(u, "b"), 4.0)
		"Titan":
			for e in enemies(u):
				e.apply_stun(1.0)
				if Board.hex_distance(u.coord, e.coord) <= 2:
					hit(u, e, amt(u, "a"))
		"Scout":
			var spot := safest_tile(u, 2)
			u.leap_to(spot)
			u.empower_hits = 3
			u.empower_dmg = amt(u, "a") * u.damage_bonus()
		"Nightblade":
			var prey: Array[Unit] = []
			for e in targets(u):
				if Board.hex_distance(u.coord, e.coord) <= 4:
					prey.append(e)
			prey.sort_custom(func(a, b): return a.health < b.health or (a.health == b.health and Board.tile_order(a.coord) < Board.tile_order(b.coord)))
			_pounce(u, t, prey, true)
		"Assassin":
			var prey := targets(u)
			prey.sort_custom(func(a, b):
				var da := Board.hex_distance(u.coord, a.coord)
				var db := Board.hex_distance(u.coord, b.coord)
				return da > db or (da == db and Board.tile_order(a.coord) < Board.tile_order(b.coord)))
			_pounce(u, t, prey, false)
		"Warlord":
			var goal := farthest_enemy(u)
			if goal != null:
				var path: Array[Vector2i] = []
				var cur := u.coord
				for i in 4:
					var next := _from_cube(Board.to_cube(cur) + _direction(cur, goal.coord))
					if not open_tile(u, next):
						break
					path.append(next)
					cur = next
				var swept: Array[Vector2i] = path.duplicate()
				swept.append(u.coord)
				for e in enemies(u):
					for c in swept:
						if Board.hex_distance(c, e.coord) <= 1:
							hit(u, e, amt(u, "a"))
							e.apply_stun(1.0)
							break
				if not path.is_empty():
					u.leap_to(path[-1], 0.1 * path.size())
		"Nightstalker":
			u.untargetable_left = 2.0
			u.empower_hits = 1
			u.empower_dmg = amt(u, "a") * u.damage_bonus()
			u.empower_crit = true
			u.empower_after_stealth = true
		"Seraph":
			var low := lowest_hp_allies(u, 1)
			for a in allies(u):
				a.heal(amt(u, "a"))
			for a in low:
				a.untargetable_left = maxf(a.untargetable_left, 1.5)
		"Necromancer":
			var alive := living_summons(u)
			if alive.is_empty():
				summon(u, "Bone Thrall", "a", "b")
			else:
				alive[0].heal(alive[0].max_hp())
		"Demonologist":
			var alive := living_summons(u)
			if alive.size() < 2:
				var demon := summon(u, "Pact Demon", "a", "b")
				if demon != null:
					var burst := amt(u, "c")
					demon.on_death = func():
						for e in enemies_within(demon, demon.coord, 1):
							hit(demon, e, burst)
			else:
				for s in alive:
					s.heal(s.max_hp())
		"Beastmaster":
			for i in 2 - living_summons(u).size():
				summon(u, "Jungle Beast", "a", "b")
		"Plague Doctor":
			var c := cluster(u)
			var gm = _gm(u)
			if c != null and gm != null:
				gm.add_zone("miasma", c.coord, 1, 4.0, u.team, amt(u, "a") * u.damage_bonus(), u)
		"Druid":
			var gm = _gm(u)
			if gm != null:
				gm.add_zone("grove", u.coord, 1, 4.0, u.team, amt(u, "b") / 100.0, u)
		"Runesmith":
			for a in lowest_hp_allies(u, 2):
				a.add_timed_shield(amt(u, "a"), 4.0)
				a.thorns = amt(u, "b")
				a.thorns_left = 4.0
	return lock

static func _gm(u: Unit):
	return u.get_tree().get_first_node_in_group("game_manager") if u.is_inside_tree() else null

static func living_summons(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for s in u.summons:
		if is_instance_valid(s) and not s.dead:
			out.append(s)
	return out

# A temporary unit for u's side on the free hex nearest to it: HP and damage from u's ability
# (keys hp_key / dmg_key, by u's star and stat_scale), the look of another unit (SUMMONS), no traits,
# items or mana. It joins the fight from the next tick and is freed when the fight ends.
static func summon(u: Unit, sname: String, hp_key: String, dmg_key: String) -> Unit:
	var gm = _gm(u)
	var spot := free_tile_near(u, u.coord)
	if gm == null or spot == Board.NO_STEP:
		return null
	var def: Dictionary = DEFS[u.data.display_name]
	var info: Dictionary = SUMMONS[sname]
	var look: UnitData = load(info.model)
	var d := UnitData.new()
	d.display_name = sname
	d.short_name = info.label
	d.cost = 0
	d.max_health = value_at(def[hp_key], u.star)
	d.attack_damage = value_at(def[dmg_key], u.star)
	d.attack_range = 1.0
	d.attacks_per_second = info.aps
	d.move_speed = look.move_speed
	d.max_mana = 0.0
	d.start_mana = 0.0
	d.model = look.model
	var s := (load("res://scenes/unit.tscn").instantiate() as Unit)
	u.board.get_node("Units").add_child(s)
	s.setup(d, u.team)
	s.summoned = true
	s.stat_scale = u.stat_scale
	s.get_node("ModelHolder").scale = Vector3.ONE * SUMMON_SIZE
	u.board.claim(s, spot)
	s.position = u.board.grid_to_world(spot)
	s.begin_combat()
	u.summons.append(s)
	gm.add_summon(s)
	return s

# The empty, unlocked hex nearest to c (ties: lower tile), or Board.NO_STEP.
static func free_tile_near(u: Unit, c: Vector2i) -> Vector2i:
	var best := Board.NO_STEP
	var best_d := 999
	for t in u.board.tiles:
		var tc: Vector2i = t
		if not u.board.is_unlocked(tc):
			continue
		var occ = u.board.tiles[tc].occupant
		if occ != null and is_instance_valid(occ):
			continue
		var d := Board.hex_distance(c, tc)
		if d < best_d or (d == best_d and Board.tile_order(tc) < Board.tile_order(best)):
			best_d = d
			best = tc
	return best

# Nightblade and Assassin: leap next to the first enemy in `prey` that has an open hex beside it
# (nearest to the caster, or farthest for a "behind" teleport) and strike it. With nowhere to land,
# it strikes its own target where it stands.
static func _pounce(u: Unit, t: Unit, prey: Array[Unit], near_side: bool) -> void:
	for e in prey:
		var spots: Array[Vector2i] = []
		for c in u.board.neighbors(e.coord):
			if open_tile(u, c):
				spots.append(c)
		if spots.is_empty():
			continue
		spots.sort_custom(func(a, b):
			var da := Board.hex_distance(u.coord, a)
			var db := Board.hex_distance(u.coord, b)
			if da != db:
				return da < db if near_side else da > db
			return Board.tile_order(a) < Board.tile_order(b))
		u.leap_to(spots[0])
		u.target = e
		hit(u, e, amt(u, "a"))
		return
	hit(u, t, amt(u, "a"))

# A tile u can land on: on the board, unlocked, and empty (or u's own).
static func open_tile(u: Unit, c: Vector2i) -> bool:
	if not u.board.tiles.has(c) or not u.board.is_unlocked(c):
		return false
	var occ = u.board.tiles[c].occupant
	return occ == null or occ == u or not is_instance_valid(occ)

# The open tile within r hexes of u that is farthest from the nearest enemy (ties: stay, then lower tile).
static func safest_tile(u: Unit, r: int) -> Vector2i:
	var foes := enemies(u)
	var best := u.coord
	var best_d := _gap(u.coord, foes)
	var cells: Array[Vector2i] = []
	for c in u.board.tiles:
		cells.append(c)
	cells.sort_custom(func(a, b): return Board.tile_order(a) < Board.tile_order(b))
	for c in cells:
		if Board.hex_distance(u.coord, c) <= r and open_tile(u, c):
			var d := _gap(c, foes)
			if d > best_d:
				best_d = d
				best = c
	return best

static func _gap(c: Vector2i, foes: Array[Unit]) -> int:
	var d := 99
	for e in foes:
		d = mini(d, Board.hex_distance(c, e.coord))
	return d

# Ability damage: scaled by the caster's damage bonus, reduced like an attack, not an attack (no
# crit, dodge or on-hit effects, no mana). Omnivamp heals from it. Returns the HP removed.
static func hit(u: Unit, e: Unit, amount: float) -> float:
	if e == null or e.dead:
		return 0.0
	var removed := e.take_damage(amount * u.damage_bonus(), u)
	u.damage_dealt += removed
	var steal := u.omnivamp()
	if steal > 0.0:
		u.heal(removed * steal)
	return removed

# One of the Initiate's strikes: an attack with fixed damage on the current target (or the nearest).
static func _strike(u: Unit, amount: float) -> void:
	var e := u.target if is_instance_valid(u.target) and not u.target.dead else u.board.nearest_enemy(u)
	if e != null:
		u._attack(e, amount * u.damage_bonus())

# --- picking targets (deterministic) ------------------------------------------------------------

# Every living unit on the board, in tile order.
static func _units(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for n in u.board.get_node("Units").get_children():
		var o := n as Unit
		if o != null and o.data != null and not o.dead and o.coord.x >= 0 and not o.is_queued_for_deletion():
			out.append(o)
	out.sort_custom(func(a, b): return Board.tile_order(a.coord) < Board.tile_order(b.coord))
	return out

static func enemies(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in _units(u):
		if o.team != u.team:
			out.append(o)
	return out

# Enemies that can be picked as a target (not vanished): single-target picks use these; areas hit all.
static func targets(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in enemies(u):
		if o.untargetable_left <= 0.0:
			out.append(o)
	return out

static func allies(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in _units(u):
		if o.team == u.team:
			out.append(o)
	return out

static func enemies_within(u: Unit, c: Vector2i, r: int) -> Array[Unit]:
	return _within(enemies(u), c, r)

static func allies_within(u: Unit, c: Vector2i, r: int) -> Array[Unit]:
	return _within(allies(u), c, r)

static func _within(list: Array[Unit], c: Vector2i, r: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in list:
		if Board.hex_distance(c, o.coord) <= r:
			out.append(o)
	return out

static func _first(list: Array[Unit], k: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in list:
		if out.size() >= k:
			break
		out.append(o)
	return out

# The k enemies nearest to c (ties: lower tile first).
static func nearest_enemies(u: Unit, c: Vector2i, k: int) -> Array[Unit]:
	var list := targets(u)
	list.sort_custom(func(a, b):
		var da := Board.hex_distance(c, a.coord)
		var db := Board.hex_distance(c, b.coord)
		return da < db or (da == db and Board.tile_order(a.coord) < Board.tile_order(b.coord)))
	return _first(list, k)

static func lowest_hp_allies(u: Unit, k: int) -> Array[Unit]:
	var list := allies(u)
	list.sort_custom(func(a, b):
		var ra: float = a.health / a.max_hp()
		var rb: float = b.health / b.max_hp()
		return ra < rb or (ra == rb and Board.tile_order(a.coord) < Board.tile_order(b.coord)))
	return _first(list, k)

# The enemy with the least HP left (ties: lower tile).
static func lowest_hp_enemy(u: Unit) -> Unit:
	var best: Unit = null
	for e in targets(u):
		if best == null or e.health < best.health:
			best = e
	return best

static func farthest_enemy(u: Unit) -> Unit:
	var best: Unit = null
	var best_d := -1
	for e in targets(u):
		var d := Board.hex_distance(u.coord, e.coord)
		if d > best_d:
			best_d = d
			best = e
	return best

# The enemy with the most enemies within 1 hex of it, itself included (ties: lower tile).
static func cluster(u: Unit) -> Unit:
	var list := enemies(u)
	var best: Unit = null
	var best_n := 0
	for e in targets(u):
		var n := 0
		for o in list:
			if Board.hex_distance(e.coord, o.coord) <= 1:
				n += 1
		if n > best_n:
			best_n = n
			best = e
	return best

# Enemies on n hexes in a straight line starting at t, in the hex direction closest to u -> t.
static func enemies_in_line(u: Unit, t: Unit, n: int) -> Array[Unit]:
	var dir := _direction(u.coord, t.coord)
	var cells: Array[Vector2i] = []
	var cube := Board.to_cube(t.coord)
	for i in n:
		cells.append(_from_cube(cube + dir * i))
	var out: Array[Unit] = []
	for o in enemies(u):
		if cells.has(o.coord):
			out.append(o)
	return out

# The target and the hexes next to it on the far side from u.
static func enemies_in_cone(u: Unit, t: Unit) -> Array[Unit]:
	var d0 := Board.hex_distance(u.coord, t.coord)
	var out: Array[Unit] = []
	for o in enemies(u):
		if o == t or (Board.hex_distance(t.coord, o.coord) == 1 and Board.hex_distance(u.coord, o.coord) > d0):
			out.append(o)
	return out

const CUBE_DIRS := [Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, 0), Vector3i(-1, 0, 1), Vector3i(0, -1, 1)]

# The cube direction that best matches a -> b on the board (first of equals wins).
static func _direction(a: Vector2i, b: Vector2i) -> Vector3i:
	var v := (_flat(b) - _flat(a)).normalized()
	var best: Vector3i = CUBE_DIRS[0]
	var best_dot := -2.0
	for d in CUBE_DIRS:
		var step := _flat(_from_cube(Board.to_cube(b) + d)) - _flat(b)
		var dot := v.dot(step.normalized())
		if dot > best_dot + 0.0001:
			best_dot = dot
			best = d
	return best

static func _from_cube(c: Vector3i) -> Vector2i:
	var y := c.z
	return Vector2i(c.x + ((y - (y & 1)) >> 1), y)

static func _flat(c: Vector2i) -> Vector2:
	return Vector2(sqrt(3.0) * (c.x + 0.5 * (c.y & 1)), 1.5 * c.y)
