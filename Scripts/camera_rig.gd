# camera_rig.gd
extends Node3D

# The board camera (main.tscn CameraRig, Camera3D child): looks down at the board from behind your
# side, like TFT, with a narrow field of view so the board fills the screen. The rig sits on the point
# the camera looks at and is tilted by `pitch`; the camera sits `distance` back along the tilt.
# Mouse wheel (or + / -) zooms between ZOOM_MIN and ZOOM_MAX times the default distance, smoothly;
# zooming in also slides the aim from `target` to `zoom_focus`, so the fight stays on screen.
# Zoomed in, drag to pan: middle mouse anywhere, or left mouse on empty ground (a left press on one of
# your units, or an item drag, moves that instead). Panning never shows more than the default view
# does: the zoomed-in view is kept inside the ground area visible at the default zoom.
# Purely a view: picking (drag_controller, unit_inspector) asks the camera for rays, so any zoom works.

@export var target := Vector3(5.63, 0.0, 9.1)   # between the middle of the board and the bench
@export var zoom_focus := Vector3(5.63, 0.0, 6.0)   # what the camera aims at when fully zoomed in: the middle of the board, where the fight is
@export var pitch := 54.0                       # degrees down from horizontal
@export var distance := 23.0                    # default zoom
@export var fov := 38.0

const ZOOM_MIN := 0.65
const ZOOM_MAX := 1.15
const ZOOM_STEP := 0.08   # per wheel notch, as a fraction of the default distance
const ZOOM_SPEED := 12.0  # how fast the camera eases to the wanted zoom

@onready var cam: Camera3D = $Camera3D
var zoom := 1.0           # wanted distance / default distance
var _zoom_now := 1.0
var pan := Vector3.ZERO   # player's drag offset on the ground, kept within bounds by _place
var panning := false
var _pan_from := Vector2.ZERO

func _ready():
	position = target
	rotation = Vector3(deg_to_rad(-pitch), 0.0, 0.0)
	cam.fov = fov
	cam.rotation = Vector3.ZERO
	get_viewport().size_changed.connect(_place)
	_place()

# The ground rectangle-ish area (a trapezoid: the far edge is wider) that the camera sees at the default
# zoom, as offsets from the aim point: [near z, near half width, far z, far half width]. A camera moved
# along its own view line scales this about the aim point, so zoom z sees `z` times these offsets.
func _footprint() -> Array:
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var tan_v := tan(deg_to_rad(fov) / 2.0)
	var basis := Basis(Vector3.RIGHT, deg_to_rad(-pitch))
	var eye := basis * Vector3(0.0, 0.0, distance)
	var out: Array = []
	for sy in [-1.0, 1.0]:   # bottom of the screen (near), top (far)
		var dir := basis * Vector3(aspect * tan_v, sy * tan_v, -1.0)
		var s := -eye.y / dir.y
		var hit := eye + dir * s
		out.append(hit.z)
		out.append(absf(hit.x))
	return out

# The aim point for the current zoom and pan, pulled back so the view stays inside the default view.
func aim() -> Vector3:
	var t := clampf((1.0 - _zoom_now) / (1.0 - ZOOM_MIN), 0.0, 1.0)   # 0 at the default zoom, 1 fully in
	var base := target.lerp(zoom_focus, t)
	var want := base + pan
	var f := _footprint()
	var nz: float = f[0]
	var nw: float = f[1]
	var fz: float = f[2]
	var fw: float = f[3]
	var z := _zoom_now
	# depth: the zoomed near and far edges stay between the default ones
	var z_lo := target.z + fz - z * fz
	var z_hi := target.z + nz - z * nz
	var a := want
	a.z = clampf(want.z, z_lo, z_hi) if z_lo <= z_hi else target.z
	# sides: at the zoomed near and far rows, the view's half width fits inside the default trapezoid
	var room := INF
	for row in [[nz, nw], [fz, fw]]:
		var rz: float = a.z - target.z + z * float(row[0])     # this row's depth, relative to the default aim
		var k := clampf((rz - nz) / (fz - nz), 0.0, 1.0)
		var default_half := lerpf(nw, fw, k)                  # default view's half width at that depth
		room = minf(room, default_half - z * float(row[1]))
	a.x = clampf(want.x, target.x - room, target.x + room) if room >= 0.0 else target.x
	pan = a - base   # never store more pan than can be used, so dragging back responds at once
	return a

func _place():
	position = aim()
	cam.position = Vector3(0.0, 0.0, distance * _zoom_now)

func zoom_by(notches: float) -> void:
	zoom = clampf(zoom + notches * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)

func _ground(screen: Vector2) -> Variant:
	return Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))

func _unhandled_input(event):
	# Wheel over a scrolling list (planner, synergies) is used by the list first, so it never zooms.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and not _drag_busy()):
			panning = true
			_pan_from = event.position
	elif event is InputEventKey and event.pressed and not get_tree().paused:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			zoom_by(-1.0)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			zoom_by(1.0)

# Motion and release are watched in _input so a drag keeps going over HUD panels.
func _input(event):
	if not panning:
		return
	if event is InputEventMouseButton and not event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE):
		panning = false
	elif event is InputEventMouseMotion:
		drag(_pan_from, event.position)
		_pan_from = event.position

# Moves the view so the ground point under `from` ends up under `to` (grab-and-drag feel).
func drag(from: Vector2, to: Vector2) -> void:
	var a = _ground(from)
	var b = _ground(to)
	if a == null or b == null:
		return
	pan -= Vector3(b.x - a.x, 0.0, b.z - a.z)
	_place()

# True while the left button is moving a unit or an item instead of the view.
func _drag_busy() -> bool:
	var dc := get_node_or_null("../DragController")
	return dc != null and (dc.dragging != null or dc.dragging_item != null)

func _process(delta):
	if is_equal_approx(_zoom_now, zoom):
		return
	_zoom_now = lerpf(_zoom_now, zoom, minf(1.0, delta * ZOOM_SPEED))
	if absf(_zoom_now - zoom) < 0.001:
		_zoom_now = zoom
	_place()
