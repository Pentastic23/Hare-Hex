
# label.gd  (XP / level label)
extends Label

func _ready():
	Events.xp_changed.connect(func(l, x, n): text = "Lv %d  (%d/%d)" % [l, x, n])
	text = "Lv %d  (%d/%d)" % [GameState.me.level, GameState.me.xp, GameState.me.xp_needed()]
