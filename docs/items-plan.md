# Items: implementation plan

Roadmap item 3. Planned with Opus 5.5 on 2026-10-21; built with Sonnet 5.5, one step at a time, in the order at the bottom. Read CLAUDE.md first.

## Goal (v1)

Players collect items and drag them onto their own units for stat boosts. Each unit holds up to 3 items. Items are permanent once equipped. No recipes, no item shop, no unequipping in v1 (see "Later").

## Decisions to confirm before building

These are the defaults this plan uses. Change them here before step 1 if you want something different.

| Question | Default |
|---|---|
| Where items come from | Free drops at the start of fixed rounds: 1-2, 1-3, and the last round of stages 2-6 (2-6, 3-6 ... 6-6). 7 per run. |
| Inventory size | No cap in v1. |
| Items per unit | 3 |
| Equip during combat | Allowed on any living player unit, including ones that are fighting. The boost applies immediately (see "Equipping mid-fight"). |
| Removing items during combat | Never. Items only leave a unit through selling or merging, and fighting units can't be sold or merged mid-fight. |
| Unequip | Not possible in v1. Selling the unit returns its items to the inventory. |
| Enemies with items | Not in v1. The data format supports it, so the opponent provider can add them. |

## Data

### `ItemData` resource (new: `Scripts/item_data.gd`)

```gdscript
class_name ItemData extends Resource

@export var id: StringName            # stable, unique; used by saves and snapshots. Never rename.
@export var display_name: String
@export_multiline var description: String
@export var color := Color.WHITE      # UI swatch until there are icons
@export var icon: Texture2D            # optional, unused in v1

# Stat boosts. Flat values add to the unit's base stats before star and synergy multipliers.
@export var hp := 0.0                  # flat max HP
@export var dmg := 0.0                 # flat attack damage
@export var attack_speed := 0.0        # fraction, 0.15 = +15%
@export var mana := 0.0                # flat starting mana
@export var damage_reduction := 0.0    # fraction
@export var lifesteal := 0.0           # fraction
```

### Starter items (new folder `tres/items/`)

| File | id | Name | Boost |
|---|---|---|---|
| iron_belt.tres | `iron_belt` | Iron Belt | +150 HP |
| longsword.tres | `longsword` | Longsword | +15 damage |
| quick_bow.tres | `quick_bow` | Quick Bow | +15% attack speed |
| mana_charm.tres | `mana_charm` | Mana Charm | +15 starting mana |
| chain_vest.tres | `chain_vest` | Chain Vest | +10% damage reduction |
| blood_fang.tres | `blood_fang` | Blood Fang | +10% lifesteal |

Names are placeholders, like the unit roster.

### Where items live

- **Inventory:** `GameState.items: Array[ItemData]`. It's player state like gold, so it moves with the rest of GameState in the per-player refactor (roadmap 11). `GameState.reset()` clears it.
- **On a unit:** `Unit.items: Array[ItemData]` (max 3). Items stay on the unit through combat, position restores and merges.
- **Item roster:** `GameManager.item_roster: Array[ItemData]` export, set in main.tscn like `unit_pool`. Drops pick from it. A save/load or snapshot loader can also use it to turn `id`s back into resources.

## How items combine with synergies

`Synergies.apply()` calls `Unit.clear_bonuses()` at every combat start, and `end_combat()` clears them again. **Item boosts must not live in those fields**, or they'd be wiped.

`Unit` gets separate item fields, rebuilt from `items` whenever the list changes:

```gdscript
var item_hp := 0.0
var item_dmg := 0.0
var item_as := 0.0
var item_mana := 0.0
var item_dr := 0.0
var item_lifesteal := 0.0

func _recalc_items():   # called by equip() and set_items(); never by clear_bonuses()
```

Stat formulas (flat item stats go in before the multipliers, percentage stats add to the synergy percentages):

| Stat | Formula |
|---|---|
| `max_hp()` | `(data.max_health + item_hp) * stat_scale * STAR_MULT[star] * (1 + bonus_hp)` |
| `damage()` | `(data.attack_damage + item_dmg) * stat_scale * STAR_MULT[star] * (1 + bonus_dmg)` |
| `attack_interval()` | `1 / (data.attacks_per_second * (1 + bonus_as + item_as))` |
| starting mana (`begin_combat`) | `minf(data.start_mana + bonus_mana + item_mana, data.max_mana)` |
| damage reduction (`take_damage`) | `minf(dmg_reduction + item_dr, 0.6)` (existing 60% cap covers both) |
| lifesteal (`combat_step`) | `lifesteal + item_lifesteal` |

Flat items scale with stars: a Longsword is worth more on a 3-star unit. That matches TFT's feel and keeps one formula. `stat_scale` also scales enemy item stats, which is what we want once enemies have items.

`end_combat()` keeps `mana = data.start_mana` as the resting value; `begin_combat()` adds the bonuses.

## Unit API (in `unit.gd`)

```gdscript
const MAX_ITEMS := 3
func can_equip() -> bool              # items.size() < MAX_ITEMS
func equip(item: ItemData) -> bool    # append, _recalc_items(), refresh health to max_hp() if not in combat; false if full
func set_items(list: Array[ItemData]) # replace all (used by merges, the opponent provider and save loading)
func take_items() -> Array[ItemData]  # remove and return all (used by sell and merge)
```

`equip()` returns false for dead units (they're hidden mid-fight). Outside combat it sets `health = max_hp()` so the health bar matches.

### Equipping mid-fight

When `equip()` is called on a unit that is fighting (`GameManager.fighting` and `coord.x >= 0`; pass a `in_combat: bool` argument rather than having Unit look up the GameManager):

- **HP:** add the increase to current health: `health += new_max_hp - old_max_hp`. A damaged unit stays damaged but gains the item's HP, like TFT.
- **Starting mana:** the item's `mana` is added to current mana once (capped at `max_mana`). From the next fight on it's part of starting mana as usual.
- **Damage, attack speed, damage reduction, lifesteal:** take effect on the next attack or hit, since they're read live. The current attack cooldown is not reset.
- Bench units during combat equip as normal (no fight in progress for them).

Items are never removed during combat: v1 has no unequip, fighting units can't be sold (`drag_controller` only lets bench units be sold mid-fight) and merges only run in PREP. If an unequip feature is added later, it must be PREP-only.

## Drops

`game_manager.gd`, at PREP start (after income, before `roll_shop()`): if `GameState.round_number` is a drop round, append `item_roster.pick_random()` to `GameState.items` and emit `Events.items_changed`.

Drop rounds as a const in GameState: `ITEM_DROP_ROUNDS := [2, 3, 9, 15, 21, 27, 33]` (overall round numbers for 1-2, 1-3 and the last round of stages 2-6). Stage 7 gets no drop because an item on the final rounds has little use. Campaign mode will later define drops per wave instead.

## UI: item bar (new `Scripts/item_bar.gd`, node in ui.tscn)

- A `PanelContainer` (panel_style.tres) on the left side, below SynergyBox, containing a `GridContainer` (2 columns) of item buttons. Hidden when the inventory is empty.
- Rebuilds on `Events.items_changed`.
- Each button: coloured square (`ItemData.color`) with the first 2 letters of the name; tooltip = name + description.
- **Pressing** a button starts an item drag: `Events.item_drag_started.emit(index)`. The bar shows a small label that follows the mouse while dragging and hides it on `Events.item_drag_ended`.

## Dragging items onto units (`drag_controller.gd`)

The existing unit drag starts in `_pick()` on mouse press, and `_pick()` already ignores clicks over UI, so pressing an item button never starts a unit drag. Item drags get their own state:

```gdscript
var dragging_item := -1   # index into GameState.items, or -1
```

- `Events.item_drag_started(index)` → set `dragging_item`.
- On left **release** in `_input`, check `dragging_item` **before** the unit drop: call `_drop_item()` and return.
- `_drop_item()`:
  1. Find the unit under the mouse with a layer-2 raycast (same as `_pick()`, which hits bench units too).
  2. Equip if: it's a player unit (`team == 0`), not dead, and `can_equip()`. This works in any phase, on the board or the bench. Pass `in_combat = not in_prep and u.coord.x >= 0` to `equip()`.
  3. On success: remove the item from `GameState.items`, emit `items_changed`.
  4. Otherwise (empty tile, enemy, dead unit, full unit, sell zone, UI): do nothing. The item stays in the inventory.
  5. Always reset `dragging_item = -1` and emit `Events.item_drag_ended`.
- `_cancel_drag()` (phase change) also cancels an item drag.
- F-to-sell ignores item drags.

Items never go onto a tile, only onto units.

## Selling and merging (`board.gd`)

- **Sell** (`sell_unit`): before `queue_free()`, `GameState.items.append_array(u.take_items())` and emit `items_changed`. The refund is unchanged; items aren't worth gold.
- **Merge** (`try_merge`, `merge_pending_unit`): before freeing the consumed copies, collect their items into the keeper up to 3 total (keeper's own items first). Anything left over goes back to `GameState.items`. Use one helper for both:

```gdscript
func _move_items_to(keeper: Unit, consumed: Array) -> void
```

- The "no room; removed" paths in `put_on_tile` / `put_on_bench` should also return items to the inventory, so they're never silently lost.

## Unit Inspector (`unit_inspector.gd`, ui.tscn)

- New `ItemsLabel` under TagsLabel: `Items: Iron Belt, Longsword` (or `Items: none`). Enemies show the line too.
- Stats include items: `Health: 910 (+150 items)`. Base stats still exclude synergies; showing synergy bonuses is a separate small task.

## Small 3D indicator (optional, last)

Built as a row of small coloured squares (one per item, in the item's colour) above the health bar, updated from `_recalc_items()`. The first version was text dots under the unit's letter; they were too easy to miss, so they were replaced.

## Compatibility with later roadmap items

- **Opponent provider (4):** board entries use this shape, so items are part of the format from day one:
  `{ "unit": UnitData, "star": int, "coord": Vector2i, "items": Array[ItemData] }`
  `_spawn_enemies()` calls `u.set_items(entry.items)` after `setup()` and before setting health.
- **Campaign waves (5) and PvP snapshots (9):** same entry shape; when stored on disk, items are saved as `id`s.
- **Save system (7):** inventory and per-unit items are saved as arrays of `ItemData.id`, resolved through `item_roster`. This is why `id` must be stable and unique.
- **Deterministic combat (10):** drops use `pick_random()`; route them through the seeded RNG when that lands.
- **Per-player state (11):** `GameState.items` moves with the rest of the player state.

## Later (not v1)

- Recipes (two components combine into a full item).
- Emblems that grant a tag: would need `Unit.all_tags()` used by `Synergies.count()` and `apply()`.
- Item abilities and on-hit effects (needs the real ability system).
- Unequip / item remover consumable (PREP only; items never come off during combat).
- Items in the shop, or as rewards for win streaks.

## Files

| File | Change |
|---|---|
| `Scripts/item_data.gd` | new (ItemData) |
| `tres/items/*.tres` | new, 6 items |
| `Scripts/unit.gd` | items, item stat fields, equip API, stat formulas |
| `Scripts/GameState.gd` | `items`, `ITEM_DROP_ROUNDS`, reset |
| `Scripts/events.gd` | `items_changed`, `item_drag_started(index)`, `item_drag_ended` |
| `Scripts/game_manager.gd` | `item_roster` export, drops at PREP start |
| `scenes/main.tscn` | set `item_roster` (in the editor) |
| `Scripts/board.gd` | items back on sell, merge helper, no-room paths |
| `Scripts/item_bar.gd` | new |
| `scenes/ui.tscn` | ItemBar node, inspector ItemsLabel |
| `Scripts/drag_controller.gd` | item drag state and `_drop_item()` |
| `Scripts/unit_inspector.gd` | items line, stats with items |
| `CLAUDE.md` | rules, scene tree, scripts table, status |

## Build order

Each step should run without errors before the next. Test headless with a temporary scene that instances main.tscn (see CLAUDE.md testing notes), then delete it.

1. **Data:** `item_data.gd` and the 6 `.tres` files. Test: load each, print name and stats.
2. **Unit stats:** items array, item fields, `_recalc_items()`, equip API, formulas. Test: equip a Longsword and Iron Belt on a Knight, check `damage()`/`max_hp()`; start combat with an Order pair and confirm synergy + item stack and that item boosts survive `clear_bonuses()`.
3. **Inventory and drops:** GameState, Events signals, `item_roster` export (set it in main.tscn), drops at PREP start. Test: run to round 3, inventory has 2 items; `reset()` clears it.
4. **Sell and merge:** board.gd changes. Test: sell an itemised unit (items return), merge three units holding 2+2+1 items (keeper has 3, 2 return).
5. **Item bar UI.** Test in the editor: items appear, tooltips work, bar hides when empty.
6. **Drag onto units.** Test in the editor: drop on a board unit (prep), a bench unit (combat), a fighting unit (accepted; an Iron Belt raises its current HP by 150 x its multipliers), a full unit (refused), an empty tile (refused). Also test headless: equip mid-fight and check health, mana and that the item is still there after combat.
7. **Inspector.** Test: items line and `(+N items)` numbers.
8. **Optional 3D dots.**
9. **CLAUDE.md:** rules, scene tree, scripts table, Current status; mark roadmap 3 done.

Steps 1-4 are pure logic and testable headless. Steps 5-7 need a look in the editor.
