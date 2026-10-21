# item_data.gd
class_name ItemData extends Resource

@export var id: StringName            # stable, unique; used by saves and snapshots. Never rename.
@export var display_name: String
@export_multiline var description: String
@export var color := Color.WHITE      # UI swatch until there are icons
@export var icon: Texture2D           # optional, unused in v1

# Stat boosts. Flat values add to the unit's base stats before star and synergy multipliers.
@export var hp := 0.0                 # flat max HP
@export var dmg := 0.0                # flat attack damage
@export var attack_speed := 0.0       # fraction, 0.15 = +15%
@export var mana := 0.0               # flat starting mana
@export var damage_reduction := 0.0   # fraction
@export var lifesteal := 0.0          # fraction
