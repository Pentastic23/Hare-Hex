# make_icon.gd
# Dev tool, not part of the game: draws the game's icon (a voxel hare on a gold-edged hex, in the HUD
# colours) as 32 px pixel art and writes:
#   res://icon.png          256 px (the project icon, config/icon)
#   res://icon.ico          16, 32, 48, 64, 128 and 256 px (the Windows .exe icon, export preset)
#   res://docs/icon_preview.png  every size side by side
# Run from the project folder, then --import once:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tools/make_icon.gd

extends SceneTree

const N := 32
const SIZES := [16, 32, 48, 64, 128, 256]

# The hare, sitting, facing right. W fur, w fur shade, P inner ear, E eye, e eye shine, N nose,
# T tail, S shadow; the outline is added around it in code.
const HARE := [
	"..........ww.......",
	".........wPw.......",
	"........wPPw..ww...",
	"........wPPw.wPw...",
	"........wPPwwPPw...",
	"........wPPwPPw....",
	".........wWWWw.....",
	"........wWWWWWw....",
	".......wWWWWEeWw...",
	".......wWWWWEEWWN..",
	".......wWWWWWWWWw..",
	"...wwwwwWWWWWWw....",
	"..wWWWWWWWWWWWw....",
	".wWWWWWWWWWWWWw....",
	"TwWWWWWWWWWWWWw....",
	"TwWWWWWWWWWWWWWw...",
	"wWWWWWWWWWWWWWWw...",
	".wWWWWWWWwWWWWWw...",
	"..wwwwwwwwwWWWww...",
	"...SSSSSSSSwwwwS...",
]
const COL := {
	"W": "f3ead6", "w": "c7b493", "P": "eb9aaa", "E": "1a1410", "e": "ffffff", "N": "e2788c",
	"T": "fffaf0", "S": "0d0f18",
}
const OUTLINE := "1b1622"
const HEX_TOP := "2b3150"
const HEX_BOTTOM := "151826"
const GOLD := "f2c14e"
const GOLD_DARK := "8a6a1f"

func _init():
	var art := _draw()
	var images := {}
	for s in SIZES:
		images[s] = _scaled(art, s)
	(images[256] as Image).save_png("res://icon.png")
	_save_ico("res://icon.ico", images)
	_preview(images)
	print("icon.png, icon.ico (%s px), docs/icon_preview.png" % ", ".join(SIZES.map(func(s): return str(s))))
	quit()

func _draw() -> Image:
	var img := Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# The hex: pointy-top like the board, filling the square; a gold rim with a darker inner line.
	var c := Vector2(15.5, 15.5)
	for y in N:
		for x in N:
			var d := _hex_dist(Vector2(x, y) - c)
			if d > 15.6:
				continue
			var t := y / float(N - 1)
			var fill := Color(HEX_TOP).lerp(Color(HEX_BOTTOM), t)
			if d > 13.6:
				fill = Color(GOLD) if y < 18 else Color(GOLD).darkened(0.18)
			elif d > 12.4:
				fill = Color(GOLD_DARK)
			elif (x + y) % 7 == 0 and d < 11.0:
				fill = fill.lightened(0.05)   # a little texture, like the tiles
			img.set_pixel(x, y, fill)
	# The hare, centred a little low so the ears have room.
	var ox := 7
	var oy := 6
	var mask := {}
	for row in HARE.size():
		var line: String = HARE[row]
		for col in line.length():
			var ch := line[col]
			if ch == ".":
				continue
			var p := Vector2i(ox + col, oy + row)
			if ch == "S":
				img.set_pixel(p.x, p.y, img.get_pixel(p.x, p.y).lerp(Color(COL.S), 0.6))
				continue
			mask[p] = true
			img.set_pixel(p.x, p.y, Color(COL[ch]))
	for p in mask:   # a dark outline keeps the hare readable at 16 px
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if not mask.has(q) and q.x >= 0 and q.y >= 0 and q.x < N and q.y < N and _hex_dist(Vector2(q) - c) <= 12.4:
				img.set_pixel(q.x, q.y, Color(OUTLINE))
	return img

# Distance in "hex radius" units: <= r means inside a pointy-top hexagon of circumradius r.
func _hex_dist(v: Vector2) -> float:
	var a := absf(v.x)
	var b := absf(v.y)
	return maxf(a / 0.8660254, a * 0.5773503 + b)

# Pixel-perfect where the size is a multiple of 32; smooth downscales for 16 and 48.
func _scaled(art: Image, s: int) -> Image:
	var img := art.duplicate() as Image
	if s % N == 0:
		img.resize(s, s, Image.INTERPOLATE_NEAREST)
	else:
		img.resize(N * 4, N * 4, Image.INTERPOLATE_NEAREST)
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
	return img

# An .ico holding each size as a PNG (Windows Vista and later read PNG entries).
func _save_ico(path: String, images: Dictionary) -> void:
	var pngs: Array[PackedByteArray] = []
	for s in SIZES:
		pngs.append((images[s] as Image).save_png_to_buffer())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_16(0)               # reserved
	f.store_16(1)               # type: icon
	f.store_16(SIZES.size())    # image count
	var offset := 6 + 16 * SIZES.size()
	for i in SIZES.size():
		var s: int = SIZES[i]
		f.store_8(0 if s >= 256 else s)   # width (0 = 256)
		f.store_8(0 if s >= 256 else s)   # height
		f.store_8(0)                      # palette colours
		f.store_8(0)                      # reserved
		f.store_16(1)                     # colour planes
		f.store_16(32)                    # bits per pixel
		f.store_32(pngs[i].size())
		f.store_32(offset)
		offset += pngs[i].size()
	for png in pngs:
		f.store_buffer(png)
	f.close()

func _preview(images: Dictionary) -> void:
	var w := 0
	for s in SIZES:
		w += s + 16
	var sheet := Image.create_empty(w + 16, 256 + 32, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("2a2d3a"))
	var x := 16
	for s in SIZES:
		var img: Image = images[s]
		sheet.blend_rect(img, Rect2i(0, 0, s, s), Vector2i(x, 16 + 256 - s))
		x += s + 16
	sheet.save_png("res://docs/icon_preview.png")
