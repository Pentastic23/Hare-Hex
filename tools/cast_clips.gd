# cast_clips.gd
# Dev tool, not part of the game: records one unit's cast up close, to look at its spell effect. Sets up
# the caster against a few enemies (who never cast), zooms in, starts the fight with the caster's mana
# full, saves a strip of frames as one PNG and quits. Needs a real window (not --headless). With Godot's
# Movie Maker it also records the cast as a video:
#   Godot_v4.7.2-stable_win64.exe --path . res://tools/cast_clips.tscn --write-movie <clip.avi> -- <cast> <strip.png>
# <cast> is a key of CASTS (ice_mage, dragon, sparkcaller, assassin, titan, pyromancer, phoenix).

extends Node

const SHOT := Vector2i(576, 324)
const FRAMES := [4, 10, 18, 28, 42, 60]   # frames after the cast to put in the strip (60 a second)
const LENGTH := 150                       # frames recorded after the fight starts

# caster, its tile, and the enemies (unit, tile) placed so its ability shows well.
const CASTS := {
	"ice_mage": ["ice_mage", Vector2i(3, 6), [["guardian", Vector2i(3, 3)], ["knight", Vector2i(2, 3)], ["knight", Vector2i(4, 3)], ["militia", Vector2i(3, 2)]]],
	"dragon": ["dragon", Vector2i(3, 5), [["guardian", Vector2i(3, 4)], ["knight", Vector2i(3, 3)], ["knight", Vector2i(2, 3)], ["militia", Vector2i(4, 3)]]],
	"sparkcaller": ["sparkcaller", Vector2i(3, 6), [["guardian", Vector2i(3, 4)], ["knight", Vector2i(3, 3)], ["militia", Vector2i(3, 2)]]],
	"assassin": ["assassin", Vector2i(3, 5), [["guardian", Vector2i(3, 4)], ["knight", Vector2i(2, 3)], ["archer", Vector2i(3, 1)]]],
	"titan": ["titan", Vector2i(3, 5), [["guardian", Vector2i(3, 4)], ["knight", Vector2i(2, 4)], ["knight", Vector2i(4, 3)], ["militia", Vector2i(3, 2)], ["archer", Vector2i(5, 1)]]],
	"pyromancer": ["pyromancer", Vector2i(3, 6), [["guardian", Vector2i(3, 3)], ["knight", Vector2i(2, 3)], ["knight", Vector2i(4, 3)]]],
	"phoenix": ["phoenix", Vector2i(3, 6), [["guardian", Vector2i(3, 3)], ["knight", Vector2i(2, 3)], ["knight", Vector2i(4, 2)], ["militia", Vector2i(3, 1)]]],
}

func _ready():
	_run.call_deferred()

func UD(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

func _run():
	get_window().size = Vector2i(1152, 648)
	var args := OS.get_cmdline_user_args()
	var key: String = args[0] if not args.is_empty() else "ice_mage"
	var out: String = args[1] if args.size() > 1 else "user://cast_%s.png" % key
	var setup: Array = CASTS[key]
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 11
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	for i in 3:
		await get_tree().process_frame
	var gm = main.get_node("Game Manager")
	var board: Board = main.get_node("Board")
	board.apply_theme(&"forest", 11)
	GameState.me.level = 9
	board.refresh_unlocks(9, false)
	var caster := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(caster)
	caster.setup(UD(setup[0]), 0)
	board.put_on_tile(caster, setup[1])
	var wave := EnemyBoard.new()
	wave.display_name = "Targets"
	for e in setup[2]:
		var bu := BoardUnit.new()
		bu.unit = UD(e[0])
		bu.coord = e[1]
		bu.star = 2
		wave.units.append(bu)
	var waves: Array[EnemyBoard] = [wave]
	gm.opponents = WaveOpponents.new(waves, 1.0)
	var rig = main.get_node("CameraRig")   # zoomed in on the fight
	rig.zoom = 0.7
	rig._zoom_now = 0.7
	rig._place()
	for i in 20:   # let the view settle
		await get_tree().process_frame
	gm.start_combat()
	for u in gm.combatants:
		u.mana = u.data.max_mana if u == caster else 0.0
		if u != caster:
			u.data = u.data.duplicate()   # the targets never fill up and cast
			u.data.max_mana = 0.0
	var shots: Array[Image] = []
	var cast_at := -1
	for f in LENGTH:
		await get_tree().process_frame
		if cast_at < 0 and caster.mana < caster.data.max_mana:
			cast_at = f
		if cast_at >= 0 and (f - cast_at) in FRAMES:
			var img := get_viewport().get_texture().get_image()
			img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_BILINEAR)
			img.convert(Image.FORMAT_RGBA8)
			shots.append(img)
	var sheet := Image.create_empty(SHOT.x * 3, SHOT.y * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, SHOT), Vector2i((i % 3) * SHOT.x, (i / 3) * SHOT.y))
	sheet.save_png(out)
	print("%s: cast at frame %d, %d frames in the strip -> %s" % [key, cast_at, shots.size(), out])
	get_tree().quit()
