# king_shots.gd
# Dev tool, not part of the game: pictures of the kings. Needs a real window (not --headless):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/king_shots.tscn -- <out.png>            every skin's model, front and three-quarter
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/king_shots.tscn -- <out.png> strike [skin,skin]
# `facing` shows your king in prep and in a fight, side by side.
# `strike` plays each skin's attack in a free-play fight and saves a row of frames per skin, cropped to
# the king and the unit it strikes (all skins unless some are named).

extends Node

const CELL := Vector2i(256, 256)
const STRIKE_CELL := Vector2i(320, 220)
const STRIKE_TIMES := [0.0, 0.12, 0.2, 0.3, 0.45, 0.7]

func _ready():
	_run.call_deferred()

func _run():
	get_window().size = Vector2i(1152, 648)
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://king_shots.png"
	Settings.path = "user://king_shots_settings.cfg"   # never the player's own settings
	SaveGame.path = "user://king_shots_save.json"
	if args.size() > 1 and args[1] == "strike":
		var skins: Array = Array(args[2].split(",")) if args.size() > 2 else KingSkins.ORDER.duplicate()
		await _strikes(out, skins)
	elif args.size() > 1 and args[1] == "facing":
		await _facing(out)
	elif args.size() > 1 and args[1] == "tab":
		await _tabs(out, Array(args[2].split(",")) if args.size() > 2 else KingSkins.ORDER.duplicate())
	elif args.size() > 1 and args[1] == "menu":
		SaveGame.set_king_skin("dragon")
		var menu: Node = load("res://scenes/menu.tscn").instantiate()
		add_child(menu)
		for i in 10:
			await get_tree().process_frame
		menu._show_panel(menu.king_panel)
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
	else:
		await _gallery(out)
	get_tree().quit()

# Every model on a turntable, front view above and three-quarter below.
func _gallery(out: String) -> void:
	var ids := KingSkins.ORDER
	var sheet := Image.create_empty(CELL.x * ids.size(), CELL.y * 2, false, Image.FORMAT_RGBA8)
	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = load("res://tres/world_env.tres")
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.5, -4.6), Vector3(0, 0.85, 0))
	var m := MeshInstance3D.new()
	vp.add_child(m)
	for i in ids.size():
		m.mesh = KingSkins.model(ids[i])
		m.material_override = King.shadow_mat() if ids[i] == &"shadow" else null
		for row in 2:
			m.rotation.y = 0.0 if row == 0 else -0.8
			for f in 3:
				await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, row * CELL.y))
	sheet.save_png(out)
	print("kings -> ", out)

# Each skin's attack in a real fight: a unit of yours and an enemy, the beat about to come.
func _strikes(out: String, skins: Array) -> void:
	Settings.ensure_loaded()
	Settings.dock_collapsed = true
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 7
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	for i in 3:
		await get_tree().process_frame
	(main.get_node("UI") as CanvasLayer).visible = false
	var gm = main.get_node("Game Manager")
	var board: Board = main.get_node("Board")
	var cam: Camera3D = main.get_node("CameraRig/Camera3D")
	var sheet := Image.create_empty(STRIKE_CELL.x * STRIKE_TIMES.size(), STRIKE_CELL.y * skins.size(), false, Image.FORMAT_RGBA8)
	for row in skins.size():
		var skin := StringName(skins[row])
		board.kings[0].set_skin(skin)
		var foe := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(foe)
		foe.setup(load("res://tres/units/guardian.tres") if ResourceLoader.exists("res://tres/units/guardian.tres") else load("res://tres/knight.tres"), 1)
		foe.stat_scale = 50.0
		board.put_enemy_on_tile(foe, Vector2i(2, 3))
		var mine := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(mine)
		mine.setup(load("res://tres/knight.tres"), 0)
		mine.stat_scale = 50.0
		board.put_on_tile(mine, Vector2i(3, 4))
		gm.opponents = WaveOpponents.new([] as Array[EnemyBoard], 1.0)
		gm.start_combat()
		gm.runner.king_skins = [skin, &""]
		gm.runner.ticks = CombatRunner.KING_PERIOD - 1
		var k: Node3D = board.kings[0]
		var mid := cam.unproject_position(k.global_position.lerp(foe.global_position, 0.3) + Vector3(0, 1.0, 0))
		var scale := get_viewport().get_final_transform().get_scale()
		gm.combat_tick()   # the beat: the kings strike
		var t0 := Time.get_ticks_msec()
		for col in STRIKE_TIMES.size():
			while Time.get_ticks_msec() - t0 < STRIKE_TIMES[col] * 1000.0:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var size := Vector2(STRIKE_CELL) * 0.55
			var r := Rect2i(Vector2i((mid - size / 2.0) * scale), Vector2i(size * scale)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			img = img.get_region(r)
			img.resize(STRIKE_CELL.x, STRIKE_CELL.y, Image.INTERPOLATE_BILINEAR)
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, STRIKE_CELL), Vector2i(col * STRIKE_CELL.x, row * STRIKE_CELL.y))
		gm.runner.stop()
		gm.fighting = false
		for n in board.get_node("Units").get_children():
			n.queue_free()
		for t in board.tiles.values():
			t.occupant = null
		await get_tree().create_timer(0.6).timeout
	sheet.save_png(out)
	print("strikes -> ", out)

# The King tab for each skin after a few rounds of its power (sold units, quests, a hoard...), cropped
# to the left box, side by side.
func _tabs(out: String, skins: Array) -> void:
	var crop := Rect2i(0, 0, 250, 600)
	var sheet := Image.create_empty(crop.size.x * skins.size(), crop.size.y, false, Image.FORMAT_RGBA8)
	for i in skins.size():
		var skin := StringName(skins[i])
		SaveGame.set_king_skin(String(skin))
		GameState.run_level = null
		GameState.run_carry = {}
		GameState.next_seed = 31
		var main: Node = load("res://scenes/main.tscn").instantiate()
		main.get_node("Game Manager").prep_time = 9999
		add_child(main)
		for f in 4:
			await get_tree().process_frame
		var gm = main.get_node("Game Manager")
		var p := GameState.me
		p.gold = 64
		p.level = 6
		if skin == &"necromancer":
			for n in ["knight", "archer", "militia", "knight"]:
				var u: Unit = gm.board.make_unit(load("res://tres/%s.tres" % n) if ResourceLoader.exists("res://tres/%s.tres" % n) else load("res://tres/units/%s.tres" % n), gm.unit_scene)
				gm.board.put_on_bench(u, gm.board.first_free_bench())
				gm.board.sell_unit(u)
		for r in [2, 3, 4, 6]:
			KingPowers.prep_start(gm.rules, r, false)
		if skin == &"explorer":
			p.king_state.quests.append({"id": "rich", "state": "open"})
			KingPowers.check(gm.rules)
		var dock = main.find_child("LeftDock", true, false)
		dock.set_collapsed(false)
		dock.show_tab("king")
		for f in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var k := get_viewport().get_final_transform().get_scale()
		img = img.get_region(Rect2i(Vector2i(Vector2(crop.position) * k), Vector2i(Vector2(crop.size) * k)))
		img.resize(crop.size.x, crop.size.y)
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, crop.size), Vector2i(i * crop.size.x, 0))
		main.queue_free()
		for f in 3:
			await get_tree().process_frame
	sheet.save_png(out)
	print("tabs -> ", out)

# Your king in prep (facing the camera) and once a fight has started (turned to the enemy), side by side.
func _facing(out: String) -> void:
	Settings.ensure_loaded()
	Settings.dock_collapsed = true
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 7
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	for i in 3:
		await get_tree().process_frame
	(main.get_node("UI") as CanvasLayer).visible = false
	var gm = main.get_node("Game Manager")
	var board: Board = main.get_node("Board")
	var cam: Camera3D = main.get_node("CameraRig/Camera3D")
	board.kings[0].set_skin(&"lion")
	var ally := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(ally)
	ally.setup(load("res://tres/knight.tres"), 0)
	ally.stat_scale = 50.0   # so the fight lasts
	board.put_on_tile(ally, Vector2i(3, 4))
	var shots: Array[Image] = []
	for fight in [false, true]:
		if fight:
			gm._enter(Events.Phase.COMBAT)
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var scale := get_viewport().get_final_transform().get_scale()
		var mid := cam.unproject_position(board.kings[0].global_position + Vector3(0, 0.8, 0)) * scale
		var r := Rect2i(Vector2i(mid) - Vector2i(160, 160), Vector2i(320, 320)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		shots.append(img.get_region(r))
	var sheet := Image.create_empty(shots[0].get_width() * 2, shots[0].get_height(), false, shots[0].get_format())
	sheet.blit_rect(shots[0], Rect2i(Vector2i.ZERO, shots[0].get_size()), Vector2i.ZERO)
	sheet.blit_rect(shots[1], Rect2i(Vector2i.ZERO, shots[1].get_size()), Vector2i(shots[0].get_width(), 0))
	sheet.save_png(out)
