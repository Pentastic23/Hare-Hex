# lobby_game.gd
class_name LobbyGame extends RefCounted

# GameManager's lobby mode: the game scene as a view of a lobby run by a LobbyServer (here or across the
# network). Nothing is decided here. Your clicks become requests (LobbyClient); the server's answers
# update the HUD (through the usual Events) and the board:
#   - "state": your gold, level, XP, HP, streaks, items and shop are copied into GameState.me, and the
#     board's units are matched to the server's by uid (made, moved, upgraded, re-itemed or removed).
#   - "fight": your fight is replayed on the visible board from its description (Arena.setup), in real
#     time with the fixed combat tick, applying item drops at the ticks the server set. From the away
#     side the board is turned around (Board.set_view_flipped) and your units are the blue ones
#     (Unit.viewer_team); the units themselves are the same as on the server.
#   - "result" / "public" / "over": HP, standings, placement.
# Your bench stays usable during a fight (buy, sell, move between bench slots, and items onto bench or
# fighting units), exactly as in single player.

var gm   # GameManager
var board: Board
var client: LobbyClient
var sides := {}          # the fight being replayed: {"home": [...], "away": [...]}
var my_side := "home"
var replay_id := -1
var replaying := false   # a fight is on the board (running or just finished)
var _rolls := -1         # last shop roll count seen (only a new roll refills the shop slots)
var scouting := -1       # the seat whose board is on show instead of yours (scout()); -1 = your own
var scouting_name := ""
var _scout_timer: Timer   # asks for the scouted board again while it is on show
var _shown_out := false

func _init(game_manager):
	gm = game_manager
	board = gm.board
	client = LobbyNet.client

func begin() -> void:
	GameState.run_level = null
	GameState.run_campaign = null
	GameState.ghost_mode = false
	GameState.run_carried = false
	GameState.round_number = 1
	var me := GameState.me
	me.reset()
	me.id = client.seat
	me.display_name = client.name if client.name != "" else "You"
	GameState.players = [me]
	gm.roster = gm.unit_pool
	gm.shared_pool = UnitPool.new(gm.roster)   # display only: the real pool is the server's
	gm.rules = PlayerRules.new(me, board, gm.shared_pool, gm.roster, gm.item_roster)   # for read-only helpers (Coin Purse income)
	gm.prep_time = int(client.prep_time)
	gm.opponents = null
	board.foe_level = 1   # the enemy half stays small until a fight opens the opponent's own tiles
	board.refresh_unlocks(me.level, false)
	_scout_timer = Timer.new()
	_scout_timer.wait_time = 1.5
	_scout_timer.timeout.connect(func(): if scouting >= 0: client.scout(scouting))
	gm.add_child(_scout_timer)
	board.apply_theme(BoardThemes.for_run(null, client.seed), client.seed)
	gm.runner.on_finish = _on_replay_finish
	gm.runner.gold_sink = Callable()   # gold comes from the server's state
	client.phase_changed.connect(_on_phase)
	client.state_changed.connect(_on_state)
	client.public_changed.connect(_on_public)
	client.fight_started.connect(_on_fight)
	client.input_received.connect(_on_input)
	client.result_received.connect(_on_result)
	client.rejected.connect(_on_rejected)
	client.game_over.connect(_on_over)
	client.board_received.connect(_on_board)
	LobbyNet.lost.connect(_on_lost)
	Music.play("game")
	# Catch up with what arrived while the scene loaded.
	if not client.public.is_empty():
		_on_public(client.public)
	if not client.phase.is_empty():
		_on_phase(client.phase)
	if not client.state.is_empty():
		_on_state(client.state)
	if not client.fight.is_empty() and str(client.phase.get("phase", "")) == LobbyProtocol.PHASE_COMBAT:
		_on_fight(client.fight)
	if not client.over.is_empty():
		_on_over(client.over)

# --- what the server says ------------------------------------------------------------------------

static func phase_of(name: String) -> int:
	match name:
		LobbyProtocol.PHASE_COMBAT:
			return Events.Phase.COMBAT
		LobbyProtocol.PHASE_RESULT, LobbyProtocol.PHASE_OVER:
			return Events.Phase.RESULT
	return Events.Phase.PREP

func _on_phase(msg: Dictionary) -> void:
	GameState.round_number = int(msg.get("round", 1))
	var p := phase_of(str(msg.get("phase", "")))
	if p == Events.Phase.PREP and replaying:
		_end_replay()
	gm.phase = p
	gm.prep_left = float(msg.get("time", 0.0)) if p == Events.Phase.PREP else 0.0
	gm.prep_length = gm.prep_left
	Events.phase_changed.emit(p)
	Events.round_changed.emit(GameState.stage(), GameState.round_in_stage())
	if p == Events.Phase.PREP:
		Events.opponent_announced.emit("Wild creatures" if bool(msg.get("pve", false)) else "")
		if not client.state.is_empty():
			_on_state(client.state)   # rebuild the board as the server has it

func _on_state(msg: Dictionary) -> void:
	var me := GameState.me
	me.gold = int(msg.gold)
	var leveled := me.level != int(msg.level) or me.xp != int(msg.xp)
	me.level = int(msg.level)
	me.xp = int(msg.xp)
	if leveled:
		Events.xp_changed.emit(me.level, me.xp, me.xp_needed())
	me.start_hp = int(msg.get("start_hp", GameState.MAX_HP))
	me.player_hp = int(msg.hp)
	if me.win_streak != int(msg.win) or me.loss_streak != int(msg.loss):
		me.win_streak = int(msg.win)
		me.loss_streak = int(msg.loss)
		Events.streak_changed.emit(me.win_streak, me.loss_streak)
	me.free_rerolls = int(msg.get("free_rerolls", 0))
	me.opening = bool(msg.get("opening", false))
	me.cheap_shop = bool(msg.get("cheap", false))
	if me.shop_locked != bool(msg.locked):
		me.shop_locked = bool(msg.locked)
		Events.shop_lock_changed.emit(me.shop_locked)
	var items: Array[ItemData] = []
	for id in msg.get("items", []):
		var it := EnemyBoard.lookup_item(gm.item_roster, StringName(str(id)))
		if it != null:
			items.append(it)
	me.items = items
	var recv := int(msg.get("recv", 0))
	if recv != me.received:   # the server handed us items since the last state: pop them up
		var got: Array[ItemData] = []
		for id in msg.get("recv_items", []):
			var it := EnemyBoard.lookup_item(gm.item_roster, StringName(str(id)))
			if it != null:
				got.append(it)
		if recv > me.received and not got.is_empty():
			Events.items_received.emit(got)
		me.received = recv
	var offers: Array[UnitData] = []
	for n in msg.get("offers", []):
		var d := EnemyBoard.lookup_unit(gm.roster, str(n))
		if d != null:
			offers.append(d)
	me.shop_offers = offers
	me.shop_has_rolled = true
	var rolls := int(msg.get("rolls", 0))
	if rolls != _rolls:
		_rolls = rolls
		Events.shop_rolled.emit(offers.duplicate())
	reconcile(msg.get("units", []), replaying)
	Events.items_changed.emit()   # item bar, and the left box's synergy and item lists (the board may have changed too)
	Events.gold_changed.emit(me.gold)   # shop prices (free rerolls) follow
	if not bool(msg.get("alive", true)) and not _shown_out:
		_shown_out = true
		_show_end(int(msg.get("place", 0)), false)

func _on_public(msg: Dictionary) -> void:
	var list: Array[PlayerState] = [GameState.me]
	for e in msg.get("seats", []):
		if int(e.seat) == client.seat:
			continue
		var p := PlayerState.new()
		p.is_local = false
		p.id = int(e.seat)
		p.display_name = str(e.name)
		p.start_hp = GameState.MAX_HP
		p.player_hp = int(e.hp)
		p.level = int(e.level)
		p.win_streak = int(e.get("win", 0))
		p.loss_streak = int(e.get("loss", 0))
		list.append(p)
	GameState.players = list
	Events.hp_changed.emit(GameState.me.player_hp)   # the standings redraw

# Where the last fight's copies of your units wait (hidden, still) so the damage meter can list them.
func _last_fight() -> Node3D:
	var holder := board.get_node_or_null("LastFight") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "LastFight"
		holder.visible = false
		holder.process_mode = Node.PROCESS_MODE_DISABLED
		board.add_child(holder)
	return holder

func _on_fight(desc: Dictionary) -> void:
	scout(-1)   # back to your own board for the fight
	if replaying:
		_end_replay()
	for n in _last_fight().get_children():
		n.free()
	my_side = "home" if int(desc.get("home", -1)) == client.seat else "away"
	Unit.viewer_team = 0 if my_side == "home" else 1
	sides = Arena.setup(board, desc, gm.roster, gm.item_roster, gm.unit_scene, true)
	_show_foe_bench(desc.get("away_bench" if my_side == "home" else "home_bench", []))
	board.set_view_flipped(my_side == "away")
	gm.snapshot.clear()
	for u in sides[my_side]:
		if u != null:
			gm.snapshot[u] = u.coord   # the damage meter lists your fighters
	replay_id = int(desc.get("id", -1))
	replaying = true
	Arena.set_kings(gm.runner, desc)
	for team in mini(board.kings.size(), 2):   # each side's king wears its player's skin
		board.kings[team].set_skin(StringName(str(desc.get("home_king" if team == 0 else "away_king", ""))))
	gm.runner.start()
	for input in client.inputs:
		Arena.schedule_input(gm.runner, sides, input, gm.item_roster)
	var at := int(desc.get("at_tick", 0))
	if at > 0:   # joined mid-fight: catch up at once
		Sfx.muted += 1
		while gm.runner.fighting and gm.runner.ticks < at:
			gm.runner.tick()
		Sfx.muted -= 1
	var foe := str(desc.get("away_name" if my_side == "home" else "home_name", ""))
	Events.opponent_announced.emit(foe)

func _on_input(fight_id: int, input: Dictionary) -> void:
	if replaying and fight_id == replay_id:
		Arena.schedule_input(gm.runner, sides, input, gm.item_roster)

# Our replay is over: the losing side leaves, the winners cheer (visual only; the server's result is what counts).
func _on_replay_finish(alive: Array, _stars: Array) -> void:
	gm.runner.stop()
	var mine := 0 if my_side == "home" else 1
	var we_won: bool = alive[1 - mine] == 0 and alive[mine] > 0
	for side in ["home", "away"]:
		for u in sides.get(side, []):
			if u == null or not is_instance_valid(u):
				continue
			var ours: bool = (side == "home") == (mine == 0)
			if not ours:
				u.leave_fight(not we_won)
			elif u.model_view != null and not u.dead:
				u.model_view.on_fight_over(we_won)

# The fight is over on the server (or we missed the end): finish it at once, clear it off the board
# and put the view back the right way round.
func _end_replay() -> void:
	if gm.runner.fighting:
		Sfx.muted += 1
		gm.runner.resolve()
		Sfx.muted -= 1
	replaying = false
	replay_id = -1
	sides = {}
	_show_foe_bench([])
	Unit.viewer_team = 0
	board.set_view_flipped(false)
	board.refresh_unlocks(GameState.me.level, false)

func _on_result(msg: Dictionary) -> void:
	for f in msg.get("fights", []):
		var home := int(f.home) == client.seat
		var away := int(f.away) == client.seat and not bool(f.ghost)
		if home or away:
			var won := str(f.winner) == ("home" if home else "away")
			Events.combat_ended.emit(won)

func _on_rejected(msg: Dictionary) -> void:
	match str(msg.get("why", "")):
		"limit":
			Events.board_limit_hit.emit()
		_:
			Sfx.play(&"error")
	if str(msg.get("of", "")) == LobbyProtocol.BUY:
		Events.shop_rolled.emit(GameState.me.shop_offers.duplicate())   # the slot that emptied itself comes back

func _on_over(msg: Dictionary) -> void:
	gm.game_over = true
	if replaying:
		_end_replay()
	_show_end(client.my_place(), true, int(msg.get("round", 0)))

func _on_lost(text: String) -> void:
	gm.game_over = true
	Telemetry.lobby_ended(0, 0)
	var es = gm.get_node_or_null("../UI/End Screen")
	if es != null and es.has_method("show_lobby"):
		es.show_lobby(0, 0, "DISCONNECTED", text)

func _show_end(place: int, over: bool, at_round := 0) -> void:
	var total: int = client.public.get("seats", []).size()
	Telemetry.lobby_ended(place, total)
	var es = gm.get_node_or_null("../UI/End Screen")
	var title := "VICTORY" if place == 1 else ("#%d" % place if place > 0 else "OUT")
	var text := "You placed %s of %d" % [_ordinal(place), total]
	if over and at_round > 0:
		text += "\nThe game ended in round %d-%d" % [GameState.stage_for(at_round), GameState.round_in_stage_for(at_round)]
	elif not over:
		text += "\nThe others play on"
	if es != null and es.has_method("show_lobby"):
		es.show_lobby(place, total, title, text)
	if place == 1:
		Sfx.play(&"win")
	else:
		Sfx.play(&"lose")

static func _ordinal(n: int) -> String:
	if n <= 0:
		return "?"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]

# --- matching the board to the server ------------------------------------------------------------

# Makes the board's own units (uid >= 0) match the server's list: same uids, stars, items, places.
# bench_only (during a fight): only the bench is touched; the board's tiles hold the fight.
func reconcile(entries: Array, bench_only: bool) -> void:
	var own := {}
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u == null or u.is_queued_for_deletion():
			continue
		if u.uid >= 0 and u.source_uid < 0 and u.team == 0:
			if not bench_only or board.bench.has(u):
				own[u.uid] = u
		elif not bench_only:
			n.get_parent().remove_child(n)   # fight copies and anything stale
			if gm.snapshot.has(n):
				_last_fight().add_child(n)   # your fighters stay for the damage meter until the next fight
			else:
				n.free()
	for u in own.values():
		board.detach(u)
	if not bench_only:
		for t in board.tiles.values():
			t.occupant = null
	for e in entries:
		if not e is Dictionary or (bench_only and not e.has("bench")):
			continue
		var d := EnemyBoard.lookup_unit(gm.roster, str(e.get("unit", "")))
		if d == null:
			continue
		var uid := int(e.get("uid", -1))
		var u: Unit = own.get(uid)
		own.erase(uid)
		if u == null:
			u = gm.unit_scene.instantiate() as Unit
			board.get_node("Units").add_child(u)
			u.uid = uid
			u.setup(d, 0)
		var star := clampi(int(e.get("star", 1)), 1, Unit.MAX_STAR)
		if u.star != star:
			u.set_star(star)
		var ids: Array = e.get("items", [])
		var stacks := EnemyBoard.stacks_in(e.get("stacks", {}))
		if ids != u.items.map(func(i): return String(i.id)) or stacks != u.item_stacks:
			var its: Array[ItemData] = []
			for id in ids:
				var it := EnemyBoard.lookup_item(gm.item_roster, StringName(str(id)))
				if it != null:
					its.append(it)
			u.set_items(its)
			u.item_stacks = stacks
			u._recalc_items()
		u.health = u.max_hp()
		if e.has("bench"):
			board.put_on_bench(u, clampi(int(e.bench), 0, Board.BENCH_SLOTS - 1))
		else:
			var c = e.get("coord", [-1, -1])
			board.put_on_tile(u, Vector2i(int(c[0]), int(c[1])))
	for u in own.values():   # sold, merged away
		board.get_node("Units").remove_child(u)
		u.free()

# The opponent's bench during a fight: display copies on the far bench (a FoeBench node, not in Units, so
# nothing fights, drags or counts them), facing you. [] clears it.
func _show_foe_bench(entries: Array) -> void:
	var old := board.get_node_or_null("FoeBench")
	if old != null:
		board.remove_child(old)
		old.queue_free()
	if entries.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "FoeBench"
	board.add_child(holder)
	for e in entries:
		var d := EnemyBoard.lookup_unit(gm.roster, str(e.get("unit", "")))
		if d == null:
			continue
		var u := gm.unit_scene.instantiate() as Unit
		holder.add_child(u)
		u.setup(d, 1 - Unit.viewer_team)   # the other side's colours, whichever side you watch from
		u.set_star(clampi(int(e.get("star", 1)), 1, Unit.MAX_STAR))
		u.position = board.enemy_bench_to_world(clampi(int(e.get("bench", 0)), 0, Board.BENCH_SLOTS - 1))
		u.rotation = Vector3(0.0, PI, 0.0)   # facing the camera, like your own bench

# --- scouting ------------------------------------------------------------------------------------

# Shows another player's board in place of yours (click their row in the standings), or yours again
# (seat -1 or your own; Space). Their units are display copies under a ScoutView node, so nothing can
# drag them or drop items on them; yours stay where they are, hidden. Not during your fight.
func scout(seat: int) -> void:
	if seat == client.seat or seat < 0 or replaying:
		if scouting < 0:
			return
		scouting = -1
		scouting_name = ""
		_scout_timer.stop()
		var view := board.get_node_or_null("ScoutView")
		if view != null:
			board.remove_child(view)
			view.queue_free()
		board.get_node("Units").visible = true
		board.refresh_unlocks(GameState.me.level, false)
		Events.hp_changed.emit(GameState.me.player_hp)   # the standings show whose board is up
		return
	scouting = seat
	client.scout(seat)
	_scout_timer.start()

# The scouted board arrived (again): rebuilt from scratch, it is only a handful of units.
func _on_board(msg: Dictionary) -> void:
	if int(msg.get("seat", -1)) != scouting or scouting < 0:
		return
	scouting_name = str(msg.get("name", ""))
	var old := board.get_node_or_null("ScoutView")
	if old != null:
		board.remove_child(old)
		old.free()
	var view := Node3D.new()
	view.name = "ScoutView"
	board.add_child(view)
	board.get_node("Units").visible = false
	for e in msg.get("units", []):
		var d := EnemyBoard.lookup_unit(gm.roster, str(e.get("unit", "")))
		if d == null:
			continue
		var u := gm.unit_scene.instantiate() as Unit
		view.add_child(u)
		u.setup(d, 0)
		u.set_star(clampi(int(e.get("star", 1)), 1, Unit.MAX_STAR))
		var its: Array[ItemData] = []
		for id in e.get("items", []):
			var it := EnemyBoard.lookup_item(gm.item_roster, StringName(str(id)))
			if it != null:
				its.append(it)
		u.set_items(its)
		u.health = u.max_hp()
		if e.has("bench"):
			u.position = board.bench_to_world(clampi(int(e.bench), 0, Board.BENCH_SLOTS - 1))
		else:
			var c = e.get("coord", [0, 0])
			u.position = board.grid_to_world(Vector2i(int(c[0]), int(c[1])))
		u.face_rest()
	board.refresh_unlocks(int(msg.get("level", 1)), false)
	Events.hp_changed.emit(GameState.me.player_hp)

# --- your requests -------------------------------------------------------------------------------

func buy(d: UnitData) -> void:
	var i := GameState.me.shop_offers.find(d)
	if i != -1:
		client.buy(i)

func reroll() -> void:
	client.reroll()
	Sfx.play(&"reroll")

func buy_xp() -> void:
	if GameState.me.is_max_level():
		Sfx.play(&"error")
		return
	client.buy_xp()
	Sfx.play(&"xp")

func lock(on: bool) -> void:
	client.lock(on)

func sell(u: Unit) -> void:
	if u != null and u.uid >= 0 and u.source_uid < 0:
		client.sell(u.uid)

# A drop on bench slot `bench_i` or tile `tile`: asked for; until the answer the unit goes back.
func move(u: Unit, bench_i: int, tile: Vector2i) -> void:
	if u == null or u.uid < 0:
		return
	var slot := board.bench.find(u)
	u.position = board.bench_local(slot) if slot != -1 else board.grid_to_world(u.coord)
	client.move(u.uid, bench_i, tile)

# An item onto one of your units: a bench or board unit, or (mid-fight) your unit's fighting copy.
func equip(u: Unit, item: ItemData) -> bool:
	var index := GameState.me.items.find(item)
	if u == null or index == -1:
		return false
	if u.get_parent() != board.get_node("Units"):
		return false   # a scouted player's unit
	var uid := u.uid
	if u.source_uid >= 0:
		if u.source_seat != client.seat:
			return false   # someone else's unit
		uid = u.source_uid
	if uid < 0:
		return false
	client.equip(uid, index)
	return true
