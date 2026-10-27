# stats_panel_check.gd
extends Node

# Dev tool: drives the STATS panel against a ghost service and saves a picture.
# Godot --path launcher res://tools/stats_panel_check.tscn -- <out.png> <server url> <stats key>
# (a window is needed). It downloads the events, checks the .jsonl / .csv it wrote, and prints them.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "stats.png"
	get_tree().root.size = Vector2i(720, 440)
	var launcher = preload("res://launcher.tscn").instantiate()
	add_child(launcher)
	await get_tree().create_timer(0.5).timeout
	print("stats button: ", launcher._stats_button.visible)
	launcher._show_panel(launcher._stats)
	var panel = launcher._stats
	print("opened: ", panel._status.text)
	panel._server.text = args[1] if args.size() > 1 else ""
	panel._key.text = args[2] if args.size() > 2 else ""
	panel._download()
	for i in 100:
		if not panel._buttons[0].disabled:
			break
		await get_tree().create_timer(0.1).timeout
	print("status: ", panel._status.text)
	for f in panel.last_files:
		var lines := FileAccess.get_file_as_string(f).split("\n", false)
		print("%s: %d lines" % [f.get_file(), lines.size()])
		for l in lines.slice(0, 2):
			print("  ", l.left(200))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit(0 if panel.last_files.size() == 2 else 1)
