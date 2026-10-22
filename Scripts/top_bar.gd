# top_bar.gd
extends HudPlate

# The combat HUD's top bar, flush with the top of the screen so the board gets the room:
#   STAGE 3  [round pips]  3-4  |  PREP  0:12  [^]
# with a thin progress track along the bottom (time left in the phase). The ^ button folds it to
# "3-4  0:12  [v]"; the choice is remembered (Settings.show_top_bar). Built in code: the rounds
# half is round_tracker.gd, the timer half top_bar_timer.gd. Only the fold button and the campaign
# rounds tooltip take the mouse.

const RoundTracker := preload("res://Scripts/round_tracker.gd")
const BarTimer := preload("res://Scripts/top_bar_timer.gd")

var rounds: RoundTracker
var timer: BarTimer
var fold_button: Button
var track: Track
var _divider: ColorRect
var expanded := true

class Track extends Control:
	var ratio := 1.0
	var color := HudStyle.GOLD
	func set_state(r: float, c: Color) -> void:
		r = clampf(r, 0.0, 1.0)
		if not is_equal_approx(r, ratio) or c != color:
			ratio = r
			color = c
			queue_redraw()
	func _draw():
		draw_rect(Rect2(Vector2.ZERO, size), HudStyle.TRACK)
		draw_rect(Rect2(0, 0, size.x * ratio, size.y), color)

func _ready():
	setup_plate(3, 12, 4)
	_style.corner_radius_top_left = 0   # flush with the top of the screen
	_style.corner_radius_top_right = 0
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = 0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	rounds = RoundTracker.new()
	rounds.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rounds)
	_divider = ColorRect.new()
	_divider.color = HudStyle.EDGE
	_divider.custom_minimum_size = Vector2(1, 20)
	_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_divider)
	timer = BarTimer.new()
	timer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(timer)
	fold_button = Button.new()
	fold_button.flat = true
	fold_button.focus_mode = Control.FOCUS_NONE
	fold_button.custom_minimum_size = Vector2(22, 22)
	fold_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fold_button.add_theme_color_override("font_color", HudStyle.MUTED)
	fold_button.add_theme_color_override("font_hover_color", HudStyle.INK)
	fold_button.draw.connect(_draw_chevron)
	fold_button.tooltip_text = Tip.wrap("Fold or unfold the top bar.")
	fold_button.pressed.connect(func():
		set_expanded(not expanded)
		Settings.show_top_bar = expanded
		Settings.save_settings())
	row.add_child(fold_button)
	track = Track.new()
	track.custom_minimum_size = Vector2(0, 3)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(track)
	minimum_size_changed.connect(func(): _recenter.call_deferred())
	Settings.ensure_loaded()
	set_expanded(Settings.show_top_bar)

func set_expanded(e: bool) -> void:
	expanded = e
	rounds.set_compact(not e)
	timer.phase_label.visible = e
	fold_button.queue_redraw()
	_recenter.call_deferred()

# Shrinks the bar to its contents and keeps it centred (folding, and the timer coming and going,
# change its width; on its own a resized panel keeps its left edge where it was).
func _recenter() -> void:
	var w := get_combined_minimum_size().x
	offset_left = -w / 2.0
	offset_right = w / 2.0
	reset_size()

func _process(_delta):
	_divider.visible = timer.active
	track.visible = timer.active
	track.set_state(timer.ratio, timer.color)
	set_edge(timer.edge_color if timer.active else HudStyle.EDGE)

# The fold button's chevron: points up while unfolded (click to fold), down while folded.
func _draw_chevron():
	var c := fold_button.size / 2.0
	var d := -1.0 if expanded else 1.0
	var col := HudStyle.INK if fold_button.is_hovered() else HudStyle.MUTED
	fold_button.draw_polyline(PackedVector2Array([c + Vector2(-5, 2.5 * -d), c + Vector2(0, -2.5 * -d), c + Vector2(5, 2.5 * -d)]), col, 2.0, true)
