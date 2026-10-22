# unit_inspector.gd
extends PanelContainer

@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var tags_label: Label = $VBoxContainer/TagsLabel
@onready var items_label: Label = $VBoxContainer/ItemsLabel
@onready var stats_label: Label = $VBoxContainer/StatsLabel

var board: Board
var shown: Unit = null

func _ready():
	# keep the box on screen: grow left from the right edge, and both ways vertically
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_right = -24
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

	name_label.text = "%s  %s" % [d.display_name, "*".repeat(u.star)]
	name_label.modulate = Color(0.5, 0.9, 0.5) if u.team == 0 else Color(0.95, 0.45, 0.45)

	var tags: PackedStringArray = []
	for t in d.tags:
		tags.append(String(t))
	tags_label.text = "%s  |  %s" % ["Ally" if u.team == 0 else "Enemy", ", ".join(tags)]

	var item_names: PackedStringArray = []
	for item in u.items:
		item_names.append(item.display_name)
	items_label.text = "Items: " + (", ".join(item_names) if not item_names.is_empty() else "none")

	# Stats at the current star with items and synergy bonuses folded in (synergies aren't called out).
	var b := _synergy_bonuses(u)
	var hp_mult: float = mult * (1.0 + b.hp)
	var dmg_mult: float = mult * (1.0 + b.dmg)
	var lines: PackedStringArray = [
		"Health: %d%s" % [roundi((d.max_health + u.item_hp) * hp_mult), _items_note(u.item_hp, "+%d" % roundi(u.item_hp * hp_mult))],
		"Damage: %d%s" % [roundi((d.attack_damage + u.item_dmg) * dmg_mult), _items_note(u.item_dmg, "+%d" % roundi(u.item_dmg * dmg_mult))],
		"Attack speed: %.2f%s" % [d.attacks_per_second * (1.0 + u.item_as + b["as"]), _items_note(u.item_as, "+%d%%" % roundi(u.item_as * 100.0))],
		"Range: %d" % roundi(d.attack_range),
		"Mana: %d  (start %d)%s" % [roundi(d.max_mana), roundi(minf(d.start_mana + b.mana + u.item_mana, d.max_mana)), _items_note(u.item_mana, "+%d" % roundi(u.item_mana))],
	]
	var reduction := minf(b.dr + u.item_dr, 0.6)   # same 60% cap as take_damage()
	if reduction > 0.0:
		lines.append("Damage reduction: %d%%" % roundi(reduction * 100.0))
	var steal: float = b.lifesteal + u.item_lifesteal
	if steal > 0.0:
		lines.append("Lifesteal: %d%%" % roundi(steal * 100.0))
	lines.append("Cost: %d g" % d.cost)
	stats_label.text = "\n".join(lines)

func _items_note(value: float, text: String) -> String:
	return "" if is_zero_approx(value) else "  (%s items)" % text

# Synergy bonuses for a unit: the real ones during a fight, otherwise what its team on the board
# would get if the fight started now (benched units get none).
func _synergy_bonuses(u: Unit) -> Dictionary:
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.fighting:
		return {"hp": u.bonus_hp, "dmg": u.bonus_dmg, "as": u.bonus_as, "mana": u.bonus_mana, "dr": u.dmg_reduction, "lifesteal": u.lifesteal}
	if u.team != 0 or u.coord.x < 0 or board == null:
		return Synergies.preview(null, [])
	var team: Array = board.all_player_units().filter(func(x): return x.coord.x >= 0)
	return Synergies.preview(u, team)
