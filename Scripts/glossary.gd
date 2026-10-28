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

# [term, regex (word stems), explanation]. Order matters where words overlap (armour before
# others). Keep explanations short: they go in tooltips.
const TERMS := [
	["Stun", "stun\\w*|frozen|freez\\w*", "Can't move, attack or cast, and gains no mana, until it wears off."],
	["Silence", "silenc\\w*", "Gains no mana, so it can't cast its ability, until it wears off."],
	["Blind", "blind\\w*", "Its next attacks miss."],
	["Taunt", "taunt\\w*", "Enemies it taunts must attack it."],
	["Root", "root\\w*", "Can still attack and cast, but can't move."],
	["Charm", "(?<!mana )(?<!heartwood )(?<!wind )charm\\w*","Fights for the other side for a while (marked with a pink hex sigil)."],
	["Doom", "doom\\w*", "Takes a big hit when the timer runs out. If it dies first, the doom jumps to an ally."],
	["Execute", "execut\\w*", "An enemy left below this share of its max HP dies at once, whatever its armour or shield."],
	["Shield", "(?<!tower )shield\\w*","Soaks up damage before HP does; a white strip on the health bar. Ability shields run out after a while."],
	["Revive", "reviv\\w*", "Once per fight, gets back up after falling, with this share of its HP."],
	["Dodge", "dodg\\w*", "Every Nth attack against it misses."],
	["Crit", "crit\\w*", "Every Nth attack deals double damage."],
	["Omnivamp", "omnivamp|lifesteal|vamp", "Heals for this share of all the damage it deals, attacks and abilities."],
	["Regen", "regen\\w*", "Heals this share of its max HP every second."],
	["Thorns", "thorns", "Attackers take damage every time they hit it."],
	["Burn", "burn\\w*", "Takes a share of its max HP as damage every second for a few seconds; its health bar turns orange."],
	["Chill", "chill\\w*", "Attacks more slowly for a short time (never more than 80% slower)."],
	["Curse", "curse\\w*", "Takes more damage from everything for a short time."],
	["Attack power", "attack power", "Attacks deal this much more damage."],
	["Ability power", "ability power", "Its ability's damage, heals and shields are this much bigger."],
	["Armour", "armou?r\\w*","Cuts attack (physical) damage: x 100 / (100 + armour)."],
	["Magic resist", "magic resist\\w*","Cuts ability, burn and zone (magic) damage: x 100 / (100 + magic resist)."],
	["Mitigation", "mitigation", "Taken off every hit after armour or magic resist (not burns or zones); at least 1 gets through."],
	["Sunder", "sunder\\w*","Lowers the target's armour for 3 s."],
	["Shred", "shred\\w*","Lowers the target's magic resist for 3 s."],
	["Summon", "summon\\w*", "A unit that fights for this fight only: no traits, items or selling, and gone when the fight ends."],
	["Leap", "leap\\w*|charge\\w*|dash\\w*", "Jumps to another hex; enemies attacking it have to pick a new target."],
	["Mana", "mana(?! charm)", "Fills by 10 per attack and a little when hit. Full mana: the unit casts its ability."],
	["Ascend", "ascen\\w*|4-star\\w*|4 stars", "A 3-star unit carrying the Ancient Sigil that survives 8 wins becomes 4-star, its astral form: x5 HP and damage (5-costs x7.5). Merging never makes one."],
	["Hex", "hexes|hex(?! ward)(?! orb)", "One tile of the board. Ranges and areas are counted in hexes."],
]

# The game's own words (gold, bench, interest, resonance...), linked only where asked for
# (bbcode(text, true): the tutorial), so ability and item texts don't light up every "gold".
const GAME_TERMS := [
	["Gold", "gold", "Spent in the shop. You earn some every round, plus interest and streak bonuses."],
	["Bench", "bench\\w*", "The row of 9 framed hexes below the board. Units wait there; only units on the board fight."],
	["Board", "board", "The hex field where fights happen. Your half is nearest you; the far half is the enemy's."],
	["Shop", "shop\\w*", "Five units for sale each round, at the bottom of the screen. Bought units go to your bench."],
	["Reroll", "reroll\\w*", "2 gold for five new offers in the shop."],
	["Lock", "lock(?!ed hex)\\w*", "Keeps the shop's offers into the next round instead of rolling new ones."],
	["XP", "xp", "Experience. Fill the bar to reach the next level: 2 a round for free, 4 for 4 gold with Buy XP."],
	["Level", "level(?:s|ling| up)?", "How many units you may field at once, and how strong the shop's units can be. 10 at most."],
	["Star", "[1-4]-stars?|stars?", "A unit's rank. Three of a unit merge into the next star: about 1.8x as strong at 2 stars, 3.2x at 3."],
	["Merge", "merg\\w*", "Three copies of a unit at the same star join into one unit a star higher, wherever they stand."],
	["Trait", "traits?|synerg\\w*|origins?|class(?:es)?", "Each unit has an origin and one or two classes. Enough different units of one trait on the board give a bonus."],
	["Item", "items?", "Gear for a unit: up to 3 each. Items come from fights (here, from the tutorial)."],
	["Element", "elements?", "Every basic item has one (Might, Vigor, Swift, Guard, Blood, Arcane), shown beside its name."],
	["Resonance", "resonan\\w*", "Two items with different elements on one unit wake a bonus between them; three elements add Prism."],
	["Interest", "interest", "+1 gold each round for every 10 gold you have saved, up to +5."],
	["Streak", "streak\\w*", "Winning or losing several fights in a row: 2-3 = +1 gold a round, 4 = +2, 5 or more = +3."],
	["HP", "hp", "Your health as a player. Losing a fight costs some; at 0 the run is over."],
	["Prep", "prep(?:aration)?", "The time between fights to buy, place and plan. The fight starts when it ends."],
	["King", "kings?", "Each side's king stands at the edge of the board and strikes a random enemy every 10 seconds. It can't be hurt."],
	["Odds", "odds", "The chance of each cost (1 to 5 gold) in each shop slot. Higher levels shift it to costlier units."],
	["Planner", "planner", "Pick the units you're aiming for: they get a star in the shop, and it shows the traits your plan makes."],
	["Inspector", "inspector", "Right-click a unit to see its stats, traits, ability and items."],
	["Sell", "sell\\w*|sold", "Gives back gold for a unit: its cost, times 3 for each star above 1."],
	["Unit cap", "unit cap", "Units you may field: your level. The rest wait on the bench."],
]

const KEYWORD_COLOUR := "f2c14e"   # gold, like the HUD's highlights

static var _compiled := []
static var _compiled_game := []

static func _terms(game := false) -> Array:
	if _compiled.is_empty():
		for t in TERMS:
			var re := RegEx.new()
			re.compile("(?i)\\b(" + t[1] + ")\\b")
			_compiled.append([t[0], re, t[2]])
		for t in GAME_TERMS:
			var re := RegEx.new()
			re.compile("(?i)\\b(" + t[1] + ")\\b")
			_compiled_game.append([t[0], re, t[2]])
	return _compiled + _compiled_game if game else _compiled

# The terms a text mentions, in the order of TERMS.
static func terms_in(text: String) -> Array:
	var out := []
	for t in _terms():
		if (t[1] as RegEx).search(text) != null:
			out.append(t[0])
	return out

static func meaning(term: String) -> String:
	for t in _terms(true):
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
static func bbcode(text: String, game := false) -> String:
	var spans := []   # [start, end, term], non-overlapping, first term wins
	for t in _terms(game):
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
