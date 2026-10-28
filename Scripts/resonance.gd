# resonance.gd
class_name Resonance extends RefCounted

# Item resonance (items v2, docs/items-v2.md). Every basic item has an element. Two items with
# different elements on one unit switch on the resonance for that pair; three different elements
# add Prism. A unit with three items can have up to three pair resonances. The Resonance Crystal
# doubles them. Effects use the synergy effect keys (Synergies.DEFS) and are merged with the unit's
# synergy effects at the start of a fight (Synergies.effects_for), so they are just as deterministic.

const ELEMENTS: Array[StringName] = [&"Might", &"Vigor", &"Swift", &"Guard", &"Blood", &"Arcane"]
const ELEMENT_COLORS := {
	&"Might": Color("e8913a"), &"Vigor": Color("d65a4f"), &"Swift": Color("6fcf6a"),
	&"Guard": Color("a9aec4"), &"Blood": Color("b0407a"), &"Arcane": Color("6c9cf0"),
}

# Key: the two elements in ELEMENTS order, joined with "+".
const PAIRS := {
	"Might+Vigor": {"name": "Juggernaut", "effects": {"hp": 0.10, "ad": 0.10}, "text": "+10% HP and attack power"},
	"Might+Swift": {"name": "Flurry", "effects": {"crit": 3}, "text": "every 3rd attack crits"},
	"Might+Guard": {"name": "Vanguard", "effects": {"ad": 0.10, "armor": 15.0}, "text": "+10% attack power, +15 armour"},
	"Might+Blood": {"name": "Hemorrhage", "effects": {"burn": 0.03}, "text": "attacks burn 3% of max HP per second"},
	"Might+Arcane": {"name": "Spellblade", "effects": {"ad": 0.10, "ap": 0.10}, "text": "+10% attack and ability power"},
	"Vigor+Swift": {"name": "Second Wind", "effects": {"regen": 0.015}, "text": "regen 1.5% of max HP per second"},
	"Vigor+Guard": {"name": "Bulwark", "effects": {"shield": 0.25}, "text": "25% shield"},
	"Vigor+Blood": {"name": "Undying", "effects": {"revive": 0.25}, "text": "revive once at 25% HP"},
	"Vigor+Arcane": {"name": "Lifebloom", "effects": {"regen": 0.025}, "text": "regen 2.5% of max HP per second"},
	"Swift+Guard": {"name": "Evasion", "effects": {"dodge": 4}, "text": "every 4th attack against it misses"},
	"Swift+Blood": {"name": "Frenzy", "effects": {"ramp": 0.04, "ramp_max": 10}, "text": "+4% attack speed per attack (max 10)"},
	"Swift+Arcane": {"name": "Tempest", "effects": {"chill": 0.20}, "text": "attacks chill 20%"},
	"Guard+Blood": {"name": "Bloodward", "effects": {"shield": 0.15, "vamp": 0.10}, "text": "15% shield, 10% omnivamp"},
	"Guard+Arcane": {"name": "Hex Ward", "effects": {"curse": 0.10}, "text": "attacks curse 10%"},
	"Blood+Arcane": {"name": "Soul Siphon", "effects": {"execute": 0.10}, "text": "execute below 10%"},
}
const PRISM := {"name": "Prism", "effects": {"hp": 0.10, "ad": 0.10, "ap": 0.10, "as": 0.10}, "text": "+10% HP, attack power, ability power and attack speed (three different elements)"}
const CRYSTAL_ALONE := {"hp": 0.08, "ad": 0.08, "ap": 0.08}   # a Resonance Crystal on a unit with no resonance

static func key(a: StringName, b: StringName) -> String:
	var ia := ELEMENTS.find(a)
	var ib := ELEMENTS.find(b)
	return "%s+%s" % [a, b] if ia <= ib else "%s+%s" % [b, a]

# Every resonance key a list of items switches on ("Might+Swift", ..., "Prism"), in a fixed order.
static func keys_for(items: Array) -> Array[String]:
	var elems: Array[StringName] = []
	for x in items:
		var it := x as ItemData
		if it != null and it.element != &"" and not elems.has(it.element):
			elems.append(it.element)
	elems.sort_custom(func(a, b): return ELEMENTS.find(a) < ELEMENTS.find(b))
	var out: Array[String] = []
	for i in elems.size():
		for j in range(i + 1, elems.size()):
			out.append(key(elems[i], elems[j]))
	if elems.size() >= 3:
		out.append("Prism")
	return out

static func def(k: String) -> Dictionary:
	return PRISM if k == "Prism" else PAIRS.get(k, {})

static func has_crystal(items: Array) -> bool:
	return items.any(func(x): return x is ItemData and x.kind == &"crystal")

# Every combat effect a unit's items give it: item effects (Wind Charm's chill), its resonances
# (doubled by a Crystal), or the Crystal's own bonus when there is no resonance.
static func unit_effects(items: Array) -> Dictionary:
	var fx := {}
	for x in items:
		var it := x as ItemData
		if it != null and not it.effects.is_empty():
			Synergies._merge(fx, it.effects)
	var keys := keys_for(items)
	var crystal := has_crystal(items)
	for k in keys:
		Synergies._merge(fx, doubled(def(k).effects) if crystal else def(k).effects)
	if crystal and keys.is_empty():
		Synergies._merge(fx, CRYSTAL_ALONE)
	return fx

# An effect set made twice as strong: amounts double, "every Nth" halves (at least every 2nd).
static func doubled(fx: Dictionary) -> Dictionary:
	var out := {}
	for k in fx:
		if k in Synergies.TAKE_EVERY:
			out[k] = maxi(2, int(fx[k]) / 2)
		elif k == "ramp_max":
			out[k] = fx[k]
		else:
			out[k] = fx[k] * 2.0
	return out

# What a resonance does, for tooltips ("Flurry: every 3rd attack crits").
static func describe(k: String) -> String:
	var d := def(k)
	return "%s: %s" % [d.get("name", k), d.get("text", "")]

# Resonances `item` would add with `others` (the items already on a unit), for the item tooltips.
static func would_add(item: ItemData, others: Array) -> Array[String]:
	var before := keys_for(others)
	var out: Array[String] = []
	for k in keys_for(others + [item]):
		if not before.has(k):
			out.append(k)
	return out
