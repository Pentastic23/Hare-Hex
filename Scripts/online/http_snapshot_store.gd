# http_snapshot_store.gd
class_name HttpSnapshotStore extends SnapshotStore

# Async PvP against other players' ghosts: boards go up to the online ghost service and ghosts come down
# from it (protocol: docs/online-ghosts.md; a ready server: snapshot_server.gd). Made by
# OnlineConfig.make_store() when an address is set.
#
# The game asks for a ghost synchronously when PREP starts (SnapshotOpponents.prepare), so ghosts are
# fetched ahead of time: `prefetch(round)` asks the service for a batch of candidates near that round and
# keeps them; `fetch` picks from what has arrived. Everything is also written to a LocalSnapshotStore,
# and `fetch` falls back to it, so a slow or unreachable service never stops a run: you meet local
# ghosts (or random enemies) instead. When a batch arrives `fetched(round)` is emitted, and the provider
# may swap a local stand-in for an online ghost while PREP is still on.

const BATCH := 24          # candidates asked for per round
const TIMEOUT := 8.0       # seconds per request
const OUTBOX_MAX := 10     # uploads that failed, kept to retry with the next one

var base_url := ""
var api_key := ""
var host: Node             # requests are HTTPRequest children of this node (the run's GameManager)
var local: LocalSnapshotStore
var status := ""           # "" (nothing asked yet), "ok", or "offline: <why>"
var _cache := {}           # round asked for -> Array of snapshots from the service
var _asking := {}          # round -> true while its request is out
var _outbox: Array = []    # snapshots whose upload failed
var sent := 0              # uploads the service accepted (tests)

func _init(url: String, key: String, request_host: Node, local_store: LocalSnapshotStore = null):
	base_url = url.trim_suffix("/")
	api_key = key
	host = request_host
	local = local_store if local_store != null else LocalSnapshotStore.new()

func submit(snapshot: Dictionary) -> void:
	if not BoardSnapshot.is_valid(snapshot):
		return
	local.submit(snapshot)   # your own later runs can meet it even offline
	var retry := _outbox.duplicate()
	_outbox.clear()
	for s in retry:
		_post(s)
	_post(snapshot)

func prefetch(round: int, player_level: int, balance: String, exclude_run := "") -> void:
	if round < 1 or _cache.has(round) or _asking.has(round):
		return
	_asking[round] = true
	# A level or two of headroom: the player may level up before that round's PREP; choose() filters exactly.
	var query := "round=%d&level=%d&balance=%s&exclude=%s&limit=%d" % [round, player_level + 2, balance.uri_encode(), exclude_run.uri_encode(), BATCH]
	_request("/v1/snapshots?" + query, HTTPClient.METHOD_GET, "", func(code: int, body: Variant):
		_asking.erase(round)
		if code != 200 or not body is Dictionary or not body.get("snapshots") is Array:
			_fail("ghosts for round %d: %s" % [round, _why(code, body)])
			return
		var list: Array = []
		for s in body.snapshots:
			if s is Dictionary and BoardSnapshot.is_valid(s):
				s["_online"] = true
				list.append(s)
		_cache[round] = list
		status = "ok"
		fetched.emit(round))

func fetch(round: int, player_level: int, balance: String, rng: RandomNumberGenerator, exclude_run := "", accept := Callable()) -> Dictionary:
	var candidates: Array = []
	var seen := {}
	for r in [round, round - 1, round + 1]:   # batches asked for neighbouring rounds overlap
		for s in _cache.get(r, []):
			var id := str(s.get("id", ""))
			if id != "" and seen.has(id):
				continue
			seen[id] = true
			candidates.append(s)
	var pick := SnapshotStore.choose(candidates, round, player_level, balance, rng, exclude_run, accept)
	if pick.is_empty():
		pick = local.fetch(round, player_level, balance, rng, exclude_run, accept)
	return pick

# True once the service has answered for `round` (tests).
func has_batch(round: int) -> bool:
	return _cache.has(round)

func _post(snapshot: Dictionary) -> void:
	var clean := snapshot.duplicate(true)
	clean.erase("_online")
	_request("/v1/snapshots", HTTPClient.METHOD_POST, JSON.stringify(clean), func(code: int, body: Variant):
		if code == 200 or code == 201:
			sent += 1
			status = "ok"
		elif code == 0 or code == 429 or code >= 500:   # unreachable or busy: try again with the next upload
			if _outbox.size() < OUTBOX_MAX:
				_outbox.append(clean)
			_fail("upload: " + _why(code, body))
		else:   # 400 / 401 / 413: the service turned it down; sending it again won't help
			_fail("upload refused: " + _why(code, body)))

# One request; `done(code, parsed_json_or_null)` runs when it ends (code 0 = no answer at all).
func _request(path: String, method: int, body: String, done: Callable) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		done.call(0, null)
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	host.add_child(req)
	var headers := PackedStringArray(["Accept: application/json"])
	if body != "":
		headers.append("Content-Type: application/json")
	if api_key != "":
		headers.append("X-Api-Key: " + api_key)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray):
		req.queue_free()
		var parsed = JSON.parse_string(data.get_string_from_utf8()) if data.size() > 0 else null
		done.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, parsed))
	var err := req.request(base_url + path, headers, method, body)
	if err != OK:
		req.queue_free()
		done.call(0, null)

func _fail(why: String) -> void:
	status = "offline: " + why
	if DisplayServer.get_name() != "headless":
		push_warning("Online ghosts: " + why)

static func _why(code: int, body: Variant) -> String:
	if code == 0:
		return "no answer"
	if body is Dictionary and body.has("error"):
		return "%d %s" % [code, str(body.error)]
	return "HTTP %d" % code
