# voxel_tiles.gd
class_name VoxelTiles

# The voxel hex tiles from docs/hex-tile-design-plan.md: every hex is a real voxel block, 16 voxels across
# (flat to flat) and 4 voxels tall, the top layer's colour dripping over the sides. Each biome has the
# plain base tiles (the only ones units stand on), a bench and a sell hex, and the decor variants the
# background ring is made of: flowers, mossy stone, roots, standing stone, shrine and trees, each in
# the biome's own materials (BIOMES). tools/make_voxel_tiles.gd bakes them all into
# res://models/tiles/<biome>/<part>.res; the game only loads those (mesh()). Seeded, so a re-bake
# gives the same voxels. Vertex colours on two shared materials: lit (tres/voxel_solid.tres) and
# glowing (tres/voxel_glow.tres: crystals, lava, embers).
# A tile's outline is a true hexagon: the voxel tops are cut along its six sides and the sides are smooth
# walls coloured voxel by voxel, so neighbouring tiles (turned any sixth of a turn) fit edge to edge.

const SEAM := 0.025                        # each tile stops this short of its neighbour: a thin even gap between hexes
const HEX_A := 0.8660254 - SEAM            # centre to a flat side; the board's hexes are sqrt(3) apart (Board.HEX = 1)
const HEX_R := HEX_A / 0.8660254           # centre to a point, about 0.97
const ACROSS := 16                         # voxels flat to flat
const V := HEX_A * 2.0 / ACROSS            # one voxel, about 0.107 world units
const LAYERS := 4                          # tile depth in voxels
const TOP_Y := 0.005                       # the top face of a tile, as before (units stand on it)
const ROWS := 19                           # voxel rows point to point
const DIR := "res://models/tiles/%s/"
const SOLID := preload("res://tres/voxel_solid.tres")
const GLOW := preload("res://tres/voxel_glow.tres")

# The parts every biome bakes. base_* are the playable board (plain, three slight variations).
const BASES := ["base_1", "base_2", "base_3"]
const VARIANTS := ["flowers", "stone", "roots", "standing", "shrine"]
const TREES := ["tree_1", "tree_2"]
const PARTS := BASES + ["bench", "sell"] + VARIANTS + TREES

# Biome palettes and what each decor slot becomes there (the slot names follow the plan's Forest set).
# top / dirt / deep: ground colours; bench: plank colours; props: slot -> recipe name; trees: two
# recipe names; c: extra colours the recipes use. Order = BoardThemes.ORDER.
const BIOMES := {
	"forest": {"name": "Forest", "backdrop": "1b2a1d", "top": ["5f9e3a", "6aa842", "568f34", "73b44b"], "dirt": ["7a5230", "6b4527", "86603a"], "deep": "4d321c",
		"bench": ["8a5f36", "9a6c3f", "7a532f"], "props": {"flowers": "daisies", "stone": "boulders", "roots": "stump", "standing": "monolith", "shrine": "shrine"}, "trees": ["pine", "pine_big"],
		"c": {"stone": ["8e9097", "7d7f86", "a1a3a9"], "moss": "6f9e3d", "wood": ["7a4f2a", "5e3a1e"], "ring": "c8a26a", "crystal": ["4fa8ff", "8fd0ff"], "petal": "f4f4ee", "eye": "f2c94c", "leaf": ["2f6b3a", "3c7d43", "275a31"]}},
	"autumn": {"name": "Autumn", "backdrop": "2a1d14", "top": ["c98a2e", "d79a3a", "b97a26", "e0a84a"], "dirt": ["7a5230", "6b4527", "86603a"], "deep": "4d321c",
		"bench": ["8a5f36", "9a6c3f", "7a532f"], "props": {"flowers": "leaves", "stone": "boulders", "roots": "stump", "standing": "monolith", "shrine": "shrine"}, "trees": ["round_tree", "round_tree_big"],
		"c": {"stone": ["cbbf9f", "b8ab8a", "ddd2b4"], "moss": "a7612a", "wood": ["6b4424", "523218"], "ring": "d4ae74", "crystal": ["ffb347", "ffd9a0"], "petal": "d9572b", "eye": "f2c94c", "leaf": ["c8452a", "e0702c", "a83420"]}},
	"snow": {"name": "Snow", "backdrop": "1d2633", "top": ["dfe8f0", "d2dde8", "e8eff5", "c6d4e1"], "dirt": ["7a98b6", "6c8aa8", "89a6c2"], "deep": "5d7891",
		"bench": ["7d6a58", "8c7865", "6e5c4b"], "props": {"flowers": "ice_shards", "stone": "snow_boulders", "roots": "snow_stump", "standing": "ice_monolith", "shrine": "shrine"}, "trees": ["snow_pine", "snow_pine_big"],
		"c": {"stone": ["9fb4c8", "8aa1b7", "b6c8d8"], "moss": "f4f8fb", "wood": ["6b4f38", "524032"], "ring": "c9b49a", "crystal": ["7fd4ff", "d6f3ff"], "petal": "bfe9ff", "eye": "ffffff", "leaf": ["2c5a48", "376b55", "244b3c"]}},
	"swamp": {"name": "Swamp", "backdrop": "141a12", "top": ["4d5a2a", "56632f", "434f24", "5f6c35"], "dirt": ["4a3a22", "3f311c", "55432a"], "deep": "2c2214",
		"bench": ["5a4a32", "665539", "4e402b"], "props": {"flowers": "reeds", "stone": "boulders", "roots": "posts", "standing": "monolith", "shrine": "pool"}, "trees": ["swamp_tree", "dead_tree"],
		"c": {"stone": ["6f7364", "5f6355", "7f8373"], "moss": "5c7a2c", "wood": ["4e3a22", "3a2a17"], "ring": "8c7450", "crystal": ["5fd38a", "b6f5c8"], "water": ["3e5a4a", "4c6b58"], "petal": "6b4a2a", "eye": "8a6a3a", "leaf": ["3d5228", "4a6130", "33451f"]}},
	"volcano": {"name": "Volcano", "backdrop": "1a0d0b", "top": ["2a2626", "332e2d", "3d3735", "221f1f"], "dirt": ["3a2522", "2e1d1b", "45302b"], "deep": "1c1110",
		"bench": ["2a2323", "332b2b", "221c1c"], "props": {"flowers": "ash_piles", "stone": "magma_stone", "roots": "lava_pool", "standing": "obsidian", "shrine": "fire_shrine"}, "trees": ["dead_tree", "charred_tree"],
		"c": {"stone": ["3b3434", "2f2929", "4a4141"], "moss": "ff6a1f", "wood": ["1e1918", "2b2321"], "ring": "4a3b36", "crystal": ["ff5a1f", "ffc46b"], "lava": ["ff5a1f", "ffa53a", "ffd36b"], "ash": ["6f6a64", "5c5853", "86807a"], "petal": "6f6a64", "eye": "ff8a3c", "leaf": ["2b2321", "3a2f2c", "1e1918"]}},
	"cave": {"name": "Cave", "backdrop": "0f0e14", "top": ["4a4954", "52515d", "42414b", "5b5a66"], "dirt": ["35343d", "2e2d35", "3c3b45"], "deep": "1f1e25",
		"bench": ["4a3a2a", "564432", "3f3124"], "props": {"flowers": "bones", "stone": "boulders", "roots": "treasure", "standing": "stalagmite", "shrine": "shrine"}, "trees": ["stalagmite_big", "crystal_cluster"],
		"c": {"stone": ["5f5e6a", "53525d", "6d6c78"], "moss": "56556a", "wood": ["5a3d22", "6e4b2a"], "ring": "7a5a34", "crystal": ["6ff3ff", "e9fbff"], "gold": ["f2c14e", "c9962c"], "bone": ["e8e2d0", "cfc8b4"], "petal": "e8e2d0", "eye": "1a1410", "leaf": ["4a4954", "52515d", "42414b"]}},
	"mushroom": {"name": "Mushroom", "backdrop": "21140f", "top": ["9c3d2e", "8a6040", "b04a36", "7a5236"], "dirt": ["5a3a24", "4c311e", "66432a"], "deep": "33210f",
		"bench": ["6b4a2e", "7a5636", "5c3f27"], "props": {"flowers": "small_mushrooms", "stone": "boulders", "roots": "mud_pool", "standing": "mushroom_tall", "shrine": "shrine"}, "trees": ["mushroom_tree", "mushroom_tree_brown"],
		"c": {"stone": ["8a7f74", "7a7066", "9c9186"], "moss": "7a8a3a", "wood": ["e8dcc4", "cfc2a8"], "ring": "e8dcc4", "crystal": ["ff8fd8", "ffd0f0"], "cap": ["d0362a", "8a5a34"], "spot": "f4efe4", "water": ["6b5a3a", "7d6a46"], "petal": "f4efe4", "eye": "d0362a", "leaf": ["d0362a", "b02e24", "8a5a34"]}},
	"mushroom_cave": {"name": "Mushroom Cave", "backdrop": "100c18", "top": ["3f3a4c", "4a3f3a", "463f55", "3a3442"], "dirt": ["2e2a36", "28242f", "34303d"], "deep": "1a1720",
		"bench": ["4a3a2a", "564432", "3f3124"], "props": {"flowers": "glow_mushrooms", "stone": "boulders", "roots": "bones", "standing": "stalagmite", "shrine": "shrine"}, "trees": ["glow_mushroom_tree", "stalagmite_big"],
		"c": {"stone": ["55506a", "4a4560", "625c78"], "moss": "5a7ad0", "wood": ["d8d0e8", "bdb3d0"], "ring": "d8d0e8", "crystal": ["6fd8ff", "d8f6ff"], "cap": ["4fb8ff", "a774ff"], "spot": "e9fbff", "bone": ["e8e2d0", "cfc8b4"], "petal": "e8e2d0", "eye": "1a1410", "leaf": ["4fb8ff", "3a8ad0", "a774ff"]}},
	"jungle": {"name": "Jungle", "backdrop": "0f1a12", "top": ["4f7a3a", "587f40", "466e33", "608a47"], "dirt": ["5e4128", "523822", "6a4a2e"], "deep": "3a2716",
		"bench": ["6b4a2e", "7a5636", "5c3f27"], "props": {"flowers": "ferns", "stone": "vine_boulders", "roots": "vine_stump", "standing": "vine_monolith", "shrine": "shrine"}, "trees": ["jungle_tree", "jungle_tree_big"],
		"c": {"stone": ["7f8a7a", "6f7a6b", "8f9a8a"], "moss": "3f7a2c", "wood": ["5e4128", "4a3220"], "ring": "a88a5a", "crystal": ["5fff9a", "c8ffd9"], "vine": ["2f6a2a", "3d7f33"], "petal": "e04a6a", "eye": "f2c94c", "leaf": ["2f6a2a", "3d7f33", "285a24"]}},
	"desert": {"name": "Desert", "backdrop": "33251a", "top": ["e0bf7a", "d8b46c", "e8c98a", "cfa862"], "dirt": ["c49a5a", "b88d50", "d0a868"], "deep": "9c7444",
		"bench": ["9c7547", "a9804f", "8a663d"], "props": {"flowers": "dunes", "stone": "sand_boulders", "roots": "bones", "standing": "sand_pillar", "shrine": "shrine"}, "trees": ["cactus", "cactus_big"],
		"c": {"stone": ["c9a670", "b8955f", "d8b67f"], "moss": "e8c98a", "wood": ["8a663d", "6e5030"], "ring": "c9a670", "crystal": ["4fe0ff", "c8f8ff"], "bone": ["f2ecdc", "d9d0ba"], "cactus": ["4f8a3a", "5f9a45"], "petal": "f2ecdc", "eye": "1a1410", "leaf": ["4f8a3a", "5f9a45", "467a33"]}},
	"salt_flats": {"name": "Salt Flats", "backdrop": "2a2c32", "top": ["e8e6df", "dedbd2", "f2f0ea", "d4d1c7"], "dirt": ["b8b4aa", "aaa69c", "c6c2b8"], "deep": "8e8a80",
		"bench": ["8f8a80", "9c978c", "827d73"], "props": {"flowers": "salt_piles", "stone": "salt_boulders", "roots": "vulture_bones", "standing": "salt_pillar", "shrine": "salt_pool"}, "trees": ["salt_spire", "shimmer"],
		"c": {"stone": ["cfcbc0", "bfbbb0", "ddd9cf"], "moss": "f7f5f0", "wood": ["9c978c", "827d73"], "ring": "cfcbc0", "crystal": ["d6f6ff", "ffffff"], "bone": ["f7f3e8", "ddd6c4"], "water": ["9fc4c8", "b6d6d8"], "petal": "ffffff", "eye": "1a1410", "leaf": ["f7f5f0", "e8e6df", "ffffff"]}},
	"parasitic": {"name": "Parasitic", "backdrop": "1c0a10", "top": ["8a3a4a", "9c4554", "7a3040", "a85060"], "dirt": ["5a1f2a", "4c1a24", "662532"], "deep": "331018",
		"bench": ["5a2a30", "66303a", "4e2429"], "props": {"flowers": "pustules", "stone": "flesh_growth", "roots": "blood_pool", "standing": "bone_spire", "shrine": "eye_shrine"}, "trees": ["tendril", "tendril_big"],
		"c": {"stone": ["c87a84", "b06a74", "d88a94"], "moss": "5a1f2a", "wood": ["e8d8cc", "cfc0b4"], "ring": "e8d8cc", "crystal": ["ff3b5a", "ffb0c0"], "blood": ["9c1a2a", "b8222f", "7a121e"], "bone": ["e8d8cc", "cfc0b4"], "petal": "d86a7a", "eye": "ffe066", "leaf": ["a85060", "c86a7a", "8a3a4a"]}},
}

# The baked mesh for a biome's part (see PARTS), or null when it isn't baked.
static func mesh(biome: String, part: String) -> Mesh:
	var p := (DIR % biome) + part + ".res"
	return load(p) as Mesh if ResourceLoader.exists(p) else null

# --- building (the bake tool calls make()) ---------------------------------------------------------

# A voxel grid: Vector3i(i, j, k) -> Color, i across (x), j up (0-3 the tile, 4+ props), k along (z).
class Grid:
	var cells := {}
	var glow := {}
	func put(i: int, j: int, k: int, c: Color, glows := false) -> void:
		var p := Vector3i(i, j, k)
		cells[p] = c
		if glows:
			glow[p] = true
		else:
			glow.erase(p)
	func has(i: int, j: int, k: int) -> bool:
		return cells.has(Vector3i(i, j, k))
	func top(i: int, k: int) -> int:   # the highest filled layer in a column, -1 if empty
		for j in range(30, -1, -1):
			if cells.has(Vector3i(i, j, k)):
				return j
		return -1

# Builds the mesh: one quad per visible voxel face, solid and glowing faces in separate surfaces. A tile
# (not `centered`) is cut to the hexagon: voxels outside it are dropped, faces crossing its sides are
# clipped, and smooth walls (_walls) close the six sides.
static func build(g: Grid, size := V, centered := false) -> ArrayMesh:
	var faces := [
		[Vector3i(0, 1, 0), [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)], 1.0],
		[Vector3i(0, -1, 0), [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)], 0.55],
		[Vector3i(1, 0, 0), [Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)], 0.82],
		[Vector3i(-1, 0, 0), [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)], 0.82],
		[Vector3i(0, 0, 1), [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)], 0.9],
		[Vector3i(0, 0, -1), [Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)], 0.72],
	]
	var tools := [SurfaceTool.new(), SurfaceTool.new()]
	var used := [false, false]
	for st in tools:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := Vector3(-ACROSS * 0.5 * V, TOP_Y - LAYERS * V, -ROWS * 0.5 * V)
	if centered:   # a model: centred on x and z, standing on y = 0
		var lo := Vector3i(9999, 9999, 9999)
		var hi := Vector3i(-9999, -9999, -9999)
		for p in g.cells:
			lo = lo.min(p)
			hi = hi.max(p)
		origin = -Vector3((lo.x + hi.x + 1) * 0.5, lo.y, (lo.z + hi.z + 1) * 0.5) * size
	else:
		var cols := hex_columns()
		for p: Vector3i in g.cells.keys():
			if not cols.has(Vector2i(p.x, p.z)):
				g.cells.erase(p)   # outside the hexagon
				g.glow.erase(p)
	for p in g.cells:
		var c: Color = g.cells[p]
		var s := 1 if g.glow.has(p) else 0
		for f in faces:
			var d: Vector3i = f[0]
			var n: Vector3i = p + d
			if g.cells.has(n):
				continue
			if d.y == -1 and p.y == 0 and not centered:
				continue   # the underside of a tile is never seen
			var st: SurfaceTool = tools[s]
			var shade := c if s == 1 else Color(c.r * f[2], c.g * f[2], c.b * f[2], c.a)
			var q: Array = f[1]
			var corners: Array[Vector3] = []
			var ao: Array[float] = []
			for v in q:
				corners.append(origin + (Vector3(p) + v) * size)
				ao.append(1.0 if s == 1 else _corner_ao(g, n, d, v))
			var inside := centered or _inside(corners)
			if not inside:
				var cut := _clip(corners, ao)
				corners = cut[0]
				ao = cut[1]
			if not centered and (corners.size() < 3 or (d.y == 0 and _on_side(corners))):
				continue   # outside, or lying on a side, where the wall is
			if not inside:
				used[s] = true
				for t in range(1, corners.size() - 1):   # the cut face is convex: a fan
					for idx in [0, t, t + 1]:
						_vert(st, Vector3(d), shade, ao[idx], corners[idx])
				continue
			used[s] = true
			# split the quad along the diagonal whose ends are lit alike, so the darkening doesn't smear
			var order := [0, 1, 2, 0, 2, 3] if ao[0] + ao[2] >= ao[1] + ao[3] else [0, 1, 3, 1, 2, 3]
			for idx in order:
				_vert(st, Vector3(d), shade, ao[idx], corners[idx])
	if not centered:
		_walls(g, origin, tools, used)
	var mesh := ArrayMesh.new()
	for s in 2:
		if used[s]:
			tools[s].index()
			tools[s].commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, SOLID if s == 0 else GLOW)
	return mesh

static func _vert(st: SurfaceTool, normal: Vector3, c: Color, ao: float, pos: Vector3) -> void:
	st.set_normal(normal)
	st.set_color(Color(c.r * ao, c.g * ao, c.b * ao, c.a))
	st.add_vertex(pos)

# --- the hexagon outline ----------------------------------------------------------------------------

# The six sides' outward normals in x / z (pointy-top like the board: points towards +-z, flat sides at
# +-x). Side m runs from corner m to corner m + 1 (corner m is at m * 60 degrees from +z).
const SIDES := [Vector2(0.5, 0.8660254), Vector2(1.0, 0.0), Vector2(0.5, -0.8660254), Vector2(-0.5, -0.8660254), Vector2(-1.0, 0.0), Vector2(-0.5, 0.8660254)]
const EPS := 0.000001

static func _corner(m: int) -> Vector2:
	var a := m * TAU / 6.0
	return Vector2(sin(a), cos(a)) * HEX_R

# How far outside side m a point is (negative = inside).
static func _out(m: int, p: Vector3) -> float:
	var n: Vector2 = SIDES[m]
	return n.x * p.x + n.y * p.z - HEX_A

static func _inside(pts: Array[Vector3]) -> bool:
	for p in pts:
		for m in 6:
			if _out(m, p) > EPS:
				return false
	return true

# A vertical face lying on one of the sides (the wall covers it there).
static func _on_side(pts: Array[Vector3]) -> bool:
	var mid := Vector3.ZERO
	for p in pts:
		mid += p
	mid /= pts.size()
	for m in 6:
		if _out(m, mid) > -0.0001:
			return true
	return false

# Cuts a face (a convex polygon, with its corner shading) to the hexagon, one side at a time
# (Sutherland-Hodgman). Returns [points, shading].
static func _clip(pts: Array[Vector3], ao: Array[float]) -> Array:
	for m in 6:
		var out_p: Array[Vector3] = []
		var out_a: Array[float] = []
		for i in pts.size():
			var cur := pts[i]
			var prev := pts[i - 1]
			var dc := _out(m, cur)
			var dp := _out(m, prev)
			if (dc <= EPS) != (dp <= EPS):   # crosses the side: add the crossing
				var t := dp / (dp - dc)
				out_p.append(prev.lerp(cur, t))
				out_a.append(lerpf(ao[i - 1], ao[i], t))
			if dc <= EPS:
				out_p.append(cur)
				out_a.append(ao[i])
		pts = out_p
		ao = out_a
		if pts.size() < 3:
			break
	return [pts, ao]

# The six smooth sides. Each side is cut where it crosses the voxel grid, so every piece lies in one
# column; that piece is walled for every voxel in the column, one band per voxel in its colour (so the
# top colour dripping over the edge shows on the walls, and a frame or a cut prop is closed off).
static func _walls(g: Grid, origin: Vector3, tools: Array, used: Array) -> void:
	for m in 6:
		var a := _corner(m)
		var b := _corner(m + 1)
		var n: Vector2 = SIDES[m]
		var normal := Vector3(n.x, 0.0, n.y)
		var face := n.x * n.x * 0.82 + n.y * n.y * (0.9 if n.y > 0.0 else 0.72)   # the voxel side faces' shading, blended
		var cuts: Array[float] = [0.0, 1.0]
		for i in ACROSS + 1:
			var x := origin.x + i * V
			if (a.x - x) * (b.x - x) < 0.0:
				cuts.append((x - a.x) / (b.x - a.x))
		for k in ROWS + 1:
			var z := origin.z + k * V
			if (a.y - z) * (b.y - z) < 0.0:
				cuts.append((z - a.y) / (b.y - a.y))
		cuts.sort()
		# the top edge runs along up x normal, the way the voxel side faces wind
		var flip := Vector3(b.x - a.x, 0.0, b.y - a.y).dot(Vector3.UP.cross(normal)) < 0.0
		for c in cuts.size() - 1:
			var t0 := cuts[c]
			var t1 := cuts[c + 1]
			if t1 - t0 < 0.0001:
				continue
			var p0 := a.lerp(b, t1 if flip else t0)
			var p1 := a.lerp(b, t0 if flip else t1)
			var mid := a.lerp(b, (t0 + t1) * 0.5) - n * 0.001
			var col := Vector2i(floori((mid.x - origin.x) / V), floori((mid.y - origin.z) / V))
			for j in range(0, 30):
				var cell := Vector3i(col.x, j, col.y)
				if not g.cells.has(cell):
					continue
				var s := 1 if g.glow.has(cell) else 0
				var c0: Color = g.cells[cell]
				var shade := c0 if s == 1 else Color(c0.r * face, c0.g * face, c0.b * face, c0.a)
				var y0 := origin.y + j * V
				var y1 := y0 + V
				var q := [Vector3(p0.x, y1, p0.y), Vector3(p1.x, y1, p1.y), Vector3(p1.x, y0, p1.y), Vector3(p0.x, y0, p0.y)]
				used[s] = true
				for idx in [0, 1, 2, 0, 2, 3]:
					_vert(tools[s], normal, shade, 1.0, q[idx])

# Baked ambient occlusion for one corner of a face: the three voxels that touch the corner in the layer the
# face looks into (`n` is the cell in front of the face, `v` the corner in the unit cube). Corners tucked
# into creases and under overhangs come out darker; an open corner keeps its colour. Glowing voxels skip it.
const AO_LEVELS := [0.58, 0.72, 0.86, 1.0]   # 3, 2, 1 or 0 neighbours (two sides = fully tucked)

static func _corner_ao(g: Grid, n: Vector3i, d: Vector3i, v: Vector3) -> float:
	var axes: Array[Vector3i] = []
	for a: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]:
		if a.x * d.x + a.y * d.y + a.z * d.z == 0:   # an axis along the face, not through it
			var along: float = v.x * a.x + v.y * a.y + v.z * a.z   # 0 or 1: which side of the face this corner is on
			axes.append(a if along > 0.5 else -a)
	var side1 := g.cells.has(n + axes[0])
	var side2 := g.cells.has(n + axes[1])
	var corner := g.cells.has(n + axes[0] + axes[1])
	if side1 and side2:
		return AO_LEVELS[0]
	return AO_LEVELS[3 - int(side1) - int(side2) - int(corner)]

# The voxel columns the hexagon covers (any part of; the ones on its sides are cut by build()).
static var _hex_cache := {}

static func hex_columns() -> Dictionary:
	if not _hex_cache.is_empty():
		return _hex_cache
	var out := _hex_cache
	for i in ACROSS:
		for k in ROWS:
			var x0 := (i - ACROSS * 0.5) * V
			var z0 := (k - ROWS * 0.5) * V
			var sq: Array[Vector3] = [Vector3(x0, 0, z0), Vector3(x0 + V, 0, z0), Vector3(x0 + V, 0, z0 + V), Vector3(x0, 0, z0 + V)]
			var cut: Array = _clip(sq, [1.0, 1.0, 1.0, 1.0] as Array[float])
			if _area(cut[0]) > V * V * 0.0001:   # not just a speck
				out[Vector2i(i, k)] = true
	return out

static func _area(pts: Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p: Vector3 = pts[i - 1]
		var q: Vector3 = pts[i]
		a += p.x * q.z - q.x * p.z
	return absf(a) * 0.5

# How many voxels in from the hexagon's nearest side a column's centre is (below 0.5: a cut column).
static func _depth(col: Vector2i) -> float:
	var c := Vector3((col.x + 0.5 - ACROSS * 0.5) * V, 0.0, (col.y + 0.5 - ROWS * 0.5) * V)
	var worst := -INF
	for m in 6:
		worst = maxf(worst, _out(m, c))
	return -worst / V

static func _cols(list: Array) -> Array:
	var out: Array = []
	for s in list:
		out.append(Color(s))
	return out

# The plain tile: noisy top colours, the top layer dripping over the edge, darker earth below.
static func base(def: Dictionary, rng: RandomNumberGenerator, tufts: int) -> Grid:
	var g := Grid.new()
	var cols := hex_columns()
	var top := _cols(def.top)
	var dirt := _cols(def.dirt)
	var deep := Color(def.deep)
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.22
	for c in cols:
		var col: Vector2i = c
		var edge := _depth(col) < 1.0   # the outer ring of columns, whose sides are the tile's walls
		var v :=(n.get_noise_2d(col.x, col.y) + 1.0) * 0.5
		var tc: Color = top[clampi(int(v * top.size()), 0, top.size() - 1)]
		g.put(col.x, 3, col.y, tc)
		for j in range(0, 3):
			var c2: Color = dirt[(col.x * 3 + col.y * 5 + j) % dirt.size()]
			if j == 0:
				c2 = deep
			if edge and j == 2 and rng.randf() < 0.6:
				c2 = top[rng.randi_range(0, top.size() - 1)].darkened(0.08)   # the drip
			elif edge and j == 1 and rng.randf() < 0.18:
				c2 = top[0].darkened(0.15)
			g.put(col.x, j, col.y, c2)
	for t in tufts:
		var spot := _spot(rng, 3)
		g.put(spot.x, 4, spot.y, top[3].lightened(0.06))
	return g

# A random column well in from the edge (about `margin` voxels round its sides, half that on the diagonals).
static func _spot(rng: RandomNumberGenerator, margin: int) -> Vector2i:
	for tries in 40:
		var p := Vector2i(rng.randi_range(margin, ACROSS - 1 - margin), rng.randi_range(margin + 1, ROWS - 2 - margin))
		if hex_columns().has(p) and _depth(p) >= margin * 0.5:
			return p
	return Vector2i(ACROSS / 2, ROWS / 2)

# One part of one biome, built from scratch (the bake tool saves it).
static func make(biome: String, part: String) -> ArrayMesh:
	var def: Dictionary = BIOMES[biome]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(biome + ":" + part)
	var g: Grid
	if part.begins_with("base"):
		g = base(def, rng, rng.randi_range(1, 3))
	elif part == "bench":
		g = base(def, rng, 0)
		_bench(g, def)
	elif part == "sell":
		g = base(def, rng, 0)
		_sell(g, def)
	else:
		g = base(def, rng, rng.randi_range(2, 4))
		var recipe: String = def.props.get(part, "")
		if part.begins_with("tree"):
			recipe = def.trees[0 if part == "tree_1" else 1]
		Props.add(g, recipe, def, rng)
	return build(g)

# The bench: the biome's own ground, a little lighter, inside a raised frame in the biome's bench colour
# (wood or stone), with a darker inner line: it matches the board but reads as a bench at a glance.
static func _bench(g: Grid, def: Dictionary) -> void:
	var frame := _cols(def.bench)
	for p in g.cells.keys():
		if p.y == 3:
			g.cells[p] = (g.cells[p] as Color).lightened(0.1)
	for c in hex_columns():
		var col: Vector2i = c
		var d := _depth(col)   # the frame follows the hexagon's sides, so its outside is as smooth as theirs
		if d < 1.0:
			g.put(col.x, 4, col.y, frame[(col.x + col.y) % frame.size()])
		elif d < 2.0:
			g.put(col.x, 3, col.y, frame[2 % frame.size()].darkened(0.3))   # the frame's inner line, flush with the ground

# The sell hex: the ground tinted red under a raised gold coin.
static func _sell(g: Grid, def: Dictionary) -> void:
	for p in g.cells.keys():
		g.cells[p] = (g.cells[p] as Color).lerp(Color("b8322a"), 0.55).darkened(0.15)
	var gold := Color("f2c14e")
	for c in hex_columns():
		var col: Vector2i = c
		var d := Vector2(col.x - 7.5, (col.y - 9.0) * 0.9).length()
		if d <= 4.2:
			g.put(col.x, 4, col.y, gold if d < 3.2 else gold.darkened(0.25))
	for k in range(7, 12):
		g.put(7, 5, k, gold.darkened(0.3))
		g.put(8, 5, k, gold.darkened(0.3))

# --- props: what sits on a decor tile ----------------------------------------------------------------

class Props:
	static func add(g: Grid, recipe: String, def: Dictionary, rng: RandomNumberGenerator) -> void:
		var c: Dictionary = def.c
		match recipe:
			"daisies": _flowers(g, rng, Color(c.petal), Color(c.eye), Color(def.top[2]).darkened(0.2), 4)
			"leaves": _scatter(g, rng, VoxelTiles._cols(c.leaf), 14, 4)
			"ice_shards": _shards(g, rng, VoxelTiles._cols(c.crystal), 4, false)
			"reeds": _reeds(g, rng, Color(def.top[0]).darkened(0.2), Color(c.petal), 6)
			"ash_piles": _piles(g, rng, VoxelTiles._cols(c.ash), 2, 3)
			"bones": _bones(g, rng, VoxelTiles._cols(c.bone))
			"vulture_bones": _bones(g, rng, VoxelTiles._cols(c.bone))
			"small_mushrooms": _mushrooms(g, rng, VoxelTiles._cols(c.cap), Color(c.spot), Color(c.wood[0]), 4, false)
			"glow_mushrooms": _mushrooms(g, rng, VoxelTiles._cols(c.cap), Color(c.spot), Color(c.wood[0]), 5, true)
			"ferns": _bushes(g, rng, VoxelTiles._cols(c.leaf), 4)
			"dunes": _dunes(g, rng, Color(def.top[2]), Color(def.top[3]))
			"salt_piles": _piles(g, rng, VoxelTiles._cols(c.stone) + [Color("ffffff")], 3, 3)
			"pustules": _pustules(g, rng, VoxelTiles._cols(c.stone), Color(c.crystal[0]))
			"boulders": _boulders(g, rng, VoxelTiles._cols(c.stone), Color(c.moss), 0.45)
			"snow_boulders": _boulders(g, rng, VoxelTiles._cols(c.stone), Color("f4f8fb"), 0.7)
			"vine_boulders": _boulders(g, rng, VoxelTiles._cols(c.stone), Color(c.vine[0]), 0.6)
			"sand_boulders": _boulders(g, rng, VoxelTiles._cols(c.stone), Color(def.top[2]), 0.3)
			"salt_boulders": _boulders(g, rng, VoxelTiles._cols(c.stone), Color("ffffff"), 0.5)
			"magma_stone": _boulders(g, rng, VoxelTiles._cols(c.stone), Color(c.lava[1]), 0.3, true)
			"flesh_growth": _boulders(g, rng, VoxelTiles._cols(c.stone), Color(c.blood[0]), 0.5)
			"stump": _stump(g, rng, VoxelTiles._cols(c.wood), Color(c.ring), Color(c.moss), null)
			"snow_stump": _stump(g, rng, VoxelTiles._cols(c.wood), Color(c.ring), Color("f4f8fb"), null)
			"vine_stump": _stump(g, rng, VoxelTiles._cols(c.wood), Color(c.ring), Color(c.vine[0]), Color(c.vine[1]))
			"posts": _posts(g, rng, VoxelTiles._cols(c.wood), Color(c.moss), VoxelTiles._cols(c.water))
			"treasure": _treasure(g, rng, VoxelTiles._cols(c.wood), VoxelTiles._cols(c.gold))
			"lava_pool": _pool(g, rng, VoxelTiles._cols(c.lava), true, Color(c.stone[0]))
			"mud_pool": _pool(g, rng, VoxelTiles._cols(c.water), false, Color(def.top[1]).darkened(0.2))
			"blood_pool": _pool(g, rng, VoxelTiles._cols(c.blood), false, Color(c.stone[0]))
			"pool": _pool(g, rng, VoxelTiles._cols(c.water), false, Color(c.moss))
			"salt_pool": _pool(g, rng, VoxelTiles._cols(c.water), false, Color("ffffff"))
			"monolith": _pillar(g, rng, VoxelTiles._cols(c.stone), Color(c.moss), 12, 3, 0.18)
			"ice_monolith": _pillar(g, rng, VoxelTiles._cols(c.crystal) + [Color("e8f6ff")], Color("ffffff"), 12, 3, 0.3)
			"vine_monolith": _pillar(g, rng, VoxelTiles._cols(c.stone), Color(c.vine[1]), 12, 3, 0.4)
			"sand_pillar": _pillar(g, rng, VoxelTiles._cols(c.stone), Color(def.top[0]), 11, 3, 0.15)
			"salt_pillar": _pillar(g, rng, VoxelTiles._cols(c.stone) + [Color("ffffff")], Color("ffffff"), 11, 3, 0.2)
			"obsidian": _pillar(g, rng, [Color("1a1418"), Color("261e24"), Color("120e12")], Color(c.lava[0]), 12, 3, 0.12, true)
			"bone_spire": _pillar(g, rng, VoxelTiles._cols(c.bone), Color(c.blood[0]), 12, 2, 0.25)
			"stalagmite": _spike(g, rng, VoxelTiles._cols(c.stone), 11)
			"mushroom_tall": _mushroom_tree(g, rng, Color(c.wood[0]), Color(c.cap[0]), Color(c.spot), 9, 3, false)
			"shrine": _shrine(g, rng, VoxelTiles._cols(c.stone), VoxelTiles._cols(c.crystal))
			"fire_shrine": _shrine(g, rng, VoxelTiles._cols(c.stone), VoxelTiles._cols(c.crystal))
			"eye_shrine": _eye(g, rng, VoxelTiles._cols(c.bone), Color(c.crystal[0]), Color(c.eye))
			"pine": _pine(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), null, 14)
			"pine_big": _pine(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), null, 17)
			"snow_pine": _pine(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), Color("f7fafc"), 14)
			"snow_pine_big": _pine(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), Color("f7fafc"), 17)
			"round_tree": _round_tree(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), 9, 4)
			"round_tree_big": _round_tree(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), 11, 5)
			"jungle_tree": _jungle_tree(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), VoxelTiles._cols(c.vine), 12)
			"jungle_tree_big": _jungle_tree(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), VoxelTiles._cols(c.vine), 15)
			"swamp_tree": _jungle_tree(g, rng, Color(c.wood[0]), VoxelTiles._cols(c.leaf), [Color(c.moss), Color(c.moss).darkened(0.2)], 11)
			"dead_tree": _dead_tree(g, rng, VoxelTiles._cols(c.wood), null, 12)
			"charred_tree": _dead_tree(g, rng, VoxelTiles._cols(c.wood), Color(c.lava[0]), 13)
			"stalagmite_big": _spike(g, rng, VoxelTiles._cols(c.stone), 15)
			"crystal_cluster": _shards(g, rng, VoxelTiles._cols(c.crystal), 5, true)
			"mushroom_tree": _mushroom_tree(g, rng, Color(c.wood[0]), Color(c.cap[0]), Color(c.spot), 11, 5, false)
			"mushroom_tree_brown": _mushroom_tree(g, rng, Color(c.wood[0]), Color(c.cap[1]), Color(c.spot), 10, 4, false)
			"glow_mushroom_tree": _mushroom_tree(g, rng, Color(c.wood[0]), Color(c.cap[0]), Color(c.spot), 11, 5, true)
			"cactus": _cactus(g, rng, VoxelTiles._cols(c.cactus), 9)
			"cactus_big": _cactus(g, rng, VoxelTiles._cols(c.cactus), 12)
			"salt_spire": _spike(g, rng, VoxelTiles._cols(c.stone) + [Color("ffffff")], 13)
			"shimmer": _sparkle(g, rng, Color(c.crystal[1]))
			"tendril": _tendril(g, rng, VoxelTiles._cols(c.leaf), Color(c.crystal[0]), 12)
			"tendril_big": _tendril(g, rng, VoxelTiles._cols(c.leaf), Color(c.crystal[0]), 15)

	static func _col(cols: Array, rng: RandomNumberGenerator) -> Color:
		return cols[rng.randi_range(0, cols.size() - 1)]

	static func _ground(g: VoxelTiles.Grid, i: int, k: int) -> int:
		return maxi(g.top(i, k), 3) + 1   # the first free layer above the tile in that column

	# White daisies: a raised plus of petals round a yellow eye, on a short stem.
	static func _flowers(g: VoxelTiles.Grid, rng: RandomNumberGenerator, petal: Color, eye: Color, stem: Color, count: int) -> void:
		for n in count:
			var p := VoxelTiles._spot(rng, 3)
			g.put(p.x, 4, p.y, stem)
			g.put(p.x, 5, p.y, eye)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				g.put(p.x + d.x, 5, p.y + d.y, petal)

	static func _scatter(g: VoxelTiles.Grid, rng: RandomNumberGenerator, cols: Array, count: int, j: int) -> void:
		for n in count:
			var p := VoxelTiles._spot(rng, 2)
			g.put(p.x, j, p.y, _col(cols, rng))

	static func _shards(g: VoxelTiles.Grid, rng: RandomNumberGenerator, cols: Array, count: int, glows: bool) -> void:
		for n in count:
			var p := VoxelTiles._spot(rng, 3)
			var h := rng.randi_range(2, 5) if glows else rng.randi_range(1, 3)
			var lean := rng.randi_range(-1, 1)
			for j in h:
				g.put(p.x + (lean if j >= h - 1 and h > 2 else 0), 4 + j, p.y, cols[0] if j < h - 1 else cols[1], glows)

	static func _reeds(g: VoxelTiles.Grid, rng: RandomNumberGenerator, stalk: Color, tip: Color, count: int) -> void:
		for n in count:
			var p := VoxelTiles._spot(rng, 2)
			var h := rng.randi_range(3, 5)
			for j in h:
				g.put(p.x, 4 + j, p.y, stalk)
			g.put(p.x, 4 + h, p.y, tip)

	static func _piles(g: VoxelTiles.Grid, rng: RandomNumberGenerator, cols: Array, count: int, size: int) -> void:
		for n in count:
			var p := VoxelTiles._spot(rng, size + 1)
			for j in size:
				var r := size - j
				for di in range(-r + 1, r):
					for dk in range(-r + 1, r):
						if absi(di) + absi(dk) < r + 1:
							g.put(p.x + di, 4 + j, p.y + dk, _col(cols, rng))

	static func _bones(g: VoxelTiles.Grid, rng: RandomNumberGenerator, cols: Array) -> void:
		var p := VoxelTiles._spot(rng, 4)
		for di in 2:   # a skull with dark eyes
			for dk in 2:
				for j in 2:
					g.put(p.x + di, 4 + j, p.y + dk, cols[0])
		g.put(p.x, 5, p.y + 2, Color("1a1410"))
		g.put(p.x + 1, 5, p.y + 2, Color("1a1410"))
		var q := VoxelTiles._spot(rng, 3)
		for t in 5:   # a rib or two
			g.put(q.x + t - 2, 4, q.y, cols[1])
			if t % 2 == 0:
				g.put(q.x + t - 2, 4, q.y + 1, cols[1])
				g.put(q.x + t - 2, 4, q.y - 1, cols[1])

	static func _mushrooms(g: VoxelTiles.Grid, rng: RandomNumberGenerator, caps: Array, spot: Color, stem: Color, count: int, glows: bool) -> void:
		for n in count:
			var p := VoxelTiles._spot(rng, 3)
			var h := rng.randi_range(1, 2)
			for j in h:
				g.put(p.x, 4 + j, p.y, stem)
			var cap: Color = _col(caps, rng)
			for di in range(-1, 2):
				for dk in range(-1, 2):
					g.put(p.x + di, 4 + h, p.y + dk, spot if (di == 0 and dk == 1 and not glows) else cap, glows)

	static func _bushes(g: VoxelTiles.Grid, rng: RandomNumberGenerator, cols: Array, count: int) -> void:
		for n in count:
			var p := VoxelTiles._spot(rng, 3)
			for di in range(-1, 2):
				for dk in range(-1, 2):
					if rng.randf() < 0.8:
						g.put(p.x + di, 4, p.y + dk, _col(cols, rng))
			g.put(p.x, 5, p.y, _col(cols, rng))
			if rng.randf() < 0.5:
				g.put(p.x + 1, 5, p.y, _col(cols, rng))

	static func _dunes(g: VoxelTiles.Grid, rng: RandomNumberGenerator, a: Color, b: Color) -> void:
		var off := rng.randi_range(0, 5)
		for c in VoxelTiles.hex_columns():
			var col: Vector2i = c
			if (col.x + col.y * 2 + off) % 7 == 0:
				g.put(col.x, 4, col.y, a if col.x % 2 == 0 else b)

	static func _pustules(g: VoxelTiles.Grid, rng: RandomNumberGenerator, cols: Array, core: Color) -> void:
		for n in 3:
			var p := VoxelTiles._spot(rng, 3)
			for di in range(-1, 2):
				for dk in range(-1, 2):
					g.put(p.x + di, 4, p.y + dk, cols[0])
			g.put(p.x, 5, p.y, core, true)

	static func _boulders(g: VoxelTiles.Grid, rng: RandomNumberGenerator, stone: Array, moss: Color, moss_chance: float, glowing_moss := false) -> void:
		var sizes := [[5, 4, 4], [3, 3, 3]]
		for s in sizes:
			var p := VoxelTiles._spot(rng, 4)
			for di in s[0]:
				for dk in s[1]:
					for j in s[2]:
						if (di == 0 or di == s[0] - 1) and (dk == 0 or dk == s[1] - 1) and j == s[2] - 1:
							continue   # rounded top corners
						var on_top: bool = j == s[2] - 1 or (j == s[2] - 2 and (di == 0 or di == s[0] - 1) and (dk == 0 or dk == s[1] - 1))
						var mossy: bool = on_top and rng.randf() < moss_chance
						g.put(p.x + di - 1, 4 + j, p.y + dk - 1, moss if mossy else _col(stone, rng), mossy and glowing_moss)

	static func _stump(g: VoxelTiles.Grid, rng: RandomNumberGenerator, wood: Array, ring: Color, moss: Color, vine) -> void:
		var cx := 7
		var ck := 9
		for di in range(-3, 4):
			for dk in range(-3, 4):
				if di * di + dk * dk > 8:
					continue
				for j in 4:
					var c: Color = wood[0] if (di + dk + j) % 3 else wood[1]
					if j == 3:
						c = ring if di * di + dk * dk <= 4 else wood[1]
					g.put(cx + di, 4 + j, ck + dk, c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1)]:   # roots
			for t in range(3, 8):
				var c: Color = moss if rng.randf() < 0.35 else wood[1]
				g.put(cx + d.x * t, 4, ck + d.y * t, c)
		if vine != null:
			for j in 3:
				g.put(cx + 3, 4 + j, ck, vine)
				g.put(cx - 2, 4 + j, ck - 2, vine)

	static func _posts(g: VoxelTiles.Grid, rng: RandomNumberGenerator, wood: Array, moss: Color, water: Array) -> void:
		_pool(g, rng, water, false, moss)
		for n in 3:
			var p := VoxelTiles._spot(rng, 3)
			var h := rng.randi_range(4, 7)
			for j in h:
				g.put(p.x, 4 + j, p.y, wood[j % 2])
				if rng.randf() < 0.3:
					g.put(p.x + 1, 4 + j, p.y, moss)

	static func _treasure(g: VoxelTiles.Grid, rng: RandomNumberGenerator, wood: Array, gold: Array) -> void:
		var p := Vector2i(6, 8)
		for di in 4:
			for dk in 3:
				for j in 3:
					var band := j == 1 or di == 0 or di == 3
					g.put(p.x + di, 4 + j, p.y + dk, gold[1] if band and j == 1 else wood[0 if j < 2 else 1])
		g.put(p.x + 1, 5, p.y + 3, gold[0])
		for n in 8:   # coins spilling out
			var q := VoxelTiles._spot(rng, 3)
			g.put(q.x, 4, q.y, gold[n % 2])

	static func _pool(g: VoxelTiles.Grid, rng: RandomNumberGenerator, liquid: Array, glows: bool, rim: Color) -> void:
		var cx := rng.randi_range(6, 9)
		var ck := rng.randi_range(8, 10)
		for c in VoxelTiles.hex_columns():
			var col: Vector2i = c
			var d := Vector2(col.x - cx, (col.y - ck) * 0.85).length()
			if d <= 3.6:
				g.put(col.x, 3, col.y, liquid[(col.x + col.y) % liquid.size()], glows)
			elif d <= 4.4 and rng.randf() < 0.6:
				g.put(col.x, 4, col.y, rim)

	static func _pillar(g: VoxelTiles.Grid, rng: RandomNumberGenerator, stone: Array, accent: Color, h: int, w: int, accent_chance: float, accent_glows := false) -> void:
		var cx := 6
		var ck := 8
		for j in h:
			var ww := w if j < h - 2 else w - 1
			for di in ww:
				for dk in ww:
					var acc := rng.randf() < accent_chance
					g.put(cx + di, 4 + j, ck + dk, accent if acc else _col(stone, rng), acc and accent_glows)
		for n in 3:   # rubble at its foot
			var q := VoxelTiles._spot(rng, 3)
			g.put(q.x, 4, q.y, _col(stone, rng))

	static func _spike(g: VoxelTiles.Grid, rng: RandomNumberGenerator, stone: Array, h: int) -> void:
		var cx := 7
		var ck := 9
		for j in h:
			var r := 2 if j < h / 3 else (1 if j < h * 2 / 3 else 0)
			for di in range(-r, r + 1):
				for dk in range(-r, r + 1):
					if absi(di) + absi(dk) <= r + (1 if r == 2 else 0):
						g.put(cx + di, 4 + j, ck + dk, _col(stone, rng))

	static func _shrine(g: VoxelTiles.Grid, rng: RandomNumberGenerator, stone: Array, crystal: Array) -> void:
		var cx := 7
		var ck := 9
		for di in range(-2, 3):
			for dk in range(-2, 3):
				g.put(cx + di, 4, ck + dk, stone[0])
		for di in range(-1, 2):
			for dk in range(-1, 2):
				g.put(cx + di, 5, ck + dk, stone[1])
		for j in range(6, 13):
			for di in 2:
				for dk in 2:
					g.put(cx + di - (1 if j > 11 else 0) * di, j, ck + dk - (1 if j > 11 else 0) * dk, crystal[0] if (di + dk + j) % 3 else crystal[1], true)
		g.put(cx, 13, ck, crystal[1], true)

	static func _eye(g: VoxelTiles.Grid, rng: RandomNumberGenerator, bone: Array, iris: Color, pupil: Color) -> void:
		_shrine(g, rng, bone, [iris, iris.lightened(0.3)])
		g.put(7, 8, 11, pupil, true)

	static func _pine(g: VoxelTiles.Grid, rng: RandomNumberGenerator, trunk: Color, leaf: Array, snow, h: int) -> void:
		var cx := 7
		var ck := 9
		for j in 3:
			g.put(cx, 4 + j, ck, trunk)
		var layers := h - 3
		for j in layers:
			var r := clampi(int((layers - j) * 0.42) + 1, 1, 5)
			for di in range(-r, r + 1):
				for dk in range(-r, r + 1):
					if absi(di) + absi(dk) <= r:
						var top := j == layers - 1 or absi(di) + absi(dk) == r
						var c: Color = snow if snow != null and top and rng.randf() < 0.55 else _col(leaf, rng)
						g.put(cx + di, 6 + j, ck + dk, c)

	static func _round_tree(g: VoxelTiles.Grid, rng: RandomNumberGenerator, trunk: Color, leaf: Array, h: int, r: int) -> void:
		var cx := 7
		var ck := 9
		for j in h - r:
			g.put(cx, 4 + j, ck, trunk)
		var cy := 4 + h - r
		for di in range(-r, r + 1):
			for dk in range(-r, r + 1):
				for dj in range(-r + 1, r):
					if di * di + dk * dk + dj * dj * 1.4 <= r * r + 1 and rng.randf() < 0.93:
						g.put(cx + di, cy + dj, ck + dk, _col(leaf, rng))

	static func _jungle_tree(g: VoxelTiles.Grid, rng: RandomNumberGenerator, trunk: Color, leaf: Array, vine: Array, h: int) -> void:
		var cx := 7
		var ck := 9
		for j in h:
			g.put(cx, 4 + j, ck, trunk)
			g.put(cx + 1, 4 + j, ck, trunk if j < h / 2 else _col(leaf, rng))
		var top := 4 + h
		for di in range(-4, 5):
			for dk in range(-4, 5):
				if di * di + dk * dk <= 17 and rng.randf() < 0.9:
					g.put(cx + di, top, ck + dk, _col(leaf, rng))
					if di * di + dk * dk <= 6:
						g.put(cx + di, top + 1, ck + dk, _col(leaf, rng))
					elif rng.randf() < 0.22:   # hanging vines
						for t in rng.randi_range(2, 5):
							g.put(cx + di, top - 1 - t, ck + dk, _col(vine, rng))

	static func _dead_tree(g: VoxelTiles.Grid, rng: RandomNumberGenerator, wood: Array, ember, h: int) -> void:
		var cx := 7
		var ck := 9
		for j in h:
			var glow := ember != null and rng.randf() < 0.15
			g.put(cx, 4 + j, ck, ember if glow else wood[j % 2], glow)
		for branch in [[Vector2i(1, 0), h * 2 / 3], [Vector2i(-1, 1), h / 2], [Vector2i(0, -1), h - 2]]:
			var d: Vector2i = branch[0]
			for t in range(1, 4):
				g.put(cx + d.x * t, 4 + branch[1] + t / 2, ck + d.y * t, wood[1])

	static func _mushroom_tree(g: VoxelTiles.Grid, rng: RandomNumberGenerator, stem: Color, cap: Color, spot: Color, h: int, r: int, glows: bool) -> void:
		var cx := 7
		var ck := 9
		for j in h:
			for di in 2:
				for dk in 2:
					g.put(cx + di, 4 + j, ck + dk, stem)
		var cy := 4 + h
		for di in range(-r, r + 2):
			for dk in range(-r, r + 2):
				var d := Vector2(di - 0.5, dk - 0.5).length()
				if d <= r + 0.6:
					var c := spot if (rng.randf() < 0.12 and not glows) else cap
					g.put(cx + di, cy, ck + dk, c, glows)
					if d <= r - 1:
						g.put(cx + di, cy + 1, ck + dk, c, glows)

	static func _cactus(g: VoxelTiles.Grid, rng: RandomNumberGenerator, cols: Array, h: int) -> void:
		var cx := 7
		var ck := 9
		for j in h:
			g.put(cx, 4 + j, ck, cols[j % 2])
		for arm in [[1, h / 2], [-1, h / 3 + 1]]:
			var s: int = arm[0]
			g.put(cx + s, 4 + arm[1], ck, cols[0])
			for j in 3:
				g.put(cx + s * 2, 4 + arm[1] + j, ck, cols[1])

	static func _sparkle(g: VoxelTiles.Grid, rng: RandomNumberGenerator, c: Color) -> void:
		for n in 10:
			var p := VoxelTiles._spot(rng, 2)
			g.put(p.x, 3, p.y, c, true)

	static func _tendril(g: VoxelTiles.Grid, rng: RandomNumberGenerator, flesh: Array, tip: Color, h: int) -> void:
		var x := 7
		var k := 9
		for j in h:
			g.put(x, 4 + j, k, _col(flesh, rng))
			g.put(x + 1, 4 + j, k, _col(flesh, rng))
			if j % 3 == 2:
				x += rng.randi_range(-1, 1)
				k += rng.randi_range(-1, 1)
		g.put(x, 4 + h, k, tip, true)

# --- king models (king_skins.gd; baked into res://models/kings/<id>.res) ------------------------------

const KING_VOXEL := 0.11   # a king stands about 1.65 tall

static func king_mesh(id: String) -> ArrayMesh:
	match id:
		"lion":
			return build(_lion(), KING_VOXEL, true)
	return null

# The Golden Lion: sitting up, facing -z (towards the enemy, like your units), a dark gold mane round
# its head, a gold crown with a red gem that glows.
static func _lion() -> Grid:
	var g := Grid.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("king:lion")
	var fur := [Color("e6b94a"), Color("dcae40"), Color("efc75a")]
	var shade := Color("c99a35")
	var light := Color("f5d98a")
	var mane := [Color("b8652a"), Color("c8742e"), Color("a85a24")]
	var box := func(i0: int, i1: int, j0: int, j1: int, k0: int, k1: int, cols: Array) -> void:
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				for k in range(k0, k1 + 1):
					g.put(i, j, k, cols[rng.randi_range(0, cols.size() - 1)])
	box.call(2, 9, 0, 4, 6, 11, [shade, fur[0]])         # haunches
	box.call(3, 8, 3, 8, 4, 9, fur)                      # body, sitting up
	box.call(4, 7, 3, 7, 3, 3, [light])                  # chest
	box.call(3, 4, 0, 4, 3, 5, fur)                      # front legs
	box.call(7, 8, 0, 4, 3, 5, fur)
	box.call(3, 4, 0, 0, 2, 2, [light])                  # paws
	box.call(7, 8, 0, 0, 2, 2, [light])
	box.call(2, 9, 8, 13, 2, 7, mane)                    # mane
	box.call(3, 8, 9, 12, 1, 4, fur)                     # head
	box.call(4, 7, 9, 10, 0, 1, [light])                 # muzzle
	g.put(5, 10, 0, Color("4a2a1a"))                     # nose
	g.put(6, 10, 0, Color("4a2a1a"))
	g.put(4, 11, 1, Color("2a1a12"))                     # eyes
	g.put(7, 11, 1, Color("2a1a12"))
	g.put(3, 13, 3, fur[0])                              # ears
	g.put(8, 13, 3, fur[0])
	var gold := Color("f2c14e")
	var gold_dark := Color("c9962c")
	for i in range(3, 9):                                # the crown: a band round the top of the head
		for k in range(1, 5):
			if i == 3 or i == 8 or k == 1 or k == 4:
				g.put(i, 13, k, gold_dark)
	for p in [Vector2i(3, 1), Vector2i(8, 1), Vector2i(3, 4), Vector2i(8, 4), Vector2i(5, 1), Vector2i(6, 1)]:
		g.put(p.x, 14, p.y, gold)                        # its points
	g.put(5, 13, 1, Color("d0362a"), true)               # the gem, glowing
	g.put(6, 13, 1, Color("d0362a"), true)
	for t in [Vector3i(9, 1, 11), Vector3i(10, 2, 11), Vector3i(10, 3, 12), Vector3i(10, 4, 12)]:
		g.put(t.x, t.y, t.z, fur[1])                     # tail
	g.put(10, 5, 12, mane[0])
	g.put(9, 5, 12, mane[0])
	return g
