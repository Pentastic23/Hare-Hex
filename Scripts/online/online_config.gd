# online_config.gd
class_name OnlineConfig extends RefCounted

# Where the online ghost service lives (async PvP, docs/online-ghosts.md). Empty = offline: async PvP
# plays against ghosts saved on this PC, as it always has.
#
# When the service is hosted, put its address here (https://, no trailing slash), e.g.
#   const SNAPSHOT_URL := "https://ghosts.example.com"
# and, if the server was started with --key, the same key in SNAPSHOT_KEY. That is all: nothing else in
# the game changes. The key is not a secret (anyone can read it out of the game); it only stops casual
# junk uploads.
const SNAPSHOT_URL := ""
const SNAPSHOT_KEY := ""

# Overrides, for testing a server before shipping its address (first match wins):
#   the command line:   Godot ... -- --snapshot-url http://127.0.0.1:8910 [--snapshot-key K]
#   user://online.cfg:  [snapshots] url="http://..."  key="..."   (also: enabled=false switches online off)
const CFG := "user://online.cfg"
const LOBBY_CFG := "user://lobby.cfg"   # the name typed on the Lobby screen names your ghosts too

static var url_override := ""   # tests set these; "" = use the sources above
static var key_override := ""
static var enabled := true      # false: always the local store (tests, and online.cfg's enabled=false)

static func snapshot_url() -> String:
	if not enabled:
		return ""
	var u := url_override
	if u == "":
		u = _arg("--snapshot-url")
	var cfg := _cfg()
	if u == "" and cfg != null:
		if not bool(cfg.get_value("snapshots", "enabled", true)):
			return ""
		u = str(cfg.get_value("snapshots", "url", ""))
	if u == "":
		u = SNAPSHOT_URL
	return u.strip_edges().trim_suffix("/")

static func snapshot_key() -> String:
	if key_override != "":
		return key_override
	var k := _arg("--snapshot-key")
	var cfg := _cfg()
	if k == "" and cfg != null:
		k = str(cfg.get_value("snapshots", "key", ""))
	return k if k != "" else SNAPSHOT_KEY

# Where the testers' telemetry goes (telemetry.gd): the ghost service above, unless overridden by
# `--telemetry-url`, user://online.cfg's [telemetry] url="...", or switched off there with enabled=false
# (events then stay queued on this PC). "" = nowhere yet.
static var telemetry_override := ""   # tests set this

static func telemetry_url() -> String:
	var u := telemetry_override
	if u == "":
		u = _arg("--telemetry-url")
	var cfg := _cfg()
	if u == "" and cfg != null:
		if not bool(cfg.get_value("telemetry", "enabled", true)):
			return ""
		u = str(cfg.get_value("telemetry", "url", ""))
	if u == "":
		u = snapshot_url()
	return u.strip_edges().trim_suffix("/")

static func is_online() -> bool:
	return snapshot_url() != ""

# The store a run records to and fetches ghosts from: online (with a local copy) when a service is set
# up, else this PC's files. `host` is a node in the run scene; online requests are its children.
static func make_store(host: Node) -> SnapshotStore:
	var local := LocalSnapshotStore.new()
	if not is_online():
		return local
	return HttpSnapshotStore.new(snapshot_url(), snapshot_key(), host, local)

# The name on your ghosts: the one from the Lobby screen, else "Player".
static func player_name() -> String:
	var cfg := ConfigFile.new()
	var n := ""
	if cfg.load(LOBBY_CFG) == OK:
		n = LobbyProtocol.clean_name(str(cfg.get_value("lobby", "name", "")))
	return n if n != "" else "Player"

static func _arg(flag: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(flag)
	return args[i + 1] if i != -1 and i + 1 < args.size() else ""

static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	return cfg if cfg.load(CFG) == OK else null
