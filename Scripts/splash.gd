# splash.gd
class_name Splash extends Control

# The launch screen (the project's main scene, scenes/splash.tscn): the hare logo and the game's name,
# with a 2-star Assassin waving beside them (just the unit, no tile), then straight into the main menu. Godot's own boot splash
# shows the same logo on the same dark colour while the engine starts (project.godot
# application/boot_splash/*: the logo at its own size, unfiltered, on BG), so the logo is already on
# screen when this scene takes over: it lifts into place, the name rises in under it, the Assassin
# waves, and everything fades back to the menu's own background before the menu fades in.
# The menu loads on a worker thread meanwhile (then the run's assets start, Preload). Any key, click,
# touch or pad button skips ahead. Headless runs (the check suites, the bot) go straight to the menu.

const MENU := "res://scenes/menu.tscn"
const LOGO := preload("res://icon.png")
const BG := Color("0b0c12")       # also application/boot_splash/bg_color
const BOOT_LOGO_PX := 256.0       # the boot splash draws the logo at its own size, in window pixels
const LOGO_SIZE := 210.0
const HOLD := 2.6                 # seconds on screen before it moves on by itself
const FADE := 0.45                # the fade out (shorter when skipped)
const UNIT := "res://tres/assassin.tres"
const UNIT_STAR := 2

static var fade_menu_in := false  # the menu fades its screen in when it comes from here

var _logo: TextureRect
var _title: Label
var _sub: Label
var _stage: SubViewportContainer
var _glow: TextureRect
var _leaving := false
var _shown := 0.0
var _assets_started := false

func _ready():
	if DisplayServer.get_name() == "headless":
		_go.call_deferred()
		return
	get_window().title = "Hare & Hex"
	Settings.ensure_loaded()
	Settings.apply()
	Music.play("menu")   # it carries on into the menu
	RenderingServer.set_default_clear_color(BG)
	ResourceLoader.load_threaded_request(MENU)
	if BugReporter != null:
		BugReporter.visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build.call_deferred()   # once the window has its size

func _build() -> void:
	var w := size
	var plain := ColorRect.new()   # the boot splash's colour, under the menu's radial background
	plain.color = BG
	plain.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(plain)
	_glow = _radial()
	_glow.modulate.a = 0.0
	add_child(_glow)
	# The logo starts exactly where and as big as the boot splash drew it, then lifts into place.
	var px := BOOT_LOGO_PX / get_viewport().get_final_transform().get_scale().y
	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.size = Vector2(px, px)
	_logo.position = (w - _logo.size) * 0.5
	add_child(_logo)
	var logo_end := Vector2(w.x * 0.5 - LOGO_SIZE * 0.5, w.y * 0.34 - LOGO_SIZE * 0.5)
	_title = HudStyle.number(120, HudStyle.GOLD)
	_title.text = "Hare & Hex"
	_title.add_theme_color_override("font_shadow_color", HudStyle.LIP)
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size = Vector2(w.x, 130)
	_title.position = Vector2(0, logo_end.y + LOGO_SIZE + 6)
	_title.modulate.a = 0.0
	add_child(_title)
	_sub = HudStyle.caps(16, HudStyle.MUTED)
	_sub.text = "A HEX AUTO BATTLER"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.size = Vector2(w.x, 24)
	_sub.position = Vector2(0, _title.position.y + 124)
	_sub.modulate.a = 0.0
	add_child(_sub)
	_stage = _unit_stage()
	_stage.position = Vector2(logo_end.x + LOGO_SIZE - 10, logo_end.y + LOGO_SIZE - _stage.size.y + 26)
	_stage.modulate.a = 0.0
	add_child(_stage)
	var calm := Settings.reduce_motion
	var t := create_tween().set_parallel()
	t.tween_property(_glow, "modulate:a", 1.0, 0.6)
	t.tween_property(_logo, "position", logo_end, 0.0 if calm else 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_logo, "size", Vector2(LOGO_SIZE, LOGO_SIZE), 0.0 if calm else 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var rise := _title.position.y
	_title.position.y += 0.0 if calm else 24.0
	t.tween_property(_title, "modulate:a", 1.0, 0.45).set_delay(0.3)
	t.tween_property(_title, "position:y", rise, 0.45).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_sub, "modulate:a", 1.0, 0.4).set_delay(0.6)
	t.tween_property(_stage, "modulate:a", 1.0, 0.35).set_delay(0.45)
	t.tween_callback(func(): Sfx.play(&"merge")).set_delay(0.35)   # a chime as the name lands

func _process(delta: float) -> void:
	if _leaving:
		return
	_shown += delta
	if not _assets_started and ResourceLoader.load_threaded_get_status(MENU) == ResourceLoader.THREAD_LOAD_LOADED:
		_assets_started = true
		Preload.warm_run()   # the menu would start this anyway; begin it now
	if _assets_started:
		Preload.collect()
	if _shown >= HOLD:
		_leave(FADE)

func _input(event: InputEvent) -> void:
	if _leaving or _shown < 0.3:
		return
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if press:
		get_viewport().set_input_as_handled()
		_leave(0.2)   # skipped

# Everything but the menu's background fades out, then the menu takes over (and fades its screen in).
func _leave(secs: float) -> void:
	_leaving = true
	var t := create_tween().set_parallel()
	for n in [_logo, _title, _sub, _stage]:
		if n != null:
			t.tween_property(n, "modulate:a", 0.0, secs)
	t.chain().tween_callback(_go)

func _go() -> void:
	if BugReporter != null:
		BugReporter.visible = true
	fade_menu_in = DisplayServer.get_name() != "headless"
	var scene: PackedScene
	if ResourceLoader.load_threaded_get_status(MENU) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		scene = ResourceLoader.load_threaded_get(MENU) as PackedScene   # waits if it isn't done yet
	if scene == null:
		scene = load(MENU) as PackedScene
	get_tree().change_scene_to_packed(scene)

# The main menu's dark radial background, so the hand-over to the menu doesn't show.
func _radial() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color("1a1e2c"))
	g.set_color(1, BG)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.1, 1.1)
	tex.width = 256
	tex.height = 256
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# The Assassin in its own little world, waving at the viewer, lit like a run in the forest.
func _unit_stage() -> SubViewportContainer:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.size = Vector2(230, 280)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	holder.add_child(vp)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var sun := DirectionalLight3D.new()
	BoardThemes.apply_look(&"forest", env, sun)
	env.fog_enabled = false
	env.glow_enabled = false
	env.ambient_light_energy *= 3.0   # brighter than the board: a transparent view skips the run's colour pass, and it stands alone on the dark screen
	sun.light_energy *= 2.6
	sun.rotation_degrees.y += 20.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	vp.add_child(sun)
	var d := load(UNIT) as UnitData
	var model := d.model.instantiate() as UnitModel if d != null and d.has_model() else null
	if model != null:
		vp.add_child(model)
		model.set_star(UNIT_STAR)
		model.scale = Vector3.ONE * Unit.STAR_SIZE[UNIT_STAR]
		model.rotation.y = PI + 0.35   # facing the viewer, turned a little toward the logo
		model.wave()
	var cam := Camera3D.new()
	cam.fov = 27.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.9, 2.3, 4.6), Vector3(0, 1.0, 0))
	return holder
