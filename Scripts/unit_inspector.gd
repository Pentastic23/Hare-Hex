# unit_inspector.gd
extends PanelContainer

@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var tags_label: Label = $VBoxContainer/TagsLabel
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

	stats_label.text = "\n".join([
		"Health: %d" % roundi(d.max_health * mult),
		"Damage: %d" % roundi(d.attack_damage * mult),
		"Attack speed: %.2f" % d.attacks_per_second,
		"Range: %d" % roundi(d.attack_range),
		"Mana: %d  (start %d)" % [roundi(d.max_mana), roundi(d.start_mana)],
		"Cost: %d g" % d.cost,
	])
