# lobby_checks.gd
# Dev tool, not part of the game: checks 2-8 player lobbies (Scripts/lobby/): the server on its own (a
# seeded game of bots to the end, twice: the same game; the lobby-wide pool never loses or makes a
# copy), fights (a description set up on two boards, and on a turned-around visible one, with an item
# dropped mid-fight: the same fight), the rules the server enforces, a real offline game through the
# game scene (your board and the server's agree; your replay of each fight ends on the same tick as
# the server's), and real networking over ENet on this machine (host, a second client joining,
# starting, leaving and rejoining). Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/lobby_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end.

extends Node

class Driver extends Node:
	var fails := 0
	func chk(name: String, cond: bool, detail := ""):
		print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
		if not cond:
			fails += 1

	func frames(n := 1):
		for i in n:
			await get_tree().process_frame

	# Waits (frames) until cond() is true or `limit` frames pass; returns cond().
	func until(cond: Callable, limit := 3000) -> bool:
		var i := 0
		while not cond.call() and i < limit:
			await get_tree().process_frame
			i += 1
		return cond.call()

	func scene() -> Node:
		return get_tree().current_scene

	# --- helpers -----------------------------------------------------------------------------

	# A seeded lobby of `bots` bots played to the end, instantly. Returns [server, per-round log].
	func bot_game(seed: int, bots := 8) -> Array:
		var srv := LobbyServer.new()
		srv.instant = true
		add_child(srv)
		for i in bots:
			srv.add_bot()
		var log := []
		var pool_ok := [true, ""]
		srv.changed.connect(func():
			if srv.phase == LobbyProtocol.PHASE_PREP:
				var bad := _pool_problem(srv)
				if bad != "" and pool_ok[0]:
					pool_ok[0] = false
					pool_ok[1] = "round %d: %s" % [srv.round_number, bad]
			elif (srv.phase == LobbyProtocol.PHASE_RESULT or srv.phase == LobbyProtocol.PHASE_OVER) and not srv.last_results.is_empty():
				log.append([srv.round_number, srv.alive_seats().size(), srv.last_results.duplicate(true)])
				srv.last_results = []
		)
		srv.start_game(seed)
		await until(func(): return srv.phase == LobbyProtocol.PHASE_OVER, 4000)
		return [srv, log, pool_ok]

	# Copies of every unit: in the pool + in shops + on boards (by star) == the pool's size. "" if so.
	func _pool_problem(srv: LobbyServer) -> String:
		for key in srv.pool.remaining:
			var d: UnitData = key
			var n: int = srv.pool.remaining[d]
			for s in srv.seats:
				n += s.player.shop_offers.count(d)
				for u in s.board.all_player_units():
					if u.data == d:
						n += UnitPool.copies_in(u.star)
			if n != UnitPool.COPIES_PER_COST.get(d.cost, 0):
				return "%s: %d copies instead of %d" % [d.display_name, n, UnitPool.COPIES_PER_COST.get(d.cost, 0)]
		return ""

	func places(srv: LobbyServer) -> Array:
		return srv.seats.map(func(s): return s.place)

	# --- the checks --------------------------------------------------------------------------

	func run():
		var r := LobbyProtocol.rosters()
		print("--- the server on its own: 8 bots")
		var g1 := await bot_game(4242)
		var srv1: LobbyServer = g1[0]
		var log1: Array = g1[1]
		chk("a game of 8 bots plays to the end", srv1.phase == LobbyProtocol.PHASE_OVER and srv1.round_number > 5 and srv1.round_number <= LobbyServer.MAX_ROUNDS, "round %d" % srv1.round_number)
		var p1 := places(srv1)
		var sorted := p1.duplicate()
		sorted.sort()
		chk("everyone is placed 1st to 8th, once", sorted == [1, 2, 3, 4, 5, 6, 7, 8], str(p1))
		chk("the winner is the only one with HP left", srv1.seats.filter(func(s): return s.player.player_hp > 0).size() == 1 and srv1.seats.filter(func(s): return s.place == 1)[0].player.player_hp > 0)
		var pve_ok := log1.slice(0, 3).all(func(e): return e[2].size() == e[1] and e[2].all(func(f): return int(f.away) == -1))
		chk("stage 1 (rounds 1-3): everyone fights a PvE wave", pve_ok)
		var pvp_ok := true
		var ghosts_ok := true
		var spawn_ok := true
		var pair_ok := true
		for e in log1:
			var fights: Array = e[2]
			for f in fights:
				if int(f.spawned[0]) != int(f.spawned[1]):
					spawn_ok = false
			if int(e[0]) <= 3:
				continue
			var seen := {}   # who fought this round (those alive before it)
			for f in fights:
				for sd in [int(f.home), int(f.away)]:
					if sd >= 0 and not (sd == int(f.away) and bool(f.ghost)):
						if seen.has(sd):
							pair_ok = false
						seen[sd] = true
			if fights.any(func(f): return int(f.away) == -1):
				pvp_ok = false
			var ghosts := fights.filter(func(f): return bool(f.ghost)).size()
			if ghosts != seen.size() % 2:
				ghosts_ok = false
		chk("from round 4 every fight is player against player", pvp_ok)
		chk("nobody fights twice in a round", pair_ok)
		chk("an odd one out fights a ghost (and only then)", ghosts_ok)
		chk("every described unit is placed in every fight", spawn_ok)
		chk("the lobby-wide pool never loses or makes a copy", g1[2][0], g1[2][1])
		var g2 := await bot_game(4242)
		chk("the same seed plays the same game (placements and rounds)", places(g2[0]) == p1 and g2[0].round_number == srv1.round_number, "%s vs %s" % [places(g2[0]), p1])
		var g3 := await bot_game(777)
		chk("another seed plays another game", places(g3[0]) != p1 or g3[0].round_number != srv1.round_number)
		var g4 := await bot_game(99, 3)
		var three_ok := true
		var three_rounds := 0
		for e in g4[1]:
			var fs: Array = e[2]
			var real := fs.filter(func(f): return not bool(f.ghost)).size() * 2 + fs.filter(func(f): return bool(f.ghost)).size()
			if int(e[0]) > 3 and real == 3:
				three_rounds += 1
				if not fs.any(func(f): return bool(f.ghost)):
					three_ok = false
		chk("3 players: a ghost in every 3-player PvP round, still to the end", g4[0].phase == LobbyProtocol.PHASE_OVER and three_ok and three_rounds > 0, "%d rounds" % three_rounds)
		for g in [g1, g2, g3, g4]:
			g[0].queue_free()
		await frames(2)

		print("--- a fight: the same on every board")
		await _fight_checks(r)

		print("--- what the server allows")
		await _rule_checks(r)

		print("--- an offline game through the game scene (you + 7 bots)")
		await _offline_checks()

		print("--- over the network (ENet on this machine)")
		await _enet_checks()

		LobbyNet.leave()
		print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
		get_tree().quit()

	# Two boards: a seat with a mix of units and items, against a mirrored second board.
	func _fight_checks(r: Dictionary) -> void:
		var units: Array = r.units
		var items: Array = r.items
		var scene: PackedScene = load("res://scenes/unit.tscn")
		var home_b := Board.make(false)
		var away_b := Board.make(false)
		var p0 := PlayerState.new()
		p0.is_local = false
		p0.level = 6
		var p1 := PlayerState.new()
		p1.is_local = false
		p1.level = 6
		var pool := UnitPool.new(units)
		var r0 := PlayerRules.new(p0, home_b, pool, units, items)
		var r1 := PlayerRules.new(p1, away_b, pool, units, items)
		add_child(home_b)
		add_child(away_b)
		home_b.position = Vector3(0, -500, 0)
		away_b.position = Vector3(0, -600, 0)
		var picks := ["Knight", "Archer", "Mage", "Cleric", "Thief", "Guardian"]
		for i in picks.size():
			for pair in [[r0, home_b, i], [r1, away_b, picks.size() - 1 - i]]:
				var d := EnemyBoard.lookup_unit(units, picks[pair[2]])
				var u: Unit = pair[1].make_unit(d, scene)
				pair[1].put_on_tile(u, pair[1].open_player_tiles(6)[i])
				if i < 2:
					u.equip(items[i], false)
		var desc := {"id": 1, "round": 9, "home": 0, "away": 1, "ghost": false, "home_name": "A", "away_name": "B", "home_level": 6,
			"home_units": Arena.board_entries(home_b, false), "away_units": Arena.board_entries(away_b, true),
			"enemy_open": Arena.mirrored_open(6, away_b), "away_scale": 1.0, "away_synergies": true}
		desc = JSON.parse_string(JSON.stringify(desc))   # as it arrives over the network
		var input := {"tick": 30, "side": "home", "index": 2, "item": String(items[3].id)}
		var traces := []
		for k in 3:
			var b := Board.make(k == 2)
			add_child(b)
			if k < 2:
				b.position = Vector3(0, -700 - 100 * k, 0)
			var runner := CombatRunner.new(b)
			var sides := Arena.setup(b, desc, units, items, scene)
			if k == 2:
				b.set_view_flipped(true)   # the away player's view
				Unit.viewer_team = 1
			var done := [false, [], []]
			runner.on_finish = func(alive, stars):
				runner.stop()
				done[0] = true
				done[1] = alive
				done[2] = stars
			runner.start()
			Arena.schedule_input(runner, sides, input, items)
			var trace := []
			Sfx.muted += 1
			while not done[0]:
				runner.tick()
				if runner.ticks % 60 == 0:
					var hp := 0.0
					for side in ["home", "away"]:
						for u in sides[side]:
							hp += maxf(u.health, 0.0)
					trace.append(snappedf(hp, 0.001))
			Sfx.muted -= 1
			Unit.viewer_team = 0
			trace.append([runner.ticks, done[1], done[2], sides.home[2].items.map(func(i): return String(i.id))])
			traces.append(trace)
			Arena.clear(b)
			b.queue_free()
		chk("the fight is a real one (both sides placed, it ends)", traces[0].back()[0] > 10 and traces[0].back()[0] < CombatRunner.MAX_TICKS, str(traces[0].back()))
		chk("the item dropped at tick 30 reached its unit", (traces[0].back()[3] as Array).has(String(items[3].id)), str(traces[0].back()[3]))
		chk("two boards, one description: the same fight, second by second", traces[0] == traces[1], "%s\n  %s" % [traces[0].back(), traces[1].back()])
		chk("turned around for the away player: still the same fight", traces[0] == traces[2], "%s\n  %s" % [traces[0].back(), traces[2].back()])
		home_b.queue_free()
		away_b.queue_free()
		await frames(2)

	# A server with one fake network player (peer 5) and a bot; we read what it sends.
	func _rule_checks(r: Dictionary) -> void:
		var srv := LobbyServer.new()
		srv.prep_time = 9999.0
		add_child(srv)
		var inbox := []
		srv.endpoint = func(peer, msg):
			if peer == 5:
				inbox.append(msg)
		srv.receive(5, {"t": "hello", "v": 999, "balance": LobbyProtocol.balance(), "name": "Old"})
		chk("a different version is refused", inbox.size() == 1 and inbox[0].t == "error" and inbox[0].why == "version")
		inbox.clear()
		srv.receive(5, {"t": "hello", "v": LobbyProtocol.VERSION, "balance": LobbyProtocol.balance(), "name": "  Tester\u0007 "})
		chk("joining: a seat, a token and the host", inbox.size() >= 2 and inbox[0].t == "welcome" and int(inbox[0].seat) == 0 and bool(inbox[0].host) and str(inbox[0].token) != "")
		chk("names are cleaned (trimmed, no control characters)", srv.seats[0].name == "Tester", srv.seats[0].name)
		srv.receive(5, {"t": "start"})
		chk("the host can't start alone (2 or more)", srv.phase == LobbyProtocol.PHASE_LOBBY)
		srv.receive(5, {"t": "add_bot"})
		srv.receive(5, {"t": "start", "seed": 31337})
		chk("with a bot it starts", srv.phase == LobbyProtocol.PHASE_PREP and srv.round_number == 1)
		var me: LobbyServer.Seat = srv.seats[0]
		var last_state := func() -> Dictionary:
			for i in range(inbox.size() - 1, -1, -1):
				if inbox[i].t == "state":
					return inbox[i]
			return {}
		chk("you get your own state (gold, shop, units)", last_state.call().has("offers") and int(last_state.call().gold) == me.player.gold)
		me.player.gold = 0
		inbox.clear()
		srv.receive(5, {"t": "buy", "offer": 0, "seq": 1})
		chk("buying without the gold is refused", me.board.all_player_units().is_empty() and inbox.any(func(m): return m.t == "reject" and int(m.seq) == 1))
		srv.receive(5, {"t": "buy", "offer": 99, "seq": 2})
		chk("buying an offer that isn't there is refused", inbox.any(func(m): return m.t == "reject" and int(m.seq) == 2))
		me.player.gold = 50
		srv.receive(5, {"t": "buy", "offer": 0, "seq": 3})
		var u: Unit = me.board.all_player_units()[0] if not me.board.all_player_units().is_empty() else null
		chk("buying with gold works, onto the bench", u != null and me.board.bench.has(u) and u.uid >= 0)
		var open: Vector2i = me.board.open_player_tiles(me.player.level)[0]
		srv.receive(5, {"t": "move", "uid": u.uid, "bench": -1, "tile": [open.x, open.y], "seq": 4})
		chk("moving it onto an open tile works", u.coord == open)
		srv.receive(5, {"t": "move", "uid": u.uid, "bench": -1, "tile": [3, 1], "seq": 5})
		chk("the enemy half is out of bounds", u.coord == open)
		srv.receive(5, {"t": "sell", "uid": 424242, "seq": 6})
		chk("selling a unit you don't have is refused", inbox.any(func(m): return m.t == "reject" and int(m.seq) == 6))
		var bot_unit_count: int = srv.seats[1].board.all_player_units().size()
		srv.receive(5, {"t": "reroll", "seq": 7})
		srv.receive(5, {"t": "xp", "seq": 8})
		chk("reroll and Buy XP go through the shared rules", me.player.gold == 50 - u.data.cost - PlayerRules.REROLL_COST - PlayerRules.BUY_XP_COST, "gold %d" % me.player.gold)
		chk("nothing you do touches another seat", srv.seats[1].board.all_player_units().size() == bot_unit_count)
		# a fight: board units are fighting (their copies are), the bench is not
		srv._begin_combat()
		chk("the fight starts with your description sent to you", inbox.any(func(m): return m.t == "fight" and int(m.fight.home) == 0))
		srv.receive(5, {"t": "move", "uid": u.uid, "bench": 0, "tile": [-1, -1], "seq": 9})
		chk("mid-fight, fighting units can't be moved...", u.coord == open)
		srv.receive(5, {"t": "sell", "uid": u.uid, "seq": 10})
		chk("...or sold", is_instance_valid(u) and not u.is_queued_for_deletion())
		var item: ItemData = r.items[0]
		me.player.items.append(item)
		inbox.clear()
		srv.receive(5, {"t": "equip", "uid": u.uid, "item": 0, "seq": 11})
		var inp := inbox.filter(func(m): return m.t == "input")
		var f: Dictionary = srv.fights[0] if int(srv.fights[0].desc.home) == 0 else srv.fights[1]
		chk("an item onto a fighting unit: a timed input for its copy, sent to the fight's players", inp.size() == 1 and int(inp[0].input.tick) == f.runner.ticks + Arena.INPUT_DELAY and f.inputs.size() == 1)
		chk("and the unit keeps the item after the fight", u.items.has(item) and me.player.items.is_empty())
		srv.queue_free()
		await frames(2)

	func _offline_checks() -> void:
		LobbyNet.start_offline("Tester", 7)
		var srv: LobbyServer = LobbyNet.server
		srv.prep_time = 1.5
		srv.result_time = 0.5
		var ok := await until(func(): return scene() != null and scene().name == "Main" and scene().get_node("Game Manager").lobby != null and not LobbyNet.client.state.is_empty(), 600)
		chk("Play vs bots: straight into the game scene in lobby mode", ok and srv.seats.size() == 8 and srv.phase != LobbyProtocol.PHASE_LOBBY)
		if not ok:
			return
		await frames(3)
		var gm = scene().get_node("Game Manager")
		var board: Board = scene().get_node("Board")
		var c: LobbyClient = LobbyNet.client
		chk("eight players in the standings (you and seven bots)", GameState.players.size() == 8 and GameState.players.filter(func(p): return not p.is_local).all(func(p): return p.display_name != ""))
		chk("your shop shows the server's offers", GameState.me.shop_offers.size() == srv.seats[c.seat].player.shop_offers.size() and GameState.me.gold == srv.seats[c.seat].player.gold)
		# buy through the HUD's own signal, as a shop slot does
		await until(func(): return gm.phase == Events.Phase.PREP)
		var mine: LobbyServer.Seat = srv.seats[c.seat]
		var offer: UnitData = GameState.me.shop_offers[0]
		var before: int = mine.board.all_player_units().size()
		mine.player.gold = maxi(mine.player.gold, 20)
		srv.send_seat(mine, srv.state_of(mine))
		await frames(3)
		Events.unit_bought.emit(offer)
		await until(func(): return mine.board.all_player_units().size() > before, 30)
		await frames(3)
		chk("buying asks the server, and your board shows what it decided", mine.board.all_player_units().size() > before and _same_units(board, mine.board), _units_text(board) + " vs " + _units_text(mine.board))
		# fights: each of your replays ends on the server's tick
		var server_ticks := {}
		var client_ticks := {}
		var flips_ok := true
		var dropped := false
		srv.changed.connect(func():
			for e in srv.last_results:
				server_ticks[int(e.id)] = [int(e.ticks), e.winner])
		var input_seen := [false]
		c.input_received.connect(func(_id, _input): input_seen[0] = true)
		var rounds_seen := 0
		var last_round := -1
		var frames_left := 60 * 60 * 6
		while frames_left > 0 and rounds_seen < 5 and srv.phase != LobbyProtocol.PHASE_OVER and GameState.me.player_hp > 0:
			await get_tree().process_frame
			frames_left -= 1
			var lg: LobbyGame = gm.lobby
			if lg.replaying:
				if (board.view_flipped != (lg.my_side == "away")) or (Unit.viewer_team != (0 if lg.my_side == "home" else 1)):
					flips_ok = false
				if not dropped and gm.runner.fighting and gm.runner.ticks > 20 and int(c.fight.get("round", 0)) >= 4:
					var mine_side: Array = lg.sides[lg.my_side].filter(func(u): return u != null and not u.dead)
					if not mine_side.is_empty():
						var item: ItemData = load("res://tres/items/longsword.tres")
						mine.player.items.append(item)
						srv.send_seat(mine, srv.state_of(mine))
						await frames(2)
						var target: Unit = mine_side[0]
						if target.can_take(item) and lg.equip(target, item):
							dropped = true
				if not gm.runner.fighting and not client_ticks.has(lg.replay_id):
					client_ticks[lg.replay_id] = gm.runner.ticks
			if srv.round_number != last_round:
				last_round = srv.round_number
				rounds_seen += 1
		var compared := 0
		var same := true
		var detail := ""
		for id in client_ticks:
			if server_ticks.has(id):
				compared += 1
				if int(server_ticks[id][0]) != int(client_ticks[id]):
					same = false
					detail += " fight %d: server %d ticks, you %d" % [id, server_ticks[id][0], client_ticks[id]]
		chk("your replay of each fight ends on the server's tick (%d fights)" % compared, compared >= 2 and same, detail)
		chk("an item dropped on a fighting unit comes back as a timed input" + ("" if dropped else " (no fight to try it in)"), not dropped or input_seen[0])
		chk("from the away side the board is turned and your units are blue", flips_ok)
		await until(func(): return gm.phase == Events.Phase.PREP and not gm.lobby.replaying, 60 * 40)
		await frames(5)
		chk("after the fights your board is the server's again", _same_units(board, mine.board), _units_text(board) + " vs " + _units_text(mine.board))
		chk("your HP and gold are the server's", GameState.me.player_hp == mine.player.player_hp and GameState.me.gold == mine.player.gold)
		GameState.go_to_menu()   # leave: back to the menu, out of the lobby
		await until(func(): return scene() != null and scene().name != "Main", 120)
		chk("leaving goes back to the menu and closes the lobby", LobbyNet.mode == LobbyNet.Mode.NONE and LobbyNet.server == null and not LobbyNet.in_lobby())

	func _units_text(b: Board) -> String:
		var list := []
		for u in b.all_player_units():
			if u.source_uid < 0:
				list.append("%d:%s*%d@%s/%d" % [u.uid, u.data.display_name, u.star, u.coord, b.bench.find(u)])
		list.sort()
		return str(list)

	func _same_units(a: Board, b: Board) -> bool:
		return _units_text(a) == _units_text(b)

	func _enet_checks() -> void:
		var port := 7781
		var err := LobbyNet.host("Host", port)
		chk("hosting listens on a port", err == OK, error_string(err))
		if err != OK:
			return
		var srv: LobbyServer = LobbyNet.server
		srv.prep_time = 9999.0
		await until(func(): return srv.seats.size() == 1, 60)
		chk("the host has the first seat", srv.seats.size() == 1 and srv.seats[0].peer == LobbyNet.LOCAL_PEER and LobbyNet.client.host)
		# a second player: a raw ENet client speaking the protocol
		var other := ENetMultiplayerPeer.new()
		other.create_client("127.0.0.1", port)
		other.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
		var got := []
		var pump := func():
			other.poll()
			while other.get_available_packet_count() > 0:
				got.append(LobbyProtocol.decode(other.get_packet()))
		var connected := await until(func():
			pump.call()
			return other.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 600)
		chk("a second game connects over ENet", connected)
		if not connected:
			return
		other.set_target_peer(1)
		other.put_packet(LobbyProtocol.encode({"t": "hello", "v": LobbyProtocol.VERSION, "balance": LobbyProtocol.balance(), "name": "Guest", "token": ""}))
		var welcomed := await until(func():
			pump.call()
			return got.any(func(m): return m.get("t") == "welcome"), 600)
		var w: Dictionary = got.filter(func(m): return m.get("t") == "welcome")[0] if welcomed else {}
		chk("it gets seat 2 (not host) and a token", welcomed and int(w.seat) == 1 and not bool(w.host))
		await until(func(): return LobbyNet.client.lobby.get("seats", []).size() == 2, 120)
		chk("the host's lobby room shows both players", LobbyNet.client.lobby.get("seats", []).size() == 2)
		LobbyNet.client.start(555)
		var started := await until(func():
			pump.call()
			return got.any(func(m): return m.get("t") == "state"), 600)
		chk("the host starts: the guest gets the start, the phase and its state", started and got.any(func(m): return m.get("t") == "started") and got.any(func(m): return m.get("t") == "phase"))
		var guest_seat: LobbyServer.Seat = srv.seats[1]
		other.close()
		var dropped := await until(func(): return guest_seat.peer == 0, 600)
		chk("the guest drops out: the seat stays, not handed to a bot", dropped and not guest_seat.bot and srv.seats.size() == 2 and guest_seat.alive)
		var gold_before: int = guest_seat.player.gold
		var units_before: int = guest_seat.board.all_player_units().size()
		srv._begin_prep()   # a new PREP while it is away
		chk("an empty seat does nothing: no buying or leveling, it just collects its income", guest_seat.board.all_player_units().size() == units_before and guest_seat.player.gold > gold_before and guest_seat.player.shop_offers.size() > 0,
			"units %d -> %d, gold %d -> %d" % [units_before, guest_seat.board.all_player_units().size(), gold_before, guest_seat.player.gold])
		var back := ENetMultiplayerPeer.new()
		back.create_client("127.0.0.1", port)
		back.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
		got.clear()
		var pump2 := func():
			back.poll()
			while back.get_available_packet_count() > 0:
				got.append(LobbyProtocol.decode(back.get_packet()))
		await until(func():
			pump2.call()
			return back.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 600)
		back.set_target_peer(1)
		back.put_packet(LobbyProtocol.encode({"t": "hello", "v": LobbyProtocol.VERSION, "balance": LobbyProtocol.balance(), "name": "Guest", "token": str(w.token)}))
		var rejoined := await until(func():
			pump2.call()
			return got.any(func(m): return m.get("t") == "state"), 600)
		chk("with its token it takes its seat back, and catches up", rejoined and not guest_seat.bot and guest_seat.peer != 0 and got.any(func(m): return m.get("t") == "welcome" and int(m.seat) == 1))
		back.close()
		await frames(5)
		LobbyNet.leave()
		chk("leaving stops the server", LobbyNet.server == null and LobbyNet.peer == null)
		# a dedicated server (what `--server` runs): no client of its own
		err = LobbyNet.start_dedicated(port + 1)
		chk("a dedicated server listens and has no client", err == OK and LobbyNet.server != null and LobbyNet.client == null)
		LobbyNet.leave()

func _ready():
	var d := Driver.new()
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(d)
	d.ready.connect(d.run)
