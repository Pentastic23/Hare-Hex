# main_menu.gd
extends Control

# The first screen: title, Continue (saved chapter run), then two sections:
#   SINGLE PLAYER: Tutorial, Campaign (chapters and levels), Free Play
#   PVP: Async PvP (ghost opponents, playable) and Live PvP (coming later: opens an info panel)
# and Settings / Keybinds / Quit. Built in code; menu.tscn is just this script on a full-screen Control.

const TITLE := "Hare & Hex"
const MAIN_SCENE := "res://scenes/main.tscn"
const CAMPAIGN_PATH := "res://tres/campaign/campaign.tres"
const TUTORIAL_PATH := "res://tres/campaign/tutorial.tres"
const GOLD := HudStyle.GOLD
const GREY := HudStyle.MUTED
const PVP_TINT := HudStyle.YOU
const ASYNC_PVP_TIP := "Free play against ghosts: boards saved from earlier runs. Your own boards are saved too. No ghosts yet? You meet random enemies."
const LIVE_PVP_TEXT := "Real-time matches with up to 8 players on a server: one shared unit pool, a fight against another player every round, last one standing wins.\n\nComing later. Async PvP comes first."

var campaign: Campaign
var main_box: VBoxContainer
var continue_button: Button
var tutorial_button: Button
var campaign_panel: PanelContainer
var settings_panel: PanelContainer
var keybinds_panel: PanelContainer   # keyboard and controller binds (keybinds.gd)
var keybinds_grid: GridContainer
var keybinds_hint: Label
var keybinds_tab := "keyboard"       # or "controller"
var keybinds_tabs := {}
var _listening := ""                 # id of the action waiting for a key / button, or ""
var settings_body: VBoxContainer       # rows of the open Settings tab
var settings_tabs := {}
var settings_tab := "display"         # display, graphics, controls, accessibility, audio
var _built_contrast := false           # Settings.high_contrast when the menu was built
static var _reopen_settings := ""      # after a rebuild (high-contrast text), reopen Settings on this tab
var info_panel: PanelContainer   # "coming soon" description for the PvP modes
var confirm: ConfirmationDialog
var _confirm_action: Callable

func _ready():
	get_window().title = TITLE   # the window's own title (config/name stays "Azerothtactics": the save folder is named after it)
	Settings.ensure_loaded()
	Settings.apply()
	if ResourceLoader.exists(CAMPAIGN_PATH):
		campaign = load(CAMPAIGN_PATH)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	add_child(_background())

	main_box = _centered_box(self, 8)
	var title := HudStyle.number(104, GOLD)   # the pixel font, with a hard dark shadow like the HUD plates' lip
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", HudStyle.LIP)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 6)
	main_box.add_child(title)
	var sub := HudStyle.caps(12, GREY)
	sub.text = "A HEX AUTO BATTLER"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_box.add_child(sub)
	main_box.add_child(_spacer(8))
	continue_button = _button(main_box, "Continue", _on_continue, true)

	main_box.add_child(_section("SINGLE PLAYER"))
	tutorial_button = _button(main_box, "Tutorial", _start_tutorial)
	tutorial_button.tooltip_text = Tip.wrap("A short guided level that teaches buying, placing, merging, synergies, items and levelling up.")
	_button(main_box, "Campaign", func(): _show_panel(campaign_panel))
	_button(main_box, "Free Play", func(): _start(null, {})).tooltip_text = Tip.wrap("39 rounds against random enemies. No campaign rules.")

	main_box.add_child(_section("PVP"))
	var async_btn := _button(main_box, "Async PvP", func(): _start(null, {}, true))
	async_btn.tooltip_text = Tip.wrap(ASYNC_PVP_TIP)
	var live_btn := _button(main_box, "Live PvP   (coming soon)", func(): _show_info("Live PvP", LIVE_PVP_TEXT))
	for b in [async_btn, live_btn]:
		_tint_button(b, HudStyle.YOU_EDGE, PVP_TINT)

	main_box.add_child(_spacer(6))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	main_box.add_child(row)
	_button(row, "Settings", func(): _show_panel(settings_panel)).custom_minimum_size = Vector2(150, 44)
	_button(row, "Keybinds", func():
		_stop_listening()
		_fill_keybinds()
		_show_panel(keybinds_panel)).custom_minimum_size = Vector2(150, 44)
	if OS.get_name() != "Web":
		_button(row, "Quit", func(): get_tree().quit()).custom_minimum_size = Vector2(150, 44)

	campaign_panel = _build_campaign_panel()
	settings_panel = _build_settings_panel()
	keybinds_panel = _build_keybinds_panel()
	info_panel = _build_info_panel()
	confirm = ConfirmationDialog.new()
	confirm.confirmed.connect(func(): _confirm_action.call())
	add_child(confirm)
	_style_dialog(confirm)
	_refresh()
	_built_contrast = Settings.high_contrast
	if _reopen_settings != "":
		settings_tab = _reopen_settings
		_reopen_settings = ""
		_fill_settings()
		_show_panel(settings_panel)

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and _panel_open():
		_show_panel(null)
		get_viewport().set_input_as_handled()

# --- starting a run ---------------------------------------------------------------------------

# level null = free play. carry = a saved chapter run to continue, or {} for a fresh start.
func _start(level: CampaignLevel, carry: Dictionary, ghost := false):
	GameState.ghost_mode = ghost   # async PvP: free-play rules against ghost boards
	GameState.run_level = level
	GameState.run_campaign = campaign if level != null else null
	GameState.run_carry = carry
	GameState.launched_from_menu = true   # so Game Manager's Debug Level doesn't override this choice
	GameState.reset()
	get_tree().change_scene_to_file(MAIN_SCENE)

func _start_tutorial():
	if ResourceLoader.exists(TUTORIAL_PATH):
		_start(load(TUTORIAL_PATH), {})   # the tutorial isn't in a chapter, so it never touches a saved run

func _saved_level() -> CampaignLevel:
	var saved := SaveGame.chapter_run()
	if saved.is_empty() or campaign == null:
		return null
	return campaign.find_level(StringName(str(saved.get("level", ""))))

func _on_continue():
	var level := _saved_level()
	if level != null:
		_start(level, SaveGame.chapter_run().duplicate(true))

func _start_chapter(chapter: CampaignChapter):
	var first: CampaignLevel = chapter.levels[0]
	var saved := _saved_level()
	if saved != null:
		_ask("Starting a new run abandons your current run at %s (%d HP). Start anyway?" % [saved.display_name, int(SaveGame.chapter_run().get("hp", 0))],
			func():
				SaveGame.clear_chapter_run()
				_start(first, {}))
	else:
		_start(first, {})

# --- panels -------------------------------------------------------------------------------------

func _show_panel(panel: Control):
	main_box.get_parent().visible = panel == null
	_stop_listening()
	for p in [campaign_panel, settings_panel, keybinds_panel, info_panel]:
		p.get_parent().visible = panel == p
	_refresh()

func _panel_open() -> bool:
	return [campaign_panel, settings_panel, keybinds_panel, info_panel].any(func(p): return p.get_parent().visible)

func _refresh():
	var saved := _saved_level()
	continue_button.visible = saved != null
	if saved != null:
		continue_button.text = "Continue: %s (%d HP)" % [saved.display_name, int(SaveGame.chapter_run().get("hp", 0))]
	if SaveGame.is_level_complete(&"tutorial"):
		tutorial_button.text = "Tutorial   (done)"
	elif SaveGame.data().completed_levels.is_empty():
		tutorial_button.text = "Tutorial   (start here)"
	else:
		tutorial_button.text = "Tutorial"
	_fill_campaign_list()

func _build_info_panel() -> PanelContainer:
	var panel := _panel()
	var box := panel.get_child(0) as VBoxContainer
	var t := _heading("", PVP_TINT)
	t.name = "Title"
	box.add_child(t)
	var badge := DockKit.chip("COMING SOON", DockKit.CHIP_ACTIVE, GOLD, 11)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(badge)
	var body := _label("", 14, HudStyle.INK)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 0)
	box.add_child(body)
	_button(box, "Back", func(): _show_panel(null))
	return panel

func _show_info(title: String, text: String):
	var box := info_panel.get_child(0)
	box.get_node("Title").text = title
	box.get_node("Body").text = text
	_show_panel(info_panel)

func _build_campaign_panel() -> PanelContainer:
	var panel := _panel()
	var box := panel.get_child(0) as VBoxContainer
	box.add_child(_heading("Campaign"))
	box.add_child(_label("Each chapter is one run: your board, items, gold and HP carry from level to level.\nLosing a level ends the run.", 13, GREY))
	# Scrolls, so any number of chapters fits a 648 px window.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(560, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	_button(box, "Back", func(): _show_panel(null))
	return panel

func _fill_campaign_list():
	if campaign_panel == null:
		return
	var list := campaign_panel.get_child(0).find_child("List", true, false)
	for c in list.get_children():
		c.queue_free()
	if campaign == null or campaign.chapters.is_empty():
		list.add_child(_label("No campaign found.", 14, GREY))
		return
	for ch in campaign.chapters:
		if ch == null or ch.levels.is_empty():
			continue
		var head := _label(ch.display_name, 18, HudStyle.INK)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(head)
		if ch.description != "":
			var desc := _label(ch.description, 12, GREY)
			desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(desc)
		for i in ch.levels.size():
			var level: CampaignLevel = ch.levels[i]
			var status: String
			var color := GREY
			if SaveGame.is_level_complete(level.id):
				status = "Completed, best %d HP" % SaveGame.best_hp(level.id)
				color = DockKit.COST_COLORS[2]   # green
			elif campaign.is_unlocked(level):
				status = "Not completed"
				color = HudStyle.INK
			else:
				status = "Locked"
				color = DockKit.DIM_TEXT
			var row := _label("  %d. %s  (%d waves)   %s" % [i + 1, level.display_name, level.waves.size(), status], 14, color)
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.tooltip_text = Tip.wrap(level.description)
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			var plate := PanelContainer.new()   # a row like the side boxes' item rows
			plate.add_theme_stylebox_override("panel", DockKit.flat(DockKit.ROW, 3, Vector4(6, 4, 6, 10)))
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.add_child(row)
			list.add_child(plate)
		var open := campaign.is_unlocked(ch.levels[0])
		var start := _button(list, "Start %s" % ch.display_name, _start_chapter.bind(ch), open)
		start.disabled = not open
		if start.disabled:
			start.modulate.a = 0.5
			start.tooltip_text = Tip.wrap("Complete the previous chapter first.")

func _build_settings_panel() -> PanelContainer:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(660, 0)
	var box := panel.get_child(0) as VBoxContainer
	box.add_child(_heading("Settings"))
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for t in [["display", "Display"], ["graphics", "Graphics"], ["controls", "Controls"], ["accessibility", "Accessibility"], ["audio", "Audio"]]:
		var b := _toggle_tab(t[1], group, t[0] == settings_tab)
		b.custom_minimum_size = Vector2(118, 34)
		b.pressed.connect(func():
			settings_tab = t[0]
			_fill_settings())
		tabs.add_child(b)
		settings_tabs[t[0]] = b
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 320)
	box.add_child(scroll)
	settings_body = VBoxContainer.new()
	settings_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_body.add_theme_constant_override("separation", 8)
	scroll.add_child(settings_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_button(row, "Reset settings", func():
		_ask("Put every setting back to its default?", func():
			Settings.reset_options()
			_settings_changed())).custom_minimum_size = Vector2(240, 42)
	_button(row, "Reset campaign progress", func():
		_ask("Erase all campaign progress, unlocks and your current run? This can't be undone.",
			func():
				SaveGame.reset_progress()
				_refresh())).custom_minimum_size = Vector2(240, 42)
	_button(box, "Back", func(): _show_panel(null))
	_fill_settings()
	return panel

# Rebuilds the open settings tab from the current values (after a change that affects other rows,
# e.g. a preset or the display mode, it runs again).
func _fill_settings() -> void:
	if settings_body == null:
		return
	for c in settings_body.get_children():
		settings_body.remove_child(c)
		c.queue_free()
	for k in settings_tabs:
		settings_tabs[k].set_pressed_no_signal(k == settings_tab)
	match settings_tab:
		"display":
			_setting_option("display_mode", "Display mode", ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"],
				Settings.DISPLAY_MODES.find(Settings.display_mode), func(i):
					Settings.display_mode = Settings.DISPLAY_MODES[i]
					_settings_changed(true),
				"Borderless keeps the game from minimising when you switch windows; exclusive can lower input lag.")
			var screen := Settings.WINDOW_SIZES[0] as Vector2i
			if DisplayServer.get_name() != "headless":
				screen = DisplayServer.screen_get_size()
			if Settings.display_mode == "windowed":
				var sizes: Array = Settings.WINDOW_SIZES.filter(func(s): return s.x <= screen.x and s.y <= screen.y)
				if not sizes.has(screen) and DisplayServer.get_name() != "headless":
					sizes.append(screen)   # the monitor's own size, if it isn't one of the presets
				sizes.sort_custom(func(a, b): return a.x < b.x)
				var names: Array = sizes.map(func(s): return "%d x %d%s" % [s.x, s.y, "  (native)" if s == screen else ""])
				_setting_option("resolution", "Resolution", names, maxi(sizes.find(Settings.window_size), 0), func(i):
					Settings.window_size = sizes[i]
					_settings_changed())
			else:
				var r := _setting_option("resolution", "Resolution", ["Native  (%d x %d)" % [screen.x, screen.y]], 0, func(_i): pass,
					"Fullscreen uses your monitor's own resolution.")
				r.disabled = true
			_setting_info("Refresh rate", "%d Hz" % Settings.monitor_hz(), "Your monitor's rate (set it in your operating system). Cap the frame rate to match it below.")
			_setting_option("vsync", "VSync", ["Off", "On", "Adaptive"], Settings.VSYNC_MODES.find(Settings.vsync_mode), func(i):
				Settings.vsync_mode = Settings.VSYNC_MODES[i]
				_settings_changed(),
				"On stops screen tearing. Adaptive turns it off when the frame rate drops, to avoid stutter; it works with G-Sync and FreeSync.")
			var caps: Array = Settings.FPS_CAPS.map(func(c): return "Off" if c == 0 else ("Match monitor  (%d)" % Settings.monitor_hz() if c == -1 else str(c)))
			_setting_option("fps_cap", "Frame rate cap", caps, Settings.FPS_CAPS.find(Settings.fps_cap), func(i):
				Settings.fps_cap = Settings.FPS_CAPS[i]
				_settings_changed(),
				"A cap at your monitor's refresh rate keeps the GPU cooler and quieter.")
		"graphics":
			var presets := ["Low", "Medium", "High", "Ultra"]
			var sel := Settings.PRESETS.find(Settings.graphics_preset)
			if sel < 0:
				presets.append("Custom")
				sel = presets.size() - 1
			_setting_option("preset", "Preset", presets, sel, func(i):
				if i < Settings.PRESETS.size():
					Settings.set_preset(Settings.PRESETS[i])
					_settings_changed(true))
			var scale_names := ["Off  (100%)", "Ultra quality  (85%)", "Quality  (77%)", "Balanced  (67%)", "Performance  (50%)"]
			var scale_i: int = maxi(Settings.RENDER_SCALES.find(Settings.render_scale), 0)
			_setting_option("render_scale", "Upscaling", scale_names, scale_i, func(i):
				Settings.render_scale = Settings.RENDER_SCALES[i]
				_custom_graphics(),
				"Draws the board at a lower resolution and scales it up: faster, a little softer. DLSS and XeSS aren't available in Godot, and FSR needs the Forward+ renderer, so this is plain scaling.")
			_setting_option("msaa", "Anti-aliasing", ["Off", "MSAA 2x", "MSAA 4x", "MSAA 8x"], Settings.MSAA_LEVELS.find(Settings.msaa), func(i):
				Settings.msaa = Settings.MSAA_LEVELS[i]
				_custom_graphics(),
				"Smooths the jagged edges of units and tiles.")
			_setting_option("shadows", "Shadows", ["Off", "Low", "High"], Settings.SHADOW_LEVELS.find(Settings.shadows), func(i):
				Settings.shadows = Settings.SHADOW_LEVELS[i]
				_custom_graphics(),
				"Shadows under units. Takes effect from the next run.")
		"controls":
			_setting_slider("pointer_sens_x", "Controller pointer, horizontal", Settings.pointer_sens_x, func(v): Settings.pointer_sens_x = v)
			_setting_slider("pointer_sens_y", "Controller pointer, vertical", Settings.pointer_sens_y, func(v): Settings.pointer_sens_y = v)
			_setting_slider("pan_sens_x", "Camera pan, horizontal", Settings.pan_sens_x, func(v): Settings.pan_sens_x = v)
			_setting_slider("pan_sens_y", "Camera pan, vertical", Settings.pan_sens_y, func(v): Settings.pan_sens_y = v)
			_setting_slider("zoom_sens", "Zoom speed", Settings.zoom_sens, func(v): Settings.zoom_sens = v)
			var note := _label("Camera pan covers dragging with the mouse and the right stick. The mouse pointer itself follows your operating system's speed.", 12, GREY)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(560, 0)
			settings_body.add_child(note)
			var kb := _button(settings_body, "Key and button binds", func():
				_stop_listening()
				_fill_keybinds()
				_show_panel(keybinds_panel))
			kb.custom_minimum_size = Vector2(280, 40)
		"accessibility":
			_setting_option("colorblind", "Colour-blind filter", ["Off", "Protanopia  (red-weak)", "Deuteranopia  (green-weak)", "Tritanopia  (blue-weak)"],
				Settings.COLORBLIND_MODES.find(Settings.colorblind), func(i):
					Settings.colorblind = Settings.COLORBLIND_MODES[i]
					_settings_changed(),
				"Shifts colours so team rings, health bars and HP rows stay easy to tell apart.")
			_setting_check("high_contrast", "High-contrast text", Settings.high_contrast, func(on):
				Settings.high_contrast = on
				_settings_changed(true),
				"Brighter grey text and a dark outline around all text.")
			_setting_check("reduce_motion", "Reduce motion", Settings.reduce_motion, func(on):
				Settings.reduce_motion = on
				_settings_changed(),
				"No camera zoom easing, no tile pop-in, and combat words fade in place instead of floating. (The camera has no head-bob.)")
			var note := _label("Subtitles: the game has no speech or sound yet, so there is nothing to subtitle.", 12, GREY)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(560, 0)
			settings_body.add_child(note)
			var rebind := _button(settings_body, "Key and button binds", func():
				_stop_listening()
				_fill_keybinds()
				_show_panel(keybinds_panel))
			rebind.custom_minimum_size = Vector2(280, 40)
		"audio":
			var vol := _setting_slider("volume", "Volume", Settings.master_volume, func(v): Settings.master_volume = v, 0.0, 1.0, 0.05, true)
			vol.tooltip_text = Tip.wrap("No sound in the game yet.")

# Saves and applies after a change; `rebuild` refreshes the tab (rows that depend on the change).
func _settings_changed(rebuild := false) -> void:
	Settings.apply()
	Settings.save_settings()
	if rebuild:
		_fill_settings.call_deferred()
		if Settings.high_contrast != _built_contrast:   # helpers pick text colours when labels are made
			_built_contrast = Settings.high_contrast
			_rebuild_menu.call_deferred()

# A single graphics option changed by hand: the preset becomes Custom.
func _custom_graphics() -> void:
	Settings.graphics_preset = "custom"
	for p in Settings.PRESETS:
		var v: Dictionary = Settings.PRESET_VALUES[p]
		if is_equal_approx(v.render_scale, Settings.render_scale) and v.msaa == Settings.msaa and v.shadows == Settings.shadows:
			Settings.graphics_preset = p   # it happens to match a preset again
	_settings_changed(true)

# Rebuilds the whole menu (new text colours after High-contrast text changes), back on Settings.
func _rebuild_menu() -> void:
	_reopen_settings = settings_tab
	get_tree().reload_current_scene()

func _setting_row(id: String, text: String, control: Control, hint := "") -> void:
	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override("separation", 12)
	var l := _label(text, 14, HudStyle.INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if hint != "":
		l.tooltip_text = Tip.wrap(hint)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		control.tooltip_text = Tip.wrap(hint)
	row.add_child(l)
	control.name = id
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 260)
	row.add_child(control)
	settings_body.add_child(row)

# A dropdown in the slate button style; `on_pick` gets the chosen index.
func _setting_option(id: String, text: String, items: Array, selected: int, on_pick: Callable, hint := "") -> OptionButton:
	var o := OptionButton.new()
	var look := DockKit.secondary_button("")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb := look.get_theme_stylebox(state).duplicate() as StyleBox
		sb.content_margin_left = 12   # room inside the box (the arrow sits on the right)
		sb.content_margin_right = 12
		o.add_theme_stylebox_override(state, sb)
	look.free()
	o.add_theme_font_override("font", HudStyle.label_font())
	o.add_theme_font_size_override("font_size", 14)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		o.add_theme_color_override(k, HudStyle.INK)
	o.add_theme_color_override("font_disabled_color", DockKit.DIM_TEXT)
	o.custom_minimum_size = Vector2(260, 34)
	o.focus_mode = Control.FOCUS_NONE
	for item in items:
		o.add_item(str(item))
	o.select(clampi(selected, 0, items.size() - 1))
	o.item_selected.connect(on_pick)
	_setting_row(id, text, o, hint)
	return o

# A slider with its value next to it (multipliers as "1.25x", the volume as a percentage).
func _setting_slider(id: String, text: String, value: float, on_change: Callable, lo := Settings.SENS_MIN, hi := Settings.SENS_MAX, step := 0.05, percent := false) -> HSlider:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.name = "Slider"
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(190, 20)
	s.focus_mode = Control.FOCUS_NONE
	s.add_theme_stylebox_override("slider", DockKit.flat(HudStyle.TRACK, 2, Vector4(3, 0, 3, 0)))
	s.add_theme_stylebox_override("grabber_area", DockKit.flat(GOLD, 2, Vector4(3, 0, 3, 0)))
	s.add_theme_stylebox_override("grabber_area_highlight", DockKit.flat(GOLD.lightened(0.12), 2, Vector4(3, 0, 3, 0)))
	wrap.add_child(s)
	var v := HudStyle.number(18, HudStyle.INK)
	v.custom_minimum_size = Vector2(56, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := func(x: float) -> String: return "%d%%" % roundi(x * 100.0) if percent else "%.2fx" % x
	v.text = fmt.call(value)
	wrap.add_child(v)
	s.value_changed.connect(func(x):
		on_change.call(x)
		v.text = fmt.call(x)
		Settings.apply())
	s.drag_ended.connect(func(_changed): Settings.save_settings())
	_setting_row(id, text, wrap)
	return s

func _setting_check(id: String, text: String, on: bool, on_toggle: Callable, hint := "") -> CheckBox:
	var c := _check("", on)
	c.toggled.connect(on_toggle)
	_setting_row(id, text, c, hint)
	return c

# A read-only value (the monitor's refresh rate).
func _setting_info(text: String, value: String, hint := "") -> void:
	var v := _label(value, 14, GREY)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(260, 34)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_setting_row("info_" + text.to_lower().replace(" ", "_"), text, v, hint)

# A tab button for a two-or-more-way choice (Settings and Keybinds): slate, lit with a gold top
# edge while selected.
func _toggle_tab(text: String, group: ButtonGroup, pressed: bool) -> Button:
	var b := DockKit.secondary_button(text)
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	var on := DockKit.flat(DockKit.SELECTED)
	on.border_width_top = 2
	on.border_color = GOLD
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	return b

# --- keybinds -----------------------------------------------------------------------------------

func _build_keybinds_panel() -> PanelContainer:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(620, 0)
	var box := panel.get_child(0) as VBoxContainer
	box.add_child(_heading("Keybinds"))
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for t in [["keyboard", "Keyboard & mouse"], ["controller", "Controller"]]:
		var b := DockKit.secondary_button(t[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t[0] == keybinds_tab
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(200, 36)
		var on := DockKit.flat(DockKit.SELECTED)
		on.border_width_top = 2
		on.border_color = GOLD
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.pressed.connect(func():
			_stop_listening()
			keybinds_tab = t[0]
			_fill_keybinds())
		tabs.add_child(b)
		keybinds_tabs[t[0]] = b
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 330)
	box.add_child(scroll)
	keybinds_grid = GridContainer.new()
	keybinds_grid.columns = 2
	keybinds_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keybinds_grid.add_theme_constant_override("h_separation", 16)
	keybinds_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(keybinds_grid)
	keybinds_hint = _label("", 12, GREY)
	box.add_child(keybinds_hint)
	_button(box, "Reset to defaults", func():
		_ask("Put every keyboard and controller bind back to the default?", func():
			Keybinds.reset_defaults()
			_fill_keybinds()))
	_button(box, "Back", func(): _show_panel(null))
	return panel

func _fill_keybinds():
	Keybinds.ensure()
	for c in keybinds_grid.get_children():
		keybinds_grid.remove_child(c)
		c.queue_free()
	var kb := keybinds_tab == "keyboard"
	keybinds_tabs["keyboard"].set_pressed_no_signal(kb)
	keybinds_tabs["controller"].set_pressed_no_signal(not kb)
	for id in (Keybinds.KEY_ORDER if kb else Keybinds.PAD_ORDER):
		var label: String = Keybinds.KEYS[id][0] if kb else Keybinds.PAD[id][0]
		var name_l := _label(label, 14, HudStyle.INK)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keybinds_grid.add_child(name_l)
		var b := DockKit.secondary_button("")
		b.name = id
		b.custom_minimum_size = Vector2(190, 32)
		var well := DockKit.well_box(DockKit.LINE, 2)
		for state in ["normal", "disabled"]:
			b.add_theme_stylebox_override(state, well)
		b.add_theme_font_override("font", HudStyle.number_font())
		b.add_theme_font_size_override("font_size", 18)
		if _listening == id:
			b.text = "Press a key..." if kb else "Press a button..."
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(k, GOLD)
		else:
			b.text = Keybinds.key_name(Keybinds.keys[id]) if kb else Keybinds.pad_name(Keybinds.pad[id])
		b.pressed.connect(_listen.bind(id))
		keybinds_grid.add_child(b)
	for f in (Keybinds.FIXED_KEYS if kb else Keybinds.FIXED_PAD):
		var name_l := _label(f[1], 14, GREY)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		keybinds_grid.add_child(name_l)
		var fixed := _label(f[0], 14, DockKit.DIM_TEXT)
		fixed.custom_minimum_size = Vector2(190, 32)
		fixed.tooltip_text = Tip.wrap("Fixed: can't be changed.")
		fixed.mouse_filter = Control.MOUSE_FILTER_STOP
		keybinds_grid.add_child(fixed)
	if _listening != "":
		keybinds_hint.text = ("Press the new key. Esc cancels." if kb else "Press the new button on your controller. Esc cancels.")
	else:
		keybinds_hint.text = "Click a bind to change it. A key or button already in use swaps over." if kb \
			else "Click a bind to change it, then press a controller button (not the D-pad). Used ones swap over."

func _listen(id: String):
	_listening = id
	if keybinds_tab == "controller":
		Keybinds.pad_capture = func(b: int):
			if Keybinds.set_pad(id, b as JoyButton):
				_stop_listening()
				_fill_keybinds()
	else:
		Keybinds.pad_capture = Callable()
	_fill_keybinds()

func _stop_listening():
	_listening = ""
	Keybinds.pad_capture = Callable()

# While a keyboard bind waits for a key, the next key press is the new bind (Esc cancels).
func _input(event):
	if _listening == "" or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if keybinds_tab == "keyboard" and event.keycode != KEY_ESCAPE:
		var k: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		Keybinds.set_key(_listening, k)
	_stop_listening()
	_fill_keybinds()

func _ask(text: String, on_yes: Callable):
	confirm.dialog_text = text
	_confirm_action = on_yes
	confirm.popup_centered()

# --- small UI helpers (the HUD / side-box look: HudStyle colours and fonts, DockKit buttons) ----

func _centered_box(parent: Control, separation: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", separation)
	center.add_child(box)
	return box

# A centred HUD plate with a gold top edge (the Campaign, Settings, Keybinds and info screens).
func _panel() -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := HudPlate.new()
	panel.setup_plate(16, 22, 18, DockKit.PANEL_FILL)
	panel.set_edge(HudStyle.EDGE_GOLD)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	center.visible = false   # shown and hidden through its CenterContainer (see _show_panel)
	return panel

# A screen heading in the pixel font.
func _heading(text: String, color := HudStyle.GOLD) -> Label:
	var l := HudStyle.number(40, color)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _label(text: String, size: int, color: Color) -> Label:
	var l := DockKit.text(size, color)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# A slate HUD button (DockKit.secondary_button); primary = the gold one.
func _button(parent: Control, text: String, action: Callable, primary := false) -> Button:
	var b := DockKit.primary_button(text) if primary else DockKit.secondary_button(text)
	b.custom_minimum_size = Vector2(320, 42)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_disabled_color", DockKit.DIM_TEXT)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

# A button with a coloured top edge and text (the PvP buttons are blue).
func _tint_button(b: Button, edge: Color, text_color: Color) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var s := (b.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
		s.border_color = edge
		b.add_theme_stylebox_override(state, s)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, text_color)

func _section(text: String) -> Label:
	var l := HudStyle.caps(11, HudStyle.MUTED)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 24)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l

func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c

# The menu background: dark, a little lighter in the middle.
func _background() -> Control:
	var g := Gradient.new()
	g.set_color(0, Color("1a1e2c"))
	g.set_color(1, Color("0b0c12"))
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

# A check box in the HUD font and colours.
func _check(text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_icon_override("unchecked", _check_icon(false))
	c.add_theme_icon_override("checked", _check_icon(true))
	c.add_theme_icon_override("unchecked_disabled", _check_icon(false))
	c.add_theme_icon_override("checked_disabled", _check_icon(true))
	c.add_theme_font_override("font", HudStyle.label_font())
	c.add_theme_font_size_override("font_size", 15)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		c.add_theme_color_override(k, HudStyle.INK)
	return c

# The confirm dialog (Reset progress, Reset binds) in the HUD look: its own small theme for the
# window frame, title bar, text and buttons (OK gold, Cancel slate).
func _style_dialog(d: ConfirmationDialog) -> void:
	var t := Theme.new()
	var frame := DockKit.flat(DockKit.PANEL_FILL, 3)
	frame.border_width_top = 2
	frame.border_color = HudStyle.EDGE_GOLD
	frame.expand_margin_left = 10
	frame.expand_margin_right = 10
	frame.expand_margin_bottom = 10
	frame.expand_margin_top = 34   # room for the title bar
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 8
	t.set_stylebox("embedded_border", "Window", frame)
	t.set_stylebox("embedded_unfocused_border", "Window", frame)
	t.set_font("title_font", "Window", HudStyle.label_font())
	t.set_font_size("title_font_size", "Window", 14)
	t.set_color("title_color", "Window", HudStyle.GOLD)
	t.set_stylebox("panel", "AcceptDialog", DockKit.flat(DockKit.PANEL_FILL, 0, Vector4(8, 10, 10, 10)))
	t.set_constant("buttons_min_width", "AcceptDialog", 120)   # the dialog sizes its buttons from these
	t.set_constant("buttons_min_height", "AcceptDialog", 36)
	t.set_font("font", "Label", HudStyle.label_font())
	t.set_font_size("font_size", "Label", 14)
	t.set_color("font_color", "Label", HudStyle.INK)
	var slate := DockKit.secondary_button("")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", slate.get_theme_stylebox(state))
	slate.free()
	t.set_font("font", "Button", HudStyle.label_font())
	t.set_font_size("font_size", "Button", 14)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "Button", HudStyle.INK)
	d.theme = t
	d.title = "Are you sure?"
	var ok := d.get_ok_button()
	var gold := DockKit.primary_button("")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		ok.add_theme_stylebox_override(state, gold.get_theme_stylebox(state))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		ok.add_theme_color_override(k, DockKit.DARK_TEXT)
	gold.free()

# A 20 px check box icon in the HUD look: a dark well with a slate edge, gold with a dark check
# mark when ticked (drawn pixel by pixel so it stays crisp).
static var _check_icons := {}

func _check_icon(on: bool) -> Texture2D:
	if _check_icons.has(on):
		return _check_icons[on]
	var n := 20
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fill: Color = GOLD if on else DockKit.WELL
	var edge: Color = DockKit.GOLD_LIP if on else HudStyle.EDGE
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var border := x <= 2 or y <= 2 or x >= n - 3 or y >= n - 3
			img.set_pixel(x, y, edge if border else fill)
	if on:   # a chunky check mark
		var pts := [Vector2i(5, 10), Vector2i(6, 11), Vector2i(7, 12), Vector2i(8, 13), Vector2i(9, 12), Vector2i(10, 11), Vector2i(11, 10), Vector2i(12, 9), Vector2i(13, 8), Vector2i(14, 7)]
		for p in pts:
			for dy in 2:
				img.set_pixel(p.x, p.y + dy - 1, DockKit.DARK_TEXT)
	var tex := ImageTexture.create_from_image(img)
	_check_icons[on] = tex
	return tex
