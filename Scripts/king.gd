# king.gd
class_name King extends Node3D

# Each side's king (Board.kings, index = team): one extra hex just left of that side's part of the
# board, with the king standing on it (its skin's voxel model, KingSkins; the enemy's in darker colours). The board keeps it at the left edge of the open
# tiles and slides it outwards as the board grows (Board.king_spot / _place_kings).
#
# It is NOT a Unit on purpose: no tile, bench slot, targeting, merging, team size, selling, dragging or
# inspecting, and it can't be hurt. It is locked to its hex (`locked`). What it does in a fight (a
# strike every 10 s, plus its skin's effect) is CombatRunner._kings_act, which works without this node
# (the lobby server's boards have none); this is only how it looks: strike() is its attack (a wind-up,
# a lunge and its skin's shot), help() its lift for an ally and act() a little hop.

const SLIDE := 0.4       # seconds to slide to a new spot when the board grows
const TURN := 0.35       # seconds to turn round when a fight starts or ends

var team := 0            # 0 you, 1 the enemy
var locked := true       # fixed to its hex: never dragged, sold, benched or removed
var body: MeshInstance3D # the king itself (its skin's model)
var skin: StringName = KingSkins.DEFAULT
var shape: StringName = KingSkins.DEFAULT   # the model it wears: its own skin's (the Shadow King: its opponent's)
var _tween: Tween
var _turn: Tween         # turning to face the fight or the camera
var fighting := false    # (set from Events.phase_changed)
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
	body.position.y = 0.01
	add_child(body)
	body.rotation.y = rest_yaw()
	set_skin(KingSkins.DEFAULT)
	Events.phase_changed.connect(_on_phase)

# Like the units: out of a fight your king faces the camera; when a fight starts it turns to the other
# side, and back when it ends. The enemy's king always faces your side.
func rest_yaw() -> float:
	if fighting or team != Unit.viewer_team:
		return PI if team == 1 else 0.0   # facing the other side (models face -Z)
	var b := get_parent().get_parent() as Board if get_parent() != null else null
	return 0.0 if b != null and b.view_flipped else PI   # world +Z, at the camera, as Unit.face_rest

func _on_phase(phase: int) -> void:
	var now := phase == Events.Phase.COMBAT
	if now == fighting:
		return
	fighting = now
	if body == null:
		return
	if _anim != null:   # a strike still playing out as the fight ends: stop it where it is
		_anim.kill()
		_anim = null
		body.position = Vector3(0, 0.01, 0)
		body.scale = Vector3.ONE
		body.rotation.x = 0.0
	if _turn != null:
		_turn.kill()
	var yaw := rest_yaw()
	if Settings.reduce_motion or not is_inside_tree():
		body.rotation.y = yaw
		return
	var from := body.rotation.y
	_turn = create_tween()
	_turn.tween_property(body, "rotation:y", from + wrapf(yaw - from, -PI, PI), TURN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

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
	_dress()

# Dresses the king in a skin (KingSkins). The Shadow King takes the shape of `mimic` (the opposing king's
# skin), in shadow. The other side's king wears its skin in darker, rival colours.
func set_skin(id: StringName, mimic: StringName = KingSkins.DEFAULT) -> void:
	skin = id if KingSkins.has(id) else KingSkins.DEFAULT
	shape = mimic if KingSkins.has(mimic) and mimic != &"shadow" else KingSkins.DEFAULT
	if skin != &"shadow":
		shape = skin
	body.mesh = KingSkins.model(skin, shape)
	_dress()

func _dress() -> void:
	if body == null:
		return
	if skin == &"shadow":
		body.material_override = shadow_mat()
	else:
		body.material_override = _rival_mat() if team != Unit.viewer_team else null

static var _rival: StandardMaterial3D
static func _rival_mat() -> StandardMaterial3D:
	if _rival == null:
		_rival = (VoxelTiles.SOLID as StandardMaterial3D).duplicate()
		_rival.albedo_color = Color(0.62, 0.42, 0.42)   # a darker, redder king across the board
	return _rival

# The Shadow King: the shape it took in near-black violet, lit faintly from within and rimmed in violet.
static var _shadow: StandardMaterial3D
static func shadow_mat() -> StandardMaterial3D:
	if _shadow == null:
		_shadow = (VoxelTiles.SOLID as StandardMaterial3D).duplicate()
		_shadow.albedo_color = Color(0.22, 0.16, 0.34)
		_shadow.emission_enabled = true
		_shadow.emission = Color("5a2fb0")
		_shadow.emission_energy_multiplier = 0.55
		_shadow.rim_enabled = true
		_shadow.rim = 0.8
		_shadow.rim_tint = 0.2
	return _shadow

# --- acting (visual only; what a king does is CombatRunner._kings_act) ---------------------------------

const WIND_UP := 0.14   # lean back and crouch
const LUNGE := 0.08     # throw itself at the target; the shot leaves here
const RECOVER := 0.3    # back to rest
const REACH := 0.32     # how far it lunges
const MUZZLE := Vector3(0, 1.2, -0.5)   # where its shots leave from, in the body's space (models face -z)

var _anim: Tween

# Its attack: it turns to the target, winds up (leaning back, crouched), lunges, and its skin's shot
# (`attack` in KingSkins.DEFS) leaves at the lunge; then it springs back and turns home. Reduce motion:
# the shot only.
func strike(target: Unit) -> void:
	if not is_inside_tree() or target == null or not is_instance_valid(target):
		return
	var at := target.global_position + Vector3(0, 1.0, 0)
	if Settings.reduce_motion:
		_fire(target, at)
		return
	var d := to_local(at)
	d.y = 0.0
	var rest := rest_yaw()
	var yaw := rest
	var dir := Vector3(0, 0, -1 if team == 0 else 1)
	if d.length() > 0.01:
		yaw = rest + wrapf(atan2(-d.x, -d.z) - rest, -PI, PI)   # the short way round
		dir = d.normalized()
	var home := Vector3(0, 0.01, 0)
	_reset_anim()
	_anim = create_tween()
	_anim.tween_property(body, "rotation", Vector3(0.2, yaw, 0), WIND_UP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_anim.parallel().tween_property(body, "scale", Vector3(1.08, 0.88, 1.08), WIND_UP)
	_anim.parallel().tween_property(body, "position", home - dir * 0.08, WIND_UP)
	_anim.tween_property(body, "rotation", Vector3(-0.3, yaw, 0), LUNGE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_anim.parallel().tween_property(body, "scale", Vector3(0.94, 1.12, 0.94), LUNGE)
	_anim.parallel().tween_property(body, "position", home + dir * REACH + Vector3(0, 0.12, 0), LUNGE)
	_anim.tween_callback(_fire.bind(target, at))
	_anim.tween_property(body, "rotation", Vector3(0, yaw, 0), RECOVER).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_anim.parallel().tween_property(body, "scale", Vector3.ONE, RECOVER).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_anim.parallel().tween_property(body, "position", home, RECOVER)
	_anim.tween_interval(0.15)
	_anim.tween_property(body, "rotation:y", rest, 0.25).set_trans(Tween.TRANS_SINE)

func animating() -> bool:
	return _anim != null and _anim.is_running()

func _reset_anim() -> void:
	if _anim != null:
		_anim.kill()
		_anim = null
	body.position = Vector3(0, 0.01, 0)
	body.scale = Vector3.ONE
	if _turn != null:
		_turn.kill()
	body.rotation = Vector3(0, rest_yaw(), 0)

# The world point its shots leave from.
func muzzle() -> Vector3:
	return body.global_transform * MUZZLE

# The skin's shot at the target (KingSkins.DEFS attack). `at` is where the target stood, if it is gone.
func _fire(target: Unit, at: Vector3) -> void:
	if not is_inside_tree():
		return
	var u: Unit = target if is_instance_valid(target) and target.is_inside_tree() else null
	if u != null:
		at = u.global_position + Vector3(0, 1.0, 0)
	var from := muzzle()
	var c := KingSkins.colour(skin)
	fired += 1
	match str(KingSkins.DEFS[skin].attack) if KingSkins.has(skin) else "":
		"claw":   # a roar, a golden bolt and claw marks
			Vfx.rings(self, from, c, 2, 0.9)
			Vfx.projectile(self, from, at, c)
			if u != null:
				Vfx._later(self, 0.14, func(): Vfx.slash(u, from, c.lightened(0.3), PI * 0.5, 0.7, 0.9))
		"coins":   # a tossed fistful of gold
			for i in 3:
				Vfx._later(self, i * 0.06, func(): Vfx.arc_shot(self, from, at + Vector3((i - 1) * 0.25, 0, 0), c, 1.4 + i * 0.3, 1.0, 0.15))
			if u != null:
				Vfx._later(self, 0.35, func(): Vfx.coins(u, 5))
		"dice":   # a big die tumbling through the air, bursting in red and white
			Vfx.arc_shot(self, from, at, Color("f4f1e8"), 1.8, 1.0, 0.26)
			Vfx._later(self, 0.38, func():
				Vfx.burst(self, at, c, 6, 0.7)
				Vfx.burst(self, at, Color("f4f1e8"), 6, 0.9))
		"souls":   # a wailing green soul, and spirits rising off the target
			Vfx.projectile(self, from, at, c)
			Vfx.lightning(self, [from, from.lerp(at, 0.5) + Vector3(0, 0.6, 0), at], c.darkened(0.2))
			if u != null:
				Vfx._later(self, 0.2, func(): Vfx.rise(u, c, 6, 0.6, 0.5))
		"stone":   # a slung stone in a high arc and a puff of dust
			Vfx.arc_shot(self, from, at, Color("8a7a66"), 2.2, 1.0, 0.2)
			Vfx._later(self, 0.4, func(): Vfx.burst(self, at, c, 10, 1.0))
		"chaos":   # lightning in a different colour each time, and confetti
			var hues := [Color("ff5ad8"), Color("5ad8ff"), Color("ffe25a"), Color("7dff6a")]
			var pick: Color = hues[fired % hues.size()]
			var mid := from.lerp(at, 0.5)
			Vfx.lightning(self, [from, mid + Vector3(0.4, 0.5, 0), mid - Vector3(0.3, 0.1, 0), at], pick)
			for h in hues:
				Vfx.burst(self, at, h, 3, 1.0)
		"fire":   # a gout of dragon fire
			Vfx.breath(self, from, at, c, 0.45, 0.35)
			Vfx._later(self, 0.3, func(): Vfx.burst(self, at, Color("ffd36b"), 8, 0.8))
		"thread":   # a golden thread of fate pulled taut, and a ring of stars
			Vfx.beam(self, from, at, c, 0.45, 0.07)
			Vfx.beam(self, from + Vector3(0, 0.05, 0), at, Color("ffe9a0"), 0.3, 0.03)
			Vfx._later(self, 0.1, func(): Vfx.ring(self, at - Vector3(0, 0.9, 0), 0.2, 1.0, Color("ffe9a0"), 0.5))
		"shadow":   # a bolt of darkness and a cloud of shadow
			Vfx.projectile(self, from, at, c)
			Vfx._later(self, 0.15, func(): Vfx.cloud(self, at, Color("2a1848"), 0.8, 0.6))
		_:
			Vfx.projectile(self, from, at, c)

var fired := 0   # shots fired (tests; the Chaos King's colour)

# Helping an ally (the Golden Lion's shield): a beam of light, a ring and a burst on the ally, and a
# hop. Right after a strike it waits for the strike to finish.
func help(u: Unit) -> void:
	if not is_inside_tree() or u == null or not is_instance_valid(u):
		return
	var c := KingSkins.colour(skin)
	var go := func():
		if not is_instance_valid(u) or not u.is_inside_tree() or not is_inside_tree():
			return
		Vfx.beam(self, muzzle() + Vector3(0, 0.4, 0), u.global_position + Vector3(0, 1.0, 0), c, 0.3, 0.05)
		Vfx.ring(u, u.global_position + Vector3(0, 0.08, 0), 0.4, 1.1, c, 0.5)
		Vfx.burst(u, u.global_position + Vector3(0, 1.0, 0), c.lightened(0.4), 8, 0.6)
	if animating():
		Vfx._later(self, WIND_UP + LUNGE + 0.1, go)
		return
	go.call()
	act()

# A little hop (Reduce motion: none).
func act() -> void:
	if Settings.reduce_motion or not is_inside_tree():
		return
	_reset_anim()
	_anim = create_tween()
	_anim.tween_property(body, "position:y", 0.35, 0.12).set_ease(Tween.EASE_OUT)
	_anim.tween_property(body, "position:y", 0.01, 0.18).set_ease(Tween.EASE_IN)

