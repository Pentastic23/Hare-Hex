# board_themes.gd
class_name BoardThemes

# The board's biomes (docs/hex-tile-design-plan.md): each is a set of voxel hex tiles baked by
# tools/make_voxel_tiles.gd from VoxelTiles.BIOMES (plain base tiles for the playable board, bench, sell
# hex, and decor variants and trees for the background ring) plus a backdrop colour. Each campaign level
# names its biome (CampaignLevel.theme); free play, async PvP and lobbies pick one from the run seed
# (for_run). Floating Islands from the plan isn't built (it needs extra code for the perspective).

const ORDER: Array[StringName] = [&"forest", &"autumn", &"snow", &"swamp", &"volcano", &"cave", &"mushroom", &"mushroom_cave", &"jungle", &"desert", &"salt_flats", &"parasitic"]
const DEFAULT: StringName = &"forest"

# Where each biome is used in the campaign (the rest turn up in free play and PvP by seed).
const WHERE := {
	&"forest": "the tutorial and Chapter 1, First Blood",
	&"jungle": "Chapter 1, Shadows in the Wood",
	&"snow": "Chapter 1, The Dragon's Roost",
	&"autumn": "Chapter 2, Smoke on the Horizon",
	&"desert": "Chapter 2, The Burning Road",
	&"volcano": "Chapter 2, Throne of Cinders",
	&"cave": "Chapter 3, Fallen Stars",
	&"salt_flats": "Chapter 3, The Sundered Bridge",
	&"parasitic": "Chapter 3, The Sky Tyrant",
}

static func has(id: StringName) -> bool:
	return VoxelTiles.BIOMES.has(String(id))

static func display_name(id: StringName) -> String:
	return VoxelTiles.BIOMES[String(id)].name if has(id) else ""

# The biome for a run: the level's own, else one picked from the run seed (free play, async PvP, lobbies).
static func for_run(level: CampaignLevel, seed: int) -> StringName:
	if level != null and has(level.theme):
		return level.theme
	return ORDER[absi(seed) % ORDER.size()]

static func backdrop(id: StringName) -> Color:
	return Color(VoxelTiles.BIOMES[String(id)].backdrop) if has(id) else Color(0.3, 0.3, 0.3)

# A baked tile of a biome (VoxelTiles.PARTS: base_1..3, bench, sell, flowers, stone, roots, standing,
# shrine, tree_1, tree_2).
static func tile(id: StringName, part: String) -> Mesh:
	return VoxelTiles.mesh(String(id), part)
