# phase_timer.gd
extends Label

# TopBar/Timer: "Prep 0:12" counting down during preparation, "Combat 0:48" counting down to the
# 60 s fight limit (reaching it counts as a loss). Turns red for the last 5 s of prep and orange for
# the last 10 s of a fight. A very long prep (the tutorial's) just says "Prep".

const UNTIMED_PREP := 300.0   # prep_time at or above this is treated as "no timer"

func _ready():
	custom_minimum_size = Vector2(120, 0)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 20)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = ""

func _process(_delta):
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm == null or gm.game_over:
		text = ""
		return
	if gm.fighting:
		var left: float = (gm.COMBAT_MAX_TICKS - gm.combat_ticks) * gm.COMBAT_TICK
		text = "Combat %s" % _clock(left)
		modulate = Color(1.0, 0.6, 0.25) if left <= 10.0 else Color.WHITE
	elif gm.phase == Events.Phase.PREP:
		if gm.prep_time >= UNTIMED_PREP:
			text = "Prep"
			modulate = Color.WHITE
		else:
			text = "Prep %s" % _clock(gm.prep_left)
			modulate = Color(1.0, 0.35, 0.35) if gm.prep_left <= 5.0 else Color.WHITE
	else:
		text = ""

# Whole seconds, rounded up, so the display shows 0:01 until the very end instead of 0:00 early.
func _clock(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]
