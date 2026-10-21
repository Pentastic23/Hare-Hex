# streak_label.gd
extends Label

func _ready():
	Events.streak_changed.connect(_update)
	_update(GameState.win_streak, GameState.loss_streak)

func _update(wins: int, losses: int):
	var s: int = maxi(wins, losses)
	if s < 2:
		text = ""
		return
	text = "%s streak: %d" % ["Win" if wins > losses else "Loss", s]
	modulate = Color(0.4, 0.9, 0.4) if wins > losses else Color(0.95, 0.4, 0.4)
