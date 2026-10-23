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
const BORDER_R := 0.95   # matches the tile mesh radius; lower it if the line sits outside the tile edge


var tile_scene: PackedScene = preload("res://scenes/Tiles.tscn")
var tiles := {}          # Vector2i -> Tile
var bench: Array[Unit]   # fixed size, null = empty
var unlocked := {}   # Vector2i -> true
var player_order: Array[Vector2i] = []
var enemy_order: Array[Vector2i] = []
var _border_mat: StandardMaterial3D
var theme: StringName = &""   # the board look (BoardThemes); set by apply_theme
var _bench_tiles: Array[Node3D] = []
var _sell_tile: Node3D
static var _prism: ArrayMesh   # the hex block every tile, bench slot and sell hex shares
static var _theme_mats := {}   # texture path -> material
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


func _ready():
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
	refresh_unlocks(GameState.me.level, false)
	Events.xp_changed.connect(_on_xp_changed)
	Events.phase_changed.connect(_on_phase_for_unlocks)
	_build_bench_slots()
	_build_sell_zone()
	apply_theme(BoardThemes.ORDER[1])   # until GameManager sets the run's theme
	
# Dresses the board in a theme (BoardThemes): every hex becomes a voxel block (the texture on top,
# the layers on its sides), board tiles pick one of three top variations by their coord, and the
# backdrop takes the theme's colour. Visual only.
func apply_theme(id: StringName) -> void:
	if not BoardThemes.has(id):
		id = BoardThemes.ORDER[1]
	theme = id
	for t in tiles.values():
		var c: Vector2i = t.coord
		var v := posmod(c.x * 7 + c.y * 13, BoardThemes.BOARD_VARIANTS) + 1
		_skin(t, "board_%d" % v, "board_side")
	for s in _bench_tiles:
		_skin(s, "bench", "bench_side")
	if _sell_tile != null:
		_skin(_sell_tile, "sell", "sell_side")
	RenderingServer.set_default_clear_color(BoardThemes.backdrop(id))

func _skin(node: Node3D, top: String, side: String) -> void:
	var mi := node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		return
	mi.mesh = hex_block()
	mi.material_override = null
	mi.set_surface_override_material(0, _theme_mat(BoardThemes.texture_path(theme, top)))
	mi.set_surface_override_material(1, _theme_mat(BoardThemes.texture_path(theme, side)))

static func _theme_mat(path: String) -> StandardMaterial3D:
	if not _theme_mats.has(path):
		var mat := StandardMaterial3D.new()
		if ResourceLoader.exists(path):
			mat.albedo_texture = load(path)
		else:
			mat.albedo_color = Color(0.45, 0.45, 0.5)   # textures missing: a plain grey block
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # every pixel a voxel
		mat.roughness = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_theme_mats[path] = mat
	return _theme_mats[path]

# A pointy-top hex block (same corners as the old 6-sided cylinder): surface 0 is the top, mapped
# flat onto the texture; surface 1 is the six sides, each showing the whole side texture.
static func hex_block() -> ArrayMesh:
	if _prism != null:
		return _prism
	var r := 0.95
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
func try_merge() -> bool:
	var groups := {}
	for u in all_player_units():
		if u.star >= 3:
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
		return true
	return false

func merge_all():
	while try_merge():
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
				GameState.me.items.append(item)
				returned = true
	var regrow := false
	for it in keeper.items:
		if best.has(it.id) and keeper.stacks_of(it) < int(best[it.id]):
			keeper.item_stacks[it.id] = best[it.id]
			regrow = true
	if regrow:
		keeper._recalc_items()
	if returned:
		Events.items_changed.emit()

# Puts a unit's items back in the inventory (selling, or a unit removed for lack of room).
func _return_items(u: Unit) -> void:
	var taken := u.take_items()
	if taken.is_empty():
		return
	GameState.me.items.append_array(taken)
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

func bench_to_world(i: int) -> Vector3:
	var w := HEX * sqrt(3.0)
	var board_center_x := w * ((COLS - 1) / 2.0 + 0.25)
	var start_x := board_center_x - w * (BENCH_SLOTS - 1) / 2.0
	return Vector3(start_x + i * w, 0.0, HEX * 1.5 * (ROWS + 1))

func would_complete_merge(d: UnitData) -> bool:
	var count := 0
	for u in all_player_units():
		if u.data == d and u.star == 1:
			count += 1
	return count >= 2

func merge_pending_unit(newbie: Unit):
	var copies: Array[Unit] = []
	for u in all_player_units():
		if u != newbie and u.data == newbie.data and u.star == 1:
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
	merge_all()

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
	u.position = bench_to_world(i)


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
	GameState.me.gold += refund
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

func refresh_unlocks(level: int, animate := true):
	var n: int = tiles_open_for_level(level)
	unlocked.clear()
	for order in [player_order, enemy_order]:
		for i in order.size():
			var c: Vector2i = order[i]
			var open: bool = i < n
			if open:
				unlocked[c] = true
			tiles[c].set_unlocked(open, animate)
	_build_border()

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
		refresh_unlocks(GameState.me.level, true)
