# touch_controls.gd
extends Node

# Touch screen support (phones and tablets), as the autoload "TouchControls". Godot already turns the
# first finger into a left mouse button (input_devices/pointing/emulate_mouse_from_touch), so tapping
# buttons, buying, dragging units and items, and one-finger panning work as they do with a mouse.
# This adds what a mouse has and a finger doesn't:
#   - Tap a unit: open the unit inspector (a right-click); tap empty ground: close it.
#   - Long press (0.45 s) on a unit: the same. Long press on anything in the HUD with a tooltip: shows
#     the tooltip in a box above the finger until the finger lifts, without pressing the button under it
#     (so a long press on a shop card reads it instead of buying it).
#   - Two fingers: pinch to zoom, move both to pan. A second finger cancels a unit or item drag.
#   - Android back button: acts like Esc (closes the planner, opens / closes the menu).
# Mouse and keyboard play is unchanged: only InputEventScreenTouch / ScreenDrag are read here.
# Native tooltips are switched off on phones in project.godot (gui/timers/tooltip_delay_sec.mobile).

const LONG_PRESS := 0.45     # seconds
const TAP_TIME := 0.3        # a shorter touch that didn't move is a tap
const SLOP := 14.0           # px a finger may wander and still count as holding still
const FAR := Vector2(-10000, -10000)

var touches := {}            # finger index -> position
var _start_pos := Vector2.ZERO
var _start_time := 0.0
var _held := 0.0
var _single := false         # one finger down and still a candidate for tap / long press
var _long_fired := false
var _multi := false          # two fingers have been down since the last full release
var _pinch_dist := 0.0
var _pinch_zoom := 1.0
var _mid := Vector2.ZERO
var _tip_layer: CanvasLayer
var _tip: PanelContainer
var _tip_label: Label
var _swallow := false        # a tooltip is up: the finger's mouse events must not reach the HUD

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS   # the pause menu works by touch too
	_tip_layer = CanvasLayer.new()
	_tip_layer.layer = 100
	add_child(_tip_layer)
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.1, 0.15, 0.96)
	s.border_width_top = 2
	s.border_color = Color("f2c14e")
	s.set_corner_radius_all(3)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	_tip.add_theme_stylebox_override("panel", s)
	_tip_layer.add_child(_tip)
	_tip_label = Label.new()
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.add_theme_font_size_override("font_size", 14)
	_tip.add_child(_tip_label)

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var e := InputEventAction.new()
		e.action = "ui_cancel"
		e.pressed = true
		Input.parse_input_event(e)

func _input(event):
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif _swallow and event is InputEventMouse and not (event is InputEventMouseButton and event.pressed) and event.position.x > FAR.x / 2.0:
		get_viewport().set_input_as_handled()   # the finger reading a tooltip moves or lifts: the HUD never sees it (our own moves off-screen go through)

func _process(delta):
	if not _single or _long_fired:
		return
	_held += delta
	if _held >= LONG_PRESS:
		_long_fired = true
		_long_press(_start_pos)

func _on_touch(e: InputEventScreenTouch):
	if e.pressed:
		touches[e.index] = e.position
		if touches.size() == 1 and not _multi:
			_single = true
			_long_fired = false
			_held = 0.0
			_start_pos = e.position
			_start_time = Time.get_ticks_msec() / 1000.0
		elif touches.size() >= 2:
			_begin_multi()
		return
	touches.erase(e.index)
	if _single and touches.is_empty():
		var quick := Time.get_ticks_msec() / 1000.0 - _start_time < TAP_TIME
		if not _long_fired and quick and e.position.distance_to(_start_pos) <= SLOP:
			_tap(e.position)
	if touches.is_empty():
		_single = false
		_multi = false
		_end_tooltip()
	elif touches.size() == 1:
		_mid = touches.values()[0]   # one finger left: keep panning from it without a jump

func _on_drag(e: InputEventScreenDrag):
	touches[e.index] = e.position
	if _single and e.position.distance_to(_start_pos) > SLOP:
		_single = false   # it's a drag now (a unit, an item, or the view)
	if not _multi:
		return
	var rig = _rig()
	if touches.size() >= 2:
		var pts: Array = touches.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var mid := (a + b) / 2.0
		var dist := maxf(a.distance_to(b), 1.0)
		if rig != null:
			rig.zoom = clampf(_pinch_zoom * _pinch_dist / dist, rig.ZOOM_MIN, rig.ZOOM_MAX)
			rig.drag(_mid, mid)
		_mid = mid
	elif touches.size() == 1 and rig != null:
		var p: Vector2 = touches.values()[0]
		rig.drag(_mid, p)
		_mid = p

# A second finger: stop whatever the first one was doing and start a pinch / pan.
func _begin_multi():
	_single = false
	_end_tooltip()
	var dc = _scene_node("DragController")
	if dc != null:
		dc._cancel_drag()   # also ends an item drag
	var rig = _rig()
	var pts: Array = touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	_mid = (a + b) / 2.0
	_pinch_dist = maxf(a.distance_to(b), 1.0)
	if rig != null:
		rig.panning = false
		_pinch_zoom = rig.zoom
	_multi = true
	# The first finger is also a held mouse button: move it off every button so lifting it presses nothing.
	_mouse_motion(FAR)

# A tap on the board (not on the HUD) inspects the unit there, or closes the inspector on empty ground.
func _tap(at: Vector2):
	if ui_at(at) != null:
		return
	_right_click(at)

func _long_press(at: Vector2):
	var c := ui_at(at)
	if c == null:
		_right_click(at)   # inspect
		return
	var text := ""
	var n: Node = c
	while n is Control:
		var ctl := n as Control
		text = ctl.get_tooltip(ctl.get_global_transform_with_canvas().affine_inverse() * at)
		if text != "":
			break
		n = n.get_parent()
	if text == "":
		return
	_show_tooltip(text, at)
	# The finger is still a held mouse button on that control: slide it off so lifting it presses nothing.
	_mouse_motion(FAR)
	_swallow = true

func _show_tooltip(text: String, at: Vector2):
	_tip_label.text = text
	_tip.visible = true
	_tip.reset_size()
	var vp := _tip.get_viewport_rect().size
	var sz := _tip.get_combined_minimum_size()
	var p := at + Vector2(-sz.x / 2.0, -sz.y - 28.0)   # above the finger, so it isn't covered
	if p.y < 4.0:
		p.y = at.y + 28.0
	p.x = clampf(p.x, 4.0, vp.x - sz.x - 4.0)
	p.y = clampf(p.y, 4.0, vp.y - sz.y - 4.0)
	_tip.position = p

func tooltip_visible() -> bool:
	return _tip.visible

func tooltip_text() -> String:
	return _tip_label.text if _tip.visible else ""

func _end_tooltip():
	if not _swallow and not _tip.visible:
		return
	_tip.visible = false
	if _swallow:
		_swallow = false
		var up := InputEventMouseButton.new()   # release the emulated button away from everything
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = _window(FAR)
		up.global_position = up.position
		Input.parse_input_event(up)

func _right_click(at: Vector2):
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = _window(at)
		e.global_position = e.position
		Input.parse_input_event(e)

func _mouse_motion(to: Vector2):
	var m := InputEventMouseMotion.new()
	m.position = _window(to)
	m.global_position = m.position
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(m)

# Events we send go in as if from the window, which the stretch mode scales; the positions here are
# in game (viewport) coordinates, like the touches we receive.
func _window(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p

# The HUD control (one that takes the mouse) under a screen point, or null over the board. Used
# instead of the viewport's hovered control, which a finger only updates once it moves.
func ui_at(at: Vector2) -> Control:
	var best: Control = null
	var best_layer := -INF
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := layer as CanvasLayer
		if cl == _tip_layer or not cl.visible:
			continue
		var hit := _hit(cl, at)
		if hit != null and cl.layer >= best_layer:
			best = hit
			best_layer = cl.layer
	return best

# The last-drawn control under `at` in this subtree that doesn't ignore the mouse.
func _hit(n: Node, at: Vector2) -> Control:
	var found: Control = null
	for c in n.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		var deeper := _hit(c, at)
		if deeper != null:
			found = deeper
		elif c is Control:
			var ctl := c as Control
			if ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE and ctl.get_global_rect().has_point(at):
				found = ctl
	return found

func _rig():
	return _scene_node("CameraRig")

# A node of the running game (main.tscn may be the current scene or, in the checks, a child of it).
func _scene_node(node_name: String) -> Node:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	var n := cs.get_node_or_null(node_name)
	if n == null:
		n = cs.find_child(node_name, true, false)
	return n
