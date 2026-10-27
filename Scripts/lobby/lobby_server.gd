# lobby_server.gd
class_name LobbyServer extends Node

# The authoritative 2-8 player lobby: it owns every seat's PlayerState and board, the lobby-wide unit
# pool, the round timer, pairings, every fight and every result. Clients only ask (intents) and show
# what it tells them. It knows nothing about networking: messages come in through receive(peer, msg)
# and go out through `endpoint` (LobbyNet wires it to the in-process link and / or ENet); peer 0 is
# nobody (bots). The same server runs inside the game (offline vs bots, or hosting a LAN game) and as a
# dedicated headless server (`--server`). Protocol: lobby_protocol.gd.
#
# Rules: free play (39 rounds at most, shared pool, items, Tinker's Tongs), stage 1 against PvE waves
# and player-vs-player from round 4. With an odd number alive, one player fights a ghost (a copy of
# another player's board; only that player's result counts). Lost fights cost 5 HP per stage plus a
# quarter of the winner's standing stars; a draw (time out) costs both. Bots play the seats the host
# adds. A player who disconnects keeps their seat but nobody plays it: their board fights each round as
# they left it, with no shopping or leveling, until they rejoin (hello with their token).

signal changed   # lobby list, phase or results changed (the dedicated server prints it)

const MAX_SEATS := 8
const MAX_ROUNDS := 39
const PVE_ROUNDS := [1, 2, 3]

var prep_time := 30.0
var result_time := 4.0
var opening_time := 4.0   # round 1, the opening: a free unit each, the shop shut, the fight starts soon
var instant := false   # tests: fights resolve at once, no waiting between phases when nobody is human
var endpoint: Callable  # endpoint.call(peer: int, msg: Dictionary)

class Seat extends RefCounted:
	var index := 0
	var name := ""
	var peer := 0          # 0: no client (a bot, or a disconnected player)
	var bot := false       # a bot plays this seat (added by the host; a player who leaves stays a player)
	var added_bot := false # added as a bot (never had a player)
	var token := ""        # lets a disconnected player take the seat back
	var king: StringName = KingSkins.DEFAULT   # the king skin this player fights with (sent in hello; bots: the default)
	var arena: StringName = &""   # the arena this player picked (sent in hello; "" = random; arena_of resolves it)
	var player: PlayerState
	var board: Board
	var rules: PlayerRules
	var alive := true
	var place := 0         # final placement (1 = winner); 0 while alive
	var last_opponent := -1

var seats: Array = []          # Array[Seat]
var host_peer := 0             # who may add bots and start
var roster: Array[UnitData] = []
var item_roster: Array[ItemData] = []
var balance := ""
var pool: UnitPool
var rng := RandomNumberGenerator.new()   # pairings and PvE waves
var seed := 0
var phase := LobbyProtocol.PHASE_LOBBY
var round_number := 0
var timer := 0.0
var fights: Array = []         # this round's fights: {desc, board, runner, sides, done, result, inputs}
var last_results: Array = []   # the last round's fights, as sent in "result" (plus "spawned": units placed / described)
var _arenas: Array = []        # reusable [Board, CombatRunner]
var _fight_id := 0
var _unit_scene: PackedScene = preload("res://scenes/unit.tscn")
var enemy_base_scale := 0.4
var enemy_scale_per_round := 0.05

func _init():
	var r := LobbyProtocol.rosters()
	roster = r.units
	item_roster = r.items
	balance = LobbyProtocol.balance()
	enemy_base_scale = r.enemy_base_scale
	enemy_scale_per_round = r.enemy_scale_per_round

# --- messages ------------------------------------------------------------------------------------

func send(peer: int, msg: Dictionary) -> void:
	if peer != 0 and endpoint.is_valid():
		endpoint.call(peer, msg)

func send_seat(s: Seat, msg: Dictionary) -> void:
	if s.peer != 0:
		send(s.peer, msg)

func broadcast(msg: Dictionary) -> void:
	for s in seats:
		send_seat(s, msg)

func seat_of_peer(peer: int) -> Seat:
	for s in seats:
		if s.peer == peer and peer != 0:
			return s
	return null

func receive(peer: int, msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if t == LobbyProtocol.HELLO:
		_on_hello(peer, msg)
		return
	var s := seat_of_peer(peer)
	if s == null:
		return
	match t:
		LobbyProtocol.ADD_BOT:
			if peer == host_peer and phase == LobbyProtocol.PHASE_LOBBY:
				add_bot()
		LobbyProtocol.REMOVE_BOT:
			if peer == host_peer and phase == LobbyProtocol.PHASE_LOBBY:
				remove_bot(int(msg.get("seat", -1)))
		LobbyProtocol.START:
			if peer == host_peer and phase == LobbyProtocol.PHASE_LOBBY and seats.size() >= 2:
				start_game(int(msg.get("seed", 0)))
		LobbyProtocol.LEAVE:
			peer_left(peer)
		LobbyProtocol.SCOUT:
			_on_scout(s, int(msg.get("seat", -1)))
		_:
			if LobbyProtocol.INTENTS.has(t):
				_on_intent(s, msg)

func _on_hello(peer: int, msg: Dictionary) -> void:
	if int(msg.get("v", 0)) != LobbyProtocol.VERSION or str(msg.get("balance", "")) != balance:
		send(peer, {"t": LobbyProtocol.ERROR, "why": "version", "text": "This lobby runs a different version of the game."})
		return
	var token := str(msg.get("token", ""))
	if token != "":
		for s in seats:
			if s.token == token and s.peer == 0:   # a player coming back
				s.peer = peer
				_welcome(s)
				if phase != LobbyProtocol.PHASE_LOBBY:
					_catch_up(s)
				_broadcast_lobby()
				return
	if phase != LobbyProtocol.PHASE_LOBBY:
		send(peer, {"t": LobbyProtocol.ERROR, "why": "started", "text": "That game has already started."})
		return
	if seats.size() >= MAX_SEATS:
		send(peer, {"t": LobbyProtocol.ERROR, "why": "full", "text": "That lobby is full (8 players)."})
		return
	var s := _new_seat(LobbyProtocol.clean_name(str(msg.get("name", ""))), false)
	s.peer = peer
	var king := StringName(str(msg.get("king", "")))
	s.king = king if KingSkins.has(king) else KingSkins.DEFAULT
	var arena := StringName(str(msg.get("arena", "")))
	s.arena = arena if BoardThemes.has(arena) else &""
	s.token = "%x%x" % [rng.randi(), Time.get_ticks_usec()]
	if host_peer == 0:
		host_peer = peer
	_welcome(s)
	_broadcast_lobby()

func _welcome(s: Seat) -> void:
	send_seat(s, {"t": LobbyProtocol.WELCOME, "seat": s.index, "token": s.token, "host": s.peer == host_peer})

func _new_seat(seat_name: String, is_bot: bool) -> Seat:
	var s := Seat.new()
	s.index = seats.size()
	s.name = seat_name if seat_name != "" else "Player %d" % (s.index + 1)
	s.bot = is_bot
	s.added_bot = is_bot
	seats.append(s)
	return s

func add_bot() -> void:
	if seats.size() >= MAX_SEATS:
		return
	var n := 1 + seats.filter(func(x): return x.added_bot).size()
	_new_seat(LobbyProtocol.BOT_NAMES[(n - 1) % LobbyProtocol.BOT_NAMES.size()], true)
	_broadcast_lobby()

func remove_bot(index: int) -> void:
	if index < 0 or index >= seats.size() or not seats[index].added_bot:
		return
	seats.remove_at(index)
	for i in seats.size():
		seats[i].index = i
	for s in seats:
		_welcome(s)   # seat numbers moved
	_broadcast_lobby()

# A client went away (closed the game, lost the connection, left). Before the start its seat goes;
# during a game the seat stays, idle (its board still fights), until the player comes back.
func peer_left(peer: int) -> void:
	var s := seat_of_peer(peer)
	if s == null:
		return
	s.peer = 0
	if phase == LobbyProtocol.PHASE_LOBBY:
		seats.erase(s)
		for i in seats.size():
			seats[i].index = i
		for x in seats:
			_welcome(x)
	if peer == host_peer:
		host_peer = 0
		for x in seats:
			if x.peer != 0:
				host_peer = x.peer
				_welcome(x)
				break
	_broadcast_lobby()

func _broadcast_lobby() -> void:
	broadcast(lobby_info())
	changed.emit()

func lobby_info() -> Dictionary:
	var list := []
	for s in seats:
		list.append({"seat": s.index, "name": s.name, "bot": s.bot, "connected": s.peer != 0, "host": s.peer != 0 and s.peer == host_peer})
	return {"t": LobbyProtocol.LOBBY, "seats": list, "max": MAX_SEATS, "phase": phase}

# --- the game ------------------------------------------------------------------------------------

func humans() -> int:
	return seats.filter(func(s): return s.peer != 0).size()

func alive_seats() -> Array:
	return seats.filter(func(s): return s.alive)

func start_game(with_seed := 0) -> void:
	seed = with_seed if with_seed != 0 else (randi() | 1)
	rng.seed = hash([seed, "lobby"])
	pool = UnitPool.new(roster)
	for s in seats:
		var p := PlayerState.new()
		p.is_local = false   # server copies never touch the HUD
		p.id = s.index
		p.display_name = s.name
		p.rng.seed = hash([seed, s.index])
		p.start_hp = GameState.MAX_HP
		p.reset()
		s.player = p
		var b := Board.make(false)
		b.name = "Seat%d" % s.index
		b.visible = false
		s.board = b
		s.rules = PlayerRules.new(p, b, pool, roster, item_roster)
		add_child(b)
		b.position = Vector3(0, -1000.0 - 40.0 * s.index, 0)   # far out of sight and out of reach of the mouse
	broadcast({"t": LobbyProtocol.STARTED, "seed": seed, "seats": lobby_info().seats, "prep_time": prep_time})
	_begin_prep()

func _process(delta: float) -> void:
	match phase:
		LobbyProtocol.PHASE_PREP:
			timer -= delta
			if timer <= 0.0 or _no_wait():
				_begin_combat()
		LobbyProtocol.PHASE_RESULT:
			timer -= delta
			if timer <= 0.0 or _no_wait():
				_begin_prep()

func _no_wait() -> bool:
	return instant and humans() == 0

# Fights tick with the physics frame (60 a second), like a client's replay.
func _physics_process(_delta: float) -> void:
	if phase == LobbyProtocol.PHASE_COMBAT:
		tick_fights()

func tick_fights() -> void:
	if phase != LobbyProtocol.PHASE_COMBAT:
		return
	Sfx.muted += 1   # the server's fights are silent and invisible (in-game hosting shares the process)
	var vfx := Vfx.enabled
	Vfx.enabled = false
	for f in fights:
		if not f.done:
			f.runner.tick()
	Vfx.enabled = vfx
	Sfx.muted -= 1
	if fights.all(func(f): return f.done):
		_end_round()

func _begin_prep() -> void:
	round_number += 1
	phase = LobbyProtocol.PHASE_PREP
	var opening := round_number == 1
	timer = opening_time if opening else prep_time
	for s in alive_seats():
		if round_number > 1:
			s.rules.add_xp(2)
		s.rules.start_prep(round_number, opening, opening)
	for s in alive_seats():
		if s.bot:
			LobbyBot.take_turn(s.rules, round_number)
	broadcast(_phase_msg())
	for s in seats:
		send_seat(s, state_of(s))
	broadcast(public_info())
	changed.emit()

func _phase_msg() -> Dictionary:
	return {"t": LobbyProtocol.PHASE, "phase": phase, "round": round_number, "stage": GameState.stage_for(round_number),
		"in_stage": GameState.round_in_stage_for(round_number), "time": timer, "pve": PVE_ROUNDS.has(round_number)}

func _begin_combat() -> void:
	phase = LobbyProtocol.PHASE_COMBAT
	for s in alive_seats():
		s.rules.ready_board_for_fight()
	fights.clear()
	for pairing in _pairings():
		_start_fight(pairing[0], pairing[1], pairing[2])
	broadcast(_phase_msg())
	for s in seats:
		send_seat(s, state_of(s))   # auto-filled boards
	for f in fights:
		var desc: Dictionary = f.desc
		for seat_i in [int(desc.home), int(desc.away)]:
			if seat_i >= 0 and not (seat_i == int(desc.away) and bool(desc.ghost)):
				send_seat(seats[seat_i], {"t": LobbyProtocol.FIGHT, "fight": desc})
	# Fights nobody watches (bots only) are settled now; with `instant`, all of them.
	for f in fights:
		if instant or not _watched(f):
			_resolve(f)
	tick_fights()   # ends the round at once if every fight is settled
	changed.emit()

func _watched(f: Dictionary) -> bool:
	var d: Dictionary = f.desc
	if seats[int(d.home)].peer != 0:
		return true
	return int(d.away) >= 0 and not bool(d.ghost) and seats[int(d.away)].peer != 0

func _resolve(f: Dictionary) -> void:
	Sfx.muted += 1
	var vfx := Vfx.enabled
	Vfx.enabled = false
	while not f.done:
		f.runner.tick()
	Vfx.enabled = vfx
	Sfx.muted -= 1

# This round's pairs: [home Seat, away Seat or null (a PvE wave), ghost]. PvE rounds: everyone against a
# wave. Otherwise random pairs that avoid last round's opponent when they can; an odd one out fights a
# ghost of another player.
func _pairings() -> Array:
	var alive := alive_seats()
	var out := []
	if PVE_ROUNDS.has(round_number) or alive.size() < 2:
		for s in alive:
			out.append([s, null, false])
		return out
	var order := alive.duplicate()
	for i in range(order.size() - 1, 0, -1):   # Fisher-Yates with the lobby's RNG
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	while order.size() >= 2:
		var a: Seat = order.pop_front()
		var pick := 0
		for k in order.size():
			if order[k].index != a.last_opponent:
				pick = k
				break
		var b: Seat = order[pick]
		order.remove_at(pick)
		a.last_opponent = b.index
		b.last_opponent = a.index
		out.append([a, b, false])
	if order.size() == 1:
		var lone: Seat = order[0]
		var others := alive.filter(func(x): return x != lone)
		var copy: Seat = others[rng.randi_range(0, others.size() - 1)]
		out.append([lone, copy, true])
	return out

# The biome a seat's half of the board wears in fights (display only): its pick, else one from the seed.
func arena_of(s: Seat) -> StringName:
	return BoardThemes.for_seat(s.arena, seed, s.index)

func _start_fight(home: Seat, away: Seat, ghost: bool) -> void:
	_fight_id += 1
	var desc := {"id": _fight_id, "round": round_number, "home": home.index, "away": away.index if away != null else -1,
		"ghost": ghost, "home_name": home.name, "home_level": home.player.level,
		"home_king": String(home.king), "away_king": "", "away_level": home.player.level,
		"home_arena": String(arena_of(home)), "away_arena": String(arena_of(home)),
		"home_units": Arena.board_entries(home.board, false), "home_bench": Arena.bench_entries(home.board)}
	if away != null:
		desc["away_name"] = ("Ghost of %s" % away.name) if ghost else away.name
		desc["away_units"] = Arena.board_entries(away.board, true)
		desc["away_bench"] = Arena.bench_entries(away.board)   # shown to the home player on the far bench (display only)
		desc["away_king"] = String(away.king)
		desc["away_arena"] = String(arena_of(away))
		desc["away_level"] = away.player.level
		desc["enemy_open"] = Arena.mirrored_open(away.player.level, away.board)
		desc["away_scale"] = 1.0
		desc["away_synergies"] = true
	else:
		_pve_wave(desc, home)
	var arena := _arena(fights.size())
	var f := {"desc": desc, "board": arena[0], "runner": arena[1], "done": false, "result": {}, "inputs": []}
	f.sides = Arena.setup(arena[0], desc, roster, item_roster, _unit_scene)
	var runner: CombatRunner = arena[1]
	runner.on_finish = func(alive: Array, stars: Array):
		runner.stop()
		f.done = true
		f.result = Arena.result(f.sides, alive, stars)
	runner.gold_sink = func(team: int, amount: int):
		var seat_i := int(desc.home) if team == 0 else (-1 if bool(desc.ghost) else int(desc.away))
		if seat_i >= 0:
			seats[seat_i].player.gold += amount   # Pickpocket kills pay the thief's owner
	Arena.set_kings(runner, desc)
	runner.start()
	fights.append(f)

# A random PvE wave for stage 1 (like free play's random enemies): about as many units as the player
# fields, cheap ones, placed on the open enemy tiles by the lobby's RNG.
func _pve_wave(desc: Dictionary, home: Seat) -> void:
	var count := maxi(home.player.max_board_units(), 1)
	if rng.randf() < 0.3:
		count += 1 if rng.randf() < 0.5 else -1
	count = maxi(count, 1)
	var max_cost := 1 + int(round_number / 3.0)
	var options := roster.filter(func(x): return x != null and x.cost <= max_cost)
	if options.is_empty():
		options = roster
	var b := home.board
	var open: Array = b.enemy_order.slice(0, Board.tiles_open_for_level(home.player.level))
	var free := open.duplicate()
	for i in range(free.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = free[i]
		free[i] = free[j]
		free[j] = tmp
	var units := []
	for i in mini(count, free.size()):
		var d: UnitData = options[rng.randi_range(0, options.size() - 1)]
		var c: Vector2i = free[i]
		units.append({"uid": -1, "unit": d.display_name, "star": 1, "items": [], "coord": [c.x, c.y]})
	desc["away_name"] = "Wild creatures"
	desc["away_units"] = units
	desc["enemy_open"] = open.map(func(c): return [c.x, c.y])
	desc["away_scale"] = enemy_base_scale + enemy_scale_per_round * (round_number - 1)
	desc["away_synergies"] = false

func _arena(i: int) -> Array:
	while _arenas.size() <= i:
		var b := Board.make(false)
		b.name = "Arena%d" % _arenas.size()
		b.visible = false
		b.runner_credits_both = true
		add_child(b)
		b.position = Vector3(0, -3000.0 - 40.0 * _arenas.size(), 0)
		_arenas.append([b, CombatRunner.new(b)])
	return _arenas[i]

func _end_round() -> void:
	var stage := GameState.stage_for(round_number)
	var summary := []
	last_results = []
	for f in fights:
		var d: Dictionary = f.desc
		var r: Dictionary = f.result
		var home: Seat = seats[int(d.home)]
		var away: Seat = seats[int(d.away)] if int(d.away) >= 0 and not bool(d.ghost) else null
		var entry := {"id": int(d.id), "home": int(d.home), "away": int(d.away), "ghost": bool(d.ghost), "winner": r.winner, "home_damage": 0, "away_damage": 0,
			"ticks": f.runner.ticks}
		entry.home_damage = _apply_result(home, r.winner == "home", int(r.away_alive), stage, r.survivors.home)
		if away != null:
			entry.away_damage = _apply_result(away, r.winner == "away", int(r.home_alive), stage, r.survivors.away)
		summary.append(entry)
		var described: int = (d.home_units as Array).size() + (d.get("away_units", []) as Array).size()
		var placed: int = (f.sides.home + f.sides.away).filter(func(u): return u != null).size()
		last_results.append(entry.merged({"spawned": [placed, described]}))
		Arena.clear(f.board)
	fights.clear()
	_eliminate()
	var over := alive_seats().size() <= 1 or round_number >= MAX_ROUNDS
	if over:
		_finish()
	else:
		phase = LobbyProtocol.PHASE_RESULT
		timer = result_time
		broadcast({"t": LobbyProtocol.RESULT, "round": round_number, "fights": summary})
		broadcast(_phase_msg())
	for s in seats:
		send_seat(s, state_of(s))
	broadcast(public_info())
	changed.emit()

# Win: +1 gold; loss: damage. Streaks either way; survivors' bound items grow (and, on a win, their Ancient Sigil marks). Returns the damage taken.
func _apply_result(s: Seat, won: bool, foe_alive: int, stage: int, survivors: Array) -> int:
	s.player.record_result(won)
	for uid in survivors:
		var u := s.rules.unit_by_uid(int(uid))
		if u != null:
			u.grow_bound_items()
			if won:
				u.count_sigil_win()   # the Ancient Sigil: a 3-star that survives 8 wins ascends
	if won:
		s.player.gold += 1
		return 0
	var dmg := GameState.stage_damage(stage) + foe_alive   # the stage's base + 1 per enemy unit standing
	s.player.player_hp -= dmg
	return dmg

# Players at 0 HP are out: those going out together are placed by the HP they ended on.
func _eliminate() -> void:
	var out := alive_seats().filter(func(s): return s.player.player_hp <= 0)
	if out.is_empty():
		return
	var left := alive_seats().size() - out.size()
	out.sort_custom(func(a, b): return a.player.player_hp > b.player.player_hp)
	for i in out.size():
		out[i].alive = false
		out[i].place = left + 1 + i

func _finish() -> void:
	var standing := alive_seats()
	standing.sort_custom(func(a, b): return a.player.player_hp > b.player.player_hp)
	for i in standing.size():
		standing[i].place = i + 1
	phase = LobbyProtocol.PHASE_OVER
	var places := []
	for s in seats:
		places.append({"seat": s.index, "name": s.name, "place": s.place, "hp": maxi(s.player.player_hp, 0)})
	broadcast({"t": LobbyProtocol.OVER, "places": places, "round": round_number})

# --- what clients see ----------------------------------------------------------------------------

# A seat's own state (sent only to that seat).
func state_of(s: Seat) -> Dictionary:
	var p := s.player
	var units := []
	for u in s.board.all_player_units():
		var e := Arena.unit_entry(u, u.coord)
		var slot := s.board.bench.find(u)
		if slot != -1:
			e.erase("coord")
			e["bench"] = slot
		units.append(e)
	return {"t": LobbyProtocol.STATE, "seat": s.index, "gold": p.gold, "level": p.level, "xp": p.xp, "hp": p.player_hp,
		"start_hp": p.start_hp, "win": p.win_streak, "loss": p.loss_streak, "free_rerolls": p.free_rerolls, "opening": p.opening,
		"cheap": p.cheap_shop, "locked": p.shop_locked, "items": p.items.map(func(i): return String(i.id)),
		"recv": p.received, "recv_items": p.last_received.map(func(i): return String(i.id)),
		"offers": p.shop_offers.map(func(d): return d.display_name), "rolls": p.shop_rolls, "units": units, "alive": s.alive, "place": s.place}

# Everyone's public standing (sent to all).
func public_info() -> Dictionary:
	var list := []
	for s in seats:
		var p: PlayerState = s.player
		list.append({"seat": s.index, "name": s.name, "hp": maxi(p.player_hp, 0) if p != null else GameState.MAX_HP,
			"level": p.level if p != null else 1, "alive": s.alive, "place": s.place, "bot": s.bot, "connected": s.peer != 0,
			"win": p.win_streak if p != null else 0, "loss": p.loss_streak if p != null else 0})
	return {"t": LobbyProtocol.PUBLIC, "round": round_number, "seats": list}

# A player rejoining mid-game: the start, the phase, their state and (mid-fight) their fight so far.
func _catch_up(s: Seat) -> void:
	send_seat(s, {"t": LobbyProtocol.STARTED, "seed": seed, "seats": lobby_info().seats, "prep_time": prep_time})
	send_seat(s, _phase_msg())
	send_seat(s, state_of(s))
	send_seat(s, public_info())
	for f in fights:
		var d: Dictionary = f.desc
		if int(d.home) == s.index or (int(d.away) == s.index and not bool(d.ghost)):
			var late := d.duplicate()
			late["at_tick"] = f.runner.ticks
			late["inputs"] = f.inputs
			send_seat(s, {"t": LobbyProtocol.FIGHT, "fight": late})

# --- intents -------------------------------------------------------------------------------------

func _on_intent(s: Seat, msg: Dictionary) -> void:
	if not s.alive or not (phase == LobbyProtocol.PHASE_PREP or phase == LobbyProtocol.PHASE_COMBAT):
		_reject(s, msg, "not now")
		return
	var in_prep := phase == LobbyProtocol.PHASE_PREP
	var ok := false
	var t := str(msg.get("t", ""))
	match t:
		LobbyProtocol.BUY:
			var i := int(msg.get("offer", -1))
			if i >= 0 and i < s.player.shop_offers.size():
				ok = s.rules.buy(s.player.shop_offers[i], in_prep) != null
		LobbyProtocol.SELL:
			var u := s.rules.unit_by_uid(int(msg.get("uid", -1)))
			ok = u != null and (in_prep or u.coord.x < 0) and s.rules.sell(u)   # fighting units can't be sold
		LobbyProtocol.MOVE:
			var u := s.rules.unit_by_uid(int(msg.get("uid", -1)))
			var c = msg.get("tile", [-1, -1])
			var tile := Vector2i(int(c[0]), int(c[1])) if c is Array and c.size() == 2 else Vector2i(-1, -1)
			var res := s.rules.move(u, int(msg.get("bench", -1)), tile, in_prep) if u != null else "back"
			ok = res == "ok"
			if res == "limit":
				send_seat(s, {"t": LobbyProtocol.REJECT, "seq": msg.get("seq", 0), "why": "limit"})
		LobbyProtocol.REROLL:
			ok = s.rules.reroll()
		LobbyProtocol.BUY_XP:
			ok = s.rules.buy_xp()
		LobbyProtocol.LOCK:
			s.rules.set_locked(bool(msg.get("on", false)))
			ok = true
		LobbyProtocol.EQUIP:
			ok = _equip(s, msg, in_prep)
	if not ok and t != LobbyProtocol.MOVE:
		_reject(s, msg, "refused")
	send_seat(s, state_of(s))

# Scouting: another player's board as it stands (their units on their tiles and bench, and their level).
func _on_scout(s: Seat, other: int) -> void:
	if other < 0 or other >= seats.size() or seats[other].board == null:
		return
	var o: Seat = seats[other]
	var view := state_of(o)
	send_seat(s, {"t": LobbyProtocol.BOARD, "seat": other, "level": o.player.level, "units": view.units, "name": o.name})

func _reject(s: Seat, msg: Dictionary, why: String) -> void:
	send_seat(s, {"t": LobbyProtocol.REJECT, "seq": msg.get("seq", 0), "why": why, "of": msg.get("t", "")})

# Equips inventory item `item` (index) on unit `uid`. A unit fighting right now: its copy in the fight
# gets the item INPUT_DELAY ticks from now (sent to both players of that fight, who apply it at the same
# tick), and the unit keeps it after the fight. A copy that has already fallen: refused.
func _equip(s: Seat, msg: Dictionary, in_prep: bool) -> bool:
	var u := s.rules.unit_by_uid(int(msg.get("uid", -1)))
	var i := int(msg.get("item", -1))
	if u == null or i < 0 or i >= s.player.items.size():
		return false
	var item: ItemData = s.player.items[i]
	var fighting := not in_prep and u.coord.x >= 0
	if not fighting:
		return s.rules.equip(u, item, in_prep, false)
	if item.kind == &"remover" or not u.can_take(item):
		return false
	for f in fights:
		if f.done:
			continue
		var d: Dictionary = f.desc
		var side := ""
		if int(d.home) == s.index:
			side = "home"
		elif int(d.away) == s.index and not bool(d.ghost):
			side = "away"
		if side == "":
			continue
		var list: Array = f.sides[side]
		for k in list.size():
			var copy: Unit = list[k]
			if copy != null and is_instance_valid(copy) and copy.source_uid == u.uid:
				if copy.dead or not copy.can_take(item):
					return false
				if not s.rules.equip(u, item, false, false):
					return false
				var input := {"tick": f.runner.ticks + Arena.INPUT_DELAY, "side": side, "index": k, "item": String(item.id)}
				Arena.schedule_input(f.runner, f.sides, input, item_roster)
				f.inputs.append(input)
				for seat_i in [int(d.home), int(d.away)]:
					if seat_i >= 0 and not (seat_i == int(d.away) and bool(d.ghost)):
						send_seat(seats[seat_i], {"t": LobbyProtocol.INPUT, "fight": int(d.id), "input": input})
				return true
		return false
	return false
