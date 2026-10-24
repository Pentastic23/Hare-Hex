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
	var lobby := LobbyNet.in_lobby()
	var foe := _lobby_opponent() if lobby else -1
	for p in GameState.players:
		var ps := p as PlayerState
		var role := "you" if ps.is_local else "other"
		if lobby and not ps.is_local:
			role = "out" if ps.player_hp <= 0 else ("opponent" if ps.id == foe else "other")
		var label := "You" if ps.is_local else (ps.display_name if lobby else "Player %d" % ps.id)
		out.append([label, role, ps.player_hp, ps.start_hp, ""])
	if not lobby:
		out.append(_opponent())   # a lobby's opponent is one of the players above
	out.sort_custom(func(a, b):
		var a_out: bool = a[2] == 0 and a[1] != "opponent"
		var b_out: bool = b[2] == 0 and b[1] != "opponent"
		if a_out != b_out:
			return b_out
		return int(a[2]) > int(b[2]))
	return out

# The seat you fight this round in a lobby (-1: none yet, or a PvE wave).
func _lobby_opponent() -> int:
	var c: LobbyClient = LobbyNet.client
	if c == null or c.fight.is_empty():
		return -1
	var home := int(c.fight.get("home", -1))
	var away := int(c.fight.get("away", -1))
	return away if home == c.seat else home

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
	var compact := list.size() > 5   # a full lobby: eight short rows fit above the bench
	add_theme_constant_override("separation", 3 if compact else 6)
	for i in list.size():
		var e: Array = list[i]
		if rows[i]._compact != compact:
			rows[i].set_compact(compact)
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
