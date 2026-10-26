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
	if Keybinds.pressed(event, "sell_unit") and not BugReporter.typing():   # F by default (main menu > Keybinds); not while typing a bug report
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
	if get_viewport().gui_get_hovered_control() != null or _scouting():
		return
	var hit := _ray(2, true, false)   # layer 2 = units
	if hit.is_empty(): return
	var u := hit.collider.get_parent() as Unit
	if u == null or u.team != 0 or u.get_parent() != board.get_node("Units"): return   # not a scouted player's unit
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
			_rules().sell(u)   # refused in the PvP opening
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

# A shop card dragged onto the board (ShopSlot) was just bought onto the bench: in prep it moves on to the
# tile under the pointer (single player; in a lobby it stays on the bench). `before`: the bench units
# before the purchase, to tell the new one apart.
func place_bought(d: UnitData, before: Array) -> void:
	if not in_prep or get_node("../Game Manager").lobby != null:
		return
	var fresh: Unit = null
	for u in board.bench:
		if u != null and u.data == d and not before.has(u):
			fresh = u
	var tile: Tile = board.nearest_tile(_ground_pos())
	if fresh == null or tile == null:
		return
	if _rules().move(fresh, -1, tile.coord, true) == "limit":
		Events.board_limit_hit.emit()

func _on_item_drag_started(index: int):
	if index >= 0 and index < GameState.me.items.size():
		dragging_item = GameState.me.items[index]
		Sfx.play(&"pickup")

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
	if get_viewport().gui_get_hovered_control() != null or _scouting():
		return
	var target := unit_for_item(get_viewport().get_mouse_position())
	if target == null:
		var hit := _ray(2, true, false)   # layer 2 = units
		if hit.is_empty():
			return
		target = hit.collider.get_parent() as Unit
	equip_item_on(target, item)

# The unit of yours an item let go at screen point `at` is meant for: the one whose body (its middle, on
# screen) is nearest the pointer, within ITEM_PICK_PX. The first collision box along the camera ray is
# often the unit standing in front of the one you aimed at, when two stand next to each other.
const ITEM_PICK_PX := 48.0
func unit_for_item(at: Vector2) -> Unit:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var best: Unit = null
	var best_d := ITEM_PICK_PX
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u == null or not u.visible or u.dead or not u.mine() or u.summoned or u.data == null:
			continue
		var mid := u.global_position + Vector3(0, minf(u.bar_height, 2.4) * 0.45, 0)
		if cam.is_position_behind(mid):
			continue
		var d := cam.unproject_position(mid).distance_to(at)
		if d < best_d:
			best_d = d
			best = u
	return best

func equip_item_on(u: Unit, item: ItemData) -> bool:
	var had: Array = u.items.duplicate() if u != null else []
	var lobby: LobbyGame = get_node("../Game Manager").lobby
	var ok: bool
	if lobby != null:
		ok = lobby.equip(u, item)   # sent to the server: sound and look now, the server has the say
	else:
		ok = u != null and _rules().equip(u, item, in_prep, not in_prep and u.coord.x >= 0)
	if not ok:
		if u != null:
			Sfx.play(&"error")   # a full unit, a second bound item, Tongs mid-fight...
		return false
	item_landed(u, item, had)
	return true

# The sound and look of an item going onto a unit (or Tinker's Tongs taking them off). `had` is what
# the unit carried before; an item that wakes a new resonance gets the resonance chime.
static func item_landed(u: Unit, item: ItemData, had: Array) -> void:
	if item.kind == &"remover":
		Sfx.play(&"tongs")
		Vfx.burst(u, Vfx._chest(u), Color("c8ccd8"), 8, 0.8)
		return
	var woke := Resonance.would_add(item, had).size()
	Sfx.play(&"resonance" if woke > 0 else &"equip")
	Vfx.equip(u, item.color, woke)

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
		_rules().sell(u)

# A lobby showing another player's board (LobbyGame.scout): your own units are hidden, so nothing of
# yours can be dragged or sold until you look at your board again.
func _scouting() -> bool:
	var lobby: LobbyGame = get_node("../Game Manager").lobby
	return lobby != null and lobby.scouting >= 0

func _unit_near_mouse() -> Unit:
	if _scouting():
		return null
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
