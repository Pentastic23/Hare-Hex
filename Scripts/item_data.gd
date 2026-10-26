# item_data.gd
class_name ItemData extends Resource

# One item type (items v2: docs/items-v2.md). Basic items have stats and an element (resonance);
# special kinds add a rule: bound items grow, economy items pay gold, benders count their holder
# twice for a trait, the Resonance Crystal doubles resonances, Tinker's Tongs remove items.

@export var id: StringName            # stable, unique; used by saves and snapshots. Never rename.
@export var display_name: String
@export_multiline var description: String
@export var color := Color.WHITE      # UI swatch, and the model's colour if there is no icon
@export var icon: Texture2D           # optional, unused in v1

# Stat boosts. Flat values add to the unit's base stats before star and synergy multipliers.
@export var hp := 0.0                 # flat max HP
@export var dmg := 0.0                # flat attack damage
@export var attack_speed := 0.0       # fraction, 0.15 = +15%
@export var mana := 0.0               # flat starting mana
@export var damage_reduction := 0.0   # fraction
@export var lifesteal := 0.0          # fraction
@export var effects := {}             # extra combat effects, keys as in Synergies.DEFS (e.g. {"dmg": 0.08})

# Items v2
@export var element: StringName = &""   # Might, Vigor, Swift, Guard, Blood, Arcane ("" = none): resonance
@export var kind: StringName = &"basic" # basic, bound, economy, bender, crystal, remover
@export var min_stage := 1              # first stage it can drop in
@export var drop_weight := 1.0          # weight in its drop pool (0 = never drops at random)
# bound: grows by a stack each fight its holder survives
@export var stack_hp := 0.0
@export var stack_dmg := 0.0
@export var max_stacks := 0
# economy: only while the holder is on the board
@export var gold_per_round := 0
@export var free_rerolls := 0
# bender: the holder counts twice for this part of its traits ("origin" or "class")
@export var counts_twice: StringName = &""

# Which units each item suits (shown as "Best on ..." in the item tooltips), by its stat: damage for
# fighters and archers, health and reduction for the front line, mana for casters, omnivamp for units
# that hit hard and need to stay up.
const BEST_ON := {
	&"longsword": "Warriors, Duelists, Knights, Rangers",
	&"iron_belt": "Protectors, Brutes, Knights",
	&"quick_bow": "Rangers, Duelists, Rogues",
	&"chain_vest": "Protectors, Knights, Warriors",
	&"blood_fang": "Brutes, Warlocks, Tricksters, Rogues",
	&"mana_charm": "Casters, Elementalists, Healers, Summoners, Bards",
	&"heros_blade": "Warriors, Duelists, Rangers (a unit that survives fights)",
	&"heartwood_charm": "Protectors, Brutes (a unit that survives fights)",
	&"resonance_crystal": "your best item carrier (a unit with two other items)",
	&"coin_purse": "any unit that stays on your board",
	&"merchants_ledger": "any unit that stays on your board",
	&"twin_sigil": "a unit whose origin is one short of its next tier",
	&"twin_crest": "a unit whose class is one short of its next tier",
}

func best_on() -> String:
	return BEST_ON.get(id, "")

func is_special() -> bool:
	return kind != &"basic"

# Takes an item slot on a unit (Tinker's Tongs don't: they are used up).
func takes_slot() -> bool:
	return kind != &"remover"
