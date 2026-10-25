# Hex Tile Design Document

## 1. Overview & Aesthetic Direction
This document outlines the asset specifications, structural dimensions, and architectural variations for the game's hexagonal grid system. The visual style utilizes a **3D isometric voxel art aesthetic** with low-poly geometric definition, crisp pixel-art textures, and stylized environments. 

The design is optimized for tactical positioning, map generation, and phase-based auto-battler/strategy layouts.


### Visual Layout References
* **Isometric View:** Match the current project view
* **Top View:** Pure regular hexagon silhouette for accurate hitboxes and selection casting.
* **Side View:** Standard 4-voxel layer depth block.


## 2. Hex Tile Variants (Game Scale)
Individual tiles use a distinct modular asset scheme to identify terrain properties, cover mechanics, or map objectives.
** Do not implement Gameplay Role on tiles, these are a design idea**

1. **Plain Grass**
   * *Description:* Unobstructed green meadow surface.
   * *Gameplay Role:* Standard walkable tile; no movement or combat penalties.
2. **Flowers**
   * *Description:* Grass tile populated with low-profile white daisy clusters.
   * *Gameplay Role:* Aesthetic cosmetic variant; identical properties to Plain Grass.
3. **Mossy Stone**
   * *Description:* Imbedded ancient boulders covered in light vegetation.
   * *Gameplay Role:* Light cover/obstacle; restricts certain unit types or provides minor defensive bonuses.
4. **Roots**
   * *Description:* A large cut tree stump exposing tangled, mossy roots.
   * *Gameplay Role:* Low cover; blocks straight-line movement but permits ranged line-of-sight.
5. **Standing Stone**
   * *Description:* A tall, prominent monolith stone pillar.
   * *Gameplay Role:* Line-of-sight blocker; complete structural obstacle that blocks both movement and ranged projectiles.
6. **Shrine**
   * *Description:* A finished stone plinth holding an illuminated, glowing blue energy crystal.
   * *Gameplay Role:* Interactive node / Capture point; grants localized stat buffs or mana generation to the occupying unit.

**These Variants will need to be made for each biome theme**

## 3. Biome Themes
The environment shifts dynamically across map territories using standardized asset conversions. The same underlying tile indexes translate smoothly across the following biome schemes:

* **Forest (Default):** Vibrant green grass over deep brown dirt layers with white flowers.
* **Autumn:** Ochre and orange terrain, weathered beige rocky details, and rich amber-red foliage.
* **Snow:** Frost-covered white terrain over cool, icy blue-tinted stone bases with pine trees.
* **Swamp:** Dark, waterlogged olive-green soil with exposed wooden posts, mossy vines, and pooling surface water.
* **Volcano** Hot, lava pools, Magama lined stone, Piles of ash
* **Cave** Dark, stone viariants, treasure piles/chests, piles of bone
* **Mushroom** Mushroom trees, small mushrooms, red and brown tiles, dirty pooling surface water
* **Mushroom Cave** A mix of Mushroom and Cave
* **Jungle** Muted green tiles, trees with alot of vines, dense foilage
* **Desert** Sandy, yellows and light oranges, Dunes, Dead bones, Mirage hexes (tile variants of forest)
* **Salt Flats** Muted whites, Salt piles, Dead vulture bones, Salty water, Shimmering flats from wow
* **Floating Islands** Isolated landmasses suspended in the sky—ranging from natural scenic chunks to carved-out floating cities. (hard to do as it would require additonal coding and perspective challanges)
* **Parasitic** Organic, fleshy landscapes acting as a collective hive-mind or giant decaying entity, blood rivers, blood structures
**Biome themes will develop as the campain is flushed out, they will also be avalible as PVP board skins**

#### 4.Design preview
Design preview is in the docs file of the project.
Current playable area for units should only be base tiles and we will set up a generating background with the tile viariants
This is to keep the playable area readable while seting a backdrop scene to make the game feel full

#### 5. As built (2026-10-25)
* **Tiles:** real voxel meshes, 16 voxels across and 4 deep, the top colour dripping over the sides (`Scripts/voxel_tiles.gd`). Baked once into `models/tiles/<biome>/` by `tools/make_voxel_tiles.tscn`; `tools/voxel_gallery.tscn` renders every biome's parts in rows.
* **Biomes built:** Forest, Autumn, Snow, Swamp, Volcano, Cave, Mushroom, Mushroom Cave, Jungle, Desert, Salt Flats, Parasitic (Floating Islands left out, as section 3 suggests).
* **Parts per biome:**
  * three plain base tiles: the only ones units stand on
  * bench (the biome's ground inside a raised frame) and sell hex (a raised gold coin); the enemy has a matching bench beyond the far edge of the board
  * the five decor slots: flowers, mossy stone, roots, standing stone, shrine
  * two trees
* **Decor in each biome:** each slot becomes something that fits. Examples:
  * Autumn: fallen leaves and beige rocks
  * Snow: ice shards and snowy pines
  * Swamp: reeds, wooden posts with a pool, and a water pool in the shrine slot
  * Volcano: ash piles, magma stone, a lava pool, an obsidian pillar and a fire shrine
  * Cave: bones, a treasure chest, a stalagmite and crystals
  * Mushroom: small mushrooms, a dirty pool and mushroom trees
  * Jungle: ferns and vine-covered stumps, stones and trees
  * Desert: dunes, bones, a sandstone pillar, cacti, and mirage tiles (see-through forest tiles in the scenery)
  * Salt Flats: salt piles, vulture bones, a salt pool, salt spires and shimmering flats
  * Parasitic: pustules, flesh growths, a blood pool, a bone spire, an eye shrine and tendrils
* **Board:** the playable area is plain base tiles only. The rest of the camera view is filled with the biome's tiles, laid out naturally from the run seed: trees gather in groves, flowers and roots in meadows, stones in rocky patches, and the ground rises and falls a little away from the board. The scenery sits a voxel lower and a shade darker, so the board reads as a bright plateau. Locked board hexes show as darker sunken ground until they unlock. Nothing tall stands beside or in front of the board, and nothing sits under the bench.
* **Campaign:**

| Level | Biome |
|---|---|
| Tutorial | Forest |
| Chapter 1 | Forest, Jungle, Snow |
| Chapter 2 | Autumn, Desert, Volcano |
| Chapter 3 | Cave, Salt Flats, Parasitic |

  Free play, async PvP and lobbies pick any biome from the run seed (these are the PvP board skins).
* **Gameplay roles:** none implemented, as section 2 says.
