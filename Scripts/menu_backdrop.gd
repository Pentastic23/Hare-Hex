# menu_backdrop.gd
class_name MenuBackdrop extends Node3D

# The main menu's moving background, in the spirit of Minecraft's title screen: a camera glides over a
# strip of voxel land made from the game's own tiles, through every biome in turn, and ends at the
# volcano, where a giant dragon roars and breathes fire; then the picture fades out and the loop (about
# 40 s, set by the glide speed) starts again. Each biome has a landmark: a hill with its shrine, a big tree and a standing stone behind,
# and two of its units in front, one of which casts as the camera passes. Behind the near land, hills
# climb in terraces to fill the far view and the sky (double-size tiles on a double-size grid: they look
# the same at that distance for a quarter of the tiles); every raised hex stands on a plain hex column
# in its biome's earth colour, so the steps never show a gap. The light follows the camera: each biome's
# sun, ambient light and haze (BoardThemes.LIGHT), blended across the borders.
#
# It lives in the menu's own world (its camera, light and environment), is built a few chunks a frame
# once the menu is on screen (the menu's dark background stays up until it is ready, then fades: that
# is `curtain`), and loads the unit models in the background (Preload). One MultiMesh per kind of tile
# per chunk, so chunks out of view aren't drawn. Visual only, with its own randomness (per-hex hashes),
# never the game's. Reduce motion: a still view of the first landmark. Off in headless runs (menu_checks
# builds one itself).

static var enabled := DisplayServer.get_name() != "headless"

# The journey, left to right; it ends at the volcano and its dragon.
const BIOMES: Array[StringName] = [&"forest", &"jungle", &"swamp", &"mushroom", &"mushroom_cave", &"cave", &"parasitic", &"autumn", &"snow", &"salt_flats", &"desert", &"volcano"]
# The two units on each biome's landmark (UnitData file names); the volcano has the dragon instead.
const LANDMARK_UNITS := {
	&"forest": ["scout", "druid"], &"jungle": ["beastmaster", "nightblade"], &"swamp": ["plague_doctor", "ghoul"],
	&"mushroom": ["sprite", "faerie_queen"], &"mushroom_cave": ["shadowfist", "nightstalker"], &"cave": ["miner", "ironbeard"],
	&"parasitic": ["cultist", "lich"], &"autumn": ["knight", "bard"], &"snow": ["frost_giant", "frostling"],
	&"salt_flats": ["archmage", "sparkcaller"], &"desert": ["sunmonk", "dwarf_gunner"],
}
const COL_W := 1.7320508      # one hex column (the board's hex grid, Board.grid_to_world)
const SEG_COLS := 6           # columns per biome
const SEG_W := COL_W * SEG_COLS
const LAST_COLS := 16          # the volcano is wider: the whole dragon shot stands in it
const DRAGON_COL := 10         # the dragon's hill, columns into the volcano
const MARGIN := 24            # columns of land past both ends (wide windows see far to the sides)
const ROW_FAR := -12          # the near land's last row; its back rows start to climb
const CLIMB_ROW := -8         # behind this row the near land rises, 2 voxels a row
const FAR_Z := -19.5          # where the far hills begin (just behind the near land)
const FAR_ROWS := 20          # rows of double-size hexes, 3 units apart
const FAR_MARGIN := 45.0      # world units of far hills past both ends (they are seen widest)
const FAR_SLOPE := 0.34       # how fast the far hills climb, per unit back
const ROW_NEAR := 5
const CHUNK_COLS := 4
const CHUNKS_PER_FRAME := 3
const LANDMARK_ROWS := [-4, -6]   # landmarks alternate nearer and further back
const DRAGON_ROW := -8
const UNIT_SCALE := 1.8
const DRAGON_SCALE := 5.0
const DRAGON_SIDE := 9.0      # the camera stops this far left of the dragon, so it stands right of the menu
const TALL := ["standing", "tree_1", "tree_2"]
const SKY_LIFT := 0.2         # the haze (and the sky, which is the haze) a little lighter than in a run: a brighter far view
const LIGHT_LIFT := 1.15      # and the sun and ambient a little stronger, for the lower, longer view

# The camera's pace; the timeline follows from it (_plan_time).
const SPEED := 3.6            # world units a second while gliding (about 3 s a biome)
const DECEL := 4.5            # seconds to slow to a stop before the dragon
const ROAR_AFTER := 0.8       # the dragon roars this long after the camera stops
const HOLD := 5.5             # and the shot holds this long after the roar, fading out at the end
const FADE_IN := 0.8
const STILL_TIME := 0.5       # Reduce motion: the frame it holds

var time := 0.0
var loop_len := 40.0          # seconds in one loop; it, fly_end, stop, roar and fade_out are set by _plan_time
var fly_end := 30.0
var stop := 34.5
var roar := 35.3
var fade_out := 40.0
var ready_to_run := false
var curtain: CanvasItem       # the menu's dark background: covers the land until it is built, and at the loop's seam
var tiles_made := 0
var camera: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _growth := FastNoiseLite.new()
var _lift := FastNoiseLite.new()
var _edge := FastNoiseLite.new()
var _chunks: Array[int] = []
var _far_cells := {}          # chunk -> Array of far-hill hexes (Vector2i on the double-size grid)
var _prism_mat: StandardMaterial3D
static var _prism_mesh: ArrayMesh
var _landmarks: Array[Dictionary] = []   # {biome, center, radius, units: [UnitData], models: [UnitModel], cast}
var _waiting: Array = []                 # [scene path, Callable(scene)] model loads in flight
var dragon: UnitModel
var _roared := false
var _breath_left := 0.0
var _breath_step := 0.0
var _shake := 0.0
var _ember_step := 0.0
var _fx_rng := RandomNumberGenerator.new()

func _ready():
	_fx_rng.seed = 2026
	_growth.seed = 11
	_growth.frequency = 0.11
	_lift.seed = 12
	_lift.frequency = 0.07
	_edge.seed = 13
	_edge.frequency = 0.08
	var we := WorldEnvironment.new()
	_env = (load("res://tres/world_env.tres") as Environment).duplicate()
	_env.fog_enabled = true   # always: the haze is what hides the end of the world here
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false
	add_child(_sun)
	camera = Camera3D.new()
	camera.fov = 44.0
	camera.far = 160.0
	add_child(camera)
	camera.make_current()
	_plan_landmarks()
	_plan_time()
	_plan_far()
	_prism_mat = StandardMaterial3D.new()
	_prism_mat.vertex_color_use_as_albedo = true
	_prism_mat.roughness = 1.0
	_prism_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var start_x := _camera_x(0.0)
	for k in _chunk_count():
		_chunks.append(k)
	_chunks.sort_custom(func(a, b): return absf(_chunk_mid(a) - start_x) < absf(_chunk_mid(b) - start_x))   # what the first frame shows first
	_apply(0.0)

# Builds every chunk now (tests; the menu builds a few a frame).
func build_all() -> void:
	while not _chunks.is_empty():
		_build_chunk(_chunks.pop_front())
	ready_to_run = true

func _process(delta: float) -> void:
	if not _chunks.is_empty():
		for i in CHUNKS_PER_FRAME:
			if _chunks.is_empty():
				break
			_build_chunk(_chunks.pop_front())
		if _chunks.is_empty():
			ready_to_run = true
			time = 0.0
		_apply(0.0)
		return
	_poll_models()
	if Settings.reduce_motion:
		time = STILL_TIME
	else:
		time += delta
		if time >= loop_len:
			_restart()
	_effects(delta)
	_apply(time)

func _restart() -> void:
	time = fmod(time, loop_len)
	_roared = false
	_breath_left = 0.0
	for lm in _landmarks:
		lm.cast = false

# --- the land ---------------------------------------------------------------------------------------

func _col_min() -> int:
	return -MARGIN

func _col_max() -> int:
	return (BIOMES.size() - 1) * SEG_COLS + LAST_COLS + MARGIN

func _chunk_count() -> int:
	return ceili(float(_col_max() - _col_min() + 1) / CHUNK_COLS)

func _chunk_mid(k: int) -> float:
	return (_col_min() + (k + 0.5) * CHUNK_COLS) * COL_W

func _chunk_of_x(x: float) -> int:
	return clampi(floori((x / COL_W - _col_min()) / CHUNK_COLS), 0, _chunk_count() - 1)

# The far hills' hexes, sorted into the chunks in front of them (those past the ends go to the end chunks).
func _plan_far() -> void:
	var x_lo := _col_min() * COL_W - FAR_MARGIN
	var x_hi := _col_max() * COL_W + FAR_MARGIN
	for y in range(-FAR_ROWS, 0):
		for x in range(floori(x_lo / (2.0 * COL_W)), ceili(x_hi / (2.0 * COL_W)) + 1):
			var c := Vector2i(x, y)
			var k := _chunk_of_x(far_world(c).x)
			if not _far_cells.has(k):
				_far_cells[k] = []
			_far_cells[k].append(c)

# A far-hill hex on the double-size grid, at ground level.
static func far_world(c: Vector2i) -> Vector3:
	return Vector3(2.0 * COL_W * (c.x + 0.5 * (c.y & 1)), 0.0, FAR_Z + 3.0 * (c.y + 1))

static func world(c: Vector2i) -> Vector3:
	return Vector3(COL_W * (c.x + 0.5 * (c.y & 1)), 0.0, 1.5 * c.y)

# A steady random number for hex c (0-1): the same however the land is built.
static func _rand(c: Vector2i, salt: int) -> float:
	return float(hash([c.x, c.y, salt]) % 100000) / 100000.0

func _seg_center_x(i: int) -> float:
	return (i * SEG_COLS + SEG_COLS * 0.5) * COL_W

# Which biome is at x (the strip's sections, left to right; the last one runs on to the end).
static func biome_index(x: float) -> int:
	return clampi(floori(x / SEG_W), 0, BIOMES.size() - 1)

# The middle of each biome's light: blended between neighbours as the camera passes (the volcano's
# light takes over just past its border).
func _light_x(i: int) -> float:
	return _seg_center_x(i) if i < BIOMES.size() - 1 else (i + 0.5) * SEG_W

func _plan_landmarks() -> void:
	for i in BIOMES.size():
		var id := BIOMES[i]
		var lm := {"biome": i, "radius": 2, "units": [], "models": [], "cast": false}
		if id == &"volcano":
			lm.center = Vector2i(i * SEG_COLS + DRAGON_COL, DRAGON_ROW)
			lm.radius = 3
		else:
			lm.center = Vector2i(i * SEG_COLS + SEG_COLS / 2, LANDMARK_ROWS[i % 2])
			for n in LANDMARK_UNITS.get(id, []):
				var d := _unit_data(n)
				if d != null and d.has_model():
					lm.units.append(d)
		_landmarks.append(lm)

static func _unit_data(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	if not ResourceLoader.exists(p):
		p = "res://tres/%s.tres" % n
	return load(p) as UnitData if ResourceLoader.exists(p) else null

# The nearest landmark to hex c and how far it is: [index, hexes], or [-1, 99].
func _landmark_near(c: Vector2i) -> Array:
	var best := -1
	var best_d := 99
	for i in _landmarks.size():
		var d := Board.hex_distance(c, _landmarks[i].center)
		if d < best_d:
			best_d = d
			best = i
	return [best, best_d]

# The cells in front of (toward the camera) and behind a landmark's centre.
static func _front(c: Vector2i) -> Array[Vector2i]:
	return [Vector2i(c.x - 1 + (c.y & 1), c.y + 1), Vector2i(c.x + (c.y & 1), c.y + 1)]

static func _back(c: Vector2i) -> Array[Vector2i]:
	return [Vector2i(c.x - 1 + (c.y & 1), c.y - 1), Vector2i(c.x + (c.y & 1), c.y - 1)]

func _build_chunk(k: int) -> void:
	var groups := {}   # "biome|part" -> Array of Transform3D; "prism" -> Array of [Transform3D, Color]
	var c0 := _col_min() + k * CHUNK_COLS
	for x in range(c0, mini(c0 + CHUNK_COLS, _col_max() + 1)):
		for y in range(ROW_FAR, ROW_NEAR + 1):
			_place(Vector2i(x, y), groups)
	for c in _far_cells.get(k, []):
		_place_far(c, groups)
	for key in groups:
		if key == "prism":
			_add_prisms(groups[key])
			continue
		var bits := (key as String).split("|")
		var mesh := BoardThemes.tile(StringName(bits[0]), bits[1])
		if mesh == null:
			continue
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		tiles_made += list.size()

# One hex of land: which biome (by where it is, the borders frayed by noise; a landmark's hill is all its
# own biome), what grows on it, and how high it stands (gentle noise hills, rising a little toward the
# horizon, and the landmarks' hills).
func _place(c: Vector2i, groups: Dictionary) -> void:
	var pos := world(c)
	var near := _landmark_near(c)
	var lm: Dictionary = _landmarks[near[0]]
	var d: int = near[1]
	var b: int = lm.biome if d <= lm.radius + 1 else biome_index(pos.x + _edge.get_noise_2d(c.x, c.y) * 6.0 + (_rand(c, 5) - 0.5) * 2.5)
	var biome := BIOMES[b]
	var h := roundi(_lift.get_noise_2d(c.x, c.y) * 2.5) + maxi(0, CLIMB_ROW - c.y) * 2
	var size := 1.0
	var part := ""
	if d <= lm.radius:
		h = maxi(h, 0) + (lm.radius + 1 - d) * 3
		part = _landmark_part(c, lm, d)
		if part in ["tree_2", "standing"] and d == 1:
			size = 1.7   # the landmark's big tree and stone, seen from afar
		elif part == "shrine":
			size = 1.25
	else:
		part = _pick_part(c)
	var spin := Basis(Vector3.UP, floori(_rand(c, 2) * 6.0) * PI / 3.0).scaled(Vector3.ONE * size)
	var key := "%s|%s" % [biome, part]
	if not groups.has(key):
		groups[key] = []
	groups[key].append(Transform3D(spin, pos + Vector3(0, h * VoxelTiles.V, 0)))
	if h >= 3:
		_prism(groups, pos, (h - 3) * VoxelTiles.V, size, b)
	if d == 1 and c in _front(lm.center):
		lm["stand_%d" % _front(lm.center).find(c)] = pos + Vector3(0, h * VoxelTiles.V, 0)

# One far-hill hex: a double-size tile, climbing with the distance (and rolling with noise), on its column.
func _place_far(c: Vector2i, groups: Dictionary) -> void:
	var pos := far_world(c)
	var b := biome_index(pos.x + _edge.get_noise_2d(c.x * 2, c.y * 2 - 40) * 8.0)
	var back := FAR_Z - pos.z
	var top := 0.9 + back * FAR_SLOPE + (_lift.get_noise_2d(c.x * 2 + 300, c.y * 2) + 0.6) * 2.4
	top = snappedf(maxf(top, 0.6), 2.0 * VoxelTiles.V)
	var cell := Vector2i(c.x + 5000, c.y)   # its own randomness, apart from the near hexes
	var part := _pick_part(cell)
	var spin := Basis(Vector3.UP, floori(_rand(cell, 2) * 6.0) * PI / 3.0).scaled(Vector3.ONE * 2.0)
	var key := "%s|%s" % [BIOMES[b], part]
	if not groups.has(key):
		groups[key] = []
	groups[key].append(Transform3D(spin, pos + Vector3(0, top, 0)))
	_prism(groups, pos, top - 6.0 * VoxelTiles.V, 2.0, b)

# A plain hex column from just under a raised tile's top down below the ground, in the biome's earth colour.
func _prism(groups: Dictionary, pos: Vector3, top: float, size: float, b: int) -> void:
	if not groups.has("prism"):
		groups["prism"] = []
	var depth := top + 0.8
	groups["prism"].append([Transform3D(Basis.from_scale(Vector3(size, depth, size)), pos + Vector3(0, top, 0)), Color(VoxelTiles.BIOMES[String(BIOMES[b])].deep)])

func _add_prisms(list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = prism()
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i][0])
		mm.set_instance_color(i, list[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _prism_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# A hex column one unit tall (its top at 0), pointy-topped like the tiles, sides only.
static func prism() -> ArrayMesh:
	if _prism_mesh != null:
		return _prism_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	var r := VoxelTiles.HEX_R * 0.98
	for i in 6:
		var a0 := PI / 6.0 + i * PI / 3.0
		var a1 := a0 + PI / 3.0
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		st.set_normal(Vector3(cos(a0 + PI / 6.0), 0, sin(a0 + PI / 6.0)))
		for v in [p0, p1, p1 + Vector3.DOWN, p0, p1 + Vector3.DOWN, p0 + Vector3.DOWN]:
			st.add_vertex(v)
	_prism_mesh = st.commit()
	return _prism_mesh

func _landmark_part(c: Vector2i, lm: Dictionary, d: int) -> String:
	var center: Vector2i = lm.center
	if lm.radius == 3:   # the dragon's hill: bare rock under it, obsidian behind, lava round the foot
		if d <= 1:
			return "base_3" if _rand(c, 3) < 0.5 else "base_1"
		if d == 2:
			return "standing" if c.y < center.y and _rand(c, 3) < 0.6 else ("shrine" if c == center + Vector2i(-2, 0) else "base_2")
		return "roots" if _rand(c, 3) < 0.35 else "flowers"
	if d == 0:
		return "shrine"
	if d == 1:
		var back := _back(center)
		if c == back[0]:
			return "tree_2"
		if c == back[1]:
			return "standing"
		return "base_1" if c in _front(center) else "flowers"
	if c.y < center.y:
		return "tree_1" if _rand(c, 3) < 0.55 else "tree_2"
	return "flowers" if _rand(c, 3) < 0.5 else "base_1"

# What grows on an ordinary hex, from the growth noise: groves, meadows and rocky ground, as on the board.
func _pick_part(c: Vector2i) -> String:
	var g := (_growth.get_noise_2d(c.x, c.y) + 1.0) * 0.5
	var r := _rand(c, 1)
	var part := ""
	if g > 0.64:
		part = ("tree_1" if _rand(c, 4) < 0.7 else "tree_2") if r < 0.7 else ("roots" if r < 0.82 else "base_3")
	elif g > 0.5:
		part = "flowers" if r < 0.4 else ("roots" if r < 0.5 else "base_1")
	elif g < 0.3:
		part = "stone" if r < 0.3 else ("standing" if r < 0.42 else "base_3")
	else:
		part = "flowers" if r < 0.12 else ("stone" if r < 0.2 else ("base_2" if r < 0.6 else "base_1"))
	if part in TALL and c.y >= 2 and r < 0.6:
		part = "flowers"   # the foreground stays fairly open
	return part

# --- the units and the dragon -----------------------------------------------------------------------

func _add_model(path: String, then: Callable) -> void:
	if ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
		then.call(load(path) as PackedScene if ResourceLoader.exists(path) else null)
		return
	Preload.request(path)
	_waiting.append([path, then])

func _poll_models() -> void:
	if _waiting.is_empty():
		_spawn_all()
		return
	Preload.collect()
	for w in _waiting.duplicate():
		if Preload.is_ready(w[0]) or ResourceLoader.has_cached(w[0]):
			_waiting.erase(w)
			w[1].call(load(w[0]) as PackedScene)

var _spawned := false
func _spawn_all() -> void:
	if _spawned:
		return
	_spawned = true
	for lm in _landmarks:
		for i in lm.units.size():
			var d: UnitData = lm.units[i]
			var spot: Vector3 = lm.get("stand_%d" % i, world(lm.center))
			_add_model(d.model_path, func(scene: PackedScene):
				var m := _model(scene, 1 if i == 0 else 2, UNIT_SCALE)
				if m != null:
					m.position = spot
					m.rotation.y = PI + (0.25 if i == 0 else -0.25)   # facing the camera, turned a little to each other
					lm.models.append(m))
	var dl: Dictionary = _landmarks[-1]
	var dd := _unit_data("dragon")
	if dd != null and dd.has_model():
		_add_model(dd.model_path, func(scene: PackedScene):
			dragon = _model(scene, 3, DRAGON_SCALE)
			if dragon != null:
				dragon.position = world(dl.center) + Vector3(0, (dl.radius + 1) * 3 * VoxelTiles.V, 0)
				var cam_end := Vector3(_camera_x(loop_len), 0, 15.0)
				dragon.rotation.y = atan2(cam_end.x - dragon.position.x, cam_end.z - dragon.position.z) + PI)

func _model(scene: PackedScene, star: int, s: float) -> UnitModel:
	var m := scene.instantiate() as UnitModel if scene != null else null
	if m == null:
		return null
	add_child(m)
	m.set_star(star)
	m.scale = Vector3.ONE * s
	return m

# --- the camera, the light, the timeline -------------------------------------------------------------

func _x_start() -> float:
	return _seg_center_x(0) - 8.0   # the forest's landmark comes in from the right as the picture fades in

func _x_end() -> float:
	return world(_landmarks[-1].center).x - DRAGON_SIDE

# The loop's timeline from the glide speed: glide, slow to a stop, the roar, hold, fade.
func _plan_time() -> void:
	var d := _x_end() - _x_start()
	fly_end = (d - SPEED * DECEL * 0.5) / SPEED
	stop = fly_end + DECEL
	roar = stop + ROAR_AFTER
	loop_len = roar + HOLD
	fade_out = loop_len - 0.9

func _camera_x(t: float) -> float:
	if t < fly_end:
		return _x_start() + SPEED * t
	if t < stop:
		var u := t - fly_end
		return _x_start() + SPEED * fly_end + SPEED * u - SPEED * u * u / (2.0 * DECEL)
	return _x_end()

# How far into the dragon shot (0 while gliding, 1 at the dragon).
func finale(t: float) -> float:
	return smoothstep(fly_end - 2.5, stop + 0.5, t)

# The biome the camera is over at time t (its light leads the picture).
func biome_at(t: float) -> StringName:
	return BIOMES[biome_index(_camera_x(t) + DRAGON_SIDE * finale(t))]

func _apply(t: float) -> void:
	var k := finale(t)
	var x := _camera_x(t)
	var shake := Vector3(sin(t * 61.0), sin(t * 47.0 + 1.0), 0) * 0.12 * _shake
	camera.position = Vector3(x, lerpf(8.5, 7.0, k), lerpf(12.0, 15.0, k) - maxf(0.0, t - stop) * 0.3) + shake
	camera.rotation_degrees = Vector3(lerpf(-31.0, -16.0, k), sin(t * 0.3) * 3.0 * (1.0 - k), 0.0)
	_env.fog_depth_begin = 30.0
	_env.fog_depth_end = 100.0
	_light(x + DRAGON_SIDE * k)
	if curtain != null:
		var a := 1.0
		if ready_to_run:
			a = 0.0 if Settings.reduce_motion else maxf(1.0 - smoothstep(0.0, FADE_IN, t), smoothstep(fade_out, loop_len, t))
		curtain.modulate.a = a

# The light over x: the two nearest biomes' looks, blended across the border between them.
func _light(x: float) -> void:
	var i := 0
	while i < BIOMES.size() - 1 and x >= _light_x(i + 1):
		i += 1
	var j := mini(i + 1, BIOMES.size() - 1)
	var s := 0.0 if j == i else smoothstep(0.25, 0.75, clampf((x - _light_x(i)) / (_light_x(j) - _light_x(i)), 0.0, 1.0))
	var a: Dictionary = BoardThemes.LIGHT[BIOMES[i]]
	var b: Dictionary = BoardThemes.LIGHT[BIOMES[j]]
	_sun.light_color = Color(a.sun).lerp(Color(b.sun), s)
	_sun.light_energy = lerpf(a.sun_e, b.sun_e, s) * LIGHT_LIFT
	_sun.rotation_degrees = Vector3(lerpf(a.pitch, b.pitch, s), lerpf(a.yaw, b.yaw, s), 0.0)
	_env.ambient_light_color = Color(a.amb).lerp(Color(b.amb), s)
	_env.ambient_light_energy = lerpf(a.amb_e, b.amb_e, s) * LIGHT_LIFT
	var fog := Color(a.fog).lerp(Color(b.fog), s).lightened(SKY_LIFT)
	_env.fog_light_color = fog
	_env.fog_density = lerpf(a.fog_d, b.fog_d, s)
	_env.glow_enabled = Settings.post_fx
	_env.glow_intensity = lerpf(a.glow, b.glow, s)
	RenderingServer.set_default_clear_color(fog)   # the sky is the haze, so the land fades into it

# The landmarks' casts, the dragon's roar and fire, embers over the volcano.
func _effects(delta: float) -> void:
	if Settings.reduce_motion:
		return
	var x := _camera_x(time)
	for lm in _landmarks:
		if not lm.cast and not lm.models.is_empty() and x >= world(lm.center).x - 3.0 and time < stop:
			lm.cast = true
			var m: UnitModel = lm.models[0]
			m.on_cast()
			var c := _origin_color(lm.units[0])
			Vfx.rings(self, m.global_position, c, 3, 1.6)
			Vfx.burst(self, m.global_position + Vector3(0, 1.2, 0), c, 10, 0.9)
	_shake = maxf(0.0, _shake - delta * 1.6)
	if dragon != null and not _roared and time >= roar:
		_roared = true
		dragon.on_cast()
		_shake = 1.0
		_breath_left = 1.5
		_breath_step = 0.25   # the fire comes a beat after the roar starts
		Vfx.rings(self, dragon.global_position + Vector3(0, 0.3, 0), Color("ff7a2e"), 4, 7.0)
		var lm: Dictionary = _landmarks[-1]
		for spot in [Vector2i(-3, 1), Vector2i(3, 0), Vector2i(-1, 3), Vector2i(2, 3)]:
			var p := world(lm.center + spot) + Vector3(0, 0.3, 0)
			Vfx._later(self, 0.3 + 0.2 * absf(spot.x), func(): Vfx.pillar(self, p, Color("ff6a1f"), 3.2, 0.5))
	if _breath_left > 0.0:
		_breath_left -= delta
		_breath_step -= delta
		while _breath_step <= 0.0 and _breath_left > 0.0:
			_breath_step += 0.03
			_fire_cube()
	if time > fly_end - 4.0 and time < fade_out:   # embers rising over the volcano
		_ember_step -= delta
		while _ember_step <= 0.0:
			_ember_step += 0.07
			_ember()

func _origin_color(d: UnitData) -> Color:
	for t in d.tags:
		if Vfx.ORIGIN_COLORS.has(t):
			return Vfx.ORIGIN_COLORS[t]
	return Color("cfd8ff")

# Where the dragon breathes from: high on its front (it faces the camera's last spot).
func _mouth() -> Vector3:
	var fwd := -dragon.global_basis.z.normalized()
	return dragon.global_position + Vector3(0, 1.25 * DRAGON_SCALE, 0) + fwd * 0.7 * DRAGON_SCALE

func _fire_cube() -> void:
	if dragon == null or not Vfx.enabled:
		return
	var fwd := -dragon.global_basis.z.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var from := _mouth()
	var sweep := 1.0 - _breath_left / 1.5   # the fire sweeps across the land in front of it
	var to := dragon.global_position + fwd * 6.0 + side * lerpf(-10.0, 3.0, sweep) + Vector3(_fx_rng.randf_range(-1.2, 1.2), _fx_rng.randf_range(0.0, 1.2), _fx_rng.randf_range(-1.2, 1.2))
	var hot := _fx_rng.randf() < 0.3
	var b := Vfx._bit(self, from, 0.3, Color("fff2b0") if hot else (Color("ff7a2e") if _fx_rng.randf() < 0.6 else Color("ff3b1f")), 1.9 if hot else 1.5)
	if b == null:
		return
	var t := b.create_tween()
	t.tween_property(b, "global_position", to, 0.5).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(b, "scale", Vector3.ONE * 3.2, 0.5)
	t.parallel().tween_property(b, "rotation", Vector3(_fx_rng.randf() * 4.0, _fx_rng.randf() * 4.0, 0), 0.5)
	t.tween_property(b, "scale", Vector3.ZERO, 0.2)
	t.tween_callback(b.queue_free)

func _ember() -> void:
	if not Vfx.enabled:
		return
	var lm: Dictionary = _landmarks[-1]
	var base := world(lm.center)
	var p := base + Vector3(_fx_rng.randf_range(-16.0, 12.0), _fx_rng.randf_range(0.0, 0.6), _fx_rng.randf_range(-8.0, 14.0))
	var b := Vfx._bit(self, p, 0.09, Color("ffb347") if _fx_rng.randf() < 0.5 else Color("ff6a1f"), 1.8)
	if b == null:
		return
	var t := b.create_tween()
	t.tween_property(b, "global_position", p + Vector3(_fx_rng.randf_range(-0.6, 0.6), _fx_rng.randf_range(1.5, 3.5), 0), 1.4)
	t.parallel().tween_property(b, "rotation", Vector3(2, 3, 1), 1.4)
	t.tween_property(b, "scale", Vector3.ZERO, 0.2)
	t.tween_callback(b.queue_free)

# A dark band down the middle (behind the title and buttons) that clears toward the sides, so the menu
# stays readable over bright snow or salt.
static func vignette() -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 1.0])
	var dark := Color("0b0c12")
	g.colors = PackedColorArray([Color(dark, 0.12), Color(dark, 0.45), Color(dark, 0.55), Color(dark, 0.45), Color(dark, 0.12)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 4
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
