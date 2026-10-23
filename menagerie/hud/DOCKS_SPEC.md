# Side boxes spec (synergies / items, and damage / planner / menu)

A design to build, not built yet. It goes with `HUD_SPEC.md` (same plate style, colours and
fonts; read that first). The live, clickable design is the "AZTactics Combat HUD" canvas in the
user's Claude artifacts: the row titled "Full HUD" shows combat (damage meter open), prep (team
planner open) and paused (menu open, left box collapsed).

Two boxes replace five things in ui.tscn today:

| New | Replaces |
|---|---|
| **Left box**: Synergies and Items tabs, collapsible | `SynergyBox` (synergy_panel.gd), `ItemBar` (item_bar.gd) |
| **Right box**: Damage / Planner / Menu tabs, one panel open at a time | `TopRightBar` (hud_buttons.gd), `DamageMeter` (damage_meter.gd), `TeamPlanner` (team_planner.gd), `PauseMenu` (pause_menu.gd) |

Keep the behaviour those scripts already have (data sources, saving open/closed state in
`Settings`, P and Esc keys, pausing the tree, item drag and drop); only the layout and look change.

Assets in this folder:
- `items/<id>.png`: 64 px voxel icons for the 6 items (transparent background), named by item id.
- `portraits/<unit>.png`: 96 px portraits of the 10 modelled units, on the plate colour.

## Layout (1152 x 648)

| Element | Position | Size |
|---|---|---|
| Left box | top-left, x 10, y 10 | 232 px wide (46 px when collapsed); height fits content |
| Timer and round (HUD_SPEC) | top center, x 466 | 220 px |
| Right box | x 694, y 10 (between the timer and the standings) | 236 px wide |
| HP standings (HUD_SPEC) | x 940, y 129 | 210 px |

The right box sits left of the standings column so its panels drop straight down without
covering the standings or the timer. Its buttons move from today's top-right corner to here.

## Shared pieces

- **Plate:** as in HUD_SPEC (fill `#171a26` at 90%, 2 px top edge `#3d4566`, 3 px hard lip
  `#0a0b11` below, 3 px corners).
- **Open panel fill:** `#202434` at 95%, so the panel reads one step lighter than the tab bar.
- **Tab:** 30-34 px tall, Atkinson Hyperlegible Bold 12 px.
  - Inactive: text muted `#a9aec4`, no fill.
  - Active: text ink `#ece6d6`, fill `#232839` (left box) or the panel fill (right box), and a
    2 px gold `#f2c14e` line along its top. In the right box the active tab has no gap below,
    so it flows into its panel like a folder tab.
- **Count badge** (on tabs): a 16 px pill, 10 px bold text. Active tab: gold fill, dark text
  `#1b1610`. Inactive: `#2c3249` fill, muted text.
- **Dark well** (item slots, tiles, segmented controls): `#141722`.
- **Buttons:** 40 px tall, 3 px corners. Primary: gold fill, dark text, 3 px darker gold
  (`#a87c22`) inner bottom edge. Secondary: `#262b3f` fill, ink text, 2 px `#3d4566` inner top
  edge and 3 px `#141722` inner bottom edge.
- **Focus:** 2 px gold outline on every clickable thing (keyboard focus).
- Everything ignores the mouse except the tabs, rows that are draggable or clickable, and buttons.

## Left box

**Header** (padding 4 px, 1 px `#262b3f` line underneath): [Synergies (n)] [Items (n)] [collapse].
- Synergies badge = number of **active** synergies. Items badge = number of items owned
  (counting duplicates).
- Collapse button: 30 px wide, a pixel chevron pointing left.

**Collapsed rail** (46 px wide plate, padding 6 px, gaps 6 px): an expand chevron (pointing
right) above two 34 px square buttons, Synergies (a gold hexagon icon) and Items (the Longsword
icon). Each has its count badge at the top-right corner. Clicking either expands the box on that
tab. Remember collapsed / open and the last tab in `Settings` (replaces `show_synergies` /
`show_items`).

**Synergies tab** (padding 6 px, rows 4 px apart): one row per tag on the board, active ones
first, then by count.
- Row: padding 4 / 6 / 4 / 4 px. Active rows get a `#1e2232` fill.
- Hex badge (26 x 28 px), with the count in Jersey 10 at 17 px:
  - all tiers reached: gold fill `#f2c14e`, `#7a5a17` outline, dark number
  - some tiers reached: darker gold `#b98a2c`, `#5e4514` outline, dark number
  - inactive: `#262b3f`, `#3d4566` outline, muted number
- Name: 12 px bold; ink when active, muted when not.
- Tier numbers on the right ("2 3"): 11 px bold chips. Reached: gold fill, dark text.
  Not reached: `#1b1f2d` fill, `#6b7290` text.
- Active rows show the effect underneath, 11 px muted, from `Synergies` (for example "Order units
  gain 40% max HP" at the 3 tier).
- Show every tag with at least one unit, as today. If the list grows past the window, scroll.

**Items tab** (padding 6 px): one row per item type owned, then a hint line.
- Row: `#1b1f2d` fill, 3 px corners, padding 4 / 6 / 4 / 4 px; cursor shows it's draggable.
  1. Icon slot: 38 px dark well with a 3 px inner bottom edge in the item's own `color`;
     the 34 px icon from `items/`.
  2. Name (12 px bold, ink) over its description (11 px muted, `ItemData.description`).
  3. "×2" in Jersey 10 at 20 px when you own more than one.
- Hint: "Drag an item onto a unit to equip it. Up to 3 per unit." (11 px muted).
- Dragging works as item_bar.gd does today (press, drag the ghost label, release on a unit).

## Right box

**Tab bar** (plate, padding 4 px 4 px 0, tabs 2 px apart; 3 tabs share the width):
[Damage] [Planner P] [Menu Esc]. Each tab has a 14 px pixel icon (bar chart, 2x2 grid, three
lines), the label, and a small key hint (9 px bold, `#6b7290`, 1 px `#3d4566` border). Clicking a
tab opens its panel; clicking the open tab closes it; opening one closes the others. P toggles
the planner and Esc the menu as today (Esc closes an open planner first, then opens the menu).
With no panel open, the bar is a normal plate with its lip; with one open, the lip moves to the
bottom of the panel.

**Panel** (padding 10 px, gaps 8 px), directly under the bar, same 236 px width.

### Damage panel
1. A caption line: "THIS FIGHT · DAMAGE DEALT" (or "LAST FIGHT" between fights, "DAMAGE TAKEN"
   in that view), 10 px bold caps muted; the total on the right (Jersey 10, 18 px, muted).
2. A segmented control (dark well, 2 px padding): Dealt | Taken. Selected half: `#2c3249` fill,
   ink text, 2 px top line in the view's colour. This replaces clicking the header.
3. One row per unit that fought, sorted, 6 px apart: 28 px portrait (dark well) | name (12 px
   bold) with the value right-aligned (Jersey 10, 18 px) | a 6 px bar under them, scaled to the
   top value. Bar colour: **gold** for dealt, **sky blue `#6cc4ff`** for taken.
   - Units without a portrait yet: show the unit's `short_name` in Jersey 10 inside the well.
- Data as damage_meter.gd today (`Unit.damage_dealt` / `damage_taken`, live during the fight,
  kept until the next fight). Remember open/closed in `Settings.show_damage_meter`.

### Planner panel
1. Cost tabs 1-5 (equal width, 26 px tall, 3 px apart). Each shows a 7 px square in the cost
   colour and the number. Selected: `#2c3249` fill, ink text, 2 px top line in the cost colour.
   Others: dark well, muted text.
   - Cost colours: 1 `#8f97b3`, 2 `#5cc27a`, 3 `#4f9cf0`, 4 `#b07cf0`, 5 `#f2c14e`.
2. A 5-column grid of square tiles (4 px gaps) with that cost's units:
   - dark well, 1 px `#262b3f` inner outline; portrait if the unit has one, else its
     `short_name` (Jersey 10, 18 px, muted); a 3 px cost-colour strip along the bottom
   - planned: 2 px gold inner outline and a small gold check square in the top-right corner
   - owned: "×2" (Jersey 10, 14 px, ink) in the top-left corner
   - click toggles planned (saved in `SaveGame.team_plan` as today); hover shows the name and tags
3. "3 of 14 planned at 1 gold" (12 px bold, ink).
4. A divider, then "PLANNED SYNERGIES" (10 px caps muted) with "9 units planned" on the right,
   and wrapping chips: "Order 6/3". Active chips: `#3a2f16` fill, gold text, 1 px `#7a5a17` inner
   outline. Inactive: dark well, muted text. Count over the next threshold, or over the top tier
   once maxed, as team_planner.gd does.
- Shop highlights for planned units stay as today.

### Menu panel
1. "Paused" (Jersey 10, 30 px, ink) with "Esc to resume" (11 px muted) on the right.
2. Resume (primary), Main menu (secondary), then the note "In a campaign, your run continues from
   the start of this level." (11 px muted), then Quit game (secondary).
- Opening it pauses the tree and dims the whole screen behind the HUD with `#0a0b11` at 50%.
  Same rules as pause_menu.gd (not available once the run has ended; `_can_pause()`).

## Checks

- `tools/hud_checks` covers the top-right bar, damage meter, planner, Esc order and fold headers.
  Its tests will need updating for the new nodes.
- `tools/tooltip_checks`: any new tooltip (planner tile hover, synergy rows) must use `Tip.wrap`.
- Make sure the box layout still fits a 1152 x 648 window with a full board and the planner open.
