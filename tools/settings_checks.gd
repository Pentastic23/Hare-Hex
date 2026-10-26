# settings_checks.gd
# Dev tool, not part of the game: checks the player settings (settings.gd): every option saves and
# loads, old files (fullscreen / vsync switches) migrate, presets, the frame cap, render scale and
# anti-aliasing on the root viewport, the colour-blind filter, high-contrast text and shadows.
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/settings_checks.tscn
# Prints PASS/FAIL per check and RESULT at the end. Uses a throwaway settings file.

extends Node

var fails := 0

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func _run():
	Settings.path = "user://settings_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))

	print("--- defaults and a full round trip")
	Settings.reset_options()   # the game already loaded your real settings.cfg at startup; start from the defaults
	Settings._loaded = false
	Settings.load_settings()
	chk("no file: defaults (windowed, VSync on, no cap, High preset)", Settings.display_mode == "windowed" and Settings.vsync_mode == "on" and Settings.fps_cap == 0 and Settings.graphics_preset == "high" and Settings.shadows == "low", "%s %s %d %s %s" % [Settings.display_mode, Settings.vsync_mode, Settings.fps_cap, Settings.graphics_preset, Settings.shadows])
	Settings.display_mode = "exclusive"
	Settings.window_size = Vector2i(1600, 900)
	Settings.vsync_mode = "adaptive"
	Settings.fps_cap = -1
	Settings.set_preset("ultra")
	Settings.pointer_sens_x = 1.5
	Settings.pointer_sens_y = 0.5
	Settings.pan_sens_x = 1.25
	Settings.pan_sens_y = 0.75
	Settings.zoom_sens = 2.0
	Settings.colorblind = "deuteranopia"
	Settings.high_contrast = true
	Settings.reduce_motion = true
	Settings.master_volume = 0.35
	Settings.save_settings()
	Settings.reset_options()
	Settings._loaded = false
	Settings.load_settings()
	chk("every option comes back from disk", Settings.display_mode == "exclusive" and Settings.window_size == Vector2i(1600, 900) and Settings.vsync_mode == "adaptive" and Settings.fps_cap == -1 and Settings.graphics_preset == "ultra" and Settings.msaa == 8 and Settings.shadows == "high")
	chk("controls and accessibility come back too", is_equal_approx(Settings.pointer_sens_x, 1.5) and is_equal_approx(Settings.pointer_sens_y, 0.5) and is_equal_approx(Settings.pan_sens_x, 1.25) and is_equal_approx(Settings.pan_sens_y, 0.75) and is_equal_approx(Settings.zoom_sens, 2.0) and Settings.colorblind == "deuteranopia" and Settings.high_contrast and Settings.reduce_motion and is_equal_approx(Settings.master_volume, 0.35))
	Settings.reset_options()
	chk("Reset settings puts every option back", Settings.display_mode == "windowed" and Settings.graphics_preset == "high" and Settings.colorblind == "off" and not Settings.high_contrast and is_equal_approx(Settings.zoom_sens, 1.0))

	print("--- old and broken files")
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", true)
	cfg.set_value("display", "vsync", false)
	cfg.save(Settings.path)
	Settings._loaded = false
	Settings.load_settings()
	chk("an old file's Fullscreen becomes borderless, its VSync off stays off", Settings.display_mode == "borderless" and Settings.vsync_mode == "off")
	cfg = ConfigFile.new()
	cfg.set_value("display", "mode", "sideways")
	cfg.set_value("display", "fps_cap", 97)
	cfg.set_value("controls", "zoom_sens", 50.0)
	cfg.set_value("graphics", "msaa", 3)
	cfg.save(Settings.path)
	Settings.reset_options()
	Settings._loaded = false
	Settings.load_settings()
	chk("unknown values fall back, sensitivities are clamped", Settings.display_mode == "windowed" and Settings.fps_cap == 0 and is_equal_approx(Settings.zoom_sens, Settings.SENS_MAX) and Settings.msaa == 4)

	print("--- applying")
	Settings.reset_options()
	Settings.set_preset("low")
	Settings.fps_cap = 60
	Settings.apply()
	chk("render scale, anti-aliasing and the frame cap are applied", is_equal_approx(get_tree().root.scaling_3d_scale, 0.67) and get_tree().root.msaa_3d == Viewport.MSAA_DISABLED and Engine.max_fps == 60)
	Settings.fps_cap = -1
	chk("Match monitor caps at the monitor's rate", Settings.effective_fps_cap() == Settings.monitor_hz() and Settings.monitor_hz() > 0)
	var filter = get_tree().root.get_node_or_null("ScreenFilter")
	Settings.colorblind = "protanopia"
	Settings.apply()
	chk("the colour-blind filter turns on with its mode", filter != null and filter.rect.visible and (filter.rect.material as ShaderMaterial).get_shader_parameter("mode") == 1)
	Settings.colorblind = "off"
	Settings.apply()
	chk("and off again", not filter.rect.visible)
	Settings.high_contrast = true
	Settings.apply()
	var muted := Settings.text_color(HudStyle.MUTED)
	var light_l := DockKit.text(12, HudStyle.MUTED)
	var dark_l := DockKit.text(12, DockKit.DARK_TEXT)
	chk("high-contrast text: light labels get an outline (not dark text on gold), grey text gets brighter", light_l.get_theme_constant("outline_size") > 0 and dark_l.get_theme_constant("outline_size") == 0 and muted.get_luminance() > HudStyle.MUTED.get_luminance() + 0.1 and Settings.text_color(HudStyle.GOLD) == HudStyle.GOLD)
	Settings.high_contrast = false
	Settings.apply()
	var plain := DockKit.text(12, HudStyle.MUTED)
	chk("high contrast off: no outline, colours unchanged", plain.get_theme_constant("outline_size") == 0 and Settings.text_color(HudStyle.MUTED) == HudStyle.MUTED)
	for l in [light_l, dark_l, plain]:
		l.free()
	var light := DirectionalLight3D.new()
	add_child(light)
	Settings.shadows = "off"
	Settings.apply_light(light)
	var off := not light.shadow_enabled
	Settings.shadows = "high"
	Settings.apply_light(light)
	chk("shadows on the run's light follow the setting", off and light.shadow_enabled)
	light.free()

	print("--- glow & fog")
	Settings.set_preset("low")
	var low_off := not Settings.post_fx
	Settings.set_preset("medium")
	chk("Glow & fog: off in the Low preset, on from Medium up", low_off and Settings.post_fx)
	Settings.post_fx = false
	Settings.save_settings()
	Settings.post_fx = true
	Settings._loaded = false
	Settings.load_settings()
	chk("Glow & fog comes back from disk", not Settings.post_fx)
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	BoardThemes.apply_look(&"volcano", env, sun)
	var fx_off := not env.glow_enabled and not env.fog_enabled
	Settings.post_fx = true
	BoardThemes.apply_look(&"volcano", env, sun)
	var lit: Dictionary = BoardThemes.LIGHT[&"volcano"]
	chk("a biome's look sets the sun, ambient and haze; Glow & fog switches glow and fog", fx_off and env.glow_enabled and env.fog_enabled and sun.light_color.is_equal_approx(Color(lit.sun)) and env.ambient_light_color.is_equal_approx(Color(lit.amb)) and is_equal_approx(sun.rotation_degrees.x, lit.pitch))
	chk("every biome has a look", BoardThemes.ORDER.all(func(id): return BoardThemes.LIGHT.has(id)))
	sun.free()

	print("--- music")
	Settings.music_volume = 0.4
	Settings.save_settings()
	Settings.music_volume = 0.7
	Settings._loaded = false
	Settings.load_settings()
	chk("music volume comes back from disk", is_equal_approx(Settings.music_volume, 0.4))
	Settings.apply()
	var bus := AudioServer.get_bus_index("Music")
	chk("the Music bus exists, sends to Master and follows the slider", bus > 0 and AudioServer.get_bus_send(bus) == &"Master" and is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.4)), "bus %d" % bus)
	Settings.music_volume = 0.0
	Settings.apply()
	chk("music at 0 mutes the Music bus only", AudioServer.is_bus_mute(bus) and not AudioServer.is_bus_mute(0))
	Music.play("menu")
	var menu_stream := Music.playing_stream()
	Music.play("boss")
	chk("Music plays the menu and boss tracks, looping", menu_stream == Music.TRACKS["menu"] and Music.playing_stream() == Music.TRACKS["boss"] and (Music.TRACKS["boss"] as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD)
	Music.stop()

	Settings.reset_options()
	Settings.apply()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = Settings.DEFAULT_PATH
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
