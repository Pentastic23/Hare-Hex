# make_tile_textures.gd
# Dev tool, not part of the game: draws the voxel tile textures for the 10 board themes
# (Scripts/board_themes.gd) into res://textures/tiles/<theme>/, and a preview sheet of all of them
# into res://docs/tile_themes_preview.png. Everything is seeded, so running it again gives the same
# pixels. Run from the project folder (then --import once so Godot picks up new files):
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tools/make_tile_textures.gd
#
# Per theme: board_1..3.png (the top of a board hex, three variations), board_side.png (its sides),
# bench.png / bench_side.png and sell.png / sell_side.png. Tops are 16 x 16, sides 16 x 8, drawn as
# pixel art and shown with nearest filtering, so every pixel reads as a voxel.

extends SceneTree

const TOP := 16
const SIDE_W := 16
const SIDE_H := 8
const OUT := "res://textures/tiles/%s/"
const PREVIEW := "res://docs/tile_themes_preview.png"

# The look of each theme: the top's shades and features, the sides, the bench and the sell hex.
const LOOKS := {
	"castle": {"top": ["8a8780", "9a968e", "7b7871", "a6a299"], "style": "flagstones", "mortar": "5e5b55", "accent": ["5f7f3a", "6e8f45"],
		"side": ["6f6c66", "7d7a73", "625f5a"], "side_style": "bricks", "lip": [], "bench": "planks", "bench_c": ["6b4a2e", "7a5636", "5c3f27"], "seam": "3d2a1a"},
	"grasslands": {"top": ["5f9e3a", "6fb043", "548f33", "7fbf4f"], "style": "grass", "accent": ["f4e36b", "ffffff", "e86a6a"],
		"side": ["7a5230", "6b4527", "86603a"], "side_style": "strata", "lip": ["5f9e3a", "548f33"], "bench": "planks", "bench_c": ["8a5f36", "9a6c3f", "7a532f"], "seam": "4a321c"},
	"forest": {"top": ["2f5d2e", "3a6b35", "284f27", "456f3a"], "style": "forest", "accent": ["6b4a2a", "7d5a32", "c0392b", "f0e6d2"],
		"side": ["4a3420", "3f2c1b", "56402a"], "side_style": "strata", "lip": ["2f5d2e", "284f27"], "bench": "planks", "bench_c": ["5a3d24", "66462a", "4e351f"], "seam": "2c1d10"},
	"mountains": {"top": ["7d7f86", "8e9097", "6c6e75", "9a9ca3"], "style": "rock", "mortar": "55575e", "accent": ["eef3f7", "dfe7ee"],
		"side": ["6a6c73", "5d5f66", "77797f"], "side_style": "strata", "lip": ["eef3f7", "dfe7ee"], "bench": "slab", "bench_c": ["5a5c63", "64666d", "50525a"], "seam": "3a3c42"},
	"ashlands": {"top": ["6f6a64", "7c766f", "615c57", "58534e"], "style": "ash", "accent": ["2d2a28", "3a3633", "ff8a3c", "ffb347"],
		"side": ["4b4642", "3f3b38", "55504b"], "side_style": "strata", "lip": ["615c57", "58534e"], "bench": "planks", "bench_c": ["3a2c22", "45352a", "2f241c"], "seam": "1c1511"},
	"scorched_road": {"top": ["b98e5a", "c79d66", "a87f4f", "d2ab73"], "style": "road", "mortar": "6e4b2a", "accent": ["ff7a2e", "ffb05c"],
		"side": ["9c7547", "8a663d", "a9804f"], "side_style": "strata", "lip": ["a87f4f", "b98e5a"], "bench": "planks", "bench_c": ["7a5634", "86603a", "6b4b2d"], "seam": "3f2a17"},
	"volcano": {"top": ["2a2626", "332e2d", "3d3735", "221f1f"], "style": "lava", "accent": ["ff5a1f", "ffa53a", "ffd36b"],
		"side": ["2b2524", "352d2b", "231e1d"], "side_style": "lava_side", "lip": [], "bench": "slab", "bench_c": ["1f1b1b", "282323", "1a1616"], "seam": "ff5a1f"},
	"crystal_cave": {"top": ["3b3550", "443d5c", "34304a", "4d4566"], "style": "cave", "accent": ["6ff3ff", "b47cff", "e9fbff"],
		"side": ["2e2940", "383150", "29243a"], "side_style": "crystal_side", "lip": [], "bench": "slab", "bench_c": ["2a2539", "322c44", "241f32"], "seam": "6ff3ff"},
	"sky_bridge": {"top": ["c9d3dc", "d8e0e7", "b8c3cd", "e6ecf1"], "style": "sky", "mortar": "8f9ba6", "accent": ["ffffff", "f3f7fb"],
		"side": ["a9b4be", "9aa5af", "b6c0c9"], "side_style": "clouds", "lip": [], "bench": "slab", "bench_c": ["9aa6b2", "a8b3be", "8d99a5"], "seam": "6f7b87"},
	"storm_citadel": {"top": ["3a4250", "444d5c", "323947", "4d5767"], "style": "storm", "mortar": "262c37", "accent": ["7fd4ff", "c4ecff"],
		"side": ["2f3542", "38404e", "29303b"], "side_style": "bricks", "lip": [], "bench": "slab", "bench_c": ["2a303c", "323947", "252b36"], "seam": "7fd4ff"},
}
# Same ids and order as BoardThemes.ORDER (kept here so the tool runs without the game's autoloads).
const ORDER := ["castle", "grasslands", "forest", "mountains", "ashlands", "scorched_road", "volcano", "crystal_cave", "sky_bridge", "storm_citadel"]
const SELL_RED := "b8322a"
const SELL_GOLD := ["f2c14e", "c9962c"]

func _init():
	var sheet_rows: Array[Image] = []
	for id in ORDER:
		var look: Dictionary = LOOKS[String(id)]
		var dir := OUT % id
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var parts := {}
		for v in 3:
			parts["board_%d" % (v + 1)] = top(String(id), look, v)
		parts["board_side"] = side(String(id), look, look.side, look.lip)
		parts["bench"] = bench(String(id), look)
		parts["bench_side"] = side(String(id) + "bench", look, look.bench_c, [])
		parts["sell"] = sell(String(id), look)
		parts["sell_side"] = sell_side(String(id), look)
		for k in parts:
			(parts[k] as Image).save_png(dir + k + ".png")
		sheet_rows.append(_sheet_row(parts))
		print("%-14s %d textures -> %s" % [id, parts.size(), dir])
	_save_sheet(sheet_rows)
	print("preview -> ", PREVIEW)
	quit()

# --- the top of a board hex --------------------------------------------------------------------

func top(id: String, look: Dictionary, variant: int) -> Image:
	var rng := _rng(id + "top" + str(variant))
	var img := _blank(TOP, TOP)
	var shades := _cols(look.top)
	var acc := _cols(look.accent)
	_noise_fill(img, shades, rng.randi(), 0.18)
	match look.style:
		"grass":
			_tufts(img, shades[2].darkened(0.15), 6 + variant * 2, rng)
			_scatter(img, acc, 2 + variant, rng)
		"forest":
			_patches(img, [acc[0], acc[1]], 3 + variant, rng)
			if variant != 1:
				_mushroom(img, acc[2], acc[3], rng)
			_tufts(img, shades[2].darkened(0.25), 5, rng)
		"rock":
			_cracks(img, Color(look.mortar), 2 + variant, 6, rng)
			_snow(img, acc, rng.randi(), 0.35 - variant * 0.08)
		"flagstones":
			_flagstones(img, shades, Color(look.mortar), rng)
			_scatter(img, [acc[0], acc[1]], 1 + variant * 2, rng)
		"ash":
			_patches(img, [acc[0], acc[1]], 3 + variant, rng)
			_scatter(img, [acc[2], acc[3]], 2 + variant, rng)
		"road":
			_flagstones(img, shades, Color(look.mortar), rng, 8)
			_cracks(img, Color(look.mortar).darkened(0.2), 1 + variant, 4, rng)
			_scatter(img, acc, variant, rng)
		"lava":
			_lava(img, acc, 1 + (variant % 2), rng)
		"cave":
			_cracks(img, shades[2].darkened(0.3), 2, 5, rng)
			for i in 1 + variant:
				_crystal(img, acc, rng)
		"sky":
			_flagstones(img, shades, Color(look.mortar), rng)
			_wisps(img, acc[0], 1 + variant, rng)
		"storm":
			_flagstones(img, shades, Color(look.mortar), rng)
			_rune(img, acc, rng)
	return img

# --- sides: layers under the top ---------------------------------------------------------------

func side(id: String, look: Dictionary, cols: Array, lip: Array) -> Image:
	var rng := _rng(id + "side")
	var img := _blank(SIDE_W, SIDE_H)
	var shades := _cols(cols)
	_noise_fill(img, shades, rng.randi(), 0.3)
	match look.side_style:
		"bricks":
			for y in SIDE_H:
				for x in SIDE_W:
					var row := y / 3
					if y % 3 == 2 or (x + row * 3) % 6 == 0:
						img.set_pixel(x, y, shades[0].darkened(0.35))
		"lava_side":
			for i in 2:
				var x := rng.randi_range(1, SIDE_W - 2)
				for y in rng.randi_range(3, SIDE_H):
					img.set_pixel(x, y, Color("ff5a1f") if y % 2 == 0 else Color("ffa53a"))
		"crystal_side":
			for i in 3:
				img.set_pixel(rng.randi_range(0, SIDE_W - 1), rng.randi_range(2, SIDE_H - 1), Color("6ff3ff"))
		"clouds":
			for x in SIDE_W:
				var h := 2 + int(abs(sin(x * 0.9 + rng.randf() * 0.5)) * 2.0)
				for y in range(SIDE_H - h, SIDE_H):
					img.set_pixel(x, y, Color("ffffff") if y > SIDE_H - h else Color("eef3f8"))
		_:
			for x in SIDE_W:   # stones in the earth
				if rng.randf() < 0.15:
					img.set_pixel(x, rng.randi_range(3, SIDE_H - 1), shades[0].lightened(0.25))
	var lips := _cols(lip)
	if not lips.is_empty():
		for x in SIDE_W:
			var depth := 1 + (1 if rng.randf() < 0.45 else 0)
			for y in depth:
				img.set_pixel(x, y, lips[(x + y) % lips.size()])
	for x in SIDE_W:   # a darker bottom row grounds the block
		img.set_pixel(x, SIDE_H - 1, img.get_pixel(x, SIDE_H - 1).darkened(0.3))
	return img

# --- bench and sell ------------------------------------------------------------------------------

func bench(id: String, look: Dictionary) -> Image:
	var rng := _rng(id + "bench")
	var img := _blank(TOP, TOP)
	var cols := _cols(look.bench_c)
	var seam := Color(look.seam)
	if look.bench == "planks":
		for y in TOP:
			for x in TOP:
				var plank := y / 4
				var c: Color = cols[(plank + (1 if x > 9 + plank % 3 else 0)) % cols.size()]
				if (x * 7 + y * 3 + plank) % 11 == 0:
					c = c.darkened(0.12)   # grain
				img.set_pixel(x, y, c)
			if y % 4 == 3:
				for x in TOP:
					img.set_pixel(x, y, seam)
		for i in 2:   # nails
			img.set_pixel(rng.randi_range(2, 13), rng.randi_range(0, 3) * 4 + 1, Color("c9c2b0"))
	else:
		_noise_fill(img, cols, rng.randi(), 0.2)
		for i in TOP:   # a glowing or dark inlay ring marks the bench
			for p in [Vector2i(i, 1), Vector2i(i, TOP - 2), Vector2i(1, i), Vector2i(TOP - 2, i)]:
				if p.x >= 1 and p.x <= TOP - 2 and p.y >= 1 and p.y <= TOP - 2:
					img.set_pixel(p.x, p.y, seam)
	return img

func sell(id: String, look: Dictionary) -> Image:
	var rng := _rng(id + "sell")
	var img := _blank(TOP, TOP)
	var base: Array = []
	for c in _cols(look.top):
		base.append(c.lerp(Color(SELL_RED), 0.55).darkened(0.25))
	_noise_fill(img, base, rng.randi(), 0.2)
	var gold := _cols(SELL_GOLD)
	for y in TOP:   # a gold coin in the middle
		for x in TOP:
			var d := Vector2(x - 7.5, y - 7.5).length()
			if d <= 4.6:
				img.set_pixel(x, y, gold[1] if d > 3.6 else gold[0])
	for y in range(5, 11):   # the coin's mark
		img.set_pixel(7, y, gold[1].darkened(0.3))
		img.set_pixel(8, y, gold[1].darkened(0.3))
	return img

func sell_side(id: String, look: Dictionary) -> Image:
	var rng := _rng(id + "sellside")
	var img := _blank(SIDE_W, SIDE_H)
	var shades: Array = []
	for c in _cols(look.side):
		shades.append(c.lerp(Color(SELL_RED), 0.5).darkened(0.2))
	_noise_fill(img, shades, rng.randi(), 0.3)
	for x in SIDE_W:
		img.set_pixel(x, 0, Color(SELL_GOLD[1]))
		img.set_pixel(x, SIDE_H - 1, img.get_pixel(x, SIDE_H - 1).darkened(0.3))
	return img

# --- drawing helpers -----------------------------------------------------------------------------

func _rng(key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	return r

func _blank(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

func _cols(list: Array) -> Array:
	var out: Array = []
	for s in list:
		out.append(Color(s))
	return out

# Patchy fill: smooth noise picks one of the shades per pixel.
func _noise_fill(img: Image, shades: Array, seed: int, freq: float) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	for y in img.get_height():
		for x in img.get_width():
			var v := (n.get_noise_2d(x, y) + 1.0) * 0.5
			img.set_pixel(x, y, shades[clampi(int(v * shades.size()), 0, shades.size() - 1)])

func _scatter(img: Image, cols: Array, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		img.set_pixel(rng.randi_range(1, TOP - 2), rng.randi_range(1, TOP - 2), cols[rng.randi_range(0, cols.size() - 1)])

func _tufts(img: Image, c: Color, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var x := rng.randi_range(1, TOP - 2)
		var y := rng.randi_range(1, TOP - 3)
		img.set_pixel(x, y, c)
		img.set_pixel(x, y + 1, c)

func _patches(img: Image, cols: Array, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var cx := rng.randi_range(2, TOP - 3)
		var cy := rng.randi_range(2, TOP - 3)
		var c: Color = cols[i % cols.size()]
		for p in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			if rng.randf() < 0.8:
				img.set_pixel(cx + p.x, cy + p.y, c)

func _mushroom(img: Image, cap: Color, stem: Color, rng: RandomNumberGenerator) -> void:
	var x := rng.randi_range(3, TOP - 4)
	var y := rng.randi_range(3, TOP - 4)
	img.set_pixel(x, y + 1, stem)
	img.set_pixel(x - 1, y, cap)
	img.set_pixel(x, y, cap)
	img.set_pixel(x + 1, y, cap)
	img.set_pixel(x, y - 1, cap.lightened(0.2))

# Random-walk lines (cracks in stone).
func _cracks(img: Image, c: Color, count: int, length: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var p := Vector2i(rng.randi_range(1, TOP - 2), rng.randi_range(1, TOP - 2))
		for s in length:
			img.set_pixel(p.x, p.y, c)
			p += [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)][rng.randi_range(0, 3)]
			p = p.clamp(Vector2i.ZERO, Vector2i(TOP - 1, TOP - 1))

func _snow(img: Image, cols: Array, seed: int, amount: float) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.22
	for y in TOP:
		for x in TOP:
			var v := (n.get_noise_2d(x, y) + 1.0) * 0.5
			if v < amount:
				img.set_pixel(x, y, cols[(x + y) % cols.size()])

# Stone blocks with mortar lines; rows are offset like masonry.
func _flagstones(img: Image, shades: Array, mortar: Color, rng: RandomNumberGenerator, size := 6) -> void:
	var stone_shade := {}
	for y in TOP:
		for x in TOP:
			var row := y / size
			var sx := x + (size / 2 if row % 2 == 1 else 0)
			var key := Vector2i(sx / size, row)
			if not stone_shade.has(key):
				stone_shade[key] = shades[rng.randi_range(0, shades.size() - 1)]
			var c: Color = stone_shade[key]
			if y % size == size - 1 or sx % size == size - 1:
				c = mortar
			elif (x * 5 + y * 3) % 13 == 0:
				c = c.lightened(0.08)
			img.set_pixel(x, y, c)

func _lava(img: Image, cols: Array, veins: int, rng: RandomNumberGenerator) -> void:
	for i in veins:
		var p := Vector2i(rng.randi_range(0, TOP - 1), 0)
		while p.y < TOP:
			img.set_pixel(p.x, p.y, cols[2] if rng.randf() < 0.3 else cols[1])
			for d in [Vector2i(1, 0), Vector2i(-1, 0)]:
				var q: Vector2i = p + d
				if q.x >= 0 and q.x < TOP and rng.randf() < 0.6:
					img.set_pixel(q.x, q.y, cols[0])
			p += Vector2i(rng.randi_range(-1, 1), 1)
			p.x = clampi(p.x, 0, TOP - 1)

func _crystal(img: Image, cols: Array, rng: RandomNumberGenerator) -> void:
	var x := rng.randi_range(2, TOP - 3)
	var y := rng.randi_range(3, TOP - 2)
	var c: Color = cols[rng.randi_range(0, 1)]
	for h in rng.randi_range(2, 4):
		img.set_pixel(x, y - h, c)
	img.set_pixel(x + 1, y - 1, c.darkened(0.25))
	img.set_pixel(x - 1, y - 1, c.darkened(0.25))
	img.set_pixel(x, y - 1, cols[2])

func _wisps(img: Image, c: Color, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var x := rng.randi_range(0, TOP - 6)
		var y := rng.randi_range(1, TOP - 2)
		for d in rng.randi_range(3, 6):
			img.set_pixel(x + d, y, c)

# A glowing rune: a few straight strokes through the middle.
func _rune(img: Image, cols: Array, rng: RandomNumberGenerator) -> void:
	var cx := rng.randi_range(5, 10)
	var cy := rng.randi_range(5, 10)
	for y in range(cy - 3, cy + 4):
		img.set_pixel(cx, y, cols[0])
	for d in 3:
		img.set_pixel(cx + 1 + d, cy - 1 - d, cols[0])
		img.set_pixel(cx - 1 - d, cy + 1 + d, cols[0])
	img.set_pixel(cx, cy, cols[1])

# --- preview sheet -------------------------------------------------------------------------------

const ZOOM := 6

func _sheet_row(parts: Dictionary) -> Image:
	var keys := ["board_1", "board_2", "board_3", "bench", "sell"]
	var row := _blank((TOP * ZOOM + 8) * keys.size() + (SIDE_W * ZOOM + 8) * 3, TOP * ZOOM + 8)
	row.fill(Color("14161c"))
	var x := 4
	for k in keys:
		var big := (parts[k] as Image).duplicate() as Image
		big.resize(TOP * ZOOM, TOP * ZOOM, Image.INTERPOLATE_NEAREST)
		row.blit_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(x, 4))
		x += TOP * ZOOM + 8
	for k in ["board_side", "bench_side", "sell_side"]:
		var big := (parts[k] as Image).duplicate() as Image
		big.resize(SIDE_W * ZOOM, SIDE_H * ZOOM, Image.INTERPOLATE_NEAREST)
		row.blit_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(x, 4 + (TOP - SIDE_H) * ZOOM / 2))
		x += SIDE_W * ZOOM + 8
	return row

func _save_sheet(rows: Array[Image]) -> void:
	var w := rows[0].get_width()
	var sheet := _blank(w, rows[0].get_height() * rows.size())
	for i in rows.size():
		sheet.blit_rect(rows[i], Rect2i(Vector2i.ZERO, rows[i].get_size()), Vector2i(0, i * rows[i].get_height()))
	sheet.save_png(PREVIEW)
