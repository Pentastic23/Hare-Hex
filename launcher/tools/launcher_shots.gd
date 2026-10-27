# launcher_shots.gd
extends Node

# Dev tool: opens the launcher with the given arguments, waits, and saves a picture of it.
# Godot --path launcher res://tools/launcher_shots.tscn -- out.png 2.5 --releases-url URL --install-dir DIR
# (a window is needed; the launcher reads its own arguments from the same list).

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "launcher.png"
	var wait := float(args[1]) if args.size() > 1 else 2.5
	get_tree().root.size = Vector2i(720, 440)
	add_child(preload("res://launcher.tscn").instantiate())
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
