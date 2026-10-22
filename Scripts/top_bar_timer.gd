# top_bar_timer.gd
extends HBoxContainer

# The timer half of the top bar (top_bar.gd): "PREP 0:12" counting down gm.prep_left of gm.prep_time,
# "COMBAT 0:48" counting down to the 60 s fight limit (reaching it counts as a loss). Gold in prep, red
# for the last 5 s of prep and the last 10 s of a fight; "--" in a very long prep (the tutorial's).
# The top bar draws the progress track from `ratio` and `color` and its edge from `edge_color`.

const UNTIMED_PREP := 300.0   # prep_time at or above this is treated as "no timer"

var phase_label: Label
var time_label: Label
var active := false            # false outside prep and combat, or once the run is over
var ratio := 1.0               # time left / phase length
var color := HudStyle.GOLD
var edge_color := HudStyle.EDGE_GOLD
var _shown := ""

func _ready():
	add_theme_constant_override("separation", 7)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_label = HudStyle.caps(11)
	phase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(phase_label)
	time_label = HudStyle.number(24)
	time_label.custom_minimum_size = Vector2(56, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(time_label)

func _process(_delta):
	var gm = get_tree().get_first_node_in_group("game_manager")
	var phase := ""
	var time := ""
	var urgent := false
	ratio = 1.0
	if gm == null or gm.game_over:
		pass
	elif gm.fighting:
		var left: float = (gm.COMBAT_MAX_TICKS - gm.combat_ticks) * gm.COMBAT_TICK
		phase = "COMBAT"
		time = clock(left)
		ratio = left / (gm.COMBAT_MAX_TICKS * gm.COMBAT_TICK)
		urgent = left <= 10.0
	elif gm.phase == Events.Phase.PREP:
		phase = "PREP"
		if gm.prep_time >= UNTIMED_PREP:
			time = "--"
		else:
			time = clock(gm.prep_left)
			ratio = gm.prep_left / maxf(float(gm.prep_time), 0.01)
			urgent = gm.prep_left <= 5.0
	active = phase != ""
	visible = active
	color = HudStyle.RED if urgent else (HudStyle.GOLD if phase == "PREP" else HudStyle.INK)
	edge_color = HudStyle.EDGE_RED if urgent else (HudStyle.EDGE_GOLD if phase == "PREP" else HudStyle.EDGE)
	var state := "%s|%s|%s" % [phase, time, urgent]
	if state == _shown:
		return
	_shown = state
	phase_label.text = phase
	time_label.text = time
	phase_label.add_theme_color_override("font_color", HudStyle.RED if urgent else (HudStyle.GOLD if phase == "PREP" else HudStyle.MUTED))
	time_label.add_theme_color_override("font_color", color)

# Whole seconds, rounded up, so the display shows 0:01 until the very end instead of 0:00 early.
static func clock(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]
