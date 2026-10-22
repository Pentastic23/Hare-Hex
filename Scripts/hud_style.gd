# hud_style.gd
class_name HudStyle extends RefCounted

# Colours, fonts and plates for the combat HUD (timer, round tracker, HP standings), from
# menagerie/hud/HUD_SPEC.md: small, dark, semi-opaque plates with colour only where it means something.
# The intended fonts are Jersey 10 (numbers) and Atkinson Hyperlegible Bold (labels, names). Drop the
# .ttf files into res://fonts/ under the names below and they are used; until then a bold monospace
# system font and the default font (emboldened) stand in.

const INK := Color("ece6d6")
const MUTED := Color("a9aec4")
const GOLD := Color("f2c14e")
const RED := Color("ff6b5e")
const YOU := Color("6cc4ff")
const YOU_EDGE := Color("3f7fb8")
const ENEMY := Color("ff8a4c")
const ENEMY_EDGE := Color("a4522a")
const NEUTRAL := Color("8f97b3")
const TRACK := Color("262b3f")
const FILL := Color(0.090, 0.102, 0.149, 0.9)        # #171a26 at 90%
const FILL_YOU := Color(0.118, 0.141, 0.212, 0.9)    # #1e2436 at 90%
const EDGE := Color("3d4566")
const EDGE_GOLD := Color("8a6a1f")
const EDGE_RED := Color("8a2f29")
const EDGE_OUT := Color("2c3249")
const LIP := Color("0a0b11")

const NUMBER_FONT_PATH := "res://fonts/Jersey10-Regular.ttf"
const LABEL_FONT_PATH := "res://fonts/AtkinsonHyperlegible-Bold.ttf"

static var _number_font: Font
static var _label_font: Font

static func number_font() -> Font:
	if _number_font == null:
		if ResourceLoader.exists(NUMBER_FONT_PATH):
			_number_font = load(NUMBER_FONT_PATH)
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Menlo", "Courier New", "monospace"])
			f.font_weight = 700
			_number_font = f
	return _number_font

static func label_font() -> Font:
	if _label_font == null:
		if ResourceLoader.exists(LABEL_FONT_PATH):
			_label_font = load(LABEL_FONT_PATH)
		else:
			var v := FontVariation.new()
			v.base_font = ThemeDB.fallback_font
			v.variation_embolden = 0.6
			_label_font = v
	return _label_font

# A number in the pixel font (time, HP, round).
static func number(size: int, color := INK) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", number_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Small caps ("COMBAT", "STAGE 3"): give it upper-case text. Letter spacing comes from a font variation.
static func caps(size := 11, color := MUTED) -> Label:
	var l := Label.new()
	var v := FontVariation.new()
	v.base_font = label_font()
	v.spacing_glyph = 2
	l.add_theme_font_override("font", v)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A player name in the label font.
static func name_label(color := INK) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", label_font())
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
