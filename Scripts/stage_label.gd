# stage_label.gd
extends Label

func _ready():
	Events.round_changed.connect(_update)
	await get_tree().process_frame
	_update(GameState.stage(), GameState.round_in_stage())

func _update(s: int, r: int):
	var lvl := GameState.run_level
	if lvl == null:
		text = "Stage %d-%d" % [s, r]
		tooltip_text = ""
		return
	var wave: EnemyBoard = lvl.waves[clampi(GameState.round_number - 1, 0, lvl.waves.size() - 1)] if not lvl.waves.is_empty() else null
	text = "%s   Wave %d/%d" % [lvl.display_name, GameState.round_number, GameState.total_rounds()]
	if wave != null and wave.display_name != "":
		text += ": " + wave.display_name
	# Hover to see who's coming (stars and item counts), so the player can prepare.
	var lines: PackedStringArray = []
	if wave != null:
		for bu in wave.units:
			if bu != null and bu.unit != null:
				lines.append("%s %s%s" % [bu.unit.display_name, "*".repeat(bu.star), ("  (%d items)" % bu.items.size()) if not bu.items.is_empty() else ""])
	tooltip_text = "Enemies this wave:\n" + "\n".join(lines) if not lines.is_empty() else ""
	mouse_filter = Control.MOUSE_FILTER_STOP if tooltip_text != "" else Control.MOUSE_FILTER_IGNORE
