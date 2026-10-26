# touch_checks.gd
# Dev tool, not part of the game: plays a free-play run with simulated touches (InputEventScreenTouch /
# ScreenDrag, as a phone sends them) and checks buying, dragging units and items, inspecting, long-press
# tooltips, pinch zoom, two-finger pan and the back button. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/touch_checks.tscn
# Prints PASS/FAIL per check and RESULT at the end. Uses a throwaway save and settings file.

extends Node

var fails := 0
var main: Node
var gm
var board: Board
var cam: Camera3D

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func frames(n := 2):
	for i in n:
		await get_tree().process_frame

# Touches arrive in window coordinates; the game works in its 1152 x 648 viewport (stretched).
func win(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p

func touch(i: int, at: Vector2, down: bool):
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = win(at)
	e.pressed = down
	Input.parse_input_event(e)
	await frames()

func move(i: int, from: Vector2, to: Vector2, steps := 6):
	for s in range(1, steps + 1):
		var e := InputEventScreenDrag.new()
		e.index = i
		var p := from.lerp(to, float(s) / steps)
		e.relative = win(to - from) / steps
		e.position = win(p)
		Input.parse_input_event(e)
		await frames(1)
	await frames()

func tap(at: Vector2):
	await touch(0, at, true)
	await touch(0, at, false)

func hold(at: Vector2, seconds := 0.6):
	await touch(0, at, true)
	await get_tree().create_timer(seconds).timeout

func screen_of(u: Node3D) -> Vector2:
	return cam.unproject_position(u.global_position + Vector3(0, 0.4, 0))

func screen_of_point(p: Vector3) -> Vector2:
	return cam.unproject_position(p)

func centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func _ready():
	_run.call_deferred()

func _run():
	SaveGame.path = "user://touch_test_save.json"
	SaveGame.reset_progress()
	SaveGame.set_team_plan([])
	Settings.path = "user://touch_test_settings.cfg"
	Settings._loaded = true
	Settings.show_damage_meter = true
	Settings.dock_collapsed = false
	Settings.dock_tab = "synergies"
	GameState.run_level = null
	GameState.run_carry = {}
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	cam = get_viewport().get_camera_3d()
	await get_tree().create_timer(0.4).timeout
	var tc = get_node("/root/TouchControls")
	chk("the TouchControls autoload is running", tc != null)
	var shop = main.get_node("UI/ShopPanel")
	var insp = main.get_node("UI/UnitInspector")
	var rig = main.get_node("CameraRig")
	var dc = main.get_node("DragController")
	GameState.me.gold = 60
	GameState.me.level = 4
	board.refresh_unlocks(4, false)
	Events.gold_changed.emit(60)

	print("--- buying and placing")
	var slot = shop.slots.filter(func(s): return s.offer != null)[0]
	var name: String = slot.offer.display_name
	var on_bench_before := board.bench.filter(func(u): return u != null).size()
	await tap(centre(slot))
	var bought := board.bench.filter(func(u): return u != null)
	chk("tapping a shop card buys the unit", bought.size() == on_bench_before + 1 and slot.offer == null and bought.any(func(u): return u.data.display_name == name), name)
	var u: Unit = bought.filter(func(x): return x.data.display_name == name)[0]
	var target: Vector2i = board.player_order[0]
	var from := screen_of(u)
	var to := screen_of_point(board.grid_to_world(target))
	await touch(0, from, true)
	await move(0, from, to, 8)
	await touch(0, to, false)
	chk("dragging it with a finger puts it on the board (right after tapping the shop)", u.coord == target, "coord %s, wanted %s" % [u.coord, target])

	print("--- inspecting")
	await tap(screen_of(u))
	await frames()
	chk("tapping a unit opens the inspector on it", insp.visible and insp.shown == u)
	var empty_tile: Vector2i = board.player_order[3]
	await tap(screen_of_point(board.grid_to_world(empty_tile)))
	chk("tapping empty ground closes it", not insp.visible)
	await hold(screen_of(u))
	await touch(0, screen_of(u), false)
	chk("a long press on a unit inspects it too", insp.visible and insp.shown == u)
	chk("and leaves it where it was", u.coord == target)
	await tap(screen_of_point(board.grid_to_world(empty_tile)))

	print("--- long-press tooltips")
	var slot2 = shop.slots.filter(func(s): return s.offer != null)[0]
	var name2: String = slot2.offer.display_name
	var gold0 := GameState.me.gold
	await hold(centre(slot2))
	chk("a long press on a shop card shows its tooltip", tc.tooltip_visible() and tc.tooltip_text().begins_with(name2), tc.tooltip_text().replace("\n", " | "))
	await touch(0, centre(slot2), false)
	chk("lifting the finger keeps it up (tooltips toggle) and buys nothing", tc.tooltip_visible() and slot2.offer != null and GameState.me.gold == gold0)
	await tap(centre(slot2))
	chk("the next tap only closes it: nothing bought", not tc.tooltip_visible() and slot2.offer != null and GameState.me.gold == gold0, "tip %s offer %s gold %d->%d" % [tc.tooltip_visible(), slot2.offer, gold0, GameState.me.gold])
	await tap(centre(slot2))
	chk("a normal tap on that card still buys it", slot2.offer == null and GameState.me.gold == gold0 - board.bench.filter(func(x): return x != null and x.data.display_name == name2)[0].data.cost)
	var dock = main.get_node("UI/RightDock")
	var tab: Button = dock.tabs["planner"]
	await hold(centre(tab))
	chk("a long press on a tab shows its tooltip", tc.tooltip_visible() and tc.tooltip_text().contains("planner"))
	await touch(0, centre(tab), false)
	chk("and doesn't open the planner", dock.current != "planner")
	await tap(centre(tab))
	chk("a tap closes the tooltip without opening the planner", not tc.tooltip_visible() and dock.current != "planner")
	await tap(centre(tab))
	chk("a tap on the tab opens it", dock.current == "planner")
	await tap(centre(tab))
	chk("another tap closes it", dock.current != "planner")

	print("--- items")
	var left = main.get_node("UI/LeftDock")
	GameState.me.items.append(load("res://tres/items/longsword.tres"))
	Events.items_changed.emit()
	left.show_tab("items")
	await frames(3)
	var row: Control = left.items.list.get_child(0)
	var r_from := centre(row)
	var r_to := screen_of(u)
	await touch(0, r_from, true)
	await move(0, r_from, r_to, 10)
	await touch(0, r_to, false)
	chk("dragging an item onto a unit with a finger equips it", u.items.size() == 1 and GameState.me.items.is_empty(), "%d on unit, %d left" % [u.items.size(), GameState.me.items.size()])

	print("--- two fingers")
	var c := Vector2(576, 330)
	rig.zoom = 1.0
	rig._zoom_now = 1.0
	rig.pan = Vector3.ZERO
	rig._place()
	await touch(0, c + Vector2(-60, 0), true)
	await touch(1, c + Vector2(60, 0), true)
	for s in range(1, 9):
		var e0 := InputEventScreenDrag.new()
		e0.index = 0
		e0.position = win(c + Vector2(-60 - s * 12, 0))
		Input.parse_input_event(e0)
		var e1 := InputEventScreenDrag.new()
		e1.index = 1
		e1.position = win(c + Vector2(60 + s * 12, 0))
		Input.parse_input_event(e1)
		await frames(1)
	await frames()
	chk("pinching out zooms in", rig.zoom < 0.9, str(rig.zoom))
	var pan0: Vector3 = rig.pan
	for s in range(1, 9):
		var e0 := InputEventScreenDrag.new()
		e0.index = 0
		e0.position = win(c + Vector2(-156 + s * 10, s * 6))
		Input.parse_input_event(e0)
		var e1 := InputEventScreenDrag.new()
		e1.index = 1
		e1.position = win(c + Vector2(156 + s * 10, s * 6))
		Input.parse_input_event(e1)
		await frames(1)
	await frames()
	chk("moving both fingers pans the view", rig.pan.distance_to(pan0) > 0.05, "%s -> %s" % [pan0, rig.pan])
	await touch(1, c + Vector2(236, 48), false)
	await touch(0, c + Vector2(-76, 48), false)
	chk("lifting both fingers leaves no drag behind", not rig.panning and dc.dragging == null)

	var here := screen_of(u)
	await touch(0, here, true)
	await move(0, here, here + Vector2(40, -30), 4)
	chk("(a finger drag picks the unit up)", dc.dragging == u)
	await touch(1, here + Vector2(200, 0), true)
	chk("a second finger cancels the unit drag", dc.dragging == null and u.coord == target, str(u.coord))
	await touch(1, here + Vector2(200, 0), false)
	await touch(0, here + Vector2(40, -30), false)
	chk("and lifting the fingers doesn't move it", u.coord == target)

	print("--- back button")
	tc._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(3)
	chk("back opens the menu (pauses)", dock.current == "menu" and get_tree().paused)
	await tap(centre(dock.menu.resume_button))
	chk("tapping Resume works while paused", dock.current != "menu" and not get_tree().paused)
	tc._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(3)
	tc._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(3)
	chk("back again closes it", dock.current != "menu" and not get_tree().paused)

	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
