# end_screen.gd
extends ColorRect

@onready var title: Label = $CenterContainer/Backing/Margin/VBoxContainer/TitleLabel
@onready var detail: Label = $CenterContainer/Backing/Margin/VBoxContainer/DetailLabel
@onready var restart_button: Button = $CenterContainer/Backing/Margin/VBoxContainer/RestartButton
var next_button: Button   # campaign only, after a completed level that has a next one
var menu_button: Button   # always shown

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.75)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	$CenterContainer.set_anchors_preset(Control.PRESET_FULL_RECT)

	# backing panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.17, 0.95)
	style.set_corner_radius_all(16)
	style.set_border_width_all(3)
	style.border_color = Color(1.0, 0.85, 0.3)
	style.shadow_size = 12
	style.shadow_color = Color(0, 0, 0, 0.5)
	$CenterContainer/Backing.add_theme_stylebox_override("panel", style)
	$CenterContainer/Backing.custom_minimum_size = Vector2(480, 300)

	var margin: MarginContainer = $CenterContainer/Backing/Margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)

	var box: VBoxContainer = $CenterContainer/Backing/Margin/VBoxContainer
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)

	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 24)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_button.custom_minimum_size = Vector2(200, 56)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	next_button = Button.new()
	next_button.text = "Next level"
	next_button.custom_minimum_size = Vector2(200, 56)
	next_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_button.visible = false
	box.add_child(next_button)
	box.move_child(next_button, restart_button.get_index())   # above Restart
	next_button.pressed.connect(_next_level)

	menu_button = Button.new()
	menu_button.text = "Main menu"
	menu_button.custom_minimum_size = Vector2(200, 56)
	menu_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(menu_button)   # last, below Restart
	menu_button.pressed.connect(func(): GameState.go_to_menu())

	Events.run_lost.connect(func(): _show(false))
	Events.run_won.connect(func(): _show(true))
	restart_button.pressed.connect(_restart)

func _show(won: bool):
	title.modulate = Color(0.4, 0.9, 0.4) if won else Color(0.95, 0.4, 0.4)
	var lvl := GameState.run_level
	restart_button.visible = true
	next_button.visible = false
	if lvl == null:
		title.text = "VICTORY" if won else "DEFEAT"
		detail.text = "Reached Stage %d-%d\nLevel %d" % [GameState.stage(), GameState.round_in_stage(), GameState.me.level]
		restart_button.text = "Restart"
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

# The next level in campaign order (a new chapter starts fresh; within a chapter run_carry holds the board).
func _next() -> CampaignLevel:
	if GameState.run_campaign == null or GameState.run_level == null:
		return null
	return GameState.run_campaign.next_level(GameState.run_level)

func _next_level():
	var nxt := _next()
	if nxt == null:
		return
	GameState.run_level = nxt
	GameState.reset()
	get_tree().reload_current_scene()

func _restart():
	if GameState.run_level != null:
		# Campaign: back to the first level of the chapter with an empty board.
		if GameState.run_campaign != null:
			GameState.run_level = GameState.run_campaign.first_of_chapter(GameState.run_level)
		GameState.run_carry = {}
		SaveGame.clear_chapter_run()
	GameState.reset()
	get_tree().reload_current_scene()
