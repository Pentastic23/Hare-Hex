# Item mechanic ideas

Brainstorm, 2026-10-21. Nothing here is decided or built. The goal is items that feel different from TFT by leaning on what this game already has: a hex board, items you can equip mid-fight but never remove, merging that moves items, authored campaign waves with item-carrying bosses, a save file, and PvP snapshots on the roadmap.

**One dependency to know first:** today items only change stats. Many ideas below need *effects* (on-hit, shields, auras, triggers). That's the same hook system abilities need (roadmap 1), so building a small effect system once would serve both. Ideas marked **[stats only]** can be built now.

---

## 1. Resonance: item combinations (your idea)

Each item has an **element** (or two): Iron, Blade, Arcane, Blood, Wind, Shadow. When a unit holds certain pairs or a full set of three, a named **resonance** switches on, on top of the items' own stats.

| Items on one unit | Resonance | Effect |
|---|---|---|
| Blade + Blood | **Hemorrhage** | Attacks make the target bleed for 3 s |
| Iron + Iron | **Bulwark** | Start each fight with a shield of 20% max HP |
| Arcane + Wind | **Tempest** | Every 3rd attack chains to a second enemy |
| Shadow + Blade | **Ambush** | First attack each fight deals double damage |
| 3 of the same element | **Ascendant** | The element's pair bonus doubles |
| 3 different elements | **Prism** | +10% to every stat (rewards mixing) |

**Why it's ours:** items can't be removed, so the third item is a real commitment. Do you finish a pair-plus-one, or hold the item for a better unit? Mid-fight equipping means you can complete a resonance **during** a losing fight to turn it around.

**Extras that fit the rest of the game:**
- **Discovery:** resonances start hidden and show as "???" in a codex until you first trigger one. Discoveries go into the save file (`SaveGame` unlocks), which gives the campaign a collection goal.
- **Readable on the board:** the item icons above a unit glow or link when a resonance is active.
- **Campaign bosses use them,** so players learn combos by fighting them.

**Build sketch:** add `elements: Array[StringName]` to `ItemData`, and a `Resonance` resource (`requires: Array[StringName]`, stat bonuses, later an effect). `Unit._recalc_items()` checks the unit's items against the resonance list and adds the bonuses. The inspector lists active resonances. The stat-only version **[stats only]** works today; Hemorrhage-style effects need the effect system.

---

## 2. Forging on merge

When three units merge, the kept unit already takes the others' items. With forging, **two copies of the same item on the merged unit fuse into an upgraded version**: two Iron Belts become a Titan's Girdle (bigger stats plus a small effect), freeing a slot.

**Why it's ours:** merging and items already interact in our code. It makes "put the same item on two copies of a unit, then merge" a deliberate strategy, and gives duplicate drops a use. **[stats only]** for the first version.

---

## 3. Formation items (hex auras)

Items that affect the **hexes around** the holder instead of the holder:
- **War Banner:** adjacent allies +15% attack speed.
- **Ward Stone:** adjacent allies take 10% less damage; the holder takes 10% more.
- **Lodestone:** adjacent *enemies* move and attack slower.

**Why it's ours:** the board is a hex grid with real pathfinding, so where you stand matters. These make placement a puzzle instead of "tanks in front, everyone else behind". Uses `Board.neighbors()`, which already exists. Needs a once-per-tick aura check.

---

## 4. Combat consumables

A new item type used **only in a fight**: drag a **Healing Draught** onto a fighting unit to heal it, a **Rally Horn** onto anyone for a team-wide speed burst, or a **Phoenix Feather** onto a dead unit's tile to revive it. Consumables don't take an item slot and vanish after use.

**Why it's ours:** most auto battlers are hands-off during combat. You already chose to let players equip items mid-fight, and consumables turn that into a real skill: watch the fight and spend at the right moment. It's a big differentiator for the campaign. Drops would be rarer than normal items.

---

## 5. Bound items that grow

Some items **grow with the unit that holds them**: +1 stack per fight that unit survives, +2 per fight won. A **Hero's Blade** starts weak and gets very strong by mid-game. Selling the unit loses the stacks (the item comes back fresh); merging keeps them.

**Why it's ours:** items are permanent, so growth items reward committing to a carry early, and selling becomes a painful choice. Stacks would show on the item icon. **[stats only]**

---

## 6. Cursed items

Strong, with a drawback: **Bloodthirst Axe** (+40% damage, but the holder loses 2% HP per second in combat) or **Glass Crown** (+50% attack speed, +30% damage taken). Because items can't be removed, equipping one is a gamble.

**Purification:** win 3 fights with the holder alive and the curse breaks, leaving only the bonus. This creates a mini-goal inside a run. Campaign waves could offer cursed items as risky rewards.

---

## 7. Boss loot and stealing

Campaign bosses already carry items. Two ways to use that:
- **Boss loot:** beating a level's boss drops one of its items into your inventory for the rest of that run, or permanently as an unlock that adds the item to future drop tables.
- **Pickpocket Gloves:** when the holder lands the killing blow on an enemy carrying an item, the player steals that item.

**Why it's ours:** it ties items to the authored campaign and gives bosses a reward beyond "level complete". In PvP snapshots, stealing becomes a way to take an opponent's build apart.

---

## 8. Economy items

**Coin Purse:** +1 gold per round while equipped. **Merchant's Ledger:** rerolls cost 1 less. They're weak in a fight but pay off over time, and since they can't be removed they hold a slot for good. It's a clear power-versus-economy choice. **[stats only]** (hooks into income).

---

## 9. Items that bend synergies

Instead of TFT-style emblems that add a tag, items that **bend the synergy rules**:
- **Twin Sigil:** the holder counts twice for its first tag (two Order units become three).
- **Turncoat Charm:** the holder counts for the *enemy's* most common tag too, weakening it if it was exactly at a threshold.
- **Lone Wolf Pendant:** big bonus if the holder shares no tags with any ally.

These change how you build your team, not just one unit. Synergy counting is already centralised in `Synergies.count()`, so these are contained changes.

---

## 10. Star-tuned items

Items that care about star level:
- **Apprentice's Charm:** huge bonus on 1-star units, nothing on 3-star. It keeps cheap units useful late, and is a reason not to merge yet.
- **Master's Mark:** only works on 3-star units, and is very strong there.

Flat item stats already scale with stars; these flip that on purpose. **[stats only]**

---

## Suggested order

1. **Resonance, stat-only version** (idea 1): add elements to the 6 existing items and 6 to 8 pair bonuses. It gives the game its identity and only needs `ItemData`, `unit.gd` and the inspector.
2. **Forging on merge** (idea 2): small, builds on code we just wrote, and pairs naturally with resonance (same-element triples).
3. **A small effect system** (on-hit, start-of-fight, aura, tick), shared with abilities. This unlocks Hemorrhage-style resonances and ideas 3, 4 and 6.
4. **Combat consumables** (idea 4): the most distinctive moment-to-moment mechanic, once effects exist.

Ideas 5, 7, 8 and 10 can be added any time as single items, which suits campaign rewards. Idea 9 is best saved until the roster is bigger.

**Model note:** resonance data and stats are Sonnet work. The effect system should be planned with Opus first (it's shared with abilities and affects deterministic combat later).
