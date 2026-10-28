# synergies.gd
class_name Synergies extends RefCounted

# Traits (design and reasoning: docs/synergies-v2.md; the stats they use since v3: docs/stats-and-items-v3.md).
# 35 traits: 11 origins, 16 classes, 8 uniques. Breakpoints, not smooth curves: only the highest tier
# reached applies, and each tier lists its whole effect (tiers don't stack). Top tiers of deep traits
# have a name.
#
# No two traits give the same bonus: every (scope, effect key) pair below belongs to one trait only
# (Brute has holder HP, Dwarven team HP; tools/roster_checks checks it).
#
# Each trait: kind ("origin" / "class" / "unique"), thresholds, desc (one line for tooltips), top (the
# top tier's name, or ""), and tiers: one dict per threshold with
#   "self": effects for units with the trait
#   "team": effects for every unit on the team
#   "tags": {tag: effects} for units with another tag (Lich King's Undead revive)
#   "text": the tier as the player reads it
# Effect keys (fractions unless noted):
#   hp, ad (attack power), ap (ability power: ability damage, heals, shields), as (attack speed),
#   armor, mr (magic resist) and mit (mitigation: flat damage off every hit) as flat numbers,
#   vamp (omnivamp: heal for that share of damage dealt), shield (of max HP, at the start of a fight),
#   regen (of max HP per second), ramp (attack speed per attack) with ramp_max (stacks), crit (every
#   Nth attack deals double), execute (kill an enemy left below this share of max HP), revive (once per
#   fight, at this share of max HP), burn (of the target's max HP per second, 3 s), chill (target's
#   attack speed down, 2 s), dodge (every Nth attack against the unit misses), curse (target takes this
#   much more damage, 3 s), sunder / shred (target's armour / magic resist down by this much, 3 s),
#   range (tiles), kill_heal (of max HP, healed on a kill), summon (what the unit summons gets this much
#   more HP and damage).
# No trait uses mana (a design decision): mana feeds the unit abilities.

const DEFS := {
	# --- origins ---
	"Order": {"kind": "origin", "thresholds": [2, 3, 4, 5], "top": "", "desc": "The kingdom's drilled soldiers shrug off every blow.", "tiers": [
		{"self": {"mit": 10.0}, "text": "Order 10 mitigation"},
		{"self": {"mit": 16.0}, "text": "Order 16 mitigation"},
		{"self": {"mit": 24.0}, "text": "Order 24 mitigation"},
		{"self": {"mit": 35.0}, "text": "Order 35 mitigation"},
	]},
	"Celestial": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Heavenly Host", "desc": "Holy light shields the whole team.", "tiers": [
		{"team": {"shield": 0.10}, "text": "team 10% shield"},
		{"team": {"shield": 0.18}, "text": "team 18% shield"},
		{"team": {"shield": 0.32}, "text": "Heavenly Host: team 32% shield"},
	]},
	"Wild": {"kind": "origin", "thresholds": [3, 4, 5, 7], "top": "Stampede", "desc": "Wild claws tear through armour.", "tiers": [
		{"self": {"sunder": 15.0}, "text": "Wild attacks sunder 15 armour"},
		{"self": {"sunder": 25.0}, "text": "Wild attacks sunder 25 armour"},
		{"self": {"sunder": 35.0}, "text": "Wild attacks sunder 35 armour"},
		{"self": {"sunder": 50.0}, "team": {"sunder": 20.0}, "text": "Stampede: Wild attacks sunder 50 armour; the team's attacks sunder 20"},
	]},
	"Shadow": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Nightfall", "desc": "Shadow units finish off the wounded.", "tiers": [
		{"self": {"execute": 0.10}, "text": "Shadow execute below 10%"},
		{"self": {"execute": 0.18}, "text": "Shadow execute below 18%"},
		{"self": {"execute": 0.28}, "text": "Nightfall: Shadow execute below 28%"},
	]},
	"Arcane": {"kind": "origin", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Arcane power raises the whole team's ability power.", "tiers": [
		{"team": {"ap": 0.08}, "text": "team +8% ability power"},
		{"team": {"ap": 0.14}, "text": "team +14% ability power"},
		{"team": {"ap": 0.20}, "text": "team +20% ability power"},
		{"team": {"ap": 0.30}, "text": "team +30% ability power"},
	]},
	"Undead": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Undying", "desc": "The Undead refuse to stay down.", "tiers": [
		{"self": {"revive": 0.25}, "text": "Undead revive once at 25% HP"},
		{"self": {"revive": 0.45}, "text": "Undead revive once at 45% HP"},
		{"self": {"revive": 0.70}, "text": "Undying: Undead revive once at 70% HP"},
	]},
	"Ember": {"kind": "origin", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Ember attacks set their targets burning.", "tiers": [
		{"self": {"burn": 0.02}, "text": "Ember attacks burn 2% of max HP per second"},
		{"self": {"burn": 0.035}, "text": "Ember attacks burn 3.5% per second"},
		{"self": {"burn": 0.055}, "text": "Ember attacks burn 5.5% per second"},
		{"self": {"burn": 0.09}, "text": "Ember attacks burn 9% per second"},
	]},
	"Frost": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Deep Freeze", "desc": "Frost attacks slow the enemy down.", "tiers": [
		{"self": {"chill": 0.15}, "text": "Frost attacks chill 15%"},
		{"self": {"chill": 0.30}, "text": "Frost attacks chill 30%"},
		{"self": {"chill": 0.50}, "team": {"chill": 0.15}, "text": "Deep Freeze: Frost attacks chill 50%; the team's attacks chill 15%"},
	]},
	"Fey": {"kind": "origin", "thresholds": [2, 4, 6], "top": "Glamour", "desc": "The Fey dance faster with every strike.", "tiers": [
		{"self": {"ramp": 0.04, "ramp_max": 10}, "text": "Fey +4% attack speed per attack (max 10)"},
		{"self": {"ramp": 0.06, "ramp_max": 12}, "text": "Fey +6% attack speed per attack (max 12)"},
		{"self": {"ramp": 0.09, "ramp_max": 15}, "text": "Glamour: Fey +9% attack speed per attack (max 15)"},
	]},
	"Dwarven": {"kind": "origin", "thresholds": [3, 4, 5, 7], "top": "Mountain's Heart", "desc": "Dwarven grit toughens the whole team.", "tiers": [
		{"team": {"hp": 0.08}, "text": "team +8% HP"},
		{"team": {"hp": 0.13}, "text": "team +13% HP"},
		{"team": {"hp": 0.20}, "text": "team +20% HP"},
		{"team": {"hp": 0.38}, "text": "Mountain's Heart: team +38% HP"},
	]},
	"Infernal": {"kind": "origin", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Infernal fury, more with every demon.", "tiers": [
		{"self": {"ad": 0.15}, "text": "Infernal +15% attack power"},
		{"self": {"ad": 0.25}, "text": "Infernal +25% attack power"},
		{"self": {"ad": 0.40}, "text": "Infernal +40% attack power"},
		{"self": {"ad": 0.65}, "text": "Infernal +65% attack power"},
	]},
	# --- classes ---
	"Warrior": {"kind": "class", "thresholds": [3, 5, 7, 9], "top": "Warband", "desc": "Warriors drink from their wounds.", "tiers": [
		{"self": {"vamp": 0.12}, "text": "Warriors 12% omnivamp"},
		{"self": {"vamp": 0.20}, "text": "Warriors 20% omnivamp"},
		{"self": {"vamp": 0.30}, "text": "Warriors 30% omnivamp"},
		{"self": {"vamp": 0.45}, "text": "Warband: Warriors 45% omnivamp"},
	]},
	"Caster": {"kind": "class", "thresholds": [3, 5, 7, 9], "top": "Archmagi", "desc": "Casters channel raw power into their spells.", "tiers": [
		{"self": {"ap": 0.20}, "text": "Casters +20% ability power"},
		{"self": {"ap": 0.40}, "text": "Casters +40% ability power"},
		{"self": {"ap": 0.65}, "text": "Casters +65% ability power"},
		{"self": {"ap": 1.00}, "text": "Archmagi: Casters +100% ability power"},
	]},
	"Protector": {"kind": "class", "thresholds": [2, 4, 6, 8], "top": "Bulwark", "desc": "Protectors raise shields and steady the line.", "tiers": [
		{"self": {"shield": 0.20}, "text": "Protectors 20% shield"},
		{"self": {"shield": 0.35}, "team": {"mit": 5.0}, "text": "Protectors 35% shield; team 5 mitigation"},
		{"self": {"shield": 0.55}, "team": {"mit": 10.0}, "text": "Protectors 55% shield; team 10 mitigation"},
		{"self": {"shield": 0.80}, "team": {"mit": 16.0}, "text": "Bulwark: Protectors 80% shield; team 16 mitigation"},
	]},
	"Ranger": {"kind": "class", "thresholds": [2, 4, 6], "top": "Deadeye", "desc": "Rangers shoot faster and farther.", "tiers": [
		{"self": {"as": 0.20}, "text": "Rangers +20% attack speed"},
		{"self": {"as": 0.40, "range": 1}, "text": "Rangers +40% attack speed, +1 range"},
		{"self": {"as": 0.80, "range": 1}, "text": "Deadeye: Rangers +80% attack speed, +1 range"},
	]},
	"Rogue": {"kind": "class", "thresholds": [2, 4, 6], "top": "Cutthroat", "desc": "Rogues land critical strikes.", "tiers": [
		{"self": {"crit": 4}, "text": "every 4th Rogue attack crits"},
		{"self": {"crit": 3}, "text": "every 3rd Rogue attack crits"},
		{"self": {"crit": 2}, "text": "Cutthroat: every 2nd Rogue attack crits"},
	]},
	"Brute": {"kind": "class", "thresholds": [2, 4, 6], "top": "Juggernaut", "desc": "Brutes are huge.", "tiers": [
		{"self": {"hp": 0.25}, "text": "Brutes +25% HP"},
		{"self": {"hp": 0.50}, "text": "Brutes +50% HP"},
		{"self": {"hp": 0.90}, "text": "Juggernaut: Brutes +90% HP"},
	]},
	"Warlock": {"kind": "class", "thresholds": [2, 4, 6], "top": "Soul Pact", "desc": "Warlocks curse their targets to take more damage.", "tiers": [
		{"self": {"curse": 0.10}, "text": "Warlock attacks curse: the target takes 10% more damage"},
		{"self": {"curse": 0.18}, "text": "Warlock curse 18%"},
		{"self": {"curse": 0.30}, "text": "Soul Pact: Warlock curse 30%"},
	]},
	"Knight": {"kind": "class", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Knights' armour gets heavier with every knight.", "tiers": [
		{"self": {"armor": 20.0}, "text": "Knights +20 armour"},
		{"self": {"armor": 30.0}, "text": "Knights +30 armour"},
		{"self": {"armor": 45.0}, "text": "Knights +45 armour"},
		{"self": {"armor": 70.0}, "text": "Knights +70 armour"},
	]},
	"Monk": {"kind": "class", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Monks' calm turns spells aside.", "tiers": [
		{"self": {"mr": 20.0}, "text": "Monks +20 magic resist"},
		{"self": {"mr": 30.0}, "text": "Monks +30 magic resist"},
		{"self": {"mr": 45.0}, "text": "Monks +45 magic resist"},
		{"self": {"mr": 70.0}, "text": "Monks +70 magic resist"},
	]},
	"Trickster": {"kind": "class", "thresholds": [2, 3, 4, 5], "top": "", "desc": "Tricksters are hard to hit.", "tiers": [
		{"self": {"dodge": 5}, "text": "every 5th attack against Tricksters misses"},
		{"self": {"dodge": 4}, "text": "every 4th attack against Tricksters misses"},
		{"self": {"dodge": 3}, "text": "every 3rd attack against Tricksters misses"},
		{"self": {"dodge": 2}, "text": "every 2nd attack against Tricksters misses"},
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
	"Summoner": {"kind": "class", "thresholds": [2, 3, 4], "top": "", "desc": "What Summoners call comes out stronger.", "tiers": [
		{"self": {"summon": 0.25}, "text": "Summoners' summons +25% HP and damage"},
		{"self": {"summon": 0.50}, "text": "Summoners' summons +50% HP and damage"},
		{"self": {"summon": 0.90}, "text": "Summoners' summons +90% HP and damage"},
	]},
	"Elementalist": {"kind": "class", "thresholds": [2, 3, 4], "top": "", "desc": "Elementalists strip away magic resist.", "tiers": [
		{"self": {"shred": 15.0}, "text": "Elementalist attacks shred 15 magic resist"},
		{"self": {"shred": 25.0}, "text": "Elementalist attacks shred 25 magic resist"},
		{"self": {"shred": 40.0}, "text": "Elementalist attacks shred 40 magic resist"},
	]},
	"Duelist": {"kind": "class", "thresholds": [2, 3], "top": "", "desc": "Duelists recover with every duel they win.", "tiers": [
		{"self": {"kill_heal": 0.20}, "text": "Duelists heal 20% of max HP on each kill"},
		{"self": {"kill_heal": 0.35}, "text": "Duelists heal 35% of max HP on each kill"},
	]},
	"Alchemist": {"kind": "class", "thresholds": [2, 3], "top": "", "desc": "Alchemists' tonics let the team drink from its wounds.", "tiers": [
		{"team": {"vamp": 0.06}, "text": "team 6% omnivamp"},
		{"team": {"vamp": 0.12}, "text": "team 12% omnivamp"},
	]},
	# --- unique (1/1): one unit holds each ---
	"Dragonlord": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Dragon's presence emboldens the team.", "tiers": [
		{"team": {"ad": 0.15}, "text": "team +15% attack power"},
	]},
	"Ascendant": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Seraph's grace wards the team.", "tiers": [
		{"team": {"mr": 20.0}, "text": "team +20 magic resist"},
	]},
	"Lich King": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Deathlord commands the dead.", "tiers": [
		{"tags": {"Undead": {"revive": 0.30}}, "text": "every Undead revives once at 30% HP"},
	]},
	"Earthshaker": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Titan steadies the ground under the team.", "tiers": [
		{"team": {"armor": 20.0}, "text": "team +20 armour"},
	]},
	"Rebirth": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Phoenix's flames mend it.", "tiers": [
		{"self": {"regen": 0.03}, "text": "Phoenix regens 3% of max HP per second"},
	]},
	"Soulreaper": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Reaper teaches the team to harvest the weak.", "tiers": [
		{"team": {"execute": 0.10}, "text": "team executes below 10%"},
	]},
	"Inferno": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Pyromancer sets the team's weapons alight.", "tiers": [
		{"team": {"burn": 0.02}, "text": "team attacks burn 2% of max HP per second"},
	]},
	"Crusade": {"kind": "unique", "thresholds": [1], "top": "", "desc": "The Paladin's crusade guides every blow.", "tiers": [
		{"team": {"crit": 6}, "text": "every 6th attack of the team crits"},
	]},
}

# How effect keys combine when several traits give the same one: most add up; these take the best.
const TAKE_MAX := ["execute", "revive", "ramp", "ramp_max", "sunder", "shred"]
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
# `extra`: effects every unit of the team gets on top (a king's relics, decrees and prophecies; KingPowers).
static func apply(units: Array, extra := {}):
	for x in units:
		var u := x as Unit
		if u:
			u.clear_bonuses()
	var fx := effects_for(units)
	for u in fx:
		if not extra.is_empty():
			_merge(fx[u], extra)
		(u as Unit).apply_synergy(fx[u])

# The bonuses apply() would give `unit` if `units` (its team on the board) fought now, without
# changing any unit. Effect keys as in DEFS; missing keys are 0. Empty for a unit that isn't in `units`.
static func preview(unit: Unit, units: Array) -> Dictionary:
	if unit == null or unit.data == null or not units.has(unit):
		return {}
	return effects_for(units).get(unit, {})
