# shader_warmup.gd
class_name ShaderWarmup extends Node

# scenes/shader_warmup.tscn: draws, once and out of sight, every kind of material a run uses (each unit
# model at 1 and 3 stars, the voxel tiles, the bars, rings, labels and spell-effect cubes) in a small
# SubViewport. The renderer compiles each shader the first time it draws it, which on a cold start
# (the first launch, a new build or driver) stalls the first fight for a couple of seconds; this does
# it on the main menu instead, a few models per frame, after Preload has loaded them. Visual only; it
# frees itself when done. MainMenu adds it once per session (`done`).

const PER_FRAME := 4       # models added per frame, so the menu never hitches badly
const HOLD_FRAMES := 2     # frames each batch stays drawn

static var done := false

@onready var stage: Node3D = $SubViewport/Stage
@onready var light: DirectionalLight3D = $SubViewport/Light
@onready var world: WorldEnvironment = $SubViewport/WorldEnvironment

func _ready():
	Settings.apply_light(light)   # shadows on or off like the run's light, so the same shaders compile
	world.environment = world.environment.duplicate()   # fog on or off like the run's (Glow & fog), so the same shaders compile
	world.environment.fog_enabled = Settings.post_fx
	world.environment.glow_enabled = Settings.post_fx
	_run.call_deferred()

func _run():
	_add_misc()
	await _hold()
	if not is_inside_tree():
		return
	var models: Array[String] = []
	for f in ResourceLoader.list_directory("res://scenes/models"):
		if f.ends_with(".tscn"):
			models.append("res://scenes/models/" + f)
	for i in range(0, models.size(), PER_FRAME):
		var k := 0
		for path in models.slice(i, i + PER_FRAME):
			var scene := load(path) as PackedScene
			if scene == null:
				continue
			for star in [1, 3]:
				var m := scene.instantiate() as UnitModel
				if m == null:
					continue
				stage.add_child(m)
				m.set_star(star)
				m.position = Vector3((k % 4) - 1.5, 0, (k / 4) - 1.0)   # side by side, all in view
				k += 1
		await _hold()
		if not is_inside_tree():
			return   # the menu was left mid-way (a run started): it warms up again next time
		for c in stage.get_children():
			c.queue_free()
	done = true
	queue_free()

func _hold():
	for i in HOLD_FRAMES:
		if not is_inside_tree():
			return
		await get_tree().process_frame

# The materials that aren't unit models: a themed tile block, a health bar sprite, a label, the team
# ring and the spell-effect cubes (opaque and see-through), and a zone disc.
func _add_misc():
	for part in ["base_1", "shrine"]:   # the voxel tiles' two materials (lit and glowing), the same in every biome
		var tile := MeshInstance3D.new()
		tile.mesh = BoardThemes.tile(BoardThemes.DEFAULT, part)
		stage.add_child(tile)
	var mirage := MeshInstance3D.new()   # and the see-through desert mirage
	mirage.mesh = BoardThemes.tile(BoardThemes.DEFAULT, "flowers")
	mirage.material_override = Board._mirage_mat()
	stage.add_child(mirage)
	var bar := Sprite3D.new()
	bar.texture = Unit.bar_texture()
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.shaded = false
	bar.no_depth_test = true
	bar.position.y = 1.5
	stage.add_child(bar)
	var label := Label3D.new()
	label.text = "CAST"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 2.0
	stage.add_child(label)
	for c in [Color(1, 0.8, 0.3), Color(0.5, 0.8, 1, 0.5)]:
		var cube := Vfx.cube(0.3, c)
		cube.position = Vector3(0.6, 0.6, 0)
		stage.add_child(cube)
	var ring := MeshInstance3D.new()
	ring.mesh = Unit.RING_MESH
	ring.material_override = Unit.RING_MATS[0]
	stage.add_child(ring)
