# board_themes.gd
class_name BoardThemes

# The 10 board themes: voxel textures for the board, bench and sell hexes (drawn by
# tools/make_tile_textures.gd into res://textures/tiles/<id>/) and a backdrop colour. Each campaign
# level names its theme (CampaignLevel.theme), so the board follows the chapter's story: the
# Borderlands go from meadow to forest to the dragon's mountain, the Ashen Frontier from burnt
# fields to the volcano, the Shattered Sky from a starfall cave to the storm citadel. Free play and
# async PvP pick one from the run seed (for_run).

const ORDER: Array[StringName] = [&"castle", &"grasslands", &"forest", &"mountains", &"ashlands", &"scorched_road", &"volcano", &"crystal_cave", &"sky_bridge", &"storm_citadel"]

const THEMES := {
	&"castle": {"name": "Castle Courtyard", "backdrop": "23232b", "where": "the tutorial (the training yard)"},
	&"grasslands": {"name": "Borderland Meadows", "backdrop": "1d2b1e", "where": "Chapter 1, First Blood"},
	&"forest": {"name": "Shadowed Wood", "backdrop": "111b13", "where": "Chapter 1, Shadows in the Wood"},
	&"mountains": {"name": "Dragon's Roost", "backdrop": "262c38", "where": "Chapter 1, The Dragon's Roost"},
	&"ashlands": {"name": "Burnt Fields", "backdrop": "221d1a", "where": "Chapter 2, Smoke on the Horizon"},
	&"scorched_road": {"name": "The Burning Road", "backdrop": "2e2016", "where": "Chapter 2, The Burning Road"},
	&"volcano": {"name": "Throne of Cinders", "backdrop": "1c0f0d", "where": "Chapter 2, Throne of Cinders"},
	&"crystal_cave": {"name": "Starfall Caverns", "backdrop": "120f1c", "where": "Chapter 3, Fallen Stars"},
	&"sky_bridge": {"name": "Sundered Bridge", "backdrop": "4d6a8c", "where": "Chapter 3, The Sundered Bridge"},
	&"storm_citadel": {"name": "Storm Citadel", "backdrop": "161b26", "where": "Chapter 3, The Sky Tyrant"},
}

const DIR := "res://textures/tiles/%s/"
const BOARD_VARIANTS := 3

static func has(id: StringName) -> bool:
	return THEMES.has(id)

# The theme for a run: the level's own, else one picked from the run seed (free play, async PvP).
static func for_run(level: CampaignLevel, seed: int) -> StringName:
	if level != null and has(level.theme):
		return level.theme
	return ORDER[absi(seed) % ORDER.size()]

static func texture_path(id: StringName, part: String) -> String:
	return (DIR % id) + part + ".png"

static func backdrop(id: StringName) -> Color:
	return Color(THEMES[id].backdrop) if has(id) else Color(0.3, 0.3, 0.3)
