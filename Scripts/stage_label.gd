# stage_label.gd
extends Label

func _ready():
	Events.round_changed.connect(_update)
	await get_tree().process_frame
	_update(GameState.stage(), GameState.round_in_stage())

func _update(s: int, r: int):
	text = "Stage %d-%d" % [s, r]
