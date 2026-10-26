# board_label.gd
extends Label

# The unit cap. It isn't shown all the time: when you try to put more units on the board than your
# level allows (Events.board_limit_hit) a big "BOARD FULL  5/5" flashes above the board and fades.
# The same flash shows Events.notice messages (each fight's result: VICTORY, DEFEAT -7 HP, TIME UP...).
# This label itself stays hidden; `flash` is the one that shows, centred over the board.

var board: Board
var flash: Label
var _tween: Tween

func _ready():
	visible = false
	board = get_tree().get_first_node_in_group("board") as Board
	flash = HudStyle.number(40, HudStyle.RED)
	flash.name = "UnitCapFlash"
	flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash.add_theme_color_override("font_shadow_color", HudStyle.LIP)
	flash.add_theme_constant_override("shadow_offset_y", 4)
	flash.add_theme_constant_override("shadow_offset_x", 0)
	flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	flash.anchor_top = 0.3
	flash.anchor_bottom = 0.3
	flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.visible = false
	(owner if owner != null else get_parent()).add_child.call_deferred(flash)
	Events.board_limit_hit.connect(_flash)
	Events.notice.connect(show_notice)

func cap_text() -> String:
	if board == null:
		return ""
	return "BOARD FULL  %d/%d" % [board.units_on_board(), GameState.me.max_board_units()]

func _flash():
	show_notice(cap_text(), HudStyle.RED)

func show_notice(text: String, color: Color) -> void:
	flash.text = text
	flash.add_theme_color_override("font_color", color)
	flash.visible = true
	flash.modulate.a = 1.0
	if _tween != null:
		_tween.kill()
	_tween = flash.create_tween()
	_tween.tween_interval(0.9)
	_tween.tween_property(flash, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(func(): flash.visible = false)
