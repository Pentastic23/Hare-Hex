# Menagerie: unit models and HUD design (not integrated yet)

Assets made in a separate chat for AZTactics, dropped here as files only. Nothing in the game
uses them yet, and no existing file was changed. This folder has a `.gdignore`, so Godot ignores
it completely (no imports, no .import files) until you are ready.

**To integrate:** move `models/glb/` somewhere Godot sees it (for example `res://models/units/`),
or delete `menagerie/.gdignore`. Then follow the notes below. The HUD is a design spec in
`hud/HUD_SPEC.md`.

## Contents

```
menagerie/
  README.md            this file
  roster_tiers.png     all 40 models at a glance (10 units x 1-4 stars)
  models/glb/          40 rigged, animated glTF models: <unit>_<n>star.glb
  models/vox/          the same models as MagicaVoxel files (static, for editing)
  models/previews/     a 3/4-view PNG of each (shop or roster portraits)
  hud/HUD_SPEC.md      timer, round tracker and HP standings design to build
  hud/hud_*.png        reference renders of that HUD
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

These match the original 10 units in `tres/*.tres`. The other 55 units have no models yet.

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

`source/build.py` rebuilds everything (Python 3 with numpy and Pillow):

    UNIFORM_SCALE=1 python3 build.py out

`UNIFORM_SCALE=1` gives these same-size files. Without it, each star level is baked
progressively bigger (1.0 / 1.12 / 1.24 / 1.32), for engines that don't scale by star.
`units.py` holds the models and tier upgrades, and `anims.py` holds the clips.
