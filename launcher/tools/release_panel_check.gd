# release_panel_check.gd
extends Node

const PanelScript := preload("res://release_panel.gd")

# Dev tool: drives the release panel through a dry run (nothing is uploaded) and saves pictures.
# Godot --path launcher res://tools/release_panel_check.tscn -- <out folder> [version]
# (a window is needed). It first presses RELEASE once with dry run off, which only shows the
# confirmation (or the missing-token message), then does a dry run of <version> (default: the
# version already in export_presets.cfg, so nothing changes).

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else OS.get_user_data_dir()
	var version := args[1] if args.size() > 1 else "0.1.3"
	get_tree().root.size = Vector2i(720, 440)
	var launcher = preload("res://launcher.tscn").instantiate()
	add_child(launcher)
	await get_tree().create_timer(1.0).timeout
	print("project: '%s', release button: %s" % [launcher.project_dir, launcher._release_button.visible])
	if launcher.project_dir == "":
		get_tree().quit(1)
		return
	launcher._show_release(true)
	var panel = launcher._release
	panel._version.text = PanelScript.next_version("v" + version)
	panel._go.pressed.emit()
	await _shot(out.path_join("release_confirm.png"))
	print("first press: ", panel._status.text)
	panel._version.text = version
	panel._dry.button_pressed = true
	var result := []
	panel.finished.connect(func(ok, dry): result.append_array([ok, dry]))
	panel._go.pressed.emit()
	await get_tree().create_timer(15.0).timeout
	await _shot(out.path_join("release_running.png"))
	while result.is_empty():
		await get_tree().create_timer(0.5).timeout
	print("finished: ok=%s dry=%s" % result)
	print("status: ", panel._status.text)
	await _shot(out.path_join("release_done.png"))
	get_tree().quit(0 if result[0] else 1)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
