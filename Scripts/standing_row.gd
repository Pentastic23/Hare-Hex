# standing_row.gd
class_name StandingRow extends HudPlate

# One row of the HP standings: name (plus a "VS" tag for this round's opponent) and HP on top, a
# 10-segment HP bar under it. role: "you", "opponent", "other" or "out" (eliminated).

const WIDTH := 210
const SEGMENTS := 10

var role := ""
var name_text := ""
var hp := -1          # -1 = no HP to show (campaign waves, random enemies)
var max_hp := 100
var number_text := ""   # shown instead of the HP (a campaign wave's "4/5")

var name_lbl: Label
var vs_tag: PanelContainer
var hp_lbl: Label
var bar: Bar
var _strike: ColorRect

class Bar extends Control:
	var ratio := 0.0
	var color := HudStyle.YOU
	func set_state(r: float, c: Color) -> void:
		ratio = clampf(r, 0.0, 1.0)
		color = c
		queue_redraw()
	func _draw():
		var gap := 2.0
		var w := (size.x - gap * (SEGMENTS - 1)) / SEGMENTS
		for i in SEGMENTS:
			var x := i * (w + gap)
			draw_rect(Rect2(x, 0, w, size.y), HudStyle.TRACK)
			var part := clampf(ratio * SEGMENTS - i, 0.0, 1.0)   # partly filled segments show the remainder
			if part > 0.0:
				draw_rect(Rect2(x, 0, w * part, size.y), color)

func _init():
	setup_plate(6, 10, 7)
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	name_lbl = HudStyle.name_label()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	top.add_child(name_lbl)
	_strike = ColorRect.new()
	_strike.color = HudStyle.MUTED
	_strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strike.anchor_right = 1.0
	_strike.anchor_top = 0.5
	_strike.anchor_bottom = 0.5
	_strike.offset_top = 0.0
	_strike.offset_bottom = 1.0
	_strike.visible = false
	name_lbl.add_child(_strike)
	vs_tag = PanelContainer.new()
	vs_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vs_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tag_style := StyleBoxFlat.new()
	tag_style.bg_color = Color(0, 0, 0, 0)
	tag_style.border_color = HudStyle.ENEMY_EDGE
	tag_style.set_border_width_all(1)
	tag_style.set_corner_radius_all(2)
	tag_style.content_margin_left = 3
	tag_style.content_margin_right = 3
	vs_tag.add_theme_stylebox_override("panel", tag_style)
	var vs := HudStyle.name_label(HudStyle.ENEMY)
	vs.add_theme_font_size_override("font_size", 9)
	vs.text = "VS"
	vs_tag.add_child(vs)
	top.add_child(vs_tag)
	hp_lbl = HudStyle.number(22)
	hp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(hp_lbl)
	bar = Bar.new()
	bar.custom_minimum_size = Vector2(0, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)

func show_player(r: String, player_name: String, player_hp: int, player_max: int, number := "") -> void:
	role = "out" if player_hp == 0 and r != "opponent" else r
	name_text = player_name
	hp = player_hp
	max_hp = maxi(player_max, 1)
	number_text = number
	_apply()

func _apply() -> void:
	var out := role == "out"
	modulate.a = 0.45 if out else 1.0
	set_fill(HudStyle.FILL_YOU if role == "you" else HudStyle.FILL)
	match role:
		"you": set_edge(HudStyle.YOU_EDGE)
		"opponent": set_edge(HudStyle.ENEMY_EDGE)
		"out": set_edge(HudStyle.EDGE_OUT)
		_: set_edge(HudStyle.EDGE)
	name_lbl.text = name_text
	name_lbl.add_theme_color_override("font_color", HudStyle.INK if role == "you" or role == "opponent" else HudStyle.MUTED)
	_strike.visible = out   # an eliminated player's name is struck through
	vs_tag.visible = role == "opponent"
	if out:
		hp_lbl.text = "Out"
	elif number_text != "":
		hp_lbl.text = number_text
	elif hp >= 0:
		hp_lbl.text = str(hp)
	else:
		hp_lbl.text = ""
	hp_lbl.add_theme_font_size_override("font_size", 17 if number_text != "" and not out else 22)
	var low := hp >= 0 and number_text == "" and not out and float(hp) <= 0.25 * max_hp
	hp_lbl.add_theme_color_override("font_color", HudStyle.RED if low else (HudStyle.MUTED if out else HudStyle.INK))
	var bar_color: Color = HudStyle.YOU if role == "you" else (HudStyle.ENEMY if role == "opponent" else HudStyle.NEUTRAL)
	bar.set_state(0.0 if out or hp < 0 or number_text != "" else float(hp) / max_hp, bar_color)
