# tip.gd
class_name Tip extends RefCounted

# Godot doesn't wrap tooltip text: a long single line runs off the edge of the screen. Pass every
# tooltip through Tip.wrap() (tooltip_text = Tip.wrap("...") or return Tip.wrap(...) from
# _get_tooltip). tools/tooltip_checks measures every tooltip in the game and fails on an unwrapped one.

const MAX_WIDTH := 340.0   # pixels at the default font; comfortably inside the 1152 px window

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

# Width in pixels of one line in the default font (what a tooltip uses).
static func width_of(line: String) -> float:
	var w := ThemeDB.fallback_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeDB.fallback_font_size).x
	return w if w > 0.0 else line.length() * 8.0   # no font metrics (rare): estimate
