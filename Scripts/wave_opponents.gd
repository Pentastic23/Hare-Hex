# wave_opponents.gd
class_name WaveOpponents extends OpponentProvider

# Campaign: hand-authored waves, one per round. Rounds past the last wave repeat it.

var waves: Array[EnemyBoard] = []
var stat_mult := 1.0   # level modifier on top of each wave's own stat_scale

func _init(level_waves: Array[EnemyBoard], mult := 1.0):
	waves = level_waves
	stat_mult = mult

func board_for_round(round_number: int) -> EnemyBoard:
	if waves.is_empty():
		return null
	var wave: EnemyBoard = waves[clampi(round_number - 1, 0, waves.size() - 1)]
	if wave == null:
		return null
	var b: EnemyBoard = wave.duplicate()   # shallow: units are shared, only the scale changes
	b.stat_scale = wave.stat_scale * stat_mult
	return b
