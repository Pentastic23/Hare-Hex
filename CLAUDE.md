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
  tres/          UnitData .tres files (one per unit type) + panel_style.tres (shared StyleBoxFlat)
  tres/items/    ItemData .tres files (one per item)
  tres/campaign/ campaign.tres -> chapter_1..3.tres -> levels/ch1_l*, ch2_l*, ch3_l*.tres (waves embedded in each level); tutorial.tres
  tools/         dev tools, not part of the game (bot_playtest.tscn, campaign_checks.tscn, menu_checks.tscn, hud_checks.tscn, combat_checks.tscn, tutorial_checks.tscn)
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
 └─ CameraRig (Node3D)            pos (6, 0, 7)
     └─ Camera3D                  pos (0, 10, 9.5), rot ~(-55, 0, 0)
```

The Game Manager exports set in main.tscn: `prep_time = 15`, `unit_pool` = all 10 unit .tres files (this is the **roster**, not the shared pool), `item_roster` = the 6 item .tres files, `enemy_base_scale = 0.4`, `enemy_scale_per_round = 0.05` (free-play random enemies). `debug_level` (CampaignLevel) is empty: it only matters when main.tscn is run directly (F6 in the editor) to jump straight into a campaign level for testing; runs started from the main menu ignore it (`GameState.launched_from_menu`). Always load a level **file** into it; a "New CampaignLevel" has no waves, so the game warns and plays free play instead. `continue_saved_run` (default on): with Debug Level set, running main.tscn directly continues the saved chapter run if it's in the same chapter.

**menu.tscn** (the project's main scene, `run/main_scene`): a full-screen Control with `main_menu.gd`, which builds everything in code: title "AZTactics", Continue (only with a saved chapter run), then **SINGLE PLAYER**: Tutorial ("(start here)" for new players, "(done)" once completed), Campaign panel (chapters, levels with status: Completed/best HP, Not completed, Locked; Start chapter), Free Play; then **PVP** (tinted blue): Async PvP and Live PvP, both "coming soon" placeholders that open an info panel; then Settings / Quit on one row. The menu must fit a 648 px tall window (`menu_checks` measures it). Starting a run sets `GameState.run_level` / `run_campaign` / `run_carry` / `launched_from_menu`, calls `reset()` and changes to main.tscn.

**ui.tscn** (root `UI`, CanvasLayer):

```
UI
 ├─ TopBar (HBoxContainer, top center)
 │   ├─ Timer (Label)             phase_timer.gd: "Prep 0:12" countdown, "Combat 0:48" countdown to the 60 s fight limit (red/orange near the end; just "Prep" in the untimed tutorial)
 │   └─ StageLabel                stage_label.gd ("Stage 2-4", or "Level name   Wave 2/5: Wave name" in a campaign, tooltip lists the wave's enemies)
 ├─ ShopPanel (PanelContainer, bottom center)   shop_panel.gd
 │   └─ HBoxContainer
 │       ├─ StatBox/VBoxContainer: Gold (gold_label.gd), Level (label.gd = XP/level label)
 │       ├─ BuyXPButton, RerollButton
 │       └─ "Slot 1" .. "Slot 5"  (ShopSlot, shop_slot.gd)
 ├─ BottomInfo (VBoxContainer)    bottom_info.gd
 │   ├─ OddsLabel                 odds_label.gd
 │   └─ InfoRow (HBox): BoardLabel (board_label.gd, unit cap), StreakLabel (streak_label.gd)
 ├─ HpLabel                       hp_label.gd (bottom right, just above the shop bar; offsets set in code)
 ├─ "End Screen" (ColorRect)      end_screen.gd
 │   └─ CenterContainer/Backing/Margin/VBoxContainer: TitleLabel, DetailLabel, RestartButton (a "Next level" button is added in code, campaign only)
 ├─ SynergyBox (PanelContainer, panel_style.tres)
 │   └─ SynergyPanel (VBoxContainer)   synergy_panel.gd (fold header button + list, built in code)
 ├─ UnitInspector (PanelContainer, panel_style.tres)   unit_inspector.gd
 │   └─ VBoxContainer: NameLabel, TagsLabel, ItemsLabel, StatsLabel
 ├─ ItemBar (PanelContainer, panel_style.tres, left of screen below center)   item_bar.gd
 │   └─ Grid (GridContainer, 2 columns): item buttons built in code
 ├─ TopRightBar (HBoxContainer, top right)   hud_buttons.gd: Damage / Planner / Menu buttons (built in code)
 ├─ DamageMeter (PanelContainer, top right under the bar, mouse ignore)   damage_meter.gd (rows built in code; group "damage_meter")
 ├─ TutorialPanel (PanelContainer, right side, below the meter)   tutorial.gd (only visible in the tutorial level; built in code)
 ├─ TeamPlanner (PanelContainer, centered, hidden)   team_planner.gd (built in code; group "team_planner")
 └─ PauseMenu (Control, full screen, last child so it draws on top)   pause_menu.gd
```

Several node names contain spaces ("Game Manager", "End Screen", "Slot 1"). Any `get_node` path must use the exact name.

`unit.tscn`: root Node3D with `unit.gd`, children `ModelHolder` (Node3D, holds a capsule MeshInstance3D at y = 1) and `Area3D` (layer 2, for picking). Health bar, mana bar and letter label are created in code.
`Tiles.tscn`: StaticBody3D root with `tile.gd` (collision layer 1), 6-sided CylinderMesh (radius 0.95, no rotation applied in the scene). Hex layout math in board.gd is **pointy-top**.

---

## Autoloads

- **Events** (`events.gd`): all global signals, plus `enum Phase { PREP, COMBAT, RESULT }`.
- **GameState** (`GameState.gd`): **run-wide** state only: `round_number`, stage math, shop odds table, `base_income_for_round`, `ITEM_DROP_ROUNDS` / `item_drop_rounds()`, `damage_for_loss`, `reset()` (round + every player), and the run setup: `run_level` (CampaignLevel or null = free play), `run_campaign`, `run_carry` (chapter run state for the next level), `run_carried`, `run_seed` / `next_seed` (set `next_seed` before a run to replay it exactly), `begin_run(level, campaign) -> carry`, `launched_from_menu`, `MENU_SCENE`, `go_to_menu()`. `run_level` / `run_campaign` / `run_carry` survive `reset()`.
  - **Per-player state is in `PlayerState`** (`player_state.gd`): `GameState.me` is the local player, `GameState.players` everyone in the run (just `[me]` for now). Fields: `gold`, `level`, `xp`, `player_hp`, `start_hp` (HP-pack cap), `win_streak` / `loss_streak`, `items`, `cheap_shop`, `shop_offers`, `shop_locked`, `shop_has_rolled`, `last_combat_won`, `rng` (this player's shop and drops, seeded from the run seed and `id`). Methods: `xp_needed`, `add_xp`, `max_board_units`, `interest_gold`, `total_income_for_round`, `record_result`, `streak_bonus`, `heal`, `reset`. Only a player with `is_local` emits the HUD signals (gold_changed, hp_changed, xp_changed, streak_changed, items_changed). **Always write `GameState.me.gold` etc.; `GameState.gold` no longer exists.**

Signals in Events: `phase_changed`, `gold_changed`, `shop_rolled`, `unit_bought`, `combat_ended`, `xp_changed`, `reroll_pressed`, `buy_xp_pressed`, `board_limit_hit`, `round_changed`, `streak_changed`, `hp_changed`, `unit_sold(data, star, refund)`, `run_won`, `run_lost`, `items_changed`, `item_drag_started(index)`, `item_drag_ended`, `shop_lock_changed(locked)`, `team_plan_changed`.

---

## Core scripts

| Script | Responsibility |
|---|---|
| `board.gd` (class Board) | Hex grid (7 cols x 8 rows; rows 0-3 enemy, 4-7 player), bench (9 slots), sell zone, tile unlocking by level, seam border, hex math + BFS pathfinding, merging, selling |
| `tile.gd` (class Tile) | `coord`, `occupant`, `unlocked`, pop-in animation |
| `unit.gd` (class Unit) | Stats, star level, combat step (tick-stepped movement, `take_damage` returns HP removed), health/mana bars, letter label, synergy bonus fields, items (`items`, `item_*` fields, `equip` / `set_items` / `take_items`, item icons above the health bar), placeholder ability casting |
| `item_data.gd` (class ItemData) | Resource: stable `id`, name, description, color, stat boosts (hp, dmg, attack_speed, mana, damage_reduction, lifesteal) |
| `item_bar.gd` | Inventory panel: one button per item, starts item drags, drag ghost label |
| `unit_data.gd` (class UnitData) | Resource: name, cost, stats, tags, mana, model, ability |
| `ability.gd` (class Ability) | Resource base class; `cast(caster, target)` does nothing yet (placeholder) |
| `synergies.gd` (class Synergies) | Static synergy table + count (units) / count_data (UnitData, for the planner) / active_tier / next_threshold / apply |
| `hud_buttons.gd` | Top-right bar: Damage (toggles the meter), Planner (toggles the team planner), Menu (pause menu); toggles stay in sync with P / Esc / Close |
| `damage_meter.gd` | Damage dealt/taken per unit in the current or last fight (from `GameManager.snapshot` and `Unit.damage_dealt` / `damage_taken`) |
| `team_planner.gd` | Team planner panel: toggle planned units (saved as names in `SaveGame.team_plan`), planned synergies, owned counts |
| `game_manager.gd` | Run setup (`_begin_run`: free play or campaign level, shop roster, opponent provider), phase loop (PREP counts down `prep_left` in `_process`, so pausing stops it and the Timer label can show it; `end_prep_early()`), shop rolling (from `shared_pool`), buying, enemy spawning (`spawn_board`), combat loop, end of combat (HP packs), run end (records campaign completion; `make_carry` / `_restore_carry` move the board between chapter levels) |
| `enemy_board.gd` (class EnemyBoard), `board_unit.gd` (class BoardUnit) | The enemy-side format: units with star, coord, items; `stat_scale`, `use_synergies`; `to_dict()` / `from_dict()` for saves and snapshots |
| `opponent_provider.gd` (class OpponentProvider) | `board_for_round(round) -> EnemyBoard`; implemented by `random_opponents.gd` (free play) and `wave_opponents.gd` (campaign) |
| `campaign.gd`, `campaign_chapter.gd`, `campaign_level.gd` | Campaign data: chapters, levels (waves + modifiers + rewards), unlock order, `validate()` |
| `save_game.gd` (class SaveGame) | Static save system: campaign progress, unlocks and the chapter run in `user://save.json` |
| `main_menu.gd` | Main menu (menu.tscn): Continue; Single player (Tutorial, Campaign panel, Free Play); PvP placeholders (Async, Live) with an info panel; Settings panel, Quit; starts runs |
| `tutorial.gd` | Tutorial step panel: 12 steps (welcome, buy, place, start fight, watch, merge, synergies, items, sell, lock the shop, level up, win). Most advance when their condition is met; welcome and "Watch the fight" wait for Next (Watch's Next is greyed out until the fight is over, and Start fight is hidden while a step waits for Next); Start fight button (`GameManager.end_prep_early()`) |
| `pause_menu.gd` | Esc during a run (node `PauseMenu` in ui.tscn, last child): pauses the tree; Resume / Main menu / Quit game |
| `settings.gd` (class Settings) | Static player options in `user://settings.cfg`: fullscreen, VSync, master volume, HUD windows (show_damage_meter, show_synergies, show_items); `apply()` |
| `drag_controller.gd` | Left-drag units, swaps, snapping (board tiles only on the player half, rows 4-7; a drop on an enemy-side tile returns the unit to where it came from), sell zone, F-to-sell, drag cancel on phase change; dropping dragged items on units (`equip_item_on`) |
| `unit_pool.gd` (class UnitPool) | Shared unit pool: copies left per UnitData, weighted `pick(cost)`, `take` / `take_copies` / `give_back`, `copies_in(star)` |
| `shop_slot.gd` (class ShopSlot) | Shop button; checks gold and bench space (in PREP, completing a merge also counts); `clear_offer()` for empty slots |
| `shop_panel.gd` | Wires shop buttons, fills slots from `shop_rolled`; adds the Lock button next to Reroll |
| UI labels | `gold_label.gd`, `label.gd` (XP/level), `stage_label.gd`, `hp_label.gd`, `odds_label.gd`, `streak_label.gd`, `board_label.gd`, `bottom_info.gd`, `synergy_panel.gd`, `unit_inspector.gd`, `end_screen.gd` |

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
- Board starts with 2 tiles per side (front row center) and grows evenly to the full board at level 8 (`tiles_open_for_level`). New tiles from a mid-combat level-up appear at the next PREP.
- Gold seam border drawn only between unlocked player front-row tiles and unlocked enemy tiles.

**Shop odds (% for 1/2/3/4/5 cost) by level:** 1-2: 100/0/0/0/0, 3: 75/25, 4: 55/30/15, 5: 45/33/20/2, 6: 30/40/25/5, 7: 19/30/35/15/1, 8: 15/20/35/25/5, 9: 10/15/30/30/15. If no unit exists at a rolled cost, falls back to the nearest cost.

**Shared unit pool:** Copies per unit by cost: 1: 30, 2: 25, 3: 18, 4: 10, 5: 9 (`UnitPool.COPIES_PER_COST`). Shop offers are taken from the pool when rolled; unbought offers go back on the next roll. Bought units stay out. Selling returns `3^(star-1)` copies. Picks within a cost are weighted by copies left; an empty cost falls back to the nearest cost with copies; if the pool runs dry the slot is left empty. Enemies do not draw from the pool. `GameManager.shared_pool` owns it (rebuilt on scene reload).

**Units and merging:** 3 copies (same `display_name`, same star) merge into the next star, max 3. Star multipliers: HP/dmg x1.0 / x1.8 / x3.2, model scale 1.0 / 1.2 / 1.45. Merges run after buys (prep only), after drops (prep only), and at PREP start. Buying on a full bench is allowed in PREP if it completes a merge. Units bought during combat go to the bench only (full bench = refused) and are not merged until the next PREP start.

**Combat (deterministic):** the same two boards always produce the same fight, at any frame rate. `GameManager.combat_tick()` runs once per physics frame with a fixed `COMBAT_TICK` (1/60 s); units act in a fixed order (`_combat_order`: each side by tile row then column, interleaved player/enemy, never node order); target ties go to the lower tile (`Board.tile_order`); movement is stepped per tick (`Unit.move_from` / `move_to` / `move_progress`), not tweened. `resolve_combat()` runs a fight to the end instantly. The run RNG is seeded (`GameManager.rng` for random enemies and placement, `PlayerState.rng` for shops and drops); never use `randf()` / `randi()` / `pick_random()` / `shuffle()` in game logic. Tile-to-tile movement on the hex grid (BFS, occupied tiles are walls, units claim their next tile before moving). `attack_range` is in tiles, `move_speed` is tiles/sec. Units target the nearest enemy. Dead units are hidden, not freed, and restored after combat. Player board positions are snapshotted at combat start and restored after. 60 s timeout counts as a loss.

**Mana:** +10 per attack, +10% of damage taken (max 15 per hit). Resets to `start_mana` each fight. At full mana the unit casts its ability (placeholder: shows a "CAST" popup, does nothing) and mana resets to 0.

**Enemies:** GameManager asks its `OpponentProvider` for an `EnemyBoard` each fight and places it with `spawn_board()` (details: `docs/campaign-and-opponents.md`).
- Free play (`RandomOpponents`): count = player's unit cap, with a 30% chance of +1 or -1. Unit cost limited early (`max_cost = 1 + round/3`). Stats scaled by `enemy_base_scale + enemy_scale_per_round * (round-1)`. Random tiles, no stars, items or synergies (balance unchanged from before).
- Campaign (`WaveOpponents`): the level's authored wave for that round, times the level's `enemy_stat_mult`. Units can have stars, items and set tiles, and get synergies.
- Placement: only unlocked, empty enemy tiles (they unlock with the player's level). A set tile that's locked or taken falls back to the nearest open one; units that don't fit are skipped with a warning. Placed with `put_enemy_on_tile` (never the bench).

**Campaign:** `Campaign` -> `CampaignChapter` -> `CampaignLevel` in `tres/campaign/`. A level has one round per wave plus settings (start gold/level/HP for fresh starts, `start_heal`, income bonus, enemy strength, `loss_damage`, prep time, item drop rounds, allowed shop units) and `unlocks`. Waves (`EnemyBoard`) can have an `hp_reward`.
- **A chapter is one run (roguelite):** the first level starts fresh at 100 HP. Completing a level carries everything into the next level of the chapter: board and bench units (stars, items, tiles/slots), item bar, gold, player level, XP and HP. HP packs: the next level's `start_heal` on arrival plus `hp_reward` for beating certain waves; HP never exceeds the run's start HP.
- A level is complete when every wave is survived **and the last wave is won**; completion is saved. **Defeat ends the chapter run**: Restart chapter goes back to its first level with an empty board. Finishing the last level completes the chapter; the next chapter starts fresh.
- The chapter run is saved (`SaveGame` `chapter_run`) when a level is completed, so quitting and continuing restarts the next level with the saved board.
- End screen: LEVEL COMPLETE with only Next level; CHAPTER COMPLETE with Next chapter (if any) / Play chapter again; DEFEAT with Restart chapter. Levels unlock in order (the first is always open). The top bar shows "Level name   Wave x/y: wave name" (hover for the enemies).
- `CampaignLevel.validate()` / `Campaign.validate()` report authoring mistakes and run at level start. The sample campaign has 3 chapters of 3 levels each (The Borderlands, The Ashen Frontier, The Shattered Sky; 63 waves in all, every chapter ending in a boss), tuned with `tools/bot_playtest -- chapter` so the difficulty steps down across chapters: the bot completes about 60% of chapter 1 runs, 45% of chapter 2 and 35% of chapter 3. A chapter always starts fresh (its first level sets its own gold and level); finishing it unlocks the next chapter's first level and the end screen offers Next chapter. Details and per-level settings: `docs/campaign-and-opponents.md`.

**Saves:** `SaveGame` (static, no autoload) keeps campaign progress (`completed_levels`: best HP, times, first completion), `unlocks`, the `chapter_run` in progress and the `team_plan` in `user://save.json` (version 2; version 1 files load fine). Writes go through a temp file; an unreadable save is copied to `.corrupt` and progress starts empty. Progress inside a level isn't saved.

**Player HP:** Starts at 100. Loss damage = `round(5 * stage + 0.25 * sum of surviving enemy star levels)`; in a campaign level with `loss_damage` set, that replaces `5 * stage` (rounds restart every level, so the stage stays low). HP 0 = defeat screen; finishing the last round = victory screen (campaign: only if the last wave was won). HP label colours are relative to `GameState.start_hp`. Restart calls `GameState.reset()` then reloads the scene (campaign: from the chapter's first level).

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

Damage reduction is capped at 60%.

---

## Unit roster (placeholder fantasy classes)

| Unit | Cost | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Knight | 1 | Order, Warrior | 650 | 50 | 1 | 0.7 | 80 | 20 |
| Archer | 1 | Wild, Ranger | 450 | 45 | 4 | 0.8 | 60 | 0 |
| Cleric | 1 | Order, Caster | 500 | 35 | 3 | 0.6 | 50 | 20 |
| Guardian | 2 | Order, Protector | 850 | 45 | 1 | 0.6 | 100 | 40 |
| Thief | 2 | Shadow, Rogue | 550 | 60 | 1 | 0.9 | 50 | 0 |
| Mage | 3 | Arcane, Caster | 600 | 55 | 3 | 0.65 | 50 | 10 |
| Assassin | 3 | Shadow, Rogue | 700 | 75 | 1 | 0.9 | 60 | 0 |
| Hunter | 4 | Wild, Ranger | 750 | 80 | 4 | 0.85 | 70 | 0 |
| Berserker | 4 | Wild, Warrior | 1000 | 85 | 1 | 0.8 | 80 | 0 |
| Dragon | 5 | Arcane, Protector | 1400 | 90 | 2 | 0.7 | 100 | 30 |

All move speed 1.5. Display names must be unique (merging groups by name). Tag spelling must match the keys in `Synergies.DEFS` exactly. The .tres files in `tres/` match this table (fixed 2026-10-21). 1-cost units: Knight, Archer, Cleric.

---

## UI behaviour

- The game opens on the main menu (see menu.tscn above). Esc closes its Campaign/Settings/info panels.
- **Tutorial** (`tres/campaign/tutorial.tres`, id `tutorial`, not part of any chapter): 5 easy waves, Knights and Clerics only, 10 start gold, 2 HP per lost wave, a 600 s safety prep timer. The TutorialPanel walks through the basics (including selling units and locking the shop; the lock step needs lock then unlock so the shop is never left locked) and its **Start fight** button ends prep early. "Watch the fight" waits for Next so a quick win doesn't skip it. A Longsword is handed out at the items step if the player has no item. The end screen shows TUTORIAL COMPLETE (Replay tutorial / Main menu) or DEFEAT (Try again). Completion is saved like a level. Levels outside a chapter (`GameManager._in_chapter`) never create, change or clear the saved chapter run. Starting a chapter while a chapter run is saved asks before abandoning it.
- During a run, Esc opens the pause menu (the whole tree pauses, including the prep timer, which is created with `process_always = false`); Esc again resumes. Not available once the run has ended. Leaving a campaign level for the menu keeps the chapter run as saved at the start of that level.
- The end screen always has a Main menu button (below Next level / Restart).

- **Shop lock:** the Lock button (next to Reroll) keeps the current offers into the next round instead of rolling a new shop (`GameManager.shop_locked`); bought slots stay empty. Reroll is disabled while locked (the button greys out; `_on_reroll` ignores it); unlock first, and a reroll then replaces all five offers. It stays locked until clicked again. A new run starts unlocked.
- **Top-right button bar:** Damage, Planner and Menu. Damage and Planner light up gold while their window is open.
- **Damage meter** (window under the top-right bar, toggled by the Damage button; open/closed is remembered in `Settings.show_damage_meter`, default open): one bar per unit that fought, sorted, live during combat and kept as "last fight" until the next fight ("No fights yet" before the first). Click its header to switch between damage dealt and damage taken. Values are HP actually removed (after damage reduction, no overkill): `Unit.take_damage()` returns it.
- **Team planner:** the top-right Planner button or **P** opens it; Esc or P closes it (Esc closes the planner before the pause menu opens). Click units to add/remove them from the plan; it shows planned synergies (count/next threshold) and how many of each you own. Planned units in the shop get a "* " and a gold border. The plan is saved (`SaveGame.team_plan`) and isn't cleared by Reset campaign progress.
- Shop stays visible during combat. Shop slots and Buy XP work during combat (bought units go to the bench only); reroll is blocked outside PREP. The shop is not dimmed yet.
- Right-click any unit (ally or enemy) to open the Unit Inspector (stats at the current star with items and synergy bonuses folded in, tags, item list; the synergy part isn't called out in the text: before a fight it shows what the unit's team on the board would get via `Synergies.preview`, during a fight the real bonuses; benched units get none). Right-clicking empty space closes it; it also closes if the unit dies or is removed.
- Item bar (left side, below center): a fold header ("Items [-]" / "Items (n) [+]", remembered in `Settings.show_items`) over one coloured button per owned item, hover for a tooltip, hidden when empty. Press and hold an item, drag it onto a unit and release to equip; a label with the item name follows the mouse. Units (board and bench) show a row of small coloured squares above their health bar, one per item in the item's colour (`Unit._update_item_icons`; the row is top_level so it stays level when the unit turns).
- Synergy box (top left) has a fold header ("Synergies [-]" / "Synergies (n active) [+]", remembered in `Settings.show_synergies`) and lists every tag on the board as `Tag  count/next threshold` (e.g. Order 2/3, or 3/3 once all tiers are reached): active in gold, inactive in grey. Tooltips show the effect and all tiers. Hidden when the board is empty.
- Odds, streak and unit cap sit above the shop bar.

---

## Conventions and gotchas

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
- HUD checks: `... res://tools/hud_checks.tscn --fixed-fps 60` (53 checks, now including the timer label, pause stopping the prep countdown and the inspector with synergies: shop lock across rounds, reroll blocked while locked, unlock + reroll refills all five slots, damage numbers and meter, top-right bar toggles, layout (meter with 10 units clears the HP display in a 1152x648 window), team planner, shop highlights, Esc order, plan saved, synergy/item fold headers; uses its own settings and save files). Run it after changing the shop, damage/combat code, synergies or the planner. Wait for phases with `await Events.phase_changed`, not by polling: a fight with no player units ends within one physics frame.
- Combat checks: `... res://tools/combat_checks.tscn --fixed-fps 60` (12 checks: the same fight resolved repeatedly, real time == `resolve_combat()`, node order irrelevant, target ties, seeded shops/enemies/drops, per-player state). `-- realtime` prints the fight's SIGNATURE line; compare it across `--fixed-fps 30` and `--fixed-fps 144` runs to prove frame-rate independence.
- Tutorial checks: `... res://tools/tutorial_checks.tscn --fixed-fps 60` (27 checks: every tutorial step with game actions, Watch waiting for Next, sell and lock steps, Start fight, end screen, saved chapter run untouched by winning or losing the tutorial). Run after changing the tutorial, end screen, GameManager phase flow or the chapter-run code.
- When a test awaits a game signal (e.g. `combat_ended`), read what it needs right away and `await get_tree().process_frame` before freeing the scene: freeing it inside the signal crashes Godot.
- The main scene is menu.tscn. To jump straight into a run while testing, open main.tscn and press F6 (Run Current Scene); Debug Level applies there.
- Never use a level's `id` for two levels, and never rename one: the save file keys progress by it.

---

## Current status (2026-10-21)

- Working: full run loop (prep/combat/result over 39 rounds), economy, leveling, board unlocks, shop odds, shared unit pool, merging, selling, synergies, items, unit inspector, end screen, opponent providers, campaign chapter runs with carried boards, campaign saves, main menu with settings, pause menu.
- Done and committed (8962b5b): opponent providers, campaign structure with chapter runs, save system (design decisions at the end of `docs/campaign-and-opponents.md`).
- Done and committed (19088de): main menu with the working title AZTactics, settings, pause menu.
- Done and committed: shop lock (59e5cb6, d55302b), damage meter, team planner, HUD button bar, fold-out lists.
- Done and committed (cdd6999): deterministic combat (roadmap 10), per-player state (roadmap 11), seeded run RNG, `docs/multiplayer-design.md`.
- Done and committed (c609132): main menu split into Single player (Tutorial, Campaign, Free Play) and PvP (Async/Live placeholders with info panels); a guided tutorial level with a step panel and Start fight; `GameManager.end_prep_early()`; fix so levels outside a chapter can't touch the saved chapter run; `tools/tutorial_checks` (27) and more `menu_checks` (28). A flaky crash in `combat_checks` (test freed the scene mid-signal) fixed. Not yet played by hand.
- Last finished (2026-10-21, Sonnet, **not committed yet**): synergy bonuses folded into the Unit Inspector stats; the TopBar Timer label is now a prep countdown and a combat timer (`phase_timer.gd`; PREP counts down `GameManager.prep_left` in `_process`); the bot plays any chapter (`-- chapter2`); campaign panel scrolls; two new chapters (The Ashen Frontier, The Shattered Sky: 6 levels, 45 waves, 6 bosses) tuned with the bot; checks updated (campaign 80, HUD 53, menu 31). Stray .tmp files left in place (editor open). Not yet played by hand.
- Next: async PvP Part 1 (local-first ghost opponents), following the build order in `docs/multiplayer-design.md`. Volume has no effect until there's sound.
- Ideas for later: `docs/item-ideas.md` (item mechanics brainstorm; resonance/item combinations first).

## Known issues

No blocking issues. Small things left:

1. **[Sonnet] Stray editor temp files** `scenes/main.tscn*.tmp` (3 files, left by interrupted editor saves, they contain old `Scenes/` paths; git ignores them). Delete them once the editor is closed (they were left alone on 2026-10-21 because the editor was open).
2. **[Sonnet] Combat, items, the menu, tutorial and the new HUD are not tested by hand** after the 2026-10-21 changes: play a few rounds and check merging, selling, buying during combat, item drops, dragging items onto units, and the item bar layout.

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
12. **Async PvP** (next up) **[Opus plan done, Sonnet can build]**: local-first ghost opponents from saved snapshots, then an HTTP snapshot store. Build order in `docs/multiplayer-design.md` Part 1 (it includes item 9's snapshots).
13. Live 8-player lobbies with a dedicated server **[Opus]** (optional): designed in `docs/multiplayer-design.md` Part 2, not built; needs the decisions listed there.

### Phase 4: Polish
14. **[Sonnet]** Combat speed button, real models and animations, sound, VFX, menus and settings.
