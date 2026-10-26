# Unit roster and synergy tree

65 units: 14 one-cost, 13 two-cost, 14 three-cost, 14 four-cost, 10 five-cost. The `.tres` files are the source of truth (`tres/*.tres` for the original 10, `tres/units/*.tres` for the rest); this page is a readable copy. `tools/roster_checks` verifies the shape described below.

## Rules the roster follows
- 35 traits (synergies v2, `docs/synergies-v2.md`): 11 origins, 16 classes, 8 uniques. Every unit has one **origin** and one or two **classes**, at most 3 traits.
  - Origins: Order, Celestial, Wild, Shadow, Arcane, Undead, Ember, Frost, Fey, Dwarven, Infernal.
  - Classes: Warrior, Caster, Protector, Ranger, Rogue, Healer, Summoner, Monk, Bard, Alchemist, Brute, Warlock, Knight, Duelist, Elementalist, Trickster.
- **Unique synergies** (threshold 1, shown as 1/1) belong to one unit each and take the place of a second class: 6 of the 10 five-cost units (Dragon: Dragonlord, Seraph: Ascendant, Deathlord: Lich King, Titan: Earthshaker, Phoenix: Rebirth, Reaper: Soulreaper) and 2 of the 14 three-cost units (Pyromancer: Inferno, Paladin: Crusade).
- Every tier of every synergy can be reached with the roster (checked by `roster_checks`).
- `short_name` is the 2-3 letters on the unit's body; each is unique.
- Display names must stay unique (merging groups by name).

## Units

### 1-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Cleric | CL | Celestial, Healer, Caster | 500 | 35 | 4 | 0.6 | 50 | 20 |
| Archer | AR | Wild, Ranger | 450 | 45 | 5 | 0.8 | 60 | 0 |
| Knight | KN | Order, Knight, Warrior | 650 | 50 | 1 | 0.7 | 80 | 20 |
| Militia | MI | Order, Protector | 600 | 40 | 1 | 0.7 | 70 | 20 |
| Scout | SC | Wild, Ranger | 430 | 42 | 5 | 0.85 | 60 | 0 |
| Acolyte | AC | Celestial, Healer | 480 | 30 | 4 | 0.6 | 50 | 20 |
| Apprentice | AP | Arcane, Caster | 420 | 45 | 4 | 0.7 | 60 | 10 |
| Skeleton | SK | Undead, Warrior | 520 | 48 | 1 | 0.8 | 70 | 0 |
| Imp | IM | Infernal, Trickster, Rogue | 400 | 50 | 1 | 0.95 | 50 | 0 |
| Sprite | SP | Fey, Trickster, Caster | 400 | 38 | 4 | 0.8 | 50 | 10 |
| Firebrand | FI | Ember, Warrior | 540 | 52 | 1 | 0.75 | 70 | 0 |
| Frostling | FR | Frost, Ranger | 440 | 42 | 5 | 0.75 | 60 | 0 |
| Miner | MN | Dwarven, Warrior | 620 | 44 | 1 | 0.7 | 80 | 10 |
| Initiate | IN | Wild, Monk | 500 | 40 | 1 | 0.95 | 60 | 0 |

### 2-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Thief | TH | Shadow, Rogue, Trickster | 550 | 60 | 1 | 0.9 | 50 | 0 |
| Guardian | GU | Order, Protector | 850 | 45 | 1 | 0.6 | 100 | 40 |
| Bard | BA | Fey, Bard | 560 | 40 | 4 | 0.7 | 60 | 20 |
| Alchemist | AL | Dwarven, Alchemist | 600 | 50 | 4 | 0.7 | 60 | 10 |
| Necromancer | NE | Undead, Summoner, Warlock | 580 | 45 | 4 | 0.7 | 70 | 20 |
| Ghoul | GH | Undead, Brute | 700 | 58 | 1 | 0.85 | 60 | 0 |
| Sparkcaller | SPK | Ember, Elementalist, Caster | 540 | 55 | 4 | 0.7 | 60 | 10 |
| Frost Archer | FA | Frost, Ranger | 540 | 55 | 5 | 0.8 | 60 | 0 |
| Ironbeard | IR | Dwarven, Protector | 900 | 42 | 1 | 0.6 | 90 | 30 |
| Druid | DU | Wild, Healer | 620 | 40 | 4 | 0.65 | 60 | 20 |
| Monk | MO | Celestial, Monk | 650 | 52 | 1 | 0.95 | 50 | 10 |
| Cultist | CU | Infernal, Warlock | 560 | 48 | 4 | 0.75 | 60 | 10 |
| Nightblade | NB | Shadow, Duelist, Warrior | 640 | 62 | 1 | 0.9 | 60 | 0 |

### 3-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Assassin | AS | Shadow, Rogue | 700 | 75 | 1 | 0.9 | 60 | 0 |
| Mage | MA | Arcane, Caster | 600 | 55 | 4 | 0.65 | 50 | 10 |
| Pyromancer | PY | Ember, Elementalist, Inferno | 620 | 68 | 4 | 0.7 | 60 | 10 |
| Paladin | PA | Celestial, Knight, Crusade | 850 | 55 | 1 | 0.65 | 90 | 30 |
| Ice Mage | IC | Frost, Elementalist, Caster | 620 | 58 | 4 | 0.65 | 50 | 10 |
| Dryad | DY | Fey, Healer | 680 | 50 | 4 | 0.65 | 60 | 20 |
| Minstrel | MIN | Fey, Bard, Trickster | 640 | 52 | 4 | 0.75 | 60 | 20 |
| Skald | SKA | Dwarven, Bard, Warrior | 760 | 58 | 1 | 0.75 | 70 | 20 |
| Plague Doctor | PD | Undead, Alchemist, Warlock | 650 | 62 | 4 | 0.7 | 60 | 10 |
| Runesmith | RU | Dwarven, Alchemist, Caster | 780 | 60 | 2 | 0.7 | 70 | 20 |
| Shadowfist | SF | Shadow, Monk, Duelist | 700 | 65 | 1 | 1.0 | 50 | 0 |
| Sunmonk | SU | Celestial, Monk | 720 | 66 | 1 | 0.95 | 60 | 10 |
| Demonologist | DE | Infernal, Summoner, Warlock | 650 | 60 | 4 | 0.7 | 70 | 20 |
| Winter Knight | WK | Frost, Knight, Warrior | 880 | 58 | 1 | 0.7 | 80 | 20 |

### 4-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Berserker | BE | Wild, Brute, Warrior | 1000 | 85 | 1 | 0.8 | 80 | 0 |
| Hunter | HU | Wild, Ranger | 750 | 80 | 5 | 0.85 | 70 | 0 |
| Warlord | WL | Order, Warrior, Brute | 950 | 82 | 1 | 0.8 | 80 | 10 |
| Duelist | DL | Fey, Duelist, Rogue | 760 | 92 | 1 | 1.0 | 60 | 0 |
| Nightstalker | NS | Shadow, Ranger, Rogue | 700 | 85 | 5 | 0.9 | 60 | 0 |
| Lich | LI | Undead, Warlock, Caster | 800 | 80 | 4 | 0.7 | 80 | 20 |
| Magma Guard | MG | Ember, Protector, Brute | 1100 | 70 | 1 | 0.65 | 90 | 30 |
| Frost Giant | FG | Frost, Protector, Brute | 1200 | 75 | 1 | 0.6 | 100 | 30 |
| Dwarf Gunner | DG | Dwarven, Ranger | 820 | 88 | 5 | 0.8 | 70 | 0 |
| Archmage | AM | Arcane, Caster | 760 | 82 | 4 | 0.7 | 70 | 20 |
| Herald | HE | Order, Bard | 900 | 72 | 2 | 0.75 | 80 | 30 |
| Hellknight | HK | Infernal, Knight, Brute | 1000 | 88 | 1 | 0.8 | 80 | 0 |
| Beastmaster | BM | Wild, Summoner | 920 | 78 | 1 | 0.8 | 80 | 10 |
| Zen Master | ZM | Arcane, Monk | 880 | 84 | 1 | 1.0 | 60 | 10 |

### 5-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Dragon | DR | Arcane, Protector, Dragonlord | 1400 | 90 | 2 | 0.7 | 100 | 30 |
| Seraph | SE | Celestial, Healer, Ascendant | 1200 | 95 | 4 | 0.7 | 100 | 30 |
| Deathlord | DEA | Undead, Knight, Lich King | 1350 | 100 | 1 | 0.75 | 100 | 20 |
| Titan | TI | Dwarven, Protector, Earthshaker | 1700 | 90 | 1 | 0.6 | 110 | 30 |
| Phoenix | PH | Ember, Summoner, Rebirth | 1100 | 100 | 4 | 0.8 | 90 | 20 |
| Archdemon | ARC | Infernal, Warlock, Caster | 1250 | 105 | 2 | 0.7 | 100 | 20 |
| Frost Queen | FQ | Frost, Elementalist, Caster | 1150 | 98 | 4 | 0.7 | 90 | 30 |
| Faerie Queen | FAE | Fey, Bard, Trickster | 1100 | 90 | 4 | 0.8 | 90 | 40 |
| Reaper | RE | Shadow, Rogue, Soulreaper | 1150 | 115 | 1 | 1.0 | 80 | 0 |
| Treant | TR | Wild, Protector, Brute | 1600 | 85 | 1 | 0.6 | 100 | 30 |

## Synergies

Every trait, its breakpoints and what each tier does: `docs/synergies-v2.md` (the game reads them from `Synergies.DEFS` in `Scripts/synergies.gd`).
