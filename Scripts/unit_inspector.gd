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

	# Base stats at the current star, plus items (synergy bonuses are not shown).
	var lines: PackedStringArray = [
		"Health: %d%s" % [roundi((d.max_health + u.item_hp) * mult), _items_note(u.item_hp, "+%d" % roundi(u.item_hp * mult))],
		"Damage: %d%s" % [roundi((d.attack_damage + u.item_dmg) * mult), _items_note(u.item_dmg, "+%d" % roundi(u.item_dmg * mult))],
		"Attack speed: %.2f%s" % [d.attacks_per_second * (1.0 + u.item_as), _items_note(u.item_as, "+%d%%" % roundi(u.item_as * 100.0))],
		"Range: %d" % roundi(d.attack_range),
		"Mana: %d  (start %d)%s" % [roundi(d.max_mana), roundi(minf(d.start_mana + u.item_mana, d.max_mana)), _items_note(u.item_mana, "+%d" % roundi(u.item_mana))],
	]
	if u.item_dr > 0.0:
		lines.append("Damage reduction: %d%%  (items)" % roundi(u.item_dr * 100.0))
	if u.item_lifesteal > 0.0:
		lines.append("Lifesteal: %d%%  (items)" % roundi(u.item_lifesteal * 100.0))
	lines.append("Cost: %d g" % d.cost)
	stats_label.text = "\n".join(lines)

func _items_note(value: float, text: String) -> String:
	return "" if is_zero_approx(value) else "  (%s items)" % text
