# Multiplayer design: async PvP and live lobbies

Design only, written 2026-10-21 with Opus 5.5. Nothing here is built yet. Part 1 (local-first async PvP) is the next thing to build; Part 2 (live 8-player lobbies) is the longer-term plan.

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

## Part 2: Live 8-player lobbies (design only)

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

- **Disconnect:** the seat keeps playing as a simple bot (the `tools/bot_playtest` logic: buy, place, equip) until the player reconnects; on reconnect the server sends the full `PlayerState` and board.
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
