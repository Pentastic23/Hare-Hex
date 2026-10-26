# board.gd
class_name Board extends Node3D

const COLS := 7
const ROWS := 8
const HEX := 1.0
const BENCH_SLOTS := 9
const PLAYER_START := [Vector2i(3, 4), Vector2i(4, 4)]
const ENEMY_START := [Vector2i(3, 3), Vector2i(4, 3)]
const FULL_BOARD_LEVEL := 8
const NO_STEP := Vector2i(-99, -99)
const DIRS_EVEN := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const DIRS_ODD := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const BORDER_R := VoxelTiles.HEX_R   # the tiles' corners, so the seam line runs along their edges
const KING_ROWS := [5, 2]   # the row each side's king stands on (index = team): the second row of its half

var tile_scene: PackedScene = preload("res://scenes/Tiles.tscn")
var tiles := {}          # Vector2i -> Tile
var bench: Array[Unit]   # fixed size, null = empty
var unlocked := {}   # Vector2i -> true
var player_order: Array[Vector2i] = []
var enemy_order: Array[Vector2i] = []
var foe_level := -1   # the enemy half's level (async PvP's ghost, a lobby); -1 = it follows yours (refresh_unlocks)
var kings: Array[King] = []   # index = team (0 you, 1 the enemy): the extra hex left of each side, see king.gd
var _border_mat: StandardMaterial3D
var theme: StringName = &""   # the board look (BoardThemes); set by apply_theme
var runner: CombatRunner      # the fight on this board (set by CombatRunner.new(board)); Abilities find it here
# Whose board this is: gold from selling, items given back. The visible board is the local player's
# (GameState.me); the lobby server's seat boards belong to their seats. Signals (Events) only fire for
# the local player, so a server board never moves the HUD.
var player: PlayerState
var pool: UnitPool   # sold units go back here (the run's or the lobby's shared pool); null: nowhere
# false for the lobby server's hidden boards: no kings, bench and sell hexes, borders, themes or unit
# models, and no listening to the local player's level or phase. Set before the board enters the tree.
var visual := true
var _next_uid := 1   # Unit.uid for the units made on this board (the lobby protocol names units by it)
var runner_credits_both := false   # a lobby arena: both teams belong to players (Pickpocket gold for either side)
var _bench_tiles: Array[Node3D] = []
var _enemy_bench_tiles: Array[Node3D] = []   # the enemy's bench across the board (scenery for now: no enemy keeps units on it)
var _sell_tile: Node3D
static var _prism: ArrayMesh   # the hex block every tile, bench slot and sell hex shares

const BLOCK_DEPTH := 0.3       # how far a tile block reaches below its top


static func to_cube(c: Vector2i) -> Vector3i:
	var q := c.x - ((c.y - (c.y & 1)) >> 1)
	return Vector3i(q, -q - c.y, c.y)

static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ca := to_cube(a)
	var cb := to_cube(b)
	return maxi(maxi(absi(ca.x - cb.x), absi(ca.y - cb.y)), absi(ca.z - cb.z))

func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dirs = DIRS_ODD if (c.y & 1) == 1 else DIRS_EVEN
	for d in dirs:
		var n: Vector2i = c + d
		if tiles.has(n) and is_unlocked(n):
			out.append(n)
	return out

# Returns the next tile to step to, or NO_STEP if nothing reachable is in range.
func next_step(from: Vector2i, goal: Vector2i, range_tiles: int) -> Vector2i:
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur != from and hex_distance(cur, goal) <= range_tiles:
			while came[cur] != from:
				cur = came[cur]
			return cur
		for n in neighbors(cur):
			if came.has(n) or tiles[n].occupant != null:
				continue
			came[n] = cur
			queue.append(n)
	return NO_STEP

func nearest_enemy(u: Unit) -> Unit:
	var best: Unit = null
	var best_d := 9999
	for n in $Units.get_children():
		var o := n as Unit
		if o == null or o == u or o.team != u.foe_team() or o.dead or o.coord.x < 0 or o.is_queued_for_deletion() or o.untargetable_left > 0.0:
			continue
		var d := hex_distance(u.coord, o.coord)
		# Ties go to the lower tile (row, then column), so node order never decides a target.
		if d < best_d or (d == best_d and tile_order(o.coord) < tile_order(best.coord)):
			best_d = d
			best = o
	return best

static func tile_order(c: Vector2i) -> int:
	return c.y * COLS + c.x

# Logical move only (no position change; the unit steps itself each combat tick).
func claim(u: Unit, c: Vector2i):
	vacate(u)
	tiles[c].occupant = u
	u.coord = c

func vacate(u: Unit):
	if tiles.has(u.coord) and tiles[u.coord].occupant == u:
		tiles[u.coord].occupant = null


# A board made in code (the scene's Board has these children in main.tscn): for the lobby server.
static func make(is_visual := true) -> Board:
	var b := Board.new()
	b.visual = is_visual
	for n in ["Bench", "Units", "Tiles"]:
		var child := Node3D.new()
		child.name = n
		b.add_child(child)
	return b

func next_uid() -> int:
	_next_uid += 1
	return _next_uid - 1

# Makes a unit of this board's side 0 (bought, carried, restored), with a fresh uid.
func make_unit(d: UnitData, scene: PackedScene) -> Unit:
	var u := scene.instantiate() as Unit
	$Units.add_child(u)
	u.uid = next_uid()
	u.setup(d, 0)
	return u

func _local() -> bool:
	return player != null and player.is_local

func _ready():
	if player == null:
		player = GameState.me
	if visual:
		add_to_group("board")
	bench.resize(BENCH_SLOTS)
	for r in ROWS:
		for c in COLS:
			var t: Tile = tile_scene.instantiate()
			t.coord = Vector2i(c, r)
			$Tiles.add_child(t)
			t.position = grid_to_world(t.coord)
			tiles[t.coord] = t
	player_order = _order_for(true)
	enemy_order = _order_for(false)
	if visual:
		_build_kings()
	refresh_unlocks(player.level, false)
	if not visual:
		return
	Events.xp_changed.connect(_on_xp_changed)
	Events.phase_changed.connect(_on_phase_for_unlocks)
	_build_bench_slots()
	_build_sell_zone()
	apply_theme(BoardThemes.DEFAULT)   # until GameManager sets the run's biome
	
# Dresses the board in a biome (BoardThemes, docs/hex-tile-design-plan.md): every board hex becomes one
# of the biome's three plain voxel tiles (picked by its coord), the bench, sell hex and kings get theirs,
# the world round it is filled with the biome's decorated tiles (flowers, stones, roots, standing stones,
# shrines, trees) from `seed` (_build_backdrop), and the backdrop takes the biome's colour. Visual only.
func apply_theme(id: StringName, seed := 0) -> void:
	if not visual:
		return
	if not BoardThemes.has(id):
		id = BoardThemes.DEFAULT
	theme = id
	for t in tiles.values():
		var c: Vector2i = t.coord
		_skin(t, VoxelTiles.BASES[posmod(c.x * 7 + c.y * 13, VoxelTiles.BASES.size())])
	for s in _bench_tiles + _enemy_bench_tiles:
		_skin(s, "bench")
	for k in kings:
		_skin(k, "base_2")
	if _sell_tile != null:
		_skin(_sell_tile, "sell")
	_build_backdrop(seed)
	RenderingServer.set_default_clear_color(BoardThemes.backdrop(id))
	var main := get_parent()
	if main != null:   # the run's sun, ambient light, haze and glow (main.tscn's WorldEnvironment and light)
		var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
		BoardThemes.apply_look(id, we.environment if we != null else null, main.get_node_or_null("DirectionalLight3D") as DirectionalLight3D)
		PortraitStudio.open(main, id)   # the unit portraits drawn in the same light

func _skin(node: Node3D, part: String) -> void:
	var mi := node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		return
	var m := BoardThemes.tile(theme, part)
	mi.mesh = m if m != null else hex_block()   # not baked yet: the plain block
	mi.material_override = null
	for i in mi.get_surface_override_material_count():
		mi.set_surface_override_material(i, null)

# --- the world around the board (scenery, never played on) --------------------------------------

# Everything the camera can show is filled with the biome's tiles, so the board sits in a landscape.
# Noise decides where things grow: trees gather in groves, flowers and roots in meadows, stones and
# standing stones in rocky patches; away from the board the ground rises and falls a voxel or two.
# The scenery sits a voxel below the board (so the board reads as a low plateau); the two hexes round
# it stay level, and nothing tall stands beside it or in front (where it would
# hide the fight, the bench or the shop). Locked board hexes show as lower, darker ground, so the board
# never has a hole and its tiles rise out of it as they unlock. Drawn with one MultiMesh per kind of
# tile. Seeded with its own RNG: it never touches the game's.

const VIEW_ASPECT := 2.4      # covers ultrawide windows too
const FLAT_RING := 2          # hexes round the board that stay level
const MIRAGE_CHANCE := 0.07   # desert: now and then a see-through forest tile shimmers in the sand
const TALL := ["standing", "tree_1", "tree_2"]
const SCENERY_SHADE := Color(0.85, 0.85, 0.88)   # the board stays at full brightness, so it reads at a glance
const UNDERLAY_SHADE := Color(0.6, 0.6, 0.64)    # board hexes not unlocked yet
var backdrop_cells := {}      # hex -> part, the scenery laid out by the last apply_theme (tests read it)
var _flip_spots: Array[Node3D] = []

func _build_backdrop(seed: int) -> void:
	var old := get_node_or_null("Backdrop")
	if old != null:
		remove_child(old)
		old.queue_free()
	var root := Node3D.new()
	root.name = "Backdrop"
	add_child(root)
	backdrop_cells.clear()
	_flip_spots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, String(theme)])
	var growth := FastNoiseLite.new()   # groves, meadows and rocky patches
	growth.seed = rng.randi()
	growth.frequency = 0.11
	var lift := FastNoiseLite.new()     # gentle hills
	lift.seed = rng.randi()
	lift.frequency = 0.08
	var area := _visible_ground()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in area:
		lo = lo.min(p)
		hi = hi.max(p)
	var w := HEX * sqrt(3.0)
	var keep_clear: Array[Vector3] = []   # both benches and the sell hex
	for i in BENCH_SLOTS + 1:
		keep_clear.append(bench_to_world(i))
	for i in BENCH_SLOTS:
		keep_clear.append(enemy_bench_to_world(i))
	var groups := {}   # part (or part + "|mirage" / "underlay") -> Array of Transform3D
	for y in range(floori(lo.y / (1.5 * HEX)) - 1, ceili(hi.y / (1.5 * HEX)) + 2):
		for x in range(floori(lo.x / w) - 2, ceili(hi.x / w) + 2):
			var c := Vector2i(x, y)
			var pos := grid_to_world(c)
			if not Geometry2D.is_point_in_polygon(Vector2(pos.x, pos.z), area) and _gap(Vector2(pos.x, pos.z), area) > w:
				continue
			var spin := Basis(Vector3.UP, rng.randi_range(0, 5) * PI / 3.0)   # a hex fits every sixth of a turn
			if tiles.has(c) or (c.x == -1 and c.y in KING_ROWS):   # under the board (and the kings' full-board spots): lower, darker ground until a tile or king is there
				_group(groups, "underlay", Transform3D(spin, pos + Vector3(0, -3.0 * VoxelTiles.V, 0)))
				continue
			if _near(pos, keep_clear, 0.9 * HEX):
				continue   # right under a bench slot or the sell hex
			var by_bench := _near(pos, keep_clear, 1.8 * HEX)   # right beside one: kept low and flat
			var d := _board_distance(c)
			var g := (growth.get_noise_2d(x, y) + 1.0) * 0.5
			var part := _pick_part(g, d, rng)
			var in_front := c.y >= ROWS - 1 or by_bench
			var beside := d <= 1 and c.y > 2
			while part in TALL and (in_front or beside):
				part = "flowers" if g > 0.5 else "base_1"
			var height := -VoxelTiles.V   # a voxel below the board, so the board stands out as a low plateau
			if d > FLAT_RING and not in_front:
				height += roundi(lift.get_noise_2d(x, y) * 3.0) * VoxelTiles.V   # -2 to +2 voxels more
			var t := Transform3D(spin, pos + Vector3(0, height, 0))
			backdrop_cells[c] = part
			if c.x == COLS and (ROWS - 1 - c.y) in KING_ROWS:
				_flip_spot(root, part, t)   # where a turned lobby board's kings stand: its own node
			elif theme == &"desert" and rng.randf() < MIRAGE_CHANCE:
				_group(groups, "flowers|mirage", t)
			else:
				_group(groups, part, t)
	for key in groups:
		var name: String = key
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true   # scenery a shade darker than the board, locked board hexes darker still
		var mirage := name.ends_with("|mirage")
		var underlay := name == "underlay"
		mm.mesh = BoardThemes.tile(&"forest" if mirage else theme, "flowers" if mirage else ("base_2" if underlay else name))
		if mm.mesh == null:
			continue
		var list: Array = groups[key]
		mm.instance_count = list.size()
		var shade := UNDERLAY_SHADE if underlay else SCENERY_SHADE
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, shade)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = name.replace("|", "_")
		mmi.multimesh = mm
		if mirage:
			mmi.material_override = _mirage_mat()
		root.add_child(mmi)

# What grows on a hex, from the growth noise (0-1) and the distance to the board.
func _pick_part(g: float, d: int, rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if d >= 2 and r < 0.015:
		return "shrine"
	if g > 0.64:   # a grove
		return ("tree_1" if rng.randf() < 0.7 else "tree_2") if r < 0.7 else ("roots" if r < 0.82 else "base_3")
	if g > 0.5:    # a meadow
		return "flowers" if r < 0.4 else ("roots" if r < 0.5 else "base_1")
	if g < 0.3:    # rocky ground
		return "stone" if r < 0.3 else ("standing" if r < 0.42 else "base_3")
	return "flowers" if r < 0.12 else ("stone" if r < 0.2 else "base_1")

func _group(groups: Dictionary, key: String, t: Transform3D) -> void:
	if not groups.has(key):
		groups[key] = []
	groups[key].append(t)

func _flip_spot(root: Node3D, part: String, t: Transform3D) -> void:
	var m := MeshInstance3D.new()
	m.mesh = BoardThemes.tile(theme, part)
	m.transform = t
	m.visible = not view_flipped
	root.add_child(m)
	_flip_spots.append(m)

# The ground the camera can show (CameraRig.widest_ground), or a generous box round the board without one.
func _visible_ground() -> PackedVector2Array:
	var rig = get_parent().get_node_or_null("CameraRig") if get_parent() != null else null
	if rig != null and rig.has_method("widest_ground"):
		return rig.widest_ground(VIEW_ASPECT)
	return PackedVector2Array([Vector2(-25, -12), Vector2(37, -12), Vector2(37, 22), Vector2(-25, 22)])

static func _gap(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best

static func _near(p: Vector3, spots: Array[Vector3], r: float) -> bool:
	for s in spots:
		if Vector2(p.x, p.z).distance_to(Vector2(s.x, s.z)) < r:
			return true
	return false

# Hex steps from c to the nearest board hex.
func _board_distance(c: Vector2i) -> int:
	var cx := clampi(c.x, 0, COLS - 1)
	var cy := clampi(c.y, 0, ROWS - 1)
	var best := 99
	for y in range(maxi(cy - 2, 0), mini(cy + 3, ROWS)):
		for x in range(maxi(cx - 2, 0), mini(cx + 3, COLS)):
			best = mini(best, hex_distance(c, Vector2i(x, y)))
	return best

static var _mirage: StandardMaterial3D
static func _mirage_mat() -> StandardMaterial3D:
	if _mirage == null:
		_mirage = (VoxelTiles.SOLID as StandardMaterial3D).duplicate()
		_mirage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mirage.albedo_color = Color(1, 1, 1, 0.38)
	return _mirage

# A pointy-top hex block (same corners as the old 6-sided cylinder): surface 0 is the top, mapped
# flat onto the texture; surface 1 is the six sides, each showing the whole side texture.
static func hex_block() -> ArrayMesh:
	if _prism != null:
		return _prism
	var r := VoxelTiles.HEX_R
	var top_y := 0.005
	var bottom_y := -BLOCK_DEPTH
	var corners: Array[Vector3] = []
	for k in 6:
		var a := k * TAU / 6.0
		corners.append(Vector3(sin(a) * r, 0.0, cos(a) * r))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := corners[k]
		var b := corners[(k + 1) % 6]
		for p in [Vector3.ZERO, b, a]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2((p.x / r + 1.0) * 0.5, (p.z / r + 1.0) * 0.5))
			st.add_vertex(p + Vector3(0, top_y, 0))
	_prism = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := corners[k]
		var b := corners[(k + 1) % 6]
		var n := ((a + b) * 0.5).normalized()
		var quad := [[a, top_y, 0.0, 0.0], [b, top_y, 1.0, 0.0], [b, bottom_y, 1.0, 1.0], [a, top_y, 0.0, 0.0], [b, bottom_y, 1.0, 1.0], [a, bottom_y, 0.0, 1.0]]
		for q in quad:
			st.set_normal(n)
			st.set_uv(Vector2(q[2], q[3]))
			st.add_vertex(q[0] + Vector3(0, q[1], 0))
	st.commit(_prism)
	return _prism

func _build_border():
	if _border_mat == null:
		_border_mat = StandardMaterial3D.new()
		_border_mat.albedo_color = Color(1.0, 0.85, 0.3)
		_border_mat.emission_enabled = true
		_border_mat.emission = Color(1.0, 0.75, 0.2)
		_border_mat.emission_energy_multiplier = 1.5

	var holder: Node3D = get_node_or_null("Border")
	if holder:
		holder.free()
	holder = Node3D.new()
	holder.name = "Border"
	add_child(holder)
	if view_flipped:
		set_view_flipped(true)

	var r := BORDER_R
	var y := 0.12
	var hw := sqrt(3.0) * r / 2.0
	for key in tiles:
		var c: Vector2i = key
		if not is_player_side(c) or not is_unlocked(c):
			continue
		var odd: bool = (c.y & 1) == 1
		var up_left: Vector2i = c + (Vector2i(0, -1) if odd else Vector2i(-1, -1))
		var up_right: Vector2i = c + (Vector2i(1, -1) if odd else Vector2i(0, -1))

		var p: Vector3 = grid_to_world(c)
		var top_left := Vector3(p.x - hw, y, p.z - r * 0.5)
		var top := Vector3(p.x, y, p.z - r)
		var top_right := Vector3(p.x + hw, y, p.z - r * 0.5)

		if tiles.has(up_left) and not is_player_side(up_left) and is_unlocked(up_left):
			_border_segment(holder, top_left, top)
		if tiles.has(up_right) and not is_player_side(up_right) and is_unlocked(up_right):
			_border_segment(holder, top, top_right)


func _border_segment(parent: Node3D, a: Vector3, b: Vector3):
	var d := b - a
	var len := Vector2(d.x, d.z).length()
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(len + 0.08, 0.03, 0.07)   # +0.08 closes the joints between segments
	m.mesh = box
	m.material_override = _border_mat
	m.position = (a + b) / 2.0
	m.rotation.y = atan2(-d.z, d.x)
	parent.add_child(m)


func bench_slot_near(p: Vector3) -> int:
	var best := -1
	var best_d := HEX * 0.95
	for i in BENCH_SLOTS:
		var b := bench_to_world(i)
		var d := Vector2(p.x - b.x, p.z - b.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best

func all_player_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for n in $Units.get_children():
		var u := n as Unit
		if u and u.team == 0 and u.data != null and not u.is_queued_for_deletion():
			out.append(u)
	return out

# Returns true if a merge happened (call repeatedly until false to chain 2-star into 3-star).
# Merges one group of three copies (same unit, same star). bench_only: only units on the bench (mid-fight,
# when the board's units are fighting).
func try_merge(bench_only := false) -> bool:
	var groups := {}
	for u in all_player_units():
		if u.star >= 3 or (bench_only and u.coord.x >= 0):
			continue
		var key := "%s|%d" % [u.data.display_name, u.star]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(u)

	for key in groups:
		var g: Array = groups[key]
		if g.size() < 3:
			continue
		g.sort_custom(func(a, b): return a.coord.x >= 0 and b.coord.x < 0)
		var keeper: Unit = g[0]
		_move_items_to(keeper, [g[1], g[2]])
		for i in [1, 2]:
			detach(g[i])
			g[i].queue_free()
		keeper.set_star(keeper.star + 1)
		if visual:
			Sfx.play(&"merge")
		return true
	return false

func merge_all(bench_only := false):
	while try_merge(bench_only):
		pass

# Gives the consumed units' items to the keeper (up to its limit); the rest go back to the inventory.
# Bound items keep their growth: the keeper's copy of each ends with the most stacks any of the three
# units had for it (items that go back to the inventory lose theirs).
func _move_items_to(keeper: Unit, consumed: Array) -> void:
	var best := {}
	for c in [keeper] + consumed:
		var cu: Unit = c
		for id in cu.item_stacks:
			best[id] = maxi(int(best.get(id, 0)), int(cu.item_stacks[id]))
	var returned := false
	for c in consumed:
		var cu: Unit = c
		for item in cu.take_items():
			if not keeper.equip(item):
				player.items.append(item)
				returned = true
	var regrow := false
	for it in keeper.items:
		if best.has(it.id) and keeper.stacks_of(it) < int(best[it.id]):
			keeper.item_stacks[it.id] = best[it.id]
			regrow = true
	if regrow:
		keeper._recalc_items()
	if returned and _local():
		Events.items_changed.emit()

# Puts a unit's items back in the inventory (selling, or a unit removed for lack of room).
func _return_items(u: Unit) -> void:
	var taken := u.take_items()
	if taken.is_empty():
		return
	player.items.append_array(taken)
	if _local():
		Events.items_changed.emit()

func nearest_tile(p: Vector3, max_dist := HEX * 1.2) -> Tile:
	var best: Tile = null
	var best_d := max_dist
	for c in tiles:
		if not is_unlocked(c):
			continue
		var w := grid_to_world(c)
		var d := Vector2(p.x - w.x, p.z - w.z).length()
		if d < best_d:
			best_d = d
			best = tiles[c]
	return best

func grid_to_world(c: Vector2i) -> Vector3:
	return Vector3(HEX * sqrt(3.0) * (c.x + 0.5 * (c.y & 1)), 0.05, HEX * 1.5 * c.y)

# Where tile c is shown in the world (spell effects): grid_to_world as placed by the Units node, which a
# lobby client turns around while watching a fight from the away side (set_view_flipped).
func display_pos(c: Vector2i) -> Vector3:
	return $Units.to_global(grid_to_world(c)) if is_inside_tree() else grid_to_world(c)

# The away player's view of a lobby fight: tiles, units, kings and the border turned 180 degrees about
# the middle of the board, so their own side (team 1, rows 0-3) is at the bottom, next to their bench.
# The board's mirror (BoardSnapshot.mirror) is exactly this turn, so every hex lands on a hex. View only.
var view_flipped := false
func set_view_flipped(on: bool) -> void:
	view_flipped = on
	var center := Vector3(HEX * sqrt(3.0) * ((COLS - 1) / 2.0 + 0.25), 0.0, HEX * 1.5 * (ROWS - 1) / 2.0)
	var t := Transform3D(Basis(Vector3.UP, PI), center * 2.0) if on else Transform3D.IDENTITY
	for n in ["Tiles", "Units", "Kings", "Border"]:
		var node := get_node_or_null(n) as Node3D
		if node != null:
			node.transform = t
	for k in kings:
		k.recolour()
	for m in _flip_spots:
		if is_instance_valid(m):
			m.visible = not on   # the scenery steps aside where the turned kings stand
	for i in bench.size():   # bench units live in Units too, but the bench itself never turns
		if bench[i] != null:
			put_on_bench(bench[i], i)

# Bench slot i in the Units node's own space (the same as bench_to_world unless the view is turned).
func bench_local(i: int) -> Vector3:
	var units := get_node_or_null("Units") as Node3D
	return units.transform.affine_inverse() * bench_to_world(i) if units != null else bench_to_world(i)

# Bench slot i (0-8; slot BENCH_SLOTS is the sell hex): one row past the board, on the same hex grid as
# the board and the scenery round it, so every hex slots in edge to edge. The bench and the sell hex
# together sit as near the middle under the board as the grid allows (a quarter hex right of it).
func bench_to_world(i: int) -> Vector3:
	var p := grid_to_world(Vector2i(i - 1, ROWS))
	return Vector3(p.x, 0.0, p.z)

# The enemy's bench slot i: the row just beyond the far edge of the board (nearer than the mirror of yours,
# so it stays in view at the top of the screen), on the hex grid like yours.
func enemy_bench_to_world(i: int) -> Vector3:
	var p := grid_to_world(Vector2i(i - 1, -1))
	return Vector3(p.x, 0.0, p.z)

# bench_only: count only bench copies (a purchase mid-fight never merges with units fighting on the board).
func would_complete_merge(d: UnitData, bench_only := false) -> bool:
	var count := 0
	for u in all_player_units():
		if u.data == d and u.star == 1 and not (bench_only and u.coord.x >= 0):
			count += 1
	return count >= 2

func merge_pending_unit(newbie: Unit, bench_only := false):
	var copies: Array[Unit] = []
	for u in all_player_units():
		if u != newbie and u.data == newbie.data and u.star == 1 and not (bench_only and u.coord.x >= 0):
			copies.append(u)
	copies.sort_custom(func(a, b): return (a.coord.x >= 0) and not (b.coord.x >= 0))
	if copies.size() < 2:
		newbie.queue_free()
		return
	var keeper: Unit = copies[0]
	_move_items_to(keeper, [copies[1]])
	detach(copies[1])
	copies[1].queue_free()
	newbie.queue_free()
	keeper.set_star(2)
	merge_all(bench_only)

func _build_bench_slots():
	for i in BENCH_SLOTS:
		var s: Node3D = tile_scene.instantiate()
		# Visual only: no collision, so drag raycasts never hit it.
		if s is CollisionObject3D:
			s.collision_layer = 0
			s.collision_mask = 0
		$Bench.add_child(s)
		s.position = bench_to_world(i)
		_bench_tiles.append(s)   # its look comes from the theme (apply_theme)
	for i in BENCH_SLOTS:   # the enemy's, mirrored on the far side of the board
		var e: Node3D = tile_scene.instantiate()
		if e is CollisionObject3D:
			e.collision_layer = 0
			e.collision_mask = 0
		$Bench.add_child(e)
		e.position = enemy_bench_to_world(i)
		_enemy_bench_tiles.append(e)

func is_player_side(c: Vector2i) -> bool:
	return c.y >= ROWS / 2

func first_free_bench() -> int:
	return bench.find(null)
func detach(u: Unit):
	var i := bench.find(u)
	if i != -1:
		bench[i] = null
	if tiles.has(u.coord) and tiles[u.coord].occupant == u:
		tiles[u.coord].occupant = null
	u.coord = Vector2i(-1, -1)

func put_on_tile(u: Unit, c: Vector2i):
	if not tiles.has(c) or (tiles[c].occupant != null and tiles[c].occupant != u):
		var slot := first_free_bench()
		if slot != -1:
			put_on_bench(u, slot)
		else:
			push_warning("No room for unit; removed")
			_return_items(u)
			u.queue_free()
		return
	tiles[c].occupant = u
	u.coord = c
	u.position = grid_to_world(c)

func put_on_bench(u: Unit, i: int):
	if bench[i] != null and bench[i] != u:
		i = first_free_bench()
		if i == -1:
			push_warning("Bench full; unit removed")
			_return_items(u)
			u.queue_free()
			return
	bench[i] = u
	u.coord = Vector2i(-1, -1)
	u.position = bench_local(i)
	u.face_rest()   # looking at the camera


# Fills free board slots from the bench when a fight starts: the leftmost bench unit goes first, while
# the board is under `cap` and has an open tile. Each unit takes a spot that suits it: melee (range 1)
# the frontmost open row, range 2 the second row, ranged (3+) the backmost; within a row, the tile
# nearest the centre column (ties to the left). Returns the units it placed.
func auto_fill(cap: int) -> Array[Unit]:
	var placed: Array[Unit] = []
	while units_on_board() < cap:
		var u: Unit = null
		for b in bench:
			if b != null and b.team == 0:
				u = b
				break
		if u == null:
			break
		var c := open_tile_for(u.data)
		if c.x < 0:
			break
		detach(u)
		put_on_tile(u, c)
		placed.append(u)
	return placed

# The open player tile that suits a unit's range (see auto_fill), or (-1, -1) if the board is full.
func open_tile_for(d: UnitData) -> Vector2i:
	var front := ROWS / 2   # row 4, next to the enemy half
	var rows: Array = range(front, ROWS)   # front to back
	var reach := roundi(d.attack_range) if d != null else 1
	if reach >= 3:
		rows.reverse()
	elif reach == 2:
		rows = [front + 1, front] + range(front + 2, ROWS)
	var mid := (COLS - 1) / 2
	for r in rows:
		var best := Vector2i(-1, -1)
		for x in COLS:
			var c := Vector2i(x, r)
			if not is_unlocked(c) or tiles[c].occupant != null:
				continue
			if best.x < 0 or absi(x - mid) < absi(best.x - mid):
				best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

func units_on_board() -> int:
	var n := 0
	for t in tiles.values():
		if t.occupant != null and t.occupant.team == 0:
			n += 1
	return n

func sell_zone_pos() -> Vector3:
	return bench_to_world(BENCH_SLOTS)   # the slot right after the last bench hex

func is_over_sell_zone(p: Vector3) -> bool:
	var s := sell_zone_pos()
	return Vector2(p.x - s.x, p.z - s.z).length() < HEX * 0.95

func sell_unit(u: Unit):
	if u == null or u.data == null or u.summoned:
		return
	var refund := u.data.cost * UnitPool.copies_in(u.star)   # use `u.data.cost` for a flat refund
	var d := u.data
	var star := u.star
	_return_items(u)
	detach(u)
	u.queue_free()
	player.gold += refund
	if pool != null:
		pool.give_back(d, UnitPool.copies_in(star))
	if player != null:
		KingPowers.on_sell(player, d, star)   # the Necromancer King remembers it
	if _local():
		Events.unit_sold.emit(d, star, refund)

func _build_sell_zone():
	var s: Node3D = tile_scene.instantiate()
	if s is CollisionObject3D:
		s.collision_layer = 0
		s.collision_mask = 0
	$Bench.add_child(s)
	s.position = sell_zone_pos()
	_sell_tile = s   # its look comes from the theme (apply_theme)
	var l := Label3D.new()
	l.text = "SELL" if OS.has_feature("mobile") else "SELL\n(F)"   # no F key on a phone: drag a unit here
	l.font_size = 64
	l.pixel_size = 0.01
	l.outline_size = 16
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.position = Vector3(0, 0.5, 0)
	s.add_child(l)

func is_unlocked(c: Vector2i) -> bool:
	return unlocked.has(c)

func _start_dist(c: Vector2i, starts: Array) -> int:
	var best := 9999
	for s in starts:
		best = mini(best, hex_distance(c, s))
	return best

func _order_for(player: bool) -> Array[Vector2i]:
	var starts: Array = PLAYER_START if player else ENEMY_START
	var center := Vector2.ZERO
	for s in starts:
		var w := grid_to_world(s)
		center += Vector2(w.x, w.z)
	center /= starts.size()

	var list: Array[Vector2i] = []
	for c in tiles:
		if is_player_side(c) == player:
			list.append(c)

	list.sort_custom(func(a, b):
		var wa := grid_to_world(a)
		var wb := grid_to_world(b)
		var da := snappedf(Vector2(wa.x, wa.z).distance_to(center), 0.01)
		var db := snappedf(Vector2(wb.x, wb.z).distance_to(center), 0.01)
		if da != db:
			return da < db
		var xa := snappedf(absf(wa.x - center.x), 0.01)
		var xb := snappedf(absf(wb.x - center.x), 0.01)
		if xa != xb:
			return xa < xb
		return a.x < b.x)
	return list

# Opens your half for `level`. The enemy half follows it too, unless foe_level is set (async PvP and
# lobbies: the opponent's own level, its tiles the mirror images of the ones that player has open).
func refresh_unlocks(level: int, animate := true):
	var n: int = tiles_open_for_level(level)
	unlocked.clear()
	for i in player_order.size():
		if i < n:
			unlocked[player_order[i]] = true
	if foe_level < 0:
		for i in mini(n, enemy_order.size()):
			unlocked[enemy_order[i]] = true
	else:
		for c in open_player_tiles(foe_level):
			unlocked[BoardSnapshot.mirror(c)] = true
	for c in tiles:
		tiles[c].set_unlocked(unlocked.has(c), animate)
	if visual:
		_build_border()
	_place_kings(animate)

# --- the kings (king.gd) ---------------------------------------------------------------------------

func _build_kings() -> void:
	var holder := Node3D.new()
	holder.name = "Kings"
	add_child(holder)
	for team in 2:
		var k := King.new()
		holder.add_child(k)
		k.setup(team)
		kings.append(k)

func king_of(team: int) -> King:
	return kings[team] if team >= 0 and team < kings.size() else null

func _place_kings(animate: bool) -> void:
	for team in kings.size():
		kings[team].move_to(king_spot(team), animate)

# Where a side's king stands (world position): in its row (KING_ROWS), one hex left of the leftmost open
# tile of that row, so it sits right at the left edge of the board and moves outwards as the board grows.
# While that row has no open tile yet (the first level only opens the start row) it hangs off the nearest
# row that has one, half a hex further left: still touching the edge, and never on an open tile.
func king_spot(team: int) -> Vector3:
	var row: int = KING_ROWS[team]
	var w := HEX * sqrt(3.0)
	var left := {}   # row -> world x of its leftmost open tile (on this side)
	for c in unlocked:
		if is_player_side(c) != (team == 0):
			continue
		var x := grid_to_world(c).x
		left[c.y] = minf(float(left.get(c.y, INF)), x)
	var ref := -1
	for r in left:
		if ref < 0 or absi(r - row) < absi(ref - row):
			ref = r
	var base := Vector3(0.0, 0.05, HEX * 1.5 * row)
	if ref < 0:
		base.x = -w   # nothing open at all (never happens: the start tiles are always open)
		return base
	base.x = float(left[ref]) - (w if ref == row else w * 0.5)
	return base

static func tiles_open_for_level(level: int) -> int:   # per side; static so campaign validation can use it
	var per_side := ROWS / 2 * COLS   # 28
	var t := clampf(float(level - 1) / float(FULL_BOARD_LEVEL - 1), 0.0, 1.0)
	return 2 + roundi((per_side - 2) * t)

func put_enemy_on_tile(u: Unit, c: Vector2i) -> bool:
	if not tiles.has(c) or tiles[c].occupant != null:
		return false
	tiles[c].occupant = u
	u.coord = c
	u.position = grid_to_world(c)
	return true

var _in_prep := true

func _on_xp_changed(l: int, _x: int, _n: int):
	if _in_prep:
		refresh_unlocks(l, true)

func _on_phase_for_unlocks(p: int):
	_in_prep = (p == Events.Phase.PREP)
	if _in_prep:
		refresh_unlocks(player.level, true)

# A lobby fight (Arena): your half opens as many tiles as `home_level` gives, the enemy half exactly
# `enemy_open` (enemy-half coords: the mirror images of the tiles the other player has open, so their
# mirrored board always lands on open tiles; a PvE wave's own tiles).
func set_fight_unlocks(home_level: int, enemy_open: Array) -> void:
	var n: int = tiles_open_for_level(home_level)
	unlocked.clear()
	for i in player_order.size():
		if i < n:
			unlocked[player_order[i]] = true
	for c in enemy_open:
		if tiles.has(c) and not is_player_side(c):
			unlocked[c] = true
	for c in tiles:
		tiles[c].set_unlocked(unlocked.has(c), false)
	if visual:
		_build_border()
	_place_kings(false)

# The tiles of your half open at `level` (the lobby sends them with each fight).
func open_player_tiles(level: int) -> Array:
	var n: int = tiles_open_for_level(level)
	return player_order.slice(0, n)
