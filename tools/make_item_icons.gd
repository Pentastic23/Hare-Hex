# make_item_icons.gd
# Dev tool, not part of the game: draws the 36 stat items' icons in the style of the hand-made unique
# item icons (Hero's Blade, Coin Purse, the Ancient Sigil...): the object itself as chunky 16 x 16 pixel
# art filling the square, flat light / mid / dark tones, a few accent colours and a 1 px near-black
# outline, scaled to 64 px. Writes textures/ui/items/<id>.png. The 9 unique items keep their hand-made icons.
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tools/make_item_icons.gd [-- <id> ...]
# With ids, only those icons are drawn. Then run --import once so Godot picks the PNGs up.

extends SceneTree

const N := 16
const SCALE := 4
const OUTLINE := Color("1b1610")   # the hand-made icons' outline

# Fixed colours shared by every icon (steel, gold, cream, wood, blood, a blue gem), matching the
# hand-made icons. 1 / 2 / 3 are the item's own colour (ItemData.color) light, mid and dark;
# x is chain mail (steel checks); k is the outline colour inside a shape (holes, a black stone).
const PALETTE := {
	"S": Color("d0d4e0"), "s": Color("a9aec4"), "t": Color("7d8296"),
	"G": Color("ffd76a"), "g": Color("e0a43a"), "h": Color("a8701e"),
	"W": Color("f4ecc8"), "w": Color("fffaeb"), "y": Color("c9b98e"),
	"B": Color("8a5a2a"), "L": Color("b07a40"), "b": Color("5e3a1a"),
	"R": Color("d63b4a"), "r": Color("8a1f2c"),
	"P": Color("7fa8ff"), "p": Color("4a6fc8"),
	"k": OUTLINE,
}

# Each sprite is the object without its outline (added in code), centred on the square by its bounds,
# at most 14 x 14 so the outline fits.
const SPRITES := {
	# --- Might: attack power ---
	"longsword": [
		"....s....",
		"...Sst...",
		"...Sst...",
		"...Sst...",
		"...Sst...",
		"...Sst...",
		"...Sst...",
		"...Sst...",
		"122222223",
		"....B....",
		"....b....",
		"...232...",
	],
	"war_axe": [
		"..SSs.....",
		".Ssssst...",
		"Sssssst2..",
		"Sssssst2..",
		"Sssst..2..",
		".Sst...2..",
		"..t....2..",
		".......2..",
		".......2..",
		".......2..",
		".......3..",
	],
	"serrated_dirk": [
		"........St",
		".......Sst",
		"......Sst.",
		".....Ssttt",
		"....Sst...",
		"...Ssttt..",
		"..1Sst....",
		"...12.....",
		"..B312....",
		".BB...2...",
		"bB........",
	],
	"giants_maul": [
		"SSSSSSSSSS",
		"ssssssssss",
		"ssssssssss",
		"tttttttttt",
		"....BL....",
		"....BL....",
		"....BL....",
		"....BL....",
		"....bB....",
		"...1223...",
	],
	# --- Vigor: HP ---
	"iron_belt": [
		"1111SSSSSS1111",
		"2222Skkkks2222",
		"2222SksSks2222",
		"2222Skkkks2222",
		"3333ssssss3333",
		"3333333333333.",
	],
	"troll_hide": [
		"22.......22",
		"222.222.222",
		".222222222.",
		"..1223223..",
		"..1222223..",
		"..1232223..",
		"..1222323..",
		".222222223.",
		"222.2.2.333",
		"22.......33",
	],
	"heart_locket": [
		".....g.....",
		"....g.g....",
		".112.g.122.",
		"11222g12223",
		"12222GG2223",
		"12222gg2223",
		".122222223.",
		"..1222223..",
		"...12223...",
		"....123....",
		".....3.....",
	],
	"ogres_girdle": [
		"11111gggg11111",
		"2222gGGGGg2222",
		"2222gGkkGh2222",
		"2222gGkkGh2222",
		"3333gGGGGh3333",
		"33333hhhh33333",
	],
	# --- Vigor: mitigation ---
	"leather_jerkin": [
		".22.....22.",
		"1222...1223",
		"12222.12223",
		"12222.12223",
		".1222g1223.",
		".1222.1223.",
		".1222g1223.",
		".1222.1223.",
		".1222g1223.",
		".333333333.",
	],
	"hide_bracers": [
		"112222222223",
		"bbbbbbbbbbbb",
		"122222222223",
		".1222222223.",
		".bbbbbbbbbb.",
		".1222222223.",
		"..12222223..",
		"..bbbbbbbb..",
		"..12222223..",
	],
	"padded_gambeson": [
		".22.....22.",
		"1222...1223",
		"12222.12223",
		"33333.33333",
		"12222.12223",
		"33333.33333",
		"12222.12223",
		"33333.33333",
		"12222.12223",
		".333333333.",
	],
	"stone_ring": [
		"...1112...",
		"..122223..",
		"..122233..",
		"..g3333h..",
		".g......h.",
		"G........h",
		"G........h",
		"G........h",
		".g......h.",
		"..gghhhh..",
	],
	# --- Swift: attack speed ---
	"quick_bow": [
		"W12.......",
		"W.12......",
		"W..12.....",
		"W...12....",
		"W....12...",
		"BBBBBB12St",
		"W....12...",
		"W...12....",
		"W..12.....",
		"W.12......",
		"W12.......",
	],
	"swift_gloves": [
		"...1.1.1...",
		"..12.2.2.1.",
		"..12.2.2.2.",
		"1.122222222",
		"12122222222",
		".1222222223",
		"..12222223.",
		"..12222223.",
		"..gggggggg.",
		"..12222223.",
		"..33333333.",
	],
	"wind_charm": [
		"....g....",
		"...g.g...",
		"..11122..",
		".1222222.",
		"12WW22222",
		"12W22W223",
		"122W2W223",
		"1222WW223",
		".2222223.",
		"..23333..",
	],
	"feather_boots": [
		"W1..1222....",
		"WW1.1222....",
		".WW.1222....",
		"..W.1222....",
		"....1222....",
		"....1222....",
		"....12222...",
		"....1222222.",
		"...12222222.",
		"...12222223.",
		"...bbbbbbbb.",
	],
	# --- Guard: armour ---
	"chain_vest": [
		"..xxx...xxx..",
		".xxxxxxxxxxx.",
		"xxxxxxxxxxxxx",
		"xx.xxxxxxx.xx",
		"...xxxxxxx...",
		"...xxxxxxx...",
		"...xxxxxxx...",
		"...xxxxxxx...",
		"...ttttttt...",
	],
	"tower_shield": [
		"SSSSSSSSSS",
		"S11222222t",
		"S1222g222t",
		"S122ggg22t",
		"S1222g222t",
		"S1222g222t",
		"S1222g223t",
		"S1222g233t",
		".S222233t.",
		"..S2233t..",
		"...Sttt...",
	],
	"bronze_buckler": [
		"...1122...",
		".11222223.",
		".12222223.",
		"1222SS2223",
		"122SWs2223",
		"122Sst2233",
		"1222tt2233",
		".12222233.",
		".22222333.",
		"...2333...",
	],
	"plate_cuirass": [
		".SSs...sSs.",
		"SSSSsssssst",
		"SSSsssssstt",
		"SSSssWssstt",
		".SSssWsstt.",
		".SSssWsstt.",
		"..Sssssst..",
		"..Sssssst..",
		"...ssstt...",
	],
	# --- Guard: magic resist ---
	"warding_cloak": [
		"....1222....",
		"...122223...",
		"...12kk23...",
		"..1222g223..",
		"..12222223..",
		".1222222223.",
		".1222222223.",
		"122222222223",
		"122222222223",
		"1222.22.2233",
	],
	"silver_circlet": [
		".....PP.....",
		"..S.Pppp.S..",
		".Ss.Pppp.st.",
		"SSSSSSssssst",
		"sssssssstttt",
	],
	"spellward_talisman": [
		"g........g",
		".g......g.",
		"..g....g..",
		"...gggg...",
		"..112222..",
		".12222223.",
		".122WW223.",
		".12W22W23.",
		".122WW223.",
		".12222233.",
		"..223333..",
	],
	"nullstone_amulet": [
		"g........g",
		".g......g.",
		"..g....g..",
		"...gggg...",
		"..SSSSss..",
		".Skkkkkkt.",
		".Skk1kkkt.",
		".Skkkkkkt.",
		".Skkkkkkt.",
		"..sstttt..",
	],
	# --- Blood: omnivamp ---
	"blood_fang": [
		"WWWWWWWW",
		"WWWWWWWy",
		".WWWWWWy",
		".WWWWWy.",
		"..WWWWy.",
		"..WWWy..",
		"...W2y..",
		"...22...",
		"...23...",
		"....3...",
	],
	"vampire_ring": [
		"...1112...",
		"..1w2223..",
		"..122233..",
		"..g3333h..",
		".g......h.",
		"G........h",
		"G........h",
		"G........h",
		".g......h.",
		"..gghhhh..",
	],
	"hungering_blade": [
		"...........S",
		"..........Ss",
		".........Sst",
		"........Sst.",
		".......Sst..",
		"......2st...",
		".....22t....",
		"..g.22......",
		"...gg.......",
		"..BBg.......",
		".BB..g......",
		"BB..........",
	],
	"sanguine_tome": [
		"g222222222g",
		"b1222222223",
		"b1222RR2223",
		"b122RRRR223",
		"b122RRRR223",
		"b1222RR2223",
		"b1222222223",
		"g333333333g",
		"WWWWWWWWWW.",
	],
	# --- Arcane: ability power ---
	"apprentice_wand": [
		"........1.1",
		".........w.",
		"........1.1",
		".......BL..",
		"......BL...",
		".....BL....",
		"....BL.....",
		"...BL......",
		"..BL.......",
		".BL........",
		"bb.........",
	],
	"sages_staff": [
		"...1...",
		"..122..",
		".12223.",
		"..123..",
		"..gBg..",
		"...B...",
		"...B...",
		"...B...",
		"...B...",
		"...B...",
		"...B...",
		"...b...",
	],
	"hex_orb": [
		"...1122...",
		"..122222..",
		".12w22223.",
		".1w222223.",
		".12222233.",
		".12222233.",
		"..222333..",
		"...2333...",
		"..gggggg..",
		".gggghhhh.",
	],
	"archmages_tome": [
		"g222222222g",
		"b1222222223",
		"b1222G22223",
		"b122GGG2223",
		"b1222G22223",
		"b1222222223",
		"b1222222223",
		"g333333333g",
		"WWWWWWWWWW.",
	],
	# --- Arcane: mana ---
	"mana_charm": [
		"....g....",
		"...ggg...",
		"...122...",
		"..12222..",
		".12w2222.",
		".1w22222.",
		"122222223",
		"122222223",
		".1222233.",
		"..23333..",
	],
	"spirit_bead": [
		"....W.....",
		"...1122...",
		".11222222.",
		".12w22222.",
		"1222222223",
		"12222k2223",
		"1222222223",
		".22222233.",
		".22223333.",
		"...2333...",
		"....W.....",
	],
	"moon_tear": [
		"...1122..",
		".1122....",
		".122.....",
		"122......",
		"122.....w",
		"122....ww",
		"122.....w",
		".223.....",
		".2233....",
		"...23333.",
	],
	"focus_gem": [
		"..112223..",
		".1w112223.",
		"1111122233",
		".22222333.",
		"..222233..",
		"...2233...",
		"....23....",
	],
}

func _init() -> void:
	var only := OS.get_cmdline_user_args()
	var made := 0
	for id in SPRITES:
		if not only.is_empty() and not only.has(id):
			continue
		var item := load("res://tres/items/%s.tres" % id) as ItemData
		if item == null:
			push_error("no item %s" % id)
			continue
		var img := draw(SPRITES[id], item.color)
		if img != null:
			img.save_png(ProjectSettings.globalize_path("res://textures/ui/items/%s.png" % id))
			made += 1
	print("made %d icons" % made)
	quit()

static func draw(rows: Array, col: Color) -> Image:
	var pal := PALETTE.duplicate()
	pal["1"] = col.lightened(0.3)
	pal["2"] = col
	pal["3"] = col.darkened(0.35)
	var x0 := 99
	var x1 := -1
	var y0 := 99
	var y1 := -1
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] != ".":
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 - x0 > 13 or y1 - y0 > 13:
		push_error("sprite too big (%d x %d): leave room for the outline" % [x1 - x0 + 1, y1 - y0 + 1])
		return null
	var ox := ceili(7.5 - (x0 + x1) / 2.0)
	var oy := floori(7.5 - (y0 + y1) / 2.0)
	var fill := Image.create(N, N, false, Image.FORMAT_RGBA8)
	fill.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			var c: Color
			if ch == "x":   # chain mail: steel checks
				c = pal["s"] if (x + y) % 2 == 0 else pal["t"]
			else:
				c = pal[ch]
			fill.set_pixel(x + ox, y + oy, c)
	# A 1 px outline round the shape (and round any holes in it), like the hand-made icons.
	var img := fill.duplicate() as Image
	for y in N:
		for x in N:
			if fill.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x >= 0 and p.y >= 0 and p.x < N and p.y < N and fill.get_pixelv(p).a > 0.0:
					img.set_pixel(x, y, OUTLINE)
					break
	img.resize(N * SCALE, N * SCALE, Image.INTERPOLATE_NEAREST)
	return img
