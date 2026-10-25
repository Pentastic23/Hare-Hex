# voxel_gallery.gd
# Dev tool, not part of the game: renders every biome's baked voxel tiles (base, bench, sell, the decor
# variants and trees) in a row, one row per biome, into one sheet. Needs a window (not --headless):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/voxel_gallery.tscn -- <output.png> [biome ...]

extends Node3D

const SHOT := Vector2i(1152, 200)

func _ready():
	_run.call_deferred()

func _run():
	get_window().size = Vector2i(SHOT.x, 360)
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://voxel_gallery.png"
	var biomes: Array = args.slice(1) if args.size() > 1 else VoxelTiles.BIOMES.keys()
	var cam := Camera3D.new()
	cam.fov = 26.0
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	add_child(env)
	var rows: Array[Image] = []
	for biome in biomes:
		env.environment.background_color = Color(VoxelTiles.BIOMES[biome].backdrop)
		var holder := Node3D.new()
		add_child(holder)
		var parts: Array = VoxelTiles.PARTS
		for i in parts.size():
			var m := MeshInstance3D.new()
			m.mesh = VoxelTiles.mesh(biome, parts[i])
			m.position = Vector3((i - (parts.size() - 1) / 2.0) * 1.9, 0, 0)
			holder.add_child(m)
		cam.position = Vector3(0, 9.0, 12.5)
		cam.look_at(Vector3(0, 0.3, 0))
		for f in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.resize(SHOT.x, int(SHOT.x * img.get_height() / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBA8)
		rows.append(img)
		holder.queue_free()
		await get_tree().process_frame
		print("rendered ", biome)
	var h := rows[0].get_height()
	var sheet := Image.create_empty(SHOT.x, h * rows.size(), false, Image.FORMAT_RGBA8)
	for i in rows.size():
		sheet.blit_rect(rows[i], Rect2i(Vector2i.ZERO, rows[i].get_size()), Vector2i(0, i * h))
	sheet.save_png(out)
	print("sheet -> ", out)
	get_tree().quit()
