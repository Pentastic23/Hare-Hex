# king_panel.gd
extends VBoxContainer

# The King tab of the left box (left_dock.gd): your king, its power, and how that power stands this run
# (KingPowers): the Merchant's interest, the Gambler's luck and odds, the Necromancer's souls and
# memories, the Explorer's quests and relics, the Chaos King's proclamation, the Dragon's hoard, the Fate
# King's prophecy (with the three to choose from), and the Shadow King's forbidden knowledge (the next
# reroll, the coming enemy, the drops, the hidden rules). Then the last few things it did.
# Rebuilt (once a frame at most) when the king's state, gold, the shop or the phase changes.

const WIDTH := 210.0

var title: Label
var power: Label
var body: VBoxContainer
var log_box: VBoxContainer
var _dirty := false

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	title = DockKit.text(15, HudStyle.GOLD)
	add_child(title)
	power = DockKit.wrapping(11, HudStyle.MUTED, WIDTH)
	add_child(power)
	body = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 4)
	add_child(body)
	log_box = VBoxContainer.new()
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_theme_constant_override("separation", 2)
	add_child(log_box)
	Events.king_changed.connect(refresh)
	Events.gold_changed.connect(func(_g): refresh())
	Events.shop_rolled.connect(func(_o): refresh())
	Events.phase_changed.connect(func(_p): refresh())
	Events.xp_changed.connect(func(_l, _x, _n): refresh())
	Events.unit_sold.connect(func(_d, _s, _r): refresh())
	Events.opponent_announced.connect(func(_t): refresh())
	visibility_changed.connect(refresh)
	refresh()

# Asks for a rebuild; it happens once, at the end of the frame (several signals often come together).
func refresh() -> void:
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()

# Something waiting on the player (a prophecy to choose): the tab's badge.
func pending() -> int:
	var p := GameState.me
	return 1 if KingPowers.on(p, &"fate") and not p.king_state.get("offer", []).is_empty() else 0

func _rebuild() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	var p := GameState.me
	var id := p.king if p.king != &"" else KingSkins.selected()
	var def: Dictionary = KingSkins.DEFS.get(id, KingSkins.DEFS[KingSkins.DEFAULT])
	title.text = def.name
	title.add_theme_color_override("font_color", KingSkins.colour(id))
	power.text = "%s: %s" % [def.power, def.text]
	for c in body.get_children():
		c.queue_free()
	for c in log_box.get_children():
		c.queue_free()
	if not is_visible_in_tree():
		return
	if p.king == &"":
		if KingSkins.is_run_power(id):
			_line("Its power works in Free Play and Async PvP. Here your king only strikes.", HudStyle.MUTED)
		else:
			_line("Every 10 s of a fight your king strikes a random enemy, then shields an ally.", HudStyle.MUTED)
		return
	var s: Dictionary = p.king_state
	match p.king:
		&"merchant":
			_stat("Interest", "+%d / %d" % [p.interest_gold(), KingPowers.interest_cap(p)])
			_line("Bank %d gold for the most." % (KingPowers.interest_cap(p) * GameState.INTEREST_STEP), HudStyle.MUTED)
		&"gambler":
			var luck := float(s.get("luck", 0.0))
			_stat("This round", str(s.get("luck_name", "")) if str(s.get("luck_name", "")) != "" else "No roll yet", HudStyle.GOLD if luck > 0.0 else (HudStyle.RED if luck < 0.0 else HudStyle.INK))
			_odds(p.shop_odds())
		&"necromancer":
			_stat("Souls", "%d / %d" % [int(s.get("souls", 0)), KingPowers.SOULS_PER_MEMORY])
			var mem: Dictionary = s.get("memories", {})
			if mem.is_empty():
				_line("Sell a unit to store its memory.", HudStyle.MUTED)
			for key in mem:
				var d: UnitData = key
				_line("%s  x%d" % [d.display_name, int(mem[d])], DockKit.COST_COLORS.get(d.cost, HudStyle.INK))
			if int(s.get("raised", 0)) > 0:
				_line("Memories returned: %d" % int(s.raised), HudStyle.MUTED)
		&"explorer":
			_cap("QUESTS")
			var quests: Array = s.get("quests", [])
			if quests.is_empty():
				_line("The first quest appears in round %d." % KingPowers.QUEST_ROUNDS[0], HudStyle.MUTED)
			for q in quests:
				var mark: String = {"open": "•", "done": "✓", "failed": "✗"}[q.state]
				var col: Color = {"open": HudStyle.INK, "done": HudStyle.GOLD, "failed": HudStyle.RED}[q.state]
				var l := _line("%s %s" % [mark, KingPowers.QUESTS[q.id]], col)
				if q.state == "done" and q.has("relic"):
					l.tooltip_text = Tip.wrap("Relic: " + KingPowers.RELICS[q.relic].name)
					l.mouse_filter = Control.MOUSE_FILTER_PASS
			var relics: Array = s.get("relics", [])
			if not relics.is_empty():
				_cap("RELICS")
				for r in relics:
					var l := _line("%s: %s" % [KingPowers.RELICS[r].name, KingPowers.RELICS[r].text], HudStyle.GOLD)
					l.mouse_filter = Control.MOUSE_FILTER_PASS
		&"chaos":
			var decree := str(s.get("decree", ""))
			if decree != "":
				_stat("Proclaimed", KingPowers.DECREES[decree].name, KingSkins.colour(&"chaos"))
				_line(KingPowers.DECREES[decree].text, HudStyle.INK)
				if decree == "discount":
					_line("Discounts left: %d" % int(s.get("discount", 0)), HudStyle.MUTED)
			else:
				_line("No proclamation this round. The next comes in round %d." % _next_decree(), HudStyle.MUTED)
		&"dragon":
			_stat("Hoard", "%d gold" % int(s.get("hoard", 0)), HudStyle.GOLD)
			var next := KingPowers.next_treasure(p)
			if not next.is_empty():
				_line("At %d: %s" % [int(next[0]), next[2]], HudStyle.INK)
			_line("Collapses if a fight starts under %d gold." % KingPowers.HOARD_FLOOR, HudStyle.RED if GameState.me.gold < KingPowers.HOARD_FLOOR and int(s.get("hoard", 0)) > 0 else HudStyle.MUTED)
		&"fate":
			var offer: Array = s.get("offer", [])
			if not offer.is_empty():
				_cap("CHOOSE YOUR PROPHECY")
				for i in offer.size():
					var pr: Dictionary = KingPowers.PROPHECIES[offer[i]]
					var b := DockKit.secondary_button("%s\n→ %s" % [pr.text, pr.reward])
					b.custom_minimum_size = Vector2(WIDTH, 0)
					b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					b.add_theme_font_size_override("font_size", 11)
					b.focus_mode = Control.FOCUS_NONE
					b.tooltip_text = Tip.wrap("Choose this prophecy. If a fight starts first, the first one is taken.")
					b.pressed.connect(_choose.bind(i))
					body.add_child(b)
			elif str(s.get("prophecy", "")) != "":
				var pr: Dictionary = KingPowers.PROPHECIES[s.prophecy]
				var done := bool(s.get("fulfilled", false))
				_stat("Prophecy", "Fulfilled" if done else "Unfolding", HudStyle.GOLD if done else HudStyle.INK)
				_line(pr.text, HudStyle.INK)
				_line("Reward: " + pr.reward, HudStyle.GOLD if done else HudStyle.MUTED)
			else:
				_line("Your prophecies are offered after the first round.", HudStyle.MUTED)
		&"shadow":
			_shadow()
	for line in s.get("log", []):
		var l := DockKit.wrapping(10, HudStyle.MUTED, WIDTH)
		l.text = "› " + str(line)
		log_box.add_child(l)

func _choose(i: int) -> void:
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.choose_prophecy(i):
		Sfx.play(&"resonance")

@warning_ignore("integer_division")
func _next_decree() -> int:
	var r := GameState.round_number + 1
	return r + (KingPowers.DECREE_EVERY - r % KingPowers.DECREE_EVERY) % KingPowers.DECREE_EVERY

# The Shadow King's forbidden knowledge.
func _shadow() -> void:
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm == null or gm.rules == null:
		return
	_cap("YOUR NEXT REROLL")
	var units := KingPowers.peek_shop(gm.rules)
	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("h_separation", 3)
	row.add_theme_constant_override("v_separation", 3)
	for d in units:
		var c := DockKit.chip(d.display_name, DockKit.ROW, DockKit.COST_COLORS.get(d.cost, HudStyle.INK), 10)
		row.add_child(c)
	body.add_child(row)
	_cap("THE COMING ENEMY")
	var foes := KingPowers.peek_enemy(gm)
	if foes.is_empty():
		_line("Unknown.", HudStyle.MUTED)
	else:
		var names := {}
		for f in foes:
			var key := "%s%s" % [f[0].display_name, " ★%d" % f[1] if int(f[1]) > 1 else ""]
			names[key] = int(names.get(key, 0)) + 1
		var parts := []
		for k in names:
			parts.append(k + (" x%d" % names[k] if names[k] > 1 else ""))
		_line(", ".join(parts), HudStyle.INK)
	_cap("DROPS")
	var next_drop := -1
	for r in gm.rules.drop_rounds:
		if int(r) > GameState.round_number:
			next_drop = int(r)
			break
	var stage: int = gm.rules.drop_stage(next_drop if next_drop > 0 else GameState.round_number)
	_line(("Next item: round %d (stage %d-%d)." % [next_drop, GameState.stage_for(next_drop), GameState.round_in_stage_for(next_drop)]) if next_drop > 0 else "No more item drops.", HudStyle.INK)
	_line("%d%% chance of a special item from stage 3 (now stage %d)." % [int(GameState.SPECIAL_DROP_CHANCE * 100), stage], HudStyle.MUTED)
	_cap("HIDDEN RULES")
	_line("A loss costs %d HP + 1 per enemy left standing." % GameState.stage_damage(GameState.stage()), HudStyle.MUTED)
	_line("Kings strike for %d every 10 s." % (CombatRunner.KING_DAMAGE + CombatRunner.KING_DAMAGE_PER_LEVEL * GameState.me.level), HudStyle.MUTED)
	var owned := {}
	for u in gm.board.all_player_units():
		if u.data != null and not u.summoned:
			owned[u.data] = true
	if not owned.is_empty():
		var left := []
		for d in owned:
			left.append("%s %d" % [d.display_name, gm.shared_pool.count(d)])
		left.sort()
		_line("Copies left in the pool: " + ", ".join(left.slice(0, 6)), HudStyle.MUTED)

# --- small pieces ------------------------------------------------------------------------------------

func _line(text: String, colour: Color) -> Label:
	var l := DockKit.wrapping(11, colour, WIDTH)
	l.text = text
	body.add_child(l)
	return l

func _cap(text: String) -> void:
	var l := HudStyle.caps(10, HudStyle.MUTED)
	l.text = text
	body.add_child(l)

func _stat(label: String, value: String, colour := HudStyle.INK) -> void:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := DockKit.text(12, HudStyle.MUTED)
	a.text = label
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := HudStyle.number(18, colour)
	b.text = value
	h.add_child(b)
	body.add_child(h)

func _odds(odds: Array) -> void:
	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	for i in odds.size():
		row.add_child(DockKit.chip("%d·%d%%" % [i + 1, roundi(float(odds[i]))], DockKit.ROW, DockKit.COST_COLORS[i + 1], 10))
	body.add_child(row)

func summary() -> String:   # (tests)
	var lines := [title.text, power.text]
	for c in body.get_children():
		if c is Label and not c.is_queued_for_deletion():
			lines.append(c.text)
	return "\n".join(lines)
