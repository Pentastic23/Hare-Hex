# Abilities: one per unit (plan)

Status: **chunks 1 and 2 built** (2026-10-23): 46 units cast for real (`Scripts/abilities.gd`, `tools/ability_checks`). Chunks 3 and 4 (19 units) still cast the placeholder. Spell effects (VFX) come after the abilities, and the bot balance pass waits until all 65 are in (user decisions). Roadmap item 1. If this doc and the code disagree, the code wins.

Every one of the 65 units gets its own ability, themed on its animal, its class and its origin. Today a full mana bar casts a placeholder (`Ability.cast` does nothing and a "CAST" word floats up). This plan says what each cast does, the rules all abilities share, the new combat mechanics they need, and the order to build them in.

## Shared rules

- **When:** unchanged. A unit casts when its mana is full (`max_mana` in its .tres), instead of attacking that tick. Mana: +10 per attack, +10% of damage taken (max 15 per hit). Mana resets to 0 after the cast. **Casts don't give mana.**
- **Cast time:** a cast locks the caster for 0.5 s (30 ticks): it plays the skill clip and doesn't attack or move. Channelled abilities say so and lock it longer.
- **Star scaling:** damage, healing and shields scale like stats, x1 / x1.8 / x3.2, and are written as `1★ / 2★ / 3★`. Durations, counts and areas don't scale unless the entry says so.
- **Ability damage:** reduced by damage reduction and absorbed by shields like an attack, and multiplied by the caster's damage bonus from synergies and items (so Arcane, Spellblade and the rest help casters). It doesn't count as an attack: no crit, dodge, burn, chill or curse from traits or resonances, and no mana for the caster. Omnivamp does heal from it (it is omni-vamp).
- **Healing:** heals never go over max HP. Shields from abilities are flat amounts that last the time given, on top of the trait shields.
- **Areas on the hex grid:** "adjacent" = within 1 hex. "Radius N" = every hex within N of the centre. A "line" = the hexes straight on from the caster through the target, using the hex direction closest to the target.
- **Targets, deterministic:** "target" is the unit's current attack target. Other picks (lowest HP, farthest, the busiest cluster) break ties with `Board.tile_order`, like attack targets. The **cluster** is the enemy whose tile has the most enemies within 1 hex. Nothing is random; durations are counted in ticks.
- **Crowd control:**
  - **Stun:** no attacks, moves or mana gain.
  - **Root:** no moving, but it can still attack.
  - **Silence:** no mana gain.
  - **Taunt:** the taunted unit's target becomes the taunter.
  - **Blind:** the next N attacks miss.
  - Crowd control on the same unit doesn't stack; the longer one wins.
- **UI:** the popup shows the ability's name instead of "CAST". The unit inspector and the shop card's tooltip show the ability name and its text at the unit's star. The planner tile tooltip shows it too.
- **Free-play random enemies cast too.** Campaign waves and ghosts cast as well, so the campaign needs a bot retune once abilities land (see Balance).

## New mechanics

Already in combat and reused here: burn, chill, curse, shield, regen, execute, revive, dodge (from synergies v2 and items v2).

New ones, each a small deterministic system in `unit.gd` / `game_manager.gd`:

| Mechanic | What it is | Used by |
|---|---|---|
| Direct heal | heal an amount now (capped at max HP) | Cleric, Alchemist, Monk, Ghoul, Skeleton, Dryad, Paladin, Treant, Seraph, Herald, Zen Master |
| Flat shield with a duration | a shield amount for N seconds | Acolyte, Militia, Ironbeard, Runesmith, Magma Guard, Dragon, Winter Knight |
| Timed buff / debuff | +stat% for N seconds (attack speed, damage, damage reduction, omnivamp) | Bard, Skald, Alchemist, Berserker, Herald, Hellknight, Winter Knight, Guardian |
| Stun, root, silence, blind, taunt | crowd control, as defined above | many (see each unit) |
| Movement | **dash** (move along a path, hitting what it passes), **leap / teleport** (to the open hex next to a unit); claims the tile like a normal step | Scout, Nightblade, Assassin, Warlord |
| Untargetable | can't be picked as a target; attackers retarget | Nightstalker, Seraph (on an ally) |
| Summons | a temporary unit on the nearest open hex (by tile order): no traits, no items, gone at the end of the fight, never on the bench, not in the damage meter's totals | Necromancer, Demonologist, Beastmaster |
| Zones | an area that ticks for N seconds | Plague Doctor, Druid, Frost Queen |
| Thorns | attackers take damage per hit | Runesmith |
| Mana grant / burn | add mana to an ally, or empty an enemy's | Minstrel, Zen Master |
| Link | part of an ally's damage goes to the caster instead | Paladin |
| Delayed damage | a mark that goes off after N seconds | Archdemon |
| Parry | attacks against the unit are blocked and countered for a time | Duelist |
| Charm | the enemy attacks its own side for a time | Faerie Queen |
| Raise | fallen allies come back for a time | Deathlord |

## The 65 abilities

Format: **Ability name**, then the effect with values at 1★ / 2★ / 3★. Mana is the unit's current `max_mana` (start mana in brackets). Values are first drafts for the balance pass.

### 1-cost (about 4 attacks' worth of value)

| Unit (animal) | Traits | Mana | Ability |
|---|---|---|---|
| Cleric (sheep) | Celestial, Healer, Caster | 50 (20) | **Shepherd's Light**: heals the two allies with the lowest HP% for 110 / 200 / 350 each. |
| Archer (fox) | Wild, Ranger | 60 (0) | **Fox Volley**: three arrows, one at each of the three nearest enemies, 90 / 160 / 290 each. |
| Knight (lion) | Order, Knight, Warrior | 80 (20) | **Lion's Roar**: strikes the target for 180 / 325 / 575 and stuns it for 1 s. |
| Militia (badger) | Order, Protector | 70 (20) | **Dig In**: gains a 200 / 360 / 640 shield for 4 s and taunts adjacent enemies for 2 s. |
| Scout (hare) | Wild, Ranger | 60 (0) | **Hare's Hop**: leaps up to 2 hexes to the open hex farthest from enemies; its next 3 attacks deal +40 / 70 / 125 damage. |
| Acolyte (mouse) | Celestial, Healer | 50 (20) | **Little Prayer**: shields the ally with the lowest HP% for 150 / 270 / 480 for 4 s. Whatever is left of the shield when it ends heals that ally. |
| Apprentice (frog) | Arcane, Caster | 60 (10) | **Hopping Bolt**: a bolt hits the target for 120 / 215 / 385, then hops to the nearest enemy not yet hit, twice; each hop deals 30% less. |
| Skeleton (skeletal rat) | Undead, Warrior | 70 (0) | **Gnaw**: bites the target for 150 / 270 / 480 and heals for half the damage dealt. |
| Imp (bat) | Infernal, Trickster, Rogue | 50 (0) | **Sonic Screech**: enemies within 2 hexes take 80 / 145 / 255 and are chilled 30% for 3 s. |
| Sprite (fairy squirrel) | Fey, Trickster, Caster | 50 (10) | **Acorn Hex**: throws an acorn at the target for 120 / 215 / 385 and silences it for 2 / 2.5 / 3 s. |
| Firebrand (red panda) | Ember, Warrior | 70 (0) | **Flare Spin**: spins, dealing 110 / 200 / 350 to every adjacent enemy and burning them. |
| Frostling (penguin) | Frost, Ranger | 60 (0) | **Snowball**: hits the target for 130 / 235 / 415 and chills it and the enemies adjacent to it by 30% for 3 s. |
| Miner (mole) | Dwarven, Warrior | 80 (10) | **Pick Through**: strikes the target for 160 / 290 / 510 and cracks its armour: it takes 15% more damage for 4 s (curse). |
| Initiate (monkey) | Wild, Monk | 60 (0) | **Monkey Barrage**: five quick strikes on the target, 35 / 65 / 110 each. Each strike counts as an attack, so on-hit effects apply. |

### 2-cost (about 6 attacks' worth)

| Unit (animal) | Traits | Mana | Ability |
|---|---|---|---|
| Thief (raccoon) | Shadow, Rogue, Trickster | 50 (0) | **Pickpocket**: strikes the target for 200 / 360 / 640. If the Thief lands the killing blow, you get 1 gold (your units only). 1 gold per kill at every star level, with no limit per round. |
| Guardian (tortoise) | Order, Protector | 100 (40) | **Shell Up**: pulls into its shell: 50% damage reduction for 3 s, and taunts enemies within 2 hexes for 2 s. |
| Bard (robin) | Fey, Bard | 60 (20) | **Dawn Chorus**: allies within 2 hexes (itself too) gain 25 / 35 / 50% attack speed for 4 s. |
| Alchemist (beaver) | Dwarven, Alchemist | 60 (10) | **Tonic Flask**: throws a tonic at the ally with the lowest HP%: heals 150 / 270 / 480 and gives +20% attack speed for 3 s. |
| Necromancer (raven) | Undead, Summoner, Warlock | 70 (20) | **Raise Thrall**: raises a Bone Thrall (300 / 540 / 960 HP, 30 / 55 / 95 damage, melee) next to itself. At most one alive; casting again heals it fully instead. |
| Ghoul (undead hyena) | Undead, Brute | 60 (0) | **Feast**: bites the target for 180 / 325 / 575. If the target is below 30% HP afterwards, the Ghoul heals 200 / 360 / 640. |
| Sparkcaller (fire salamander) | Ember, Elementalist, Caster | 60 (10) | **Arc Lash**: a whip of sparks hits every enemy in a line through the target, up to 3 hexes, for 170 / 305 / 545. |
| Frost Archer (snow lynx) | Frost, Ranger | 60 (0) | **Piercing Icicle**: shoots the farthest enemy for 220 / 395 / 705 and chills it 40% for 3 s. |
| Ironbeard (mountain goat) | Dwarven, Protector | 90 (30) | **Headbutt**: rams the target for 150 / 270 / 480, stuns it for 1.5 s and gains a 150 / 270 / 480 shield for 4 s. |
| Druid (stag) | Wild, Healer | 60 (20) | **Antler Grove**: grows a grove around itself (radius 1) for 4 s: allies in it regenerate 3 / 4 / 5% of max HP per second. |
| Monk (panda) | Celestial, Monk | 50 (10) | **Bamboo Calm**: sits for 1 s (channelled), heals 25% of its max HP, and its next attack stuns the target for 1 s. |
| Cultist (ferret) | Infernal, Warlock | 60 (10) | **Blood Pact**: spends 10% of its current HP to curse the two nearest enemies (+25% damage taken for 4 s) and burn them. |
| Nightblade (black panther) | Shadow, Duelist, Warrior | 60 (0) | **Panther Pounce**: leaps to the enemy with the lowest HP within 4 hexes and strikes it for 220 / 395 / 705. |

### 3-cost (about 8 attacks' worth, first area crowd control)

| Unit (animal) | Traits | Mana | Ability |
|---|---|---|---|
| Assassin (black cat) | Shadow, Rogue | 60 (0) | **Shadowstep**: teleports behind the enemy farthest from it (the backline) and strikes for 300 / 540 / 960. |
| Mage (owl) | Arcane, Caster | 50 (10) | **Moonbolt Volley**: four bolts, one after another; each hits whichever enemy has the lowest HP when it is fired, for 90 / 160 / 290. |
| Pyromancer (meerkat) | Ember, Elementalist, Inferno | 60 (10) | **Flame Pillar**: a pillar of fire on the cluster: 220 / 395 / 705 to every enemy in radius 1, and their burns are twice as strong for 4 s. |
| Paladin (golden retriever) | Celestial, Knight, Crusade | 90 (30) | **Loyal Guard**: heals the ally with the lowest HP% for 150 / 270 / 480 and links to it for 4 s: half the damage that ally takes goes to the Paladin instead. |
| Ice Mage (walrus) | Frost, Elementalist, Caster | 50 (10) | **Glacier Slam**: drops a block of ice on the cluster: 180 / 325 / 575 to every enemy in radius 1, stunned for 1.25 s. |
| Dryad (koala) | Fey, Healer | 60 (20) | **Eucalyptus Bloom**: heals every ally for 70 / 125 / 225 and gives them 1% regen per second for 4 s. |
| Minstrel (otter) | Fey, Bard, Trickster | 60 (20) | **Encore**: plays for the two allies closest to a full mana bar (not itself): each gains 30 / 40 / 60 mana. |
| Skald (boar) | Dwarven, Bard, Warrior | 70 (20) | **War Chant**: allies within 2 hexes gain +20 / 30 / 45% damage for 4 s; the Skald gains a 150 / 270 / 480 shield. |
| Plague Doctor (vulture) | Undead, Alchemist, Warlock | 60 (10) | **Miasma**: a plague cloud on the cluster (radius 1) for 4 s: enemies in it take 50 / 90 / 160 per second and are cursed 15%. |
| Runesmith (armadillo) | Dwarven, Alchemist, Caster | 70 (20) | **Rune Ward**: carves a rune on the two allies with the lowest HP%: a 160 / 290 / 510 shield and thorns (attackers take 20 / 35 / 65 per hit) for 4 s. |
| Shadowfist (skunk) | Shadow, Monk, Duelist | 50 (0) | **Stink Cloud**: adjacent enemies take 120 / 215 / 385 and are blinded: their next 2 attacks miss. |
| Sunmonk (tiger) | Celestial, Monk | 60 (10) | **Solar Palm**: a three-hit combo on the target, 100 / 180 / 320 each; the last hit stuns for 1 s. |
| Demonologist (lemur) | Infernal, Summoner, Warlock | 70 (20) | **Pact Demon**: summons a Pact Demon (350 / 630 / 1120 HP, 40 / 70 / 130 damage, melee). When it dies it explodes for 150 / 270 / 480 to adjacent enemies. At most two alive. |
| Winter Knight (polar bear) | Frost, Knight, Warrior | 80 (20) | **Frozen Bulwark**: slams the ice: adjacent enemies are chilled 50% for 3 s, and it gains 25% damage reduction for 4 s. |

### 4-cost (fight-swinging, about 10 attacks' worth)

| Unit (animal) | Traits | Mana | Ability |
|---|---|---|---|
| Berserker (bear) | Wild, Brute, Warrior | 80 (0) | **Bloodrage**: for 5 s, +60 / 75 / 100% attack speed and 30% omnivamp. |
| Hunter (wolf) | Wild, Ranger | 70 (0) | **Hunter's Mark**: shoots the enemy with the lowest HP for 250 / 450 / 800 and marks it: it takes 30% more damage from everyone for 5 s. |
| Warlord (rhino) | Order, Warrior, Brute | 80 (10) | **Rhino Charge**: charges up to 4 hexes towards the farthest enemy, stopping before the first unit in the way. Every enemy next to its path takes 200 / 360 / 640 and is stunned for 1 s. (As built: towards the farthest enemy, because the Warlord is melee and its target is already next to it when it casts.) |
| Duelist (rooster) | Fey, Duelist, Rogue | 60 (0) | **Riposte**: takes a stance for 2 s: attacks against it are parried (no damage) and each is answered with a counter for 80 / 145 / 255. |
| Nightstalker (coyote) | Shadow, Ranger, Rogue | 60 (0) | **Moonlit Hunt**: vanishes for 2 s (untargetable, keeps attacking); its first attack after reappearing deals +250 / 450 / 800 and always crits. |
| Lich (crocodile) | Undead, Warlock, Caster | 80 (20) | **Death Roll**: seizes the target: stunned for 1.5 s while taking 350 / 630 / 1120 over that time (channelled). The Lich heals for 30% of it. |
| Magma Guard (hippo) | Ember, Protector, Brute | 90 (30) | **Molten Shell**: gains a 400 / 720 / 1280 shield for 5 s. When it breaks or runs out, it erupts: adjacent enemies take damage equal to the shield it started with and burn. |
| Frost Giant (mammoth) | Frost, Protector, Brute | 100 (30) | **Avalanche Stomp**: enemies within 2 hexes take 150 / 270 / 480 and are stunned for 1.5 s. |
| Dwarf Gunner (hedgehog) | Dwarven, Ranger | 70 (0) | **Quill Shot**: a blast of quills hits the target and every enemy adjacent to it for 200 / 360 / 640, cursing them 10% for 4 s. |
| Archmage (peacock) | Arcane, Caster | 70 (20) | **Dazzling Display**: fans its tail: enemies within 2 hexes are stunned for 1 s, then the three nearest take 220 / 395 / 705. |
| Herald (eagle) | Order, Bard | 80 (30) | **Rallying Cry**: every ally gains 20% damage reduction and +15% attack speed for 4 s; Order allies also heal 100 / 180 / 320. |
| Hellknight (bull) | Infernal, Knight, Brute | 80 (0) | **Red Fury**: taunts enemies within 2 hexes for 2 s and gains 30% omnivamp and 20% damage reduction for 4 s. |
| Beastmaster (gorilla) | Wild, Summoner | 80 (10) | **Jungle Call**: summons two jungle beasts (250 / 450 / 800 HP, 35 / 65 / 110 damage, fast melee) next to itself. Casting again replaces any that died. |
| Zen Master (crane) | Arcane, Monk | 60 (10) | **Pressure Point**: strikes the target for 200 / 360 / 640; it is stunned for 2 s and its mana is emptied. |

### 5-cost (the showpieces)

| Unit (animal) | Traits | Mana | Ability |
|---|---|---|---|
| Dragon (red dragon) | Arcane, Protector, Dragonlord | 100 (30) | **Dragonfire Breath**: breathes fire on the target and every hex next to it on the far side from the Dragon (a 4-hex cone): 400 / 720 / 1280 and a burn. The Dragon gains a 300 / 540 / 960 shield for 4 s. |
| Seraph (pegasus) | Celestial, Healer, Ascendant | 100 (30) | **Wings of Dawn**: heals every ally for 200 / 360 / 640; the ally with the lowest HP% is also untargetable for 1.5 s. |
| Deathlord (jackal) | Undead, Knight, Lich King | 100 (20) | **Army of the Dead**: every ally that has died this fight rises where it fell (or on the nearest open hex) at 30% HP for 5 s, then falls again. Once per fight; later casts strike the target for 400 / 720 / 1280. |
| Titan (elephant) | Dwarven, Protector, Earthshaker | 110 (30) | **Earthquake**: stamps: every enemy is stunned for 1 s; those within 2 hexes also take 300 / 540 / 960. |
| Phoenix (phoenix) | Ember, Summoner, Rebirth | 90 (20) | **Sunfire Nova**: sets every enemy burning for 6 s (twice the normal burn), and allies heal for 10% of the burn damage dealt. |
| Archdemon (demon ram) | Infernal, Warlock, Caster | 100 (20) | **Doom**: dooms the enemy with the most HP: after 4 s it takes 600 / 1080 / 1920. If it dies before then, the doom jumps to the nearest enemy and the clock restarts. |
| Frost Queen (ermine) | Frost, Elementalist, Caster | 90 (30) | **Eternal Winter**: a blizzard over the enemy half for 4 s: enemies are chilled 50% and take 60 / 110 / 190 per second. When it ends, every enemy below 50% HP is frozen (stunned) for 1.5 s. |
| Faerie Queen (luna moth) | Fey, Bard, Trickster | 90 (40) | **Moonlit Charm**: charms the two enemies that deal the most damage: for 3 / 3.5 / 4 s they attack their own side. Charmed units are clearly marked as hexed (see Charm visuals). |
| Reaper (mantis) | Shadow, Rogue, Soulreaper | 80 (0) | **Scythe Sweep**: slashes every adjacent enemy for 300 / 540 / 960 and executes any left below 20%. Each kill refunds 40 mana. |
| Treant (moose) | Wild, Protector, Brute | 100 (30) | **Overgrowth**: roots enemies within 2 hexes for 2 s, deals 120 / 215 / 385 to them, and heals itself for 20% of its max HP. |

## How they fit together

- **Every unit is different.** Units that share a job do it differently:
  - **Stuns:** Knight on one target, Ice Mage on a cluster, Frost Giant around itself, Titan everyone, Zen Master with a mana burn.
  - **Heals:** Cleric heals two allies, Acolyte shields one, Dryad heals everyone, Seraph adds untargetable, Paladin takes the hits.
  - **Leaps:** Scout leaps away, Nightblade to the weakest enemy, Assassin to the backline.
  - **Summons:** the Necromancer's thrall tanks, the Demonologist's demons explode, the Beastmaster's pack hits fast.
- **Traits get a reason to stack mana.** Mana Charm (+15 start mana) and the Minstrel's Encore now matter. Bards buff, Healers heal, and Protectors taunt and shield, so each class's ability matches its trait. Summoners finally summon.
- **Uniques** get abilities that echo their trait: the Phoenix's Rebirth trait plus its burn-heal nova, the Reaper's execute trait plus its execute sweep, the Deathlord raising the dead.

## Build order (each chunk tested, like synergies v2 and items v2)

1. **Toolkit and simple casts (40 units), built 2026-10-23:** the ability data format, cast time, the name popup, ability damage, direct heal, flat shields, timed buffs and debuffs, stun, silence, blind and taunt; areas, lines, clusters and multi-target picks. That covers every unit not listed in the later chunks. Checks: one per mechanic, plus a fight full of casts resolved twice (deterministic).
2. **Movement and stealth (6), built 2026-10-23:** leap, teleport and dash with tile claiming, untargetable. Scout, Nightblade, Assassin, Warlord, Nightstalker, Seraph.
3. **Summons and zones (6):** temporary units, persistent areas, thorns. Necromancer, Demonologist, Beastmaster, Plague Doctor, Druid, Runesmith.
4. **Special rules (13):** mana grant and burn, link, parry, delayed damage, root, charm, raise, the Thief's gold, eruptions and refunds. Minstrel, Zen Master, Paladin, Duelist, Archdemon, Treant, Faerie Queen, Deathlord, Thief, Magma Guard, Reaper, Phoenix, Frost Queen.
5. **UI and balance:** ability text in the inspector, shop and planner tooltips (`Tip.wrap`, checked by `tooltip_checks`); a combat speed check; a bot retune of every campaign level's `enemy_stat_mult` (casts make both sides stronger, but waves are hand-built, so expect the clear rates to move).

**Data format (as built):** like `Synergies.DEFS`, the abilities are a table in code, `Abilities.DEFS` in `Scripts/abilities.gd`, keyed by unit name: the name, the text and the numbers (a plain number scales with stars x1 / x1.8 / x3.2, rounded to 5; an array is per star as written). What each one does is a short entry in `Abilities.cast()`. Balance changes are edits to the table. The `Ability` resource and `UnitData.ability` stay for the units not built yet.

## Balance notes

- First-draft values aim for about 4 / 6 / 8 / 10 / 14 attacks' worth of value per cast for costs 1-5. The bot runs will show which ones are off.
- Units with low max mana (50) cast about every 5 s. If those abilities prove too strong, raise their mana before cutting the numbers, so the casts still feel big.
- **Hard crowd control** (area stuns: Ice Mage, Frost Giant, Archmage, Titan; charm: Faerie Queen) is the biggest risk. Crowd control doesn't stack (the longer one wins), but chains of stuns could still lock a board, so the first balance check should be a free-play run with several stunners on each side.
- The Thief's gold has no cap, so watch it in the bot runs: a 3-star Thief with Shadow and Rogue could kill several units a fight. Raising its mana is the first lever if it earns too much.
- Free-play random enemies scale with the round. Their casts make early free play harder, so `enemy_base_scale` may need a small cut.

## Decisions (2026-10-22, from the user)

1. **Free-play random enemies cast too.** Every unit in every mode casts.
2. **The Thief's gold stays, kept small.** Only when the Thief itself lands the killing blow with Pickpocket: 1 gold per kill, the same at every star level, with no limit on how much it can earn in a round.
3. **Summons don't count for traits.** No traits, no items.
4. **Charm stays**, with a clear "hexed" look (below), so it never reads as a bug.

## Charm visuals (Faerie Queen)

A charmed unit must be obvious at a glance for the whole time it is charmed:
- A **hex sigil** (a slowly turning pink-violet hexagon with a moth-wing glyph) floats above its health bar, in the same place as other status icons.
- Its **team ring turns pink-violet** (`#d98cff`), neither ally blue nor enemy ember, and its model gets a soft pink tint.
- A faint **moth-dust thread** connects it to the Faerie Queen while the charm lasts.
- **"CHARMED"** pops up when it starts and **"FREED"** when it ends; the health bar keeps its original team colour, so you can see whose unit it really is.
- With Reduce motion on, the sigil doesn't turn and the dust thread is a still line.
- In the unit inspector, the status line reads "Charmed: fighting for the other side (2.1 s)".
- All of this is visual only: the charm itself is ticked in combat like any other crowd control, and nothing reads the visuals back.

## Chunk 1 as built (2026-10-23)

- **Units casting:** Cleric, Archer, Knight, Militia, Acolyte, Apprentice, Skeleton, Imp, Sprite, Firebrand, Frostling, Miner, Initiate; Guardian, Bard, Alchemist, Ghoul, Sparkcaller, Frost Archer, Ironbeard, Monk, Cultist; Mage, Pyromancer, Ice Mage, Dryad, Skald, Shadowfist, Sunmonk, Winter Knight; Berserker, Hunter, Lich, Frost Giant, Dwarf Gunner, Archmage, Herald, Hellknight; Dragon, Titan.
- **Mechanics in `unit.gd`:** stun, silence, blind, taunt, cast lock, timed buffs (`add_buff`, `buff_total`: as, dmg, dr, vamp, regen), ability shields that run out (`add_timed_shield`), `heal`, queued hits (`queue_action`), the Monk's stunning next attack. Burn, chill and curse take a duration.
- **Choices made while building:**
  - A stunned unit finishes the step it is on, then stands still.
  - Ability damage-reduction buffs (Shell Up and the rest) apply after the synergy and item reduction and its 60% cap, so they still help a unit that is already at the cap.
  - Burn from abilities is 3% of max HP per second (the Pyromancer's 6% for 4 s). The text says so.
  - Bards' and Skalds' buffs don't stack with a second cast of the same ability; it refreshes instead.
- **UI:** the cast popup shows the ability's name. The unit inspector has an ABILITY line and the text at the unit's star. Shop cards and planner tiles list the ability with all three stars in their tooltip. A tall inspector (an ability, three items and resonances) can reach the HP standings at 648 px, so the standings fade out while it covers them. The duplicate "Cost" line left the inspector's stats (the header already shows the cost).
- **Balance so far:** the ghosts' balance hash includes `Abilities.DEFS`, so older ghosts play as "older balance". Chapter 1's boss level (a 2-star Dragon with two Mages) got much harder, so its `enemy_stat_mult` went from 1.46 to 1.1. The bot then completes about 40-50% of chapter 1 runs (was 58% before abilities); chapters 2 and 3 were 4/12 and 5/12 with the old values. The full retune waits for the other chunks (chunk 5).

## Chunk 2 as built (2026-10-23)

- **Units casting:** Scout, Nightblade, Assassin, Warlord, Nightstalker, Seraph.
- **Mechanics in `unit.gd`:**
  - `leap_to(tile, secs)`: the tile is claimed at once, and the model flies there over 0.25 s (the Warlord's charge takes 0.1 s per hex), stepped by the combat tick.
  - `untargetable_left`: the unit can't be picked by attacks (`Board.nearest_enemy`) or single-target abilities (`Abilities.targets`). Areas still hit it.
  - Empowered attacks (`empower_hits`, `empower_dmg`, `empower_crit`, `empower_after_stealth`).
- **Choices made while building:**
  - Landing spots are open, unlocked hexes. The Nightblade lands on the side nearest itself, the Assassin on the far side ("behind"). If no enemy on its list has an open hex beside it, it strikes its own target where it stands.
  - The Scout only leaps if a hex within 2 is farther from the nearest enemy than where it stands.
  - The Warlord charges towards the farthest enemy, not its target (see its entry). Enemies within 1 hex of any hex of its path, its starting hex included, are hit.
  - A vanished unit's attackers drop it and pick another target. If every enemy has vanished, they wait.
