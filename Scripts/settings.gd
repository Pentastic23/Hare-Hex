# settings.gd
class_name Settings extends RefCounted

# Player options, stored in user://settings.cfg (separate from the progress save). Static, so it
# needs no autoload; the main menu loads and applies them once per launch (apply()), and a run
# applies the scene parts (apply_light()). The Settings screen (main_menu.gd) edits them.
#
# Things the engine can't do are left out on purpose: Godot can read the monitor's refresh rate but
# not change it (the frame cap can match it), DLSS / XeSS don't exist in Godot, and FSR needs the
# Forward+ renderer (this project uses GL Compatibility, so upscaling is plain render scaling there).

const DEFAULT_PATH := "user://settings.cfg"

const DISPLAY_MODES := ["windowed", "borderless", "exclusive"]
const VSYNC_MODES := ["off", "on", "adaptive"]
const FPS_CAPS := [0, 30, 60, 120, 144, 165, 240, -1]   # 0 = no cap, -1 = match the monitor's refresh rate
const WINDOW_SIZES := [Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const PRESETS := ["low", "medium", "high", "ultra"]   # "custom" once a single graphics option is changed
const PRESET_VALUES := {
	"low": {"render_scale": 0.67, "msaa": 0, "shadows": "off"},
	"medium": {"render_scale": 0.85, "msaa": 2, "shadows": "off"},
	"high": {"render_scale": 1.0, "msaa": 4, "shadows": "low"},
	"ultra": {"render_scale": 1.0, "msaa": 8, "shadows": "high"},
}
const RENDER_SCALES := [1.0, 0.85, 0.77, 0.67, 0.5]   # Off / Ultra quality / Quality / Balanced / Performance
const MSAA_LEVELS := [0, 2, 4, 8]
const SHADOW_LEVELS := ["off", "low", "high"]
const COLORBLIND_MODES := ["off", "protanopia", "deuteranopia", "tritanopia"]
const SENS_MIN := 0.25
const SENS_MAX := 2.0

static var path := DEFAULT_PATH   # tests point this elsewhere
# display
static var display_mode := "windowed"
static var window_size := Vector2i(1152, 648)   # windowed only; fullscreen uses the monitor's resolution
static var vsync_mode := "on"
static var fps_cap := 0
# graphics
static var graphics_preset := "high"
static var render_scale := 1.0
static var msaa := 4
static var shadows := "low"
# controls (multipliers, 1.0 = default)
static var pointer_sens_x := 1.0   # controller pointer, left stick
static var pointer_sens_y := 1.0
static var pan_sens_x := 1.0       # camera panning: mouse drag and right stick
static var pan_sens_y := 1.0
static var zoom_sens := 1.0        # wheel, keys and triggers
# accessibility
static var colorblind := "off"
static var high_contrast := false   # brighter secondary text and a dark outline on every label
static var reduce_motion := false   # no zoom easing, tile pop-in or floating combat words
# audio
static var master_volume := 0.8   # 0..1
static var music_volume := 0.7    # 0..1, the Music bus (the soundtrack, music.gd)
static var sfx_volume := 0.8      # 0..1, the SFX bus (sound effects, sfx.gd)
# HUD state, remembered between sessions
static var show_damage_meter := true   # the Damage button's window
static var dock_collapsed := false     # left box (synergies / items) folded to its rail
static var dock_tab := "synergies"     # left box tab: "synergies" or "items"
static var show_top_bar := true        # top bar (rounds and timer) unfolded
static var _loaded := false

static func ensure_loaded() -> void:
	if not _loaded:
		load_settings()

# Back to the defaults above (every option; the HUD state is kept).
static func reset_options() -> void:
	display_mode = "windowed"
	window_size = Vector2i(1152, 648)
	vsync_mode = "on"
	fps_cap = 0
	set_preset("high")
	pointer_sens_x = 1.0
	pointer_sens_y = 1.0
	pan_sens_x = 1.0
	pan_sens_y = 1.0
	zoom_sens = 1.0
	colorblind = "off"
	high_contrast = false
	reduce_motion = false
	master_volume = 0.8
	music_volume = 0.7
	sfx_volume = 0.8

static func load_settings() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return   # first launch or unreadable: keep the defaults
	# Older files had fullscreen / vsync on-off switches.
	if cfg.has_section_key("display", "fullscreen") and not cfg.has_section_key("display", "mode"):
		display_mode = "borderless" if bool(cfg.get_value("display", "fullscreen")) else "windowed"
	if cfg.has_section_key("display", "vsync") and not cfg.has_section_key("display", "vsync_mode"):
		vsync_mode = "on" if bool(cfg.get_value("display", "vsync")) else "off"
	display_mode = _pick(cfg.get_value("display", "mode", display_mode), DISPLAY_MODES, display_mode)
	var ws = cfg.get_value("display", "window_size", window_size)
	window_size = ws if ws is Vector2i and ws.x >= 640 and ws.y >= 360 else window_size
	vsync_mode = _pick(cfg.get_value("display", "vsync_mode", vsync_mode), VSYNC_MODES, vsync_mode)
	fps_cap = int(_pick(int(cfg.get_value("display", "fps_cap", fps_cap)), FPS_CAPS, fps_cap))
	graphics_preset = _pick(cfg.get_value("graphics", "preset", graphics_preset), PRESETS + ["custom"], graphics_preset)
	render_scale = clampf(float(cfg.get_value("graphics", "render_scale", render_scale)), 0.5, 1.0)
	msaa = int(_pick(int(cfg.get_value("graphics", "msaa", msaa)), MSAA_LEVELS, msaa))
	shadows = _pick(cfg.get_value("graphics", "shadows", shadows), SHADOW_LEVELS, shadows)
	pointer_sens_x = _sens(cfg.get_value("controls", "pointer_sens_x", pointer_sens_x))
	pointer_sens_y = _sens(cfg.get_value("controls", "pointer_sens_y", pointer_sens_y))
	pan_sens_x = _sens(cfg.get_value("controls", "pan_sens_x", pan_sens_x))
	pan_sens_y = _sens(cfg.get_value("controls", "pan_sens_y", pan_sens_y))
	zoom_sens = _sens(cfg.get_value("controls", "zoom_sens", zoom_sens))
	colorblind = _pick(cfg.get_value("accessibility", "colorblind", colorblind), COLORBLIND_MODES, colorblind)
	high_contrast = bool(cfg.get_value("accessibility", "high_contrast", high_contrast))
	reduce_motion = bool(cfg.get_value("accessibility", "reduce_motion", reduce_motion))
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	show_damage_meter = bool(cfg.get_value("hud", "show_damage_meter", show_damage_meter))
	dock_collapsed = bool(cfg.get_value("hud", "dock_collapsed", dock_collapsed))
	dock_tab = str(cfg.get_value("hud", "dock_tab", dock_tab))
	show_top_bar = bool(cfg.get_value("hud", "show_top_bar", show_top_bar))

static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "mode", display_mode)
	cfg.set_value("display", "window_size", window_size)
	cfg.set_value("display", "vsync_mode", vsync_mode)
	cfg.set_value("display", "fps_cap", fps_cap)
	cfg.set_value("graphics", "preset", graphics_preset)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "msaa", msaa)
	cfg.set_value("graphics", "shadows", shadows)
	cfg.set_value("controls", "pointer_sens_x", pointer_sens_x)
	cfg.set_value("controls", "pointer_sens_y", pointer_sens_y)
	cfg.set_value("controls", "pan_sens_x", pan_sens_x)
	cfg.set_value("controls", "pan_sens_y", pan_sens_y)
	cfg.set_value("controls", "zoom_sens", zoom_sens)
	cfg.set_value("accessibility", "colorblind", colorblind)
	cfg.set_value("accessibility", "high_contrast", high_contrast)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("hud", "show_damage_meter", show_damage_meter)
	cfg.set_value("hud", "dock_collapsed", dock_collapsed)
	cfg.set_value("hud", "dock_tab", dock_tab)
	cfg.set_value("hud", "show_top_bar", show_top_bar)
	var err := cfg.save(path)
	if err != OK:
		push_warning("Settings: can't write %s (%s)" % [path, error_string(err)])

static func _pick(v, allowed: Array, fallback):
	return v if allowed.has(v) else fallback

static func _sens(v) -> float:
	return clampf(float(v), SENS_MIN, SENS_MAX)

# Picks a graphics preset and sets the options it stands for.
static func set_preset(p: String) -> void:
	graphics_preset = p
	if PRESET_VALUES.has(p):
		var v: Dictionary = PRESET_VALUES[p]
		render_scale = v.render_scale
		msaa = v.msaa
		shadows = v.shadows

# The monitor's refresh rate in Hz (60 when the OS can't tell).
static func monitor_hz() -> int:
	if DisplayServer.get_name() == "headless":
		return 60
	var hz := DisplayServer.screen_get_refresh_rate()
	return roundi(hz) if hz > 0.0 else 60

# The frame cap in effect: 0 = none.
static func effective_fps_cap() -> int:
	return monitor_hz() if fps_cap == -1 else fps_cap

# The "Music" bus (made on first use, sent to Master); the soundtrack plays on it.
static func music_bus() -> int:
	var idx := AudioServer.get_bus_index("Music")
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	return idx

# The "SFX" bus (made on first use, sent to Master); sound effects play on it.
static func sfx_bus() -> int:
	var idx := AudioServer.get_bus_index("SFX")
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")
	return idx

# Everything that isn't tied to a scene: audio, window, sync, frame cap, render scale and
# anti-aliasing (on the root viewport) and the colour filter. High-contrast text is applied where
# labels are made (HudStyle / DockKit call contrast() and text_color()), so it shows once a screen is rebuilt.
static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	var music := music_bus()
	AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(music, music_volume <= 0.0)
	var sfx := sfx_bus()
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(sfx, sfx_volume <= 0.0)
	Engine.max_fps = effective_fps_cap()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var root := tree.root
		root.scaling_3d_scale = render_scale
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Viewport.SCALING_3D_MODE_FSR
		root.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}[msaa]
		var filter := root.get_node_or_null("ScreenFilter")
		if filter != null:
			filter.refresh()
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = {"windowed": DisplayServer.WINDOW_MODE_WINDOWED, "borderless": DisplayServer.WINDOW_MODE_FULLSCREEN, "exclusive": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN}[display_mode]
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if display_mode == "windowed":
		var screen := DisplayServer.screen_get_size()
		var size := Vector2i(mini(window_size.x, screen.x), mini(window_size.y, screen.y))
		if DisplayServer.window_get_size() != size:
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen - size) / 2)
	DisplayServer.window_set_vsync_mode({"off": DisplayServer.VSYNC_DISABLED, "on": DisplayServer.VSYNC_ENABLED, "adaptive": DisplayServer.VSYNC_ADAPTIVE}[vsync_mode])

# Shadows on a run's sun light (game_manager.gd calls this when a run starts).
static func apply_light(light: DirectionalLight3D) -> void:
	if light == null:
		return
	light.shadow_enabled = shadows != "off"
	if shadows != "off":
		RenderingServer.directional_shadow_atlas_set_size(4096 if shadows == "high" else 2048, true)
		light.shadow_blur = 1.5 if shadows == "high" else 1.0
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if shadows == "low" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

# In high-contrast mode a light label gets a dark outline (dark text on gold chips is left alone,
# an outline would blot it out).
static func contrast(l: Label, c: Color) -> void:
	if high_contrast and c.get_luminance() > 0.35:
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.043, 0.067, 1.0))

# A text colour as it should be drawn: in high-contrast mode grey (muted, dim) text is lifted
# close to the ink colour; coloured text (gold, blue, red) is left alone.
static func text_color(c: Color) -> Color:
	if not high_contrast:
		return c
	if c.get_luminance() < 0.75 and c.s < 0.35:
		return c.lerp(Color("ece6d6"), 0.75)
	return c
