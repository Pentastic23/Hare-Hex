# Items v2: resonance, special items and item models (proposal)

Status: **built** (2026-10-22). If this doc and the code disagree, the code wins. Decisions: 14 item drops per free-play run (not 14 item types; the 14 types stay as designed), placeholder icons for the 8 new items until the art chat makes proper ones.
Builds on `docs/item-ideas.md` (ideas 1, 5, 8, 9) and the combat mechanics added with synergies v2.

## What the request asks for, and the plan in one line each

| Request | Plan |
|---|---|
| Resonance, with UI in the item / synergy box | Every basic item has an element; two different elements on one unit switch on a named resonance (15 pairs), three different elements add Prism. The left box's Items tab shows each item's element, the resonances active on your board, and a resonance book |
| Item removers (limited) | **Tinker's Tongs**: a consumable. Drag it onto a unit in prep to send all its items back to your inventory. Two per run at most |
| Bound items that grow | **Hero's Blade** and **Heartwood Charm** gain a stack each fight their holder survives. Selling the unit resets them; merging keeps the highest stack |
| Economy items (balance carefully) | **Coin Purse** (+1 gold per round) and **Merchant's Ledger** (first reroll each round free). Rare, no combat stats, and they hold a slot for good |
| Items that bend synergies (very rare) | **Twin Sigil** (the holder counts twice for its origin) and **Twin Crest** (twice for its first class). Late drops only, at most one of each per run |
| Dragging shows the item icon | The drag ghost becomes the item's icon (with a small name tag) |
| Items on units as a model | Each equipped item is a small voxel model of its icon, floating in a row above the health bar (instead of coloured squares) |
| 14 items in total throughout the stages | 14 item drops per free-play run, spread over the stages (was 7); the item pool is 14 types: 6 basic from the start, 8 special ones joining as the stages go on |

## Why it fits the game

- Items still can't be taken off (except with the rare Tongs), so every second and third item is a real commitment: do you finish a resonance now, or hold the item?
- Resonances and special items reuse the combat mechanics synergies v2 added (shield, regen, crit, burn, chill, curse, dodge, execute, revive, ramp), so no new effect system is needed and fights stay deterministic.
- Economy items trade fight power for gold, and they can only appear from stage 3, so they can't snowball the early game.

## The 14 items

### Basic items (6): drop from stage 1, each with one element

| Item | Element | Stats |
|---|---|---|
| Longsword | Might | +15 damage |
| Iron Belt | Vigor | +150 HP |
| Quick Bow | Swift | +15% attack speed |
| Chain Vest | Guard | +10% damage reduction |
| Blood Fang | Blood | +10% omnivamp |
| Mana Charm | Arcane | +15 starting mana **and +8% damage** (new: mana alone does nothing while casts are empty) |

### Special items (8): join the drops through the stages

| Item | Kind | From | Effect |
|---|---|---|---|
| Hero's Blade | Bound (Might) | stage 3 | +10 damage, +4 damage per stack (max 15). +1 stack per fight the holder survives |
| Heartwood Charm | Bound (Vigor) | stage 3 | +100 HP, +40 HP per stack (max 15). +1 stack per fight the holder survives |
| Resonance Crystal | Resonance | stage 3 | No element. The resonances on its unit are twice as strong; with none it gives +8% HP and damage |
| Coin Purse | Economy | stage 3 | +1 gold at the start of each round while its holder is on the board. No combat stats |
| Merchant's Ledger | Economy | stage 4 | One free reroll each round while its holder is on the board; each Ledger adds another (changed 2026-10-25: they used to not stack). No combat stats |
| Tinker's Tongs | Remover (consumable) | stage 3 | Drag onto one of your units during prep: all its items go back to your inventory (bound items lose their stacks). Used up. No slot |
| Twin Sigil | Synergy bender | stage 5 | The holder counts twice for its origin. Very rare |
| Twin Crest | Synergy bender | stage 5 | The holder counts twice for its first class. Very rare |

Rules for the special kinds:
- **Bound:** a unit holds at most one of each bound item. A stack is gained when a fight ends with the holder alive (won or lost). Selling the unit returns the item with 0 stacks; a merge keeps the item with the highest stacks among the three copies. The stack count shows on the item model and in the inspector, and is saved in chapter runs and PvP snapshots.
- **Economy:** they only pay while the holder is on the board (not the bench), so they still cost a board slot's worth of commitment. The gold label tooltip lists the purse in the income breakdown.
- **Benders:** a unit holds at most one bender. Uniques can't be doubled. The synergy box shows the doubled unit with a "x2" mark.
- **Tongs:** prep only (so a fight can't be rescued by moving items around), and they never drop more than twice a run.

## Resonance

Two items with different elements on one unit switch on the resonance for that pair. A unit with three items can have up to three pair resonances (one per different pair), plus **Prism** if all three elements differ. Two items with the same element do nothing extra. Effects are applied at the start of each fight together with synergies (resonance effects add to synergy effects using the same rules).

| Pair | Resonance | Effect |
|---|---|---|
| Might + Vigor | Juggernaut | +10% HP and damage |
| Might + Swift | Flurry | every 3rd attack crits |
| Might + Guard | Vanguard | +10% damage, 10% damage reduction |
| Might + Blood | Hemorrhage | attacks burn 3% of max HP per second |
| Might + Arcane | Spellblade | +20% damage |
| Vigor + Swift | Second Wind | regen 1.5% of max HP per second |
| Vigor + Guard | Bulwark | 25% shield |
| Vigor + Blood | Undying | revive once at 25% HP |
| Vigor + Arcane | Lifebloom | regen 2.5% per second |
| Swift + Guard | Evasion | every 4th attack against the holder misses |
| Swift + Blood | Frenzy | +4% attack speed per attack (max 10) |
| Swift + Arcane | Tempest | attacks chill 20% |
| Guard + Blood | Bloodward | 15% shield, 10% omnivamp |
| Guard + Arcane | Hex Ward | attacks curse 10% |
| Blood + Arcane | Soul Siphon | execute below 10% |
| three different elements | Prism | +10% HP, damage and attack speed |

**Resonance UI (left box, Items tab):**
- Each item row shows its element as a small coloured tag.
- Hovering an item lists what it would resonate with ("+ Swift: Flurry, every 3rd attack crits").
- A "Resonance" section lists the resonances active on your board ("Knight: Flurry, Bulwark").
- A "Book" button opens all 16 resonances in a grid; ones you have triggered at least once are lit (saved, a collection goal).
- The unit inspector lists the unit's resonances; the item models on a unit with an active resonance get a soft glow.

## Drops through the stages

Free play drops **14 items** a run (was 7): rounds 1-2, 1-3; 2-2, 2-4, 2-6; 3-2, 3-4, 3-6; 4-3, 4-6; 5-3, 5-6; 6-3, 6-6. The two Tongs come on top (they are a consumable, not an item for a slot). What each drop can be:
- Stages 1-2: basic items only.
- From stage 3: each drop has a 30% chance to be a special item (Hero's Blade, Heartwood, Crystal, Coin Purse, from stage 4 the Ledger), the rest basic.
- From stage 5: benders join the special pool at a low weight (about 1 in 12 special drops), at most one of each per run.
- Tinker's Tongs: one extra drop at the end of stage 3 and one at the end of stage 5.
- Campaign levels map to a stage for the drop table: chapter 1 = stage 2, chapter 2 = stage 4, chapter 3 = stage 6; their own drop rounds stay.
- Waves and PvP ghosts can carry special items too (bound items with their stacks).

Economy check: a Coin Purse found at the end of stage 3 pays about 1 gold for each of the ~18 rounds left, about 18 gold: 4-5 rerolls, in return for a slot that does nothing in fights. The Ledger saves 2 gold per round only if you reroll. Both are rare (special drops, and the purse competes with three other items), and they show up in the bot balance runs.

## Item models

Each item's icon (64 px pixel art in `textures/ui/items/`) is turned into a small voxel model at runtime: every opaque pixel of a 16 x 16 downsample becomes a cube, coloured from the icon, built once per item and shared. A unit's items float in a row above its health bar and turn slowly (still with Reduce motion), with the stack number of bound items next to them. Dragging an item shows its icon under the pointer instead of the text.

The 8 new items need 64 px icons in the same style as the existing six.

## How it would be built

1. **Data:** `ItemData` gains `element`, `kind` (basic / bound / economy / bender / resonance / remover), `min_stage`, `drop_weight`, effect fields for the specials; 8 new `.tres` items; a `Resonance` table (like `Synergies.DEFS`).
2. **Combat:** resonance and special-item effects merge into the per-unit effect dicts in `Synergies.apply` (same mechanics); bound stacks live on the unit (per item) and grow in `_end_combat`; benders change `Synergies.count`.
3. **Economy:** Coin Purse in `PlayerState.total_income_for_round` (and the gold tooltip), Ledger in `_on_reroll`.
4. **Tongs:** a drop target like equipping; consumes the item.
5. **Drops:** stage-weighted table in `GameManager._drop_item`, the Tongs rounds, campaign stage mapping.
6. **Saves and snapshots:** items with stacks in chapter runs and ghosts (the item format grows from an id to id + stacks; old saves still load).
7. **UI:** element tags, resonance section and book in the Items tab, inspector lines, voxel item models above units, icon drag ghost.
8. **Checks and balance:** combat checks for each resonance and special item, saves round trip, drop tables; a bot run to make sure the campaign difficulty still holds.

About the size of synergies v2; built in chunks (data and combat, economy and drops, UI and models), each tested.
