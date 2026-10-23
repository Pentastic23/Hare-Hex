# unit_inspector.gd
extends HudPlate

# Unit Inspector (right-click a unit): styled like the side boxes. A HUD plate whose top edge is the
# team colour (blue ally, ember enemy), a portrait well with a cost-coloured edge, the name with gold
# stars, the team and traits, items and the stats (with items and synergies folded in).

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
	setup_plate(10, 12, 12, DockKit.PANEL_FILL)
	custom_minimum_size = Vector2(236, 0)
	_restyle()
	visible = false
	board = get_tree().get_first_node_in_group("board") as Board

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var u := _unit_under_mouse()
		if u != null:
			shown = u
			visible = true
			_fill()
		else:
			_close()

func _process(_delta):
	if shown == null:
		return
	if not is_instance_valid(shown) or shown.is_queued_for_deletion() or shown.dead:
		_close()
		return
	_fill()   # keeps it right if the unit merges up a star

func _close():
	shown = null
	visible = false

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
	var mult: float = u.stat_scale * Unit.STAR_MULT[u.star]

	name_label.text = d.display_name
	stars_label.text = "★".repeat(u.star)
	set_edge(HudStyle.YOU_EDGE if u.team == 0 else HudStyle.ENEMY_EDGE)
	if _portrait_of != d:
		_portrait_of = d
		for c in portrait_slot.get_children():
			c.queue_free()
		var p := DockKit.portrait_well(d, 48)
		(p.get_theme_stylebox("panel") as StyleBoxFlat).border_width_bottom = 3
		(p.get_theme_stylebox("panel") as StyleBoxFlat).border_color = DockKit.COST_COLORS.get(d.cost, HudStyle.MUTED)
		portrait_slot.add_child(p)
	team_label.text = ("ALLY" if u.team == 0 else "ENEMY") + "  ·  %d GOLD" % d.cost
	team_label.add_theme_color_override("font_color", HudStyle.YOU if u.team == 0 else HudStyle.ENEMY)

	var tags: PackedStringArray = []
	for t in d.tags:
		tags.append(String(t))
	tags_label.text = "  ·  ".join(tags)

	var item_names: PackedStringArray = []
	for item in u.items:
		item_names.append(item.display_name + (" (%d)" % u.stacks_of(item) if item.kind == &"bound" else ""))   # bound items show their stacks
	items_label.text = "Items: " + (", ".join(item_names) if not item_names.is_empty() else "none")
	var res: PackedStringArray = []
	for k in Resonance.keys_for(u.items):
		res.append(Resonance.def(k).get("name", k))
	if not res.is_empty():   # resonance (items v2)
		items_label.text += "\nResonance: " + ", ".join(res) + ("  (x2)" if Resonance.has_crystal(u.items) else "")
	items_label.add_theme_color_override("font_color", HudStyle.GOLD if not item_names.is_empty() else DockKit.DIM_TEXT)

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
	lines.append_array(_mechanic_lines(b))
	lines.append("Cost: %d g" % d.cost)
	stats_label.text = "\n".join(lines)

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
	portrait_slot.custom_minimum_size = Vector2(48, 48)
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
	_font_style(name_label, 16, HudStyle.INK)
	name_label.reparent(name_row)
	stars_label = DockKit.text(14, HudStyle.GOLD)
	name_row.add_child(stars_label)
	team_label = HudStyle.caps(10, HudStyle.YOU)
	col.add_child(team_label)
	_font_style(tags_label, 12, HudStyle.MUTED)
	tags_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var line := ColorRect.new()
	line.color = DockKit.LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	box.move_child(line, items_label.get_index())
	_font_style(items_label, 12, HudStyle.GOLD)
	_font_style(stats_label, 12, HudStyle.INK)
	stats_label.add_theme_constant_override("line_spacing", 2)

func _font_style(l: Label, size: int, color: Color):
	l.add_theme_font_override("font", HudStyle.label_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
