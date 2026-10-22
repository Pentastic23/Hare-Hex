# main_menu.gd
extends Control

# The first screen: title, Continue (saved chapter run), then two sections:
#   SINGLE PLAYER: Tutorial, Campaign (chapters and levels), Free Play
#   PVP: Async PvP (ghost opponents, playable) and Live PvP (coming later: opens an info panel)
# and Settings / Quit. Built in code; menu.tscn is just this script on a full-screen Control.

const TITLE := "AZTactics"
const MAIN_SCENE := "res://scenes/main.tscn"
const CAMPAIGN_PATH := "res://tres/campaign/campaign.tres"
const TUTORIAL_PATH := "res://tres/campaign/tutorial.tres"
const GOLD := Color(1.0, 0.85, 0.3)
const GREY := Color(0.65, 0.65, 0.7)
const PVP_TINT := Color(0.7, 0.85, 1.0)
const ASYNC_PVP_TIP := "Free play against ghosts: boards saved from earlier runs. Your own boards are saved too. No ghosts yet? You meet random enemies."
const LIVE_PVP_TEXT := "Real-time matches with up to 8 players on a server: one shared unit pool, a fight against another player every round, last one standing wins.\n\nComing later. Async PvP comes first."

var campaign: Campaign
var main_box: VBoxContainer
var continue_button: Button
var tutorial_button: Button
var campaign_panel: PanelContainer
var settings_panel: PanelContainer
var info_panel: PanelContainer   # "coming soon" description for the PvP modes
var confirm: ConfirmationDialog
var _confirm_action: Callable
var panel_style: StyleBox = preload("res://tres/panel_style.tres")

func _ready():
	DisplayServer.window_set_title(TITLE)
	Settings.ensure_loaded()
	Settings.apply()
	if ResourceLoader.exists(CAMPAIGN_PATH):
		campaign = load(CAMPAIGN_PATH)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	main_box = _centered_box(self, 8)
	var title := _label(TITLE, 72, GOLD)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 12)
	main_box.add_child(title)
	main_box.add_child(_label("A hex auto battler", 20, GREY))
	main_box.add_child(_spacer(10))
	continue_button = _button(main_box, "Continue", _on_continue)

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
		b.modulate = PVP_TINT

	main_box.add_child(_spacer(6))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	main_box.add_child(row)
	_button(row, "Settings", func(): _show_panel(settings_panel)).custom_minimum_size = Vector2(156, 44)
	if OS.get_name() != "Web":
		_button(row, "Quit", func(): get_tree().quit()).custom_minimum_size = Vector2(156, 44)

	campaign_panel = _build_campaign_panel()
	settings_panel = _build_settings_panel()
	info_panel = _build_info_panel()
	confirm = ConfirmationDialog.new()
	confirm.confirmed.connect(func(): _confirm_action.call())
	add_child(confirm)
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
	for p in [campaign_panel, settings_panel, info_panel]:
		p.get_parent().visible = panel == p
	_refresh()

func _panel_open() -> bool:
	return [campaign_panel, settings_panel, info_panel].any(func(p): return p.get_parent().visible)

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
	var t := _label("", 36, PVP_TINT)
	t.name = "Title"
	box.add_child(t)
	var badge := _label("Coming soon", 16, GOLD)
	box.add_child(badge)
	var body := _label("", 17, Color.WHITE)
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
	box.add_child(_label("Campaign", 40, GOLD))
	box.add_child(_label("Each chapter is one run: your board, items, gold and HP carry from level to level.\nLosing a level ends the run.", 16, GREY))
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
		list.add_child(_label("No campaign found.", 18, GREY))
		return
	for ch in campaign.chapters:
		if ch == null or ch.levels.is_empty():
			continue
		list.add_child(_label(ch.display_name, 26, Color.WHITE))
		if ch.description != "":
			list.add_child(_label(ch.description, 15, GREY))
		for i in ch.levels.size():
			var level: CampaignLevel = ch.levels[i]
			var status: String
			var color := GREY
			if SaveGame.is_level_complete(level.id):
				status = "Completed, best %d HP" % SaveGame.best_hp(level.id)
				color = Color(0.5, 0.9, 0.5)
			elif campaign.is_unlocked(level):
				status = "Not completed"
				color = Color.WHITE
			else:
				status = "Locked"
			var row := _label("  %d. %s  (%d waves)   %s" % [i + 1, level.display_name, level.waves.size(), status], 18, color)
			row.tooltip_text = Tip.wrap(level.description)
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			list.add_child(row)
		var start := _button(list, "Start %s" % ch.display_name, _start_chapter.bind(ch))
		start.disabled = not campaign.is_unlocked(ch.levels[0])
		if start.disabled:
			start.tooltip_text = Tip.wrap("Complete the previous chapter first.")

func _build_settings_panel() -> PanelContainer:
	var panel := _panel()
	var box := panel.get_child(0) as VBoxContainer
	box.add_child(_label("Settings", 40, GOLD))

	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on):
		Settings.fullscreen = on
		Settings.apply()
		Settings.save_settings())
	box.add_child(fs)

	var vs := CheckBox.new()
	vs.text = "VSync"
	vs.button_pressed = Settings.vsync
	vs.toggled.connect(func(on):
		Settings.vsync = on
		Settings.apply()
		Settings.save_settings())
	box.add_child(vs)

	var vol_label := _label("Volume: %d%%" % roundi(Settings.master_volume * 100), 18, Color.WHITE)
	vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(vol_label)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Settings.master_volume
	vol.custom_minimum_size = Vector2(320, 24)
	vol.value_changed.connect(func(v):
		Settings.master_volume = v
		vol_label.text = "Volume: %d%%" % roundi(v * 100)
		Settings.apply())
	vol.drag_ended.connect(func(_changed): Settings.save_settings())
	box.add_child(vol)
	box.add_child(_label("(No sound in the game yet.)", 14, GREY))

	box.add_child(_spacer(8))
	_button(box, "Reset campaign progress", func():
		_ask("Erase all campaign progress, unlocks and your current run? This can't be undone.",
			func():
				SaveGame.reset_progress()
				_refresh()))
	_button(box, "Back", func(): _show_panel(null))
	return panel

func _ask(text: String, on_yes: Callable):
	confirm.dialog_text = text
	_confirm_action = on_yes
	confirm.popup_centered()

# --- small UI helpers ---------------------------------------------------------------------------

func _centered_box(parent: Control, separation: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", separation)
	center.add_child(box)
	return box

func _panel() -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	center.visible = false   # shown and hidden through its CenterContainer (see _show_panel)
	return panel

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _section(text: String) -> Label:
	var l := _label(text, 14, GREY)
	l.custom_minimum_size = Vector2(0, 22)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l

func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
