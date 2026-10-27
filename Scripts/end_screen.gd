# end_screen.gd
extends ColorRect

# The end of a run (victory, defeat, a level or chapter complete, the tutorial, a lobby placement), in the
# HUD look: the board dimmed behind a dark plate with a lit top edge (gold for a win, red for a loss) and
# a dark lip, a small caps line for the mode, the title in the pixel font with a hard shadow, the detail,
# and DockKit buttons (the way forward in gold). Drawn over every other panel.

@onready var title: Label = $CenterContainer/Backing/Margin/VBoxContainer/TitleLabel
@onready var detail: Label = $CenterContainer/Backing/Margin/VBoxContainer/DetailLabel
@onready var restart_button: Button = $CenterContainer/Backing/Margin/VBoxContainer/RestartButton
var next_button: Button   # campaign: after a completed level that has a next one; async PvP: Endless mode
var menu_button: Button   # always shown
var mode_label: Label     # "FREE PLAY", "CAMPAIGN · THE BORDERLANDS", "TUTORIAL", "LOBBY"
var _backing_style: StyleBoxFlat

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0.04, 0.045, 0.07, 0.72)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	$CenterContainer.set_anchors_preset(Control.PRESET_FULL_RECT)

	# backing panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(HudStyle.FILL, 0.97)
	style.set_corner_radius_all(4)
	style.border_width_top = 3
	style.border_color = HudStyle.GOLD
	style.shadow_size = 1   # a hard dark lip under the plate, like the HUD plates
	style.shadow_color = HudStyle.LIP
	style.shadow_offset = Vector2(0, 5)
	_backing_style = style
	$CenterContainer/Backing.add_theme_stylebox_override("panel", style)
	$CenterContainer/Backing.custom_minimum_size = Vector2(460, 0)

	var margin: MarginContainer = $CenterContainer/Backing/Margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)

	var box: VBoxContainer = $CenterContainer/Backing/Margin/VBoxContainer
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)

	mode_label = HudStyle.caps(12, HudStyle.MUTED)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mode_label)
	box.move_child(mode_label, 0)
	title.add_theme_font_override("font", HudStyle.number_font())
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_shadow_color", HudStyle.LIP)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_override("font", HudStyle.label_font())
	detail.add_theme_font_size_override("font_size", 16)
	detail.add_theme_color_override("font_color", Settings.text_color(HudStyle.INK))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(380, 0)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	box.add_child(gap)
	box.move_child(gap, restart_button.get_index())
	_style_button(restart_button, true)

	next_button = Button.new()
	next_button.text = "Next level"
	_style_button(next_button, true)
	next_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_button.visible = false
	box.add_child(next_button)
	box.move_child(next_button, restart_button.get_index())   # above Restart
	next_button.pressed.connect(_next_level)

	menu_button = Button.new()
	menu_button.text = "Main menu"
	_style_button(menu_button, false)
	box.add_child(menu_button)   # last, below Restart
	menu_button.pressed.connect(func(): GameState.go_to_menu())

	Events.run_lost.connect(func(): _show(false))
	Events.run_won.connect(func(): _show(true))
	restart_button.pressed.connect(_restart)

# A DockKit button (gold primary or slate secondary) at the end screen's size.
func _style_button(b: Button, primary: bool) -> void:
	var t := DockKit.primary_button(b.text) if primary else DockKit.secondary_button(b.text)
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		if t.has_theme_stylebox_override(k):
			b.add_theme_stylebox_override(k, t.get_theme_stylebox(k))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		if t.has_theme_color_override(k):
			b.add_theme_color_override(k, t.get_theme_color(k))
	b.add_theme_font_override("font", HudStyle.label_font())
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(240, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.free()

# Win or loss colours: the plate's top edge and the title.
func _tone(good: bool, colour := Color()) -> void:
	var c := colour if colour != Color() else (HudStyle.GOLD if good else HudStyle.RED)
	title.add_theme_color_override("font_color", c)
	title.modulate = Color.WHITE
	_backing_style.border_color = c
	_backing_style.border_color.a = 1.0
	get_parent().move_child(self, -1)   # over the inspector and the side boxes

func _show(won: bool):
	_tone(won)
	var lvl := GameState.run_level
	mode_label.text = _mode_text()
	restart_button.visible = true
	next_button.visible = false
	if lvl == null and GameState.ghost_mode:
		_show_async(won)
	elif lvl == null:
		title.text = "VICTORY" if won else "DEFEAT"
		detail.text = "Reached Stage %d-%d\nLevel %d" % [GameState.stage(), GameState.round_in_stage(), GameState.me.level]
		restart_button.text = "Restart"
	elif _is_tutorial():
		# The tutorial stands alone: no chapter run, no next level. Main menu leads on to the campaign.
		title.text = "TUTORIAL COMPLETE" if won else "DEFEAT"
		detail.text = "You know the basics.\nTry the Campaign from the main menu." if won else "Every unit fell. Try again: place more units and merge them into stars."
		restart_button.text = "Replay tutorial" if won else "Try again"
	elif not won:
		# Roguelite: a defeat ends the chapter run.
		title.text = "DEFEAT"
		detail.text = "%s, wave %d of %d\nYour chapter run is over" % [lvl.display_name, GameState.round_number, GameState.total_rounds()]
		restart_button.text = "Restart chapter"
	elif not GameState.run_carry.is_empty():
		# Mid-chapter: the board carries on, so the only way forward is the next level.
		title.text = "LEVEL COMPLETE"
		detail.text = "%s   HP %d/%d\nYour board carries into %s" % [lvl.display_name, GameState.me.player_hp, GameState.me.start_hp, _next().display_name]
		next_button.text = "Next level"
		next_button.visible = true
		restart_button.visible = false
	else:
		title.text = "CHAPTER COMPLETE"
		var ch := GameState.run_campaign.chapter_of(lvl) if GameState.run_campaign != null else null
		detail.text = "%s cleared with %d HP" % [ch.display_name if ch != null else lvl.display_name, GameState.me.player_hp]
		next_button.text = "Next chapter"
		next_button.visible = _next() != null
		restart_button.text = "Play chapter again"
	visible = true

# Async PvP: 10 trophies is a win, with Endless mode on offer; out of lives is the end (of endless too).
func _show_async(won: bool) -> void:
	var me := GameState.me
	var best := SaveGame.async_best()
	restart_button.text = "New run"
	if won:
		title.text = "VICTORY"
		detail.text = "%d trophies with %d lives left, by round %d.
Keep going in endless mode (sudden death: one loss ends it), or stop here." % [me.trophies, me.lives_left(), GameState.round_number]
		next_button.text = "Endless mode"
		next_button.visible = true
	elif me.endless:
		_tone(true)   # endless only ends one way; reaching it was the win
		title.text = "ENDLESS OVER"
		detail.text = "%d trophies by round %d.
Your best: %d." % [me.trophies, GameState.round_number, best]
	else:
		title.text = "DEFEAT"
		detail.text = "%d of %d trophies by round %d.
Your best: %d." % [me.trophies, GameState.ASYNC_TROPHIES, GameState.round_number, best]

# The next level in campaign order (a new chapter starts fresh; within a chapter run_carry holds the board).
func _mode_text() -> String:
	var lvl := GameState.run_level
	if lvl == null:
		return "ASYNC PVP" if GameState.ghost_mode else "FREE PLAY"
	if _is_tutorial():
		return "TUTORIAL"
	var ch := GameState.run_campaign.chapter_of(lvl) if GameState.run_campaign != null else null
	return "CAMPAIGN · %s" % ch.display_name.to_upper() if ch != null else "CAMPAIGN"

func _next() -> CampaignLevel:
	if GameState.run_campaign == null or GameState.run_level == null:
		return null
	return GameState.run_campaign.next_level(GameState.run_level)

func _next_level():
	if GameState.ghost_mode and GameState.run_level == null:   # async PvP: Endless mode
		var gm = get_tree().get_first_node_in_group("game_manager")
		if gm != null:
			visible = false
			gm.continue_endless()
		return
	var nxt := _next()
	if nxt == null:
		return
	GameState.run_level = nxt
	GameState.reset()
	get_tree().reload_current_scene()

func _is_tutorial() -> bool:
	return GameState.run_level != null and GameState.run_level.id == &"tutorial"

func _restart():
	if GameState.run_level != null and not _is_tutorial():
		# Campaign: back to the first level of the chapter with an empty board.
		if GameState.run_campaign != null:
			GameState.run_level = GameState.run_campaign.first_of_chapter(GameState.run_level)
		GameState.run_carry = {}
		SaveGame.clear_chapter_run()
	GameState.reset()
	get_tree().reload_current_scene()

# A lobby game's end for you (lobby_game.gd): your placement, or that the connection was lost. The
# only way on is the main menu (which leaves the lobby).
func show_lobby(place: int, _total: int, title_text: String, detail_text: String) -> void:
	title.text = title_text
	mode_label.text = "LOBBY"
	_tone(place > 0 and place <= 4, HudStyle.GOLD if place == 1 else (HudStyle.INK if place > 0 and place <= 4 else HudStyle.RED))
	detail.text = detail_text
	restart_button.visible = false
	next_button.visible = false
	menu_button.visible = true
	visible = true
