# drag_controller.gd
extends Node

@onready var board: Board = $"../Board"

var in_prep := true
var dragging: Unit = null
var origin_coord := Vector2i(-1, -1)
var origin_bench := -1
var dragging_item: ItemData = null   # item picked up from the item bar

func _ready():
	Events.phase_changed.connect(_on_phase_changed)
	Events.item_drag_started.connect(_on_item_drag_started)

func _on_phase_changed(p: int):
	in_prep = (p == Events.Phase.PREP)
	_cancel_drag()

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_sell_with_key()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pick()
		elif dragging_item != null:
			_drop_item()
		else:
			_drop()
	elif event is InputEventMouseMotion and dragging:
		var p := _ground_pos()
		dragging.global_position = Vector3(p.x, 0.3, p.z)

func _ray(mask: int, areas: bool, bodies: bool) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var m := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(m)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(m) * 200.0)
	q.collision_mask = mask
	q.collide_with_areas = areas
	q.collide_with_bodies = bodies
	return cam.get_world_3d().direct_space_state.intersect_ray(q)

func _ground_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var m := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(m), cam.project_ray_normal(m))
	return hit if hit else Vector3.ZERO

func _pick():
	if get_viewport().gui_get_hovered_control() != null:
		return
	var hit := _ray(2, true, false)   # layer 2 = units
	if hit.is_empty(): return
	var u := hit.collider.get_parent() as Unit
	if u == null or u.team != 0: return
	if not in_prep and u.coord.x >= 0:
		return
	dragging = u
	origin_coord = u.coord
	origin_bench = board.bench.find(u)

func _drop():
	if dragging == null: return
	var u := dragging
	dragging = null

	var ob := origin_bench
	var oc := origin_coord
	origin_bench = -1
	origin_coord = Vector2i(-1, -1)

	var ground := _ground_pos()
	if board.is_over_sell_zone(ground):
		board.sell_unit(u)
		return
	var bench_i := board.bench_slot_near(ground)
	var tile: Tile = null
	if bench_i == -1:
		tile = board.nearest_tile(ground)
		if not in_prep:
			tile = null
		elif tile != null and not board.is_player_side(tile.coord):
			tile = null   # your units only go on your half; the drop falls back to the origin spot
	board.detach(u)   # u's origin slot is now free

	if bench_i != -1:
		var other := board.bench[bench_i]
		if other:
			board.detach(other)
			_place_at_origin(other, ob, oc)
		board.put_on_bench(u, bench_i)
	elif tile:
		var other := tile.occupant
		if other == null and ob != -1 and board.units_on_board() >= GameState.max_board_units():
			_place_at_origin(u, ob, oc)
			Events.board_limit_hit.emit()
		else:
			if other:
				board.detach(other)
				_place_at_origin(other, ob, oc)
			board.put_on_tile(u, tile.coord)
	else:
		_place_at_origin(u, ob, oc)

	if in_prep:
		board.merge_all()

func _place_at_origin(u: Unit, ob: int, oc: Vector2i):
	if ob != -1:
		board.put_on_bench(u, ob)
	else:
		board.put_on_tile(u, oc)

func _on_item_drag_started(index: int):
	if index >= 0 and index < GameState.items.size():
		dragging_item = GameState.items[index]

func _end_item_drag():
	if dragging_item == null:
		return
	dragging_item = null
	Events.item_drag_ended.emit()

# Items go on units only, in any phase. A fighting unit gets the boost immediately.
# Released over the UI, an enemy, a full or dead unit, or empty ground: the item stays in the inventory.
func _drop_item():
	var item := dragging_item
	_end_item_drag()
	if get_viewport().gui_get_hovered_control() != null:
		return
	var hit := _ray(2, true, false)   # layer 2 = units
	if hit.is_empty():
		return
	equip_item_on(hit.collider.get_parent() as Unit, item)

func equip_item_on(u: Unit, item: ItemData) -> bool:
	var index := GameState.items.find(item)
	if index == -1 or u == null or u.team != 0:
		return false
	if not u.equip(item, not in_prep and u.coord.x >= 0):
		return false
	GameState.items.remove_at(index)
	Events.items_changed.emit()
	return true

func _sell_with_key():
	if dragging_item != null:
		return
	var u: Unit = dragging
	if u != null:
		# Selling mid-drag: forget the drag so the mouse release does nothing.
		dragging = null
		origin_bench = -1
		origin_coord = Vector2i(-1, -1)
	else:
		u = _unit_near_mouse()
	if u != null:
		board.sell_unit(u)

func _unit_near_mouse() -> Unit:
	var ground := _ground_pos()
	var best: Unit = null
	var best_d := 1.2
	for u in board.all_player_units():
		if not in_prep and u.coord.x >= 0:
			continue
		var d := Vector2(u.global_position.x - ground.x, u.global_position.z - ground.z).length()
		if d < best_d:
			best_d = d
			best = u
	return best

func _cancel_drag():
	_end_item_drag()
	if dragging == null:
		return
	var u := dragging
	dragging = null
	var ob := origin_bench
	var oc := origin_coord
	origin_bench = -1
	origin_coord = Vector2i(-1, -1)
	board.detach(u)
	if ob != -1 and board.bench[ob] == null:
		board.put_on_bench(u, ob)
	elif board.tiles.has(oc) and board.tiles[oc].occupant == null:
		board.put_on_tile(u, oc)
	else:
		var slot := board.first_free_bench()
		if slot != -1:
			board.put_on_bench(u, slot)
