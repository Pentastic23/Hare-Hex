# portrait_shots.gd
# Dev tool, not part of the game: compares the unit portraits with the units on the board. For each biome
# it starts a run, puts a few units on the board, waits for PortraitStudio to draw their portraits, and saves
# one sheet: per biome a row of [baked, live] portrait pairs and a crop of the board with those units.
# Needs a real window (not --headless):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/portrait_shots.tscn -- <output.png> [biome,biome,...]

extends Node

const UNITS := ["dragon", "knight", "ice_mage", "druid", "titan", "assassin"]
const CELL := 96
const CROP := Vector2i(576, 216)

func _ready():
	_run.call_deferred()

func UD(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

func _run():
	get_window().size = Vector2i(1152, 648)
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://portrait_shots.png"
	var biomes: Array = (args[1].split(",") if args.size() > 1 else PackedStringArray(["forest", "volcano", "snow"]))
	var row_h := maxi(CELL, CROP.y)
	var sheet := Image.create_empty(CELL * 2 * UNITS.size() + CROP.x, row_h * biomes.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("14161f"))
	for bi in biomes.size():
		GameState.run_level = null
		GameState.run_carry = {}
		GameState.next_seed = 11
		var main: Node = load("res://scenes/main.tscn").instantiate()
		main.get_node("Game Manager").prep_time = 9999
		add_child(main)
		for i in 3:
			await get_tree().process_frame
		var board: Board = main.get_node("Board")
		board.apply_theme(StringName(biomes[bi]), 11)
		GameState.me.level = 9
		board.refresh_unlocks(9, false)
		var live: Array[Texture2D] = []
		for i in UNITS.size():
			var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
			board.get_node("Units").add_child(u)
			u.setup(UD(UNITS[i]), 0)
			board.put_on_tile(u, Vector2i(i, 5))
			live.append(DockKit.portrait(u.data))
		var rig = main.get_node("CameraRig")
		rig.zoom = 0.65
		rig._zoom_now = 0.65
		rig._place()
		var want := PortraitStudio.rendered + UNITS.size()
		for i in 240:
			await get_tree().process_frame
			if PortraitStudio.rendered >= want and i > 30:
				break
		await RenderingServer.frame_post_draw
		var y := bi * row_h
		for i in UNITS.size():
			var baked := (load("res://textures/ui/portraits/%s.png" % UD(UNITS[i]).resource_path.get_file().get_basename()) as Texture2D).get_image()
			baked.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(baked, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL * 2, y))
			var li := live[i].get_image()
			li.convert(Image.FORMAT_RGBA8)
			if i == 0:
				print("%s: background baked %s, live %s" % [biomes[bi], baked.get_pixel(0, 0).to_html(false), li.get_pixel(0, 0).to_html(false)])
			var bg := Image.create_empty(CELL, CELL, false, Image.FORMAT_RGBA8)
			bg.fill(Color("1e2230"))
			bg.blend_rect(li, Rect2i(0, 0, CELL, CELL), Vector2i.ZERO)
			sheet.blit_rect(bg, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL * 2 + CELL, y))
		var shot := get_viewport().get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		if bi == 0:   # the whole screen once, to see the shop cards
			shot.save_png(out.get_basename() + "_screen.png")
		var cam := get_viewport().get_camera_3d()
		var mid := cam.unproject_position(board.display_pos(Vector2i(3, 5)) + Vector3(0, 0.8, 0))
		var from := Vector2i(clampi(int(mid.x) - CROP.x / 2, 0, shot.get_width() - CROP.x), clampi(int(mid.y) - CROP.y / 2, 0, shot.get_height() - CROP.y))
		sheet.blit_rect(shot, Rect2i(from, CROP), Vector2i(CELL * 2 * UNITS.size(), y))
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	sheet.save_png(out)
	print("portrait sheet -> ", out, "  (drawn: ", PortraitStudio.rendered, ")")
	get_tree().quit()
