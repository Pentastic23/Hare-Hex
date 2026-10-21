# Auto Battler: Project Notes

A 3D TFT-style auto battler built in **Godot 4.7** with GDScript. Single player for now; a campaign mode and a PvP mode are planned.

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
  scenes/        main.tscn, Tiles.tscn (one hex tile), unit.tscn, ui.tscn (all UI, instanced in main)
  Scripts/       all .gd files
  tres/          UnitData .tres files (one per unit type) + panel_style.tres (shared StyleBoxFlat)
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

The Game Manager exports set in main.tscn: `prep_time = 15`, `unit_pool` = all 10 unit .tres files (this is the **roster**, not the shared pool), `enemy_base_scale = 0.4`, `enemy_scale_per_round = 0.05`.

**ui.tscn** (root `UI`, CanvasLayer):

```
UI
 ├─ TopBar (HBoxContainer, top center)
 │   ├─ Timer (Label)             no script, unused
 │   └─ StageLabel                stage_label.gd
 ├─ ShopPanel (PanelContainer, bottom center)   shop_panel.gd
 │   └─ HBoxContainer
 │       ├─ StatBox/VBoxContainer: Gold (gold_label.gd), Level (label.gd = XP/level label)
 │       ├─ BuyXPButton, RerollButton
 │       └─ "Slot 1" .. "Slot 5"  (ShopSlot, shop_slot.gd)
 ├─ BottomInfo (VBoxContainer)    bottom_info.gd
 │   ├─ OddsLabel                 odds_label.gd
 │   └─ InfoRow (HBox): BoardLabel (board_label.gd, unit cap), StreakLabel (streak_label.gd)
 ├─ HpLabel                       hp_label.gd (right side)
 ├─ "End Screen" (ColorRect)      end_screen.gd
 │   └─ CenterContainer/Backing/Margin/VBoxContainer: TitleLabel, DetailLabel, RestartButton
 ├─ SynergyBox (PanelContainer, panel_style.tres)
 │   └─ SynergyPanel (VBoxContainer)   synergy_panel.gd
 └─ UnitInspector (PanelContainer, panel_style.tres)   unit_inspector.gd
     └─ VBoxContainer: NameLabel, TagsLabel, StatsLabel
```

Several node names contain spaces ("Game Manager", "End Screen", "Slot 1"). Any `get_node` path must use the exact name.

`unit.tscn`: root Node3D with `unit.gd`, children `ModelHolder` (Node3D, holds a capsule MeshInstance3D at y = 1) and `Area3D` (layer 2, for picking). Health bar, mana bar and letter label are created in code.
`Tiles.tscn`: StaticBody3D root with `tile.gd` (collision layer 1), 6-sided CylinderMesh (radius 0.95, no rotation applied in the scene). Hex layout math in board.gd is **pointy-top**.

---

## Autoloads

- **Events** (`events.gd`): all global signals, plus `enum Phase { PREP, COMBAT, RESULT }`.
- **GameState** (`GameState.gd`): gold, level, xp, round_number, player_hp, streaks, shop odds, income, stage math, `reset()`.

Signals in Events: `phase_changed`, `gold_changed`, `shop_rolled`, `unit_bought`, `combat_ended`, `xp_changed`, `reroll_pressed`, `buy_xp_pressed`, `board_limit_hit`, `round_changed`, `streak_changed`, `hp_changed`, `unit_sold(data, star, refund)`, `run_won`, `run_lost`.

---

## Core scripts

| Script | Responsibility |
|---|---|
| `board.gd` (class Board) | Hex grid (7 cols x 8 rows; rows 0-3 enemy, 4-7 player), bench (9 slots), sell zone, tile unlocking by level, seam border, hex math + BFS pathfinding, merging, selling |
| `tile.gd` (class Tile) | `coord`, `occupant`, `unlocked`, pop-in animation |
| `unit.gd` (class Unit) | Stats, star level, combat step, health/mana bars, letter label, synergy bonus fields, placeholder ability casting |
| `unit_data.gd` (class UnitData) | Resource: name, cost, stats, tags, mana, model, ability |
| `ability.gd` (class Ability) | Resource base class; `cast(caster, target)` does nothing yet (placeholder) |
| `synergies.gd` (class Synergies) | Static synergy table + count / tier / apply |
| `game_manager.gd` | Phase loop, shop rolling (from `shared_pool`), buying, enemy spawning, combat loop, end of combat, run end |
| `drag_controller.gd` | Left-drag units, swaps, snapping, sell zone, F-to-sell, drag cancel on phase change |
| `unit_pool.gd` (class UnitPool) | Shared unit pool: copies left per UnitData, weighted `pick(cost)`, `take` / `give_back`, `copies_in(star)` |
| `shop_slot.gd` (class ShopSlot) | Shop button; checks gold, bench space (or completing a merge), phase; `clear_offer()` for empty slots |
| `shop_panel.gd` | Wires shop buttons, fills slots from `shop_rolled` |
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

**Units and merging:** 3 copies (same `display_name`, same star) merge into the next star, max 3. Star multipliers: HP/dmg x1.0 / x1.8 / x3.2, model scale 1.0 / 1.2 / 1.45. Merges run after buys, after drops (prep only), and at PREP start. Buying on a full bench is allowed if it completes a merge.

**Combat:** Tile-to-tile movement on the hex grid (BFS, occupied tiles are walls, units claim their next tile before tweening). `attack_range` is in tiles, `move_speed` is tiles/sec. Units target the nearest enemy. Dead units are hidden, not freed, and restored after combat. Player board positions are snapshotted at combat start and restored after. 60 s timeout counts as a loss.

**Mana:** +10 per attack, +10% of damage taken (max 15 per hit). Resets to `start_mana` each fight. At full mana the unit casts its ability (placeholder: shows a "CAST" popup, does nothing) and mana resets to 0.

**Enemies:** Count = player's unit cap (level), with a 30% chance of +1 or -1, clamped to open enemy tiles. Unit cost limited early (`max_cost = 1 + round/3`). Stats scaled by `enemy_base_scale + enemy_scale_per_round * (round-1)`. Placed with `put_enemy_on_tile` (never the bench). Enemies have no synergies or star levels yet.

**Player HP:** Starts at 100. Loss damage = `round(5 * stage + 0.25 * sum of surviving enemy star levels)`. HP 0 = defeat screen; finishing the last round = victory screen. Restart calls `GameState.reset()` then reloads the scene.

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

- Shop stays visible during combat; slots and reroll are blocked outside PREP (`_on_unit_bought` also checks the phase), Buy XP is not. The shop is not dimmed yet.
- Right-click any unit (ally or enemy) to open the Unit Inspector (base stats at current star, tags). Right-clicking empty space closes it; it also closes if the unit dies or is removed.
- Synergy box (top left) lists active synergies in gold and inactive in grey, with tooltips; hidden when the board is empty.
- Odds, streak and unit cap sit above the shop bar.

---

## Conventions and gotchas

- One function per name per script: Godot errors on duplicates, and many past bugs were leftover copies of replaced functions.
- When looping over untyped arrays or dictionaries, type variables explicitly (`var c: Vector2i = key`) to avoid "cannot infer type" errors.
- Exported scene references (`@export var tile_scene`) reset when a script is re-attached; prefer `preload`.
- Units must be instances of `unit.tscn` under `Board/Units`; `unit.gd` finds the board via `get_parent().get_parent()` and needs `ModelHolder`.
- Never place enemies with `put_on_tile` (it falls back to the bench); use `put_enemy_on_tile`.
- Combat is not deterministic yet (tweens + frame delta + unseeded random). Required before networked PvP.
- `game_manager.gd` joins group `game_manager`; other scripts find it with `get_first_node_in_group` (its node name "Game Manager" has a space, so path lookups are fragile).
- `GameManager.unit_pool` is the roster export (all unit types). The limited-copies pool is `GameManager.shared_pool` (UnitPool). Don't confuse them, and don't rename the export (main.tscn stores its value by name).
- Testing without the editor: `Godot_v4.7.2-stable_win64.exe --headless --path . --quit-after 600` runs the main scene for ~10 s and prints script errors. Autoloads don't exist in `--script` mode, so test scripts that touch GameState/Events must run through the main scene.

---

## Current status (2026-10-21)

- Working: full run loop (prep/combat/result over 39 rounds), economy, leveling, board unlocks, shop odds, shared unit pool, merging, selling, synergies, unit inspector, end screen.
- Last finished: the Known issues audit (combat start/end resets, shop phase check, path casing, prep-only merges, unit data, leftovers). Checked with a headless run: units start combat at full health with synergy bonuses, bonuses clear afterwards, buying during combat is refused. Not playtested by hand.
- Next: Items (roadmap item 3). Plan it with Opus first (see Roadmap tags).

## Known issues

No blocking issues. Small things left:

1. **[Sonnet] `TopBar/Timer`** in ui.tscn is an empty Label with no script. Either wire it up as a prep countdown or delete it.
2. **[Sonnet] Stray editor temp files** `scenes/main.tscn*.tmp` (left by interrupted editor saves, they contain old `Scenes/` paths). Safe to delete once the editor is closed.
3. **[Sonnet] Combat is not tested by hand** after the 2026-10-21 fixes: play a few rounds and check merging, selling, and the shop during combat.

If a combat bug survives two fix attempts, stop and recommend Opus 5.5 (see Model guidance).

---

## Roadmap

Goal: a **campaign mode** and a **PvP mode** sharing the same core game.

Model tags: **[Sonnet]** = do directly. **[Opus]** = recommend switching before starting. **[Opus plan, Sonnet build]** = use Opus to design it (data format, which scripts change), then Sonnet can implement the plan.

### Phase 1: Shared core
1. Abilities **[Opus plan, Sonnet build]**: real designs deferred until unit visuals exist; placeholder system is in place.
2. ~~Shared unit pool~~: done (see Game rules).
3. **Items** (next up, after Known issues) **[Opus plan, Sonnet build]**: drag onto units for stat boosts. Touches drag_controller, unit stats, inspector and combat bonuses.
4. Opponent provider layer **[Opus]**: `_spawn_enemies()` asks a provider for a board (units, stars, tile positions) instead of rolling randomly. Its board format is reused by campaign waves and PvP snapshots, so get it right once.

### Phase 2: Campaign
5. Hand-authored waves as resources (plus bosses) **[Sonnet]**, once item 4's format exists.
6. Campaign structure **[Opus]**: chapters/levels with their own waves, gold, modifiers.
7. Save system **[Opus]** for progress and unlocks.
8. Main menu with mode select **[Sonnet]**.

### Phase 3: PvP
9. Board snapshots **[Sonnet]** in the same format as waves; fight your own past boards offline.
10. Deterministic combat **[Opus]** (seeded RNG, fixed timestep).
11. Per-player state **[Opus]** (refactor global GameState).
12. Async PvP **[Opus]**: fight other players' uploaded snapshots.
13. Live 8-player lobbies with a dedicated server **[Opus]** (optional).

### Phase 4: Polish
14. **[Sonnet]** Combat speed button, real models and animations, sound, VFX, menus and settings.
