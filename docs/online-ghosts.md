# Online ghosts (async PvP, Part 1b)

Built 2026-10-25. Async PvP can fight **other players' ghosts** through a small web service. The game side
and a ready-to-run service are both in place; nothing is hosted yet. Until an address is set, async PvP
works exactly as before, against ghosts saved on this PC.

## Turning it on

1. **Host the service** (below).
2. **Point the game at it:** in `Scripts/online/online_config.gd` set
   ```gdscript
   const SNAPSHOT_URL := "https://ghosts.example.com"
   const SNAPSHOT_KEY := ""   # the --key the server was started with, if any
   ```
   That is the whole switch. To try a server before shipping its address, use the command line
   (`Godot ... -- --snapshot-url http://127.0.0.1:8910`) or `user://online.cfg`:
   ```ini
   [snapshots]
   url="http://127.0.0.1:8910"
   key=""
   enabled=true     ; false turns online ghosts off on this PC
   ```

## What the game does

- `OnlineConfig.make_store()` gives free play and async PvP an `HttpSnapshotStore` when an address is set
  (else a `LocalSnapshotStore`).
- **Uploading:** at every fight start the board is recorded (as before), saved locally **and** posted to the
  service. A failed upload (no answer, busy) is kept and retried with the next one, up to 10.
- **Downloading:** the ghost is picked synchronously when PREP starts, so ghosts are fetched a round ahead:
  rounds 1 and 2 when the run starts, then round n+1 during round n. The service returns up to 24
  candidates near that round; the game picks one with the same rules as the local store
  (`SnapshotStore.choose`: same round first, then neighbours; level within 1 preferred, never more than 1
  above; never your own run; today's balance hash first, else an older ghost whose units and items still
  exist).
- **Late arrivals:** if this round's online ghosts arrive after PREP began and the pick so far was only a
  local ghost or random enemies, the opponent is picked again and announced (`SnapshotOpponents.ghost_changed`).
  Once the fight starts the ghost is fixed.
- **Offline is never fatal:** a slow or unreachable service only means local ghosts or random enemies.
- Ghost names come from the name typed on the Lobby screen (`user://lobby.cfg`), else "Player".

## Hosting the service

The service is part of the game: `Scripts/online/snapshot_server.gd`, started by a command-line flag on a
headless build. It checks every upload against the game's own unit and item files, so run the **same
version of the project** as the players (an older server would refuse new units).

```bash
Godot --headless --path /srv/hare-hex -- --snapshot-server --snapshot-port 8910 --snapshot-data /srv/ghosts --key <optional key>
```

- `--snapshot-port` (default 8910), `--snapshot-data` (default `user://snapshot_server`), `--key` (or the
  `SNAPSHOT_KEY` environment variable). It can share one process with the lobby server: add `--server
  --port 7777` to the same command.
- The same service collects the testers' telemetry and serves its stats page at `/stats`; add
  `--stats-key <key>` (or `STATS_KEY`) to open it from elsewhere. See `docs/telemetry.md`.
- It speaks plain HTTP. Put it behind a reverse proxy for HTTPS, e.g. Caddy (gets certificates itself):
  ```
  ghosts.example.com {
      reverse_proxy 127.0.0.1:8910
  }
  ```
- Keep it running with systemd (or any process manager):
  ```ini
  [Unit]
  Description=Hare & Hex ghosts
  After=network.target

  [Service]
  ExecStart=/opt/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path /srv/hare-hex -- --snapshot-server --snapshot-data /srv/ghosts
  Restart=always
  User=harehex

  [Install]
  WantedBy=multi-user.target
  ```
- A small VPS is plenty: snapshots are about 1 KB, kept in memory and as one JSON file each, at most 400
  per round (the oldest go first).

## The API (for any other backend)

Anything that answers these three calls works; the game doesn't care what runs behind them.

| Call | Answer |
|---|---|
| `GET /v1/health` | `200 {"ok": true, "service": "hare-hex-ghosts", "api": 1, "snapshots": n}` |
| `POST /v1/snapshots` with a snapshot as JSON (header `X-Api-Key` if a key is set) | `201 {"id": "..."}`; `400 {"error": ...}` for a bad snapshot, `401` wrong key, `413` too big, `429` too many |
| `GET /v1/snapshots?round=9&level=7&balance=<hash>&exclude=<run>&limit=24` | `200 {"snapshots": [...]}`: rounds 8-10, `player_level` at most 7, not run `exclude`, today's balance first then older ones, random order, at most `limit` (50 max) |

A snapshot (format: `board_snapshot.gd`):
```json
{"version": 1, "balance": "3f9c...", "created": 1792985995, "run": "184467", "round": 9, "stage": "2-6",
 "player_level": 5, "hp": 100, "trophies": 4, "losses": 2, "name": "Mason",
 "board": {"name": "Mason", "units": [{"unit": "Knight", "star": 2, "coord": [3, 3], "items": ["longsword"], "stacks": {}}]}}
```
`trophies` / `losses` only come from async PvP runs (free-play boards have neither). The board is already
mirrored onto the enemy half (rows 0-3).

**What the server checks:** a valid snapshot of this version; round 1-999, level 1-10; no more units than
the level; units and items that exist; stars 1-3; at most 3 items; every unit on the enemy half, one per
tile; a body under 32 KB. It cleans the name, sets its own time and an id, and limits each address to 60
requests and 20 uploads a minute.

## Not done

- **Plausibility checks.** A hacked client could still upload a legal-looking but impossible board (three
  3-star 5-costs in round 4). The server could cap a board's total value by round; not needed until there
  are players to cheat.
- Accounts, moderation of names, a leaderboard (the best trophies are only saved locally:
  `SaveGame.async_best`).
- Matching by trophies as well as round (the snapshot carries them, the service ignores them for now).
- A web build would need the service to be reachable over HTTPS from the page's origin (CORS headers are
  already sent).

Checks: `tools/async_checks` (the service, the store over real HTTP on this machine, a ghost-mode run
against it, trophies and lives, endless mode, Start fight and fast forward).
