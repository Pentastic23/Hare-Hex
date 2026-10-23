# Menagerie: unit models and HUD design (not integrated yet)

Assets made in a separate chat for AZTactics, dropped here as files only. Nothing in the game
uses them yet, and no existing file was changed. **All 65 units now have a model** (65 units x 4
star levels = 260 models). This folder has a `.gdignore`, so Godot ignores
it completely (no imports, no .import files) until you are ready.

**To integrate:** move `models/glb/` somewhere Godot sees it (for example `res://models/units/`),
or delete `menagerie/.gdignore`. Then follow the notes below. The HUD is a design spec in
`hud/HUD_SPEC.md`.

## Contents

```
menagerie/
  README.md            this file
  roster_all_65.png    every unit at 1 star, in roster order
  roster_tiers.png     the first 10 units at 1-4 stars
  roster_tiers_new55.png  the other 55 units at 1-4 stars
  models/glb/          260 rigged, animated glTF models: <unit>_<n>star.glb
  models/vox/          the same models as MagicaVoxel files (static, for editing)
  models/previews/     a 3/4-view PNG of each (shop or roster portraits)
  hud/HUD_SPEC.md      timer, round tracker and HP standings design to build
  hud/hud_*.png        reference renders of that HUD
  hud/DOCKS_SPEC.md    left box (synergies / items) and right box (damage / planner / menu) design
  hud/items/           64 px voxel icons for the 6 items, named by item id
  hud/portraits/       96 px portraits of all 65 units
  source/              the Python generator (build.py) and units.json metadata
```

## The models

| UnitData (display_name) | File base | Animal |
|---|---|---|
| Knight | knight_lion | Lion |
| Archer | archer_fox | Fox |
| Cleric | cleric_sheep | Sheep |
| Guardian | guardian_tortoise | Tortoise |
| Thief | thief_raccoon | Raccoon |
| Mage | mage_owl | Owl |
| Assassin | assassin_cat | Black cat |
| Hunter | hunter_wolf | Wolf |
| Berserker | berserker_bear | Bear |
| Dragon | dragon | Red dragon |

The other 55 units (`tres/units/*.tres`):

| UnitData (display_name) | File base | Animal |
|---|---|---|
| Militia | militia_badger | Badger |
| Scout | scout_hare | Hare |
| Acolyte | acolyte_mouse | Mouse |
| Apprentice | apprentice_frog | Frog |
| Skeleton | skeleton_rat | Skeletal rat |
| Imp | imp_bat | Bat |
| Sprite | sprite_squirrel | Fairy squirrel |
| Firebrand | firebrand_redpanda | Red panda |
| Frostling | frostling_penguin | Penguin |
| Miner | miner_mole | Mole |
| Initiate | initiate_monkey | Monkey |
| Bard | bard_robin | Robin |
| Alchemist | alchemist_beaver | Beaver |
| Necromancer | necromancer_raven | Raven |
| Ghoul | ghoul_hyena | Undead hyena |
| Sparkcaller | sparkcaller_salamander | Fire salamander |
| Frost Archer | frostarcher_lynx | Snow lynx |
| Ironbeard | ironbeard_goat | Mountain goat |
| Druid | druid_stag | Stag |
| Monk | monk_panda | Panda |
| Cultist | cultist_ferret | Ferret |
| Nightblade | nightblade_panther | Black panther |
| Pyromancer | pyromancer_meerkat | Meerkat |
| Paladin | paladin_retriever | Golden retriever |
| Ice Mage | icemage_walrus | Walrus |
| Dryad | dryad_koala | Koala |
| Minstrel | minstrel_otter | Otter |
| Skald | skald_boar | Boar |
| Plague Doctor | plaguedoctor_vulture | Vulture |
| Runesmith | runesmith_armadillo | Armadillo |
| Shadowfist | shadowfist_skunk | Skunk |
| Sunmonk | sunmonk_tiger | Tiger |
| Demonologist | demonologist_lemur | Lemur |
| Winter Knight | winterknight_polarbear | Polar bear |
| Warlord | warlord_rhino | Rhino |
| Duelist | duelist_rooster | Rooster |
| Nightstalker | nightstalker_coyote | Coyote |
| Lich | lich_crocodile | Crocodile |
| Magma Guard | magmaguard_hippo | Hippo |
| Frost Giant | frostgiant_mammoth | Mammoth |
| Dwarf Gunner | dwarfgunner_hedgehog | Hedgehog |
| Archmage | archmage_peacock | Peacock |
| Herald | herald_eagle | Eagle |
| Hellknight | hellknight_bull | Bull |
| Beastmaster | beastmaster_gorilla | Gorilla |
| Zen Master | zenmaster_crane | Crane |
| Seraph | seraph_pegasus | Pegasus |
| Deathlord | deathlord_jackal | Jackal |
| Titan | titan_elephant | Elephant |
| Phoenix | phoenix_firebird | Phoenix |
| Archdemon | archdemon_ram | Demon ram |
| Frost Queen | frostqueen_ermine | Ermine |
| Faerie Queen | faeriequeen_moth | Luna moth |
| Reaper | reaper_mantis | Mantis |
| Treant | treant_moose | Moose |

Every model uses the same skeleton, clip names and scale. Each unit's gear matches its class (for
example, Protectors carry a shield, Rangers a bow, Casters a staff, Monks fight bare-handed) and its
colours match its origin. At 3 stars, the topper depends on the origin: gold crown (Order, Dwarven,
Ember), dark iron crown (Infernal), bone crown (Undead), ice spikes (Frost), and circlets for Wild,
Fey, Shadow and Arcane.

**Tiers:** `_1star`, `_2star` and `_3star` match the game's star levels (better gear and colours at
each). `_4star` is a secret "astral" form: a star-flecked spirit with a halo and orbiting motes
on their own `aura` bone. The game caps stars at 3 (`Unit.set_star` clamps), so 4-star needs a
design decision (a reward, a cosmetic unlock, a 4th merge).

**Format:**
- glTF binary. Meters, Y up, origin at the feet, facing **+Z**.
- About 1.4-1.8 m tall at 5 cm per voxel; a hex tile is 0.95 m radius.
- All star files are the **same scale** here, because `Unit.STAR_SIZE` already scales ModelHolder
  by star (1.0 / 1.2 / 1.45). Don't scale them again.
- Vertex colours only, no textures. The material must use vertex colour as albedo
  (`vertex_color_use_as_albedo`); Godot's importer normally sets this, so check one model.
- Glowing parts (enchanted blades, crystals, 3-4 star eyes, halos) are separate surfaces with
  emissive materials named `glow_<hex>`. They only bloom if the WorldEnvironment has glow on.
- Rigid skinning: each voxel follows exactly one bone.

**Skeleton** (bipeds; one rig for all nine):

```
root
├─ body ─┬─ head
│        ├─ arm_r ── weapon_r
│        ├─ arm_l ── weapon_l
│        └─ tail
├─ leg_r
└─ leg_l
```

The dragon uses `root body head tail wing_r wing_l leg_fr leg_fl leg_br leg_bl`. 4-star models
add `aura` under root. `_r` is the character's own right.

**Animation clips** (every model, same names, inside an AnimationPlayer after import):

| Clip | Length | Should loop | Notes |
|---|---|---|---|
| idle | 1.6 s | yes | |
| walk | 0.8 s | yes | |
| attack | 0.9 s | no | speed it up when `attack_interval()` is shorter |
| skill | 1.3-1.4 s | no | for the ability cast (mana full) |
| hit | 0.45 s | no | flinch; rate-limit it |
| death | 1.2 s | no | ends lying down |
| victory | 1.2-1.4 s | yes | after a won fight |

glTF has no loop flag, so set `Animation.loop_mode` for idle / walk / victory after import (or in
the import settings).

Impact frames, for damage numbers or projectiles later:

| Unit | Attack hit | Skill hit |
|---|---|---|
| Knight | 0.42 s | sweeps 0.15-0.75 s |
| Archer | release 0.60 s | arrows 0.37, 0.65, 0.93 s |
| Cleric | 0.50 s | heal pulse 0.35-0.95 s |
| Guardian | shove 0.18 s, mace 0.42 s | counter 1.15 s |
| Thief | 0.29 s | 0.85 s |
| Mage | 0.50 s | 0.85 s |
| Assassin | 0.29 and 0.46 s | 0.50 and 0.65 s |
| Hunter | 0.40 s | 0.70 s |
| Berserker | 0.42 s | 1.00 s |
| Dragon | 0.40 s | breath 0.50-1.05 s |

## Things in the current code that affect integration

Found by reading the code; nothing was changed.

- **`UnitData.model`** (PackedScene) already exists, and `Unit.setup()` instances it under
  `ModelHolder`. A wrapper scene per unit that swaps the glb by star fits there.
- **The capsule placeholder** (`ModelHolder/MeshInstance3D` in unit.tscn) and the letter label
  (`Unit.letter_label`, at capsule height) will still show unless hidden.
- **Enemies are painted solid red:** `Unit.setup()` sets a red `material_override` on every
  MeshInstance3D in ModelHolder when `team == 1`, which would hide the models' colours. Use another
  team marker instead (for example a coloured ring at the feet; the HUD spec uses blue
  `#6cc4ff` for you and ember `#ff8a4c` for enemies).
- **Facing:** `Unit._face_point()` uses `look_at`, which points a node's **-Z** at the target. The
  models face **+Z**, so rotate the model 180 degrees on Y inside its wrapper.
- **Death:** `Unit.take_damage()` sets `visible = false` the instant a unit dies, so a death
  animation never shows. Either delay hiding (visual only, so combat stays deterministic) or play
  the death on a stand-in copy.
- **Merges** change `Unit.star` through `set_star()`; the wrapper needs to notice and load the next
  star's model.
- **Animation state** can be read from the Unit without touching combat logic: `moving` (walk),
  `cooldown` jumping up (an attack just happened), `mana` dropping from full to 0 (skill cast),
  `damage_taken` rising (hit), `dead`, and `Events.combat_ended` (victory). Keep animation purely
  visual so combat stays deterministic (CLAUDE.md, Combat).
- **Height:** `Unit.BAR_HEIGHT` is 2.4. Models are 1.4-1.8 m tall before star scaling, so the
  bars may want lowering to sit just above the heads.
- Run `tools/combat_checks` after integrating, to confirm nothing touched combat.

## Regenerating

The generator in `source/` rebuilds everything (Python 3 with numpy and Pillow):

    UNIFORM_SCALE=1 python3 build.py out        # the first 10 (units.py)
    UNIFORM_SCALE=1 python3 build_new.py out    # the other 55 (units2.py, built from the parts in kit.py)

`UNIFORM_SCALE=1` gives these same-size files. Without it, each star level is baked progressively
bigger (1.0 / 1.12 / 1.24 / 1.32), for engines that don't scale by star.
`units.py` holds the models and tier upgrades, and `anims.py` holds the clips.
