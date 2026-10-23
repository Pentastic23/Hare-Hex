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
static var dock_collapsed := false     # left box (synergies / items) folded to its rail
static var dock_tab := "synergies"     # left box tab: "synergies" or "items"
static var show_top_bar := true        # top bar (rounds and timer) unfolded
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
	dock_collapsed = bool(cfg.get_value("hud", "dock_collapsed", dock_collapsed))
	dock_tab = str(cfg.get_value("hud", "dock_tab", dock_tab))
	show_top_bar = bool(cfg.get_value("hud", "show_top_bar", show_top_bar))

static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("hud", "show_damage_meter", show_damage_meter)
	cfg.set_value("hud", "dock_collapsed", dock_collapsed)
	cfg.set_value("hud", "dock_tab", dock_tab)
	cfg.set_value("hud", "show_top_bar", show_top_bar)
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
