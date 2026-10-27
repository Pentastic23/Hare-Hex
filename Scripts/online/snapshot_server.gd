# snapshot_server.gd
class_name SnapshotServer extends Node

# The online ghost service for async PvP: a small HTTP server in the game itself, so the headless build
# that hosts lobbies can host ghosts too (docs/online-ghosts.md):
#   Godot --headless --path . -- --snapshot-server [--snapshot-port 8910] [--snapshot-data DIR] [--key K]
# Plain HTTP; put it behind a reverse proxy for HTTPS (the docs show Caddy). Any other backend that speaks
# the same three calls works as well:
#   GET  /v1/health                     {"ok": true, "service": "hare-hex-ghosts", "api": 1, "snapshots": n}
#   POST /v1/snapshots   (a snapshot)   201 {"id": "..."}   | 400 / 401 / 413 / 429 {"error": "..."}
#   GET  /v1/snapshots?round=9&level=7&balance=<hash>&exclude=<run>&limit=24
#                                       200 {"snapshots": [...]}: rounds 8-10, level <= 7, not that run,
#                                       today's balance first, then older ones; random order
#
# Every upload is checked against the game's own roster (units and items that exist, stars, item counts,
# tiles on the enemy half, no more units than the level allows) and cleaned (name, server time, an id), so
# junk can't reach other players. Snapshots are kept in memory and as one JSON file each under
# `data_dir`/round_NN/, at most MAX_PER_ROUND per round (the oldest go first).

const API := 1
const DEFAULT_PORT := 8910
const MAX_PER_ROUND := 400
const MAX_BODY := 32 * 1024
const MAX_LIMIT := 50
const REQUEST_TIMEOUT := 5.0   # seconds a client may take to send its request
const RATE := 60               # requests per minute per address
const POST_RATE := 20          # uploads per minute per address (a run uploads one per round)
const ENEMY_ROWS := 4         # a ghost stands on rows 0-3 (BoardSnapshot.mirror)

var port := DEFAULT_PORT
var data_dir := "user://snapshot_server"
var api_key := ""              # when set, uploads need the header X-Api-Key: <key>
var log_requests := true
var _tcp := TCPServer.new()
var _conns: Array = []         # {peer, buf, started, addr}
var _rounds := {}              # round -> Array of snapshots, oldest first
var _count := 0
var _rate := {}                # address -> {"t": minute, "n": requests, "p": posts}
var _units := {}               # display name -> UnitData (the roster uploads are checked against)
var _items := {}               # id -> ItemData
var _rng := RandomNumberGenerator.new()

# Starts listening; false if the port is taken.
func start(listen_port := DEFAULT_PORT, dir := "", key := "") -> bool:
	port = listen_port
	if dir != "":
		data_dir = dir
	api_key = key
	_load_roster()
	_load_store()
	_rng.randomize()
	var err := _tcp.listen(port, "*")
	if err != OK:
		push_error("Snapshot server: can't listen on port %d (%s)" % [port, error_string(err)])
		return false
	print("Snapshot server: listening on port %d, %d snapshots in %s%s" % [port, _count, ProjectSettings.globalize_path(data_dir), ", uploads need a key" if api_key != "" else ""])
	return true

func stop() -> void:
	for c in _conns:
		(c.peer as StreamPeerTCP).disconnect_from_host()
	_conns.clear()
	_tcp.stop()

func count() -> int:
	return _count

func _exit_tree() -> void:
	stop()

func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var p := _tcp.take_connection()
		_conns.append({"peer": p, "buf": PackedByteArray(), "started": Time.get_ticks_msec(), "addr": p.get_connected_host()})
	for c in _conns.duplicate():
		_poll(c)

func _poll(c: Dictionary) -> void:
	var p: StreamPeerTCP = c.peer
	p.poll()
	if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_conns.erase(c)
		return
	var n := p.get_available_bytes()
	if n > 0:
		var got := p.get_partial_data(n)
		if got[0] == OK:
			c.buf.append_array(got[1])
	var req := _parse(c.buf)
	if req.is_empty():
		if c.buf.size() > MAX_BODY + 8192:
			_reply(c, 413, {"error": "too large"})
		elif Time.get_ticks_msec() - int(c.started) > REQUEST_TIMEOUT * 1000.0:
			_reply(c, 408, {"error": "timed out"})
		return
	if req.has("error"):
		_reply(c, int(req.code), {"error": req.error})
		return
	var out: Array = handle(req.method, req.path, req.headers, req.body, str(c.addr))
	_reply(c, out[0], out[1])

# One HTTP request -> [status code, JSON body]. Separate from the socket code so tests can call it.
func handle(method: String, target: String, headers: Dictionary, body: String, addr := "local") -> Array:
	var path := target.get_slice("?", 0)
	var query := _query(target.get_slice("?", 1) if target.contains("?") else "")
	if method == "OPTIONS":
		return [204, null]
	if not _allow(addr, method == "POST"):
		return [429, {"error": "slow down"}]
	var out: Array
	match [method, path]:
		["GET", "/v1/health"]:
			out = [200, {"ok": true, "service": "hare-hex-ghosts", "api": API, "snapshots": _count}]
		["GET", "/v1/snapshots"]:
			out = [200, {"snapshots": find(int(query.get("round", "0")), int(query.get("level", "10")), str(query.get("balance", "")), str(query.get("exclude", "")), int(query.get("limit", "24")))}]
		["POST", "/v1/snapshots"]:
			if api_key != "" and str(headers.get("x-api-key", "")) != api_key:
				out = [401, {"error": "bad key"}]
			else:
				var parsed = JSON.parse_string(body)
				var problem := "not JSON" if not parsed is Dictionary else check(parsed)
				if problem != "":
					out = [400, {"error": problem}]
				else:
					out = [201, {"id": add(parsed)}]
		_:
			out = [404, {"error": "no such call"}]
	if log_requests:
		print("%s %s %s -> %d" % [addr, method, path, out[0]])
	return out

# --- the store ------------------------------------------------------------------------------------

# Candidates for a player at `level` in `round`: rounds round-1..round+1, at most `level`, never from
# `exclude` (the asking run). Today's balance first, then older ones, each group shuffled; at most `limit`.
func find(round: int, level: int, balance: String, exclude: String, limit: int) -> Array:
	limit = clampi(limit, 1, MAX_LIMIT)
	var same: Array = []
	var other: Array = []
	for r in [round, round - 1, round + 1]:
		for s in _rounds.get(r, []):
			if int(s.player_level) > level or str(s.run) == exclude:
				continue
			(same if balance == "" or str(s.balance) == balance else other).append(s)
	_shuffle(same)
	_shuffle(other)
	same.append_array(other)
	return same.slice(0, limit)

# "" when the snapshot may be stored, else what is wrong with it.
func check(s: Dictionary) -> String:
	if not BoardSnapshot.is_valid(s):
		return "not a snapshot (version %d)" % BoardSnapshot.VERSION
	var round := int(s.get("round", 0))
	var level := int(s.get("player_level", 0))
	if round < 1 or round > 999:
		return "round out of range"
	if level < 1 or level > GameState.XP_TABLE.size() + 1:
		return "level out of range"
	if int(s.get("trophies", 0)) < 0 or int(s.get("losses", 0)) < 0 or int(s.get("losses", 0)) > GameState.ASYNC_LIVES:
		return "trophies or losses out of range"
	var units: Array = s.board.units
	if units.size() > level:
		return "more units than the level allows"
	var tiles := {}
	for e in units:
		if not e is Dictionary or not _units.has(str(e.get("unit", ""))):
			return "unknown unit"
		var star := int(e.get("star", 1))
		if star < 1 or star > Unit.MAX_STAR:
			return "bad star"
		var c = e.get("coord", [])
		if not c is Array or c.size() != 2 or int(c[0]) < 0 or int(c[0]) >= Board.COLS or int(c[1]) < 0 or int(c[1]) >= ENEMY_ROWS:
			return "unit off the enemy half"
		var key := Vector2i(int(c[0]), int(c[1]))
		if tiles.has(key):
			return "two units on one tile"
		tiles[key] = true
		var its = e.get("items", [])
		if not its is Array or its.size() > 3:
			return "bad items"
		for id in its:
			if not _items.has(str(id)):
				return "unknown item"
	return ""

# Stores a checked snapshot; returns its id.
func add(raw: Dictionary) -> String:
	var s := {
		"version": BoardSnapshot.VERSION,
		"id": "%d-%06d" % [int(Time.get_unix_time_from_system()), _rng.randi() % 1000000],
		"balance": str(raw.balance).left(64),
		"created": int(Time.get_unix_time_from_system()),
		"run": str(raw.run).left(40),
		"round": int(raw.round),
		"stage": str(raw.get("stage", "")).left(8),
		"player_level": int(raw.player_level),
		"hp": clampi(int(raw.get("hp", 0)), 0, 999),
		"name": _clean_name(str(raw.name)),
		"board": _clean_board(raw.board),
	}
	if raw.has("trophies"):   # async PvP boards (free play ones have none)
		s["trophies"] = clampi(int(raw.trophies), 0, 9999)
		s["losses"] = clampi(int(raw.get("losses", 0)), 0, GameState.ASYNC_LIVES)
	if KingSkins.has(StringName(str(raw.get("king", "")))):   # the player's king skin (a look only)
		s["king"] = str(raw.king)
	var round: int = s.round
	if not _rounds.has(round):
		_rounds[round] = []
	_rounds[round].append(s)
	_count += 1
	var dir := "%s/round_%02d" % [data_dir, round]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open("%s/%s.json" % [dir, s.id], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(s))
		f.close()
	while _rounds[round].size() > MAX_PER_ROUND:
		var old: Dictionary = _rounds[round].pop_front()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s.json" % [dir, old.id]))
		_count -= 1
	return s.id

func _clean_board(b: Dictionary) -> Dictionary:
	var units: Array = []
	for e in b.units:
		var u := {"unit": str(e.unit), "star": int(e.get("star", 1)), "coord": [int(e.coord[0]), int(e.coord[1])], "items": (e.get("items", []) as Array).map(func(i): return str(i))}
		var stacks = e.get("stacks", {})
		if stacks is Dictionary and not stacks.is_empty():
			var clean := {}
			for k in stacks:
				if _items.has(str(k)):
					clean[str(k)] = clampi(int(stacks[k]), 0, 99)
			u["stacks"] = clean
		units.append(u)
	return {"name": _clean_name(str(b.get("name", ""))), "units": units}

static func _clean_name(raw: String) -> String:
	var n := LobbyProtocol.clean_name(raw)
	return n if n != "" else "Player"

func _load_store() -> void:
	_rounds.clear()
	_count = 0
	var root := ProjectSettings.globalize_path(data_dir)
	if not DirAccess.dir_exists_absolute(root):
		return
	for d in DirAccess.get_directories_at(root):
		if not d.begins_with("round_"):
			continue
		var files := Array(DirAccess.get_files_at(root + "/" + d)).filter(func(f): return f.ends_with(".json"))
		files.sort()   # ids start with the upload time: oldest first
		for f in files:
			var s = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/%s" % [root, d, f]))
			if s is Dictionary and BoardSnapshot.is_valid(s) and check(s) == "":
				var r := int(s.round)
				if not _rounds.has(r):
					_rounds[r] = []
				_rounds[r].append(s)
				_count += 1

# The roster uploads are checked against: every UnitData and ItemData in the game's tres folders.
func _load_roster() -> void:
	_units.clear()
	_items.clear()
	for dir in ["res://tres", "res://tres/units", "res://tres/items"]:
		for f in ResourceLoader.list_directory(dir):
			if not f.ends_with(".tres"):
				continue
			var r = load(dir + "/" + f)
			if r is UnitData:
				_units[(r as UnitData).display_name] = r
			elif r is ItemData:
				_items[String((r as ItemData).id)] = r

func _allow(addr: String, post: bool) -> bool:
	var minute := int(Time.get_unix_time_from_system() / 60.0)
	var e: Dictionary = _rate.get(addr, {})
	if int(e.get("t", -1)) != minute:
		e = {"t": minute, "n": 0, "p": 0}
		if _rate.size() > 10000:
			_rate.clear()
	e.n += 1
	if post:
		e.p += 1
	_rate[addr] = e
	return e.n <= RATE and e.p <= POST_RATE

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

# --- HTTP -----------------------------------------------------------------------------------------

# {} while the request is incomplete; {"error", "code"} for a bad one; else method, path, headers, body.
static func _parse(buf: PackedByteArray) -> Dictionary:
	var head_end := -1
	for i in range(maxi(buf.size() - 3, 0)):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			head_end = i
			break
	if head_end == -1:
		return {}
	var lines := buf.slice(0, head_end).get_string_from_utf8().split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"error": "bad request", "code": 400}
	var headers := {}
	for i in range(1, lines.size()):
		var at := lines[i].find(":")
		if at > 0:
			headers[lines[i].left(at).strip_edges().to_lower()] = lines[i].substr(at + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	if length > MAX_BODY:
		return {"error": "too large", "code": 413}
	var body_start := head_end + 4
	if buf.size() - body_start < length:
		return {}
	return {"method": first[0].to_upper(), "path": first[1], "headers": headers, "body": buf.slice(body_start, body_start + length).get_string_from_utf8()}

static func _query(q: String) -> Dictionary:
	var out := {}
	for pair in q.split("&", false):
		var kv := pair.split("=")
		out[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else ""
	return out

func _reply(c: Dictionary, code: int, body: Variant) -> void:
	var text := "" if body == null else JSON.stringify(body)
	var reason := {200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 408: "Request Timeout", 413: "Payload Too Large", 429: "Too Many Requests"}
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, X-Api-Key\r\n\r\n" % [code, reason.get(code, "Error"), text.to_utf8_buffer().size()]
	var p: StreamPeerTCP = c.peer
	p.put_data((head + text).to_utf8_buffer())
	p.disconnect_from_host()
	_conns.erase(c)
