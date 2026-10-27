# board_themes.gd
class_name BoardThemes

# The board's biomes (docs/hex-tile-design-plan.md): each is a set of voxel hex tiles baked by
# tools/make_voxel_tiles.gd from VoxelTiles.BIOMES (plain base tiles for the playable board, bench, sell
# hex, and decor variants and trees for the background ring) plus a backdrop colour. Each campaign level
# names its biome (CampaignLevel.theme); free play, async PvP and lobbies use the player's arena (picked on
# the main menu, SaveGame.arena) or one from the run seed (for_run). In PvP the far half wears the
# opponent's arena and the two blend across the middle (Board.apply_theme's `foe`).
# Floating Islands from the plan isn't built (it needs extra code for the perspective).

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

# The biome for a run: a campaign level always uses its own (the arena pick never touches the campaign
# or the tutorial); otherwise `pick` (the player's arena, picked()) if it is a biome, else one from the seed.
static func for_run(level: CampaignLevel, seed: int, pick: StringName = &"") -> StringName:
	if level != null and has(level.theme):
		return level.theme
	if level == null and has(pick):
		return pick
	return ORDER[absi(seed) % ORDER.size()]

# The arena the player picked on the main menu (SaveGame.arena), or &"" for a random one.
static func picked() -> StringName:
	var id := StringName(SaveGame.arena())
	return id if has(id) else &""

# A lobby seat's arena: its pick, else one from the game seed and the seat (the server and every client
# work it out the same way, so everyone sees the same biome on that player's side).
static func for_seat(pick: StringName, seed: int, seat: int) -> StringName:
	return pick if has(pick) else ORDER[absi(hash([seed, seat])) % ORDER.size()]

static func backdrop(id: StringName) -> Color:
	return Color(VoxelTiles.BIOMES[String(id)].backdrop) if has(id) else Color(0.3, 0.3, 0.3)

# Each biome's lighting (apply_look): the sun's colour, strength and direction (pitch down, yaw round from
# the camera's side), the ambient colour and strength, the haze the far ground fades into, and how
# strongly glowing parts bloom. Visual only.
const LIGHT := {
	&"forest": {"sun": "fff4e0", "sun_e": 0.48, "pitch": -52.0, "yaw": 28.0, "amb": "b4c2bc", "amb_e": 0.32, "fog": "5a7464", "fog_d": 0.4, "glow": 0.6},
	&"autumn": {"sun": "ffe2b8", "sun_e": 0.48, "pitch": -40.0, "yaw": 40.0, "amb": "c8b4a0", "amb_e": 0.32, "fog": "7a5236", "fog_d": 0.4, "glow": 0.6},
	&"snow": {"sun": "eef3ff", "sun_e": 0.40, "pitch": -50.0, "yaw": 25.0, "amb": "b8c6d8", "amb_e": 0.18, "fog": "9aaabf", "fog_d": 0.4, "glow": 0.5},
	&"swamp": {"sun": "eaeed2", "sun_e": 0.42, "pitch": -55.0, "yaw": 30.0, "amb": "a4ae96", "amb_e": 0.34, "fog": "3c4632", "fog_d": 0.55, "glow": 0.8},
	&"volcano": {"sun": "ffc8a0", "sun_e": 0.48, "pitch": -45.0, "yaw": 35.0, "amb": "b08070", "amb_e": 0.37, "fog": "2e120c", "fog_d": 0.5, "glow": 1.0},
	&"cave": {"sun": "dde2f5", "sun_e": 0.45, "pitch": -65.0, "yaw": 20.0, "amb": "8a8ea8", "amb_e": 0.37, "fog": "0c0b12", "fog_d": 0.6, "glow": 1.0},
	&"mushroom": {"sun": "ffeedc", "sun_e": 0.45, "pitch": -50.0, "yaw": 30.0, "amb": "bca89e", "amb_e": 0.32, "fog": "4a2c20", "fog_d": 0.45, "glow": 0.7},
	&"mushroom_cave": {"sun": "d6d2f2", "sun_e": 0.42, "pitch": -62.0, "yaw": 25.0, "amb": "8c84aa", "amb_e": 0.37, "fog": "100c1a", "fog_d": 0.6, "glow": 1.1},
	&"jungle": {"sun": "f6ffe6", "sun_e": 0.45, "pitch": -58.0, "yaw": 30.0, "amb": "a6b8a2", "amb_e": 0.34, "fog": "2e4430", "fog_d": 0.5, "glow": 0.7},
	&"desert": {"sun": "fff3dc", "sun_e": 0.48, "pitch": -60.0, "yaw": 30.0, "amb": "d0c2a8", "amb_e": 0.28, "fog": "b49668", "fog_d": 0.4, "glow": 0.5},
	&"salt_flats": {"sun": "f6f6fc", "sun_e": 0.40, "pitch": -58.0, "yaw": 25.0, "amb": "c0c4cc", "amb_e": 0.18, "fog": "a8acb6", "fog_d": 0.4, "glow": 0.5},
	&"parasitic": {"sun": "ffe0dc", "sun_e": 0.42, "pitch": -50.0, "yaw": 30.0, "amb": "b08a92", "amb_e": 0.34, "fog": "2e0c16", "fog_d": 0.5, "glow": 1.0},
}

# Lights the run in a biome: the sun, the ambient light, the haze and the glow. With Settings.post_fx
# off (Glow & fog, off in the Low preset) the glow and haze are switched off; the light still changes.
# With `other` (the far half's biome, when the two players' arenas differ) the light is mixed `mix` of
# the way towards it, so one sun and one haze suit both halves.
static func apply_look(id: StringName, env: Environment, sun: DirectionalLight3D, other: StringName = &"", mix := 0.0) -> void:
	var l: Dictionary = LIGHT.get(id, LIGHT[DEFAULT])
	if mix > 0.0 and other != id and LIGHT.has(other):
		l = _blend_light(l, LIGHT[other], mix)
	if sun != null:
		sun.light_color = Color(l.sun)
		sun.light_energy = l.sun_e
		sun.rotation_degrees = Vector3(l.pitch, l.yaw, 0.0)
	if env == null:
		return
	env.ambient_light_color = Color(l.amb)
	env.ambient_light_energy = l.amb_e
	env.fog_light_color = Color(l.fog)
	env.fog_density = l.fog_d
	env.glow_intensity = l.glow
	env.glow_enabled = Settings.post_fx
	env.fog_enabled = Settings.post_fx

static func _blend_light(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		if a[k] is String:
			out[k] = Color(a[k]).lerp(Color(b[k]), t)   # apply_look's Color() takes a Color as well
		else:
			out[k] = lerpf(float(a[k]), float(b[k]), t)
	return out

# The clear colour between two biomes (mostly hidden by the scenery).
static func backdrop_between(id: StringName, other: StringName, mix: float) -> Color:
	return backdrop(id).lerp(backdrop(other), mix) if has(other) else backdrop(id)

# How much the playable board is brightened over its biome's own ground colours, so open hexes stand
# out from the scenery and the sunken locked hexes even in the darkest biomes (volcano, the caves):
# ground darker than BOARD_LUMA is lifted towards it, at most BOARD_LIFT_MAX. 1.0 = left as it is.
const BOARD_LUMA := 0.34
const BOARD_LIFT_MAX := 2.0
static func board_lift(id: StringName) -> float:
	if not has(id):
		return 1.0
	var tops: Array = VoxelTiles.BIOMES[String(id)].top
	var l := 0.0
	for h in tops:
		l += Color(str(h)).get_luminance()
	l /= maxf(tops.size(), 1)
	return clampf(BOARD_LUMA / maxf(l, 0.01), 1.0, BOARD_LIFT_MAX)

# The colour of the studs along the line between the two halves (Board._build_border): the biome's
# accent ("ring", the colour of its standing-stone and shrine trim), or its crystal colour where that
# accent is too dark to see on the ground.
static func border_colour(id: StringName) -> Color:
	if not has(id):
		return Color("c8a26a")
	var c: Dictionary = VoxelTiles.BIOMES[String(id)].c
	var accent := Color(str(c.get("ring", "c8a26a")))
	if accent.get_luminance() < 0.35 and c.has("crystal"):
		accent = Color(str(c.crystal[0]))
	return accent

# The solid voxel material brightened by board_lift (null when the biome needs none). Cached per biome.
static var _lifted := {}
static func board_material(id: StringName) -> Material:
	var lift := board_lift(id)
	if lift <= 1.001:
		return null
	if not _lifted.has(id):
		var m := (VoxelTiles.SOLID as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = Color(lift, lift, lift)
		_lifted[id] = m
	return _lifted[id]

# A baked tile of a biome (VoxelTiles.PARTS: base_1..3, bench, sell, flowers, stone, roots, standing,
# shrine, tree_1, tree_2).
static func tile(id: StringName, part: String) -> Mesh:
	return VoxelTiles.mesh(String(id), part)
