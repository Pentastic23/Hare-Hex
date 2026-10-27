# glossary.gd
class_name Glossary

# What the game's mechanic words mean (burn, chill, stun, shield, hex...), so any text about a unit can
# explain them. Two ways:
#   - explain(text): the text plus a short "Burn: ..." line for each mechanic it mentions (for tooltips,
#     which can't be hovered themselves: the shop cards, the planner, synergy and item rows, item chips).
#   - bbcode(text): the text with each mechanic word coloured and underlined as a link (meta = the term),
#     for a RichTextLabel; hook(label) shows the term's explanation as the label's tooltip while the mouse
#     is over the word (the unit inspector's ability and rules).
# Matching is by word start, any case, any ending ("burn", "burns", "burning"); a term is explained once.

# [term, regex (word stems), explanation]. Order matters where words overlap (damage reduction before
# others). Keep explanations short: they go in tooltips.
const TERMS := [
	["Stun", "stun\\w*|frozen|freez\\w*", "Can't move, attack or cast, and gains no mana, until it wears off."],
	["Silence", "silenc\\w*", "Gains no mana, so it can't cast its ability, until it wears off."],
	["Blind", "blind\\w*", "Its next attacks miss."],
	["Taunt", "taunt\\w*", "Enemies it taunts must attack it."],
	["Root", "root\\w*", "Can still attack and cast, but can't move."],
	["Charm", "(?<!mana )(?<!heartwood )charm\\w*","Fights for the other side for a while (marked with a pink hex sigil)."],
	["Doom", "doom\\w*", "Takes a big hit when the timer runs out. If it dies first, the doom jumps to an ally."],
	["Execute", "execut\\w*", "An enemy left below this share of its max HP dies at once, whatever its damage reduction."],
	["Shield", "shield\\w*", "Soaks up damage before HP does; a white strip on the health bar. Ability shields run out after a while."],
	["Revive", "reviv\\w*", "Once per fight, gets back up after falling, with this share of its HP."],
	["Dodge", "dodg\\w*", "Every Nth attack against it misses."],
	["Crit", "crit\\w*", "Every Nth attack deals double damage."],
	["Omnivamp", "omnivamp|lifesteal|vamp", "Heals for this share of all the damage it deals, attacks and abilities."],
	["Regen", "regen\\w*", "Heals this share of its max HP every second."],
	["Thorns", "thorns", "Attackers take damage every time they hit it."],
	["Burn", "burn\\w*", "Takes a share of its max HP as damage every second for a few seconds; its health bar turns orange."],
	["Chill", "chill\\w*", "Attacks more slowly for a short time (never more than 80% slower)."],
	["Curse", "curse\\w*", "Takes more damage from everything for a short time."],
	["Damage reduction", "damage reduction|less damage taken|reduction", "Takes this much less damage (60% at most, from all sources together)."],
	["Summon", "summon\\w*", "A unit that fights for this fight only: no traits, items or selling, and gone when the fight ends."],
	["Leap", "leap\\w*|charge\\w*|dash\\w*", "Jumps to another hex; enemies attacking it have to pick a new target."],
	["Mana", "mana(?! charm)", "Fills by 10 per attack and a little when hit. Full mana: the unit casts its ability."],
	["Ascend", "ascen\\w*|4-star\\w*|4 stars", "A 3-star unit carrying the Ancient Sigil that survives 8 wins becomes 4-star, its astral form: x5 HP and damage (5-costs x7.5). Merging never makes one."],
	["Hex", "hexes|hex(?! ward)", "One tile of the board. Ranges and areas are counted in hexes."],
]

const KEYWORD_COLOUR := "f2c14e"   # gold, like the HUD's highlights

static var _compiled := []

static func _terms() -> Array:
	if _compiled.is_empty():
		for t in TERMS:
			var re := RegEx.new()
			re.compile("(?i)\\b(" + t[1] + ")\\b")
			_compiled.append([t[0], re, t[2]])
	return _compiled

# The terms a text mentions, in the order of TERMS.
static func terms_in(text: String) -> Array:
	var out := []
	for t in _terms():
		if (t[1] as RegEx).search(text) != null:
			out.append(t[0])
	return out

static func meaning(term: String) -> String:
	for t in _terms():
		if t[0] == term:
			return t[2]
	return ""

# The text with a line for each mechanic it mentions ("Burn: ..."), under a blank line. `about`: look for
# mechanics only in this part (a long tooltip whose tail lists other things, like an item's resonances).
static func explain(text: String, about := "") -> String:
	var lines := PackedStringArray()
	for term in terms_in(about if about != "" else text):
		lines.append("%s: %s" % [term, meaning(term)])
	return text if lines.is_empty() else text + "\n\n" + "\n".join(lines)

# The text as BBCode with every mechanic word as a gold, underlined link ([url=Term]word[/url]).
static func bbcode(text: String) -> String:
	var spans := []   # [start, end, term], non-overlapping, first term wins
	for t in _terms():
		for m in (t[1] as RegEx).search_all(text):
			var a := m.get_start()
			var b := m.get_end()
			if spans.any(func(s): return a < s[1] and b > s[0]):
				continue
			spans.append([a, b, t[0]])
	spans.sort_custom(func(x, y): return x[0] < y[0])
	var out := ""
	var at := 0
	for s in spans:
		out += _escape(text.substr(at, s[0] - at))
		out += "[url=%s][color=#%s]%s[/color][/url]" % [s[2], KEYWORD_COLOUR, _escape(text.substr(s[0], s[1] - s[0]))]
		at = s[1]
	return out + _escape(text.substr(at))

static func _escape(t: String) -> String:
	return t.replace("[", "[lb]")

# Makes a RichTextLabel show a term's explanation as its tooltip while the mouse is on that word.
static func hook(label: RichTextLabel) -> void:
	label.bbcode_enabled = true
	label.meta_underlined = true
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.meta_hover_started.connect(func(meta): label.tooltip_text = Tip.wrap("%s: %s" % [str(meta), meaning(str(meta))]))
	label.meta_hover_ended.connect(func(_meta): label.tooltip_text = "")
