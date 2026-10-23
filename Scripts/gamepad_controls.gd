# gamepad_controls.gd
extends Node

# Controller support (Xbox / PlayStation / Switch pads through SDL), as the autoload "GamepadControls".
# The pad drives the mouse pointer and presses the game's own mouse buttons and shortcut keys, so
# everything that works with a mouse works with a pad (shop, dragging units and items, tooltips, tabs,
# menus) and mouse / keyboard play is unchanged.
#
# The buttons below are the defaults; they can be changed in the main menu (Keybinds, keybinds.gd).
#   Left stick          move the pointer (D-pad: slow, precise moves)
#   A                   click; hold to drag a unit or an item, release to drop
#   X                   inspect the unit under the pointer (right-click)
#   Y                   sell the unit under the pointer, or the one being dragged (F)
#   B                   back: closes the planner or the menu, else the inspector
#   Start               menu (Esc)
#   Back / Select       team planner (P)
#   LB / RB             Buy XP / Reroll
#   LT / RT             zoom out / in
#   Right stick         pan the view (when zoomed in)
#   L3                  lock / unlock the shop
#   R3                  reset the view
#
# Godot's default ui_* actions also listen to the pad (A = accept, B = cancel, D-pad = focus moves),
# which would fight with the pointer; _ready takes the pad events off them, and this script sends
# ui_cancel itself.

const DEADZONE := 0.2
const SPEED := 1100.0        # pointer px/s at full tilt (game coordinates), eased in for fine control
const DPAD_SPEED := 220.0
const PAN_SPEED := 700.0     # px/s of view drag at full right-stick tilt
const ZOOM_SPEED := 1.2      # zoom factor change per second at full trigger
const UI_ACTIONS := ["ui_accept", "ui_select", "ui_cancel", "ui_focus_next", "ui_focus_prev",
	"ui_left", "ui_right", "ui_up", "ui_down", "ui_page_up", "ui_page_down", "ui_home", "ui_end"]

var device := 0              # the pad used last
var cursor := Vector2(576, 324)
var holding := false         # A is held: the pointer drags
var active := false          # the pad was used since the mouse last moved by itself

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS   # the pause menu works with the pad too
	for a in UI_ACTIONS:
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(a, e)

func _input(event):
	if event is InputEventJoypadButton:
		device = event.device
		active = true
		_button(event.button_index, event.pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		device = event.device
		if absf(event.axis_value) > DEADZONE:
			active = true
		get_viewport().set_input_as_handled()
	elif active and event is InputEventMouseMotion and not event.has_meta("pad") and event.relative.length() > 3.0:
		active = false   # the real mouse moved: it takes over (the pointer continues from where it is)

func _process(delta):
	if not active:
		cursor = _mouse()   # the real mouse is in charge: start from wherever it is
		return
	var v := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	var move: Vector2 = v * v.length() * SPEED * delta   # squared: slow near the centre, fast at the edge
	move *= Vector2(Settings.pointer_sens_x, Settings.pointer_sens_y)   # Settings > Controls
	var d := Vector2(
		float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP)))
	move += d * DPAD_SPEED * delta
	if move != Vector2.ZERO:
		move_cursor_to(cursor + move)
	var rig = _scene_node("CameraRig")
	if rig != null and not get_tree().paused:
		var pan := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		if pan != Vector2.ZERO:
			var c := _view_size() / 2.0
			rig.drag(c, c - pan * pan.length() * PAN_SPEED * delta)   # stick right: look further right
		var z := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) - Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
		if absf(z) > DEADZONE:
			rig.zoom = clampf(rig.zoom + z * ZOOM_SPEED * Settings.zoom_sens * delta, rig.ZOOM_MIN, rig.ZOOM_MAX)

func _stick(ax: JoyAxis, ay: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(device, ax), Input.get_joy_axis(device, ay))
	if v.length() < DEADZONE:
		return Vector2.ZERO
	return v.normalized() * inverse_lerp(DEADZONE, 1.0, minf(v.length(), 1.0))

func _button(b: JoyButton, pressed: bool):
	if pressed and Keybinds.pad_capture.is_valid():
		Keybinds.pad_capture.call(b)   # the Keybinds screen is waiting for a button
		return
	var action: String = Keybinds.pad_action(b)
	if action == "click":
		if pressed != holding:
			holding = pressed
			_mouse_button(MOUSE_BUTTON_LEFT, pressed)
		return
	if not pressed:
		return
	match action:
		"inspect":
			_mouse_button(MOUSE_BUTTON_RIGHT, true)
			_mouse_button(MOUSE_BUTTON_RIGHT, false)
		"sell_unit":
			var dc = _scene_node("DragController")
			if dc != null and not get_tree().paused:
				dc._sell_with_key()
		"back":
			_back()
		"menu":
			_cancel()
		"team_planner":
			var dock := get_tree().get_first_node_in_group("right_dock")
			if dock != null and not get_tree().paused:
				dock.toggle_panel("planner")
		"buy_xp":
			if _in_run():
				Events.buy_xp_pressed.emit()
		"reroll":
			if _in_run():
				Events.reroll_pressed.emit()
		"lock_shop":
			if _in_run():
				var shop = _scene_node("ShopPanel")
				if shop != null and shop.lock_button != null:
					shop.lock_button.button_pressed = not shop.lock_button.button_pressed
		"reset_view":
			var rig = _scene_node("CameraRig")
			if rig != null:
				rig.reset_view()

# B: close the planner or the menu (like Esc); with neither open, close the unit inspector. Unlike
# Esc it never opens the menu, so mashing B is safe.
func _back():
	var dock := get_tree().get_first_node_in_group("right_dock")
	if dock != null and dock.current in ["planner", "menu"]:
		_cancel()
		return
	var insp = _scene_node("UnitInspector")
	if insp != null and insp.visible:
		insp._close()
		return
	if dock == null:
		_cancel()   # main menu: closes its panels

func _cancel():
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	Input.parse_input_event(e)

func _in_run() -> bool:
	return _scene_node("Game Manager") != null and not get_tree().paused

# Moves the pointer (game coordinates): the OS cursor follows, and the game gets a mouse motion, with
# the left button held while A is down so drags follow it.
func move_cursor_to(p: Vector2) -> void:
	var vs := _view_size()
	var to := Vector2(clampf(p.x, 0.0, vs.x - 1.0), clampf(p.y, 0.0, vs.y - 1.0))
	var rel := to - cursor
	cursor = to
	var w := _window(to)
	Input.warp_mouse(w)
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if holding else 0
	m.set_meta("pad", true)
	Input.parse_input_event(m)

func _mouse_button(b: MouseButton, pressed: bool):
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = pressed
	e.position = _window(cursor)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if (holding and b == MOUSE_BUTTON_LEFT) else 0
	e.set_meta("pad", true)
	Input.parse_input_event(e)

func _mouse() -> Vector2:
	return get_tree().root.get_mouse_position()

func _view_size() -> Vector2:
	return get_tree().root.get_visible_rect().size

# Events we send go in as if from the window, which the stretch mode scales.
func _window(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p

# A node of the running game (main.tscn may be the current scene or, in the checks, a child of it).
func _scene_node(node_name: String) -> Node:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	var n := cs.get_node_or_null(node_name)
	if n == null:
		n = cs.find_child(node_name, true, false)
	return n
