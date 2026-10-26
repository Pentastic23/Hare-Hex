# weapon_shots.gd
# Dev tool, not part of the game: poses unit models in every clip, to check that held weapons stay in
# their hands. One row per unit, one column per pose (a clip at a time), seen from the front-left.
# Needs a real window (not --headless):
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/weapon_shots.tscn -- <out.png> <star> <yaw> <model> [<model> ...]
# <yaw> turns the models (degrees; 35 = front-left, 90 = side on). <model> is a scene name in scenes/models/ (knight, archer, titan, ...).

extends Node3D

const POSES := [["idle", 0.8], ["walk", 0.2], ["attack", 0.3], ["attack", 0.42], ["skill", 0.4], ["skill", 0.9],
		["hit", 0.09], ["victory", 0.25], ["death", 1.2]]
const CELL := Vector2(2.4, 2.4)    # metres between models (square, like the pixel cells)
const PX := 200                    # pixels per cell

func _ready():
	_run.call_deferred()

func _run():
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://weapon_shots.png"
	var star := int(args[1]) if args.size() > 1 else 1
	var yaw := float(args[2]) if args.size() > 2 else 35.0
	var names: Array = args.slice(3) if args.size() > 3 else ["knight", "archer", "titan"]
	get_window().size = Vector2i(PX * POSES.size(), PX * names.size())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#202128")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	for r in names.size():
		for c in POSES.size():
			var m := (load("res://scenes/models/%s.tscn" % names[r]) as PackedScene).instantiate() as UnitModel
			add_child(m)
			m.set_star(star)
			m.set_process(false)
			m.position = Vector3(c * CELL.x, -r * CELL.y, 0)
			m.rotation.y = PI + deg_to_rad(yaw)   # the model is turned to face -Z; face the camera, turned by yaw
			var anim: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false).front()
			anim.play(POSES[c][0])
			anim.seek(POSES[c][1], true)
			anim.pause()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CELL.y * names.size()
	cam.position = Vector3((POSES.size() - 1) * CELL.x / 2.0, -(names.size() - 1) * CELL.y / 2.0 + 0.8, 10)
	add_child(cam)
	if has_node("/root/BugReporter"):
		get_node("/root/BugReporter").visible = false
	cam.make_current()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
