# unit.gd
class_name Unit extends Node3D

@export var data: UnitData
var team := 0
var coord := Vector2i(-1, -1)   # (-1,-1) = on bench
var star := 1
var health: float
var mana := 0.0
var target: Unit
var dead := false
var cooldown := 0.0
var moving := false
# Tile-to-tile movement is stepped by combat ticks (no tweens), so it never depends on frame timing.
var move_from := Vector3.ZERO
var move_to := Vector3.ZERO
var move_progress := 0.0   # 0..1 along the current step
var letter_label: Label3D   # the placeholder capsule's name tag; units with a model don't show it
var model_view: UnitModel   # the animated model (UnitData.model), or null for the placeholder capsule
var bar_height := BAR_HEIGHT   # where the bars sit; set from the model's height and star
var _hide_in := -1.0   # seconds until a dead unit with a model disappears (its death animation plays first)
var bar_bg: Sprite3D
var bar_fill: Sprite3D
var _last_ratio := -1.0
var stat_scale := 1.0
var mana_bg: Sprite3D
var mana_fill: Sprite3D
var _last_mana_ratio := -1.0
var bonus_hp := 0.0
var bonus_dmg := 0.0
var bonus_as := 0.0
var bonus_mana := 0.0
var dmg_reduction := 0.0
var lifesteal := 0.0
var damage_dealt := 0.0   # this fight, HP actually removed from enemies (damage meter)
var damage_taken := 0.0   # this fight, HP lost

# Items live apart from the synergy bonuses above: clear_bonuses() runs every combat and must not wipe them.
const MAX_ITEMS := 3
var items: Array[ItemData] = []
var item_hp := 0.0
var item_dmg := 0.0
var item_as := 0.0
var item_mana := 0.0
var item_dr := 0.0
var item_lifesteal := 0.0
var item_icons: Node3D   # row of coloured squares above the health bar, one per item
static var _icon_tex: ImageTexture
const ICON_PX := 16
const ICON_SIZE := 0.22    # world size of one icon square
const ICON_STEP := 0.3     # spacing between icon centers
const ICON_HEIGHT := 0.28  # how far above the health bar the row sits

const STAR_MULT := {1: 1.0, 2: 1.8, 3: 3.2}
const STAR_SIZE := {1: 1.0, 2: 1.2, 3: 1.45}
@onready var board: Board = get_parent().get_parent()
const BAR_PX_W := 100
const BAR_PX_H := 10
const BAR_HEIGHT := 2.4        # bar height for the placeholder capsule; models set bar_height from their own height
const BAR_GAP := 0.35          # bars sit this far above a model's head
const RING_COLORS := [Color("6cc4ff"), Color("ff8a4c")]   # team ring at a model's feet: you, enemy
const MANA_PER_ATTACK := 10.0
const MANA_FROM_DAMAGE := 0.1   # mana per point of damage taken
const MANA_HIT_CAP := 15.0      # max mana from a single hit
const MANA_OFFSET := 0.13       # how far below the health bar the mana bar sits
const DEFAULT_ABILITY := preload("res://Scripts/ability.gd")

func max_hp() -> float:
	return (data.max_health + item_hp) * stat_scale * STAR_MULT[star] * (1.0 + bonus_hp)

func damage() -> float:
	return (data.attack_damage + item_dmg) * stat_scale * STAR_MULT[star] * (1.0 + bonus_dmg)

func _make_letter():
	if letter_label != null:
		letter_label.queue_free()
	if data == null or data.display_name.is_empty():
		return
	letter_label = Label3D.new()
	letter_label.text = data.label()
	letter_label.font_size = 128
	letter_label.pixel_size = 0.006
	letter_label.outline_size = 24
	letter_label.modulate = Color.WHITE
	letter_label.outline_modulate = Color.BLACK
	letter_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	letter_label.no_depth_test = true      # stays visible even if the capsule would block it
	letter_label.shaded = false
	letter_label.position = Vector3(0, 1.0, 0)   # middle of the capsule; match your ModelHolder offset
	add_child(letter_label)

func set_star(s: int):
	star = clampi(s, 1, 3)
	health = max_hp()
	_last_ratio = -1.0
	$ModelHolder.scale = Vector3.ONE * STAR_SIZE[star]
	if model_view != null:
		model_view.set_star(star)
		_place_bars()
	if letter_label != null:
		letter_label.text = data.label() + ("*".repeat(star - 1))

func _ready():
	_make_bar()

func _make_bar():
	var img := Image.create(BAR_PX_W, BAR_PX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)

	bar_bg = _make_bar_sprite(tex, 0)
	bar_bg.modulate = Color(0.1, 0.1, 0.1, 0.85)
	bar_bg.scale = Vector3(1.06, 1.5, 1.0)   # slightly bigger = a border

	bar_fill = _make_bar_sprite(tex, 1)
	bar_fill.modulate = Color(0.3, 0.85, 0.3)
	bar_fill.region_enabled = true
	bar_fill.region_rect = Rect2(0, 0, BAR_PX_W, BAR_PX_H)

	mana_bg = _make_bar_sprite(tex, 0)
	mana_bg.modulate = Color(0.1, 0.1, 0.1, 0.85)
	mana_bg.scale = Vector3(1.06, 1.1, 1.0)
	mana_bg.position.y = BAR_HEIGHT - MANA_OFFSET

	mana_fill = _make_bar_sprite(tex, 1)
	mana_fill.modulate = Color(0.3, 0.55, 1.0)
	mana_fill.scale = Vector3(1.0, 0.7, 1.0)
	mana_fill.region_enabled = true
	mana_fill.region_rect = Rect2(0, 0, 0.01, BAR_PX_H)
	mana_fill.position.y = BAR_HEIGHT - MANA_OFFSET

func _make_bar_sprite(tex: Texture2D, priority: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = 0.01                       # 100 px wide = 1 world unit
	s.centered = false
	s.offset = Vector2(-BAR_PX_W / 2.0, -BAR_PX_H / 2.0)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true                    # draw over the model
	s.render_priority = priority
	s.position = Vector3(0, BAR_HEIGHT, 0)
	add_child(s)
	return s

# Moves the health and mana bars to bar_height (models: just above the head at the current star).
func _place_bars():
	if model_view != null:
		bar_height = model_view.height * STAR_SIZE[star] + BAR_GAP
	if bar_bg == null:
		return
	bar_bg.position.y = bar_height
	bar_fill.position.y = bar_height
	mana_bg.position.y = bar_height - MANA_OFFSET
	mana_fill.position.y = bar_height - MANA_OFFSET

func _process(delta):
	if _hide_in > 0.0:
		_hide_in -= delta
		if _hide_in <= 0.0 and dead:
			visible = false   # the death animation has played
	if item_icons != null:
		item_icons.global_position = global_position + Vector3(0, bar_height + ICON_HEIGHT, 0)
	if data == null or bar_fill == null:
		return

	var ratio := clampf(health / max_hp(), 0.0, 1.0)
	if not is_equal_approx(ratio, _last_ratio):
		_last_ratio = ratio
		bar_fill.region_rect = Rect2(0, 0, maxf(BAR_PX_W * ratio, 0.01), BAR_PX_H)

	bar_bg.visible = not dead   # a dying model lies there without bars until it disappears
	bar_fill.visible = not dead
	if item_icons != null:
		item_icons.visible = not dead
	var has_mana := data.max_mana > 0.0 and not dead
	mana_bg.visible = has_mana
	mana_fill.visible = has_mana
	if has_mana:
		var m := clampf(mana / data.max_mana, 0.0, 1.0)
		if not is_equal_approx(m, _last_mana_ratio):
			_last_mana_ratio = m
			mana_fill.region_rect = Rect2(0, 0, maxf(BAR_PX_W * m, 0.01), BAR_PX_H)
			mana_fill.modulate = Color(0.55, 0.85, 1.0) if m >= 1.0 else Color(0.3, 0.55, 1.0)



func setup(d: UnitData, t: int):
	data = d
	team = t
	if bar_fill:
		bar_fill.modulate = Color(0.3, 0.85, 0.3) if team == 0 else Color(0.9, 0.25, 0.25)
	health = d.max_health
	var holder := get_node_or_null("ModelHolder")
	if holder == null:
		push_error("Unit was not created from unit.tscn (no ModelHolder)")
		return
	rotation.y = PI if team == 1 else 0.0   # face the other side of the board
	if d.model:
		var body := d.model.instantiate()
		holder.add_child(body)
		model_view = body as UnitModel
	if model_view != null:
		holder.get_node("MeshInstance3D").visible = false   # the placeholder capsule
		model_view.unit = self
		model_view.set_star(star)
		_place_bars()
		_make_ring()
	else:
		if team == 1:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.9, 0.25, 0.25)
			for m in holder.find_children("*", "MeshInstance3D", true, false):
				m.material_override = mat
		_make_letter()
	mana = d.start_mana

# A flat ring at a model's feet in the team colour (the capsule is painted red for enemies instead).
func _make_ring():
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.58
	torus.outer_radius = 0.7
	torus.rings = 32
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.12, 1.0)
	ring.position.y = 0.04
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = RING_COLORS[team]
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

func begin_combat():
	if data == null:
		return
	health = max_hp()
	dead = false
	target = null
	cooldown = 0.0
	moving = false
	_last_ratio = -1.0
	mana = minf(data.start_mana + bonus_mana + item_mana, data.max_mana)
	_last_mana_ratio = -1.0
	damage_dealt = 0.0
	damage_taken = 0.0

# An enemy leaving the board when its fight ends (GameManager frees it). A model still falling, or
# celebrating because the enemy side won, is left behind as a stand-in that finishes and then
# disappears. Visual only: the Unit itself is gone at once.
func leave_fight(enemy_won: bool):
	if model_view != null and visible and (dead or enemy_won) and is_inside_tree():
		var holder: Node3D = $ModelHolder
		var stand_in := Node3D.new()
		stand_in.name = "StandIn"
		board.get_parent().add_child(stand_in)
		stand_in.global_transform = global_transform
		remove_child(holder)
		stand_in.add_child(holder)
		model_view.unit = null
		var left := model_view.death_left() + 0.4
		if not dead:
			model_view.on_fight_over(true)
			left = UnitModel.VICTORY_TIME
		get_tree().create_timer(left).timeout.connect(stand_in.queue_free)
		model_view = null
	queue_free()

# won: the player won the fight; surviving units with a model celebrate (visual only).
func end_combat(won := false):
	var celebrate := won and not dead and team == 0
	moving = false
	dead = false
	visible = true
	_hide_in = -1.0
	if team == 0:
		rotation = Vector3.ZERO   # face the enemy side again
	if model_view != null:
		model_view.on_fight_over(celebrate)
	clear_bonuses()   # synergies are re-applied at the next combat start
	health = max_hp()
	target = null
	_last_ratio = -1.0
	mana = data.start_mana
	_last_mana_ratio = -1.0

# One combat tick. GameManager calls it with a fixed delta (COMBAT_TICK) in a fixed unit order,
# so the same two boards always produce the same fight.
func combat_step(delta: float):
	if dead or coord.x < 0:
		return
	if moving:
		move_progress += delta * data.move_speed
		if move_progress >= 1.0:
			position = move_to
			moving = false
		else:
			position = move_from.lerp(move_to, move_progress)
		return
	cooldown = maxf(0.0, cooldown - delta)

	if not is_instance_valid(target) or target.dead:
		target = board.nearest_enemy(self)
		if target == null:
			return

	var rng := roundi(data.attack_range)
	if Board.hex_distance(coord, target.coord) <= rng:
		_face(target)
		if data.max_mana > 0.0 and mana >= data.max_mana:
			_cast(target)
			return
		if cooldown <= 0.0:
			cooldown = attack_interval()
			if model_view != null:
				model_view.on_attack(cooldown)
			var dmg := damage()
			damage_dealt += target.take_damage(dmg)
			gain_mana(MANA_PER_ATTACK)
			var steal := lifesteal + item_lifesteal
			if steal > 0.0:
				health = minf(health + dmg * steal, max_hp())
	else:
		var next := board.next_step(coord, target.coord, rng)
		if next == Board.NO_STEP:
			return   # blocked; try again next tick
		board.claim(self, next)
		moving = true
		move_from = position
		move_to = board.grid_to_world(next)
		move_progress = 0.0
		_face_point(move_to)

# Returns the HP actually removed (after damage reduction, without overkill), for the damage meter.
func take_damage(amount: float) -> float:
	if dead:
		return 0.0
	amount *= 1.0 - minf(dmg_reduction + item_dr, 0.6)
	var removed := minf(amount, maxf(health, 0.0))
	damage_taken += removed
	health -= amount
	gain_mana(minf(amount * MANA_FROM_DAMAGE, MANA_HIT_CAP))
	if health <= 0.0:
		dead = true
		board.vacate(self)
		if model_view != null:
			model_view.on_death()   # stays visible while it falls; _process hides it after
			_hide_in = model_view.death_left() + 0.4
		else:
			visible = false
	elif model_view != null:
		model_view.on_hit()
	return removed

func _face(u: Unit):
	_face_point(u.global_position)

func _face_point(p: Vector3):
	var flat := Vector3(p.x, global_position.y, p.z)
	if flat.distance_to(global_position) > 0.01:
		look_at(flat)

func gain_mana(n: float):
	if data == null or data.max_mana <= 0.0:
		return
	mana = minf(mana + n, data.max_mana)

func clear_bonuses():
	bonus_hp = 0.0
	bonus_dmg = 0.0
	bonus_as = 0.0
	bonus_mana = 0.0
	dmg_reduction = 0.0
	lifesteal = 0.0

func attack_interval() -> float:
	return 1.0 / (data.attacks_per_second * (1.0 + bonus_as + item_as))

func can_equip() -> bool:
	return items.size() < MAX_ITEMS

# in_combat: the unit is mid-fight, so keep its current health and mana and add the boost on top.
func equip(item: ItemData, in_combat := false) -> bool:
	if item == null or dead or not can_equip():
		return false
	var old_max := max_hp()
	items.append(item)
	_recalc_items()
	if in_combat:
		health += max_hp() - old_max
		gain_mana(item.mana)
	else:
		health = max_hp()
	return true

# Replaces all items (opponent provider, save loading).
func set_items(list: Array[ItemData]) -> void:
	items = list.duplicate()
	if items.size() > MAX_ITEMS:
		items.resize(MAX_ITEMS)
	_recalc_items()
	health = minf(health, max_hp())

# Removes and returns every item (selling, merging).
func take_items() -> Array[ItemData]:
	var out: Array[ItemData] = items.duplicate()
	items.clear()
	_recalc_items()
	health = minf(health, max_hp())
	return out

func _recalc_items() -> void:
	item_hp = 0.0
	item_dmg = 0.0
	item_as = 0.0
	item_mana = 0.0
	item_dr = 0.0
	item_lifesteal = 0.0
	for it in items:
		item_hp += it.hp
		item_dmg += it.dmg
		item_as += it.attack_speed
		item_mana += it.mana
		item_dr += it.damage_reduction
		item_lifesteal += it.lifesteal
	_update_item_icons()

# One coloured square per item above the health bar, so items are visible on the board
# without the inspector. The row is top_level so it keeps facing the camera when the unit turns;
# _process moves it along with the unit.
func _update_item_icons() -> void:
	if item_icons == null:
		item_icons = Node3D.new()
		item_icons.top_level = true
		add_child(item_icons)
		if is_inside_tree():
			item_icons.global_position = global_position + Vector3(0, bar_height + ICON_HEIGHT, 0)   # _process keeps it there
	for c in item_icons.get_children():
		item_icons.remove_child(c)
		c.queue_free()
	var n := items.size()
	for i in n:
		var x := (i - (n - 1) / 2.0) * ICON_STEP
		item_icons.add_child(_icon_sprite(Color(0.05, 0.05, 0.05, 0.9), ICON_SIZE * 1.3, 1, x))   # border
		item_icons.add_child(_icon_sprite(items[i].color, ICON_SIZE, 2, x))

func _icon_sprite(color: Color, world_size: float, priority: int, x: float) -> Sprite3D:
	if _icon_tex == null:
		var img := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_icon_tex = ImageTexture.create_from_image(img)
	var s := Sprite3D.new()
	s.texture = _icon_tex
	s.pixel_size = world_size / ICON_PX
	s.modulate = color
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true    # draw over the model
	s.render_priority = priority
	s.position = Vector3(x, 0, 0)
	return s

func _ability() -> Ability:
	if data.ability != null:
		return data.ability
	return DEFAULT_ABILITY.new()

func _cast(target_unit: Unit):
	mana = 0.0
	_last_mana_ratio = -1.0
	_ability().cast(self, target_unit)
	if model_view != null:
		model_view.on_cast()
	_cast_popup()

func _cast_popup():
	var l := Label3D.new()
	l.text = "CAST"
	l.font_size = 64
	l.pixel_size = 0.01
	l.outline_size = 16
	l.modulate = Color(0.55, 0.85, 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, bar_height + 0.3, 0)
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", bar_height + 0.9, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)
