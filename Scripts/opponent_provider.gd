# opponent_provider.gd
class_name OpponentProvider extends RefCounted

# GameManager asks its provider for the enemy board at the start of every fight.
# Implementations: RandomOpponents (free play), WaveOpponents (campaign).
# Planned: snapshots of past player boards (PvP), using the same EnemyBoard format.

func board_for_round(_round_number: int) -> EnemyBoard:
	return null

# Called when PREP starts, so a provider can pick this round's opponent early (async PvP ghosts).
func prepare(_round_number: int) -> void:
	pass

# What to show on the top bar for the coming fight; "" = nothing to say.
func describe_next() -> String:
	return ""
