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
	if Keybinds.pressed(event, "sell_unit"):   # F by default (main menu > Keybinds)
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
	Sfx.play(&"pickup")

func _drop():
	if dragging == null: return
	var u := dragging
	dragging = null
	origin_bench = -1
	origin_coord = Vector2i(-1, -1)   # PlayerRules.move reads the origin from the board (the drag only moved the model)

	var ground := _ground_pos()
	var lobby: LobbyGame = get_node("../Game Manager").lobby
	if board.is_over_sell_zone(ground):
		if lobby != null:
			lobby.sell(u)
		else:
			board.sell_unit(u)
		return
	var bench_i := board.bench_slot_near(ground)
	var tile: Tile = board.nearest_tile(ground) if bench_i == -1 else null
	if lobby != null:   # a lobby: ask the server; the unit goes back until it answers
		lobby.move(u, bench_i, tile.coord if tile != null else Vector2i(-1, -1))
		Sfx.play(&"place")
		return
	var result := _rules().move(u, bench_i, tile.coord if tile != null else Vector2i(-1, -1), in_prep)
	if result == "limit":
		Events.board_limit_hit.emit()
	Sfx.play(&"place")

func _rules() -> PlayerRules:
	return get_node("../Game Manager").rules

func _on_item_drag_started(index: int):
	if index >= 0 and index < GameState.me.items.size():
		dragging_item = GameState.me.items[index]

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
	var lobby: LobbyGame = get_node("../Game Manager").lobby
	if lobby != null:
		return lobby.equip(u, item)
	if u == null or not _rules().equip(u, item, in_prep, not in_prep and u.coord.x >= 0):
		return false
	if item.kind != &"remover":
		Sfx.play(&"equip")
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
	if u == null:
		return
	var lobby: LobbyGame = get_node("../Game Manager").lobby
	if lobby != null:
		var slot := board.bench.find(u)
		u.position = board.bench_local(slot) if slot != -1 else board.grid_to_world(u.coord)   # back in place until the server answers
		lobby.sell(u)
	else:
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

# Tinker's Tongs (items v2): PlayerRules.use_tongs.
func use_tongs_on(u: Unit, tongs: ItemData) -> bool:
	return _rules().use_tongs(u, tongs, in_prep)
