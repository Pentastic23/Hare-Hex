# synergy_panel.gd
extends VBoxContainer

# Synergy list (top left). A header button folds the list open or closed; the state is remembered
# in Settings.show_synergies. The whole box is hidden while the board is empty.

const GOLD := Color(1.0, 0.85, 0.3)

var board: Board
var header: Button
var list: VBoxContainer
var expanded := true
var _timer := 0.0
var _last_sig := ""
var _active := 0
var _total := 0

func _ready():
	board = get_tree().get_first_node_in_group("board") as Board
	Settings.ensure_loaded()
	expanded = Settings.show_synergies
	header = Button.new()
	header.flat = true
	header.focus_mode = Control.FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", GOLD)
	header.add_theme_color_override("font_hover_color", Color.WHITE)
	header.tooltip_text = Tip.wrap("Show or hide the synergy list.")
	header.pressed.connect(func():
		expanded = not expanded
		Settings.show_synergies = expanded
		Settings.save_settings()
		_apply_expanded())
	add_child(header)
	list = VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 6)
	add_child(list)
	get_parent().visible = false
	_apply_expanded()

func _apply_expanded():
	list.visible = expanded
	header.text = "Synergies  [-]" if expanded else "Synergies (%d active)  [+]" % _active

func _process(delta):
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	_refresh()

func _refresh():
	if board == null:
		return
	var units: Array = []
	for u in board.all_player_units():
		if u.coord.x >= 0:
			units.append(u)
	var counts := Synergies.count(units)

	var sig := str(counts)
	if sig == _last_sig:
		return
	_last_sig = sig

	for c in list.get_children():
		c.queue_free()

	var tags: Array = counts.keys().filter(func(t): return Synergies.DEFS.has(t))
	get_parent().visible = not tags.is_empty()   # hide the box when the board is empty

	tags.sort_custom(func(a, b):
		var ta := Synergies.active_tier(a, counts[a])
		var tb := Synergies.active_tier(b, counts[b])
		if (ta >= 0) != (tb >= 0):
			return ta >= 0
		return counts[a] > counts[b])

	_active = 0
	_total = tags.size()
	for tag in tags:
		var n: int = counts[tag]
		var t := Synergies.active_tier(tag, n)
		if t >= 0:
			_active += 1
		var parts: PackedStringArray = []
		for th in Synergies.DEFS[tag]["thresholds"]:
			parts.append(str(th))
		var l := Label.new()
		l.text = "%s  %d/%d" % [tag, n, Synergies.next_threshold(tag, n)]
		l.tooltip_text = Tip.wrap("%s\nTiers: %s units" % [Synergies.DEFS[tag]["desc"], " / ".join(parts)])
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.modulate = GOLD if t >= 0 else Color(0.65, 0.65, 0.65)
		list.add_child(l)
	_apply_expanded()
