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
# Every unit in the roster has an entry (chunks 1-4); the Ability resource is only a fallback.

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
	"Guardian": {"name": "Shell Up", "text": "Gains 100 armour and magic resist for 3 s and taunts enemies within 2 hexes for 2 s."},
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
	"Skald": {"name": "War Chant", "b": [20, 30, 45], "c": 150, "text": "Allies within 2 hexes gain {b}% attack power for 4 s; the Skald gains a {c} shield for 4 s."},
	"Shadowfist": {"name": "Stink Cloud", "a": 120, "text": "Adjacent enemies take {a} and their next 2 attacks miss."},
	"Sunmonk": {"name": "Solar Palm", "a": 100, "text": "Three blows on the target for {a} each; the last one stuns for 1 s."},
	"Winter Knight": {"name": "Frozen Bulwark", "text": "Adjacent enemies are chilled 50% for 3 s, and it gains 35 armour and magic resist for 4 s."},
	# 4-cost
	"Berserker": {"name": "Bloodrage", "b": [60, 75, 100], "text": "For 5 s: {b}% attack speed and 30% omnivamp."},
	"Hunter": {"name": "Hunter's Mark", "a": 250, "text": "Shoots the enemy with the lowest HP for {a}; it takes 30% more damage from everyone for 5 s."},
	"Lich": {"name": "Death Roll", "a": 350, "text": "Seizes the target: stunned for 1.5 s while taking {a} over that time. The Lich heals 30% of it."},
	"Frost Giant": {"name": "Avalanche Stomp", "a": 150, "text": "Enemies within 2 hexes take {a} and are stunned for 1.5 s."},
	"Dwarf Gunner": {"name": "Quill Shot", "a": 200, "text": "Hits the target and every enemy next to it for {a}; they take 10% more damage for 4 s."},
	"Archmage": {"name": "Dazzling Display", "a": 220, "text": "Stuns enemies within 2 hexes for 1 s, then the three nearest take {a}."},
	"Herald": {"name": "Rallying Cry", "a": 100, "text": "Every ally gains 25 armour and magic resist and 15% attack speed for 4 s; Order allies also heal {a}."},
	"Hellknight": {"name": "Red Fury", "text": "Taunts enemies within 2 hexes for 2 s and gains 30% omnivamp and 25 armour and magic resist for 4 s."},
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
	# chunk 4: special rules
	"Thief": {"name": "Pickpocket", "a": 200, "text": "Strikes the target for {a}. If that kills it, you get 1 gold."},
	"Minstrel": {"name": "Encore", "b": [30, 40, 60], "text": "Plays for the two allies closest to a full mana bar (not itself): each gains {b} mana."},
	"Paladin": {"name": "Loyal Guard", "a": 150, "text": "Heals the ally with the lowest HP% for {a} and guards it for 4 s: half the damage it takes goes to the Paladin instead."},
	"Duelist": {"name": "Riposte", "a": 80, "text": "Takes a stance for 2 s: attacks against it are parried (no damage) and each is answered with a counter for {a}."},
	"Magma Guard": {"name": "Molten Shell", "a": 400, "text": "Gains a {a} shield for 5 s. When it breaks or runs out, adjacent enemies take {a} and burn."},
	"Zen Master": {"name": "Pressure Point", "a": 200, "text": "Strikes the target for {a}; it is stunned for 2 s and its mana is emptied."},
	"Deathlord": {"name": "Army of the Dead", "b": 400, "text": "Once per fight, every ally that has died rises at 30% HP for 5 s, then falls again. Otherwise, or later, it strikes the target for {b}."},
	"Phoenix": {"name": "Sunfire Nova", "text": "Sets every enemy burning for 6 s (6% of max HP per second); allies heal 10% of the burn damage it deals meanwhile."},
	"Archdemon": {"name": "Doom", "a": 600, "text": "Dooms the enemy with the most HP: after 4 s it takes {a}. If it dies first, the doom jumps to the nearest of its allies and starts again."},
	"Frost Queen": {"name": "Eternal Winter", "a": 60, "text": "A blizzard over the enemies for 4 s: chilled 50% and {a} damage per second. When it ends, enemies below 50% HP are frozen for 1.5 s."},
	"Faerie Queen": {"name": "Moonlit Charm", "b": [3.0, 3.5, 4.0], "text": "Charms the two enemies that have dealt the most damage: for {b} s they attack their own side."},
	"Reaper": {"name": "Scythe Sweep", "a": 300, "text": "Slashes every adjacent enemy for {a} and executes any left below 20%. Each kill refunds 40 mana."},
	"Treant": {"name": "Overgrowth", "a": 120, "text": "Roots enemies within 2 hexes for 2 s (they can attack but not move), deals {a} to them, and heals itself 20% of its max HP."},
}

# Summons (chunk 3): the model they borrow, their attack speed and how many letters they show.
const SUMMONS := {
	"Bone Thrall": {"model": "res://tres/units/skeleton.tres", "aps": 0.7, "label": "BT"},
	"Pact Demon": {"model": "res://tres/units/imp.tres", "aps": 0.8, "label": "PD"},
	"Jungle Beast": {"model": "res://tres/units/initiate.tres", "aps": 1.1, "label": "JB"},
}
const SUMMON_SIZE := 0.5   # summons are a little smaller than real units

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
			out = out.replace("{%s}" % k, _shown(def[k], star, d.cost))
	return out

# The ability as a tooltip paragraph (shop cards, planner tiles), all three stars; "" without one.
static func tooltip_line(d: UnitData) -> String:
	return "\n%s: %s" % [name_of(d), text(d)] if has(d) else ""

static func _shown(v, star: int, cost := 1) -> String:
	if star > 0:
		return _num(value_at(v, star, cost))
	return " / ".join([_num(value_at(v, 1, cost)), _num(value_at(v, 2, cost)), _num(value_at(v, 3, cost))])

static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(x)

# A value at a star: arrays as they are, plain numbers scaled like stats (rounded to 5).
static func value_at(v, star: int, cost := 1) -> float:
	if v is Array:
		return float(v[clampi(star, 1, 3) - 1])
	return snappedf(float(v) * Unit.star_mult(star, cost), 5.0)

# This caster's amount for a key: scaled by star, and by stat_scale for plain numbers (enemies).
static func amt(u: Unit, key: String) -> float:
	var v = DEFS[u.data.display_name][key]
	return value_at(v, u.star, u.data.cost) * (1.0 if v is Array else u.stat_scale)

# --- casting ------------------------------------------------------------------------------------

# Runs u's ability on its target t. Returns how long the cast locks u (CAST_TIME, longer for channels).
static func cast(u: Unit, t: Unit) -> float:
	var lock := CAST_TIME
	var fx := Vfx.color_of(u)   # the look of each cast is visual only (vfx.gd): nothing reads it back
	match u.data.display_name:
		"Cleric":
			for a in lowest_hp_allies(u, 2):
				Vfx.sky_beam(u, a.global_position, Color("fff2b0"))
				mend(a, amt(u, "a") * u.ability_bonus())
		"Archer":
			for e in nearest_enemies(u, u.coord, 3):
				Vfx.arc_shot(u, Vfx._chest(u), Vfx._chest(e), fx, 0.8)
				hit(u, e, amt(u, "a"), false)
		"Knight":
			Vfx.slash(u, t.global_position, fx)
			Vfx.rings(u, u.global_position, fx, 2, 1.4)
			hit(u, t, amt(u, "a"))
			t.apply_stun(1.0)
		"Militia":
			Vfx.wall(u, fx, 0.8)
			Vfx.shockwave(u, u.board, u.coord, 1, fx, 0.35, 2)
			u.add_timed_shield(amt(u, "a") * u.ability_bonus(), 4.0)
			for e in enemies_within(u, u.coord, 1):
				e.apply_taunt(u, 2.0)
		"Acolyte":
			for a in lowest_hp_allies(u, 1):
				Vfx.sky_beam(u, a.global_position, fx, 0.4, 0.5)
				Vfx.wall(a, Color("cfe8ff"), 0.6)
				a.add_timed_shield(amt(u, "a") * u.ability_bonus(), 4.0, true)
		"Apprentice":
			var dmg := amt(u, "a")
			var hit_list: Array[Unit] = [t]
			var chain: Array = [Vfx._chest(u), Vfx._chest(t)]
			hit(u, t, dmg, false)
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
				hit(u, next, dmg, false)
				hit_list.append(next)
				chain.append(Vfx._chest(next))
				last = next
			Vfx.lightning(u, chain, fx)
		"Skeleton":
			Vfx.slash(u, t.global_position, Color("e8e2c8"))
			Vfx.stream(t, u, Vfx.HEAL, 4)
			mend(u, hit(u, t, amt(u, "a")) * 0.5)
		"Imp":
			Vfx.rings(u, u.global_position, fx, 4, 3.2)
			Vfx.shockwave(u, u.board, u.coord, 2, fx, 0.3, 2)
			for e in enemies_within(u, u.coord, 2):
				hit(u, e, amt(u, "a"))
				e.apply_chill(0.3, 3.0)
		"Sprite":
			Vfx.arc_shot(u, Vfx._chest(u), Vfx._chest(t), Color("b07a3a"), 1.2, 1.0, 0.2)
			hit(u, t, amt(u, "a"), false)
			t.apply_silence(amt(u, "b"))
		"Firebrand":
			Vfx.slash(u, t.global_position, fx, TAU, 1.0, 0.0)
			Vfx.shockwave(u, u.board, u.coord, 1, fx, 0.35, 2)
			for e in enemies_within(u, u.coord, 1):
				hit(u, e, amt(u, "a"))
				e.apply_burn(0.03 * e.max_hp(), u)
		"Frostling":
			var tc := t.coord
			Vfx.arc_shot(u, Vfx._chest(u), Vfx._chest(t), Color("eefaff"), 1.0, 1.0, 0.26)
			Vfx._later(u, 0.25, func(): Vfx.shockwave(u, u.board, tc, 1, fx, 0.3, 2))
			var around := enemies_within(u, t.coord, 1)
			hit(u, t, amt(u, "a"), false)
			for e in around:
				e.apply_chill(0.3, 3.0)
		"Miner":
			Vfx.slash(u, t.global_position, fx, PI * 0.5, 0.8, 1.2)
			Vfx.spikes(u, u.board, [t.coord], fx, 0.6, 0.3)
			Vfx.mark(t, Color("ff6b5a"), 4.0)
			hit(u, t, amt(u, "a"))
			t.apply_curse(0.15, 4.0)
		"Initiate":
			var d := amt(u, "a")
			for i in 5:
				u.queue_action(0.1 * i, func():
					var e := u.target if is_instance_valid(u.target) and not u.target.dead else u.board.nearest_enemy(u)
					if e != null:
						Vfx.slash(u, e.global_position, fx, PI * 0.5, 0.8, 0.6 if i % 2 else -0.6)
					_strike(u, d))
		"Guardian":
			Vfx.wall(u, fx, 2.5, 0.9)
			Vfx.shockwave(u, u.board, u.coord, 2, fx, 0.3, 2)
			u.add_buff("Shell Up", "armor", 100.0, 3.0)
			u.add_buff("Shell Up mr", "mr", 100.0, 3.0)
			for e in enemies_within(u, u.coord, 2):
				e.apply_taunt(u, 2.0)
		"Bard":
			Vfx.notes(u, fx, 4)
			Vfx.rings(u, u.global_position, fx, 2, 3.0)
			for a in allies_within(u, u.coord, 2):
				if a != u:
					Vfx.notes(a, fx, 1)
				a.add_buff("Dawn Chorus", "as", amt(u, "b") / 100.0, 4.0)
		"Alchemist":
			for a in lowest_hp_allies(u, 1):
				Vfx.arc_shot(u, Vfx._chest(u), Vfx._chest(a), Color("7fdc5a"), 1.6, 1.0, 0.22)
				Vfx.rise(a, Color("ffe066"), 6)
				mend(a, amt(u, "a") * u.ability_bonus())
				a.add_buff("Tonic Flask", "as", 0.2, 3.0)
		"Ghoul":
			Vfx.slash(u, t.global_position, fx)
			hit(u, t, amt(u, "a"))
			if t.dead or t.health < t.max_hp() * 0.3:
				Vfx.stream(t, u, Vfx.HEAL, 5)
				mend(u, amt(u, "b") * u.ability_bonus())
		"Sparkcaller":
			var bolt: Array = [Vfx._chest(u)]
			for e in enemies_in_line(u, t, 3):
				bolt.append(Vfx._chest(e))
				hit(u, e, amt(u, "a"), false)
			if bolt.size() == 1:
				bolt.append(Vfx._chest(t))
			Vfx.lightning(u, bolt, fx)
		"Frost Archer":
			var far := farthest_enemy(u)
			if far != null:
				Vfx.arc_shot(u, Vfx._chest(u), Vfx._chest(far), Color("cfefff"), 0.25, 3.5, 0.18)
				Vfx.spikes(u, u.board, [far.coord], fx, 0.9, 0.4)
				hit(u, far, amt(u, "a"), false)
				far.apply_chill(0.4, 3.0)
		"Ironbeard":
			Vfx.shockwave(u, u.board, t.coord, 0, fx, 0.7)
			Vfx.wall(u, fx, 0.6)
			hit(u, t, amt(u, "a"))
			t.apply_stun(1.5)
			u.add_timed_shield(amt(u, "b") * u.ability_bonus(), 4.0)
		"Monk":
			lock = 1.0
			Vfx.rise(u, fx, 12, 1.0)
			Vfx.orbit(u, Color("ffe066"), 1.0, 3, 0.5, 0.4)
			u.next_attack_stun = 1.0
			u.queue_action(1.0, func(): mend(u, u.max_hp() * 0.25))
		"Cultist":
			Vfx.burst(u, Vfx._chest(u), Color("c0203a"), 8, 0.6)
			u.health = maxf(1.0, u.health * 0.9)
			for e in nearest_enemies(u, u.coord, 2):
				Vfx.arc_shot(u, Vfx._chest(u), Vfx._chest(e), Color("c0203a"), 1.3, 1.0, 0.18)
				Vfx.mark(e, Color("c0203a"), 4.0)
				e.apply_curse(0.25, 4.0)
				e.apply_burn(0.03 * e.max_hp(), u)
		"Mage":
			var d := amt(u, "a")
			for i in 4:
				u.queue_action(0.15 * i, func():
					var e := lowest_hp_enemy(u)
					if e != null:
						Vfx.arc_shot(u, Vfx._chest(u) + Vector3(0, 0.6, 0), Vfx._chest(e), fx, 0.6, 1.0, 0.2)
						hit(u, e, d, false))
		"Pyromancer":
			var c := cluster(u)
			if c != null:
				Vfx.pillar(u, c.global_position, fx, 2.7)
				Vfx.shockwave(u, u.board, c.coord, 1, fx, 0.4, 2)
				for e in enemies_within(u, c.coord, 1):
					hit(u, e, amt(u, "a"), false)
					e.apply_burn(0.06 * e.max_hp(), u, 4.0)
		"Ice Mage":
			var c := cluster(u)
			if c != null:
				var cells := _cells_near(u, c.coord, 0, 1)
				Vfx.meteor(u, c.global_position, fx, 0.8)
				Vfx._later(u, 0.22, func(): Vfx.spikes(u, u.board, cells, fx, 0.9, 0.9))
				for e in enemies_within(u, c.coord, 1):
					hit(u, e, amt(u, "a"), false)
					e.apply_stun(1.25)
		"Dryad":
			Vfx.shockwave(u, u.board, u.coord, 3, fx, 0.25, 1)
			for a in allies(u):
				Vfx.rise(a, Vfx.HEAL, 6, 0.6)
				mend(a, amt(u, "a") * u.ability_bonus())
				a.add_buff("Eucalyptus Bloom", "regen", 0.01, 4.0)
		"Skald":
			Vfx.notes(u, Color("ff6b5a"), 3)
			Vfx.rings(u, u.global_position, Color("ff6b5a"), 3, 3.2)
			Vfx.wall(u, fx, 0.8)
			for a in allies_within(u, u.coord, 2):
				a.add_buff("War Chant", "ad", amt(u, "b") / 100.0, 4.0)
			u.add_timed_shield(amt(u, "c") * u.ability_bonus(), 4.0)
		"Shadowfist":
			Vfx.cloud(u, u.global_position, Color("8a9a5a"), 1.5, 1.4)
			Vfx.shockwave(u, u.board, u.coord, 1, Color("8a9a5a"), 0.25, 1)
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
						Vfx.slash(u, e.global_position, Color("ffe066"), PI * 0.5, 0.8, 0.5 if i % 2 else -0.5)
						hit(u, e, d)
						if last and not e.dead:
							Vfx.sky_beam(u, e.global_position, Color("ffe066"), 0.3, 0.5)
							e.apply_stun(1.0))
		"Winter Knight":
			Vfx.spikes(u, u.board, _cells_near(u, u.coord, 1, 1), fx, 0.8, 0.8)
			Vfx.wall(u, Color("cfefff"), 1.0)
			for e in enemies_within(u, u.coord, 1):
				e.apply_chill(0.5, 3.0)
			u.add_buff("Frozen Bulwark", "armor", 35.0, 4.0)
			u.add_buff("Frozen Bulwark mr", "mr", 35.0, 4.0)
		"Berserker":
			Vfx.rise(u, Color("ff3b3b"), 10, 0.6)
			Vfx.orbit(u, Color("d0304a"), 5.0, 5, 0.7, 1.0)
			u.add_buff("Bloodrage", "as", amt(u, "b") / 100.0, 5.0)
			u.add_buff("Bloodrage vamp", "vamp", 0.3, 5.0)
		"Hunter":
			var e := lowest_hp_enemy(u)
			if e != null:
				Vfx.arc_shot(u, Vfx._chest(u), Vfx._chest(e), fx, 0.5, 2.8)
				Vfx.mark(e, Color("ff4a3a"), 5.0)
				hit(u, e, amt(u, "a"), false)
				e.apply_curse(0.3, 5.0)
		"Lich":
			lock = 1.5
			Vfx.orbit(t, fx, 1.5, 6, 0.6, 1.0)
			Vfx.mark(t, fx, 1.5)
			t.apply_stun(1.5)
			var d := amt(u, "a") / 6.0
			for i in 6:
				u.queue_action(0.25 * (i + 1), func():
					if not t.dead:
						Vfx.stream(t, u, fx, 2, 0.3)
						mend(u, hit(u, t, d, false) * 0.3))
		"Frost Giant":
			Vfx.shockwave(u, u.board, u.coord, 2, fx, 0.9, 3)
			Vfx.spikes(u, u.board, _cells_near(u, u.coord, 1, 1), fx, 0.7, 0.5)
			for e in enemies_within(u, u.coord, 2):
				hit(u, e, amt(u, "a"))
				e.apply_stun(1.5)
		"Dwarf Gunner":
			var tc := t.coord
			Vfx.arc_shot(u, Vfx._chest(u), Vfx._chest(t), Color("e0a85a"), 0.3, 2.0)
			Vfx._later(u, 0.2, func(): Vfx.shockwave(u, u.board, tc, 1, fx, 0.4, 2))
			for e in enemies_within(u, t.coord, 1):
				hit(u, e, amt(u, "a"), false)
				e.apply_curse(0.1, 4.0)
		"Archmage":
			Vfx.shockwave(u, u.board, u.coord, 2, Color("fff2b0"), 0.5, 2)
			Vfx.rings(u, u.global_position, fx, 3, 2.6)
			for e in enemies_within(u, u.coord, 2):
				e.apply_stun(1.0)
			for e in nearest_enemies(u, u.coord, 3):
				Vfx.lightning(u, [Vfx._chest(u) + Vector3(0, 0.8, 0), Vfx._chest(e)], fx)
				hit(u, e, amt(u, "a"), false)
		"Herald":
			Vfx.sky_beam(u, u.global_position, fx, 0.6, 0.9)
			Vfx.rings(u, u.global_position, fx, 3, 2.5)
			for a in allies(u):
				Vfx.rise(a, fx, 5, 0.6)
				a.add_buff("Rallying Cry", "armor", 25.0, 4.0)
				a.add_buff("Rallying Cry mr", "mr", 25.0, 4.0)
				a.add_buff("Rallying Cry speed", "as", 0.15, 4.0)
				if a.data.tags.has(&"Order"):
					mend(a, amt(u, "a") * u.ability_bonus())
		"Hellknight":
			Vfx.pillar(u, u.global_position, fx, 1.8, 0.25)
			Vfx.shockwave(u, u.board, u.coord, 2, fx, 0.4, 2)
			for e in enemies_within(u, u.coord, 2):
				e.apply_taunt(u, 2.0)
			u.add_buff("Red Fury", "vamp", 0.3, 4.0)
			u.add_buff("Red Fury guard", "armor", 25.0, 4.0)
			u.add_buff("Red Fury guard mr", "mr", 25.0, 4.0)
		"Dragon":
			Vfx.breath(u, Vfx._chest(u) + Vector3(0, 0.4, 0), Vfx._chest(t), Color("ff7a2e"), 0.6, 1.0)
			Vfx.orbit(u, Color("fff2b0"), 1.2, 4, 0.9, 1.2)
			for e in enemies_in_cone(u, t):
				hit(u, e, amt(u, "a"), false)
				e.apply_burn(0.03 * e.max_hp(), u)
			u.add_timed_shield(amt(u, "b") * u.ability_bonus(), 4.0)
		"Titan":
			Vfx.shockwave(u, u.board, u.coord, 2, fx, 1.0, 3)
			Vfx.shockwave(u, u.board, u.coord, 7, fx.darkened(0.2), 0.25, 1)
			for e in enemies(u):
				e.apply_stun(1.0)
				if Board.hex_distance(u.coord, e.coord) <= 2:
					hit(u, e, amt(u, "a"))
		"Scout":
			var spot := safest_tile(u, 2)
			if spot != u.coord:
				Vfx.blink(u, u.global_position, fx, true)
			Vfx.orbit(u, fx, 2.0, 3, 0.55, 0.8)
			u.leap_to(spot)
			u.empower_hits = 3
			u.empower_dmg = amt(u, "a") * u.ability_bonus()
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
			Vfx.rings(u, u.global_position, fx, 2, 1.6)   # it paws the ground
			Vfx.shockwave(u, u.board, u.coord, 0, fx, 0.4, 3)
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
				for i in path.size():
					var cell := path[i]
					Vfx._later(u, 0.1 * i, func(): Vfx.shockwave(u, u.board, cell, 0, fx, 0.5, 3))
				if not path.is_empty():
					u.leap_to(path[-1], 0.1 * path.size())
		"Nightstalker":
			Vfx.ring(u, u.global_position + Vector3(0, 0.08, 0), 1.2, 0.3, Color("2a1f3d"), 0.5)
			Vfx.blink(u, u.global_position, fx, true)
			Vfx.cloud(u, u.global_position, Color("2a1f3d"), 1.8, 0.7)
			u.untargetable_left = 2.0
			u.empower_hits = 1
			u.empower_dmg = amt(u, "a") * u.ability_bonus()
			u.empower_crit = true
			u.empower_after_stealth = true
		"Seraph":
			var low := lowest_hp_allies(u, 1)
			Vfx.rise(u, fx, 10)
			for a in allies(u):
				Vfx.sky_beam(u, a.global_position, Color("fff2b0"), 0.45, 0.6)
				mend(a, amt(u, "a") * u.ability_bonus())
			for a in low:
				Vfx.wall(a, Color("fff2b0"), 1.2)
				a.untargetable_left = maxf(a.untargetable_left, 1.5)
		"Necromancer":
			var alive := living_summons(u)
			if alive.is_empty():
				Vfx.spikes(u, u.board, _cells_near(u, u.coord, 1, 1), Color("e8e2c8"), 0.5, 0.4)
				summon(u, "Bone Thrall", "a", "b")
			else:
				Vfx.stream(u, alive[0], fx, 6)
				mend(alive[0], alive[0].max_hp())
		"Demonologist":
			var alive := living_summons(u)
			if alive.size() < 2:
				var demon := summon(u, "Pact Demon", "a", "b")
				if demon != null:
					Vfx.pillar(u, demon.global_position, fx, 1.6, 0.2)
					var burst := amt(u, "c")
					demon.on_death = func():
						Vfx.shockwave(demon, demon.board, demon.coord, 1, Color("ff3b3b"), 0.6)
						for e in enemies_within(demon, demon.coord, 1):
							hit(demon, e, burst)
			else:
				for s in alive:
					Vfx.stream(u, s, fx, 5)
					mend(s, s.max_hp())
		"Beastmaster":
			Vfx.rings(u, u.global_position, fx, 3, 2.0)
			for i in 2 - living_summons(u).size():
				summon(u, "Jungle Beast", "a", "b")
		"Plague Doctor":
			var c := cluster(u)
			var gm = _gm(u)
			if c != null and gm != null:
				var spot := u.board.display_pos(c.coord)
				Vfx.arc_shot(u, Vfx._chest(u), spot + Vector3(0, 0.5, 0), Color("8fd14f"), 1.6, 1.0, 0.22)
				Vfx.cloud(u, spot, Color("6f8f2f"), 4.0, 1.4)
				gm.add_zone("miasma", c.coord, 1, 4.0, u.team, amt(u, "a") * u.ability_bonus(), u)
		"Druid":
			Vfx.spikes(u, u.board, _cells_near(u, u.coord, 1, 1), Color("4f9a3a"), 1.1, 3.5)
			Vfx.rise(u, Vfx.HEAL, 8)
			var gm = _gm(u)
			if gm != null:
				gm.add_zone("grove", u.coord, 1, 4.0, u.team, amt(u, "b") / 100.0, u)
		"Runesmith":
			for a in lowest_hp_allies(u, 2):
				Vfx.stream(u, a, fx, 4)
				Vfx.wall(a, Color("7a9cff"), 0.8)
				a.add_timed_shield(amt(u, "a") * u.ability_bonus(), 4.0)
				a.thorns = amt(u, "b")
				a.thorns_left = 4.0
		"Thief":
			var was_alive := not t.dead
			Vfx.slash(u, t.global_position, fx, PI * 0.6, 0.9, -0.5)
			hit(u, t, amt(u, "a"))
			if was_alive and t.dead and not u.summoned:
				var fight = _gm(u)
				if fight is CombatRunner and fight.gold_sink.is_valid():
					fight.credit_gold(u.team, 1)   # 1 gold per Pickpocket kill (user decision: no cap), to the thief's owner
					if u.team == 0 or fight.board.runner_credits_both:
						u._popup("+1 GOLD", Color(1.0, 0.85, 0.3))
						Vfx.coins(u)
		"Minstrel":
			var fans: Array[Unit] = []
			for a in allies(u):
				if a != u and a.data.max_mana > 0.0:
					fans.append(a)
			fans.sort_custom(func(a, b):
				var ra: float = a.mana / a.data.max_mana
				var rb: float = b.mana / b.data.max_mana
				return ra > rb or (ra == rb and Board.tile_order(a.coord) < Board.tile_order(b.coord)))
			Vfx.notes(u, fx, 3)
			for a in _first(fans, 2):
				Vfx.beam(u, Vfx._chest(u), Vfx._chest(a), fx, 0.5)
				Vfx.stream(u, a, Color("7a9cff"), 5)
				a.gain_mana(amt(u, "b"))
		"Paladin":
			for a in lowest_hp_allies(u, 1):
				Vfx.sky_beam(u, a.global_position, fx, 0.5, 0.6)
				mend(a, amt(u, "a") * u.ability_bonus())
				if a != u:
					Vfx.stream(u, a, fx, 4)
					a.link_to = u
					a.link_left = 4.0
		"Duelist":
			Vfx.slash(u, t.global_position, fx, PI * 0.6, 0.9, 0.6)
			Vfx.slash(u, t.global_position, fx, PI * 0.6, 0.9, -0.6)
			Vfx.orbit(u, Color("fff0b0"), 2.0, 2, 0.6, 1.0)
			u.parry_left = 2.0
			u.parry_dmg = amt(u, "a")
		"Magma Guard":
			Vfx.wall(u, fx, 1.0)
			Vfx.orbit(u, Color("ff6a1f"), 5.0, 4, 0.8, 0.5)
			u.add_timed_shield(amt(u, "a") * u.ability_bonus(), 5.0)
			u.erupt_dmg = amt(u, "a")
		"Zen Master":
			Vfx.slash(u, t.global_position, Color("fff2b0"), PI * 0.3, 0.8, 0.0)
			Vfx.shockwave(u, u.board, t.coord, 0, fx, 0.5)
			Vfx.rise(t, Color("6cb4ff"), 8, 0.6)   # its mana leaving it
			hit(u, t, amt(u, "a"))
			t.apply_stun(2.0)
			t.mana = 0.0
		"Deathlord":
			var fallen: Array[Unit] = []
			if not u.army_used:
				for n in u.board.get_node("Units").get_children():
					var o := n as Unit
					if o != null and o.team == u.team and o.dead and not o.summoned and o.coord.x >= 0 and not o.is_queued_for_deletion():
						fallen.append(o)
			if fallen.is_empty():
				Vfx.slash(u, t.global_position, fx)
				Vfx.spikes(u, u.board, [t.coord], Color("2a1f3d"), 1.0, 0.4)
				hit(u, t, amt(u, "b"))
			else:
				u.army_used = true
				Vfx.shockwave(u, u.board, u.coord, 2, fx, 0.4, 2)
				fallen.sort_custom(func(a, b): return Board.tile_order(a.coord) < Board.tile_order(b.coord))
				for o in fallen:
					_raise(u, o)
					Vfx.sky_beam(u, u.board.display_pos(o.coord), Color("cfffe0"), 0.5, 0.6)
		"Phoenix":
			Vfx.pillar(u, u.global_position, fx, 3.0, 0.3)
			Vfx.rings(u, u.global_position, fx, 3, 3.0)
			for e in enemies(u):
				Vfx.arc_shot(u, Vfx._chest(u) + Vector3(0, 1.2, 0), Vfx._chest(e), fx, 1.8, 1.0, 0.2)
				e.apply_burn(0.06 * e.max_hp(), u, 6.0)
			u.nova_left = 6.0
		"Archdemon":
			var big: Unit = null
			for e in targets(u):
				if big == null or e.health > big.health:
					big = e
			if big != null:
				big.doom_left = 4.0
				big.doom_dmg = amt(u, "a") * u.ability_bonus()
				big.doom_by = u
				Vfx.beam(u, Vfx._chest(u), Vfx._chest(big), Color("b0306a"), 0.5)
				Vfx.stream(u, big, Color("b0306a"), 6)
				Vfx.mark(big, Color("e04a9a"), 4.0)
		"Frost Queen":
			Vfx.rise(u, fx, 12, 0.8)
			Vfx.rings(u, u.global_position, fx, 3, 2.2)
			var gm = _gm(u)
			if gm != null:
				gm.add_zone("winter", Vector2i.ZERO, 99, 4.0, u.team, amt(u, "a") * u.ability_bonus(), u)
		"Faerie Queen":
			var list := targets(u)
			list.sort_custom(func(a, b):
				if a.damage_dealt != b.damage_dealt:
					return a.damage_dealt > b.damage_dealt
				if a.damage() != b.damage():
					return a.damage() > b.damage()
				return Board.tile_order(a.coord) < Board.tile_order(b.coord))
			for e in _first(list, 2):
				Vfx.beam(u, Vfx._chest(u), Vfx._chest(e), Unit.CHARM_COLOR, 0.5)
				Vfx.stream(u, e, Unit.CHARM_COLOR, 6)
				Vfx.rings(e, e.global_position, Unit.CHARM_COLOR, 2, 1.1)
				e.apply_charm(u, amt(u, "b"))
		"Reaper":
			Vfx.slash(u, t.global_position, Color("cfd8ff"), TAU, 1.2, 0.0)
			Vfx.shockwave(u, u.board, u.coord, 1, fx, 0.3, 1)
			var kills := 0
			for e in enemies_within(u, u.coord, 1):
				hit(u, e, amt(u, "a"))
				if not e.dead and e.health < e.max_hp() * 0.2:
					u.damage_dealt += e.take_damage(e.health + e.shield, u, false, true)
				if e.dead:
					kills += 1
			if kills > 0:
				u.mana = minf(u.mana + 40.0 * kills, u.data.max_mana)   # the one cast that refunds mana
		"Treant":
			Vfx.spikes(u, u.board, _cells_near(u, u.coord, 1, 2), Color("6b4a2a"), 0.9, 1.6)
			Vfx.rise(u, Vfx.HEAL, 8)
			for e in enemies_within(u, u.coord, 2):
				e.apply_root(2.0)
				hit(u, e, amt(u, "a"))
			mend(u, u.max_hp() * 0.2)
	return lock

# Army of the Dead: a fallen ally stands up where it fell (or the nearest free hex) at 30% HP for 5 s.
static func _raise(u: Unit, o: Unit) -> void:
	var spot := o.coord
	var occ = u.board.tiles[spot].occupant if u.board.tiles.has(spot) else null
	if occ != null and is_instance_valid(occ):
		spot = free_tile_near(u, o.coord)
		if spot == Board.NO_STEP:
			return
	o.dead = false
	o.visible = true
	o._hide_in = -1.0
	o.health = o.max_hp() * 0.3
	o.raised_left = 5.0
	o.moving = false
	o.target = null
	u.board.claim(o, spot)
	o.position = u.board.grid_to_world(spot)
	if o.model_view != null:
		o.model_view.on_fight_over(false)   # back on its feet (idle)
	o._popup("RISE", Color(0.75, 0.95, 0.8))
	Vfx.puff(o)

# Doom: its holder died before it went off, so it jumps to the nearest of the holder's allies.
static func pass_doom(holder: Unit) -> void:
	var next: Unit = null
	for o in allies(holder):
		if next == null or Board.hex_distance(holder.coord, o.coord) < Board.hex_distance(holder.coord, next.coord):
			next = o
	if next != null:
		next.doom_left = 4.0
		next.doom_dmg = holder.doom_dmg
		next.doom_by = holder.doom_by
	holder.doom_left = 0.0

# The fight the unit is in: its board's CombatRunner (zones, summons, gold), so fights on several
# boards (the lobby server's arenas) never reach each other. Falls back to the GameManager.
static func _gm(u: Unit):
	if u.board != null and u.board.runner != null:
		return u.board.runner
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
	d.max_health = value_at(def[hp_key], u.star, u.data.cost)
	d.attack_damage = value_at(def[dmg_key], u.star, u.data.cost)
	d.attack_range = 1.0
	d.attacks_per_second = info.aps
	d.move_speed = look.move_speed
	d.max_mana = 0.0
	d.start_mana = 0.0
	d.model_path = look.model_path
	var s := (load("res://scenes/unit.tscn").instantiate() as Unit)
	u.board.get_node("Units").add_child(s)
	s.setup(d, u.team)
	s.summoned = true
	s.stat_scale = u.stat_scale * (1.0 + u.summon_power)   # Summoners: what they call is stronger
	s.get_node("ModelHolder").scale = Vector3.ONE * SUMMON_SIZE
	u.board.claim(s, spot)
	s.position = u.board.grid_to_world(spot)
	s.begin_combat()
	u.summons.append(s)
	Vfx.puff(s)
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
		var fx := Vfx.color_of(u)
		if not near_side:   # a teleport: gone in a column of shadow, back out of one behind its prey
			Vfx.blink(u, u.global_position, fx, true)
			Vfx.blink(u, u.board.display_pos(spots[0]), fx, false)
		u.leap_to(spots[0])
		u.target = e
		Vfx._later(u, 0.22, func():   # once it has landed
			if is_instance_valid(e):
				Vfx.slash(u, e.global_position, fx.lightened(0.2)))
		hit(u, e, amt(u, "a"))
		return
	Vfx.slash(u, t.global_position, Vfx.color_of(u))
	hit(u, t, amt(u, "a"))

# The board's open hexes from r0 to r1 hexes away from c (effects that cover the ground).
static func _cells_near(u: Unit, c: Vector2i, r0: int, r1: int) -> Array:
	var out := []
	for cell in u.board.tiles:
		var d := Board.hex_distance(c, cell)
		if d >= r0 and d <= r1 and u.board.is_unlocked(cell):
			out.append(cell)
	return out

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
# Heals from an ability, with green motes (regen and omnivamp heal quietly). Returns the HP restored.
static func mend(a: Unit, amount: float) -> float:
	var healed := a.heal(amount)
	if healed > 0.0:
		Vfx.heal(a)
	return healed

# fx = false: the ability draws its own shot, so no generic bolt (a small burst on the target still shows).
static func hit(u: Unit, e: Unit, amount: float, fx := true) -> float:
	if e == null or e.dead:
		return 0.0
	if fx:
		Vfx.impact(u, e)
	else:
		Vfx.burst(e, Vfx._chest(e), Vfx.color_of(u), 5, 0.5)
	var removed := e.take_damage(amount * u.ability_bonus(), u)
	u.damage_dealt += removed
	var steal := u.omnivamp()
	if steal > 0.0:
		u.heal(removed * steal)
	return removed

# One of the Initiate's strikes: an attack with fixed damage on the current target (or the nearest).
static func _strike(u: Unit, amount: float) -> void:
	var e := u.target if is_instance_valid(u.target) and not u.target.dead else u.board.nearest_enemy(u)
	if e != null:
		u._attack(e, amount * u.ability_bonus())

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
