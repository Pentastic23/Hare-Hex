# item_data.gd
class_name ItemData extends Resource

# One item type (items v2: docs/items-v2.md). Basic items have stats and an element (resonance);
# special kinds add a rule: bound items grow, economy items pay gold, benders count their holder
# twice for a trait, the Resonance Crystal doubles resonances, Tinker's Tongs remove items, and the
# Ancient Sigil (ascension) takes a 3-star unit to 4 stars after 8 wins it survives (Unit.count_sigil_win).

@export var id: StringName            # stable, unique; used by saves and snapshots. Never rename.
@export var display_name: String
@export_multiline var description: String
@export var color := Color.WHITE      # UI swatch, and the model's colour if there is no icon
@export var icon: Texture2D           # optional, unused in v1

# Stat boosts (items v3, docs/stats-and-items-v3.md). Each basic item has one main stat, which sets its
# element: attack power Might, HP and mitigation Vigor, attack speed Swift, armour and magic resist
# Guard, omnivamp Blood, ability power and mana Arcane. Flat HP adds to base HP before the star and
# synergy multipliers; the fractions add to the synergy percentages. Negative values are drawbacks.
@export var hp := 0.0                 # flat max HP
@export var attack_power := 0.0       # fraction: attacks deal this much more
@export var ability_power := 0.0      # fraction: ability damage, heals and shields this much more
@export var attack_speed := 0.0       # fraction, 0.15 = +15%
@export var armor := 0.0              # flat
@export var magic_resist := 0.0       # flat
@export var mitigation := 0.0         # flat damage off every hit
@export var mana := 0.0               # flat starting mana
@export var lifesteal := 0.0          # omnivamp, fraction
@export var effects := {}             # extra combat effects, keys as in Synergies.DEFS (e.g. {"regen": 0.01})

# Items v2
@export var element: StringName = &""   # Might, Vigor, Swift, Guard, Blood, Arcane ("" = none): resonance
@export var kind: StringName = &"basic" # basic, bound, economy, bender, crystal, remover, ascension
@export var min_stage := 1              # first stage it can drop in
@export var drop_weight := 1.0          # weight in its drop pool (0 = never drops at random)
# bound: grows by a stack each fight its holder survives (ascension: a mark per won fight; max_stacks marks ascend)
@export var stack_hp := 0.0
@export var stack_ad := 0.0    # attack power per stack, fraction
@export var max_stacks := 0
# economy: only while the holder is on the board
@export var gold_per_round := 0
@export var free_rerolls := 0
# bender: the holder counts twice for this part of its traits ("origin" or "class")
@export var counts_twice: StringName = &""

# Which units each item suits (shown as "Best on ..." in the item tooltips), by its stat: attack power
# and speed for fighters and archers, ability power and mana for casters, HP, armour, magic resist and
# mitigation for the front line, omnivamp for units that hit hard and need to stay up.
const BEST_ON := {
	&"longsword": "Rangers, Rogues, Duelists, Infernals",
	&"war_axe": "Warriors, Brutes, Duelists",
	&"serrated_dirk": "Rogues, Rangers, Wild units (fast attackers)",
	&"giants_maul": "Rogues, Duelists, Shadow units (big single hits)",
	&"iron_belt": "Protectors, Brutes, Knights",
	&"troll_hide": "Brutes, Warriors, Knights",
	&"heart_locket": "Protectors, Celestials, front-line casters",
	&"ogres_girdle": "Protectors, Brutes (units that don't need to attack fast)",
	&"leather_jerkin": "Knights, Monks, Order units (taking many small hits)",
	&"hide_bracers": "Brutes, Warriors, Order units",
	&"padded_gambeson": "Knights, Protectors, Monks",
	&"stone_ring": "Protectors, Order units (tanks that don't need to attack fast)",
	&"quick_bow": "Rangers, Duelists, Rogues",
	&"swift_gloves": "Rangers, Rogues, Wild units",
	&"wind_charm": "Rangers, Frost units, Fey",
	&"feather_boots": "Rangers and Fey in the back row",
	&"chain_vest": "Protectors, Knights, Warriors",
	&"tower_shield": "Protectors, Knights, Brutes",
	&"bronze_buckler": "Knights, Tricksters, Warriors",
	&"plate_cuirass": "Protectors, Knights (tanks that don't need to attack fast)",
	&"warding_cloak": "Protectors, Monks, Knights",
	&"silver_circlet": "front-line casters, Healers, Monks",
	&"spellward_talisman": "Protectors, Knights, Warriors",
	&"nullstone_amulet": "Protectors, Monks (units that don't cast for damage)",
	&"blood_fang": "Brutes, Warlocks, Tricksters, Rogues",
	&"vampire_ring": "Duelists, Shadow units, Rogues (units that land kills)",
	&"hungering_blade": "Warriors, Duelists, Brutes",
	&"sanguine_tome": "Casters, Warlocks, Elementalists",
	&"apprentice_wand": "Casters, Elementalists, Summoners",
	&"sages_staff": "Casters, Healers, Bards",
	&"hex_orb": "Elementalists, Warlocks, Casters",
	&"archmages_tome": "Casters in the back row",
	&"mana_charm": "Casters, Elementalists, Healers, Bards",
	&"spirit_bead": "Healers, Bards, front-line casters",
	&"moon_tear": "Bards, Monks, Rangers with a strong ability",
	&"focus_gem": "Casters and Healers in the back row",
	&"heros_blade": "Warriors, Duelists, Rangers (a unit that survives fights)",
	&"heartwood_charm": "Protectors, Brutes (a unit that survives fights)",
	&"resonance_crystal": "your best item carrier (a unit with two other items)",
	&"coin_purse": "any unit that stays on your board",
	&"merchants_ledger": "any unit that stays on your board",
	&"twin_sigil": "a unit whose origin is one short of its next tier",
	&"twin_crest": "a unit whose class is one short of its next tier",
	&"ancient_sigil": "your best 3-star unit, one that keeps surviving fights",
}

func best_on() -> String:
	return BEST_ON.get(id, "")

func is_special() -> bool:
	return kind != &"basic"

# Takes an item slot on a unit (Tinker's Tongs don't: they are used up).
# Rare enough to drop at most once a run (benders, the Ancient Sigil).
func once_a_run() -> bool:
	return kind == &"bender" or kind == &"ascension"

# Counts something on the unit it is on (bound stacks, the Ancient Sigil's marks).
func counts() -> bool:
	return kind == &"bound" or kind == &"ascension"

func takes_slot() -> bool:
	return kind != &"remover"
