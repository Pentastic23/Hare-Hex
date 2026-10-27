# round_tracker.gd
extends HBoxContainer

# The rounds half of the top bar (top_bar.gd): "STAGE 3  [pips]  3-4" in free play, "WAVE  [pips]  4/5" in a campaign
# level (one pip per wave; the last wave of a chapter level is the boss, drawn as a diamond), and
# "TROPHIES  [pips]  4/10" in async PvP (one pip per trophy toward the 10 that win; "ENDLESS  14" after).
# In a campaign, hovering it lists the level, the wave and its enemies so you can prepare.
# Collapsed (set_compact), only the "3-4" text shows.

const MAX_PIPS := 10   # more rounds than this: just the text

var stage_label: Label
var count_label: Label
var pips: PipRow
var compact := false

class PipRow extends Control:
	const PIP := 9
	const GAP := 5
	var states: Array[String] = []   # "done", "current", "next", "boss" (or "boss_done" / "boss_current")
	func set_states(s: Array[String]) -> void:
		states = s
		custom_minimum_size = Vector2(maxi(s.size() * (PIP + GAP) - GAP + 2, 0), PIP + 4)
		queue_redraw()
	func _draw():
		var y := (size.y - PIP) / 2.0
		for i in states.size():
			var x := 1.0 + i * (PIP + GAP)
			var st := states[i]
			if st.begins_with("boss"):
				_diamond(Vector2(x + PIP / 2.0, y + PIP / 2.0), st)
			elif st == "done":
				draw_rect(Rect2(x, y + 2, PIP, PIP), Color("7a5a17"))
				draw_rect(Rect2(x, y, PIP, PIP), HudStyle.GOLD)
			elif st == "current":
				draw_rect(Rect2(x - 1, y - 1, PIP + 2, PIP + 2), HudStyle.GOLD)
				draw_rect(Rect2(x + 1, y + 1, PIP - 2, PIP - 2), HudStyle.INK)
			else:
				draw_rect(Rect2(x, y + 2, PIP, PIP), HudStyle.LIP)
				draw_rect(Rect2(x, y, PIP, PIP), Color("2c3249"))
	func _diamond(c: Vector2, st: String) -> void:
		var r := 5.7   # an 8 x 8 square turned 45 degrees
		var outer := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		var inner := PackedVector2Array([c + Vector2(0, -r + 2.8), c + Vector2(r - 2.8, 0), c + Vector2(0, r - 2.8), c + Vector2(-r + 2.8, 0)])
		var fill := Color("3a2620")
		if st == "boss_done":
			fill = HudStyle.GOLD
		elif st == "boss_current":
			fill = HudStyle.INK
		draw_colored_polygon(outer, HudStyle.ENEMY)
		draw_colored_polygon(inner, fill)

func _ready():
	add_theme_constant_override("separation", 9)
	stage_label = HudStyle.caps(11)
	stage_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(stage_label)
	pips = PipRow.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(pips)
	count_label = HudStyle.number(22)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(count_label)
	Events.round_changed.connect(func(_s, _r): refresh())
	Events.trophies_changed.connect(func(_t, _l): refresh())
	refresh()

func set_compact(c: bool) -> void:
	compact = c
	refresh()

func refresh() -> void:
	var lvl := GameState.run_level
	var states: Array[String] = []
	if GameState.ghost_mode and lvl == null:
		var me := GameState.me
		stage_label.text = "ENDLESS" if me.endless else "TROPHIES"
		count_label.text = str(me.trophies) if me.endless else "%d/%d" % [me.trophies, GameState.ASYNC_TROPHIES]
		if not me.endless:
			for i in GameState.ASYNC_TROPHIES:
				states.append("done" if i < me.trophies else ("current" if i == me.trophies else "next"))
		tooltip_text = Tip.wrap("Round %d. Win a fight for a trophy; %d trophies win the run. Lose %d fights and it is over (%d lives left).%s" % [GameState.round_number, GameState.ASYNC_TROPHIES, GameState.ASYNC_LIVES, me.lives_left(), " Endless mode: sudden death, the next loss ends the run." if me.endless else ""])
	elif lvl == null or lvl.waves.is_empty():
		stage_label.text = "STAGE %d" % GameState.stage()
		count_label.text = "%d-%d" % [GameState.stage(), GameState.round_in_stage()]
		var n := GameState.rounds_in_current_stage()
		var cur := GameState.round_in_stage()
		for i in n:
			states.append("done" if i + 1 < cur else ("current" if i + 1 == cur else "next"))
		tooltip_text = ""
	else:
		var total := GameState.total_rounds()
		var cur := clampi(GameState.round_number, 1, total)
		stage_label.text = "WAVE"
		count_label.text = "%d/%d" % [cur, total]
		for i in total:
			var st := "done" if i + 1 < cur else ("current" if i + 1 == cur else "next")
			if i == total - 1 and _has_boss(lvl):
				st = "boss" if st == "next" else "boss_" + st
			states.append(st)
		tooltip_text = _wave_tip(lvl, cur)
	pips.visible = states.size() <= MAX_PIPS and not compact
	stage_label.visible = not compact
	pips.set_states(states if pips.visible else ([] as Array[String]))
	mouse_filter = Control.MOUSE_FILTER_STOP if tooltip_text != "" else Control.MOUSE_FILTER_IGNORE

# Chapter levels end in a boss wave; the tutorial (not in any chapter) doesn't.
func _has_boss(lvl: CampaignLevel) -> bool:
	var camp := GameState.run_campaign
	return camp != null and camp.all_levels().has(lvl)

# Hover text: the level, this wave and who's in it (stars and item counts).
func _wave_tip(lvl: CampaignLevel, cur: int) -> String:
	var wave: EnemyBoard = lvl.waves[cur - 1]
	var head := "%s\nWave %d/%d%s" % [lvl.display_name, cur, lvl.waves.size(), (": " + wave.display_name) if wave != null and wave.display_name != "" else ""]
	var lines: PackedStringArray = []
	if wave != null:
		for bu in wave.units:
			if bu != null and bu.unit != null:
				lines.append("%s %s%s" % [bu.unit.display_name, "*".repeat(bu.star), ("  (%d items)" % bu.items.size()) if not bu.items.is_empty() else ""])
	if lines.is_empty():
		return Tip.wrap(head)
	return Tip.wrap(head + "\nEnemies this wave:\n" + "\n".join(lines))
