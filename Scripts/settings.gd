# settings.gd
class_name Settings extends RefCounted

# Player options, stored in user://settings.cfg (separate from the progress save). Static, so it
# needs no autoload; the main menu loads and applies them once per launch.

const DEFAULT_PATH := "user://settings.cfg"

static var path := DEFAULT_PATH   # tests point this elsewhere
static var fullscreen := false
static var vsync := true
static var master_volume := 0.8   # 0..1
static var show_damage_meter := true   # the Damage button's window, remembered between sessions
static var show_synergies := true      # synergy list unfolded
static var show_items := true          # item bar unfolded
static var _loaded := false

static func ensure_loaded() -> void:
	if not _loaded:
		load_settings()

static func load_settings() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return   # first launch or unreadable: keep the defaults
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	show_damage_meter = bool(cfg.get_value("hud", "show_damage_meter", show_damage_meter))
	show_synergies = bool(cfg.get_value("hud", "show_synergies", show_synergies))
	show_items = bool(cfg.get_value("hud", "show_items", show_items))

static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("hud", "show_damage_meter", show_damage_meter)
	cfg.set_value("hud", "show_synergies", show_synergies)
	cfg.set_value("hud", "show_items", show_items)
	var err := cfg.save(path)
	if err != OK:
		push_warning("Settings: can't write %s (%s)" % [path, error_string(err)])

static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
