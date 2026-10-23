# Synergies v2: breakpoints and power spikes

Status: **built** (2026-10-22). The game reads the traits from `Synergies.DEFS` in `Scripts/synergies.gd`; if this doc and the code disagree, the code wins.
Round 1 (an animal "Kin" family) was turned down; this version re-themes the origins and classes instead.

## Decisions so far

- **35 traits in total** across the 65 units, uniques included.
- **No Kin family.** Traits are origins, classes and uniques.
- **Level 10 is added** (10 units on the board; XP 100 to go from 9 to 10; shop odds at 10:
  5 / 10 / 20 / 35 / 30), so a 9-piece vertical leaves one flex slot.
- **Casts stay empty** until real abilities exist, so **no trait uses mana**. Every effect works on
  attacks, HP and the new combat mechanics below.

## Goals

- Breakpoints, not smooth curves. Each tier is a visible jump; the top tiers of deep traits unlock a
  new mechanic (omnivamp, revives, executes, crits, multipliers) so committing is worth a rigid board.
- Four shapes:
  - **Vertical / deep** (3 / 5 / 7 / 9, 3 / 4 / 5 / 7): 4 traits
  - **Shallow / two-step** (2 / 4 / 6, 2 / 4 / 6 / 8): 10 traits
  - **Tight ladder** (2 / 3 / 4, 2 / 3 / 4 / 5, 2 / 3): 13 traits
  - **Unique** (1): 8 traits
- An 11-piece tier needs trait emblems (items that add a trait), which fit the planned item
  combinations; not part of this.

## The 35 traits

| Family | Traits | Count |
|---|---|---|
| Origins | Order, **Celestial** (new), Wild, Shadow, Arcane, Undead, Ember, Frost, Fey, Dwarven, Infernal | 11 |
| Classes | Warrior, Caster, Protector, Ranger, Rogue, Healer, Summoner, Monk, Bard, Alchemist, **Brute**, **Warlock**, **Knight**, **Duelist**, **Elementalist**, **Trickster** (new) | 16 |
| Unique | Dragonlord, Ascendant, Lich King, Earthshaker, Inferno, Crusade, **Rebirth**, **Soulreaper** (new) | 8 |

Every unit has one origin and one or two classes; the 8 unique holders have one class plus their
unique. No unit has more than 3 traits (36 units have 3, 29 have 2).

What changes for existing units:
- **Celestial** takes the holy units out of Order: Cleric, Acolyte, Monk, Paladin, Seraph, and Sunmonk
  (from Ember). Order keeps the kingdom's soldiers: Knight, Militia, Guardian, Warlord, Herald.
- Units named after a class get it: **Knight** (Knight, Paladin, Winter Knight, Hellknight, Deathlord).
- Big melee bruisers become **Brute**; dark casters **Warlock**; fast fencers **Duelist**; elemental
  mages **Elementalist**; pranksters and illusionists **Trickster**.
- The full list is in Unit assignments below.

## Mechanics

All deterministic (no random rolls: "every Nth attack" instead of a % chance), so fights stay
replayable for async PvP.

| Mechanic | Meaning | Used by |
|---|---|---|
| HP / damage / attack speed / damage reduction | percent, as today | many |
| Omnivamp | heal for a % of damage dealt (today's lifesteal, renamed) | Warrior, Warlock, Ascendant, Lich King |
| Shield | a barrier of % max HP at the start of the fight, absorbed before HP | Protector, Celestial, Dwarven, Earthshaker |
| Regen | heal % max HP every second | Healer, Celestial, Ascendant |
| Ramp | +% attack speed per attack, stacking to a cap | Duelist, Wild |
| Crit | every Nth attack deals double damage | Rogue, Ranger, Caster |
| Execute | an attack kills an enemy left below % max HP | Shadow, Soulreaper |
| Revive | once per fight, a killing blow leaves the unit at % max HP | Undead, Rebirth, Lich King |
| Burn | attacks burn the target for % of its max HP per second, 3 s | Ember, Elementalist, Inferno |
| Chill | attacks slow the target's attack speed by %, 2 s | Frost, Elementalist |
| Dodge | every Nth attack against the unit misses | Trickster |
| Curse | attacks make the target take % more damage from everyone, 3 s | Warlock |
| Range | +1 attack range | Ranger |

"Holders" are units with the trait; "team" is all your units. Damage reduction stays capped at 60%.

## Vertical traits

**Caster** (3 / 5 / 7 / 9) · class · 11 units
- 3: Casters +15% damage
- 5: +30% damage
- 7: +50% damage; team +10% damage
- 9: **Archmagi**: Casters +90% damage and every 3rd attack crits; team +20% damage

**Warrior** (3 / 5 / 7 / 9) · class · 9 units
- 3: Warriors +15% damage
- 5: +25% damage, 10% omnivamp
- 7: +40% damage, 20% omnivamp
- 9: **Warband**: Warriors +60% damage, 30% omnivamp; team +20% damage

**Wild** (3 / 4 / 5 / 7) · origin · 8 units
- 3: Wild +15% attack speed
- 4: +25% attack speed
- 5: +35% attack speed, ramp +3% per attack (max 10)
- 7: **Stampede**: team +40% attack speed; Wild ramp +5% per attack (max 15)

**Dwarven** (3 / 4 / 5 / 7) · origin · 7 units
- 3: team +8% HP
- 4: team +12% HP; Dwarven 15% shield
- 5: team +18% HP; Dwarven 25% shield
- 7: **Mountain's Heart**: team +35% HP and a 25% shield

## Shallow (two-step) traits

**Protector** (2 / 4 / 6 / 8) · class · 8 units
- 2: Protectors 20% shield
- 4: 35% shield; team 8% damage reduction
- 6: 55% shield; team 15% damage reduction
- 8: **Bulwark**: Protectors 80% shield; team 25% damage reduction

**Ranger** (2 / 4 / 6) · class · 7 units
- 2: Rangers +20% attack speed
- 4: +40% attack speed, +1 range
- 6: **Deadeye**: +70% attack speed, +1 range, every 3rd attack crits

**Brute** (2 / 4 / 6) · class (new) · 7 units
- 2: Brutes +20% HP
- 4: +40% HP, +15% damage
- 6: **Juggernaut**: +75% HP, +35% damage

**Warlock** (2 / 4 / 6) · class (new) · 6 units
- 2: Warlocks' attacks curse: the target takes 8% more damage
- 4: curse 15%
- 6: **Soul Pact**: curse 25%; Warlocks 20% omnivamp

**Rogue** (2 / 4 / 6) · class · 6 units
- 2: every 4th Rogue attack crits
- 4: every 3rd crits, +15% damage
- 6: **Cutthroat**: every 2nd crits, +30% damage

**Undead** (2 / 4 / 6) · origin · 6 units
- 2: Undead +15% HP
- 4: Undead revive once at 30% HP
- 6: **Undying**: revive at 60% HP; team +15% HP

**Shadow** (2 / 4 / 6) · origin · 6 units
- 2: Shadow +20% damage
- 4: +35% damage, execute below 10%
- 6: **Nightfall**: +55% damage, execute below 20%

**Frost** (2 / 4 / 6) · origin · 6 units
- 2: Frost attacks chill 15%
- 4: chill 30%; Frost 15% damage reduction
- 6: **Deep Freeze**: chill 50%; Frost 30% damage reduction

**Fey** (2 / 4 / 6) · origin · 6 units
- 2: Fey +15% attack speed
- 4: +30% attack speed, +15% damage
- 6: **Glamour**: +50% attack speed, +30% damage; team +15% attack speed

**Celestial** (2 / 4 / 6) · origin (new) · 6 units
- 2: team 8% shield
- 4: team 15% shield; Celestial +20% HP
- 6: **Heavenly Host**: team 25% shield and 1% regen per second; Celestial +40% HP

## Tight-ladder traits

| Trait | Tiers | Units | Effect per tier |
|---|---|---|---|
| Order (origin) | 2 / 3 / 4 / 5 | 5 | Order +15% / +25% / +35% HP, at 4 also 10% damage reduction; at 5 **+50% HP, 20% reduction, team +10% HP** |
| Arcane (origin) | 2 / 3 / 4 / 5 | 5 | team +5% / +10% / +15% / **+25%** damage |
| Ember (origin) | 2 / 3 / 4 / 5 | 5 | Ember attacks burn 2% / 3% / 5% per second; at 5 **burn 8%, +20% damage** |
| Infernal (origin) | 2 / 3 / 4 / 5 | 5 | Infernal +12% / +22% / +35% / **+60%** damage |
| Knight (class, new) | 2 / 3 / 4 / 5 | 5 | Knights 15% / 20% / 30% damage reduction, at 3 +10% and at 4 +20% damage; at 5 **40% reduction, +30% damage, team 10% reduction** |
| Monk (class) | 2 / 3 / 4 / 5 | 5 | Monks +20% / +30% / +45% attack speed, at 4 also 10% damage reduction; at 5 **+60%, 20% reduction** |
| Trickster (class, new) | 2 / 3 / 4 / 5 | 5 | every 5th / 4th / 3rd attack against Tricksters misses; at 5 **every 2nd, and the team dodges every 5th** |
| Healer (class) | 2 / 3 / 4 | 5 | team regen 1% / 2% / **3.5%** max HP per second |
| Bard (class) | 2 / 3 / 4 | 5 | team +8% / +15% / **+25%** attack speed |
| Summoner (class) | 2 / 3 / 4 | 4 | Summoners +20% / +40% HP; at 4 **+65% HP, +20% damage** |
| Elementalist (class, new) | 2 / 3 / 4 | 4 | attacks burn 3% / 5% / 8% per second and chill 15% / 25% / **40%** |
| Duelist (class, new) | 2 / 3 | 3 | ramp +4% / **+7%** attack speed per attack (max 12) |
| Alchemist (class) | 2 / 3 | 3 | team +6% / **+15%** HP and damage |

## Unique traits

| Trait | Holder | Effect |
|---|---|---|
| Dragonlord | Dragon (5) | team +15% damage |
| Ascendant | Seraph (5) | team 10% omnivamp and 1% regen per second |
| Lich King | Deathlord (5) | Deathlord 40% omnivamp; every Undead revives once at 30% HP |
| Earthshaker | Titan (5) | team +20% HP and a 10% shield |
| Rebirth (new) | Phoenix (5) | Phoenix revives once at 60% HP |
| Soulreaper (new) | Reaper (5) | Reaper executes below 20% and heals 30% max HP on each kill |
| Inferno | Pyromancer (3) | Pyromancer +35% damage, burn 5% per second |
| Crusade | Paladin (3) | team 10% damage reduction |

## Unit assignments

| Cost | Unit | Origin | Classes | Unique |
|---|---|---|---|---|
| 1 | Knight | Order | Knight, Warrior |  |
| 1 | Archer | Wild | Ranger |  |
| 1 | Cleric | Celestial | Healer, Caster |  |
| 1 | Militia | Order | Protector |  |
| 1 | Scout | Wild | Ranger |  |
| 1 | Acolyte | Celestial | Healer |  |
| 1 | Apprentice | Arcane | Caster |  |
| 1 | Skeleton | Undead | Warrior |  |
| 1 | Imp | Infernal | Trickster, Rogue |  |
| 1 | Sprite | Fey | Trickster, Caster |  |
| 1 | Firebrand | Ember | Warrior |  |
| 1 | Frostling | Frost | Ranger |  |
| 1 | Miner | Dwarven | Warrior |  |
| 1 | Initiate | Wild | Monk |  |
| 2 | Thief | Shadow | Rogue, Trickster |  |
| 2 | Guardian | Order | Protector |  |
| 2 | Bard | Fey | Bard |  |
| 2 | Alchemist | Dwarven | Alchemist |  |
| 2 | Necromancer | Undead | Summoner, Warlock |  |
| 2 | Ghoul | Undead | Brute |  |
| 2 | Sparkcaller | Ember | Elementalist, Caster |  |
| 2 | Frost Archer | Frost | Ranger |  |
| 2 | Ironbeard | Dwarven | Protector |  |
| 2 | Druid | Wild | Healer |  |
| 2 | Monk | Celestial | Monk |  |
| 2 | Cultist | Infernal | Warlock |  |
| 2 | Nightblade | Shadow | Duelist, Warrior |  |
| 3 | Assassin | Shadow | Rogue |  |
| 3 | Mage | Arcane | Caster |  |
| 3 | Pyromancer | Ember | Elementalist | Inferno |
| 3 | Paladin | Celestial | Knight | Crusade |
| 3 | Ice Mage | Frost | Elementalist, Caster |  |
| 3 | Dryad | Fey | Healer |  |
| 3 | Minstrel | Fey | Bard, Trickster |  |
| 3 | Skald | Dwarven | Bard, Warrior |  |
| 3 | Plague Doctor | Undead | Alchemist, Warlock |  |
| 3 | Runesmith | Dwarven | Alchemist, Caster |  |
| 3 | Shadowfist | Shadow | Monk, Duelist |  |
| 3 | Sunmonk | Celestial | Monk |  |
| 3 | Demonologist | Infernal | Summoner, Warlock |  |
| 3 | Winter Knight | Frost | Knight, Warrior |  |
| 4 | Berserker | Wild | Brute, Warrior |  |
| 4 | Hunter | Wild | Ranger |  |
| 4 | Warlord | Order | Warrior, Brute |  |
| 4 | Duelist | Fey | Duelist, Rogue |  |
| 4 | Nightstalker | Shadow | Ranger, Rogue |  |
| 4 | Lich | Undead | Warlock, Caster |  |
| 4 | Magma Guard | Ember | Protector, Brute |  |
| 4 | Frost Giant | Frost | Protector, Brute |  |
| 4 | Dwarf Gunner | Dwarven | Ranger |  |
| 4 | Archmage | Arcane | Caster |  |
| 4 | Herald | Order | Bard |  |
| 4 | Hellknight | Infernal | Knight, Brute |  |
| 4 | Beastmaster | Wild | Summoner |  |
| 4 | Zen Master | Arcane | Monk |  |
| 5 | Dragon | Arcane | Protector | Dragonlord |
| 5 | Seraph | Celestial | Healer | Ascendant |
| 5 | Deathlord | Undead | Knight | Lich King |
| 5 | Titan | Dwarven | Protector | Earthshaker |
| 5 | Phoenix | Ember | Summoner | Rebirth |
| 5 | Archdemon | Infernal | Warlock, Caster |  |
| 5 | Frost Queen | Frost | Elementalist, Caster |  |
| 5 | Faerie Queen | Fey | Bard, Trickster |  |
| 5 | Reaper | Shadow | Rogue | Soulreaper |
| 5 | Treant | Wild | Protector, Brute |  |

Holders: Caster 11, Warrior 9, Wild 8, Protector 8, Ranger 7, Dwarven 7, Brute 7, Warlock / Undead /
Shadow / Rogue / Frost / Fey / Celestial 6, Order / Arcane / Ember / Infernal / Knight / Monk /
Trickster / Healer / Bard 5, Summoner / Elementalist 4, Duelist / Alchemist 3, each unique 1. Every
trait has at least as many holders as its top tier.

## How it would be built

1. **Data:** `Synergies.DEFS` becomes a list of tiers per trait, each tier a set of effects for the
   holders and/or the team, plus the top tier's name. The tags in the 65 unit files change as above.
2. **Mechanics:** new fields on `Unit` (shield, regen, ramp, crit, execute, revive, burn, chill, dodge,
   curse, range), all stepped in the fixed combat tick, so fights stay deterministic.
3. **Level 10:** XP table and shop odds.
4. **UI:** the synergy dock rows and tooltips, planner chips and inspector read the new tiers
   (`DockKit.effect_text`); shields and burns shown on the health bar.
5. **Checks:** `roster_checks` (35 traits, every tier reachable, at most 3 traits, 8 uniques), new
   `combat_checks` per mechanic (including determinism), tooltip and HUD suites.
6. **Balance:** campaign enemies get synergies too, so `tools/bot_playtest -- chapter` reruns and the
   chapter multipliers are retuned. Old Async PvP ghosts stop matching (the balance hash changes).

Built in chunks, each tested: (1) data, level 10 and UI; (2) the new mechanics; (3) balance.
