# king.gd
class_name King extends Node3D

# Each side's king (Board.kings, index = team): one extra hex just left of that side's part of the
# board, with a placeholder cylinder standing on it. The board keeps it at the left edge of the open
# tiles and slides it outwards as the board grows (Board.king_spot / _place_kings).
#
# It is NOT a Unit on purpose, so for now it stays out of everything units take part in: no tile,
# bench slot, targeting, merging, team size, selling, dragging or inspecting. It is locked to its hex
# (`locked`): nothing can pick it up, sell it or take it off the board. Its mechanics (health, what
# happens when it falls, abilities...) come later; this node is where they hook in.

const RADIUS := 0.38     # of the placeholder cylinder
const HEIGHT := 1.5
const SLIDE := 0.4       # seconds to slide to a new spot when the board grows

var team := 0            # 0 you, 1 the enemy
var locked := true       # fixed to its hex: never dragged, sold, benched or removed
var body: MeshInstance3D # the placeholder cylinder
var _tween: Tween
var _mats: Array[StandardMaterial3D] = []   # body and outline, recoloured by recolour()

func setup(t: int) -> void:
	team = t
	name = "PlayerKing" if t == 0 else "EnemyKing"
	add_to_group("kings")
	var colour: Color = Unit.RING_COLORS[t]   # the same team colours as a unit's ring
	# The hex it stands on. Named "MeshInstance3D" so Board._skin dresses it like a board tile.
	var hex := MeshInstance3D.new()
	hex.name = "MeshInstance3D"
	hex.mesh = Board.hex_block()
	add_child(hex)
	_outline(colour)
	body = MeshInstance3D.new()
	body.name = "Body"
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = HEIGHT
	body.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.7
	body.material_override = mat
	_mats.append(mat)
	body.position.y = HEIGHT / 2.0 + 0.02
	add_child(body)

# A thin glowing outline round the hex in the team colour, so you can tell the two kings apart.
func _outline(colour: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 1.2
	_mats.append(mat)
	var r := Board.BORDER_R
	var holder := Node3D.new()
	holder.name = "Outline"
	add_child(holder)
	for k in 6:
		var a := Vector3(sin(k * TAU / 6.0) * r, 0.1, cos(k * TAU / 6.0) * r)
		var b := Vector3(sin((k + 1) * TAU / 6.0) * r, 0.1, cos((k + 1) * TAU / 6.0) * r)
		var d := b - a
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(Vector2(d.x, d.z).length() + 0.06, 0.03, 0.06)
		seg.mesh = box
		seg.material_override = mat
		seg.position = (a + b) / 2.0
		seg.rotation.y = atan2(-d.z, d.x)
		holder.add_child(seg)

# Moves to a new spot: a short slide, or at once (the first placement, Reduce motion).
func move_to(p: Vector3, animate := true) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if not animate or Settings.reduce_motion or not is_inside_tree() or position.is_equal_approx(p):
		position = p
		return
	_tween = create_tween()
	_tween.tween_property(self, "position", p, SLIDE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# Blue for the viewer's side, orange for the other (Unit.viewer_team: a lobby client watching a fight
# from the away side sees the enemy king's hex as its own). Visual only.
func recolour() -> void:
	var colour: Color = Unit.RING_COLORS[0 if team == Unit.viewer_team else 1]
	for m in _mats:
		m.albedo_color = colour
		if m.emission_enabled:
			m.emission = colour
