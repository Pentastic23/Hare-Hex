# interest_stack.gd
class_name InterestStack extends Node3D

# Your interest as a pile of gold (Board.interest): one extra hex just right of your half of the board
# (INTEREST_CELL) with one coin stacked on it per 10 gold banked, up to the interest cap
# (PlayerState.interest_gold, so the Merchant King's higher cap shows too). A new coin drops onto the
# pile and a spent one pops off. Visual only: nothing reads it back.

const COIN_R := 0.34
const COIN_H := 0.11
const DROP := 0.28        # seconds for a new coin to fall onto the pile
const FALL := 1.2         # it falls from this high above its place

var coins: Array[MeshInstance3D] = []   # bottom first (tests read coins.size())
var _board: Board
static var _mesh: CylinderMesh
static var _mat: StandardMaterial3D

func setup(board: Board) -> void:
	_board = board
	name = "InterestStack"
	# The hex it sits on. Named "MeshInstance3D" so Board._skin dresses it like a board tile.
	var hex := MeshInstance3D.new()
	hex.name = "MeshInstance3D"
	hex.mesh = Board.hex_block()
	add_child(hex)
	_outline()
	Events.gold_changed.connect(func(_g): refresh())
	Events.phase_changed.connect(func(_p): refresh())   # a new king power or round can move the cap
	refresh(false)

func wanted() -> int:
	var p := _board.player if _board != null else null
	return p.interest_gold() if p != null else 0

func refresh(animate := true) -> void:
	var n := maxi(wanted(), 0)
	animate = animate and not Settings.reduce_motion and is_inside_tree()
	while coins.size() < n:
		_add_coin(animate)
	while coins.size() > n:
		_remove_coin(animate)

func _add_coin(animate: bool) -> void:
	var i := coins.size()
	var c := MeshInstance3D.new()
	c.mesh = _coin_mesh()
	c.material_override = _coin_mat()
	# a slightly untidy pile: each coin a little off centre (fixed per height, so it never jitters)
	var off := Vector2(0.05, 0.0).rotated(i * 2.4)
	var at := Vector3(off.x, 0.01 + COIN_H * (i + 0.5), off.y)
	add_child(c)
	coins.append(c)
	if not animate:
		c.position = at
		return
	c.position = at + Vector3(0, FALL, 0)
	var t := c.create_tween()
	t.tween_property(c, "position", at, DROP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(c, "scale", Vector3(1.15, 0.7, 1.15), 0.06)
	t.tween_property(c, "scale", Vector3.ONE, 0.1)

func _remove_coin(animate: bool) -> void:
	var c: MeshInstance3D = coins.pop_back()
	if not animate:
		c.queue_free()
		return
	var t := c.create_tween()
	t.set_parallel()
	t.tween_property(c, "position:y", c.position.y + 0.5, 0.25).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(c.queue_free)

# A thin gold outline round the hex (like the kings' team outlines), so the pile reads as its own spot.
func _outline() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HudStyle.GOLD
	mat.emission_enabled = true
	mat.emission = HudStyle.GOLD
	mat.emission_energy_multiplier = 0.8
	var r := Board.BORDER_R
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
		add_child(seg)

static func _coin_mesh() -> CylinderMesh:
	if _mesh == null:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = COIN_R
		_mesh.bottom_radius = COIN_R
		_mesh.height = COIN_H
		_mesh.radial_segments = 12   # a little faceted, to sit with the voxel art
		_mesh.rings = 1
	return _mesh

static func _coin_mat() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = HudStyle.GOLD
		_mat.metallic = 0.55
		_mat.roughness = 0.35
		_mat.emission_enabled = true   # a faint glow, so the pile reads in the darker biomes
		_mat.emission = HudStyle.GOLD
		_mat.emission_energy_multiplier = 0.25
	return _mat
