# opponent_provider.gd
class_name OpponentProvider extends RefCounted

# GameManager asks its provider for the enemy board at the start of every fight.
# Implementations: RandomOpponents (free play), WaveOpponents (campaign).
# Planned: snapshots of past player boards (PvP), using the same EnemyBoard format.

func board_for_round(_round_number: int) -> EnemyBoard:
	return null
