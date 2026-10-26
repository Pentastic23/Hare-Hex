# portrait_studio.gd
class_name PortraitStudio extends SubViewport

# Unit portraits in the board's light. The baked portraits (textures/ui/portraits) are drawn in their own
# flat light, so in a run they looked brighter and more saturated than the same unit on the board. In a
# run the studio redraws each portrait from the unit's 1-star model with the run's environment
# (tres/world_env.tres: tonemap, exposure, saturation, glow) and the biome's sun and ambient light
# (BoardThemes.apply_look), seen from the front, a little to the right and above, like the baked ones.
#
# DockKit.portrait hands out an ImageTexture that starts as the baked portrait and is updated in place
# once its render is done, so shop cards, planner tiles, the inspector and the damage panel all pick it up
# with no code of their own. One portrait a frame, only those asked for; a new biome redraws them.
# Board.apply_theme opens the studio (a child of the run's scene, so it goes when the run does); outside a
# run and in headless runs DockKit gets the baked image. Visual only.

const SIZE := 96
const RENDER := 192        # drawn at twice the size and scaled down, for clean edges
const YAW := 25.0          # degrees to the right of straight on
const PITCH := -14.0       # degrees looking down
const FOV := 30.0
const FILL := 1.45         # how much of the frame the model's bounding sphere fills

static var enabled := DisplayServer.get_name() != "headless"
static var _inst: PortraitStudio
static var _tex := {}      # unit key -> the ImageTexture handed out
static var _data := {}     # unit key -> UnitData
static var _drawn := {}    # unit key -> the biome it was last drawn in
static var rendered := 0   # portraits drawn so far (tests)
static var _bg := Color("1e2230")   # the baked portraits' background (read from the first one handed out)
static var _bg_in := Color(-1, 0, 0)   # the studio background colour that comes out as _bg (found once by measuring)
static var _calibrated := false

var look := &""
var _queue: Array[String] = []
var _busy := false
var _env: Environment
var _sun: DirectionalLight3D
var _cam: Camera3D

# Opens the studio under `scene` (the run) in biome `id`'s light, or switches it to that biome.
static func open(scene: Node, id: StringName) -> void:
	if not enabled or scene == null or not scene.is_inside_tree():
		return
	if not is_instance_valid(_inst) or _inst.get_parent() != scene:
		if is_instance_valid(_inst):
			_inst.queue_free()
		_inst = PortraitStudio.new()
		_drawn.clear()
		scene.add_child.call_deferred(_inst)   # the run applies its biome while its scene is still being set up
	_inst.set_look(id)

# The portrait texture for unit d (`key` its file name): live while a studio is open, else `baked`.
static func texture_for(d: UnitData, key: String, baked: Texture2D) -> Texture2D:
	if not is_instance_valid(_inst) or _inst.is_queued_for_deletion() or d == null or not d.has_model():
		return baked
	if not _tex.has(key):
		var img := _fit(baked.get_image()) if baked != null else Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		if baked != null and _tex.is_empty():
			_bg = img.get_pixel(0, 0)
		_tex[key] = ImageTexture.create_from_image(img)
	_data[key] = d
	if _drawn.get(key, &"") != _inst.look:
		_inst._ask(key)
	return _tex[key]

static func _fit(img: Image) -> Image:
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_size() != Vector2i(SIZE, SIZE):
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img

func _init():
	size = Vector2i(RENDER, RENDER)
	own_world_3d = true
	transparent_bg = false   # a transparent viewport skips the run's colour pass (tonemap, exposure, saturation), so it is opaque
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var we := WorldEnvironment.new()
	_env = (load("res://tres/world_env.tres") as Environment).duplicate()
	_env.background_mode = Environment.BG_COLOR
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false
	add_child(_sun)
	_cam = Camera3D.new()
	_cam.fov = FOV
	add_child(_cam)

func set_look(id: StringName) -> void:
	if id == look:
		return
	look = id
	BoardThemes.apply_look(id, _env, _sun)
	_sun.rotation_degrees.y += YAW   # the sun sits where it does on the board, seen from the portrait's angle
	_env.fog_enabled = false
	for key in _tex:   # everything handed out so far, in the new light
		_ask(key)

func _ask(key: String) -> void:
	if not _queue.has(key):
		_queue.append(key)

func _process(_delta):
	if _busy or _queue.is_empty():
		return
	_draw_next()

func _draw_next() -> void:
	_busy = true
	var key: String = _queue.pop_front()
	var d: UnitData = _data.get(key)
	var scene: PackedScene = d.model if d != null else null
	var model := scene.instantiate() as Node3D if scene != null else null
	if model == null:
		_busy = false
		return
	add_child(model)
	if model is UnitModel:
		(model as UnitModel).set_star(1)
	model.rotation.y = PI   # facing the camera, as your units do at rest
	await get_tree().process_frame   # the idle pose is applied
	if not is_instance_valid(model):
		_busy = false
		return
	_frame(model)
	# The background should come out as the baked portraits' own, after the run's colour pass. The
	# first portrait finds the colour that does that: draw, measure the corner, correct, a few times.
	if _bg_in.r < 0.0:
		_bg_in = _bg
	var img: Image
	for tries in (1 if _calibrated else 6):
		_env.background_color = _bg_in
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		img = get_texture().get_image()
		if _calibrated or not is_instance_valid(model):
			break
		var got := img.get_pixel(0, 0)
		if absf(got.r - _bg.r) + absf(got.g - _bg.g) + absf(got.b - _bg.b) < 0.012 or tries == 5:
			_calibrated = true
			break
		_bg_in = Color(clampf(_bg_in.r * _bg.r / maxf(got.r, 0.002), 0.0, 1.0), clampf(_bg_in.g * _bg.g / maxf(got.g, 0.002), 0.0, 1.0), clampf(_bg_in.b * _bg.b / maxf(got.b, 0.002), 0.0, 1.0))   # it scales about evenly
	if is_instance_valid(model) and _tex.has(key):
		(_tex[key] as ImageTexture).update(_fit(img))
		_drawn[key] = look
		rendered += 1
	if is_instance_valid(model):
		model.queue_free()
	_busy = false

# Points the camera at the whole model, from the portrait's angle.
func _frame(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.3)
	var dist := radius / sin(deg_to_rad(FOV * 0.5)) / FILL
	var dir := Basis.from_euler(Vector3(deg_to_rad(PITCH), deg_to_rad(YAW), 0.0)) * Vector3.BACK
	_cam.position = center + dir * dist
	_cam.look_at(center)
