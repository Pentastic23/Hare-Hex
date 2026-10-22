# Combat HUD spec (timer, round tracker, HP standings)

A design to build, not built yet. Reference images: `hud_combat.png` and `hud_prep.png` in this
folder (rendered with fallback fonts; the intended fonts are below). The live design canvas is
"AZTactics Combat HUD" in the user's Claude artifacts (it has a states sheet for every case).

It replaces four existing labels: `TopBar/Timer` (phase_timer.gd), `TopBar/StageLabel`
(stage_label.gd), `TopBar/OpponentLabel` (opponent_label.gd) and `HpLabel` (hp_label.gd). Their
logic (where each value comes from) carries over; only the presentation changes.

Goal: complement the voxel units without pulling attention from the fight. Small, dark,
semi-opaque plates; colour only where it carries meaning.

## Layout (1152 x 648 window)

- **Top center:** the timer plate, with the round tracker plate 8 px under it. Both are centred
  horizontally; the timer plate's top is 10 px from the top of the window.
- **Right edge:** the HP standings, a vertical stack of rows, each row a horizontal bar. Column
  210 px wide, top at y = 129 (below the top-right Damage / Planner / Menu bar), 2 px from the
  right edge (the user placed it there). 6 px between rows.
- **Conflicts to resolve:** the DamageMeter window (top right, under the button bar) and the
  UnitInspector (anchored center-right) sit where the standings go. Move the meter (left side
  under the synergy box is the natural spot) or let it overlay the standings only while it is
  toggled on. Ask the user before choosing.
- Everything is `MOUSE_FILTER_IGNORE`; no tooltips, so nothing new for `tools/tooltip_checks`.

## Plate style (all three plates and every standings row)

| Part | Value |
|---|---|
| Fill | `#171a26` at 90% alpha (`Color(0.090, 0.102, 0.149, 0.9)`) |
| Top edge | 2 px, `#3d4566` (the lit top face of a voxel); some states change its colour, below |
| Bottom lip | hard shadow 3 px straight down, `#0a0b11`, no blur |
| Corners | 3 px radius |

In Godot that is a StyleBoxFlat with `border_width_top = 2` and the edge colour, and a 3 px dark
rectangle drawn under the plate (StyleBoxFlat's shadow is blurred, so draw the lip yourself or
use a second StyleBoxFlat offset by 3 px).

## Type

| Use | Font | Size | Colour |
|---|---|---|---|
| Numbers (time, HP, round "3-4") | **Jersey 10** (Google Fonts, OFL), a pixel font; fallback: any monospace bold | timer 42 px, HP 22 px, round 20 px | per state |
| Small caps labels ("COMBAT", "STAGE 3") | **Atkinson Hyperlegible** Bold (Google Fonts, OFL); fallback: the default font, bold | 10-11 px, letter spacing 1.4-1.8 px, uppercase | `#a9aec4` unless a state says otherwise |
| Player names | Atkinson Hyperlegible Bold | 12 px | `#ece6d6` for you and your opponent, `#a9aec4` for others |

The fonts could not be downloaded from where this was made; add the two .ttf files from
fonts.google.com, or use the fallbacks.

## Colours

| Token | Hex | Used for |
|---|---|---|
| ink | `#ece6d6` | main numbers and text |
| muted | `#a9aec4` | labels, other players' names |
| gold | `#f2c14e` | prep timer, finished round pips |
| red | `#ff6b5e` | last seconds, HP at 25 or less |
| you | `#6cc4ff` (edge `#3f7fb8`) | your HP bar |
| enemy / ember | `#ff8a4c` (edge `#a4522a`) | this round's opponent, boss pip |
| neutral bar | `#8f97b3` | other players' bars |
| empty track | `#262b3f` | unfilled bar segments, timer track |

You and the enemy differ in lightness and position as well as hue, so colour-blind players can
still tell them apart.

## Timer plate (132 px wide, padding 6 / 10 / 9 px)

Stacked and centred: phase label, time, a 100 x 4 px progress track (fill = time left / phase
length).

| State | When | Label | Time and bar colour | Top edge |
|---|---|---|---|---|
| Prep | `gm.phase == PREP` | "PREP" in gold | gold | `#8a6a1f` |
| Prep, last 5 s | `prep_left <= 5` | "PREP" in red | red | `#8a2f29` |
| Combat | `gm.fighting` | "COMBAT" in muted | ink | `#3d4566` |
| Combat, last 10 s | time left <= 10 | "COMBAT" in red | red | `#8a2f29` |
| Untimed prep (tutorial) | `prep_time >= 300` | "PREP" in gold | show "--", bar full | `#8a6a1f` |

Time values are exactly what phase_timer.gd computes today: prep = `gm.prep_left` of
`gm.prep_time`; combat = `(COMBAT_MAX_TICKS - combat_ticks) * COMBAT_TICK` of 60 s; shown as
m:ss rounded up. Hide the time once `gm.game_over`.

## Round tracker plate (padding 5 / 12 / 6 px, 9 px gaps)

`STAGE 3`  `[pips]`  `3-4`

- Free play: label "STAGE n" (`GameState.stage()`), one pip per round in the stage
  (`rounds_in_current_stage()`), current = `round_in_stage()`, text "n-r".
- Campaign: label "WAVE", one pip per wave (`total_rounds()`), current = `round_number`, text
  "4/5". The wave's name goes in the standings (below). If a level ever has more than ~10 waves,
  drop the pips and keep the text.
- Pips, 9 x 9 px, 5 px apart:
  - done: gold, with a 2 px `#7a5a17` lip under it
  - current: 11 x 11 ink square with a 2 px gold outline
  - upcoming: `#2c3249` with a 2 px `#0a0b11` lip
  - boss (campaign): an 8 x 8 diamond (square rotated 45 degrees), fill `#3a2620`, 2 px ember
    inset outline. Waves have no boss flag today; mark the last wave of a chapter's last level,
    or add a `boss` field to EnemyBoard.
- Update on `Events.round_changed` like stage_label.gd does.

## HP standings (right edge)

One row per player, sorted by HP (highest first); eliminated players at the bottom.

Row: padding 6 / 10 / 7 px, two lines 5 px apart.
1. Name (left, ellipsized), an optional "VS" tag, HP number (right, Jersey 10 22 px).
2. A 10-segment bar, 6 px tall, 2 px gaps; each segment is 10% of max HP (partly filled
   segments show the remainder).

| Row type | Fill | Top edge | Name colour | Bar |
|---|---|---|---|---|
| You | slightly lighter, `#1e2436` at 90% | `#3f7fb8` | ink | you blue |
| This round's opponent | normal | `#a4522a` | ink, plus a "VS" tag (9 px bold ember text, 1 px `#a4522a` border, 2 px radius) | ember |
| Other players | normal | `#3d4566` | muted | neutral |
| Eliminated (HP 0) | whole row 45% opacity | `#2c3249` | muted, struck through | empty; number reads "Out" |

The HP number turns red at 25 or less (relative to the run's `start_hp`, like hp_label.gd).

Data today (single player):
- **You:** `GameState.me.player_hp` of `GameState.me.start_hp`; update on `Events.hp_changed`.
- **Async PvP:** the ghost's row. `gm.opponents` is a SnapshotOpponents; its `_snapshot`
  dictionary has `name` and `hp` (the ghost's HP when it was recorded). Label "Ghost of <name>",
  role opponent. Refresh on `Events.opponent_announced`.
- **Campaign:** waves have no HP. Show the opponent row with the wave's name (or "Wave 4") and
  "4/5" in place of the number (Jersey 10 at 17 px), with an empty bar.
- **Free play (random enemies):** an opponent row reading "Random enemies", no number, empty bar.
- **Lobbies later:** one row per `GameState.players` entry; the one you face this round gets the
  VS tag.
