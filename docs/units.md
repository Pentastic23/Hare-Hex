# Unit roster and synergy tree

65 units: 14 one-cost, 13 two-cost, 14 three-cost, 14 four-cost, 10 five-cost. The `.tres` files are the source of truth (`tres/*.tres` for the original 10, `tres/units/*.tres` for the rest); this page is a readable copy. `tools/roster_checks` verifies the shape described below.

## Rules the roster follows
- Every unit has one **origin** and one **class** tag (two normal tags). Origins: Order, Wild, Shadow, Arcane, Undead, Ember, Frost, Fey, Dwarven, Infernal. Classes: Warrior, Ranger, Caster, Protector, Rogue, Healer, Summoner, Monk, Alchemist, Bard.
- **Unique synergies** (threshold 1, shown as 1/1) belong to one unit each and are an extra third tag: 4 of the 10 five-cost units (Dragon: Dragonlord, Seraph: Ascendant, Deathlord: Lich King, Titan: Earthshaker) and 2 of the 14 three-cost units (Pyromancer: Inferno, Paladin: Crusade).
- Every tier of every synergy can be reached with the roster (checked by `roster_checks`).
- `short_name` is the 2-3 letters on the unit's body; each is unique.
- Display names must stay unique (merging groups by name).

## Units

### 1-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Cleric | CL | Order, Caster | 500 | 35 | 3 | 0.6 | 50 | 20 |
| Archer | AR | Wild, Ranger | 450 | 45 | 4 | 0.8 | 60 | 0 |
| Knight | KN | Order, Warrior | 650 | 50 | 1 | 0.7 | 80 | 20 |
| Militia | MI | Order, Protector | 600 | 40 | 1 | 0.7 | 70 | 20 |
| Scout | SC | Wild, Ranger | 430 | 42 | 4 | 0.85 | 60 | 0 |
| Acolyte | AC | Order, Healer | 480 | 30 | 3 | 0.6 | 50 | 20 |
| Apprentice | AP | Arcane, Caster | 420 | 45 | 3 | 0.7 | 60 | 10 |
| Skeleton | SK | Undead, Warrior | 520 | 48 | 1 | 0.8 | 70 | 0 |
| Imp | IM | Infernal, Rogue | 400 | 50 | 1 | 0.95 | 50 | 0 |
| Sprite | SP | Fey, Caster | 400 | 38 | 3 | 0.8 | 50 | 10 |
| Firebrand | FI | Ember, Warrior | 540 | 52 | 1 | 0.75 | 70 | 0 |
| Frostling | FR | Frost, Ranger | 440 | 42 | 4 | 0.75 | 60 | 0 |
| Miner | MN | Dwarven, Warrior | 620 | 44 | 1 | 0.7 | 80 | 10 |
| Initiate | IN | Wild, Monk | 500 | 40 | 1 | 0.95 | 60 | 0 |

### 2-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Thief | TH | Shadow, Rogue | 550 | 60 | 1 | 0.9 | 50 | 0 |
| Guardian | GU | Order, Protector | 850 | 45 | 1 | 0.6 | 100 | 40 |
| Bard | BA | Fey, Bard | 560 | 40 | 3 | 0.7 | 60 | 20 |
| Alchemist | AL | Dwarven, Alchemist | 600 | 50 | 3 | 0.7 | 60 | 10 |
| Necromancer | NE | Undead, Summoner | 580 | 45 | 3 | 0.7 | 70 | 20 |
| Ghoul | GH | Undead, Rogue | 700 | 58 | 1 | 0.85 | 60 | 0 |
| Sparkcaller | SPK | Ember, Caster | 540 | 55 | 3 | 0.7 | 60 | 10 |
| Frost Archer | FA | Frost, Ranger | 540 | 55 | 4 | 0.8 | 60 | 0 |
| Ironbeard | IR | Dwarven, Protector | 900 | 42 | 1 | 0.6 | 90 | 30 |
| Druid | DU | Wild, Healer | 620 | 40 | 3 | 0.65 | 60 | 20 |
| Monk | MO | Order, Monk | 650 | 52 | 1 | 0.95 | 50 | 10 |
| Cultist | CU | Infernal, Summoner | 560 | 48 | 3 | 0.75 | 60 | 10 |
| Nightblade | NB | Shadow, Warrior | 640 | 62 | 1 | 0.9 | 60 | 0 |

### 3-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Assassin | AS | Shadow, Rogue | 700 | 75 | 1 | 0.9 | 60 | 0 |
| Mage | MA | Arcane, Caster | 600 | 55 | 3 | 0.65 | 50 | 10 |
| Pyromancer | PY | Ember, Caster, Inferno | 620 | 68 | 3 | 0.7 | 60 | 10 |
| Paladin | PA | Order, Healer, Crusade | 850 | 55 | 1 | 0.65 | 90 | 30 |
| Ice Mage | IC | Frost, Caster | 620 | 58 | 3 | 0.65 | 50 | 10 |
| Dryad | DY | Fey, Healer | 680 | 50 | 3 | 0.65 | 60 | 20 |
| Minstrel | MIN | Fey, Bard | 640 | 52 | 3 | 0.75 | 60 | 20 |
| Skald | SKA | Dwarven, Bard | 760 | 58 | 1 | 0.75 | 70 | 20 |
| Plague Doctor | PD | Undead, Alchemist | 650 | 62 | 3 | 0.7 | 60 | 10 |
| Runesmith | RU | Dwarven, Alchemist | 780 | 60 | 2 | 0.7 | 70 | 20 |
| Shadowfist | SF | Shadow, Monk | 700 | 65 | 1 | 1.0 | 50 | 0 |
| Sunmonk | SU | Ember, Monk | 720 | 66 | 1 | 0.95 | 60 | 10 |
| Demonologist | DE | Infernal, Summoner | 650 | 60 | 3 | 0.7 | 70 | 20 |
| Winter Knight | WK | Frost, Warrior | 880 | 58 | 1 | 0.7 | 80 | 20 |

### 4-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Berserker | BE | Wild, Warrior | 1000 | 85 | 1 | 0.8 | 80 | 0 |
| Hunter | HU | Wild, Ranger | 750 | 80 | 4 | 0.85 | 70 | 0 |
| Warlord | WL | Order, Warrior | 950 | 82 | 1 | 0.8 | 80 | 10 |
| Duelist | DL | Fey, Rogue | 760 | 92 | 1 | 1.0 | 60 | 0 |
| Nightstalker | NS | Shadow, Ranger | 700 | 85 | 4 | 0.9 | 60 | 0 |
| Lich | LI | Undead, Caster | 800 | 80 | 3 | 0.7 | 80 | 20 |
| Magma Guard | MG | Ember, Protector | 1100 | 70 | 1 | 0.65 | 90 | 30 |
| Frost Giant | FG | Frost, Protector | 1200 | 75 | 1 | 0.6 | 100 | 30 |
| Dwarf Gunner | DG | Dwarven, Ranger | 820 | 88 | 4 | 0.8 | 70 | 0 |
| Archmage | AM | Arcane, Caster | 760 | 82 | 3 | 0.7 | 70 | 20 |
| Herald | HE | Order, Bard | 900 | 72 | 2 | 0.75 | 80 | 30 |
| Hellknight | HK | Infernal, Warrior | 1000 | 88 | 1 | 0.8 | 80 | 0 |
| Beastmaster | BM | Wild, Summoner | 920 | 78 | 1 | 0.8 | 80 | 10 |
| Zen Master | ZM | Arcane, Monk | 880 | 84 | 1 | 1.0 | 60 | 10 |

### 5-cost

| Unit | Label | Tags | HP | Dmg | Range | Atk/s | Mana | Start |
|---|---|---|---|---|---|---|---|---|
| Dragon | DR | Arcane, Protector, Dragonlord | 1400 | 90 | 2 | 0.7 | 100 | 30 |
| Seraph | SE | Order, Healer, Ascendant | 1200 | 95 | 3 | 0.7 | 100 | 30 |
| Deathlord | DEA | Undead, Warrior, Lich King | 1350 | 100 | 1 | 0.75 | 100 | 20 |
| Titan | TI | Dwarven, Protector, Earthshaker | 1700 | 90 | 1 | 0.6 | 110 | 30 |
| Phoenix | PH | Ember, Summoner | 1100 | 100 | 3 | 0.8 | 90 | 20 |
| Archdemon | ARC | Infernal, Caster | 1250 | 105 | 2 | 0.7 | 100 | 20 |
| Frost Queen | FQ | Frost, Caster | 1150 | 98 | 3 | 0.7 | 90 | 30 |
| Faerie Queen | FAE | Fey, Bard | 1100 | 90 | 3 | 0.8 | 90 | 40 |
| Reaper | RE | Shadow, Rogue | 1150 | 115 | 1 | 1.0 | 80 | 0 |
| Treant | TR | Wild, Protector | 1600 | 85 | 1 | 0.6 | 100 | 30 |

## Synergies

| Tag | Tiers | Effect |
|---|---|---|
| Order | 2, 3 | Order units gain 20% / 40% max HP |
| Wild | 2, 3 | Wild units gain 15% / 30% attack speed |
| Shadow | 2 | Shadow units heal for 20% of damage dealt |
| Arcane | 2 | Your team deals 10% more damage |
| Warrior | 2 | Warriors take 20% less damage |
| Ranger | 2 | Rangers gain 25% attack speed |
| Caster | 2 | Casters start combat with +20 mana |
| Protector | 2 | Your team takes 10% less damage |
| Rogue | 2 | Rogues deal 40% more damage |
| Undead | 2, 4 | Undead units heal for 15% / 30% of damage dealt |
| Ember | 2, 4 | Ember units deal 20% / 45% more damage |
| Frost | 2, 4 | Frost units take 15% / 30% less damage |
| Fey | 2, 4 | Fey units gain 15% / 40% attack speed |
| Dwarven | 2, 4 | Your team gains 10% / 25% max HP |
| Infernal | 2, 3 | Infernal units deal 15% / 40% more damage |
| Healer | 2, 4 | Your team heals for 6% / 15% of damage dealt |
| Summoner | 2, 3 | Summoners gain 15% / 35% max HP |
| Monk | 2, 4 | Monks gain 20% / 45% attack speed |
| Alchemist | 2, 3 | Your team deals 8% / 20% more damage |
| Bard | 2, 4 | Your team starts combat with +10 / +25 mana |
| Dragonlord | 1 | Your team deals 15% more damage |
| Ascendant | 1 | Your team heals for 10% of damage dealt |
| Lich King | 1 | The Lich King heals for 40% of damage dealt |
| Earthshaker | 1 | Your team gains 20% max HP |
| Inferno | 1 | The Pyromancer deals 35% more damage |
| Crusade | 1 | Your team takes 8% less damage |
