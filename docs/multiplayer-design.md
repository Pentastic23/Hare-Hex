# Multiplayer design: async PvP and live lobbies

Written 2026-10-21 with Opus 5.5. Part 1 (local-first async PvP) was built 2026-10-21. Part 2 (live 2-8 player lobbies) was built 2026-10-23: playable offline against bots and over LAN, with a dedicated-server mode ready for hosting. See "Part 2: as built" below; the original plan follows it.

## What's already in place

These were built first because both parts depend on them:

| Piece | Where | Why it matters |
|---|---|---|
| Deterministic combat | `game_manager.gd` `combat_tick()`, `unit.gd` `combat_step()` | The same two boards always give the same fight (fixed 1/60 s ticks, fixed acting order, tile-based tie-breaks, no tweens). A server can compute a result and every client can replay it exactly. `tools/combat_checks` proves it across frame rates. |
| Instant resolution | `GameManager.resolve_combat()` | Runs a fight to the end without waiting for real time: what a server does. |
| Seeded RNG | `GameState.run_seed`, `GameManager.rng`, `PlayerState.rng` | A run (shops, drops, random enemies) replays exactly from a seed. Each player has its own shop RNG derived from the run seed. |
| Per-player state | `PlayerState`, `GameState.me`, `GameState.players` | Gold, level, XP, HP, streaks, items, shop offers and lock belong to a player. Only the local player drives the HUD. |
| Board format | `EnemyBoard` / `BoardUnit`, `to_dict()` / `from_dict()` | JSON-safe boards (units by name, items by id, stars, tiles). Snapshots and network messages use it. |
| Opponent providers | `OpponentProvider` | A new provider type is all a ghost or live opponent needs on the spawning side. |

Still single-player assumptions: one `Board` scene (the local player's), the shared unit pool lives in `GameManager`, and units are scene nodes (no node-free combat simulation yet).

---

## Part 1: Async PvP, local first (BUILT 2026-10-21)

**Status:** all six build-order steps are done and checked by `tools/pvp_checks` (33 checks). The menu's **Async PvP** button starts a ghost-mode run. Differences from the plan below, all deliberate:
- `fetch` also takes the game's balance hash and the run's seeded RNG: `fetch(round, player_level, balance, rng, exclude_run := "")`. The seeded RNG means a run seed picks the same ghost every time; "exclude_run" (the run id = run seed) replaces "exclude_name", so you never fight your own current run.
- Which ghosts fit: same balance hash, same round (or the round before or after if that one is empty), and a ghost level at most 1 above the player's (otherwise it could have more units than the open enemy tiles). Ghosts within 1 level of the player are preferred.
- The ghost is chosen when PREP starts (`OpponentProvider.prepare`) and announced on the top bar (`Events.opponent_announced`, `OpponentLabel`); it falls back to random enemies when nothing matches.
- Boards are recorded in free play and ghost mode, not in campaign levels, since only free-play rounds line up with each other.
- Headless runs (test tools, the bot) write to `user://snapshots_headless` instead of `user://snapshots`, so tests never fill your real store. Tests can also set `LocalSnapshotStore.root`.
- Not done: the HTTP store (Part 1b), and a rule for mid-fight item equips in PvP (still to decide before Part 2).

You fight **ghosts**: other players' boards recorded at the same point of their run. "Local first" means snapshots are saved on this PC; a server swaps in later behind the same interface.

### Snapshots

At every combat start, record the local player's board:

```json
{"version": 1, "balance": "<hash of unit/item data>", "created": 1792629429,
 "round": 9, "stage": "2-6", "player_level": 5, "hp": 74, "name": "You",
 "board": { EnemyBoard.to_dict() of the player's board, mirrored to the enemy half }}
```

- **Mirroring:** player tiles (rows 4-7) become enemy tiles by a 180° turn, `(x, y) -> (6 - x, 7 - y)`. With the odd-row hex offset this maps every tile to the exact opposite tile (worked through in the design; add a check).
- **Balance hash:** a hash of all `UnitData` / `ItemData` stats. Snapshots from older balance are skipped, so a stat change never produces unfair ghosts.
- Only board units are recorded; synergies are recomputed when the ghost spawns (`use_synergies = true`).

### Store interface

```gdscript
class_name SnapshotStore extends RefCounted
func submit(snapshot: Dictionary) -> void
func fetch(round: int, player_level: int, balance: String, rng: RandomNumberGenerator, exclude_run := "") -> Dictionary   # {} if none (as built)
```

- **LocalSnapshotStore** (first): files in `user://snapshots/`, bucketed by round, at most ~50 per round (drop the oldest). Your own past runs become your opponents, so the mode works offline from the first run.
- **HttpSnapshotStore** (later, Part 1b): the same two calls against a tiny web service (`POST /snapshots`, `GET /snapshots?round=9&level=5`). Nothing else in the game changes.

### Provider and mode

- **SnapshotOpponents** (`OpponentProvider`): `board_for_round(r)` asks the store for a snapshot near round `r` and the player's level, and falls back to `RandomOpponents` when there's none.
- **Ghost PvP mode** in the main menu: free-play rules (39 rounds, shared pool, items), opponents from SnapshotOpponents, loss damage from the free-play formula. The opponent's name and HP show on the top bar.

### Fairness and verification

- Combat is deterministic, so a fight against a ghost can be re-run anywhere from: both boards, the run seed, and the player's mid-fight inputs.
- **Mid-fight inputs:** equipping items on fighting units is the only thing a player can do that changes a fight in progress. Record them as `(tick, unit index in combat order, item id)`. For PvP the simplest rule is to **only allow equipping bench units during a PvP fight**; decide before Part 2.

### Build order (Part 1)

1. Board mirroring + a check that it maps tiles and neighbours correctly.
2. `BoardSnapshot` capture at combat start; balance hash.
3. `SnapshotStore` + `LocalSnapshotStore` (with pruning).
4. `SnapshotOpponents` provider with fallback.
5. "Ghost PvP" in the main menu; opponent name/HP on the top bar.
6. Checks: snapshot round trip, mirroring, fetch by round/level, fallback, same fight from a snapshot twice.

---

## Part 2: as built (2026-10-23)

**Status:** working end to end, checked by `tools/lobby_checks` (56 checks). The main menu's **Lobby (2-8 players)** button opens a screen with **Play vs bots** (you + 1-7 bots, all in this game), **Host a game** (a LAN game: this game runs the server and others join) and **Join a game** (address and port), then a waiting room where the host adds or removes bots and starts.

**Decisions taken** (the four questions at the end of this doc):
1. Mid-fight items: **allowed**, recorded as timed inputs. The server accepts the drop, schedules it `Arena.INPUT_DELAY` (15) ticks ahead and sends it to both players, so every copy of the fight applies it on the same tick.
2. Lobby size: **2-8 players**, no bots unless the host adds them (offline: you choose how many). A player who disconnects mid-game keeps their seat, idle: their board still fights each round as they left it, but nobody shops or levels for them until they rejoin (decided 2026-10-23: no bot takes over). With an odd number alive, one player fights a **ghost** (a copy of another player's board; only that player's result counts).
3. Hosting and 4. accounts: **not decided yet**. Nothing built depends on them (see "Plugging in a server").

### How it fits together

| Piece | File | What it does |
|---|---|---|
| Fight loop per board | `Scripts/combat_runner.gd` (`CombatRunner`) | The fixed tick, acting order, zones, summons, timed inputs and end check, owned by a board. Single player uses one on the visible board; the server has one per arena. Abilities find the runner of their own board (`Board.runner`). |
| Shared rules | `Scripts/player_rules.gd` (`PlayerRules`) | Every player action (buy, sell, move, reroll, Buy XP, lock, equip, Tongs) and the round economy, for one `PlayerState` + `Board`. Single player and the server both call it, so they can't drift apart. Strict mode (server): a buy must be on offer and affordable. |
| Fight description | `Scripts/lobby/arena.gd` (`Arena`) | A fight as JSON-safe data (both sides' units by uid, name, star, items, stacks, tile; the enemy tiles to open; PvE strength) and the one `setup()` that builds it on a board. The server and both clients run the same description through the same setup, so they get the same fight. |
| Server | `Scripts/lobby/lobby_server.gd` (`LobbyServer`) | Authoritative: seats (`PlayerState`, hidden `Board`, `PlayerRules`), the lobby-wide `UnitPool`, the phase timer, pairings (no repeat opponent when avoidable), PvE stage 1 (rounds 1-3), PvP from round 4, damage, eliminations, placements, bots (only for seats the host adds), idle seats for disconnected players, rejoin by token. Knows nothing about networking: `receive(peer, msg)` in, `endpoint` out. |
| Messages | `Scripts/lobby/lobby_protocol.gd` (`LobbyProtocol`) | Every message type and its fields (the file header is the reference), `VERSION`, JSON encode/decode. A client and server only talk when `VERSION` and the balance hash match. |
| Transport | `Scripts/lobby/lobby_net.gd` (autoload `LobbyNet`) | Modes OFFLINE (in-process link), HOST (server here + ENet), CLIENT (ENet), DEDICATED (`--server`). JSON over a `MultiplayerPeer`'s raw reliable packets, no RPCs or node paths. `_make_peer()` is the one place to swap in `WebSocketMultiplayerPeer`. |
| Client | `Scripts/lobby/lobby_client.gd` (`LobbyClient`) | Keeps the latest of everything the server said and sends this player's intents. |
| Game view | `Scripts/lobby/lobby_game.gd` (`LobbyGame`, `GameManager.lobby`) | The game scene in lobby mode: copies your state into `GameState.me`, matches board units to the server's by uid, replays your fight in real time (turned around when you're the away side), shows standings and your placement. Your clicks become requests; nothing is decided here. |
| Bots | `Scripts/lobby/lobby_bot.gd` (`LobbyBot`) | Plays a seat through `PlayerRules`; deterministic, so a seeded lobby of bots replays exactly. |

Rules are free play's (up to 39 rounds, shared pool, items, Tinker's Tongs). A lost fight costs 5 HP per stage plus a quarter of the winner's standing stars; a draw (time out) costs both sides. The pause menu pauses an offline game (bots wait for you) but not a LAN or online one (`LobbyNet.can_pause()`).

### Plugging in a server

Everything a hosted server needs is in place; what's missing is a machine to run it on.
1. **Run it:** export a Linux build (or use the Godot binary) and start `Godot --headless --path <project> -- --server --port 7777`. It prints one line per lobby change. One process is one lobby of up to 8.
2. **Open the port:** UDP 7777 (or the `--port` you chose) on the machine's firewall / provider.
3. **Join:** players use Lobby > Join a game with the server's address and port. The first player to join is the host (adds bots, starts); if they leave, the next player becomes host.
4. **Later, if wanted:**
   - a matchmaker (a small web service that starts one server process per lobby and hands out address + port);
   - `WebSocketMultiplayerPeer` behind TLS for a web build (change `LobbyNet._make_peer()`);
   - accounts instead of anonymous names;
   - saving the rejoin token on the client, so a player can rejoin after restarting the game. The server already accepts tokens; the client only keeps one while it is running.

### Not done
- Rejoining after closing the game (see above). Reconnecting while the game is still open works.
- Spectating, chat, and a lobby browser (LAN games are joined by address).
- Tested on one machine only (ENet over localhost in `lobby_checks`); a real two-PC LAN test is still to do.

## Part 2: Live 8-player lobbies (original design)

### Architecture

- **Authoritative dedicated server:** a headless build of this same Godot project, started in "server mode" (a command-line flag). It owns all game state; clients only send intents and render.
- **Transport:** Godot's high-level multiplayer API. `ENetMultiplayerPeer` (UDP) for desktop builds; `WebSocketMultiplayerPeer` if there's ever a web build. Both work with the same RPC code.
- **What runs where:**

| | Server | Client |
|---|---|---|
| Run state (round, phase timer, seed, shared pool) | owns it | mirror |
| Each PlayerState (gold, level, HP, items, shop) | owns it, validates every action | its own, read-only mirror |
| Boards | one per player | its own board (editable in PREP), opponents' for viewing |
| Combat | resolves every pairing with `resolve_combat()` | replays its own fight in real time from the same inputs |

### Round flow

1. **PREP** (server timer): clients send intents as RPCs: buy, sell, move unit, equip item, reroll, lock, buy XP. The server checks each against that player's `PlayerState` (enough gold? valid tile? unit owned?), applies it, and sends the change back.
2. **Pairing:** at COMBAT the server pairs the 8 players (TFT-style: avoid the same opponent twice in a row; with an odd number alive, one player fights a ghost of another).
3. **Combat:** the server snapshots both boards of each pair and resolves the fight instantly (deterministic). It sends each client the two boards plus the fight's inputs; the client plays the fight in real time and gets the same result. Bandwidth is tiny: boards, not per-frame positions.
4. **Results:** the server applies damage, streaks and income, eliminates players at 0 HP and ranks them, then starts the next PREP.

### Shared pool

The `UnitPool` becomes lobby-wide on the server (TFT's contested pool): one player's purchase removes copies for everyone. It's already run-wide in `GameManager`; it moves to the lobby object.

### What has to change in the code first

1. **Node-free combat simulation.** The server resolves up to 4 fights per round per lobby. Instantiating board scenes headless works for a prototype, but a data-only `CombatSim` (units as plain objects with the same `combat_step` logic) is lighter and easier to run many of. Plan with Opus.
2. **Lobby object.** `GameState` becomes "the lobby": `players` (8 `PlayerState`s), the shared pool, the pairing history, and the round timer. `GameState.me` stays as the local client's view.
3. **Board per player** on the server (data, or scenes for the prototype).
4. **Intent layer:** every player action becomes a function `apply_intent(player, intent) -> bool` used by both the local game and the server, so single-player and multiplayer share rules.

### Disconnects and cheating

- **Disconnect** (as built: the seat stays idle instead, see "Decisions taken"): the seat keeps playing as a simple bot (the `tools/bot_playtest` logic: buy, place, equip) until the player reconnects; on reconnect the server sends the full `PlayerState` and board.
- **Cheating:** clients never decide results; the server validates every intent and computes every fight. Client replays are only visual.

### Hosting

- A small Linux VPS (around $5-10 per month) can run several lobbies: each lobby is one headless Godot process.
- Needs: a public IP/port (UDP for ENet), a simple matchmaker (can be a tiny HTTP service that starts lobby processes), and later TLS if WebSockets are used.
- A hosted backend (Nakama, PlayFab, Steam lobbies) can replace the matchmaker and accounts; the game server stays the same.

### Phases

1. **Part 1** (local-first ghosts): no networking.
2. **Part 1b:** the HTTP snapshot store, so ghosts come from other players.
3. **LAN prototype:** server mode + 2-8 clients on one network, scene-based combat on the server.
4. **Node-free `CombatSim`** and the intent layer.
5. **Online:** hosted server, matchmaker, reconnects.

### Decisions needed before Part 2

1. Mid-fight item equips in PvP: allow (record as timed inputs) or bench-only?
2. Lobby size and bots: always 8 (fill with bots/ghosts) or start with fewer?
3. Hosting: own VPS or a hosted backend?
4. Accounts: anonymous player IDs or a login?
