# unit_inspector.gd
extends HudPlate

# Unit Inspector (right-click a unit): styled like the side boxes. A solid HUD plate whose top edge is the
# team colour (blue ally, ember enemy), a portrait well with a cost-coloured edge, the name with gold
# stars, the team, the traits as chips; then STATS as a grid of cells, each a pixel icon in the stat's
# colour, the value in the pixel font (what items add in gold beside it) and a caption (with items and
# synergies folded in), and the special rules (shields, crits...) as icon rows; the ability; the items.
# StatsLabel keeps the same stats as plain text (hidden; the checks read it).

@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var tags_label: Label = $VBoxContainer/TagsLabel
@onready var items_label: Label = $VBoxContainer/ItemsLabel
@onready var stats_label: Label = $VBoxContainer/StatsLabel

var board: Board
var shown: Unit = null
var stars_label: Label
var team_label: Label
var portrait_slot: Control
var _portrait_of: UnitData
var item_row: HBoxContainer        # one hoverable chip per item (icon; tooltip with what it does)
var res_row: HFlowContainer        # one hoverable chip per resonance
var ability_head: Label            # "ABILITY · SHEPHERD'S LIGHT"
var ability_text: RichTextLabel    # what it does at the unit's star (abilities.gd); hover a mechanic word for what it means (Glossary)
var _items_sig := ""
var trait_row: HFlowContainer      # the traits as chips
var stat_grid: GridContainer       # one cell per stat (STAT_ROWS)
var cells := {}                    # stat key -> {"box", "value", "bonus", "caption"}
var rules_box: VBoxContainer       # special rules from synergies and items, one icon row each
var _rules_sig := ""

# The stat cells: key, pixel icon, colour, caption.
const STAT_ROWS := [
	["hp", "heart", Color("6fd86a"), "HEALTH"],
	["dmg", "sword", Color("ff8a4c"), "DAMAGE"],
	["as", "bolt", Color("f2c14e"), "ATTACK SPD"],
	["range", "target", Color("c58cff"), "RANGE"],
	["mana", "drop", Color("5aa8ff"), "MANA"],
	["dr", "shield", Color("b8c0dc"), "REDUCTION"],
	["vamp", "fang", Color("ff6b8a"), "OMNIVAMP"],
]
const PLATE_FILL := Color(0.098, 0.110, 0.161, 0.98)   # nearly solid: the board doesn't show through the text
const CELL_FILL := Color("141722")

func _ready():
	# Bottom right, just above the shop bar, growing up and left, so it stays clear of the HP standings
	# at the top right (the old HP label's spot).
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -24
	offset_left = -24
	offset_bottom = -96
	offset_top = -96
	setup_plate(10, 12, 12, PLATE_FILL)
	custom_minimum_size = Vector2(264, 0)
	_restyle()
	visible = false
	board = get_tree().get_first_node_in_group("board") as Board

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var u := _unit_under_mouse()
		if u != null:
			show_unit(u)
		else:
			_close()

# Opens on unit u, drawn (and hovered) over every other panel of the HUD.
func show_unit(u: Unit) -> void:
	shown = u
	visible = true
	get_parent().move_child(self, -1)
	_fill()

func _process(_delta):
	if shown == null:
		return
	if not is_instance_valid(shown) or shown.is_queued_for_deletion() or shown.dead:
		_close()
		return
	_fill()   # keeps it right if the unit merges up a star
	_yield_standings()

func _close():
	shown = null
	_items_sig = ""
	visible = false
	_yield_standings()

# A tall inspector (an ability, three items and their resonances) can reach up into the HP standings;
# they fade out while it covers them and come back when it closes or shrinks. (The right box decides
# whether they are shown at all; this only touches their transparency.)
func _yield_standings() -> void:
	var standings := get_parent().get_node_or_null("Standings") as Control
	if standings == null:
		return
	var covered := visible and get_global_rect().intersects(standings.get_global_rect())
	standings.modulate.a = 0.0 if covered else 1.0

func _unit_under_mouse() -> Unit:
	if board == null:
		return null
	var cam := get_viewport().get_camera_3d()
	var m := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(m), cam.project_ray_normal(m))
	if hit == null:
		return null
	var p: Vector3 = hit
	var best: Unit = null
	var best_d := 1.2
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u == null or u.data == null or u.dead or not u.visible or u.is_queued_for_deletion():
			continue
		var d := Vector2(u.global_position.x - p.x, u.global_position.z - p.z).length()
		if d < best_d:
			best_d = d
			best = u
	return best

func _fill():
	var u := shown
	var d := u.data
	var mult: float = u.stat_scale * Unit.star_mult(u.star, d.cost)

	name_label.text = d.display_name
	stars_label.text = "★".repeat(u.star)
	set_edge(HudStyle.YOU_EDGE if u.team == 0 else HudStyle.ENEMY_EDGE)
	if _portrait_of != d:
		_portrait_of = d
		for c in portrait_slot.get_children():
			c.queue_free()
		var p := DockKit.portrait_well(d, 52)
		(p.get_theme_stylebox("panel") as StyleBoxFlat).border_width_bottom = 3
		(p.get_theme_stylebox("panel") as StyleBoxFlat).border_color = DockKit.COST_COLORS.get(d.cost, HudStyle.MUTED)
		portrait_slot.add_child(p)
		for c in trait_row.get_children():
			c.queue_free()
		for t in d.tags:   # origin first, then classes, as the unit lists them
			var kind: String = Synergies.DEFS.get(String(t), {}).get("kind", "")
			trait_row.add_child(DockKit.chip(String(t), DockKit.ROW, HudStyle.GOLD if kind == "unique" else HudStyle.INK, 11, DockKit.LINE))
	team_label.text = ("ALLY" if u.team == 0 else "ENEMY") + ("  ·  SUMMONED" if u.summoned else "  ·  %d GOLD" % d.cost)
	team_label.add_theme_color_override("font_color", HudStyle.YOU if u.team == 0 else HudStyle.ENEMY)

	var tags: PackedStringArray = []
	for t in d.tags:
		tags.append(String(t))
	tags_label.text = "  ·  ".join(tags)
	var has_ability := Abilities.has(d)
	ability_head.visible = has_ability
	ability_text.visible = has_ability
	if has_ability:
		ability_head.text = "ABILITY  ·  " + Abilities.name_of(d).to_upper()
		var said := Glossary.bbcode(Abilities.text(d, u.star))
		if ability_text.text != said:   # (set only on a change: setting it ends a hover)
			ability_text.text = said

	# Items and resonances as chips you can hover (rebuilt only when they change).
	var sig := str(u.items.map(func(i): return i.id)) + str(u.item_stacks)
	if sig != _items_sig:
		_items_sig = sig
		_fill_item_chips(u)
	items_label.text = "ITEMS" if not u.items.is_empty() else "Items: none"
	items_label.add_theme_color_override("font_color", HudStyle.MUTED if not u.items.is_empty() else DockKit.DIM_TEXT)

	# Stats at the current star with items and synergy bonuses folded in (synergies aren't called out).
	var b := _synergy_bonuses(u)
	var hp_mult: float = mult * (1.0 + b.get("hp", 0.0))
	var dmg_mult: float = mult * (1.0 + b.get("dmg", 0.0))
	var lines: PackedStringArray = [
		"Health: %d%s" % [roundi((d.max_health + u.item_hp) * hp_mult), _items_note(u.item_hp, "+%d" % roundi(u.item_hp * hp_mult))],
		"Damage: %d%s" % [roundi((d.attack_damage + u.item_dmg) * dmg_mult), _items_note(u.item_dmg, "+%d" % roundi(u.item_dmg * dmg_mult))],
		"Attack speed: %.2f%s" % [d.attacks_per_second * (1.0 + u.item_as + b.get("as", 0.0)), _items_note(u.item_as, "+%d%%" % roundi(u.item_as * 100.0))],
		"Range: %d" % (roundi(d.attack_range) + int(b.get("range", 0))),
		"Mana: %d  (start %d)%s" % [roundi(d.max_mana), roundi(minf(d.start_mana + u.item_mana, d.max_mana)), _items_note(u.item_mana, "+%d" % roundi(u.item_mana))],
	]
	var reduction := minf(b.get("dr", 0.0) + u.item_dr, 0.6)   # same 60% cap as take_damage()
	if reduction > 0.0:
		lines.append("Damage reduction: %d%%" % roundi(reduction * 100.0))
	var steal: float = b.get("vamp", 0.0) + u.item_lifesteal
	if steal > 0.0:
		lines.append("Omnivamp: %d%%" % roundi(steal * 100.0))
	var rules := _mechanic_lines(b)
	if u.charm_left > 0.0:
		rules.append("Charmed: fighting for the other side (%.1f s)" % u.charm_left)
	lines.append_array(rules)
	stats_label.text = "\n".join(lines)
	_cell("hp", str(roundi((d.max_health + u.item_hp) * hp_mult)), _bonus(u.item_hp, "+%d" % roundi(u.item_hp * hp_mult)))
	_cell("dmg", str(roundi((d.attack_damage + u.item_dmg) * dmg_mult)), _bonus(u.item_dmg, "+%d" % roundi(u.item_dmg * dmg_mult)))
	_cell("as", "%.2f" % (d.attacks_per_second * (1.0 + u.item_as + b.get("as", 0.0))), _bonus(u.item_as, "+%d%%" % roundi(u.item_as * 100.0)))
	_cell("range", str(roundi(d.attack_range) + int(b.get("range", 0))), "")
	_cell("mana", str(roundi(d.max_mana)), _bonus(u.item_mana, "+%d" % roundi(u.item_mana)), "MANA · START %d" % roundi(minf(d.start_mana + u.item_mana, d.max_mana)))
	_cell("dr", "%d%%" % roundi(reduction * 100.0), "", "", reduction > 0.0)
	_cell("vamp", "%d%%" % roundi(steal * 100.0), "", "", steal > 0.0)
	var rules_sig := "|".join(rules)
	if rules_sig != _rules_sig:
		_rules_sig = rules_sig
		for c in rules_box.get_children():
			c.queue_free()
		for r in rules:
			rules_box.add_child(_rule_row(r))
		rules_box.visible = not rules.is_empty()

# Updates one stat cell: its value, what items add (gold, beside it), an optional caption, shown or not.
func _cell(key: String, value: String, bonus: String, caption := "", on := true) -> void:
	var c: Dictionary = cells[key]
	c.box.visible = on
	c.value.text = value
	c.bonus.text = bonus
	c.bonus.visible = bonus != ""
	if caption != "":
		c.caption.text = caption

func _bonus(value: float, text: String) -> String:
	return "" if is_zero_approx(value) else text

# A stat cell: the icon in the stat's colour, the value and items' part, the caption under them.
func _make_cell(row: Array) -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # for the tooltip
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := DockKit.flat(CELL_FILL, 3, Vector4(4, 7, 4, 6))
	st.border_width_left = 2
	st.border_color = (row[2] as Color).darkened(0.35)
	box.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 7)
	box.add_child(h)
	h.add_child(DockKit.PixelIcon.new(row[1], row[2], 16))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", -3)
	h.add_child(col)
	var vals := HBoxContainer.new()
	vals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vals.add_theme_constant_override("separation", 4)
	col.add_child(vals)
	var value := HudStyle.number(21, HudStyle.INK)
	vals.add_child(value)
	var bonus := HudStyle.number(15, HudStyle.GOLD)
	bonus.size_flags_vertical = Control.SIZE_SHRINK_END
	bonus.tooltip_text = ""
	vals.add_child(bonus)
	var caption := HudStyle.caps(9, HudStyle.MUTED)
	caption.text = row[3]
	col.add_child(caption)
	box.tooltip_text = Tip.wrap({"hp": "Health, with items and synergies. Gold: what items add.", "dmg": "Damage per attack, with items and synergies. Gold: what items add.", "as": "Attacks per second. Gold: what items add.", "range": "How many hexes away it can attack from.", "mana": "Mana to cast its ability, and how much it starts a fight with. It gains 10 per attack and some when hit.", "dr": "Less damage taken (60% at most).", "vamp": "Heals for this share of the damage it deals."}[row[0]])
	cells[row[0]] = {"box": box, "value": value, "bonus": bonus, "caption": caption}
	return box

# One special rule (a shield, crits, burns...): a small spark and the text.
func _rule_row(text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var icon := DockKit.PixelIcon.new("spark", HudStyle.GOLD, 10)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(icon)
	var l := _rich(12)
	l.text = Glossary.bbcode(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 200
	h.add_child(l)
	return h

# Text in the HUD's label font whose mechanic words (burn, stun, shield...) are gold links: hovering one
# shows what it means (Glossary.hook).
func _rich(size: int) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("normal_font", HudStyle.label_font())
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_color_override("default_color", Settings.text_color(HudStyle.INK))
	l.add_theme_constant_override("line_separation", 1)
	Glossary.hook(l)
	return l

# A section heading: small caps and a line running to the right edge.
func _heading(text: String, colour := HudStyle.MUTED) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var l := HudStyle.caps(10, colour)
	l.text = text
	h.add_child(l)
	var line := ColorRect.new()
	line.color = DockKit.LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	return h

func _items_note(value: float, text: String) -> String:
	return "" if is_zero_approx(value) else "  (%s items)" % text

# Synergy bonuses for a unit: the real ones during a fight, otherwise what its team on the board
# would get if the fight started now (benched units get none).
func _synergy_bonuses(u: Unit) -> Dictionary:
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.fighting:
		return {"hp": u.bonus_hp, "dmg": u.bonus_dmg, "as": u.bonus_as, "dr": u.dmg_reduction, "vamp": u.lifesteal, "shield": u.shield_pct, "regen": u.regen, "ramp": u.ramp, "ramp_max": u.ramp_max, "crit": u.crit_every, "execute": u.execute, "revive": u.revive, "burn": u.burn, "chill": u.chill, "dodge": u.dodge_every, "curse": u.curse, "range": u.range_bonus, "kill_heal": u.kill_heal}
	if u.team != 0 or u.coord.x < 0 or board == null:
		return Synergies.preview(null, [])
	var team: Array = board.all_player_units().filter(func(x): return x.coord.x >= 0)
	return Synergies.preview(u, team)

# One line per synergy mechanic the unit has (shields, crits, revives...), in the inspector's words.
func _mechanic_lines(b: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var pct := func(k: String) -> int: return roundi(float(b.get(k, 0.0)) * 100.0)
	if b.get("shield", 0.0) > 0.0:
		out.append("Shield: %d%% of max HP" % pct.call("shield"))
	if b.get("regen", 0.0) > 0.0:
		out.append("Regen: %s%% of max HP per second" % str(snappedf(float(b.regen) * 100.0, 0.1)))
	if b.get("ramp", 0.0) > 0.0:
		out.append("Attack speed +%d%% per attack (max %d)" % [pct.call("ramp"), int(b.get("ramp_max", 0))])
	if int(b.get("crit", 0)) > 0:
		out.append("Every %s attack crits" % _nth(int(b.crit)))
	if b.get("execute", 0.0) > 0.0:
		out.append("Executes below %d%%" % pct.call("execute"))
	if b.get("revive", 0.0) > 0.0:
		out.append("Revives once at %d%% HP" % pct.call("revive"))
	if b.get("burn", 0.0) > 0.0:
		out.append("Attacks burn %d%% of max HP per second" % pct.call("burn"))
	if b.get("chill", 0.0) > 0.0:
		out.append("Attacks chill %d%%" % pct.call("chill"))
	if b.get("curse", 0.0) > 0.0:
		out.append("Attacks curse +%d%% damage taken" % pct.call("curse"))
	if int(b.get("dodge", 0)) > 0:
		out.append("Dodges every %s attack" % _nth(int(b.dodge)))
	if b.get("kill_heal", 0.0) > 0.0:
		out.append("Heals %d%% of max HP on a kill" % pct.call("kill_heal"))
	return out

func _nth(n: int) -> String:
	return {2: "2nd", 3: "3rd"}.get(n, "%dth" % n)

# Builds the header (portrait, name and stars, team) around the scene's labels and gives every label
# the HUD fonts and colours. The scene's NameLabel / TagsLabel / ItemsLabel / StatsLabel are kept
# (tests and _fill use them), just moved into the new layout.
func _restyle():
	var box: VBoxContainer = $VBoxContainer
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	box.move_child(head, 0)
	portrait_slot = Control.new()
	portrait_slot.custom_minimum_size = Vector2(52, 52)
	portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(portrait_slot)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	_font_style(name_label, 17, HudStyle.INK)
	name_label.reparent(name_row)
	stars_label = DockKit.text(14, HudStyle.GOLD)
	name_row.add_child(stars_label)
	team_label = HudStyle.caps(10, HudStyle.YOU)
	col.add_child(team_label)
	_font_style(tags_label, 12, HudStyle.MUTED)
	tags_label.visible = false   # (kept for its text; the traits show as chips)
	trait_row = HFlowContainer.new()
	trait_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trait_row.add_theme_constant_override("h_separation", 4)
	trait_row.add_theme_constant_override("v_separation", 4)
	box.add_child(trait_row)
	box.move_child(trait_row, tags_label.get_index() + 1)
	# STATS: the grid of cells and the special rules, right under the header.
	var stats_head := _heading("STATS")
	box.add_child(stats_head)
	box.move_child(stats_head, trait_row.get_index() + 1)
	stat_grid = GridContainer.new()
	stat_grid.columns = 2
	stat_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_grid.add_theme_constant_override("h_separation", 4)
	stat_grid.add_theme_constant_override("v_separation", 4)
	for row in STAT_ROWS:
		stat_grid.add_child(_make_cell(row))
	box.add_child(stat_grid)
	box.move_child(stat_grid, stats_head.get_index() + 1)
	rules_box = VBoxContainer.new()
	rules_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rules_box.add_theme_constant_override("separation", 3)
	box.add_child(rules_box)
	box.move_child(rules_box, stat_grid.get_index() + 1)
	var line := Control.new()   # (where the ability and items go: before ItemsLabel)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	box.move_child(line, items_label.get_index())
	ability_head = HudStyle.caps(10, HudStyle.GOLD)
	box.add_child(ability_head)
	box.move_child(ability_head, line.get_index())
	ability_text = _rich(13)
	box.add_child(ability_text)
	box.move_child(ability_text, line.get_index())
	_font_style(items_label, 12, HudStyle.GOLD)
	item_row = HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 6)
	item_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(item_row)
	box.move_child(item_row, items_label.get_index() + 1)
	res_row = HFlowContainer.new()
	res_row.add_theme_constant_override("h_separation", 4)
	res_row.add_theme_constant_override("v_separation", 4)
	res_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(res_row)
	box.move_child(res_row, item_row.get_index() + 1)
	_font_style(stats_label, 12, HudStyle.INK)
	stats_label.visible = false   # the same stats as text (the checks read it); the grid shows them

func _font_style(l: Label, size: int, color: Color):
	l.add_theme_font_override("font", HudStyle.label_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

# One chip per item (its icon, the bound stacks on it) and one per resonance, each with a tooltip.
func _fill_item_chips(u: Unit) -> void:
	for row in [item_row, res_row]:
		for c in row.get_children():
			row.remove_child(c)
			c.queue_free()
	for it in u.items:
		var chip := DockKit.well(Vector2(34, 34), it.color, 3)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP   # for the tooltip
		chip.tooltip_text = Tip.wrap(Glossary.explain(item_tip(it, u.stacks_of(it))))
		var tex := DockKit.item_icon(it)
		if tex != null:
			var r := TextureRect.new()
			r.texture = tex
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(r)
		if it.kind == &"bound":
			var s := HudStyle.number(14, HudStyle.GOLD)
			s.text = str(u.stacks_of(it))
			s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			s.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			chip.add_child(s)
		item_row.add_child(chip)
	var doubled := Resonance.has_crystal(u.items)
	for k in Resonance.keys_for(u.items):
		var c := DockKit.chip(str(Resonance.def(k).get("name", k)) + ("  x2" if doubled else ""), DockKit.CHIP_ACTIVE, HudStyle.GOLD, 11)
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.tooltip_text = Tip.wrap(Glossary.explain(resonance_tip(k, doubled)))
		res_row.add_child(c)
	res_row.visible = res_row.get_child_count() > 0

# An item's tooltip in the inspector: name and element, what it does, and what its stacks add now.
func item_tip(it: ItemData, stacks: int) -> String:
	var lines: PackedStringArray = [it.display_name + ("  (%s)" % String(it.element) if it.element != &"" else ""), it.description]
	if it.kind == &"bound":
		var now: PackedStringArray = []
		if it.stack_dmg > 0.0:
			now.append("+%d damage" % roundi(it.dmg + it.stack_dmg * stacks))
		if it.stack_hp > 0.0:
			now.append("+%d HP" % roundi(it.hp + it.stack_hp * stacks))
		lines.append("%d / %d stacks: %s now" % [stacks, it.max_stacks, ", ".join(now)])
	if it.best_on() != "":
		lines.append("Best on " + it.best_on() + ".")
	return "\n".join(lines)

# A resonance's tooltip: its name, the two elements, what it does (doubled by a Crystal).
func resonance_tip(k: String, doubled: bool) -> String:
	var d := Resonance.def(k)
	var elems := "three different elements" if k == "Prism" else k.replace("+", " + ")
	var lines: PackedStringArray = ["%s  (%s)" % [d.get("name", k), elems], str(d.get("text", ""))]
	if doubled:
		lines.append("Twice as strong: Resonance Crystal.")
	return "\n".join(lines)
