# end_screen.gd
extends ColorRect

@onready var title: Label = $CenterContainer/Backing/Margin/VBoxContainer/TitleLabel
@onready var detail: Label = $CenterContainer/Backing/Margin/VBoxContainer/DetailLabel
@onready var restart_button: Button = $CenterContainer/Backing/Margin/VBoxContainer/RestartButton

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

	Events.run_lost.connect(func(): _show(false))
	Events.run_won.connect(func(): _show(true))
	restart_button.pressed.connect(_restart)

func _show(won: bool):
	title.text = "VICTORY" if won else "DEFEAT"
	title.modulate = Color(0.4, 0.9, 0.4) if won else Color(0.95, 0.4, 0.4)
	detail.text = "Reached Stage %d-%d\nLevel %d" % [GameState.stage(), GameState.round_in_stage(), GameState.level]
	visible = true

func _restart():
	GameState.reset()
	get_tree().reload_current_scene()
