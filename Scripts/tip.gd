# tip.gd
class_name Tip extends RefCounted

# Godot doesn't wrap tooltip text: a long single line runs off the edge of the screen. Pass every
# tooltip through Tip.wrap() (tooltip_text = Tip.wrap("...") or return Tip.wrap(...) from
# _get_tooltip). tools/tooltip_checks measures every tooltip in the game and fails on an unwrapped one.

const MAX_WIDTH := 340.0   # pixels in the tooltip font; comfortably inside the 1152 px window
# Tooltips are styled by the project theme (tres/ui_theme.tres: TooltipPanel / TooltipLabel); measure
# with the same font and size it uses.
const THEME_PATH := "res://tres/ui_theme.tres"
static var _font: Font
static var _size := 0

# Breaks `text` at spaces so no line is wider than max_width pixels. Existing newlines are kept.
static func wrap(text: String, max_width := MAX_WIDTH) -> String:
	if text == "":
		return text
	var out: PackedStringArray = []
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" ", true):
			var candidate := word if line == "" else line + " " + word
			if line != "" and width_of(candidate) > max_width:
				out.append(line)
				line = word
			else:
				line = candidate
		out.append(line)
	return "\n".join(out)

# Width in pixels of one line in the tooltip font.
static func width_of(line: String) -> float:
	if _font == null:
		var theme := load(THEME_PATH) as Theme if ResourceLoader.exists(THEME_PATH) else null
		if theme != null and theme.has_font("font", "TooltipLabel"):
			_font = theme.get_font("font", "TooltipLabel")
			_size = theme.get_font_size("font_size", "TooltipLabel")
		else:
			_font = ThemeDB.fallback_font
			_size = ThemeDB.fallback_font_size
	var w := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x
	return w if w > 0.0 else line.length() * 8.0   # no font metrics (rare): estimate
