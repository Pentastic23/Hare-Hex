# Tester telemetry

Anonymous gameplay stats from testers, to see which modes people play, finish and come back to, and where
they get stuck. Built 2026-10-26, ready for when the online service is hosted: the game collects now and
uploads once it knows the service's address.

## Turning it on

Nothing to do in the game: telemetry goes to the same service as the online ghosts (`docs/online-ghosts.md`).
Once `OnlineConfig.SNAPSHOT_URL` is set and that service runs, the stats go up with the ghosts.

Start the service with a stats key so you can read the page from anywhere:

```
Godot --headless --path /srv/hare-hex -- --snapshot-server --snapshot-data /srv/ghosts --stats-key <a long random word>
```

(or set the `STATS_KEY` environment variable). Then open `https://<your server>/stats?key=<the key>`
(`&days=7` for the last week; 30 by default). `/v1/stats?key=...` gives the same numbers as JSON. Without a
stats key the page only answers the server machine itself.

To try it before hosting: run the service on your PC (`-- --snapshot-server`), start the game with
`-- --telemetry --telemetry-url http://127.0.0.1:8910` (`--telemetry` turns it on in the editor too), play a
little, and open `http://127.0.0.1:8910/stats`.

Other overrides (OnlineConfig): `--telemetry-url`, or `user://online.cfg` with `[telemetry] url="..."`, or
`[telemetry] enabled=false` to keep events on that PC.

## What the game does (`Scripts/telemetry.gd`, autoload `Telemetry`)

- **On by default, with a notice:** the first time the menu opens, a dialog explains it (OK / Turn off).
  Settings > Privacy has the switch, the status (waiting / sent / not answering) and the tester's anonymous id.
  Turning it off drops the queue and keeps nothing. Off in the editor and headless runs.
- **Anonymous:** a random install id (`user://telemetry.cfg`) and a random id per session. No names, files
  or anything typed. The bug reporter adds the first 8 characters of the id to a report's game info, so a bug
  report can be matched to that tester's row on the stats page.
- **Queue:** events wait in `user://telemetry_queue.json` (at most 3000, oldest dropped) and go up every
  30 s in batches under 24 KB (every 2 s while a backlog goes up; longer waits, up to 10 min, while the
  service doesn't answer). Events from before the service existed go up once it does.

| Event | When | Main fields |
|---|---|---|
| `session_start` | launch | first launch?, sessions so far, OS, GPU, screen, language, pad, touch |
| `session_end` | clean quit | seconds, runs |
| `unclean_exit` | next launch, if the last session never quit cleanly (crash, force-quit freeze, power loss) | where (menu / run), mode, level, round, phase |
| `menu` | a main-menu screen opens | screen (campaign, settings, king, planner, lobby, ...; `_in_run` from the pause menu) |
| `run_start` | a run is set up (`GameManager._ready`) | run id, mode (tutorial / campaign / free / async / lobby), level, chapter, resumed (mid_level / carried), king, biome |
| `fight` | every fight ends | round, won, HP and HP lost, gold, level, units, prep seconds, fight seconds (async: trophies, losses) |
| `tutorial_step` | each tutorial step | step, title, seconds spent on the step before |
| `endless` | async PvP goes on into endless mode | round, trophies |
| `run_end` | won, lost, placed / disconnected (lobby), or quit (menu, restart, closing the game) | result, round, length, fights, wins, HP, level, gold, the board's units and active traits, average and lowest FPS (tutorial: the step) |

## The service (`SnapshotServer`) and the page (`TelemetryStats`)

- `POST /v1/events` `{"events": [...]}` (at most 100): keeps known event names with sane ids and properties
  under 4 KB, adds the server's time, appends them to `<data>/events/YYYY-MM-DD.jsonl`; IP addresses are not
  stored. Uploads need the `--key` like snapshots, and have their own rate budget (40 a minute an address).
- `GET /stats` builds the page from those files: overview tiles; per mode the runs, testers, how many came
  back for a second run, results, win rate, share left partway, average round and length; the rounds where
  runs end (lost / left / never ended); campaign levels with clear rate and the wave most runs end at; the
  hardest fights (lowest win rate, 3+ plays); the rounds with the longest prep; the tutorial funnel (testers
  per step, time on each, where tutorial runs stopped); crashes by where; frame rate by graphics card; menu
  screens; one row per tester.
- The raw files are JSON lines, easy to copy off the server and load elsewhere (`TelemetryStats.load_dir`).
- `GET /v1/events?key=<stats key>&days=30` serves them as one JSON-lines download (same key rule as the stats).

## Reading it yourself: the launcher's STATS panel

On your PC the launcher has a **STATS** button next to RELEASE (`launcher/telemetry_panel.gd`; only when
it knows the project folder, like RELEASE). Fill in the server address (it starts from
`OnlineConfig.SNAPSHOT_URL`, empty until you host) and the stats key once; they are kept in the launcher's
`user://stats_panel.cfg` on your PC only.

- **DOWNLOAD** fetches `/v1/events` for the last DAYS days.
- **THIS PC** loads the events your own game has queued but not sent (its `user://telemetry_queue.json`),
  which works before any server exists.
- **STATS PAGE** opens `/stats` in the browser; **FOLDER** opens the output folder.

Each load is saved to `<project>/telemetry/` (git-ignored: it is testers' data) as
`events_<server|this_pc>_<date>_<time>.jsonl` (as stored) and `.csv`: one row per event with
`time_utc, received_utc, event, player, session, version`, then one column per property name seen
(nested values such as the board's units stay JSON in their cell). The panel also sums the load up
(events, testers, sessions, events by name, fight win rate, how runs ended per mode, crashes).
`launcher/tools/stats_panel_check.tscn -- out.png <server> <key>` drives it.

Checks: `tools/telemetry_checks.tscn` (client, a real run's events, the service, the numbers, an upload over
HTTP).

## Not done

- No retention limit on the server's event files (one small file a day; delete old ones by hand).
- No per-unit / per-item balance tables yet (`run_end` already carries the comp and traits).
- Free play / async PvP prep timing counts time paused in the pause menu.
