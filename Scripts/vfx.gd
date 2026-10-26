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
static var _boxes := {}
static var made := 0   # effect nodes made so far (tests)

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

# An unshaded material in colour c, shared; glow > 1 pushes it past 1.0 so it blooms with Glow & fog.
static func _mat(c: Color, glow := 1.0) -> StandardMaterial3D:
	var key := c.to_html() + str(glow)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r * glow, c.g * glow, c.b * glow, c.a)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		_mats[key] = m
	return _mats[key]

static func cube(size: float, c: Color, glow := 1.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var key := snappedf(size, 0.001)
	if not _boxes.has(key):   # one mesh per size, shared by every cube of that size
		var b := BoxMesh.new()
		b.size = Vector3.ONE * size
		_boxes[key] = b
	m.mesh = _boxes[key]
	m.material_override = _mat(c, glow)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

static func _add(ctx: Node3D, n: Node3D, pos: Vector3) -> bool:
	var r := _root(ctx)
	if r == null:
		n.free()
		return false
	r.add_child(n)
	n.global_position = pos
	made += 1
	return true

# A glowing cube at pos in the world (null if there is no world to put it in).
static func _bit(ctx: Node3D, pos: Vector3, size: float, c: Color, glow := 1.0) -> MeshInstance3D:
	var b := cube(size, c, glow)
	return b if _add(ctx, b, pos) else null

# A cube that rides along with unit u (orbits, walls, marks): a child of the unit.
static func _on(u: Unit, n: Node3D, local: Vector3) -> bool:
	if u == null or not is_instance_valid(u) or not u.is_inside_tree():
		n.free()
		return false
	u.add_child(n)
	n.position = local
	made += 1
	return true

# Runs fn after secs of game time (pauses with the game; dropped if ctx has gone).
static func _later(ctx: Node, secs: float, fn: Callable) -> void:
	if secs <= 0.0:
		fn.call()
		return
	if ctx == null or not is_instance_valid(ctx) or not ctx.is_inside_tree():
		return
	ctx.get_tree().create_timer(secs, false).timeout.connect(func():
		if is_instance_valid(ctx) and ctx.is_inside_tree():
			fn.call())

# Shrinks a node to nothing over secs (after `wait`), then frees it: how voxel bits blink out.
static func _shrink_out(n: Node3D, secs: float, wait := 0.0) -> void:
	var t := n.create_tween()
	if wait > 0.0:
		t.tween_interval(wait)
	t.tween_property(n, "scale", Vector3.ZERO, secs).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	t.tween_callback(n.queue_free)

# How many pieces an effect uses: fewer with Reduce motion.
static func _n(count: int) -> int:
	return maxi(1, count / 3) if Settings.reduce_motion else count

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
	blink(u, u.global_position, color_of(u), false)

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

# --- animated spell pieces (the abilities' own effects) ------------------------------------------
# Each is a handful of voxel cubes on tweens: they pop in, move, and blink out (shrink), so they read
# as part of the voxel world. Reduce motion keeps the shapes but drops the flying and most pieces.

# A ripple through the ground: hex by hex outwards from center, voxel chunks jump up and drop back.
static func shockwave(ctx: Node3D, board: Board, center: Vector2i, radius: int, c: Color, lift := 0.6, per_hex := 3) -> void:
	if not enabled or board == null:
		return
	ring(ctx, board.display_pos(center) + Vector3(0, 0.08, 0), 0.3, HEX_R * (1.0 + 1.75 * radius), c, 0.2 + 0.1 * radius)
	for cell in board.tiles:
		var d := Board.hex_distance(center, cell)
		if d > radius:
			continue
		var p := board.display_pos(cell)
		_later(ctx, d * 0.07, func(): _jolt(ctx, p, c, lift, per_hex))

static func _jolt(ctx: Node3D, p: Vector3, c: Color, lift: float, count: int) -> void:
	for i in _n(count):
		var off := Vector3(cos(i * 2.1) * 0.35, 0.12, sin(i * 2.1) * 0.35)
		var b := _bit(ctx, p + off, 0.22 - 0.03 * (i % 2), c if i != 0 else c.lightened(0.35), 1.3)
		if b == null:
			return
		if Settings.reduce_motion:
			_shrink_out(b, 0.25)
			continue
		var t := b.create_tween()
		t.tween_property(b, "global_position", p + off + Vector3(0, lift * (0.7 + 0.3 * i), 0), 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(b, "rotation", Vector3(1.5, 2.0, 0.5), 0.32)
		t.tween_property(b, "global_position", p + off, 0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_shrink_out(b, 0.15, 0.3)

# A column of cubes stacking up from the ground (fire, lava, dark power), then blowing apart.
static func pillar(ctx: Node3D, pos: Vector3, c: Color, height := 2.4, hold := 0.35) -> void:
	if not enabled:
		return
	ring(ctx, pos + Vector3(0, 0.08, 0), 0.3, 1.2, c, 0.4)
	var count := int(height / 0.3)
	for i in count:
		var y := 0.15 + i * 0.3
		var col := c.lightened(0.18 * (i % 3)) if i % 4 != 3 else Color("fff2b0")
		var size := 0.4 - 0.2 * float(i) / count
		_later(ctx, i * 0.025, func():
			for k in (1 if Settings.reduce_motion else 2):
				var off := Vector3(cos(i * 1.9 + k * PI) * 0.12, y, sin(i * 1.9 + k * PI) * 0.12)
				var b := _bit(ctx, pos + off, size, col, 1.6)
				if b == null:
					return
				b.scale = Vector3.ONE * 0.2
				b.rotation.y = i * 0.7
				var t := b.create_tween()
				t.tween_property(b, "scale", Vector3.ONE, 0.08)
				t.tween_interval(hold)
				if not Settings.reduce_motion:
					var out := Vector3(cos(i * 1.7 + k), 0.4, sin(i * 1.7 + k)) * 0.7
					t.tween_property(b, "global_position", pos + off + out, 0.25).set_ease(Tween.EASE_OUT)
					t.parallel().tween_property(b, "scale", Vector3.ZERO, 0.25)
				else:
					t.tween_property(b, "scale", Vector3.ZERO, 0.2)
				t.tween_callback(b.queue_free))

# A big block that drops out of the sky and shatters where it lands (ice, rock).
static func meteor(ctx: Node3D, pos: Vector3, c: Color, size := 0.7) -> void:
	if not enabled:
		return
	var land := func(at: Node3D):
		burst(at, pos + Vector3(0, 0.3, 0), c, 10, 1.0)
		ring(at, pos + Vector3(0, 0.08, 0), 0.3, 1.4, c.lightened(0.3), 0.35)
	if Settings.reduce_motion:
		land.call(ctx)
		return
	var b := _bit(ctx, pos + Vector3(0.5, 4.5, 0.3), size, c.lightened(0.15), 1.4)
	if b == null:
		return
	var t := b.create_tween()
	t.tween_property(b, "global_position", pos + Vector3(0, size * 0.5, 0), 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(b, "rotation", Vector3(1.2, 0.7, 0.4), 0.22)
	t.tween_callback(func():
		land.call(b)
		b.queue_free())

# Voxel spikes that jut up from each hex and sink again (ice, roots, rock).
static func spikes(ctx: Node3D, board: Board, cells: Array, c: Color, h := 0.8, secs := 0.6) -> void:
	if not enabled or board == null:
		return
	var n := 0
	for cell in cells:
		var p := board.display_pos(cell)
		var delay := 0.03 * n
		n += 1
		for i in _n(3):
			var off := Vector3(cos(i * 2.3 + n) * 0.32, 0, sin(i * 2.3 + n) * 0.32)
			var tall := h * (0.6 + 0.4 * ((i + n) % 3) / 2.0)
			var tilt := Vector3(0.25 * cos(i + n), i, 0.25 * sin(i + n))
			_later(ctx, delay, func():
				var s := _bit(ctx, p + off, 1.0, c if i != 1 else c.lightened(0.3), 1.2)
				if s == null:
					return
				s.rotation = tilt
				s.scale = Vector3(0.2, 0.02, 0.2)
				var t := s.create_tween()
				t.tween_property(s, "scale", Vector3(0.2, tall, 0.2), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				t.parallel().tween_property(s, "global_position", p + off + Vector3(0, tall * 0.5, 0), 0.1)
				t.tween_interval(secs)
				t.tween_property(s, "scale", Vector3(0.2, 0.02, 0.2), 0.15)
				t.parallel().tween_property(s, "global_position", p + off, 0.15)
				t.tween_callback(s.queue_free))

# A shot that flies from a to b in an arc (arrows, flasks, snowballs), leaving voxel crumbs behind,
# and bursts where it lands. `long` stretches it into an arrow or icicle.
static func arc_shot(ctx: Node3D, a: Vector3, b: Vector3, c: Color, height := 1.0, long := 2.4, size := 0.16) -> void:
	if not enabled:
		return
	var p := _bit(ctx, a, size, c.lightened(0.3), 1.6)
	if p == null:
		return
	p.scale = Vector3(1, 1, long)
	var dur := clampf(a.distance_to(b) / 13.0, 0.15, 0.45)
	var crumbs := {"n": 0}
	var at := func(k: float) -> Vector3: return a.lerp(b, k) + Vector3(0, height * 4.0 * k * (1.0 - k), 0)
	var step := func(k: float):
		if not is_instance_valid(p):
			return
		var pos: Vector3 = at.call(k)
		var dir: Vector3 = at.call(minf(k + 0.05, 1.0)) - pos
		p.global_position = pos
		if dir.length() > 0.001 and absf(dir.normalized().dot(Vector3.UP)) < 0.98:
			p.look_at(pos + dir)
		crumbs.n += 1
		if crumbs.n % 2 == 0 and not Settings.reduce_motion:
			var cr := _bit(p, pos, size * 0.55, c, 1.2)
			if cr != null:
				_shrink_out(cr, 0.2)
	var t := p.create_tween()
	t.tween_method(step, 0.0, 1.0, dur)
	t.tween_callback(func():
		burst(p, b, c, 6, 0.6)
		p.queue_free())

# Lightning between the points: a zigzag of small cubes that flickers and blinks out.
static func lightning(ctx: Node3D, points: Array, c: Color) -> void:
	if not enabled or points.size() < 2:
		return
	var holder := Node3D.new()
	if not _add(ctx, holder, points[0]):
		return
	for s in points.size() - 1:
		var a: Vector3 = points[s]
		var b: Vector3 = points[s + 1]
		var side := (b - a).cross(Vector3.UP).normalized()
		var steps := maxi(2, int(a.distance_to(b) / 0.2))
		for k in steps + 1:
			var f := float(k) / steps
			var jag := 0.0 if k == 0 or k == steps else sin(k * 2.7 + s * 1.3) * 0.28
			var m := cube(0.11 if k % 3 else 0.16, c.lightened(0.45) if k % 2 else c, 1.8)
			holder.add_child(m)
			m.global_position = a.lerp(b, f) + side * jag + Vector3(0, cos(k * 1.9) * 0.1, 0)
	made += holder.get_child_count() - 1   # count its pieces, not just the group
	var t := holder.create_tween()
	if not Settings.reduce_motion:
		t.tween_interval(0.06)
		t.tween_callback(holder.hide)
		t.tween_interval(0.04)
		t.tween_callback(holder.show)
	t.tween_interval(0.14)
	t.tween_property(holder, "scale", Vector3(1, 0.01, 1), 0.08)
	t.tween_callback(holder.queue_free)

# A swing: cubes appear one after another along an arc in front of u, facing `toward`, then blink out.
# arc = TAU spins all the way round.
static func slash(u: Unit, toward: Vector3, c: Color, arc := PI * 0.75, radius := 0.95, tilt := 0.4) -> void:
	if not enabled or u == null or not u.is_inside_tree():
		return
	var o := u.global_position
	var dir := toward - o
	dir.y = 0.0
	var base := atan2(dir.z, dir.x) if dir.length() > 0.01 else -PI / 2
	var n := _n(11)
	for i in n:
		var f := float(i) / maxf(n - 1, 1)
		var ang := base - arc / 2.0 + arc * f
		var p := o + Vector3(cos(ang) * radius, 0.75 + tilt * (f - 0.5), sin(ang) * radius)
		_later(u, f * 0.12, func():
			var b := _bit(u, p, 0.17 - 0.05 * absf(f - 0.5), c.lightened(0.45 * f), 1.7)
			if b != null:
				b.rotation.y = -ang
				_shrink_out(b, 0.2, 0.05))

# Cubes circling u for secs (buffs, stances, empowered hits); they ride along with it.
static func orbit(u: Unit, c: Color, secs := 1.5, count := 4, radius := 0.75, height := 1.0) -> void:
	if not enabled or u == null:
		return
	var spin := Node3D.new()
	if not _on(u, spin, Vector3(0, height, 0)):
		return
	for i in count:
		var a := TAU * i / count
		var m := cube(0.15, c if i % 2 == 0 else c.lightened(0.4), 1.6)
		m.position = Vector3(cos(a) * radius, 0.15 * sin(a * 2.0), sin(a) * radius)
		m.rotation = Vector3(0.6, a, 0.6)
		spin.add_child(m)
	spin.scale = Vector3.ONE * 0.1
	made += spin.get_child_count() - 1   # count its pieces, not just the group
	var t := spin.create_tween()
	t.tween_property(spin, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not Settings.reduce_motion:
		t.tween_property(spin, "rotation:y", TAU * secs / 0.9, secs)
	else:
		t.tween_interval(secs)
	t.tween_property(spin, "scale", Vector3.ZERO, 0.15)
	t.tween_callback(spin.queue_free)

# A spiral of cubes winding up around u from its feet to over its head (blessings, power gathering).
static func rise(u: Unit, c: Color, count := 8, secs := 0.7, radius := 0.6) -> void:
	if not enabled or u == null:
		return
	for i in _n(count):
		var a0 := TAU * i / count
		_later(u, i * 0.04, func():
			var m := cube(0.13, c if i % 2 else c.lightened(0.35), 1.6)
			if not _on(u, m, Vector3(cos(a0) * radius, 0.1, sin(a0) * radius)):
				return
			var t := m.create_tween()
			if not Settings.reduce_motion:
				t.tween_method(func(k: float):
					if is_instance_valid(m):
						var a := a0 + k * PI * 1.5
						m.position = Vector3(cos(a) * radius * (1.0 - 0.4 * k), 0.1 + 2.0 * k, sin(a) * radius * (1.0 - 0.4 * k))
						m.rotation.y = a, 0.0, 1.0, secs)
			else:
				t.tween_interval(0.3)
			t.tween_property(m, "scale", Vector3.ZERO, 0.12)
			t.tween_callback(m.queue_free))

# A shaft of light from the sky onto pos (holy heals, blessings), with motes drifting down it.
static func sky_beam(ctx: Node3D, pos: Vector3, c: Color, secs := 0.55, width := 0.7) -> void:
	if not enabled:
		return
	var col := _bit(ctx, pos + Vector3(0, 3.0, 0), 1.0, Color(c, 0.45), 1.5)
	if col == null:
		return
	col.scale = Vector3(0.01, 6.0, 0.01)
	var t := col.create_tween()
	t.tween_property(col, "scale", Vector3(width, 6.0, width), 0.1).set_ease(Tween.EASE_OUT)
	t.tween_interval(secs)
	t.tween_property(col, "scale", Vector3(0.01, 6.0, 0.01), 0.18).set_ease(Tween.EASE_IN)
	t.tween_callback(col.queue_free)
	ring(ctx, pos + Vector3(0, 0.08, 0), 0.4, 1.1, c, secs)
	for i in _n(5):
		var start := pos + Vector3(cos(i * 1.4) * width * 0.35, 2.6 + 0.3 * i, sin(i * 1.4) * width * 0.35)
		var m := _bit(ctx, start, 0.11, c.lightened(0.5), 1.8)
		if m == null:
			return
		if not Settings.reduce_motion:
			m.create_tween().tween_property(m, "global_position", Vector3(start.x, pos.y + 0.3, start.z), secs + 0.1)
		_shrink_out(m, 0.12, secs + 0.1)

# A stream of voxel fire (or frost, or poison) pouring from `from` towards `to` and spreading out.
static func breath(ctx: Node3D, from: Vector3, to: Vector3, c: Color, secs := 0.5, spread := 0.9) -> void:
	if not enabled:
		return
	var side := (to - from).cross(Vector3.UP).normalized()
	var count := _n(int(secs / 0.03))
	for i in count:
		_later(ctx, i * secs / count, func():
			var end := to + side * sin(i * 2.39) * spread + Vector3(0, cos(i * 1.7) * 0.3, 0)
			var hot := i % 3 == 0
			var b := _bit(ctx, from, 0.14, Color("fff2b0") if hot else c, 1.8 if hot else 1.4)
			if b == null:
				return
			var t := b.create_tween()
			t.tween_property(b, "global_position", end, 0.3).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(b, "scale", Vector3.ONE * 2.6, 0.3)
			t.parallel().tween_property(b, "rotation", Vector3(2.0, 1.0, 3.0), 0.3)
			t.tween_property(b, "scale", Vector3.ZERO, 0.12)
			t.tween_callback(b.queue_free))

# A lumpy cloud of translucent cubes that hangs over pos for secs, bobbing (gas, smoke, shadow).
static func cloud(ctx: Node3D, pos: Vector3, c: Color, secs := 1.5, radius := 0.9) -> void:
	if not enabled:
		return
	var holder := Node3D.new()
	if not _add(ctx, holder, pos):
		return
	for i in _n(9):
		var a := i * 2.4
		var r := radius * (0.3 + 0.7 * ((i * 7) % 5) / 4.0)
		var m := cube(0.32 + 0.06 * (i % 3), Color(c.lightened(0.12 * (i % 3)), 0.7))
		m.position = Vector3(cos(a) * r, 0.45 + 0.25 * (i % 3), sin(a) * r)
		m.rotation = Vector3(0.3 * i, 0.7 * i, 0)
		holder.add_child(m)
	holder.scale = Vector3.ONE * 0.2
	var y := holder.position.y
	made += holder.get_child_count() - 1   # count its pieces, not just the group
	var t := holder.create_tween()
	t.tween_property(holder, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if not Settings.reduce_motion:
		for k in maxi(1, int(secs / 0.6)):
			t.tween_property(holder, "position:y", y + 0.12, 0.3).set_trans(Tween.TRANS_SINE)
			t.parallel().tween_property(holder, "rotation:y", 0.4 * (k + 1), 0.6)
			t.tween_property(holder, "position:y", y, 0.3).set_trans(Tween.TRANS_SINE)
	else:
		t.tween_interval(secs)
	t.tween_property(holder, "scale", Vector3.ZERO, 0.25)
	t.tween_callback(holder.queue_free)

# Little voxel music notes floating up from u and swaying (bards).
static func notes(u: Unit, c: Color, count := 3) -> void:
	if not enabled or u == null or not u.is_inside_tree():
		return
	for i in _n(count):
		_later(u, i * 0.12, func():
			var note := Node3D.new()
			var head := cube(0.16, c, 1.6)
			var stem := cube(1.0, c.lightened(0.3), 1.6)
			stem.scale = Vector3(0.04, 0.3, 0.04)
			stem.position = Vector3(0.07, 0.15, 0)
			note.add_child(head)
			note.add_child(stem)
			var start := u.global_position + Vector3(cos(i * 2.0) * 0.5, 1.6, sin(i * 2.0) * 0.5)
			if not _add(u, note, start):
				return
			made += note.get_child_count() - 1   # count its pieces, not just the group
			var t := note.create_tween()
			if not Settings.reduce_motion:
				t.tween_method(func(k: float):
					if is_instance_valid(note):
						note.global_position = start + Vector3(sin(k * 9.0) * 0.18, k * 1.1, 0), 0.0, 1.0, 0.7)
			else:
				t.tween_interval(0.4)
			t.tween_property(note, "scale", Vector3.ZERO, 0.12)
			t.tween_callback(note.queue_free))

# A teleport: a column of cubes at pos that collapses into the middle (vanish) or flies out of it
# (appear).
static func blink(ctx: Node3D, pos: Vector3, c: Color, vanish := true) -> void:
	if not enabled:
		return
	ring(ctx, pos + Vector3(0, 0.08, 0), 1.1 if vanish else 0.2, 0.2 if vanish else 1.1, c, 0.3)
	for i in _n(10):
		var a := i * 2.2
		var y := 0.2 + 0.2 * i
		var wide := pos + Vector3(cos(a) * 0.8, y, sin(a) * 0.8)
		var mid := pos + Vector3(0, y, 0)
		var b := _bit(ctx, wide if vanish else mid, 0.15, c if i % 2 else c.darkened(0.4), 1.4)
		if b == null:
			return
		if Settings.reduce_motion:
			_shrink_out(b, 0.25)
			continue
		var t := b.create_tween()
		t.tween_property(b, "global_position", mid if vanish else wide, 0.22).set_ease(Tween.EASE_IN if vanish else Tween.EASE_OUT)
		t.parallel().tween_property(b, "rotation", Vector3(0, 3.0, 0), 0.22)
		t.tween_property(b, "scale", Vector3.ZERO, 0.1)
		t.tween_callback(b.queue_free)

# A ring of blocks that rises around u like a wall, holds, and sinks (shields, stances).
static func wall(u: Unit, c: Color, hold := 0.5, radius := 0.85) -> void:
	if not enabled or u == null:
		return
	for i in 6:
		var a := TAU * i / 6 + PI / 6
		for k in (1 if Settings.reduce_motion else 2):
			var b := cube(0.3, c if (i + k) % 2 else c.lightened(0.3), 1.2)
			var top := Vector3(cos(a) * radius, 0.18 + 0.32 * k, sin(a) * radius)
			if not _on(u, b, top - Vector3(0, 0.7, 0)):
				return
			b.rotation.y = -a
			var t := b.create_tween()
			t.tween_interval(0.03 * i)
			t.tween_property(b, "position", top, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_interval(hold)
			t.tween_property(b, "position", top - Vector3(0, 0.6, 0), 0.15).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(b, "scale", Vector3.ZERO, 0.15)
			t.tween_callback(b.queue_free)

# Motes flowing from one unit to another (life drain, mana, songs, links); they follow both.
static func stream(src: Unit, dst: Unit, c: Color, count := 6, secs := 0.4) -> void:
	if not enabled or src == null or dst == null or not src.is_inside_tree() or not dst.is_inside_tree():
		return
	for i in _n(count):
		var lift := 0.4 + 0.3 * sin(i * 1.7)
		_later(src, i * 0.05, func():
			if not is_instance_valid(dst) or not dst.is_inside_tree():
				return
			var m := _bit(src, _chest(src), 0.12, c if i % 2 else c.lightened(0.4), 1.7)
			if m == null:
				return
			var t := m.create_tween()
			t.tween_method(func(k: float):
				if is_instance_valid(m) and is_instance_valid(src) and is_instance_valid(dst):
					m.global_position = _chest(src).lerp(_chest(dst), k) + Vector3(0, lift * 4.0 * k * (1.0 - k), 0), 0.0, 1.0, secs)
			t.tween_property(m, "scale", Vector3.ZERO, 0.08)
			t.tween_callback(m.queue_free))

# A turning hex of cubes on the ground under u for secs (marks, curses, dooms); it follows u.
static func mark(u: Unit, c: Color, secs := 3.0) -> void:
	if not enabled or u == null:
		return
	var sigil := Node3D.new()
	if not _on(u, sigil, Vector3(0, 0.12, 0)):
		return
	for i in 6:
		var a := TAU * i / 6
		var m := cube(0.14, c, 1.5)
		m.position = Vector3(cos(a) * 0.62, 0, sin(a) * 0.62)
		m.rotation.y = -a
		sigil.add_child(m)
	sigil.scale = Vector3.ONE * 1.6
	made += sigil.get_child_count() - 1   # count its pieces, not just the group
	var t := sigil.create_tween()
	t.tween_property(sigil, "scale", Vector3.ONE, 0.18).set_ease(Tween.EASE_OUT)
	if not Settings.reduce_motion:
		t.tween_property(sigil, "rotation:y", secs * 1.5, secs)
	else:
		t.tween_interval(secs)
	t.tween_property(sigil, "scale", Vector3.ZERO, 0.15)
	t.tween_callback(sigil.queue_free)

# Gold coins (flat cubes) popping up out of u and spinning away (the Thief's gold).
static func coins(u: Unit, count := 4) -> void:
	if not enabled or u == null or not u.is_inside_tree():
		return
	for i in _n(count):
		var b := _bit(u, _chest(u), 0.16, Color("ffd34a"), 1.7)
		if b == null:
			return
		b.scale = Vector3(1, 1, 0.35)
		if not Settings.reduce_motion:
			var t := b.create_tween()
			t.tween_property(b, "global_position", _chest(u) + Vector3(cos(i * 1.6) * 0.6, 1.0 + 0.2 * i, sin(i * 1.6) * 0.6), 0.4).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(b, "rotation:y", 9.0, 0.4)
		_shrink_out(b, 0.15, 0.4)

# Echoing rings at pos, one after another, climbing (roars, screeches, calls).
static func rings(ctx: Node3D, pos: Vector3, c: Color, count := 3, r1 := 1.8) -> void:
	if not enabled:
		return
	for i in _n(count):
		_later(ctx, i * 0.1, func(): ring(ctx, pos + Vector3(0, 0.3 + 0.35 * i, 0), 0.3, r1, c.lightened(0.15 * i), 0.35))

# An item settling onto a unit: cubes in its colour spiral down from above its bars and flash at its
# feet; a new resonance (two elements meeting) adds climbing gold rings and a burst.
static func equip(u: Unit, c: Color, resonances := 0) -> void:
	if not enabled or u == null or not u.is_inside_tree():
		return
	var h := u.bar_height + 0.6
	for i in _n(6):
		var a0 := TAU * i / 6
		var m := _bit(u, u.global_position + Vector3(cos(a0) * 0.8, h, sin(a0) * 0.8), 0.14, c if i % 2 else c.lightened(0.4), 1.6)
		if m == null:
			return
		var t := m.create_tween()
		if not Settings.reduce_motion:
			t.tween_method(func(k: float):
				if is_instance_valid(m) and is_instance_valid(u):
					var a := a0 + k * PI
					var r := 0.7 * (1.0 - k) + 0.1
					m.global_position = u.global_position + Vector3(cos(a) * r, h * (1.0 - k) + 0.3, sin(a) * r), 0.0, 1.0, 0.35)
		t.tween_property(m, "scale", Vector3.ZERO, 0.1)
		t.tween_callback(m.queue_free)
	_later(u, 0.3, func():
		ring(u, u.global_position + Vector3(0, 0.08, 0), 0.3, 0.95, c, 0.3)
		if resonances > 0:
			rings(u, u.global_position, Color("ffe9a0"), 3, 1.3)
			burst(u, _chest(u), Color("ffe9a0"), 10, 0.9))
