# synergies.gd
class_name Synergies extends RefCounted

# Traits (design and reasoning: docs/synergies-v2.md). 35 traits: 11 origins, 16 classes, 8 uniques.
# Breakpoints, not smooth curves: only the highest tier reached applies, and each tier lists its whole
# effect (tiers don't stack). Top tiers of deep traits have a name and unlock a new mechanic.
#
# Each trait: kind ("origin" / "class" / "unique"), thresholds, desc (one line for tooltips), top (the
# top tier's name, or ""), and tiers: one dict per threshold with
#   "self": effects for units with the trait
#   "team": effects for every unit on the team
#   "tags": {tag: effects} for units with another tag (Lich King's Undead revive)
#   "text": the tier as the player reads it
# Effect keys (fractions unless noted):
#   hp, dmg, as (attack speed), dr (damage reduction), vamp (omnivamp: heal for that share of damage
#   dealt), shield (of max HP, at the start of a fight), regen (of max HP per second), ramp (attack
#   speed per attack) with ramp_max (stacks), crit (every Nth attack deals double), execute (kill an
#   enemy left below this share of max HP), revive (once per fight, at this share of max HP), burn (of
#   the target's max HP per second, 3 s), chill (target's attack speed down, 2 s), dodge (every Nth
#   attack against the unit misses), curse (target takes this much more damage, 3 s), range (tiles),
#   kill_heal (of max HP, healed on a kill).
# Mana effects are deliberately absent: casts do nothing until abilities exist.

const DEFS := {
	# --- origins ---
	"Order": {"kind": "origin", "thresholds": [2, 3, 4, 5], "top": "", "desc": "The kingdom's soldiers grow tougher with every unit.", "tiers": [
		{"self": {"hp": 0.15}, "text": "Order +15% HP"},
		{"self": {"hp": 0.25}, "text": "Order +25% HP"},
		{"self": {"hp": 0.35, "dr": 0.10}, "text": "Order +35% HP, 10% damage reduction"},
		{"self": {"hp": 0.40, "dr": 0.20}, "team": {"hp": 0.10}, "text": "Order +50% HP, 20% damage reduction; team +10% HP"},
	]},
	"Celestial": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Heavenly Host", "desc": "Holy light shields the whole team.", "tiers": [
		{"team": {"shield": 0.08}, "text": "team 8% shield"},
		{"team": {"shield": 0.15}, "self": {"hp": 0.20}, "text": "team 15% shield; Celestial +20% HP"},
		{"team": {"shield": 0.25, "regen": 0.01}, "self": {"hp": 0.40}, "text": "Heavenly Host: team 25% shield and 1% regen per second; Celestial +40% HP"},
	]},
	"Wild": {"kind": "origin", "thresholds": [3, 4, 5, 7], "top": "Stampede", "desc": "Wild units attack faster and faster.", "tiers": [
		{"self": {"as": 0.15}, "text": "Wild +15% attack speed"},
		{"self": {"as": 0.25}, "text": "Wild +25% attack speed"},
		{"self": {"as": 0.35, "ramp": 0.03, "ramp_max": 10}, "text": "Wild +35% attack speed, +3% more per attack (max 10)"},
		{"team": {"as": 0.40}, "self": {"ramp": 0.05, "ramp_max": 15}, "text": "Stampede: team +40% attack speed; Wild +5% more per attack (max 15)"},
	]},
	"Shadow": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Nightfall", "desc": "Shadow units hit hard and finish off the wounded.", "tiers": [
		{"self": {"dmg": 0.20}, "text": "Shadow +20% damage"},
		{"self": {"dmg": 0.35, "execute": 0.10}, "text": "Shadow +35% damage, execute below 10%"},
		{"self": {"dmg": 0.55, "execute": 0.20}, "text": "Nightfall: Shadow +55% damage, execute below 20%"},
	]},
	"Arcane": {"kind": "origin", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Arcane power raises the whole team's damage.", "tiers": [
		{"team": {"dmg": 0.05}, "text": "team +5% damage"},
		{"team": {"dmg": 0.10}, "text": "team +10% damage"},
		{"team": {"dmg": 0.15}, "text": "team +15% damage"},
		{"team": {"dmg": 0.25}, "text": "team +25% damage"},
	]},
	"Undead": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Undying", "desc": "The Undead refuse to stay down.", "tiers": [
		{"self": {"hp": 0.15}, "text": "Undead +15% HP"},
		{"self": {"hp": 0.15, "revive": 0.30}, "text": "Undead +15% HP, revive once at 30% HP"},
		{"self": {"hp": 0.15, "revive": 0.60}, "team": {"hp": 0.15}, "text": "Undying: Undead revive once at 60% HP; team +15% HP"},
	]},
	"Ember": {"kind": "origin", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Ember attacks set their targets burning.", "tiers": [
		{"self": {"burn": 0.02}, "text": "Ember attacks burn 2% of max HP per second"},
		{"self": {"burn": 0.03}, "text": "Ember attacks burn 3% per second"},
		{"self": {"burn": 0.05}, "text": "Ember attacks burn 5% per second"},
		{"self": {"burn": 0.08, "dmg": 0.20}, "text": "Ember attacks burn 8% per second; Ember +20% damage"},
	]},
	"Frost": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Deep Freeze", "desc": "Frost attacks slow the enemy down.", "tiers": [
		{"self": {"chill": 0.15}, "text": "Frost attacks chill 15%"},
		{"self": {"chill": 0.30, "dr": 0.15}, "text": "Frost attacks chill 30%; Frost 15% damage reduction"},
		{"self": {"chill": 0.50, "dr": 0.30}, "text": "Deep Freeze: Frost attacks chill 50%; Frost 30% damage reduction"},
	]},
	"Fey": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Glamour", "desc": "The Fey dance through their attacks.", "tiers": [
		{"self": {"as": 0.15}, "text": "Fey +15% attack speed"},
		{"self": {"as": 0.30, "dmg": 0.15}, "text": "Fey +30% attack speed, +15% damage"},
		{"self": {"as": 0.35, "dmg": 0.30}, "team": {"as": 0.15}, "text": "Glamour: Fey +50% attack speed, +30% damage; team +15% attack speed"},
	]},
	"Dwarven": {"kind": "origin", "thresholds": [3, 4, 5, 7], "top": "Mountain's Heart", "desc": "Dwarven grit toughens the whole team.", "tiers": [
		{"team": {"hp": 0.08}, "text": "team +8% HP"},
		{"team": {"hp": 0.12}, "self": {"shield": 0.15}, "text": "team +12% HP; Dwarven 15% shield"},
		{"team": {"hp": 0.18}, "self": {"shield": 0.25}, "text": "team +18% HP; Dwarven 25% shield"},
		{"team": {"hp": 0.35, "shield": 0.25}, "text": "Mountain's Heart: team +35% HP and a 25% shield"},
	]},
	"Infernal": {"kind": "origin", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Infernal fury, more with every demon.", "tiers": [
		{"self": {"dmg": 0.12}, "text": "Infernal +12% damage"},
		{"self": {"dmg": 0.22}, "text": "Infernal +22% damage"},
		{"self": {"dmg": 0.35}, "text": "Infernal +35% damage"},
		{"self": {"dmg": 0.60}, "text": "Infernal +60% damage"},
	]},
	# --- classes ---
	"Warrior": {"kind": "class", "thresholds": [3, 5, 7, 9], "top": "Warband", "desc": "Warriors hit harder and drink from their wounds.", "tiers": [
		{"self": {"dmg": 0.15}, "text": "Warriors +15% damage"},
		{"self": {"dmg": 0.25, "vamp": 0.10}, "text": "Warriors +25% damage, 10% omnivamp"},
		{"self": {"dmg": 0.40, "vamp": 0.20}, "text": "Warriors +40% damage, 20% omnivamp"},
		{"self": {"dmg": 0.40, "vamp": 0.30}, "team": {"dmg": 0.20}, "text": "Warband: Warriors +60% damage, 30% omnivamp; team +20% damage"},
	]},
	"Caster": {"kind": "class", "thresholds": [3, 5, 7, 9], "top": "Archmagi", "desc": "Casters channel raw power into every attack.", "tiers": [
		{"self": {"dmg": 0.15}, "text": "Casters +15% damage"},
		{"self": {"dmg": 0.30}, "text": "Casters +30% damage"},
		{"self": {"dmg": 0.40}, "team": {"dmg": 0.10}, "text": "Casters +50% damage; team +10% damage"},
		{"self": {"dmg": 0.70, "crit": 3}, "team": {"dmg": 0.20}, "text": "Archmagi: Casters +90% damage, every 3rd attack crits; team +20% damage"},
	]},
	"Protector": {"kind": "class", "thresholds": [2, 4, 6, 8], "top": "Bulwark", "desc": "Protectors raise shields and steady the line.", "tiers": [
		{"self": {"shield": 0.20}, "text": "Protectors 20% shield"},
		{"self": {"shield": 0.35}, "team": {"dr": 0.08}, "text": "Protectors 35% shield; team 8% damage reduction"},
		{"self": {"shield": 0.55}, "team": {"dr": 0.15}, "text": "Protectors 55% shield; team 15% damage reduction"},
		{"self": {"shield": 0.80}, "team": {"dr": 0.25}, "text": "Bulwark: Protectors 80% shield; team 25% damage reduction"},
	]},
	"Ranger": {"kind": "class", "thresholds": [2, 4, 6], "top": "Deadeye", "desc": "Rangers shoot faster and farther.", "tiers": [
		{"self": {"as": 0.20}, "text": "Rangers +20% attack speed"},
		{"self": {"as": 0.40, "range": 1}, "text": "Rangers +40% attack speed, +1 range"},
		{"self": {"as": 0.70, "range": 1, "crit": 3}, "text": "Deadeye: Rangers +70% attack speed, +1 range, every 3rd attack crits"},
	]},
	"Rogue": {"kind": "class", "thresholds": [2, 4, 6], "top": "Cutthroat", "desc": "Rogues land critical strikes.", "tiers": [
		{"self": {"crit": 4}, "text": "every 4th Rogue attack crits"},
		{"self": {"crit": 3, "dmg": 0.15}, "text": "every 3rd Rogue attack crits; Rogues +15% damage"},
		{"self": {"crit": 2, "dmg": 0.30}, "text": "Cutthroat: every 2nd Rogue attack crits; Rogues +30% damage"},
	]},
	"Brute": {"kind": "class", "thresholds": [2, 4, 6], "top": "Juggernaut", "desc": "Brutes are huge and hit like it.", "tiers": [
		{"self": {"hp": 0.20}, "text": "Brutes +20% HP"},
		{"self": {"hp": 0.40, "dmg": 0.15}, "text": "Brutes +40% HP, +15% damage"},
		{"self": {"hp": 0.75, "dmg": 0.35}, "text": "Juggernaut: Brutes +75% HP, +35% damage"},
	]},
	"Warlock": {"kind": "class", "thresholds": [2, 4, 6], "top": "Soul Pact", "desc": "Warlocks curse their targets to take more damage.", "tiers": [
		{"self": {"curse": 0.08}, "text": "Warlock attacks curse: the target takes 8% more damage"},
		{"self": {"curse": 0.15}, "text": "Warlock curse 15%"},
		{"self": {"curse": 0.25, "vamp": 0.20}, "text": "Soul Pact: Warlock curse 25%; Warlocks 20% omnivamp"},
	]},
	"Knight": {"kind": "class", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Knights' armour gets heavier with every knight.", "tiers": [
		{"self": {"dr": 0.15}, "text": "Knights 15% damage reduction"},
		{"self": {"dr": 0.20, "dmg": 0.10}, "text": "Knights 20% damage reduction, +10% damage"},
		{"self": {"dr": 0.30, "dmg": 0.20}, "text": "Knights 30% damage reduction, +20% damage"},
		{"self": {"dr": 0.30, "dmg": 0.30}, "team": {"dr": 0.10}, "text": "Knights 40% damage reduction, +30% damage; team 10% damage reduction"},
	]},
	"Monk": {"kind": "class", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Monks strike faster with every monk.", "tiers": [
		{"self": {"as": 0.20}, "text": "Monks +20% attack speed"},
		{"self": {"as": 0.30}, "text": "Monks +30% attack speed"},
		{"self": {"as": 0.45, "dr": 0.10}, "text": "Monks +45% attack speed, 10% damage reduction"},
		{"self": {"as": 0.60, "dr": 0.20}, "text": "Monks +60% attack speed, 20% damage reduction"},
	]},
	"Trickster": {"kind": "class", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Tricksters are hard to hit.", "tiers": [
		{"self": {"dodge": 5}, "text": "every 5th attack against Tricksters misses"},
		{"self": {"dodge": 4}, "text": "every 4th attack against Tricksters misses"},
		{"self": {"dodge": 3}, "text": "every 3rd attack against Tricksters misses"},
		{"self": {"dodge": 2}, "team": {"dodge": 5}, "text": "every 2nd attack against Tricksters misses; the team dodges every 5th"},
	]},
	"Healer": {"kind": "class", "thresholds": [2, 3, 4], "top": "", "desc": "Healers mend the whole team during the fight.", "tiers": [
		{"team": {"regen": 0.01}, "text": "team regen 1% of max HP per second"},
		{"team": {"regen": 0.02}, "text": "team regen 2% per second"},
		{"team": {"regen": 0.035}, "text": "team regen 3.5% per second"},
	]},
	"Bard": {"kind": "class", "thresholds": [2, 3, 4], "top": "", "desc": "Bards' songs speed up the whole team.", "tiers": [
		{"team": {"as": 0.08}, "text": "team +8% attack speed"},
		{"team": {"as": 0.15}, "text": "team +15% attack speed"},
		{"team": {"as": 0.25}, "text": "team +25% attack speed"},
	]},
	"Summoner": {"kind": "class", "thresholds": [2, 3, 4], "top": "", "desc": "Summoners draw strength from what they call.", "tiers": [
		{"self": {"hp": 0.20}, "text": "Summoners +20% HP"},
		{"self": {"hp": 0.40}, "text": "Summoners +40% HP"},
		{"self": {"hp": 0.65, "dmg": 0.20}, "text": "Summoners +65% HP, +20% damage"},
	]},
	"Elementalist": {"kind": "class", "thresholds": [2, 3, 4], "top": "", "desc": "Elementalists burn and freeze what they hit.", "tiers": [
		{"self": {"burn": 0.03, "chill": 0.15}, "text": "Elementalist attacks burn 3% per second and chill 15%"},
		{"self": {"burn": 0.05, "chill": 0.25}, "text": "Elementalist attacks burn 5% per second and chill 25%"},
		{"self": {"burn": 0.08, "chill": 0.40}, "text": "Elementalist attacks burn 8% per second and chill 40%"},
	]},
	"Duelist": {"kind": "class", "thresholds": [2, 3], "top": "", "desc": "Duelists speed up with every strike.", "tiers": [
		{"self": {"ramp": 0.04, "ramp_max": 12}, "text": "Duelists +4% attack speed per attack (max 12)"},
		{"self": {"ramp": 0.07, "ramp_max": 12}, "text": "Duelists +7% attack speed per attack (max 12)"},
	]},
	"Alchemist": {"kind": "class", "thresholds": [2, 3], "top": "", "desc": "Alchemists' brews strengthen the team.", "tiers": [
		{"team": {"hp": 0.06, "dmg": 0.06}, "text": "team +6% HP and damage"},
		{"team": {"hp": 0.15, "dmg": 0.15}, "text": "team +15% HP and damage"},
	]},
	# --- unique (1/1): one unit holds each ---
	"Dragonlord": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Dragon's presence emboldens the team.", "tiers": [
		{"team": {"dmg": 0.15}, "text": "team +15% damage"},
	]},
	"Ascendant": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Seraph's grace sustains the team.", "tiers": [
		{"team": {"vamp": 0.10, "regen": 0.01}, "text": "team 10% omnivamp and 1% regen per second"},
	]},
	"Lich King": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Deathlord commands the dead.", "tiers": [
		{"self": {"vamp": 0.40}, "tags": {"Undead": {"revive": 0.30}}, "text": "Deathlord 40% omnivamp; every Undead revives once at 30% HP"},
	]},
	"Earthshaker": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Titan steadies the ground under the team.", "tiers": [
		{"team": {"hp": 0.20, "shield": 0.10}, "text": "team +20% HP and a 10% shield"},
	]},
	"Rebirth": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Phoenix rises again.", "tiers": [
		{"self": {"revive": 0.60}, "text": "Phoenix revives once at 60% HP"},
	]},
	"Soulreaper": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Reaper harvests the weak.", "tiers": [
		{"self": {"execute": 0.20, "kill_heal": 0.30}, "text": "Reaper executes below 20% and heals 30% of max HP on each kill"},
	]},
	"Inferno": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Pyromancer's fire burns hotter.", "tiers": [
		{"self": {"dmg": 0.35, "burn": 0.05}, "text": "Pyromancer +35% damage, attacks burn 5% per second"},
	]},
	"Crusade": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Paladin's crusade hardens the team.", "tiers": [
		{"team": {"dr": 0.10}, "text": "team 10% damage reduction"},
	]},
}

# How effect keys combine when several traits give the same one: most add up; these take the best.
const TAKE_MAX := ["execute", "revive", "ramp", "ramp_max"]
const TAKE_EVERY := ["crit", "dodge"]   # "every Nth": the smallest N wins

static func count(units: Array) -> Dictionary:
	var datas := []
	for x in units:
		var u := x as Unit
		if u != null and u.data != null:
			datas.append(u.data)
	var counts := count_data(datas)
	# Synergy benders (Twin Sigil / Twin Crest): the holder counts once more for its origin / first
	# class. Once per unit name, like the counting itself; unique traits are never doubled.
	var doubled := {}
	for x in units:
		var u := x as Unit
		if u == null or u.data == null:
			continue
		for it in u.items:
			if it.kind != &"bender":
				continue
			var tag := bent_tag(u.data, it.counts_twice)
			var k := "%s|%s" % [u.data.display_name, tag]
			if tag != "" and not doubled.has(k):
				doubled[k] = true
				counts[tag] = int(counts.get(tag, 0)) + 1
	return counts

# The tag a bender doubles on a unit: its origin, or its first class ("" if none).
static func bent_tag(d: UnitData, part: StringName) -> String:
	var want := "origin" if part == &"origin" else "class"
	for t in d.tags:
		var key := String(t)
		if DEFS.has(key) and DEFS[key]["kind"] == want:
			return key
	return ""

# Same counting for UnitData (the team planner counts a planned team, not units on the board).
static func count_data(datas: Array) -> Dictionary:
	var seen := {}
	var counts := {}
	for x in datas:
		var d := x as UnitData
		if d == null or seen.has(d.display_name):
			continue
		seen[d.display_name] = true
		for tag in d.tags:
			var key := String(tag)
			counts[key] = int(counts.get(key, 0)) + 1
	return counts

# The next threshold not yet reached, or the last one once all are reached (e.g. Order 5 -> 5).
static func next_threshold(tag: String, n: int) -> int:
	var thresholds: Array = DEFS[tag]["thresholds"]
	for th in thresholds:
		if n < int(th):
			return int(th)
	return int(thresholds.back())

static func active_tier(tag: String, n: int) -> int:
	if not DEFS.has(tag):
		return -1
	var thresholds: Array = DEFS[tag]["thresholds"]
	var result := -1
	for i in thresholds.size():
		if n >= int(thresholds[i]):
			result = i
	return result

# What one tier does, as the player reads it ("Casters +30% damage").
static func tier_text(tag: String, tier: int) -> String:
	if not DEFS.has(tag):
		return ""
	var tiers: Array = DEFS[tag]["tiers"]
	return str(tiers[clampi(tier, 0, tiers.size() - 1)]["text"])

# Tooltip for a trait: its line, then every tier ("3: Casters +15% damage"), the reached one marked.
static func tooltip(tag: String, n := -1) -> String:
	if not DEFS.has(tag):
		return ""
	var def: Dictionary = DEFS[tag]
	var lines: PackedStringArray = [str(def["desc"])]
	var reached := active_tier(tag, n) if n >= 0 else -1
	var thresholds: Array = def["thresholds"]
	for i in thresholds.size():
		lines.append("%s%d: %s" % ["> " if i == reached else "", int(thresholds[i]), tier_text(tag, i)])
	return "\n".join(lines)

# Every effect each unit gets from `units` (its team on the board), keyed by unit: {unit: {key: value}}.
static func effects_for(units: Array) -> Dictionary:
	var out := {}
	for x in units:
		if x is Unit:
			out[x] = {}
	var counts := count(units)
	for tag in counts:
		var t := active_tier(tag, int(counts[tag]))
		if t < 0:
			continue
		var tier: Dictionary = DEFS[tag]["tiers"][t]
		for u in out:
			var unit := u as Unit
			if tier.has("team"):
				_merge(out[u], tier["team"])
			if tier.has("self") and unit.data.tags.has(StringName(tag)):
				_merge(out[u], tier["self"])
			if tier.has("tags"):
				for other in tier["tags"]:
					if unit.data.tags.has(StringName(other)):
						_merge(out[u], tier["tags"][other])
	# Items: their own effects and resonances (items v2), on top of the traits.
	for u in out:
		_merge(out[u], Resonance.unit_effects((u as Unit).items))
	return out

static func _merge(into: Dictionary, fx: Dictionary) -> void:
	for k in fx:
		var v: float = float(fx[k])
		if not into.has(k):
			into[k] = v
		elif TAKE_MAX.has(k):
			into[k] = maxf(into[k], v)
		elif TAKE_EVERY.has(k):
			into[k] = minf(into[k], v)
		else:
			into[k] += v

# Clears every unit's synergy bonuses and applies what `units` (one team) earns now.
static func apply(units: Array):
	for x in units:
		var u := x as Unit
		if u:
			u.clear_bonuses()
	var fx := effects_for(units)
	for u in fx:
		(u as Unit).apply_synergy(fx[u])

# The bonuses apply() would give `unit` if `units` (its team on the board) fought now, without
# changing any unit. Effect keys as in DEFS; missing keys are 0. Empty for a unit that isn't in `units`.
static func preview(unit: Unit, units: Array) -> Dictionary:
	if unit == null or unit.data == null or not units.has(unit):
		return {}
	return effects_for(units).get(unit, {})
