# menu_shots.gd
# Dev tool, not part of the game: opens the main menu and saves frames of its moving background
# (MenuBackdrop) across one loop as a sheet. Needs a real window (not --headless). With Godot's Movie
# Maker it also records the menu as a video (one loop and a little more):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/menu_shots.tscn [--write-movie menu.avi] -- <sheet.png> [--no-ui]
# --no-ui hides the menu's buttons and panels, to look at the world alone.

extends Node

const SHOT := Vector2i(480, 270)

func _ready():
	_run.call_deferred()

func _run():
	get_window().size = Vector2i(1152, 648)
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://menu_shots.png"
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	var bd: MenuBackdrop = menu.backdrop
	if bd == null:
		push_error("no backdrop (headless?)")
		get_tree().quit()
		return
	if "--no-ui" in args:
		for c in menu.get_children():
			if c is Control and c != bd.curtain and not (c is TextureRect):
				c.visible = false
	while not bd.ready_to_run:
		await get_tree().process_frame
	var times: Array[float] = []   # eight points of the glide, then the dragon: stopping, roaring, fire, the fade
	for i in 8:
		times.append(1.0 + i * (bd.fly_end - 1.0) / 8.0)
	times.append_array([bd.stop - 0.5, bd.roar + 0.3, bd.roar + 1.0, bd.loop_len - 0.3])
	var shots: Array[Image] = []
	for t in times:
		while bd.time < t:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBA8)
		shots.append(img)
		print("t %.1f: %s, %d tiles, %d fps, %d draw calls, %dk triangles" % [bd.time, bd.biome_at(bd.time), bd.tiles_made, Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	while bd.time > 1.0:   # through the seam into the next loop
		await get_tree().process_frame
	var sheet := Image.create_empty(SHOT.x * 4, SHOT.y * 3, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, SHOT), Vector2i((i % 4) * SHOT.x, (i / 4) * SHOT.y))
	sheet.save_png(out)
	print("menu sheet -> ", out)
	get_tree().quit()
