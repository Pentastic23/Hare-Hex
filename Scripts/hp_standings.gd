# hp_standings.gd
extends VBoxContainer

# Combat HUD, right edge: one StandingRow per player, highest HP first, eliminated players last.
# Single player today: you, plus a row for this round's opponent: the ghost in async PvP (its HP when
# it was recorded), the wave in a campaign ("4/5" instead of HP), or "Random enemies" in free play.
# Lobbies later: one row per GameState.players entry, the one you face gets the VS tag.
# Replaces the old HpLabel and TopBar/OpponentLabel. The damage meter overlays it while open.

const TOP := 129    # below the top-right button bar
const RIGHT := 2    # px from the right edge

var rows: Array[StandingRow] = []

func _ready():
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -RIGHT
	offset_left = -RIGHT - StandingRow.WIDTH
	offset_top = TOP
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.hp_changed.connect(func(_hp): refresh())
	Events.opponent_announced.connect(func(_t): refresh())
	Events.round_changed.connect(func(_s, _r): refresh())
	refresh.call_deferred()

# [name, role, hp, max hp, number text] per row, sorted.
func entries() -> Array:
	var out: Array = []
	for p in GameState.players:
		var ps := p as PlayerState
		out.append(["You" if ps.is_local else "Player %d" % ps.id, "you" if ps.is_local else "other", ps.player_hp, ps.start_hp, ""])
	out.append(_opponent())
	out.sort_custom(func(a, b):
		var a_out: bool = a[2] == 0 and a[1] != "opponent"
		var b_out: bool = b[2] == 0 and b[1] != "opponent"
		if a_out != b_out:
			return b_out
		return int(a[2]) > int(b[2]))
	return out

func _opponent() -> Array:
	var gm = get_tree().get_first_node_in_group("game_manager")
	var lvl := GameState.run_level
	if lvl != null and not lvl.waves.is_empty():
		var cur := clampi(GameState.round_number, 1, lvl.waves.size())
		var wave: EnemyBoard = lvl.waves[cur - 1]
		var wave_name := wave.display_name if wave != null and wave.display_name != "" else "Wave %d" % cur
		return [wave_name, "opponent", -1, 1, "%d/%d" % [cur, lvl.waves.size()]]
	if gm != null and gm.opponents is SnapshotOpponents:
		var s: Dictionary = gm.opponents.current_snapshot()
		if not s.is_empty():
			return ["Ghost of %s" % str(s.get("name", "?")), "opponent", int(s.get("hp", 0)), 100, ""]
	return ["Random enemies", "opponent", -1, 1, ""]

func refresh() -> void:
	var list := entries()
	while rows.size() < list.size():
		var r := StandingRow.new()
		add_child(r)
		rows.append(r)
	while rows.size() > list.size():
		rows.pop_back().queue_free()
	for i in list.size():
		var e: Array = list[i]
		rows[i].show_player(e[1], e[0], e[2], e[3], e[4])

# The row of this round's opponent (tests, later the lobby).
func opponent_row() -> StandingRow:
	for r in rows:
		if r.role == "opponent":
			return r
	return null

func you_row() -> StandingRow:
	for r in rows:
		if r.role == "you" or (r.role == "out" and r.name_text == "You"):
			return r
	return null
