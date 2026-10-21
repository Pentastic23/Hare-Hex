# synergies.gd
class_name Synergies extends RefCounted

# stat: hp, dmg, as (attack speed), mana, dr (damage reduction), lifesteal
# scope: "tag" = only units with this tag, "team" = all your units
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
}

static func count(units: Array) -> Dictionary:
	var seen := {}
	var counts := {}
	for x in units:
		var u := x as Unit
		if u == null or u.data == null:
			continue
		if seen.has(u.data.display_name):
			continue
		seen[u.data.display_name] = true
		for tag in u.data.tags:
			var key := String(tag)
			counts[key] = int(counts.get(key, 0)) + 1
	return counts

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

static func _add(u: Unit, stat: String, v: float):
	match stat:
		"hp": u.bonus_hp += v
		"dmg": u.bonus_dmg += v
		"as": u.bonus_as += v
		"mana": u.bonus_mana += v
		"dr": u.dmg_reduction += v
		"lifesteal": u.lifesteal += v
