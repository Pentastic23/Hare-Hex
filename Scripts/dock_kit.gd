# dock_kit.gd
class_name DockKit extends RefCounted

# Shared pieces for the two side boxes (menagerie/hud/DOCKS_SPEC.md): the left box (Synergies / Items)
# and the right box (Damage / Planner / Menu). Same plates, colours and fonts as the combat HUD
# (HudStyle, HudPlate); this adds tabs, badges, wells, buttons, small pixel icons and the portrait and
# item icon lookups.

const PANEL_FILL := Color(0.125, 0.141, 0.204, 0.95)   # #202434 at 95%: an open panel, one step lighter than the tab bar
const TAB_ACTIVE := Color("232839")                    # active tab in the left box
const WELL := Color("141722")                          # item slots, tiles, segmented controls
const ROW := Color("1b1f2d")                           # item rows, unreached tier chips
const ROW_ACTIVE := Color("1e2232")                    # active synergy rows
const BADGE_OFF := Color("2c3249")
const SELECTED := Color("2c3249")                      # selected half of a segmented control, selected cost tab
const LINE := Color("262b3f")                          # dividers, tile outlines
const DIM_TEXT := Color("6b7290")
const DARK_TEXT := Color("1b1610")                     # text on gold
const GOLD_DARK := Color("b98a2c")                     # synergy with some tiers reached
const GOLD_EDGE := Color("7a5a17")
const GOLD_EDGE_DARK := Color("5e4514")
const GOLD_LIP := Color("a87c22")
const CHIP_ACTIVE := Color("3a2f16")
const SECONDARY := Color("262b3f")
const COST_COLORS := {1: Color("8f97b3"), 2: Color("5cc27a"), 3: Color("4f9cf0"), 4: Color("b07cf0"), 5: Color("f2c14e")}

const PORTRAIT_DIR := "res://textures/ui/portraits/"   # <unit .tres file name>.png, e.g. militia.png
const ITEM_ICON_DIR := "res://textures/ui/items/"      # <item id>.png

static var _portraits := {}
static var _icons := {}

# --- fonts and labels -----------------------------------------------------------------------------

static func text(size: int, color := HudStyle.INK) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", HudStyle.label_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Settings.text_color(color))
	Settings.contrast(l, Settings.text_color(color))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A label that wraps inside a narrow box (descriptions, effects, hints).
static func wrapping(size: int, color: Color, min_width: float) -> Label:
	var l := text(size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = min_width
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

# --- the unit inspector's look, shared (the King, Items and Planner tabs and the tutorial use it too) ---

const CELL_FILL := Color("141722")

# A section heading: small caps and a line running to the right edge.
static func heading(label: String, colour := HudStyle.MUTED) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var l := HudStyle.caps(10, colour)
	l.text = label
	h.add_child(l)
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	return h

# Wrapping text in the label font whose mechanic words (burn, stun, shield...) are gold links: hovering
# one shows what it means (Glossary.hook). Give it text through Glossary.bbcode, or set_rich below.
static func rich(size: int, colour := HudStyle.INK, min_width := 0.0) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = min_width
	l.add_theme_font_override("normal_font", HudStyle.label_font())
	l.add_theme_font_override("bold_font", HudStyle.label_font())
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_font_size_override("bold_font_size", size)
	l.add_theme_color_override("default_color", Settings.text_color(colour))
	l.add_theme_constant_override("line_separation", 1)
	Glossary.hook(l)
	return l

# Sets plain text on a rich label with its mechanic words linked (only on a change: setting it ends a hover).
# `game`: the game's own words too (gold, bench, interest...; Glossary.GAME_TERMS), as the tutorial does.
static func set_rich(l: RichTextLabel, plain: String, game := false) -> void:
	var said := Glossary.bbcode(plain, game)
	if l.text != said:
		l.text = said

# A dark cell with a coloured edge on its left (the inspector's stat cells), padded; put content in it.
static func cell(accent: Color, pad := Vector4(5, 7, 5, 6)) -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # for a tooltip
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := flat(CELL_FILL, 3, pad)
	st.border_width_left = 2
	st.border_color = accent.darkened(0.35)
	box.add_theme_stylebox_override("panel", st)
	return box

# A stat cell: a pixel icon in the accent colour, the value in the pixel font, a caption under it.
static func stat_cell(icon: String, accent: Color, value: String, caption: String, value_colour := HudStyle.INK) -> PanelContainer:
	var box := cell(accent)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 7)
	box.add_child(h)
	h.add_child(PixelIcon.new(icon, accent, 16))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", -3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var v := HudStyle.number(19, value_colour)
	v.name = "Value"
	v.text = value
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(v)
	var c := HudStyle.caps(9, HudStyle.MUTED)
	c.name = "Caption"
	c.text = caption
	col.add_child(c)
	return box

# A rule row: a small spark (or another pixel icon) and linked text beside it.
static func rule_row(plain: String, colour := HudStyle.INK, icon := "spark", icon_colour := HudStyle.GOLD, size := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var i := PixelIcon.new(icon, icon_colour, 10)
	i.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(i)
	var l := rich(size, colour)
	l.name = "Text"
	set_rich(l, plain)
	h.add_child(l)
	return h

# All the text a built panel shows, one line per label (tests read panels with it).
static func texts_in(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for c in root.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Label and (c as Label).text != "":
			out.append((c as Label).text)
		elif c is RichTextLabel:
			out.append((c as RichTextLabel).get_parsed_text())
		elif c is Button and (c as Button).text != "":
			out.append((c as Button).text)
		out.append_array(texts_in(c))
	return out

# --- style boxes ----------------------------------------------------------------------------------

static func flat(bg: Color, radius := 3, pad := Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_top = pad.x
	s.content_margin_left = pad.y
	s.content_margin_bottom = pad.z
	s.content_margin_right = pad.w
	return s

# Keyboard focus: a 2 px gold outline.
static func focus_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_border_width_all(2)
	s.border_color = HudStyle.GOLD
	s.set_corner_radius_all(3)
	return s

static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

# A dark well (item slot, portrait, tile). `edge` adds a coloured inner bottom edge.
static func well_box(edge_color := Color.TRANSPARENT, edge := 0) -> StyleBoxFlat:
	var s := flat(WELL)
	if edge > 0:
		s.border_width_bottom = edge
		s.border_color = edge_color
	return s

static func well(size: Vector2, edge_color := Color.TRANSPARENT, edge := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", well_box(edge_color, edge))
	return p

# --- buttons --------------------------------------------------------------------------------------

static func _button_boxes(b: Button, normal: StyleBoxFlat, hover: StyleBoxFlat, pressed: StyleBoxFlat) -> void:
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", focus_box())

static func _button_text(b: Button, color: Color, size := 13) -> void:
	b.add_theme_font_override("font", HudStyle.label_font())
	b.add_theme_font_size_override("font_size", size)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, color)

# Gold, dark text, a 3 px darker gold inner bottom edge.
static func primary_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 40)
	var n := flat(HudStyle.GOLD)
	n.border_width_bottom = 3
	n.border_color = GOLD_LIP
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = HudStyle.GOLD.lightened(0.12)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = HudStyle.GOLD.darkened(0.1)
	p.border_width_bottom = 1
	_button_boxes(b, n, h, p)
	_button_text(b, DARK_TEXT, 14)
	return b

# Dark slate, ink text, a lit top edge and a dark bottom edge.
static func secondary_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 40)
	var n := flat(SECONDARY)
	n.border_width_top = 2
	n.border_width_bottom = 3
	n.border_color = HudStyle.EDGE
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = SECONDARY.lightened(0.08)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = WELL
	_button_boxes(b, n, h, p)
	_button_text(b, HudStyle.INK, 14)
	return b

# A tab: inactive = no fill, muted text; active = a fill and a 2 px gold line along its top.
# `content` (an HBox of icon / label / badge) sits inside and ignores the mouse.
static func tab(content: Control, height: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(content)
	return b

static func set_tab_active(b: Button, on: bool, fill: Color, flows_down := false) -> void:
	var s := StyleBoxFlat.new()
	if on:
		s.bg_color = fill
		s.border_width_top = 2
		s.border_color = HudStyle.GOLD
		s.corner_radius_top_left = 3
		s.corner_radius_top_right = 3
		if not flows_down:
			s.corner_radius_bottom_left = 3
			s.corner_radius_bottom_right = 3
	else:
		s.bg_color = Color.TRANSPARENT
	var hover := s.duplicate() as StyleBoxFlat
	if not on:
		hover.bg_color = Color(1, 1, 1, 0.04)
	_button_boxes(b, s, hover, s)
	for l in b.find_children("*", "Label", true, false):
		if l.has_meta("tab_text"):
			l.add_theme_color_override("font_color", HudStyle.INK if on else HudStyle.MUTED)
	for c in b.find_children("*", "Control", true, false):
		if c is PixelIcon:
			c.set_color(HudStyle.INK if on else HudStyle.MUTED)

static func tab_label(label: String, size := 12) -> Label:
	var l := text(size, HudStyle.MUTED)
	l.text = label
	l.set_meta("tab_text", true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

# --- badges and chips -----------------------------------------------------------------------------

# A 16 px count pill. Active: gold with dark text; inactive: slate with muted text.
static func badge() -> Label:
	var l := text(10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(16, 16)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	set_badge(l, 0, false)
	return l

static func set_badge(l: Label, n: int, active: bool) -> void:
	l.text = str(n)
	l.add_theme_stylebox_override("normal", flat(HudStyle.GOLD if active else BADGE_OFF, 8, Vector4(0, 4, 0, 4)))
	var fg: Color = DARK_TEXT if active else Settings.text_color(HudStyle.MUTED)
	l.add_theme_color_override("font_color", fg)
	l.remove_theme_constant_override("outline_size")   # high contrast: outline only light text (Settings.contrast)
	Settings.contrast(l, fg)

# A small chip: tier numbers in the synergy list, planned synergies in the planner.
static func chip(label: String, bg: Color, fg: Color, size := 11, outline := Color.TRANSPARENT) -> Label:
	var l := text(size, fg)
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s := flat(bg, 3, Vector4(1, 5, 1, 5))
	if outline.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = outline
	l.add_theme_stylebox_override("normal", s)
	return l

# --- portraits and item icons ---------------------------------------------------------------------

# The 96 px portrait for a unit, found by its .tres file name; null when it has none. In a run it is
# redrawn from the unit's model in the board's light (PortraitStudio); outside one, the baked image.
static func portrait(d: UnitData) -> Texture2D:
	if d == null or d.resource_path == "":
		return null
	var key := d.resource_path.get_file().get_basename()
	if not _portraits.has(key):
		var p := PORTRAIT_DIR + key + ".png"
		_portraits[key] = load(p) if ResourceLoader.exists(p) else null
	return PortraitStudio.texture_for(d, key, _portraits[key])

static func item_icon(item: ItemData) -> Texture2D:
	if item == null:
		return null
	if item.icon != null:
		return item.icon
	var key := String(item.id)
	if not _icons.has(key):
		var p := ITEM_ICON_DIR + key + ".png"
		_icons[key] = load(p) if ResourceLoader.exists(p) else null
	return _icons[key]

# A portrait (or the unit's short name when it has no portrait yet) in a dark well.
static func portrait_well(d: UnitData, side: float, font_size := 14) -> PanelContainer:
	var w := well(Vector2(side, side))
	var tex := portrait(d)
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.add_child(r)
	else:
		var l := HudStyle.number(font_size, HudStyle.MUTED)
		l.text = d.label() if d != null else "?"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		w.add_child(l)
	return w

# --- synergy text ---------------------------------------------------------------------------------

# The effect at one tier, as the player reads it ("Casters +30% damage").
static func effect_text(tag: String, tier: int) -> String:
	return Synergies.tier_text(tag, tier)

# --- pixel icons ----------------------------------------------------------------------------------

# Small icons drawn with rectangles, so they stay crisp: "chart", "grid", "lines", "chev_left",
# "chev_right", "hex", "check".
class PixelIcon extends Control:
	var kind := ""
	var color := HudStyle.MUTED

	func _init(k := "", c := HudStyle.MUTED, side := 14.0) -> void:
		kind = k
		color = c
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_color(c: Color) -> void:
		color = c
		queue_redraw()

	func _draw() -> void:
		var s := minf(custom_minimum_size.x, custom_minimum_size.y)   # drawn at its own size, centred in its rect
		if s <= 0.0:
			s = minf(size.x, size.y)
		var o := ((size - Vector2(s, s)) / 2.0).floor()
		var u := s / 14.0   # one "pixel" of the 14 px design
		var px := func(x: float, y: float, w: float, h: float):
			draw_rect(Rect2(o + Vector2(x, y) * u, Vector2(w, h) * u), color)
		match kind:
			"chart":
				px.call(1, 8, 3, 5)
				px.call(5.5, 4, 3, 9)
				px.call(10, 1, 3, 12)
			"grid":
				px.call(1, 1, 5, 5)
				px.call(8, 1, 5, 5)
				px.call(1, 8, 5, 5)
				px.call(8, 8, 5, 5)
			"lines":
				px.call(1, 2, 12, 2)
				px.call(1, 6, 12, 2)
				px.call(1, 10, 12, 2)
			"chev_left":
				for i in 5:
					px.call(8 - i, 2 + i, 2, 1)
					px.call(8 - i, 11 - i, 2, 1)
				px.call(3, 7, 2, 1)
			"chev_right":
				for i in 5:
					px.call(4 + i, 2 + i, 2, 1)
					px.call(4 + i, 11 - i, 2, 1)
				px.call(9, 7, 2, 1)
			"hex":
				var pts := PackedVector2Array()
				for i in 6:
					var a := deg_to_rad(60.0 * i - 90.0)
					pts.append(o + Vector2(s / 2.0, s / 2.0) + Vector2(cos(a), sin(a)) * s * 0.47)
				draw_colored_polygon(pts, color)
			"heart":   # health
				px.call(2, 2, 4, 1)
				px.call(8, 2, 4, 1)
				px.call(1, 3, 12, 3)
				px.call(2, 6, 10, 1)
				px.call(3, 7, 8, 1)
				px.call(4, 8, 6, 1)
				px.call(5, 9, 4, 1)
				px.call(6, 10, 2, 1)
			"sword":   # damage: a blade from the top right, a crossguard, the hilt
				for i in 6:
					px.call(11 - i, 1 + i, 2, 2)
				px.call(3, 5, 2, 2)
				px.call(7, 9, 2, 2)
				px.call(4, 8, 2, 2)
				px.call(2, 10, 2, 2)
				px.call(1, 11, 2, 2)
			"bolt":   # attack speed
				px.call(6, 1, 5, 1)
				px.call(5, 2, 4, 1)
				px.call(4, 3, 4, 1)
				px.call(3, 4, 4, 1)
				px.call(3, 5, 8, 2)
				px.call(7, 7, 3, 1)
				px.call(6, 8, 3, 1)
				px.call(5, 9, 3, 1)
				px.call(4, 10, 3, 1)
				px.call(4, 11, 2, 1)
				px.call(4, 12, 1, 1)
			"target":   # range
				px.call(4, 1, 6, 2)
				px.call(4, 11, 6, 2)
				px.call(1, 4, 2, 6)
				px.call(11, 4, 2, 6)
				px.call(2, 2, 2, 2)
				px.call(10, 2, 2, 2)
				px.call(2, 10, 2, 2)
				px.call(10, 10, 2, 2)
				px.call(6, 6, 2, 2)
			"drop":   # mana
				px.call(6, 1, 2, 2)
				px.call(5, 3, 4, 2)
				px.call(4, 5, 6, 2)
				px.call(3, 7, 8, 3)
				px.call(4, 10, 6, 1)
				px.call(5, 11, 4, 1)
			"shield":   # armour
				px.call(2, 1, 10, 6)
				px.call(3, 7, 8, 2)
				px.call(4, 9, 6, 2)
				px.call(5, 11, 4, 1)
				px.call(6, 12, 2, 1)
			"ward":   # magic resist: a shield outline with a rune in it
				px.call(2, 1, 10, 2)
				px.call(2, 3, 2, 5)
				px.call(10, 3, 2, 5)
				px.call(3, 8, 2, 2)
				px.call(9, 8, 2, 2)
				px.call(5, 10, 2, 2)
				px.call(7, 10, 2, 2)
				px.call(6, 12, 2, 1)
				px.call(6, 4, 2, 4)
				px.call(5, 5, 4, 1)
			"orb":   # ability power: a four-pointed star over a glowing orb
				px.call(6, 0, 2, 3)
				px.call(6, 11, 2, 3)
				px.call(0, 6, 3, 2)
				px.call(11, 6, 3, 2)
				px.call(4, 4, 6, 6)
				px.call(3, 5, 8, 4)
				px.call(5, 3, 4, 8)
			"block":   # mitigation: a raised forearm guard, a bar across the blow
				px.call(1, 2, 12, 3)
				px.call(2, 5, 10, 2)
				px.call(3, 9, 2, 4)
				px.call(9, 9, 2, 4)
				px.call(6, 8, 2, 5)
			"fang":   # omnivamp
				px.call(2, 2, 10, 2)
				px.call(3, 4, 3, 3)
				px.call(4, 7, 2, 2)
				px.call(4, 9, 1, 1)
				px.call(8, 4, 3, 3)
				px.call(8, 7, 2, 2)
				px.call(9, 9, 1, 1)
			"spark":   # a special rule (crits, shields, burns...)
				px.call(6, 1, 2, 12)
				px.call(1, 6, 12, 2)
				px.call(5, 5, 4, 4)
			"crown":
				px.call(1, 9, 12, 3)
				px.call(1, 3, 2, 6)
				px.call(6, 2, 2, 7)
				px.call(11, 3, 2, 6)
				px.call(3, 6, 8, 3)
			"check":
				px.call(2, 7, 2, 2)
				px.call(4, 9, 2, 2)
				px.call(6, 7, 2, 2)
				px.call(8, 5, 2, 2)
				px.call(10, 3, 2, 2)

# The synergy count in a hexagon (26 x 28): gold when every tier is reached, darker gold when some
# are, slate when none.
class HexBadge extends Control:
	var count := 0
	var state := 0   # 0 inactive, 1 some tiers, 2 all tiers

	func _init() -> void:
		custom_minimum_size = Vector2(26, 28)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_count(n: int, s: int) -> void:
		count = n
		state = s
		queue_redraw()

	func _draw() -> void:
		var fill: Color = [DockKit.LINE, DockKit.GOLD_DARK, HudStyle.GOLD][state]
		var edge: Color = [HudStyle.EDGE, DockKit.GOLD_EDGE_DARK, DockKit.GOLD_EDGE][state]
		var c := size / 2.0
		var pts := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(60.0 * i - 90.0)
			pts.append(c + Vector2(cos(a) * (size.x / 2.0 - 1.0) / 0.866, sin(a) * (size.y / 2.0 - 1.0)))
		for i in pts.size():
			pts[i].x = clampf(pts[i].x, 1.0, size.x - 1.0)
		draw_colored_polygon(pts, fill)
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, edge, 2.0)
		var f := HudStyle.number_font()
		var txt := str(count)
		var fs := 17
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var asc := f.get_ascent(fs)
		var desc := f.get_descent(fs)
		var col: Color = HudStyle.MUTED if state == 0 else DockKit.DARK_TEXT
		draw_string(f, Vector2(c.x - w / 2.0, c.y + (asc - desc) / 2.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

# A thin bar: track plus a fill (the damage panel's per-unit bars).
class Bar extends Control:
	var ratio := 0.0
	var color := HudStyle.GOLD

	func _init(h := 6.0) -> void:
		custom_minimum_size = Vector2(0, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_value(r: float, c: Color) -> void:
		ratio = clampf(r, 0.0, 1.0)
		color = c
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), HudStyle.TRACK)
		if ratio > 0.0:
			draw_rect(Rect2(0, 0, maxf(1.0, size.x * ratio), size.y), color)

# A gold coin (the shop mockup's gold square): lighter top, darker bottom edge.
class Coin extends Control:
	var side := 12.0

	func _init(s := 12.0) -> void:
		side = s
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var o := ((size - Vector2(side, side)) / 2.0).floor()
		var r := Rect2(o, Vector2(side, side))
		var body := StyleBoxFlat.new()
		body.bg_color = HudStyle.GOLD
		body.set_corner_radius_all(int(side / 4.0))
		body.border_width_bottom = maxi(2, int(side / 6.0))
		body.border_color = DockKit.GOLD_LIP
		draw_style_box(body, r)
		draw_rect(Rect2(o + Vector2(side * 0.25, side * 0.18), Vector2(side * 0.3, maxf(1.0, side * 0.12))), HudStyle.GOLD.lightened(0.35))

# Segments in a row: filled ones in `on`, the rest as track (owned copies on a shop card).
class Pips extends Control:
	var count := 3
	var filled := 0
	var on := HudStyle.INK

	func _init(n := 3, w := 8.0, h := 5.0) -> void:
		count = n
		custom_minimum_size = Vector2(n * w + (n - 1) * 2.0, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_filled(n: int) -> void:
		filled = n
		queue_redraw()

	func _draw() -> void:
		var w := (size.x - (count - 1) * 2.0) / count
		for i in count:
			draw_rect(Rect2(i * (w + 2.0), 0, w, size.y), on if i < filled else HudStyle.TRACK)

# A segmented progress bar (XP in the shop's level panel): `segments` blocks, filled by ratio.
class SegBar extends Control:
	var segments := 10
	var ratio := 0.0
	var color := HudStyle.YOU

	func _init(n := 10, h := 5.0) -> void:
		segments = n
		custom_minimum_size = Vector2(0, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var step := 0.0    # > 0: each segment stands for `step` of `total` (the XP bar: 4 XP, one Buy XP)
	var total := 0.0

	func set_ratio(r: float) -> void:
		ratio = clampf(r, 0.0, 1.0)
		queue_redraw()

	# Segments of a fixed size: `amount` of `whole`, one segment per `per` (the last one shorter when
	# `whole` isn't a multiple: 6 XP is one and a half segments of 4).
	func set_steps(amount: float, whole: float, per: float) -> void:
		step = per
		total = maxf(whole, 0.001)
		segments = maxi(ceili(total / per), 1)
		set_ratio(amount / total)

	func _draw() -> void:
		var gap := 2.0 if segments <= 12 else 1.0
		var units := float(segments) if step <= 0.0 else total / step   # segment widths in "whole segments"
		var w := (size.x - gap * (segments - 1)) / units
		var lit := ratio * units
		var x := 0.0
		for i in segments:
			var span := minf(1.0, units - i)   # the last one may be a part segment
			draw_rect(Rect2(x, 0, w * span, size.y), HudStyle.TRACK)
			var part := clampf(lit - i, 0.0, span)
			if part > 0.0:
				draw_rect(Rect2(x, 0, w * part, size.y), color)
			x += w * span + gap

# A small padlock as a texture (the shop's Lock button uses it as its icon).
static func padlock(color: Color, px := 2) -> ImageTexture:
	var rows := [
		"..####..",
		".#....#.",
		".#....#.",
		"########",
		"########",
		"###..###",
		"###..###",
		"########",
	]
	var img := Image.create(8 * px, 8 * px, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in rows.size():
		for x in 8:
			if rows[y][x] == "#":
				img.fill_rect(Rect2i(x * px, y * px, px, px), color)
	return ImageTexture.create_from_image(img)
