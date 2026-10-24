# lobby_protocol.gd
class_name LobbyProtocol extends RefCounted

# The lobby's messages: plain Dictionaries with a "t" (type) key, sent as JSON text (lobby_net.gd), so
# a server written in anything else could speak it later. Numbers arrive as floats: read them with
# int(). Bump VERSION whenever a message changes shape; a client and a server only talk when VERSION
# and the balance hash (BoardSnapshot.balance_hash: unit and item stats) match.
#
# Client -> server
#   hello {v, balance, name, token}   join (token: rejoin your seat after a disconnect; "" otherwise)
#   add_bot {} / remove_bot {seat} / start {seed?}   the host, in the lobby room
#   leave {}
#   intents, during PREP (and bench-only during a fight), each with a client "seq":
#     buy {offer: shop index}  sell {uid}  move {uid, bench: slot or -1, tile: [x, y]}
#     reroll {}  xp {}  lock {on}  equip {uid, item: inventory index}
# Server -> client
#   welcome {seat, token, host}       your seat (sent again if it changes)
#   error {why, text}                 refused to join (version, full, started)
#   lobby {seats: [{seat, name, bot, connected, host}], max, phase}
#   started {seed, seats, prep_time}  the game begins: load the game scene
#   phase {phase, round, stage, in_stage, time, pve}
#   state {...}                       your own state (LobbyServer.state_of): gold, level, xp, hp, streaks,
#                                     items, shop offers, lock, units (uid, unit, star, items, stacks, coord or bench)
#   public {round, seats: [{seat, name, hp, level, alive, place, bot, connected}]}
#   fight {fight: description}        your fight (arena.gd); "at_tick" / "inputs" when joining late
#   input {fight, input: {tick, side, index, item}}   an item dropped onto a fighting unit
#   result {round, fights: [{id, home, away, ghost, winner, home_damage, away_damage}]}
#   reject {seq, why, of}             an intent that wasn't allowed (your state follows anyway)
#   over {places: [{seat, name, place, hp}], round}

const VERSION := 1
const DEFAULT_PORT := 7777

const HELLO := "hello"
const ADD_BOT := "add_bot"
const REMOVE_BOT := "remove_bot"
const START := "start"
const LEAVE := "leave"
const BUY := "buy"
const SELL := "sell"
const MOVE := "move"
const REROLL := "reroll"
const BUY_XP := "xp"
const LOCK := "lock"
const EQUIP := "equip"
const INTENTS := [BUY, SELL, MOVE, REROLL, BUY_XP, LOCK, EQUIP]

const WELCOME := "welcome"
const ERROR := "error"
const LOBBY := "lobby"
const STARTED := "started"
const PHASE := "phase"
const STATE := "state"
const PUBLIC := "public"
const FIGHT := "fight"
const INPUT := "input"
const RESULT := "result"
const REJECT := "reject"
const OVER := "over"

const PHASE_LOBBY := "lobby"
const PHASE_PREP := "prep"
const PHASE_COMBAT := "combat"
const PHASE_RESULT := "result"
const PHASE_OVER := "over"

const BOT_NAMES := ["Bramble", "Thistle", "Clover", "Juniper", "Hazel", "Sorrel", "Fennel", "Tansy"]
const NAME_MAX := 16

static func encode(msg: Dictionary) -> PackedByteArray:
	return JSON.stringify(msg).to_utf8_buffer()

static func decode(bytes: PackedByteArray) -> Dictionary:
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}

# A display name as the lobby shows it: printable, trimmed, at most NAME_MAX characters.
static func clean_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.unicode_at(0) >= 32 and out.length() < NAME_MAX:
			out += ch
	return out

# This build's balance hash (BoardSnapshot.balance_hash of the rosters): client and server must agree.
static var _balance := ""
static func balance() -> String:
	if _balance == "":
		var r := rosters()
		_balance = BoardSnapshot.balance_hash(r.units, r.items)
	return _balance

# The game's unit and item rosters, read from main.tscn's Game Manager (the server has no game scene).
static var _rosters := {}
static func rosters() -> Dictionary:
	if not _rosters.is_empty():
		return _rosters
	var out := {"units": [] as Array[UnitData], "items": [] as Array[ItemData], "enemy_base_scale": 0.4, "enemy_scale_per_round": 0.05, "only_models": false}
	var st := (load("res://scenes/main.tscn") as PackedScene).get_state()
	for i in st.get_node_count():
		if st.get_node_name(i) != "Game Manager":
			continue
		for j in st.get_node_property_count(i):
			var v = st.get_node_property_value(i, j)
			match st.get_node_property_name(i, j):
				"unit_pool":
					for d in v:
						if d is UnitData:
							out.units.append(d)
				"item_roster":
					for it in v:
						if it is ItemData:
							out.items.append(it)
				"enemy_base_scale":
					out.enemy_base_scale = float(v)
				"enemy_scale_per_round":
					out.enemy_scale_per_round = float(v)
				"only_units_with_models":
					out.only_models = bool(v)
	if out.only_models:
		out.units = out.units.filter(func(d): return d.model != null)
	_rosters = out
	return out
