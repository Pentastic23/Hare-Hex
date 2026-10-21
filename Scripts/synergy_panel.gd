# synergy_panel.gd
extends VBoxContainer

var board: Board
var _timer := 0.0
var _last_sig := ""

func _ready():
	board = get_tree().get_first_node_in_group("board") as Board
	get_parent().visible = false

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

	for c in get_children():
		c.queue_free()

	var tags: Array = counts.keys().filter(func(t): return Synergies.DEFS.has(t))
	get_parent().visible = not tags.is_empty()   # hide the box when the board is empty

	tags.sort_custom(func(a, b):
		var ta := Synergies.active_tier(a, counts[a])
		var tb := Synergies.active_tier(b, counts[b])
		if (ta >= 0) != (tb >= 0):
			return ta >= 0
		return counts[a] > counts[b])

	for tag in tags:
		var n: int = counts[tag]
		var t := Synergies.active_tier(tag, n)
		var thresholds: Array = Synergies.DEFS[tag]["thresholds"]
		var parts: PackedStringArray = []
		for th in thresholds:
			parts.append(str(th))
		# Progress toward the next tier; once every tier is reached it shows the last one (e.g. 3/3).
		var target: int = int(thresholds.back())
		for th in thresholds:
			if n < int(th):
				target = int(th)
				break

		var l := Label.new()
		l.text = "%s  %d/%d" % [tag, n, target]
		l.tooltip_text = "%s\nTiers: %s units" % [Synergies.DEFS[tag]["desc"], " / ".join(parts)]
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.modulate = Color(1.0, 0.85, 0.3) if t >= 0 else Color(0.65, 0.65, 0.65)
		add_child(l)
