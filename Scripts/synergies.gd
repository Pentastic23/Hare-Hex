# synergies.gd
class_name Synergies extends RefCounted

# stat: hp, dmg, as (attack speed), mana, dr (damage reduction), lifesteal
# scope: "tag" = only units with this tag, "team" = all your units
#
# Tag families (every unit has one origin and one class; a few strong units also carry a unique tag):
#   Origins: Order, Wild, Shadow, Arcane, Undead, Ember, Frost, Fey, Dwarven, Infernal
#   Classes: Warrior, Ranger, Caster, Protector, Rogue, Healer, Summoner, Monk, Alchemist, Bard
#   Unique (threshold 1, held by exactly one unit): Dragonlord, Ascendant, Lich King, Earthshaker (5-cost),
#                                                    Inferno, Crusade (3-cost)
const DEFS := {
	"Order":     {"thresholds": [2, 3], "values": [0.2, 0.4],   "stat": "hp",        "scope": "tag",  "desc": "Order units gain 20% / 40% max HP"},
	"Wild":      {"thresholds": [2, 3], "values": [0.15, 0.3],  "stat": "as",        "scope": "tag",  "desc": "Wild units gain 15% / 30% attack speed"},
	"Shadow":    {"thresholds": [2],    "values": [0.2],        "stat": "lifesteal", "scope": "tag",  "desc": "Shadow units heal for 20% of damage dealt"},
	"Arcane":    {"thresholds": [2],    "values": [0.1],        "stat": "dmg",       "scope": "team", "desc": "Your team deals 10% more damage"},
	"Warrior":   {"thresholds": [2],    "values": [0.2],        "stat": "dr",        "scope": "tag",  "desc": "Warriors take 20% less damage"},
	"Ranger":    {"thresholds": [2],    "values": [0.25],       "stat": "as",        "scope": "tag",  "desc": "Rangers gain 25% attack speed"},
	"Caster":    {"thresholds": [2],    "values": [20.0],       "stat": "mana",      "scope": "tag",  "desc": "Casters start combat with +20 mana"},
	"Protector": {"thresholds": [2],    "values": [0.1],        "stat": "dr",        "scope": "team", "desc": "Your team takes 10% less damage"},
	"Rogue":     {"thresholds": [2],    "values": [0.4],        "stat": "dmg",       "scope": "tag",  "desc": "Rogues deal 40% more damage"},
	# --- more origins ---
	"Undead":    {"thresholds": [2, 4], "values": [0.15, 0.3],  "stat": "lifesteal", "scope": "tag",  "desc": "Undead units heal for 15% / 30% of damage dealt"},
	"Ember":     {"thresholds": [2, 4], "values": [0.2, 0.45],  "stat": "dmg",       "scope": "tag",  "desc": "Ember units deal 20% / 45% more damage"},
	"Frost":     {"thresholds": [2, 4], "values": [0.15, 0.3],  "stat": "dr",        "scope": "tag",  "desc": "Frost units take 15% / 30% less damage"},
	"Fey":       {"thresholds": [2, 4], "values": [0.15, 0.4],  "stat": "as",        "scope": "tag",  "desc": "Fey units gain 15% / 40% attack speed"},
	"Dwarven":   {"thresholds": [2, 4], "values": [0.1, 0.25],  "stat": "hp",        "scope": "team", "desc": "Your team gains 10% / 25% max HP"},
	"Infernal":  {"thresholds": [2, 3], "values": [0.15, 0.4],  "stat": "dmg",       "scope": "tag",  "desc": "Infernal units deal 15% / 40% more damage"},
	# --- more classes ---
	"Healer":    {"thresholds": [2, 4], "values": [0.06, 0.15], "stat": "lifesteal", "scope": "team", "desc": "Your team heals for 6% / 15% of damage dealt"},
	"Summoner":  {"thresholds": [2, 3], "values": [0.15, 0.35], "stat": "hp",        "scope": "tag",  "desc": "Summoners gain 15% / 35% max HP"},
	"Monk":      {"thresholds": [2, 4], "values": [0.2, 0.45],  "stat": "as",        "scope": "tag",  "desc": "Monks gain 20% / 45% attack speed"},
	"Alchemist": {"thresholds": [2, 3], "values": [0.08, 0.2],  "stat": "dmg",       "scope": "team", "desc": "Your team deals 8% / 20% more damage"},
	"Bard":      {"thresholds": [2, 4], "values": [10.0, 25.0], "stat": "mana",      "scope": "team", "desc": "Your team starts combat with +10 / +25 mana"},
	# --- unique synergies: one unit holds each (1/1) ---
	"Dragonlord":  {"thresholds": [1],  "values": [0.15],       "stat": "dmg",       "scope": "team", "desc": "Your team deals 15% more damage"},
	"Ascendant":   {"thresholds": [1],  "values": [0.1],        "stat": "lifesteal", "scope": "team", "desc": "Your team heals for 10% of damage dealt"},
	"Lich King":   {"thresholds": [1],  "values": [0.4],        "stat": "lifesteal", "scope": "tag",  "desc": "The Lich King heals for 40% of damage dealt"},
	"Earthshaker": {"thresholds": [1],  "values": [0.2],        "stat": "hp",        "scope": "team", "desc": "Your team gains 20% max HP"},
	"Inferno":     {"thresholds": [1],  "values": [0.35],       "stat": "dmg",       "scope": "tag",  "desc": "The Pyromancer deals 35% more damage"},
	"Crusade":     {"thresholds": [1],  "values": [0.08],       "stat": "dr",        "scope": "team", "desc": "Your team takes 8% less damage"},
}

static func count(units: Array) -> Dictionary:
	var datas := []
	for x in units:
		var u := x as Unit
		if u != null and u.data != null:
			datas.append(u.data)
	return count_data(datas)

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

# The next threshold not yet reached, or the last one once all are reached (e.g. Order 3 -> 3).
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

static func apply(units: Array):
	for x in units:
		var u := x as Unit
		if u:
			u.clear_bonuses()
	var counts := count(units)
	for tag in counts:
		var n: int = counts[tag]
		var t := active_tier(tag, n)
		if t < 0:
			continue
		var def: Dictionary = DEFS[tag]
		var v: float = def["values"][t]
		for x in units:
			var u := x as Unit
			if u == null:
				continue
			if def["scope"] == "team" or u.data.tags.has(StringName(tag)):
				_add(u, def["stat"], v)

# The bonuses apply() would give `unit` if `units` (its team on the board) fought now, without
# changing any unit. Keys: hp, dmg, as, mana, dr, lifesteal. All zero for a unit that isn't in `units`.
static func preview(unit: Unit, units: Array) -> Dictionary:
	var out := {"hp": 0.0, "dmg": 0.0, "as": 0.0, "mana": 0.0, "dr": 0.0, "lifesteal": 0.0}
	if unit == null or unit.data == null or not units.has(unit):
		return out
	var counts := count(units)
	for tag in counts:
		var t := active_tier(tag, int(counts[tag]))
		if t < 0:
			continue
		var def: Dictionary = DEFS[tag]
		if def["scope"] == "team" or unit.data.tags.has(StringName(tag)):
			out[def["stat"]] += float(def["values"][t])
	return out

static func _add(u: Unit, stat: String, v: float):
	match stat:
		"hp": u.bonus_hp += v
		"dmg": u.bonus_dmg += v
		"as": u.bonus_as += v
		"mana": u.bonus_mana += v
		"dr": u.dmg_reduction += v
		"lifesteal": u.lifesteal += v
