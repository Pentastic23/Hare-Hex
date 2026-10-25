# lobby_net.gd  (autoload "LobbyNet")
extends Node

# Where the lobby lives and how its messages travel. One of:
#   OFFLINE    you + bots: a LobbyServer in this game, your client talks to it in-process.
#   HOST       a LAN game: the LobbyServer runs in this game and listens on ENet; your client is
#              in-process (peer 1), everyone else connects over the network.
#   CLIENT     you joined someone's game (LAN now, a hosted server later) over ENet.
#   DEDICATED  `--server [--port N]` on a headless build: a LobbyServer listening on ENet, no client.
# Messages are LobbyProtocol dictionaries, JSON over a MultiplayerPeer's raw packets (reliable, in
# order), polled here: no RPCs and no node paths, so the scene can change freely and any
# MultiplayerPeer works. WebSocketMultiplayerPeer has the same API: a web build (or a server behind
# TLS) swaps it in at _make_peer().
#
# The local client is `client` (LobbyClient); the game scene reads it in lobby mode (GameManager.lobby).

enum Mode { NONE, OFFLINE, HOST, CLIENT, DEDICATED }

signal joined                 # this client has a seat (welcome)
signal failed(text: String)   # couldn't connect or join; back to the menu
signal lost(text: String)     # the connection dropped mid-game

const LOCAL_PEER := 1   # the in-process client's peer id on its own server (ENet's server id is 1 too; it never sends to itself)
const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

var mode := Mode.NONE
var server: LobbyServer
var client: LobbyClient
var peer: MultiplayerPeer
var _to_server: Array = []   # the local client's messages, delivered next frame (as over a network)
var _to_client: Array = []
var _last_status := MultiplayerPeer.CONNECTION_DISCONNECTED
var port := LobbyProtocol.DEFAULT_PORT

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS   # a LAN game never stops for one player's pause menu
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		var p := LobbyProtocol.DEFAULT_PORT
		var i := args.find("--port")
		if i != -1 and i + 1 < args.size():
			p = int(args[i + 1])
		start_dedicated.call_deferred(p)

func in_lobby() -> bool:
	return mode != Mode.NONE and client != null

# Can the game pause? Only offline (nobody else is waiting on you).
func can_pause() -> bool:
	return mode == Mode.NONE or mode == Mode.OFFLINE

# --- starting and leaving ------------------------------------------------------------------------

func start_offline(player_name: String, bots := 7) -> void:
	leave()
	mode = Mode.OFFLINE
	_make_server()
	server.process_mode = Node.PROCESS_MODE_PAUSABLE   # offline, the pause menu stops the whole lobby
	_make_client(player_name)
	for i in clampi(bots, 1, LobbyServer.MAX_SEATS - 1):
		_to_server.append({"t": LobbyProtocol.ADD_BOT})
	_to_server.append({"t": LobbyProtocol.START})   # after our hello (queued first), so we are the host

func host(player_name: String, listen_port := LobbyProtocol.DEFAULT_PORT) -> Error:
	leave()
	var p := _make_peer()
	var err := (p as ENetMultiplayerPeer).create_server(listen_port, LobbyServer.MAX_SEATS - 1)
	if err != OK:
		return err
	port = listen_port
	mode = Mode.HOST
	_attach_peer(p)
	_make_server()
	_make_client(player_name)
	return OK

func join(player_name: String, address: String, join_port := LobbyProtocol.DEFAULT_PORT, token := "") -> Error:
	leave()
	var p := _make_peer()
	var err := (p as ENetMultiplayerPeer).create_client(address, join_port)
	if err != OK:
		return err
	port = join_port
	mode = Mode.CLIENT
	_attach_peer(p)
	client = LobbyClient.new(self, player_name)
	client.token = token
	_hook_client()
	_last_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK

func start_dedicated(listen_port := LobbyProtocol.DEFAULT_PORT) -> Error:
	leave()
	var p := _make_peer()
	var err := (p as ENetMultiplayerPeer).create_server(listen_port, LobbyServer.MAX_SEATS)
	if err != OK:
		printerr("LobbyNet: can't listen on port %d (%s)" % [listen_port, error_string(err)])
		return err
	port = listen_port
	mode = Mode.DEDICATED
	_attach_peer(p)
	_make_server()
	server.changed.connect(func(): print("[lobby] %s round %d, %d seats, %d connected" % [server.phase, server.round_number, server.seats.size(), server.humans()]))
	print("Hare & Hex lobby server listening on port %d" % listen_port)
	return OK

# Leaves whatever lobby this game is in (tells the server first) and stops serving.
func leave() -> void:
	if client != null and mode == Mode.CLIENT and peer != null:
		_send_peer(1, {"t": LobbyProtocol.LEAVE})   # (the server also notices the disconnect itself)
		var enet := peer as ENetMultiplayerPeer
		if enet != null and enet.host != null:
			enet.host.flush()
	if peer != null:
		peer.close()
	peer = null
	if server != null:
		server.queue_free()
	server = null
	client = null
	_to_server.clear()
	_to_client.clear()
	mode = Mode.NONE
	Unit.viewer_team = 0

# Back to the main menu, out of the lobby.
func quit_to_menu() -> void:
	leave()
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func _make_peer() -> MultiplayerPeer:
	return ENetMultiplayerPeer.new()

func _attach_peer(p: MultiplayerPeer) -> void:
	peer = p
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.transfer_channel = 0
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)

func _make_server() -> void:
	server = LobbyServer.new()
	server.name = "LobbyServer"
	server.endpoint = _server_send
	add_child(server)

func _make_client(player_name: String) -> void:
	client = LobbyClient.new(self, player_name)
	_hook_client()
	client.say_hello()

func _hook_client() -> void:
	client.started.connect(_on_started)
	client.welcomed.connect(func(): joined.emit())
	client.refused.connect(func(text: String):
		failed.emit(text)
		leave())

# The game begins: load the game scene (GameManager sees LobbyNet.in_lobby() and plays it as a lobby client).
func _on_started() -> void:
	get_tree().paused = false
	GameState.change_to_run.call_deferred()   # the game scene, usually preloaded on the menu (Preload)

# --- moving messages -----------------------------------------------------------------------------

# The local client's way out.
func send_to_server(msg: Dictionary) -> void:
	if mode == Mode.OFFLINE or mode == Mode.HOST:
		_to_server.append(msg)
	elif mode == Mode.CLIENT:
		_send_peer(1, msg)

# The server's way out (LobbyServer.endpoint).
func _server_send(to_peer: int, msg: Dictionary) -> void:
	if to_peer == LOCAL_PEER and (mode == Mode.OFFLINE or mode == Mode.HOST):
		_to_client.append(msg)
	else:
		_send_peer(to_peer, msg)

func _send_peer(to_peer: int, msg: Dictionary) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	peer.set_target_peer(to_peer)
	peer.put_packet(LobbyProtocol.encode(msg))

func _on_peer_connected(_id: int) -> void:
	pass   # a client says hello first; until then it has no seat

func _on_peer_disconnected(id: int) -> void:
	if server != null:
		server.peer_left(id)

func _process(_delta: float) -> void:
	if peer != null:
		peer.poll()
		if mode == Mode.CLIENT:
			_watch_connection()
		while peer != null and peer.get_available_packet_count() > 0:
			var from := peer.get_packet_peer()
			var msg := LobbyProtocol.decode(peer.get_packet())
			if msg.is_empty():
				continue
			if mode == Mode.CLIENT:
				if client != null:
					client.on_message(msg)
			elif server != null:
				server.receive(from, msg)
	# In-process messages: one frame late, as over a network (and never re-entrant).
	var up := _to_server
	_to_server = []
	for m in up:
		if server != null:
			server.receive(LOCAL_PEER, m)
	var down := _to_client
	_to_client = []
	for m in down:
		if client != null:
			client.on_message(m)

func _watch_connection() -> void:
	var st := peer.get_connection_status()
	if st == _last_status:
		return
	var was := _last_status
	_last_status = st
	if st == MultiplayerPeer.CONNECTION_CONNECTED and client != null:
		client.say_hello()
	elif st == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if was == MultiplayerPeer.CONNECTION_CONNECTING:
			failed.emit("Couldn't reach that game. Check the address and that the host is in its lobby.")
		else:
			lost.emit("The connection to the game was lost.")
