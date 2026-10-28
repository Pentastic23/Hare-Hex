# hp_standings.gd
extends VBoxContainer

# Combat HUD, right edge: one StandingRow per player, highest HP first, eliminated players last.
# Single player today: you, plus a row for this round's opponent: the ghost in async PvP (its HP when
# it was recorded), the wave in a campaign ("4/5" instead of HP), or "Random enemies" in free play.
# Your row shows your win / loss streak (flames / droplets) in every mode.
# Lobbies: one row per GameState.players entry, the one you face gets the VS tag, everyone's streaks show
# beside the HP; click a player's row to see their board (LobbyGame.scout), your own row or Space to come back.
# Async PvP has no HP: the rows show lives left out of 10 (one bar segment each), yours and the ghost's.
# Replaces the old HpLabel and TopBar/OpponentLabel. The damage meter overlays it while open.

const TOP := 129    # below the top-right button bar
const RIGHT := 2    # px from the right edge

var rows: Array[StandingRow] = []
var scout_note: Label   # "VIEWING ..." under the rows while another player's board is on show

func _ready():
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -RIGHT
	offset_left = -RIGHT - StandingRow.WIDTH
	offset_top = TOP
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.hp_changed.connect(func(_hp): refresh())
	Events.trophies_changed.connect(func(_t, _l): refresh())
	Events.opponent_announced.connect(func(_t): refresh())
	Events.round_changed.connect(func(_s, _r): refresh())
	Events.streak_changed.connect(func(_w, _l): refresh())
	scout_note = HudStyle.caps(10, HudStyle.GOLD)
	scout_note.visible = false
	scout_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scout_note.custom_minimum_size = Vector2(StandingRow.WIDTH, 0)
	add_child(scout_note)
	refresh.call_deferred()

func _lobby() -> LobbyGame:
	var gm = get_tree().get_first_node_in_group("game_manager")
	return gm.lobby if gm != null else null

func _input(event: InputEvent) -> void:
	var lobby := _lobby()
	if lobby != null and lobby.scouting >= 0 and Keybinds.pressed(event, "scout_home") and not BugReporter.typing():
		lobby.scout(-1)
		get_viewport().set_input_as_handled()

func _on_row_input(event: InputEvent, r: StandingRow) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var lobby := _lobby()
		if lobby != null and r.seat >= 0:
			lobby.scout(-1 if r.role == "you" else r.seat)

# [name, role, hp, max hp, number text, seat, streak] per row, sorted (seat: lobbies only; streak: yours, and everyone's in lobbies).
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
		var streak := (ps.win_streak if ps.win_streak > 0 else -ps.loss_streak) if lobby or ps.is_local else 0   # yours in every mode
		if GameState.ghost_mode and not lobby:
			out.append([label, role, ps.lives_left(), 1 if ps.endless else GameState.ASYNC_LIVES, "", -1, streak])   # endless: sudden death
			continue
		out.append([label, role, ps.player_hp, ps.start_hp, "", ps.id if lobby else -1, streak])
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
		return [wave_name, "opponent", -1, 1, "%d/%d" % [cur, lvl.waves.size()], -1, 0]
	if gm != null and gm.opponents is SnapshotOpponents:
		var s: Dictionary = gm.opponents.current_snapshot()
		if not s.is_empty() and s.has("trophies"):   # an async PvP ghost: its lives when it was recorded
			return ["Ghost of %s" % str(s.get("name", "?")), "opponent", maxi(GameState.ASYNC_LIVES - int(s.get("losses", 0)), 0), GameState.ASYNC_LIVES, "", -1, 0]
		if not s.is_empty():   # recorded before trophies (or in free play): its HP
			return ["Ghost of %s" % str(s.get("name", "?")), "opponent", int(s.get("hp", 0)), 100, "", -1, 0]
	return ["Random enemies", "opponent", -1, 1, "", -1, 0]

func refresh() -> void:
	var list := entries()
	while rows.size() < list.size():
		var r := StandingRow.new()
		add_child(r)
		r.gui_input.connect(_on_row_input.bind(r))
		rows.append(r)
	while rows.size() > list.size():
		rows.pop_back().queue_free()
	var lobby := _lobby()
	var compact := list.size() > 5   # a full lobby: eight short rows fit above the bench
	add_theme_constant_override("separation", 3 if compact else 6)
	for i in list.size():
		var e: Array = list[i]
		if rows[i]._compact != compact:
			rows[i].set_compact(compact)
		rows[i].seat = e[5]
		rows[i].streak = e[6]
		rows[i].scouted = lobby != null and e[5] >= 0 and e[5] == lobby.scouting
		rows[i].tooltip_text = (Tip.wrap("Your board. Space also brings you back here.") if e[1] == "you" else Tip.wrap("Click to see this player's board.")) if e[5] >= 0 else ""
		rows[i].show_player(e[1], e[0], e[2], e[3], e[4])
	scout_note.visible = lobby != null and lobby.scouting >= 0
	if scout_note.visible:
		Keybinds.ensure()
		var whose := (lobby.scouting_name + "'s") if lobby.scouting_name != "" else "another player's"
		scout_note.text = "Viewing %s board. Click your row or press %s to return." % [whose, Keybinds.key_name(Keybinds.keys.get("scout_home", KEY_SPACE))]
	move_child(scout_note, -1)

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
