# main_menu.gd
extends Control

# The first screen: title, Continue (saved chapter run), then two sections:
#   SINGLE PLAYER: Tutorial, Campaign (chapters and levels), Free Play
#   PVP: Async PvP (ghost opponents, playable) and Live PvP (coming later: opens an info panel)
# and Settings / Keybinds / Quit. Built in code; menu.tscn is just this script on a full-screen Control.

const TITLE := "AZTactics"
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
var info_panel: PanelContainer   # "coming soon" description for the PvP modes
var confirm: ConfirmationDialog
var _confirm_action: Callable

func _ready():
	DisplayServer.window_set_title(TITLE)
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
	var box := panel.get_child(0) as VBoxContainer
	box.add_child(_heading("Settings"))

	var fs := _check("Fullscreen", Settings.fullscreen)
	fs.toggled.connect(func(on):
		Settings.fullscreen = on
		Settings.apply()
		Settings.save_settings())
	box.add_child(fs)

	var vs := _check("VSync", Settings.vsync)
	vs.toggled.connect(func(on):
		Settings.vsync = on
		Settings.apply()
		Settings.save_settings())
	box.add_child(vs)

	var vol_label := _label("Volume: %d%%" % roundi(Settings.master_volume * 100), 15, HudStyle.INK)
	vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(vol_label)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Settings.master_volume
	vol.custom_minimum_size = Vector2(320, 24)
	var track := DockKit.flat(HudStyle.TRACK, 2, Vector4(3, 0, 3, 0))
	vol.add_theme_stylebox_override("slider", track)
	vol.add_theme_stylebox_override("grabber_area", DockKit.flat(HudStyle.GOLD, 2, Vector4(3, 0, 3, 0)))
	vol.add_theme_stylebox_override("grabber_area_highlight", DockKit.flat(HudStyle.GOLD.lightened(0.12), 2, Vector4(3, 0, 3, 0)))
	vol.value_changed.connect(func(v):
		Settings.master_volume = v
		vol_label.text = "Volume: %d%%" % roundi(v * 100)
		Settings.apply())
	vol.drag_ended.connect(func(_changed): Settings.save_settings())
	box.add_child(vol)
	box.add_child(_label("(No sound in the game yet.)", 12, GREY))

	box.add_child(_spacer(8))
	_button(box, "Reset campaign progress", func():
		_ask("Erase all campaign progress, unlocks and your current run? This can't be undone.",
			func():
				SaveGame.reset_progress()
				_refresh()))
	_button(box, "Back", func(): _show_panel(null))
	return panel

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
