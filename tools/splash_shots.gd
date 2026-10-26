# splash_shots.gd
# Dev tool, not part of the game: plays the launch screen (scenes/splash.tscn) and saves frames of it as
# a sheet, up to the moment it hands over to the menu. Needs a real window (not --headless):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/splash_shots.tscn -- <sheet.png> [--unit]
# --unit crops every frame to the waving unit instead, to see the wave.

extends Node

const SHOT := Vector2i(576, 324)
const TIMES := [0.03, 0.25, 0.5, 0.9, 1.6, 2.4]

func _ready():
	_run.call_deferred()

func _run():
	get_window().size = Vector2i(1152, 648)
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://splash_shots.png"
	var splash: Node = load("res://scenes/splash.tscn").instantiate()
	add_child(splash)
	var t0 := Time.get_ticks_msec()
	var shots: Array[Image] = []
	var times: Array = TIMES if not "--unit" in args else [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]   # a beat of the wave
	for t in times:
		while (Time.get_ticks_msec() - t0) / 1000.0 < t:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if "--unit" in args and splash._stage != null:
			var k := get_viewport().get_final_transform().get_scale()   # the window may not be the base size
			img = img.get_region(Rect2i(Vector2i(splash._stage.position * k), Vector2i(splash._stage.size * k)))
		img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBA8)
		shots.append(img)
	var sheet := Image.create_empty(SHOT.x * 3, SHOT.y * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, SHOT), Vector2i((i % 3) * SHOT.x, (i / 3) * SHOT.y))
	sheet.save_png(out)
	print("splash sheet -> ", out)
	get_tree().quit()
