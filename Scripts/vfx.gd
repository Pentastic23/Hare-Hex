# vfx.gd
class_name Vfx

# Spell effects (visual only). Abilities call these when they cast, hit, heal or lay down an area;
# nothing in combat ever reads them back, so fights stay deterministic. Everything is built from
# small glowing cubes, in the voxel look of the units and tiles, and tweened in real time.
# The colour of a unit's effects comes from its origin (color_of). Reduce motion: shorter, with no
# flying debris. Headless runs (tests, the bot) skip them unless a test turns `enabled` on.

static var enabled := DisplayServer.get_name() != "headless"

const ORIGIN_COLORS := {
	&"Order": Color("ffd46b"), &"Celestial": Color("fff2b0"), &"Wild": Color("7fdc5a"),
	&"Shadow": Color("a774ff"), &"Arcane": Color("7a9cff"), &"Undead": Color("9be07a"),
	&"Ember": Color("ff7a2e"), &"Frost": Color("8fe3ff"), &"Fey": Color("ff8fd8"),
	&"Dwarven": Color("e0a85a"), &"Infernal": Color("ff3b3b"),
}
const HEAL := Color("7dff9a")
const HEX_R := 0.95   # one hex, for sizing areas

static var _mats := {}

# The colour of a unit's spells: its origin's (the first tag that is an origin).
static func color_of(u: Unit) -> Color:
	if u != null and u.data != null:
		for t in u.data.tags:
			if ORIGIN_COLORS.has(t):
				return ORIGIN_COLORS[t]
	return Color("cfd8ff")

static func _root(ctx: Node3D) -> Node:
	if ctx == null or not is_instance_valid(ctx) or not ctx.is_inside_tree():
		return null
	var b := ctx.get_tree().get_first_node_in_group("board")
	return b.get_parent() if b != null else ctx.get_tree().current_scene

static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		_mats[key] = m
	return _mats[key]

static func cube(size: float, c: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3.ONE * size
	m.mesh = b
	m.material_override = _mat(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

static func _add(ctx: Node3D, n: Node3D, pos: Vector3) -> bool:
	var r := _root(ctx)
	if r == null:
		n.free()
		return false
	r.add_child(n)
	n.global_position = pos
	return true

# Fades a node's material copy out over secs, then frees it.
static func _fade_out(n: MeshInstance3D, secs: float) -> void:
	var m := (n.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	n.material_override = m
	var t := n.create_tween()
	t.tween_property(m, "albedo_color:a", 0.0, secs)
	t.tween_callback(n.queue_free)

static func _chest(u: Unit) -> Vector3:
	return u.global_position + Vector3(0, 1.0, 0)

# --- one-shot effects ------------------------------------------------------------------------------

# A ring of light at the caster's feet when it casts.
static func cast_flash(u: Unit) -> void:
	if not enabled or u == null:
		return
	ring(u, u.global_position + Vector3(0, 0.08, 0), 0.5, 1.1, color_of(u), 0.45)

# A flat ring that grows from r0 to r1 and fades.
static func ring(ctx: Node3D, pos: Vector3, r0: float, r1: float, c: Color, secs := 0.5) -> void:
	if not enabled:
		return
	var m := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.82
	tor.outer_radius = 1.0
	tor.rings = 24
	tor.ring_segments = 6
	m.mesh = tor
	m.material_override = _mat(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _add(ctx, m, pos):
		return
	m.scale = Vector3(r0, 0.15, r0)
	var t := m.create_tween()
	t.tween_property(m, "scale", Vector3(r1, 0.15, r1), secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_out(m, secs)

# Cubes that burst out from pos and fall away.
static func burst(ctx: Node3D, pos: Vector3, c: Color, count := 8, spread := 0.9) -> void:
	if not enabled:
		return
	var n := count if not Settings.reduce_motion else 3
	for i in n:
		var b := cube(0.14, c if i % 3 != 0 else c.lightened(0.4))
		if not _add(ctx, b, pos):
			return
		var a := TAU * i / n
		var out := Vector3(cos(a), 0.6 + 0.3 * (i % 2), sin(a)) * spread
		var t := b.create_tween()
		if Settings.reduce_motion:
			_fade_out(b, 0.3)
		else:
			t.tween_property(b, "global_position", pos + out, 0.35).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(b, "rotation", Vector3(2, 3, 1), 0.35)
			_fade_out(b, 0.45)

# A glowing cube flying from a to b; bursts where it lands.
static func projectile(ctx: Node3D, a: Vector3, b: Vector3, c: Color) -> void:
	if not enabled:
		return
	var p := cube(0.22, c.lightened(0.2))
	if not _add(ctx, p, a):
		return
	var secs := clampf(a.distance_to(b) / 14.0, 0.08, 0.3)
	var t := p.create_tween()
	t.tween_property(p, "global_position", b, secs)
	t.parallel().tween_property(p, "rotation", Vector3(4, 4, 0), secs)
	t.tween_callback(func():
		if is_instance_valid(p):
			burst(p, b, c, 6, 0.6)
			p.queue_free())

# The impact of a spell on a unit: from the caster as a bolt when it stands apart, else a burst.
static func impact(by: Unit, e: Unit) -> void:
	if not enabled or e == null or not e.is_inside_tree():
		return
	var c := color_of(by)
	if by != null and by.is_inside_tree() and by.global_position.distance_to(e.global_position) > 2.2:
		projectile(by, _chest(by), _chest(e), c)
	else:
		burst(e, _chest(e), c, 6, 0.6)

# Green motes rising from a healed unit.
static func heal(u: Unit) -> void:
	if not enabled or u == null or not u.is_inside_tree():
		return
	for i in (2 if Settings.reduce_motion else 5):
		var b := cube(0.12, HEAL)
		var start := u.global_position + Vector3(cos(i * 1.3) * 0.4, 0.4 + 0.2 * i, sin(i * 1.3) * 0.4)
		if not _add(u, b, start):
			return
		var t := b.create_tween()
		if not Settings.reduce_motion:
			t.tween_property(b, "global_position", start + Vector3(0, 1.0, 0), 0.6)
		_fade_out(b, 0.6)

# An area spell: a hex-sized ring over the area and a burst in the middle.
static func area(ctx: Node3D, board: Board, center: Vector2i, radius: int, c: Color) -> void:
	if not enabled or board == null:
		return
	var pos := board.display_pos(center) + Vector3(0, 0.1, 0)
	var r := HEX_R * (1.0 + 1.75 * radius)
	ring(ctx, pos, r * 0.3, r, c, 0.55)
	burst(ctx, pos + Vector3(0, 0.4, 0), c, 10, 0.4 + 0.6 * radius)

# A beam from a to b that fades (lines, links, tethers).
static func beam(ctx: Node3D, a: Vector3, b: Vector3, c: Color, secs := 0.4, width := 0.16) -> void:
	if not enabled or a.distance_to(b) < 0.01:
		return
	var m := cube(1.0, c)
	if not _add(ctx, m, (a + b) * 0.5):
		return
	m.look_at(b)
	m.scale = Vector3(width, width, a.distance_to(b))
	_fade_out(m, secs)

# A path of bursts over hexes (lines, charges).
static func trail(ctx: Node3D, board: Board, cells: Array, c: Color) -> void:
	if not enabled or board == null:
		return
	for cell in cells:
		burst(ctx, board.display_pos(cell) + Vector3(0, 0.4, 0), c, 5, 0.5)

# A summon appears: a puff where it stands.
static func puff(u: Unit) -> void:
	if not enabled or u == null:
		return
	ring(u, u.global_position + Vector3(0, 0.08, 0), 0.3, 1.0, color_of(u).darkened(0.2), 0.5)
	burst(u, u.global_position + Vector3(0, 0.5, 0), Color("d0d0d0"), 8, 0.5)

# A ground zone that stays for secs: a translucent hex disc that pulses, then fades.
static func zone(ctx: Node3D, board: Board, center: Vector2i, radius: int, c: Color, secs: float) -> void:
	if not enabled or board == null:
		return
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var r := HEX_R * (1.0 + 1.75 * radius)
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 0.04
	cyl.radial_segments = 6
	m.mesh = cyl
	m.material_override = _mat(Color(c, 0.35 * c.a))
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _add(ctx, m, board.display_pos(center) + Vector3(0, 0.08, 0)):
		return
	var t := m.create_tween()
	if not Settings.reduce_motion:
		t.set_loops(int(secs / 0.8))
		t.tween_property(m, "scale", Vector3(1.06, 1, 1.06), 0.4)
		t.tween_property(m, "scale", Vector3.ONE, 0.4)
	m.get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(m):
			_fade_out(m, 0.3))

# A blizzard over a whole side of the board: snow cubes falling for secs (Eternal Winter).
static func blizzard(ctx: Node3D, board: Board, enemy_team: int, secs: float) -> void:
	if not enabled or board == null:
		return
	var rows := range(0, 4) if enemy_team == 1 else range(4, 8)
	var cells: Array[Vector2i] = []
	for y in rows:
		for x in Board.COLS:
			cells.append(Vector2i(x, y))
	for cell in cells:   # frost on every hex of that side
		zone(ctx, board, cell, 0, Color(0.8, 0.95, 1.0, 0.6), secs)
	var waves := 2 if Settings.reduce_motion else int(secs / 0.5)
	for w in waves:
		ctx.get_tree().create_timer(w * 0.5).timeout.connect(func():
			if not is_instance_valid(board) or not is_instance_valid(ctx) or not board.is_inside_tree():
				return   # the fight (or the scene) is gone
			for i in range(w % 3, cells.size(), 3):
				var top := board.display_pos(cells[i]) + Vector3(0.3 * (i % 2), 3.0, 0)
				var s := cube(0.12, Color("eefaff"))
				if not _add(ctx, s, top):
					return
				var t := s.create_tween()
				t.tween_property(s, "global_position", top - Vector3(0, 2.9, 0), 0.7)
				t.tween_callback(s.queue_free))
