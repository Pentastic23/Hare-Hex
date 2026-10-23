# Auto Battler: Project Notes

A 3D TFT-style auto battler built in **Godot 4.7** with GDScript. Working title **AZTactics** (shown on the main menu and set as the window title at runtime; the project's `config/name` stays "Azerothtactics" because Godot derives the save folder `app_userdata/Azerothtactics` from it). Single player: free play and a campaign; a PvP mode is planned.

> These notes describe the intended design as built step by step. If the code and these notes disagree, the code wins. Update this file when systems change.

---

## Model guidance

I usually work with Sonnet 5.5. Before starting a task, if it would clearly benefit from Opus 5.5, say so in one line at the top of your reply, explain why, and wait for me to switch or tell you to go ahead. Flag it for:
- Planning game architecture (state machines, save/load, opponent providers, campaign structure, per-player state)
- Bugs that survive two fix attempts, especially combat timing, tween, physics, or signal-order issues. Count attempts across the conversation: if I report the same bug is still happening after your second fix, recommend Opus instead of trying a third time.
- Refactors that touch many scripts or scenes (e.g. refactoring global GameState)
- Deterministic combat, networking/PvP, shaders, pathfinding, or other math-heavy systems
- Any roadmap item tagged **[Opus]** below

Don't flag routine work like writing GDScript, setting up nodes or UI, tweaking unit data, or small fixes. Items tagged **[Sonnet]** are fine to do directly.

When recommending Opus, also write a 3-5 line handoff (what the task is, what's been tried, which files matter) so I can paste it into the Opus session.

At the start of a session, read **Current status** and **Known issues** below. When you finish a task, update both (and the roadmap) so the next session knows where things stand.

---

## Folder layout

```
res://
  scenes/        menu.tscn (main menu, the project's main scene), main.tscn (a run), Tiles.tscn (one hex tile), unit.tscn, ui.tscn (all in-run UI, instanced in main)
  Scripts/       all .gd files
  models/units/  the unit models: <unit>_<n>star.glb for 1-3 stars (voxel, rigged, animated; from menagerie/)
  textures/ui/shop/ the shop mockup (also in the user's Desktop/Art assets/autochess ui): the shop bar is built in code in its style; only unit_silhouette_1-5 are used (empty slots), the rest have numbers painted in
  textures/ui/portraits/, textures/ui/items/  96 px unit portraits (<unit .tres name>.png) and 64 px item icons (<item id>.png) for the side boxes and the shop
  scenes/models/ one wrapper scene per modelled unit (UnitModel root + its three star glbs); UnitData.model points here
  menagerie/     art drop from a separate chat: README (model format, clips, impact frames), hud/HUD_SPEC.md (with mockups hud_states_sheet.png, hp_standings_mockup.png, timer_round_mockup.png), previews, vox, the generator, the unused 4-star glbs. Has a .gdignore, so Godot never imports it
  tres/          UnitData .tres files (one per unit type) + panel_style.tres (shared StyleBoxFlat)
  tres/items/    ItemData .tres files (one per item)
  tres/campaign/ campaign.tres -> chapter_1..3.tres -> levels/ch1_l*, ch2_l*, ch3_l*.tres (waves embedded in each level); tutorial.tres
  tools/         dev tools, not part of the game (bot_playtest.tscn, campaign_checks.tscn, menu_checks.tscn, hud_checks.tscn, combat_checks.tscn, tutorial_checks.tscn, pvp_checks.tscn, tooltip_checks.tscn, roster_checks.tscn, touch_checks.tscn, gamepad_checks.tscn, keybinds_checks.tscn)
  docs/          design docs (items-plan.md, campaign-and-opponents.md, item-ideas.md, multiplayer-design.md)
  addons/        third-party plugins; don't edit
```

Casing is mixed on disk: `scenes/` is lowercase, `Scripts/` is capitalized. Every `preload` / `load` path must match the on-disk casing exactly, or exports to case-sensitive platforms break (Godot prints a "Case mismatch" warning when it's wrong).

---

## Scene tree (main.tscn)

```
Main (Node3D)
 ├─ WorldEnvironment
 ├─ DirectionalLight3D
 ├─ Board (Node3D)                board.gd, in group "board"
 │   ├─ Bench (Node3D)            plain Node3D, bench + sell hexes spawned at runtime
 │   ├─ Units (Node3D)            plain Node3D, ALL unit instances live here
 │   └─ Tiles (Node3D)            plain Node3D, tiles spawned at runtime
 ├─ UI                            instance of ui.tscn (see below)
 ├─ "Game Manager" (Node)         game_manager.gd  -- note the SPACE in the node name
 ├─ DragController (Node)         drag_controller.gd
 └─ CameraRig (Node3D)            camera_rig.gd (sets its own position, tilt and the camera's distance and FOV at runtime)
     └─ Camera3D
```

The Game Manager exports set in main.tscn: `prep_time = 15`, `unit_pool` = all 65 unit .tres files (this is the **roster**, not the shared pool), `item_roster` = the 6 item .tres files, `enemy_base_scale = 0.4`, `enemy_scale_per_round = 0.05` (free-play random enemies). `only_units_with_models` (default **off** since all 65 units have models): when on, `_begin_run` drops every unit without a model from `unit_pool`. Keep it off; it only matters again if a unit is added without a model. `debug_level` (CampaignLevel) is empty: it only matters when main.tscn is run directly (F6 in the editor) to jump straight into a campaign level for testing; runs started from the main menu ignore it (`GameState.launched_from_menu`). Always load a level **file** into it; a "New CampaignLevel" has no waves, so the game warns and plays free play instead. `continue_saved_run` (default on): with Debug Level set, running main.tscn directly continues the saved chapter run if it's in the same chapter.

**menu.tscn** (the project's main scene, `run/main_scene`): a full-screen Control with `main_menu.gd`, which builds everything in code: title "AZTactics", Continue (only with a saved chapter run), then **SINGLE PLAYER**: Tutorial ("(start here)" for new players, "(done)" once completed), Campaign panel (chapters, levels with status: Completed/best HP, Not completed, Locked; Start chapter), Free Play; then **PVP** (tinted blue): **Async PvP** (a real mode: free-play rules against ghost boards, see Async PvP below; sets `GameState.ghost_mode`) and Live PvP (a "coming soon" placeholder that opens an info panel); then Settings / Quit on one row. The menu must fit a 648 px tall window (`menu_checks` measures it). Starting a run sets `GameState.run_level` / `run_campaign` / `run_carry` / `launched_from_menu`, calls `reset()` and changes to main.tscn.

**ui.tscn** (root `UI`, CanvasLayer):

```
UI
 ├─ TopBar (PanelContainer, top center, flush with the top edge)   top_bar.gd (combat HUD, styled after TFT's top bar): "STAGE 3 [pips] 3-4 | PREP 0:12 [fold]" with a thin time track along the bottom. Children built in code: `rounds` (round_tracker.gd: pips, "3-4" or campaign "WAVE [pips] 4/5" with a boss diamond; campaign tooltip lists the level, wave and enemies) and `timer` (top_bar_timer.gd: gold in prep, red in the last 5 s of prep / 10 s of a fight, "--" in the untimed tutorial prep). The fold chevron shrinks it to "3-4 0:12" (remembered in `Settings.show_top_bar`); it re-centres itself whenever its width changes (`_recenter`)
 ├─ ShopPanel (PanelContainer, bottom center, 6 px up)   shop_panel.gd (a HudPlate); its children are built in code:
 │   └─ HBoxContainer: LevelPanel (LVL, XP bar, gold), BuyXPButton, RerollButton, LockButton, "Slot 1" .. "Slot 5" (ShopSlot, shop_slot.gd)
 ├─ BottomInfo (VBoxContainer)    bottom_info.gd
 │   ├─ OddsLabel                 odds_label.gd
 │   └─ InfoRow (HBox): BoardLabel (board_label.gd, unit cap), StreakLabel (streak_label.gd)
 ├─ Standings (VBoxContainer, right edge, top at y = 129, 210 px)   hp_standings.gd: one StandingRow per player (you, plus this round's opponent with a VS tag: the ghost and its HP, the campaign wave with "4/5", or "Random enemies"); the right box pushes it down below an open panel (up to y = 300) and hides it under a taller one
 ├─ "End Screen" (ColorRect)      end_screen.gd
 │   └─ CenterContainer/Backing/Margin/VBoxContainer: TitleLabel, DetailLabel, RestartButton (a "Next level" button is added in code, campaign only)
 ├─ LeftDock (PanelContainer, top left, 232 px; 46 px rail when collapsed)   left_dock.gd (class LeftDock): Synergies / Items tabs, built in code; tab contents synergy_panel.gd and item_bar.gd
 ├─ UnitInspector (PanelContainer, panel_style.tres, bottom right above the shop bar, grows up)   unit_inspector.gd
 │   └─ VBoxContainer: NameLabel, TagsLabel, ItemsLabel, StatsLabel
 ├─ TutorialPanel (PanelContainer, right side, below the standings)   tutorial.gd (only visible in the tutorial level; built in code)
 └─ RightDock (VBoxContainer, top right, 236 px, last child)   right_dock.gd (class RightDock, group "right_dock"): tab bar + one panel (damage_meter.gd, team_planner.gd, pause_menu.gd), built in code. Adds the pause dim as the first child of UI at runtime
```

Several node names contain spaces ("Game Manager", "End Screen", "Slot 1"). Any `get_node` path must use the exact name.

`unit.tscn`: root Node3D with `unit.gd`, children `ModelHolder` (Node3D, holds a capsule MeshInstance3D at y = 1) and `Area3D` (layer 2, for picking). Health bar, mana bar and letter label are created in code. A unit whose UnitData has a `model` hides the capsule and letter label, puts its UnitModel in ModelHolder and gets a team ring at its feet instead.
`Tiles.tscn`: StaticBody3D root with `tile.gd` (collision layer 1), 6-sided CylinderMesh (radius 0.95, no rotation applied in the scene). Hex layout math in board.gd is **pointy-top**.

---

## Autoloads

- **GamepadControls** (`gamepad_controls.gd`): controller support on PC; see "Controller" under UI behaviour. Takes the pad events off Godot's default ui_* actions in `_ready` (so A / B / D-pad don't move GUI focus or fire ui_cancel) and sends mouse events and shortcut keys instead.
- **TouchControls** (`touch_controls.gd`): touch screen support; see "Touch controls" under UI behaviour. Reads only InputEventScreenTouch / ScreenDrag, so mouse and keyboard play is unaffected.
- **Events** (`events.gd`): all global signals, plus `enum Phase { PREP, COMBAT, RESULT }`.
- **GameState** (`GameState.gd`): **run-wide** state only: `round_number`, stage math, shop odds table, `base_income_for_round`, `ITEM_DROP_ROUNDS` / `item_drop_rounds()`, `damage_for_loss`, `reset()` (round + every player), and the run setup: `run_level` (CampaignLevel or null = free play), `run_campaign`, `run_carry` (chapter run state for the next level), `run_carried`, `run_seed` / `next_seed` (set `next_seed` before a run to replay it exactly), `begin_run(level, campaign) -> carry`, `launched_from_menu`, `MENU_SCENE`, `go_to_menu()`. `run_level` / `run_campaign` / `run_carry` survive `reset()`.
  - **Per-player state is in `PlayerState`** (`player_state.gd`): `GameState.me` is the local player, `GameState.players` everyone in the run (just `[me]` for now). Fields: `gold`, `level`, `xp`, `player_hp`, `start_hp` (HP-pack cap), `win_streak` / `loss_streak`, `items`, `cheap_shop`, `shop_offers`, `shop_locked`, `shop_has_rolled`, `last_combat_won`, `rng` (this player's shop and drops, seeded from the run seed and `id`). Methods: `xp_needed`, `add_xp`, `max_board_units`, `interest_gold`, `total_income_for_round`, `record_result`, `streak_bonus`, `heal`, `reset`. Only a player with `is_local` emits the HUD signals (gold_changed, hp_changed, xp_changed, streak_changed, items_changed). **Always write `GameState.me.gold` etc.; `GameState.gold` no longer exists.**

Signals in Events: `phase_changed`, `gold_changed`, `shop_rolled`, `unit_bought`, `combat_ended`, `xp_changed`, `reroll_pressed`, `buy_xp_pressed`, `board_limit_hit`, `round_changed`, `streak_changed`, `hp_changed`, `unit_sold(data, star, refund)`, `run_won`, `run_lost`, `items_changed`, `item_drag_started(index)`, `item_drag_ended`, `shop_lock_changed(locked)`, `team_plan_changed`, `opponent_announced(text)`.

---

## Core scripts

| Script | Responsibility |
|---|---|
| `board.gd` (class Board) | Hex grid (7 cols x 8 rows; rows 0-3 enemy, 4-7 player), bench (9 slots), sell zone, tile unlocking by level, seam border, hex math + BFS pathfinding, merging, selling |
| `tile.gd` (class Tile) | `coord`, `occupant`, `unlocked`, pop-in animation |
| `unit.gd` (class Unit) | Stats, star level, combat step (tick-stepped movement, `take_damage` returns HP removed), health/mana bars, letter label, synergy bonus fields, items (`items`, `item_*` fields, `equip` / `set_items` / `take_items`, item icons above the health bar), placeholder ability casting |
| `item_data.gd` (class ItemData) | Resource: stable `id`, name, description, color, stat boosts (hp, dmg, attack_speed, mana, damage_reduction, lifesteal) |
| `item_bar.gd` | Items tab of the left box: one row per item type (icon, name, description, "x2"), press a row to start an item drag, drag ghost label |
| `hud_style.gd` (class HudStyle), `hud_plate.gd` (class HudPlate), `standing_row.gd` (class StandingRow) | Combat HUD building blocks: spec colours and fonts (Jersey 10 / Atkinson Hyperlegible from `res://fonts/` if present, else a bold monospace system font and the default font emboldened), the dark plate with its lit top edge and 3 px lip, one HP standings row (name, VS tag, HP, 10-segment bar; roles you / opponent / other / out) |
| `top_bar.gd`, `top_bar_timer.gd`, `round_tracker.gd`, `hp_standings.gd` | The HUD pieces (see the ui.tscn tree); they replaced phase_timer.gd, stage_label.gd, opponent_label.gd and hp_label.gd |
| `camera_rig.gd` | main.tscn CameraRig: TFT-like view (rig on the aim point, `pitch` 54, `distance` 23, `fov` 38; board fills the screen with the bench just above the shop). Mouse wheel or the zoom keys (= / - by default; Keybinds) zoom, the reset-view key (Home) resets (0.65x-1.15x, eased); zooming in slides the aim from `target` to `zoom_focus` (mid-board) so the fight stays in view. Zoomed in, drag to pan (middle mouse anywhere, or left mouse on empty ground; a left press on your unit or an item drag moves that instead). `aim()` clamps the view so it never shows ground outside the default zoom's view (`_footprint()` is the trapezoid seen at zoom 1, and zoom scales it about the aim point), so at the default zoom or wider it can't pan. Picking uses camera rays, so zoom never breaks dragging or the inspector |
| `tip.gd` (class Tip) | `Tip.wrap(text)` word-wraps tooltip text at 340 px (Godot does not wrap tooltips); `Tip.width_of(line)` measures a line; every tooltip goes through it |
| `unit_model.gd` (class UnitModel) | A unit's animated model (root of each `scenes/models/*.tscn`): swaps the star glb on merges, turns it 180 degrees (models face +Z, `look_at` points -Z), plays idle / walk / attack / skill / hit / death / victory. Purely visual: Unit tells it about attacks, casts, hits, deaths and the fight ending, it reads `moving`, and nothing in combat reads it back |
| `unit_data.gd` (class UnitData) | Resource: name, cost, stats, tags, mana, model, ability |
| `ability.gd` (class Ability) | Resource base class; `cast(caster, target)` does nothing yet (placeholder) |
| `synergies.gd` (class Synergies) | Static synergy table + count (units) / count_data (UnitData, for the planner) / active_tier / next_threshold / apply |
| `left_dock.gd` (class LeftDock) | Left box: Synergies / Items tabs with count badges, collapse to a rail; remembers `Settings.dock_collapsed` / `dock_tab` |
| `right_dock.gd` (class RightDock) | Right box: Damage / Planner / Menu tabs, one panel at a time; P and Esc; pauses and dims for the menu; moves the standings and the tutorial panel below an open panel |
| `dock_kit.gd` (class DockKit) | Shared pieces for both boxes: colours, tabs, badges, chips, wells, primary/secondary buttons, pixel icons, `portrait(UnitData)` (`textures/ui/portraits/<tres name>.png`), `item_icon(ItemData)` (`textures/ui/items/<id>.png`), `effect_text(tag, tier)` |
| `hud_buttons.gd` | **Unused** since the side boxes (2026-10-22); safe to delete with its .uid |
| `damage_meter.gd` | Damage panel of the right box: dealt/taken per unit in the current or last fight (from `GameManager.snapshot` and `Unit.damage_dealt` / `damage_taken`), Dealt / Taken switch, portraits and bars |
| `team_planner.gd` | Planner panel of the right box: cost tabs 1-5, a 5-column tile grid (portrait, owned count, planned outline), toggle planned units (saved as names in `SaveGame.team_plan`), planned synergy chips |
| `game_manager.gd` | Run setup (`_begin_run`: free play or campaign level, shop roster, opponent provider), phase loop (PREP counts down `prep_left` in `_process`, so pausing stops it and the top bar timer can show it; `end_prep_early()`), shop rolling (from `shared_pool`), buying, enemy spawning (`spawn_board`), combat loop, end of combat (HP packs), run end (records campaign completion; `make_carry` / `_restore_carry` move the board between chapter levels) |
| `enemy_board.gd` (class EnemyBoard), `board_unit.gd` (class BoardUnit) | The enemy-side format: units with star, coord, items; `stat_scale`, `use_synergies`; `to_dict()` / `from_dict()` for saves and snapshots |
| `opponent_provider.gd` (class OpponentProvider) | `board_for_round(round) -> EnemyBoard`, `prepare(round)` (called when PREP starts) and `describe_next()` (a one-line description; the HUD standings read the provider directly); implemented by `random_opponents.gd` (free play), `wave_opponents.gd` (campaign) and `snapshot_opponents.gd` (async PvP ghosts, falls back to random); `SnapshotOpponents.current_snapshot()` is the ghost picked for the coming fight (the standings show it) |
| `board_snapshot.gd` (class BoardSnapshot), `snapshot_store.gd` (class SnapshotStore), `local_snapshot_store.gd` (class LocalSnapshotStore) | Async PvP: `BoardSnapshot` mirrors a player board onto the enemy half (`mirror`), hashes the balance (`balance_hash`), and captures / validates / converts snapshots; `SnapshotStore` is the submit/fetch interface; `LocalSnapshotStore` keeps JSON files in `user://snapshots/round_NN/` (50 per round, oldest pruned) |
| `campaign.gd`, `campaign_chapter.gd`, `campaign_level.gd` | Campaign data: chapters, levels (waves + modifiers + rewards), unlock order, `validate()` |
| `save_game.gd` (class SaveGame) | Static save system: campaign progress, unlocks and the chapter run in `user://save.json` |
| `main_menu.gd` | Main menu (menu.tscn): Continue; Single player (Tutorial, Campaign panel, Free Play); PvP placeholders (Async, Live) with an info panel; Settings panel, Quit; starts runs |
| `tutorial.gd` | Tutorial step panel: 12 steps (welcome, buy, place, start fight, watch, merge, synergies, items, sell, lock the shop, level up, win). Most advance when their condition is met; welcome and "Watch the fight" wait for Next (Watch's Next is greyed out until the fight is over, and Start fight is hidden while a step waits for Next); Start fight button (`GameManager.end_prep_early()`) |
| `pause_menu.gd` | Menu panel of the right box (Esc): Resume / Main menu / Quit game; the right box pauses the tree while it is open |
| `settings.gd` (class Settings) | Static player options in `user://settings.cfg`: fullscreen, VSync, master volume, HUD state (show_damage_meter, dock_collapsed, dock_tab, show_top_bar); `apply()` |
| `drag_controller.gd` | Left-drag units, swaps, snapping (board tiles only on the player half, rows 4-7; a drop on an enemy-side tile returns the unit to where it came from), sell zone, F-to-sell, drag cancel on phase change; dropping dragged items on units (`equip_item_on`) |
| `unit_pool.gd` (class UnitPool) | Shared unit pool: copies left per UnitData, weighted `pick(cost)`, `take` / `take_copies` / `give_back`, `copies_in(star)` |
| `shop_slot.gd` (class ShopSlot) | A shop card: portrait (cost-colour edge), name, traits, coin + cost, 3 pips for 1-star copies owned, gold outline and star when planned, silhouette when empty, "Not enough gold" / "Bench full" flash. Checks gold and bench space (in PREP, completing a merge also counts); `clear_offer()` for empty slots |
| `shop_panel.gd` | The shop bar (built in code, style of the shop mockup): level panel (LVL, XP bar, gold with the income tooltip), Buy XP, Reroll, Lock (padlock, gold when locked; disables Reroll), five ShopSlots filled from `shop_rolled` |
| `gold_label.gd`, `label.gd` | **Unused** since the shop bar rebuild (2026-10-22): the level panel shows gold and XP. Safe to delete with their .uid files |
| UI labels | `odds_label.gd`, `streak_label.gd`, `board_label.gd`, `bottom_info.gd`, `unit_inspector.gd`, `end_screen.gd` |

---

## Game rules implemented

**Phases:** PREP (timer, `prep_time` export) -> COMBAT -> RESULT -> PREP. `_enter()` drives it and is guarded by `game_over`. `_end_combat()` must start with `if not fighting: return` (missing it caused rounds to be skipped).

**Stages:** 7 stages. Stage 1 = 3 rounds, stages 2-7 = 6 rounds (39 total). `round_number` is the overall round; `stage()` / `round_in_stage()` derive the display (e.g. Stage 2-4).

**Economy:**
- Start with 2 gold.
- Passive income: 1-1: 0, 1-2: 2, 1-3: 3, 2-1: 4, then 5 per round.
- Interest: +1 per 10 gold banked, max +5.
- Streaks: win or loss streak of 2-3 = +1, 4 = +2, 5+ = +3.
- Round 1-1 shop (`cheap_shop`) is limited to 1-cost units at normal price.
- Win a fight: +1 gold.
- Reroll 2g (prep only). Buy XP 4g for 4 XP (any time, including combat).
- Selling refunds `cost * 3^(star-1)`, applied immediately (bench units can be sold during combat).
- Gold label tooltip shows next round's base / interest / streak / total.

**Levels and board:**
- +2 XP per round. XP table in GameState.
- Unit cap on board = level.
- **Auto-fill:** when a fight starts, free board slots (under the cap, on unlocked tiles) are filled from the bench, leftmost bench unit first (`Board.auto_fill`, called in `start_combat` before the position snapshot, so those units stay on the board afterwards). Each takes a spot that suits it (`Board.open_tile_for`): melee (range 1) the frontmost open row, range 2 the second row, ranged (3+) the backmost; within a row the tile nearest the centre column.
- Board starts with 2 tiles per side (front row center) and grows evenly to the full board at level 8 (`tiles_open_for_level`). New tiles from a mid-combat level-up appear at the next PREP.
- Gold seam border drawn only between unlocked player front-row tiles and unlocked enemy tiles.

**Shop odds (% for 1/2/3/4/5 cost) by level:** 1-2: 100/0/0/0/0, 3: 75/25, 4: 55/30/15, 5: 45/33/20/2, 6: 30/40/25/5, 7: 19/30/35/15/1, 8: 15/20/35/25/5, 9: 10/15/30/30/15. If no unit exists at a rolled cost, falls back to the nearest cost.

**Shared unit pool:** Copies per unit by cost: 1: 30, 2: 25, 3: 18, 4: 10, 5: 9 (`UnitPool.COPIES_PER_COST`). Shop offers are taken from the pool when rolled; unbought offers go back on the next roll. Bought units stay out. Selling returns `3^(star-1)` copies. Picks within a cost are weighted by copies left; an empty cost falls back to the nearest cost with copies; if the pool runs dry the slot is left empty. Enemies do not draw from the pool. `GameManager.shared_pool` owns it (rebuilt on scene reload).

**Units and merging:** 3 copies (same `display_name`, same star) merge into the next star, max 3. Star multipliers: HP/dmg x1.0 / x1.8 / x3.2, model scale 1.0 / 1.2 / 1.45. Merges run after buys (prep only), after drops (prep only), and at PREP start. Buying on a full bench is allowed in PREP if it completes a merge. Units bought during combat go to the bench only (full bench = refused) and are not merged until the next PREP start.

**Combat (deterministic):** the same two boards always produce the same fight, at any frame rate. `GameManager.combat_tick()` runs once per physics frame with a fixed `COMBAT_TICK` (1/60 s); units act in a fixed order (`_combat_order`: each side by tile row then column, interleaved player/enemy, never node order); target ties go to the lower tile (`Board.tile_order`); movement is stepped per tick (`Unit.move_from` / `move_to` / `move_progress`), not tweened. `resolve_combat()` runs a fight to the end instantly. The run RNG is seeded (`GameManager.rng` for random enemies and placement, `PlayerState.rng` for shops and drops); never use `randf()` / `randi()` / `pick_random()` / `shuffle()` in game logic. Tile-to-tile movement on the hex grid (BFS, occupied tiles are walls, units claim their next tile before moving). `attack_range` is in tiles, `move_speed` is tiles/sec. Units target the nearest enemy. Dead units are hidden, not freed, and restored after combat. Player board positions are snapshotted at combat start and restored after. 60 s timeout counts as a loss.

**Unit models:** all 65 units have voxel models (`UnitData.model` -> `scenes/models/<unit>.tscn` -> `models/units/<file base>_{1,2,3}star.glb`; the 55 newer units map display name to animal file base in `menagerie/README.md`, e.g. Militia -> `militia_badger`). The capsule placeholder is only a fallback for a unit without a model. Enemies with a model get an ember ring at their feet (`#ff8a4c`), yours a blue one (`#6cc4ff`); only capsules are painted red. Player units face the enemy side (-Z) at rest and enemies face you; `look_at` turns them in a fight and `end_combat` turns your units back. Animations: walk while `moving`, attack on each swing (sped up when `attack_interval()` is shorter than the clip), skill on a cast, hit when damaged (at most every 0.6 s, never cutting off a swing, cast or death), death when killed, victory for 2.6 s for your survivors after a won fight. A unit with a model that dies stays visible (no bars) while it falls and hides about 1.6 s later; the death is visual only, `dead` and the tile are cleared at once. Enemies are freed when the fight ends (`Unit.leave_fight`): one that is still falling, or still standing after beating you, leaves a `StandIn` (its ModelHolder under Main) that finishes the clip and frees itself. Bars sit just above the model's head (`Unit.bar_height` from the model's height and star). The imported glb materials have vertex colour as albedo switched on at runtime (the importer leaves it off). Glow parts are emissive but the WorldEnvironment has no Environment, so they don't bloom. The 4-star "astral" models are not used (still in `menagerie/models/glb/`).

**Mana:** +10 per attack, +10% of damage taken (max 15 per hit). Resets to `start_mana` each fight. At full mana the unit casts its ability (placeholder: shows a "CAST" popup, does nothing) and mana resets to 0.

**Enemies:** GameManager asks its `OpponentProvider` for an `EnemyBoard` each fight and places it with `spawn_board()` (details: `docs/campaign-and-opponents.md`).
- Free play (`RandomOpponents`): count = player's unit cap, with a 30% chance of +1 or -1. Unit cost limited early (`max_cost = 1 + round/3`). Stats scaled by `enemy_base_scale + enemy_scale_per_round * (round-1)`. Random tiles, no stars, items or synergies (balance unchanged from before).
- Campaign (`WaveOpponents`): the level's authored wave for that round, times the level's `enemy_stat_mult`. Units can have stars, items and set tiles, and get synergies.
- Placement: only unlocked, empty enemy tiles (they unlock with the player's level). A set tile that's locked or taken falls back to the nearest open one; units that don't fit are skipped with a warning. Placed with `put_enemy_on_tile` (never the bench).

**Campaign:** `Campaign` -> `CampaignChapter` -> `CampaignLevel` in `tres/campaign/`. A level has one round per wave plus settings (start gold/level/HP for fresh starts, `start_heal`, income bonus, enemy strength, `loss_damage`, prep time, item drop rounds, allowed shop units) and `unlocks`. Waves (`EnemyBoard`) can have an `hp_reward`.
- **A chapter is one run (roguelite):** the first level starts fresh at 100 HP. Completing a level carries everything into the next level of the chapter: board and bench units (stars, items, tiles/slots), item bar, gold, player level, XP and HP. HP packs: the next level's `start_heal` on arrival plus `hp_reward` for beating certain waves; HP never exceeds the run's start HP.
- A level is complete when every wave is survived **and the last wave is won**; completion is saved. **Defeat ends the chapter run**: Restart chapter goes back to its first level with an empty board. Finishing the last level completes the chapter; the next chapter starts fresh.
- The chapter run is saved (`SaveGame` `chapter_run`) when a level is completed, so quitting and continuing restarts the next level with the saved board.
- End screen: LEVEL COMPLETE with only Next level; CHAPTER COMPLETE with Next chapter (if any) / Play chapter again; DEFEAT with Restart chapter. Levels unlock in order (the first is always open). The round tracker shows "WAVE [pips] x/y" (hover for the level, wave name and enemies) and the standings name the wave.
- `CampaignLevel.validate()` / `Campaign.validate()` report authoring mistakes and run at level start. The sample campaign has 3 chapters of 3 levels each (The Borderlands, The Ashen Frontier, The Shattered Sky; 63 waves in all, every chapter ending in a boss), tuned with `tools/bot_playtest -- chapter` so the difficulty steps down across chapters: with the 65-unit roster the bot completes about 50% of chapter 1 runs, 33% of chapter 2 and 33% of chapter 3 (12-run samples; the bigger shop makes the bot build worse teams, so multipliers were lowered 2026-10-21). A chapter always starts fresh (its first level sets its own gold and level); finishing it unlocks the next chapter's first level and the end screen offers Next chapter. Details and per-level settings: `docs/campaign-and-opponents.md`.

**Async PvP (ghost mode):** the menu's Async PvP starts a free-play run (39 rounds, shared pool, items) with `GameState.ghost_mode` set, so `GameManager` uses `SnapshotOpponents` instead of random enemies. At every fight start in free play and ghost mode, `_record_snapshot()` saves the player's board (units with stars and items, mirrored onto the enemy half by `BoardSnapshot.mirror`: `(x, y) -> (6-x, 7-y)`) with the round, level, HP, a balance hash and the run id to `LocalSnapshotStore`. When PREP starts the provider picks a ghost: same balance hash, same round (or one either side), level at most 1 above yours (nearest preferred), never from this run; the HP standings show it as this round's opponent ("Ghost of <name>" with its recorded HP), and the ghost spawns like any enemy board with synergies. With no match it falls back to random enemies. Ghost fights are deterministic (same boards, same result). Headless runs write to `user://snapshots_headless`, never your real `user://snapshots`. Campaign levels and the tutorial neither record nor use ghosts. Details: `docs/multiplayer-design.md` Part 1.

**Saves:** `SaveGame` (static, no autoload) keeps campaign progress (`completed_levels`: best HP, times, first completion), `unlocks`, the `chapter_run` in progress and the `team_plan` in `user://save.json` (version 2; version 1 files load fine). Writes go through a temp file; an unreadable save is copied to `.corrupt` and progress starts empty. Progress inside a level isn't saved.

**Player HP:** Starts at 100. Loss damage = `round(5 * stage + 0.25 * sum of surviving enemy star levels)`; in a campaign level with `loss_damage` set, that replaces `5 * stage` (rounds restart every level, so the stage stays low). HP 0 = defeat screen; finishing the last round = victory screen (campaign: only if the last wave was won). The standings' HP number turns red at 25% of `start_hp` or less. Restart calls `GameState.reset()` then reloads the scene (campaign: from the chapter's first level).

**Items:** `ItemData` resources in `tres/items/` (Iron Belt +150 HP, Longsword +15 dmg, Quick Bow +15% attack speed, Mana Charm +15 start mana, Chain Vest +10% damage reduction, Blood Fang +10% lifesteal). Details and reasoning in `docs/items-plan.md`.
- **Drops:** a random item from `GameManager.item_roster` at PREP start on rounds in `GameState.ITEM_DROP_ROUNDS` (1-2, 1-3, and the last round of stages 2-6) goes into `GameState.items`. The inventory is unlimited and cleared by `reset()`.
- **Equipping:** drag an item from the item bar onto one of your units (board or bench, any phase, including units that are fighting). Max 3 items per unit; dead units, enemies and full units refuse. Released over the UI, enemies or empty ground, the item stays in the inventory. Fighting units get the boost immediately (HP is added to current health; mana item adds to current mana once).
- **No removal:** items only leave a unit when it is sold (they return to the inventory) or merged (the kept unit takes them up to 3, extras return). Units removed for lack of room also return their items.
- **Stats:** kept in `Unit.item_*` fields, separate from the synergy `bonus_*` fields (those are cleared every combat). Flat HP and damage add to base stats before the star and synergy multipliers (so they scale with stars); attack speed, damage reduction and lifesteal add to the synergy percentages; item mana adds to starting mana. The 60% damage-reduction cap covers both sources.
- **Enemies:** free-play random enemies have no items; campaign waves can give enemies items (`BoardUnit.items`, applied with `Unit.set_items`). Items are saved by `ItemData.id` (never rename an id).

**Synergies:** Each unique unit on the board counts once per tag. `Synergies.apply()` clears and re-applies bonuses at combat start; `Unit.end_combat()` clears them again.

| Tag | Thresholds | Bonus | Scope |
|---|---|---|---|
| Order | 2 / 3 | +20% / +40% max HP | tag |
| Wild | 2 / 3 | +15% / +30% attack speed | tag |
| Shadow | 2 | 20% lifesteal | tag |
| Arcane | 2 | +10% damage | team |
| Warrior | 2 | 20% damage reduction | tag |
| Ranger | 2 | +25% attack speed | tag |
| Caster | 2 | +20 starting mana | tag |
| Protector | 2 | 10% damage reduction | team |
| Rogue | 2 | +40% damage | tag |
| Undead | 2 / 4 | 15% / 30% lifesteal | tag |
| Ember | 2 / 4 | +20% / +45% damage | tag |
| Frost | 2 / 4 | 15% / 30% damage reduction | tag |
| Fey | 2 / 4 | +15% / +40% attack speed | tag |
| Dwarven | 2 / 4 | +10% / +25% max HP | team |
| Infernal | 2 / 3 | +15% / +40% damage | tag |
| Healer | 2 / 4 | 6% / 15% lifesteal | team |
| Summoner | 2 / 3 | +15% / +35% max HP | tag |
| Monk | 2 / 4 | +20% / +45% attack speed | tag |
| Alchemist | 2 / 3 | +8% / +20% damage | team |
| Bard | 2 / 4 | +10 / +25 starting mana | team |
| Dragonlord (Dragon) | 1 | +15% damage | team |
| Ascendant (Seraph) | 1 | 10% lifesteal | team |
| Lich King (Deathlord) | 1 | 40% lifesteal | tag |
| Earthshaker (Titan) | 1 | +20% max HP | team |
| Inferno (Pyromancer) | 1 | +35% damage | tag |
| Crusade (Paladin) | 1 | 8% damage reduction | team |

Every unit has one origin and one class tag; the six **unique** synergies (threshold 1, shown 1/1) are a third tag held by exactly one unit (4 five-cost, 2 three-cost units). The full list is in `docs/units.md`.
Damage reduction is capped at 60%.

---

## Unit roster

65 units: 14 one-cost, 13 two-cost, 14 three-cost, 14 four-cost, 10 five-cost. Full stat tables, labels and synergy list: **`docs/units.md`**. The original 10 live in `tres/*.tres`, the other 55 in `tres/units/*.tres`; all are in Game Manager's `unit_pool` in main.tscn.

- Display names must be unique (merging groups by name). Tag spelling must match the keys in `Synergies.DEFS` exactly.
- `UnitData.short_name` is the 2-3 letters drawn on the unit's body (`UnitData.label()`); each is unique.
- To add a unit: create the .tres, add it to `unit_pool` in main.tscn, then run `tools/roster_checks` (unique names/labels, valid tags, every synergy tier reachable, unique synergies have one holder; update its `EXPECT` counts if the roster size changes).
- UI that lists units or tags scrolls (team planner grid, synergy box) because of the roster size.
---

## UI behaviour

- The game opens on the main menu (see menu.tscn above). Esc closes its Campaign/Settings/Keybinds/info panels.
- **Keybinds** (main menu > Keybinds; `keybinds.gd`, class Keybinds, static, saved in `user://keybinds.cfg`): two tabs, Keyboard & mouse and Controller. Click a bind, press the new key / pad button (Esc cancels); a key or button already used by another action swaps over; Reset to defaults. Keyboard defaults: F sell, E Buy XP, D reroll, L lock shop, P planner, = / - zoom (plus keypad + / -), Home reset view. Controller defaults: A select, X inspect, Y sell, B back, Start menu, Back planner, LB Buy XP, RB reroll, L3 lock, R3 reset view. Fixed (shown, not rebindable): the mouse, Esc (menu / back, so you can't lock yourself out), the sticks, the D-pad (it can't be bound) and the triggers. Scripts test keys with `Keybinds.pressed(event, "sell_unit")` (InputMap actions `kb_<id>`, made on first use) and pad buttons with `Keybinds.pad_action(button)`; never hard-code a key again. While the screen waits for a pad button, `Keybinds.pad_capture` gets it instead of gamepad_controls. Check suites that press shortcuts point `Keybinds.path` at a throwaway file so the player's binds can't break them.
- **Controller** (PC; `gamepad_controls.gd`, autoload): the pad drives the mouse pointer and presses the game's own mouse buttons and keys, so every screen works without pad-specific code. Left stick moves the pointer (squared response, D-pad for fine moves), A = left click (hold to drag units / items), X = inspect (right-click), Y = sell (F), B = back (closes the planner or menu, else the inspector; never opens the menu), Start = menu (Esc), Back/Select = planner (P), LB / RB = Buy XP / Reroll, LT / RT = zoom out / in, right stick = pan, L3 = lock the shop, R3 = reset the view. Moving the real mouse hands the pointer back to it. The pause menu lists the buttons while a pad is connected (`pause_menu.gd` `pad_help`).
- **Touch controls** (phones and tablets; `touch_controls.gd`, autoload). The first finger is a left mouse button (Godot's `emulate_mouse_from_touch`), so tapping, buying, dragging units and items and one-finger panning work as with a mouse. On top: tap a unit to inspect it (tap empty ground closes the inspector); long press (0.45 s) a unit does the same; long press anything in the HUD with a tooltip shows it above the finger and lifting presses nothing; two fingers pinch to zoom and move to pan (a second finger cancels a unit or item drag); the Android back button acts as Esc. Events the touch layer sends (right-clicks, pointer moves) are converted to window coordinates (`_window`), because the stretch mode scales the game. Mobile settings in project.godot: landscape (`window/handheld/orientation=4`, sensor landscape), `quit_on_go_back=false`, native tooltips off on mobile (`tooltip_delay_sec.mobile`). The sell zone reads "SELL" without "(F)" on mobile.
- **Mobile export (not set up yet):** needs Android export templates and the Android SDK / JDK set in Editor Settings (or Xcode on a Mac for iOS), then Project > Export > Add Android. The renderer is already GL Compatibility (`rendering_method.mobile`). Text is small at phone size (10-12 px in a 1152 x 648 view): check it on a real phone.
- **Tutorial** (`tres/campaign/tutorial.tres`, id `tutorial`, not part of any chapter): 5 easy waves, Knights and Clerics only, 10 start gold, 2 HP per lost wave, a 600 s safety prep timer. The TutorialPanel walks through the basics (including selling units and locking the shop; the lock step needs lock then unlock so the shop is never left locked) and its **Start fight** button ends prep early. "Watch the fight" waits for Next so a quick win doesn't skip it. A Longsword is handed out at the items step if the player has no item. The end screen shows TUTORIAL COMPLETE (Replay tutorial / Main menu) or DEFEAT (Try again). Completion is saved like a level. Levels outside a chapter (`GameManager._in_chapter`) never create, change or clear the saved chapter run. Starting a chapter while a chapter run is saved asks before abandoning it.
- During a run, Esc opens the pause menu (the whole tree pauses, including the prep timer, which is created with `process_always = false`); Esc again resumes. Not available once the run has ended. Leaving a campaign level for the menu keeps the chapter run as saved at the start of that level.
- The end screen always has a Main menu button (below Next level / Restart).

- **Shop lock:** the Lock button (next to Reroll) keeps the current offers into the next round instead of rolling a new shop (`GameManager.shop_locked`); bought slots stay empty. Reroll is disabled while locked (the button greys out; `_on_reroll` ignores it); unlock first, and a reroll then replaces all five offers. It stays locked until clicked again. A new run starts unlocked.
- **Side boxes** (from `menagerie/hud/DOCKS_SPEC.md`, built 2026-10-22). Deviation from the spec: the right box sits top right (where the old button bar was), not between the timer and the standings, because the reworked top bar is wider than the spec's; the standings move down under it.
- **Right box** (top right): tabs [Damage] [Planner P] [Menu Esc], one panel open at a time; clicking the open tab closes it. The damage panel is the resting one: open/closed is remembered in `Settings.show_damage_meter` (default open) and it comes back when the planner or the menu closes. The standings sit just below the box (pushed down to y = 300 at most, hidden under a taller panel) and the tutorial panel stays below the standings (but on screen).
- **Damage panel:** "THIS FIGHT / LAST FIGHT · DAMAGE DEALT/TAKEN" with the total, a Dealt | Taken switch, one row per unit that fought (portrait, name and stars, value, a bar scaled to the top value: gold dealt, sky blue taken), sorted, live during combat and kept until the next fight ("No fights yet" before the first). Values are HP actually removed (after damage reduction, no overkill): `Unit.take_damage()` returns it.
- **Team planner** (Planner panel): the Planner tab or **P** opens it; Esc or P closes it (Esc closes the planner before the menu opens). Cost tabs 1-5 pick which units show (5-column grid of portraits, "x2" when owned, gold outline and check when planned, a cost-colour strip); click a tile to add/remove it from the plan. Below: "n of m planned at c gold" and the planned synergies as chips (count/next threshold, gold when active).
- **Menu panel:** Esc or the Menu tab; pauses the tree and dims the board behind the HUD (`#0a0b11` at 50%). Resume, Main menu, Quit game (not on Web). Not available once the run has ended. Planned units in the shop get a "* " and a gold border. The plan is saved (`SaveGame.team_plan`) and isn't cleared by Reset campaign progress.
- Shop stays visible during combat. Shop slots and Buy XP work during combat (bought units go to the bench only); reroll is blocked outside PREP. Design decision: the shop is deliberately NOT dimmed during combat (it stays fully visible and usable); don't add dimming.
- Right-click any unit (ally or enemy) to open the Unit Inspector (stats at the current star with items and synergy bonuses folded in, tags, item list; the synergy part isn't called out in the text: before a fight it shows what the unit's team on the board would get via `Synergies.preview`, during a fight the real bonuses; benched units get none). Right-clicking empty space closes it; it also closes if the unit dies or is removed.
- **Left box** (top left): Synergies and Items tabs with count badges (active synergies; items owned, duplicates counted) and a collapse button; collapsed it is a 46 px rail (expand chevron, a button per tab with its badge). Collapsed/open and the last tab are remembered (`Settings.dock_collapsed`, `dock_tab`).
- Items tab: one row per item type (icon from `textures/ui/items/`, name, description, "x2"), hover for a tooltip. Press a row, drag it onto a unit and release to equip; a label with the item name follows the mouse. Units (board and bench) show a row of small coloured squares above their health bar, one per item in the item's colour (`Unit._update_item_icons`; the row is top_level so it stays level when the unit turns).
- Synergies tab: one row per tag on the board, active first, then by count: the count in a hexagon (gold = every tier reached, darker gold = some, slate = none), the name, the tier numbers (gold once reached), and for active rows the effect at the reached tier (`DockKit.effect_text`). Tooltips show the effect and all tiers. Scrolls past about 360 px.
- Odds, streak and unit cap sit above the shop bar.

---

## Conventions and gotchas

- **Tooltips must be wrapped.** Godot does not wrap tooltip text, so a long single line runs off the screen (the Async PvP tooltip was 1783 px wide in a 1152 px window). Always write `tooltip_text = Tip.wrap("...")` (or `return Tip.wrap(...)` from `_get_tooltip`); `Tip.wrap` breaks lines at 340 px using the real font, keeping your own newlines. Keep tooltips short anyway. `tools/tooltip_checks` builds every screen and measures every tooltip (the free-play HUD, planner, items, all synergy tags, menu panels, campaign stage label, tutorial); run it after adding any tooltip.
- One function per name per script: Godot errors on duplicates, and many past bugs were leftover copies of replaced functions.
- When looping over untyped arrays or dictionaries, type variables explicitly (`var c: Vector2i = key`) to avoid "cannot infer type" errors.
- Exported scene references (`@export var tile_scene`) reset when a script is re-attached; prefer `preload`.
- Units must be instances of `unit.tscn` under `Board/Units`; `unit.gd` finds the board via `get_parent().get_parent()` and needs `ModelHolder`.
- Never place enemies with `put_on_tile` (it falls back to the bench); use `put_enemy_on_tile`.
- Combat is deterministic; keep it that way: no tweens or frame delta in combat logic, no unseeded random (see Combat rules). Run `tools/combat_checks` after touching combat.
- `game_manager.gd` joins group `game_manager`; other scripts find it with `get_first_node_in_group` (its node name "Game Manager" has a space, so path lookups are fragile).
- `GameManager.unit_pool` is the roster export (all unit types). The limited-copies pool is `GameManager.shared_pool` (UnitPool). Don't confuse them, and don't rename the export (main.tscn stores its value by name).
- Testing without the editor: `Godot_v4.7.2-stable_win64.exe --headless --path . --quit-after 600` runs the main scene for ~10 s and prints script errors. Autoloads don't exist in `--script` mode, so test scripts that touch GameState/Events must run through the main scene. After adding a new `class_name` script, headless runs don't know the class until Godot rescans: open the editor, or run `--headless --path . --import` once.
- Balance check for the campaign: `Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/bot_playtest.tscn --fixed-fps 60 -- chapter` (12 bot chapter runs per chapter with carried boards, about a minute each; `-- chapter2` plays only chapter 2). When adding or changing a chapter, sweep each level's `enemy_stat_mult` until the clear rates step down (about 80% / 70% / 50% per level) and compare chapters with each other. Without arguments it plays each level fresh; add level paths after `--` for single levels, or `-- free` for a 15-round free-play smoke test.
- Regression checks for opponents, campaign and saves: `... res://tools/campaign_checks.tscn --fixed-fps 60` (80 checks, ~25 s; must end with `RESULT: ALL PASS`; tests override Debug Level, so main.tscn's setting doesn't matter). Run it after changing game_manager.gd, GameState.gd, the campaign scripts or save_game.gd.
- Menu checks: `... res://tools/menu_checks.tscn --fixed-fps 60` (31 checks through real scene changes: menu buttons and sections, the scrolling three-chapter campaign panel and locked Start buttons, the 648 px fit, PvP info panels, Tutorial start and done label, Free Play, Campaign panel and Start chapter, Continue, abandon-run confirmation, pause/resume, back to menu, settings saved, reset progress, menu choice beats Debug Level). Run it after changing the menus, end screen, GameState or SaveGame.
- HUD checks: `... res://tools/hud_checks.tscn --fixed-fps 60` (64 checks, including the top bar timer, folding the top bar (and staying centred), camera zoom limits and panning bounds, pause stopping the prep countdown, the HP standings layout (right edge, y 129, 210 px, meter drawn over them, inspector bottom right) and the inspector with synergies: shop lock across rounds, reroll blocked while locked, unlock + reroll refills all five slots, damage numbers and meter, top-right bar toggles, team planner, shop highlights, Esc order, plan saved, synergy/item fold headers; uses its own settings and save files). Run it after changing the shop, damage/combat code, synergies or the planner. Wait for phases with `await Events.phase_changed`, not by polling: a fight with no player units ends within one physics frame.
- Combat checks: `... res://tools/combat_checks.tscn --fixed-fps 60` (16 checks: auto-fill from the bench (cap, leftmost first, front/back rows, stays after the fight), the same fight resolved repeatedly, real time == `resolve_combat()`, node order irrelevant, target ties, seeded shops/enemies/drops, per-player state). `-- realtime` prints the fight's SIGNATURE line; compare it across `--fixed-fps 30` and `--fixed-fps 144` runs to prove frame-rate independence.
- Tutorial checks: `... res://tools/tutorial_checks.tscn --fixed-fps 60` (27 checks: every tutorial step with game actions, Watch waiting for Next, sell and lock steps, Start fight, end screen, saved chapter run untouched by winning or losing the tutorial). Run after changing the tutorial, end screen, GameManager phase flow or the chapter-run code.
- PvP checks: `... res://tools/pvp_checks.tscn --fixed-fps 60` (33 checks: board mirroring and hex distances, snapshot capture/JSON round trip, balance hash, the local store (fetch rules, neighbouring rounds, level fit, corrupt files, pruning), the ghost provider and its fallback, a ghost fight twice, recording in free play, the ghost in the standings). Uses its own snapshot folder. Run after changing snapshots, opponent providers, GameManager.start_combat or the units/items stats (the balance hash). New tests that start free-play or ghost runs headless are safe: they write to `snapshots_headless`.
- Controller checks: `... res://tools/gamepad_checks.tscn` (simulated pad buttons and sticks in a free-play run: pointer, A buy / drag, X inspect, Y sell, B back, Start / Back, LB / RB, L3 lock, triggers zoom, right-stick pan, R3 reset, the mouse taking over).
- Touch checks: `... res://tools/touch_checks.tscn` (simulated finger touches in a free-play run: tap to buy, drag to place, tap / long-press to inspect, long-press tooltips that don't press the button, items, pinch, two-finger pan, back button). Simulated touches are in window coordinates (`get_tree().root.get_final_transform() * p`); the headless window is tiny, so viewport positions must be converted.
- Roster checks: `... res://tools/roster_checks.tscn` (checks the 65-unit roster and the synergy table; no `--fixed-fps` needed). Run it after adding or changing units or synergies.
- Tooltip checks: `... res://tools/tooltip_checks.tscn --fixed-fps 60` (12 checks: the measurement itself, a control case proving an unwrapped tooltip is flagged, and every tooltip on the menu panels, a free-play run, the biggest campaign wave and the tutorial; 44 distinct tooltips, widest line 339 px against a 360 px limit). Run it after adding or changing any tooltip or the text in one.
- When a test awaits a game signal (e.g. `combat_ended`), read what it needs right away and `await get_tree().process_frame` before freeing the scene: freeing it inside the signal crashes Godot.
- The main scene is menu.tscn. To jump straight into a run while testing, open main.tscn and press F6 (Run Current Scene); Debug Level applies there.
- Never use a level's `id` for two levels, and never rename one: the save file keys progress by it.

---

## Current status (2026-10-22)

- Working: full run loop (prep/combat/result over 39 rounds), economy, leveling, board unlocks, shop odds, shared unit pool, merging, selling, synergies, items, unit inspector, end screen, opponent providers, campaign chapter runs with carried boards, campaign saves, main menu with settings, pause menu.
- Done and committed (8962b5b): opponent providers, campaign structure with chapter runs, save system (design decisions at the end of `docs/campaign-and-opponents.md`).
- Done and committed (19088de): main menu with the working title AZTactics, settings, pause menu.
- Done and committed: shop lock (59e5cb6, d55302b), damage meter, team planner, HUD button bar, fold-out lists.
- Done and committed (cdd6999): deterministic combat (roadmap 10), per-player state (roadmap 11), seeded run RNG, `docs/multiplayer-design.md`.
- Done and committed (c609132): main menu split into Single player (Tutorial, Campaign, Free Play) and PvP (Async/Live placeholders with info panels); a guided tutorial level with a step panel and Start fight; `GameManager.end_prep_early()`; fix so levels outside a chapter can't touch the saved chapter run; `tools/tutorial_checks` (27) and more `menu_checks` (28). A flaky crash in `combat_checks` (test freed the scene mid-signal) fixed. Not yet played by hand.
- Done and committed (50370a3, 27b7363): synergy bonuses in the inspector stats, prep/combat timer label, chapters 2 and 3, bot chapter mode, stray .tmp files removed.
- Done and committed (24a1a97): 65-unit roster (14/13/14/14/10 by cost), 21 synergy tags plus 6 unique 1/1 synergies, `short_name` labels, `tools/roster_checks`, `docs/units.md`, campaign retuned for it. Async PvP Part 1 is in the same commit.
- Done and committed (24c87fc, 2026-10-22, playtested): **combat HUD, Part 2** from `menagerie/hud/HUD_SPEC.md`, then reworked from a TFT reference: one slim foldable top bar flush with the top (rounds + timer), a TFT-like camera with mouse-wheel zoom, HP standings at the right edge (the damage meter overlays them while open, as the user chose), unit inspector moved to the bottom right, tutorial panel moved below the standings. The pixel/label fonts aren't in the project yet (fallbacks are used; see `hud_style.gd`). Deviation from the spec: the campaign round tracker keeps a tooltip (level, wave, enemies) so the old stage label's enemy preview isn't lost.
- Committed in 2c8a511 (2026-10-22, from the menagerie art chat, **awaiting playtest**): **keybinds**: main menu Keybinds screen (keyboard and controller, rebindable, saved), `keybinds.gd`; the hard-coded keys (F, P, + / -) and pad buttons now go through it; new keyboard shortcuts Buy XP (E), Reroll (D), Lock (L), Reset view (Home); `tools/keybinds_checks`.
- Committed in 2c8a511 (2026-10-22, from the menagerie art chat, **awaiting playtest with a real pad**): **controller support** on PC: `gamepad_controls.gd` autoload (pointer on the left stick, buttons as clicks and shortcuts), controller legend in the pause menu, `tools/gamepad_checks`; all 10 suites pass.
- Committed in 2c8a511 (2026-10-22, from the menagerie art chat, **awaiting playtest on a phone**): **touch controls** for a mobile version: `touch_controls.gd` autoload (tap / long-press inspect, long-press tooltips, pinch zoom, two-finger pan, back button), mobile settings in project.godot, `tools/touch_checks` (all 9 suites pass). Not tried on a real device yet; no export preset made.
- Committed in 2c8a511 (2026-10-22, from the menagerie art chat, **awaiting playtest**): **shop bar** rebuilt in the style of the user's shop mockup (Desktop/Art assets/autochess ui = textures/ui/shop): level/XP/gold panel, Buy XP, Reroll, Lock, unit cards with portraits, traits, cost and owned pips. Same behaviour and node names (HBoxContainer/BuyXPButton, RerollButton, lock_button, slots). Cards are laid out sideways (the mockup's tall cards would cover the bench). `gold_label.gd` and `label.gd` are now unused. hud_checks' shop-plan checks use `ShopSlot.shown_name()` / `planned`; all 8 suites pass.
- Committed in 2c8a511 (2026-10-22, from the menagerie art chat, **awaiting playtest**): **side boxes** from `menagerie/hud/DOCKS_SPEC.md`: the left box (Synergies / Items) and the right box (Damage / Planner / Menu) replace SynergyBox, ItemBar, TopRightBar, DamageMeter, TeamPlanner and PauseMenu. New scripts `left_dock.gd`, `right_dock.gd`, `dock_kit.gd`; the panel scripts (synergy_panel, item_bar, damage_meter, team_planner, pause_menu) were rewritten in place; `hud_buttons.gd` is now unused. Portraits for all 65 units in `textures/ui/portraits/`, item icons in `textures/ui/items/`. Settings `show_synergies` / `show_items` became `dock_collapsed` / `dock_tab`. hud_checks rewritten for the boxes (menu_checks and tooltip_checks paths updated); all 8 suites pass with Godot 4.7.2.
- Committed in 2c8a511 (2026-10-22, from the menagerie art chat, **awaiting playtest**): **unit models, Part 2**: the other 55 units got their voxel models the same way as Part 1 (165 glbs in `models/units/`, 55 wrapper scenes in `scenes/models/`, `model` set in each `tres/units/*.tres`), and `only_units_with_models` now defaults to off, so the full 65-unit roster is back in play (campaign balance is as tuned again). All 8 check suites passed on a copy of the project with Godot 4.7.2, including combat_checks. No script other than that one default changed.
- Done and committed (24c87fc, 2026-10-21, playtested): **unit models, Part 1**: the 10 original units use the voxel models with star swaps, team rings, facing and animations. Same commit: the TFT-style camera with zoom and drag-to-pan. Then committed: shop UI art and HUD mockups (e28fcf1), bench auto-fill at fight start (b6f784c).
- Next: playtest what 2c8a511 added (side boxes, shop bar, keybinds, the 55 new unit models; controller with a real pad, touch on a phone). Fonts: add Jersey10-Regular.ttf and AtkinsonHyperlegible-Bold.ttf (Google Fonts, OFL) to `res://fonts/` for the intended look.
- After that: playtest Async PvP (play a few free-play runs first so ghosts exist), then mid-level saves (needs a design: see the handoff in the roadmap), then item combinations. Volume has no effect until there's sound.
- Ideas for later: `docs/item-ideas.md` (item mechanics brainstorm; resonance/item combinations first).

## Known issues

No blocking issues. Small things left:

1. **[Sonnet] Combat, items, the menu, tutorial and the new HUD are not tested by hand** after the 2026-10-21 changes: play a few rounds and check merging, selling, buying during combat, item drops, dragging items onto units, and the item bar layout.
2. **[Sonnet] Playtest the 55 new unit models** (2026-10-22): check each looks right at 1-3 stars in the shop flow, faces the right way and animates. `only_units_with_models` is now off by default; the switch can be deleted once the models are approved.

If a combat bug survives two fix attempts, stop and recommend Opus 5.5 (see Model guidance).

---

## Roadmap

Goal: a **campaign mode** and a **PvP mode** sharing the same core game.

Model tags: **[Sonnet]** = do directly. **[Opus]** = recommend switching before starting. **[Opus plan, Sonnet build]** = use Opus to design it (data format, which scripts change), then Sonnet can implement the plan.

### Phase 1: Shared core
1. Abilities **[Opus plan, Sonnet build]**: real designs deferred until unit visuals exist; placeholder system is in place.
2. ~~Shared unit pool~~: done (see Game rules).
3. ~~Items~~: done (see Game rules and `docs/items-plan.md`). Not yet playtested by hand.
4. ~~Opponent provider layer~~: done (`EnemyBoard` format, `RandomOpponents`, `WaveOpponents`, `spawn_board`; see `docs/campaign-and-opponents.md`).

### Phase 2: Campaign
5. Hand-authored waves as resources (plus bosses) **[Sonnet]**: format and 3 chapters of 3 levels (63 waves, 9 bosses) done, tuned with the bot; more chapters and hand balancing still to do. Check difficulty with `tools/bot_playtest -- chapter`.
6. ~~Campaign structure~~: done (chapters as roguelite runs with carried boards, levels, modifiers, HP packs, unlock order, final-wave rule, end screen).
7. ~~Save system~~: done for progress, unlocks and the chapter run in progress (`SaveGame`). Progress inside a level isn't saved.
8. ~~Main menu with mode select~~: done (menu.tscn: Continue, Campaign, Free Play, Settings, Quit; pause menu; see UI behaviour).

### Phase 3: PvP
9. Board snapshots **[Sonnet]** (part of async PvP Part 1) in the same format as waves (`EnemyBoard.to_dict()` / `from_dict()` exist); add a snapshot `OpponentProvider`; fight your own past boards offline.
10. ~~Deterministic combat~~: done (fixed ticks, fixed order, tie-breaks, seeded RNG; `tools/combat_checks`).
11. ~~Per-player state~~: done (`PlayerState`, `GameState.me` / `players`).
12. **Async PvP**: Part 1 (local ghost opponents) is done, including item 9's snapshots (see `docs/multiplayer-design.md`). Part 1b, an HTTP snapshot store so ghosts come from other players, is not built (needs a small web service; hosting decision).
12b. **Mid-level saves** **[Opus plan, Sonnet build]**: save partway through a level (today only the start of each chapter level is saved). Needs a design for what a mid-level save holds (round and phase, board, bench, items, shop offers and lock, shared unit pool, gold/level/XP/HP/streaks, run seed and RNG state, enemy board for the round) and when it's written (end of every round?), plus resuming into the right phase and cleaning up on defeat or chapter completion. Touches `SaveGame`, `GameManager.make_carry` / `_restore_carry` and `PlayerState`.
13. Live 8-player lobbies with a dedicated server **[Opus]** (optional): designed in `docs/multiplayer-design.md` Part 2, not built; needs the decisions listed there.

### Phase 4: Polish
14. **[Sonnet]** Combat speed button, 4-star models (all 65 units have 1-3 star models; the 4-star "astral" glbs are in `menagerie/models/glb/` and need a design decision: Unit.set_star caps at 3), animations, sound, VFX, menus and settings.
