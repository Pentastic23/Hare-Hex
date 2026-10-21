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
var tween: Tween
var letter_label: Label3D
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

const STAR_MULT := {1: 1.0, 2: 1.8, 3: 3.2}
const STAR_SIZE := {1: 1.0, 2: 1.2, 3: 1.45}
@onready var board: Board = get_parent().get_parent()
const BAR_PX_W := 100
const BAR_PX_H := 10
const BAR_HEIGHT := 2.4        # world height above the unit's feet; raise if your model is taller
const MANA_PER_ATTACK := 10.0
const MANA_FROM_DAMAGE := 0.1   # mana per point of damage taken
const MANA_HIT_CAP := 15.0      # max mana from a single hit
const MANA_OFFSET := 0.13       # how far below the health bar the mana bar sits
const DEFAULT_ABILITY := preload("res://Scripts/ability.gd")

func max_hp() -> float:
	return data.max_health * stat_scale * STAR_MULT[star] * (1.0 + bonus_hp)

func damage() -> float:
	return data.attack_damage * stat_scale * STAR_MULT[star] * (1.0 + bonus_dmg)

func _make_letter():
	if letter_label != null:
		letter_label.queue_free()
	if data == null or data.display_name.is_empty():
		return
	letter_label = Label3D.new()
	letter_label.text = data.display_name.substr(0, 2).to_upper()
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
	letter_label.text = data.display_name.substr(0, 1).to_upper() + ("*".repeat(star - 1))

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

func _process(_delta):
	if data == null or bar_fill == null:
		return

	var ratio := clampf(health / max_hp(), 0.0, 1.0)
	if not is_equal_approx(ratio, _last_ratio):
		_last_ratio = ratio
		bar_fill.region_rect = Rect2(0, 0, maxf(BAR_PX_W * ratio, 0.01), BAR_PX_H)

	var has_mana := data.max_mana > 0.0
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
	if d.model:
		holder.add_child(d.model.instantiate())
	if team == 1:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.25, 0.25)
		for m in holder.find_children("*", "MeshInstance3D", true, false):
			m.material_override = mat
	_make_letter()
	mana = d.start_mana

func begin_combat():
	if data == null:
		return
	health = max_hp()
	dead = false
	target = null
	cooldown = 0.0
	moving = false
	_last_ratio = -1.0
	mana = minf(data.start_mana + bonus_mana, data.max_mana)
	_last_mana_ratio = -1.0

func end_combat():
	if tween:
		tween.kill()
	moving = false
	dead = false
	visible = true
	health = max_hp()
	target = null
	_last_ratio = -1.0
	mana = data.start_mana
	_last_mana_ratio = -1.0

func combat_step(delta: float):
	if dead or moving or coord.x < 0:
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
			var dmg := damage()
			target.take_damage(dmg)
			gain_mana(MANA_PER_ATTACK)
			if lifesteal > 0.0:
				health = minf(health + dmg * lifesteal, max_hp())
	else:
		var next := board.next_step(coord, target.coord, rng)
		if next == Board.NO_STEP:
			return   # blocked; try again next tick
		board.claim(self, next)
		moving = true
		_face_point(board.grid_to_world(next))
		tween = create_tween()
		tween.tween_property(self, "position", board.grid_to_world(next), 1.0 / data.move_speed)
		tween.finished.connect(func(): moving = false)

func take_damage(amount: float):
	if dead:
		return
	amount *= 1.0 - minf(dmg_reduction, 0.6)
	health -= amount
	gain_mana(minf(amount * MANA_FROM_DAMAGE, MANA_HIT_CAP))
	if health <= 0.0:
		dead = true
		visible = false
		board.vacate(self)

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
	return 1.0 / (data.attacks_per_second * (1.0 + bonus_as))

func _ability() -> Ability:
	if data.ability != null:
		return data.ability
	return DEFAULT_ABILITY.new()

func _cast(target_unit: Unit):
	mana = 0.0
	_last_mana_ratio = -1.0
	_ability().cast(self, target_unit)
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
	l.position = Vector3(0, BAR_HEIGHT + 0.3, 0)
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", BAR_HEIGHT + 0.9, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)
