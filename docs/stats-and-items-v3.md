# Stats and items v3 (2026-10-27)

What changed from items v2 (`docs/items-v2.md`) and synergies v2 (`docs/synergies-v2.md`). The user's
decisions: TFT-style damage types; 4 items for each of the 9 stats; one element per stat; synergies
converted to the new stats with no two traits giving the same bonus; the 15 resonances + Prism kept.

## Damage and stats

| Stat | Kind | What it does |
|---|---|---|
| Attack power | % (`ad`, `attack_power`) | attack damage x (1 + attack power) |
| Ability power | % (`ap`, `ability_power`) | ability damage, and the heals and shields abilities give, x (1 + ability power). The inspector shows it as 100 + that % |
| Armour | flat (`armor`) | physical damage taken x 100 / (100 + armour) |
| Magic resist | flat (`mr`, `magic_resist`) | magic damage taken x 100 / (100 + magic resist) |
| Mitigation | flat (`mit`, `mitigation`) | taken off every hit after armour / magic resist; a hit still deals at least 1; not off damage over time |

- **Damage types** (`Unit.take_damage(amount, by, attack, pierce, kind, tick)`): attacks (and anything
  that counts as one: empowered attacks, the Initiate's strikes) are **physical**; everything else
  (ability hits, burns, zones, Doom, thorns, kings' strikes) is **magic**; executes are **true damage**
  (`pierce`: no curse, resists or mitigation). `tick = true` marks burn and zone slices, which mitigation
  leaves alone (it would wipe them out). Curse still multiplies physical and magic damage.
- **Base resists** (`UnitData.armor` / `magic_resist`): front-liners (range 1-2, 35 units) 20 / 20, the
  back line (30 units) 10 / 10. They don't scale with stars.
- **Sunder / shred** (new effect keys): attacks lower the target's armour / magic resist by that much
  for 3 s (`Unit.apply_sunder` / `apply_shred`; the bigger cut wins, never below 0).
- **Summon** (new effect key): what the unit summons gets that much more HP and damage (via the
  summon's `stat_scale`).
- Gone: the old shared `dmg` (attacks and abilities) and `dr` (% damage reduction, 60% cap) keys, the
  items' flat damage and % damage reduction. Ability buffs that gave "% less damage" now give armour
  and magic resist (Shell Up 100, Frozen Bulwark 35, Rallying Cry and Red Fury 25); War Chant gives
  attack power.

## Items: 4 per stat + the 9 unique items (45)

One element per stat, so resonances work as before: attack power **Might**, HP and mitigation
**Vigor**, attack speed **Swift**, armour and magic resist **Guard**, omnivamp **Blood**, ability power
and mana **Arcane**. Each stat has a plain item, two with a small second stat or rule, and a big one
with a drawback that drops from stage 2. Drop weights are 1.0 for the 4-item elements and 0.5 for the
8-item ones, so every element still drops equally often and the resonance spread is unchanged.

| Stat | Items |
|---|---|
| Attack power | Longsword +20%; War Axe +15%, +100 HP; Serrated Dirk +12%, sunder 15; Giant's Maul +35%, -10% attack speed |
| HP | Iron Belt +150; Troll Hide +100, 1% regen; Heart Locket +100, 12% shield; Ogre's Girdle +300, -10% attack speed |
| Mitigation | Leather Jerkin 8; Hide Bracers 6, +80 HP; Padded Gambeson 6, +15 magic resist; Stone Ring 15, -10% attack speed |
| Attack speed | Quick Bow +15%; Swift Gloves +10%, +8% attack power; Wind Charm +10%, chill 10%; Feather Boots +28%, -100 HP |
| Armour | Chain Vest +25; Tower Shield +20, +100 HP; Bronze Buckler +18, dodge every 6th; Plate Cuirass +50, -10% attack speed |
| Magic resist | Warding Cloak +25; Silver Circlet +20, +10 mana; Spellward Talisman +15, +15 armour; Nullstone Amulet +50, -10% ability power |
| Omnivamp | Blood Fang 10%; Vampire Ring 8%, 15% kill heal; Hungering Blade 8%, +10% attack power; Sanguine Tome 8%, +10% ability power |
| Ability power | Apprentice Wand +20%; Sage's Staff +15%, +10 mana; Hex Orb +12%, shred 15; Archmage's Tome +35%, -100 HP |
| Mana | Mana Charm +15, +8% ability power; Spirit Bead +10, +15 magic resist; Moon Tear +10, +10% attack speed; Focus Gem +30, -80 HP |

The old basic items keep their ids (saves, waves and ghosts load them): Longsword went from +15 flat
damage to +20% attack power, Chain Vest from 10% damage reduction to +25 armour, Mana Charm's +8%
damage became +8% ability power. Hero's Blade is +10% attack power and +4% per stack. The Resonance
Crystal alone gives +8% HP, attack power and ability power. Icons for the 30 new items are placeholders
from `tools/make_item_icons.gd`.

## Resonances

Same 15 pairs and Prism; only the ones using the old keys changed: Juggernaut +10% HP and attack
power, Vanguard +10% attack power and +15 armour, Spellblade +10% attack and ability power, Prism +10%
HP, attack power, ability power and attack speed.

## Traits: one bonus each

Every (scope, effect) pair belongs to one trait (`tools/roster_checks` checks it):

| Trait | Bonus | Trait | Bonus |
|---|---|---|---|
| Order | mitigation (holders) | Warrior | omnivamp (holders) |
| Celestial | shield (team) | Caster | ability power (holders) |
| Wild | sunder (holders; team at 7) | Protector | shield (holders), mitigation (team) |
| Shadow | execute (holders) | Ranger | attack speed and range (holders) |
| Arcane | ability power (team) | Rogue | crit (holders) |
| Undead | revive (holders) | Brute | HP (holders) |
| Ember | burn (holders) | Warlock | curse (holders) |
| Frost | chill (holders; team at 6) | Knight | armour (holders) |
| Fey | ramp (holders) | Monk | magic resist (holders) |
| Dwarven | HP (team) | Trickster | dodge (holders) |
| Infernal | attack power (holders) | Healer | regen (team) |
| Bard | attack speed (team) | Summoner | summon power (holders) |
| Elementalist | shred (holders) | Duelist | kill heal (holders) |
| Alchemist | omnivamp (team) | | |
| Dragonlord | attack power (team) | Ascendant | magic resist (team) |
| Lich King | revive (Undead) | Earthshaker | armour (team) |
| Rebirth | regen (Phoenix) | Soulreaper | execute (team) |
| Inferno | burn (team) | Crusade | crit (team) |

Numbers are in `Scripts/synergies.gd`. Not balanced with the bot yet: the campaign's `enemy_stat_mult`
values were tuned before this change.
