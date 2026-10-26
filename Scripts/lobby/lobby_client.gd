# lobby_client.gd
class_name LobbyClient extends RefCounted

# The local player's side of a lobby: keeps the latest of everything the server said (so the game
# scene, which loads after "started", can catch up), and sends this player's requests. It never
# changes the game itself: GameManager's lobby mode (game_manager.gd, "lobby mode") listens to these
# signals and shows what the server decided. Messages: lobby_protocol.gd.

signal lobby_changed          # the room: seats, host, bots
signal welcomed               # we have a seat (and know if we host)
signal refused(text: String)  # the server wouldn't let us in
signal started                # the game began (LobbyNet loads the game scene)
signal phase_changed(msg: Dictionary)
signal state_changed(msg: Dictionary)
signal public_changed(msg: Dictionary)
signal fight_started(desc: Dictionary)
signal input_received(fight_id: int, input: Dictionary)
signal result_received(msg: Dictionary)
signal rejected(msg: Dictionary)
signal game_over(msg: Dictionary)
signal board_received(msg: Dictionary)   # a scouted player's board (scout())

var net   # LobbyNet
var name := ""
var seat := -1
var token := ""
var host := false
var lobby := {}       # last "lobby"
var phase := {}       # last "phase"
var state := {}       # last "state" (ours)
var public := {}      # last "public"
var fight := {}       # this round's fight description (cleared at the next PREP)
var inputs: Array = []   # inputs for `fight` received so far
var result := {}
var over := {}
var seed := 0
var prep_time := 30.0
var in_game := false
var _seq := 0

func _init(lobby_net, player_name: String):
	net = lobby_net
	name = LobbyProtocol.clean_name(player_name)

func say_hello() -> void:
	net.send_to_server({"t": LobbyProtocol.HELLO, "v": LobbyProtocol.VERSION, "balance": LobbyProtocol.balance(), "name": name, "token": token, "king": String(KingSkins.selected())})

func send(msg: Dictionary) -> void:
	_seq += 1
	msg["seq"] = _seq
	net.send_to_server(msg)

func on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		LobbyProtocol.WELCOME:
			seat = int(msg.seat)
			token = str(msg.token)
			host = bool(msg.host)
			welcomed.emit()
		LobbyProtocol.ERROR:
			refused.emit(str(msg.get("text", "The lobby refused to let you in.")))
		LobbyProtocol.LOBBY:
			lobby = msg
			lobby_changed.emit()
		LobbyProtocol.STARTED:
			seed = int(msg.get("seed", 0))
			prep_time = float(msg.get("prep_time", 30.0))
			lobby["seats"] = msg.get("seats", [])
			in_game = true
			over = {}
			started.emit()
		LobbyProtocol.PHASE:
			phase = msg
			if str(msg.phase) == LobbyProtocol.PHASE_PREP:
				fight = {}
				inputs.clear()
			phase_changed.emit(msg)
		LobbyProtocol.STATE:
			state = msg
			state_changed.emit(msg)
		LobbyProtocol.PUBLIC:
			public = msg
			public_changed.emit(msg)
		LobbyProtocol.FIGHT:
			fight = msg.get("fight", {})
			inputs = (fight.get("inputs", []) as Array).duplicate()
			fight_started.emit(fight)
		LobbyProtocol.INPUT:
			if int(msg.get("fight", -1)) == int(fight.get("id", -2)):
				inputs.append(msg.input)
			input_received.emit(int(msg.get("fight", -1)), msg.get("input", {}))
		LobbyProtocol.RESULT:
			result = msg
			result_received.emit(msg)
		LobbyProtocol.REJECT:
			rejected.emit(msg)
		LobbyProtocol.OVER:
			over = msg
			game_over.emit(msg)
		LobbyProtocol.BOARD:
			board_received.emit(msg)

# The room (host only).
func add_bot() -> void:
	send({"t": LobbyProtocol.ADD_BOT})

func remove_bot(seat_index: int) -> void:
	send({"t": LobbyProtocol.REMOVE_BOT, "seat": seat_index})

func start(with_seed := 0) -> void:
	send({"t": LobbyProtocol.START, "seed": with_seed})

# Requests (the server checks each one and answers with our new state).
func buy(offer_index: int) -> void:
	send({"t": LobbyProtocol.BUY, "offer": offer_index})

func sell(uid: int) -> void:
	send({"t": LobbyProtocol.SELL, "uid": uid})

func move(uid: int, bench: int, tile: Vector2i) -> void:
	send({"t": LobbyProtocol.MOVE, "uid": uid, "bench": bench, "tile": [tile.x, tile.y]})

func reroll() -> void:
	send({"t": LobbyProtocol.REROLL})

func buy_xp() -> void:
	send({"t": LobbyProtocol.BUY_XP})

func lock(on: bool) -> void:
	send({"t": LobbyProtocol.LOCK, "on": on})

# Asks for another player's board (the answer comes as board_received).
func scout(seat_index: int) -> void:
	net.send_to_server({"t": LobbyProtocol.SCOUT, "seat": seat_index})

func equip(uid: int, item_index: int) -> void:
	send({"t": LobbyProtocol.EQUIP, "uid": uid, "item": item_index})

# Seat entries of the room or the game, by seat.
func seat_info(i: int) -> Dictionary:
	for s in public.get("seats", lobby.get("seats", [])):
		if int(s.seat) == i:
			return s
	return {}

func my_place() -> int:
	for p in over.get("places", []):
		if int(p.seat) == seat:
			return int(p.place)
	return 0
