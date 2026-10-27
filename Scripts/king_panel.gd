# king_panel.gd
extends VBoxContainer

# The King tab of the left box (left_dock.gd): your king, its power, and how that power stands this run
# (KingPowers): the Merchant's interest, the Gambler's luck and odds, the Necromancer's souls and
# memories, the Explorer's quests and relics, the Chaos King's proclamation, the Dragon's hoard, the Fate
# King's prophecy (with the three to choose from), and the Shadow King's forbidden knowledge (the next
# reroll, the coming enemy, the drops, the hidden rules). Then the last few things it did.
# Rebuilt (once a frame at most) when the king's state, gold, the shop or the phase changes.

# Laid out like the unit inspector: a header (a crown in the king's colour, its name, YOUR KING), the
# POWER heading with its text (mechanic words hoverable), the run state as stat cells and rule rows under
# their own headings, and RECENTLY with the log.

const WIDTH := 210.0

var title: Label
var power_head: HBoxContainer
var power: RichTextLabel
var crown: DockKit.PixelIcon
var crown_well: PanelContainer
var kind_label: Label
var body: VBoxContainer
var log_box: VBoxContainer
var _grid: GridContainer   # the stat cells of this rebuild (two to a row)
var _dirty := false

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	crown_well = DockKit.well(Vector2(40, 40), HudStyle.GOLD, 3)
	head.add_child(crown_well)
	crown = DockKit.PixelIcon.new("crown", HudStyle.GOLD, 24)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	crown_well.add_child(crown)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(col)
	title = DockKit.text(16, HudStyle.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	kind_label = HudStyle.caps(10, HudStyle.YOU)
	col.add_child(kind_label)
	power_head = DockKit.heading("POWER", HudStyle.GOLD)
	add_child(power_head)
	power = DockKit.rich(12, HudStyle.INK, WIDTH)
	add_child(power)
	body = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 5)
	add_child(body)
	log_box = VBoxContainer.new()
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_theme_constant_override("separation", 3)
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
	var colour := KingSkins.colour(id)
	title.text = def.name
	title.add_theme_color_override("font_color", colour)
	crown.set_color(colour)
	(crown_well.get_theme_stylebox("panel") as StyleBoxFlat).border_color = colour
	kind_label.text = "YOUR KING  ·  " + ("RUN POWER" if KingSkins.is_run_power(id) else "EVERY FIGHT")
	(power_head.get_child(0) as Label).text = "POWER  ·  " + str(def.power).to_upper()
	DockKit.set_rich(power, str(def.text))
	for c in body.get_children():
		c.queue_free()
	for c in log_box.get_children():
		c.queue_free()
	_grid = null
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
	var log: Array = s.get("log", [])
	if not log.is_empty():
		log_box.add_child(DockKit.heading("RECENTLY"))
	for line in log:
		log_box.add_child(DockKit.rule_row(str(line), HudStyle.MUTED, "chev_right", HudStyle.MUTED, 11))

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

# A line of the run state: a spark and the text (mechanic words hoverable), in its colour.
func _line(text: String, colour: Color) -> Control:
	var row := DockKit.rule_row(text, colour, "spark", colour if colour != HudStyle.MUTED else DockKit.DIM_TEXT, 11)
	body.add_child(row)
	_grid = null
	return row

func _cap(text: String) -> void:
	body.add_child(DockKit.heading(text))
	_grid = null

# A stat cell (two to a row, like the inspector's), its icon from the label.
const STAT_ICONS := {"Interest": "hex", "Souls": "drop", "Hoard": "hex", "Prophecy": "spark", "Proclaimed": "crown", "This round": "bolt"}
func _stat(label: String, value: String, colour := HudStyle.INK) -> void:
	if _grid == null:
		_grid = GridContainer.new()
		_grid.columns = 2
		_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_theme_constant_override("h_separation", 4)
		_grid.add_theme_constant_override("v_separation", 4)
		body.add_child(_grid)
	var accent := colour if colour != HudStyle.INK else HudStyle.GOLD
	_grid.add_child(DockKit.stat_cell(STAT_ICONS.get(label, "spark"), accent, value, label.to_upper(), colour))

func _odds(odds: Array) -> void:
	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	for i in odds.size():
		row.add_child(DockKit.chip("%d·%d%%" % [i + 1, roundi(float(odds[i]))], DockKit.ROW, DockKit.COST_COLORS[i + 1], 10))
	body.add_child(row)

func summary() -> String:   # (tests)
	var lines := PackedStringArray([title.text, power.get_parsed_text()])
	lines.append_array(DockKit.texts_in(body))
	return "\n".join(lines)
