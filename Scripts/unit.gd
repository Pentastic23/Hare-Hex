# unit.gd
class_name Unit extends Node3D

@export var data: UnitData
var team := 0
var coord := Vector2i(-1, -1)   # (-1,-1) = on bench
var uid := -1          # this unit's id on its board (Board.make_unit); the lobby protocol names units by it
var source_uid := -1   # a lobby fight copy (Arena): the uid of the seat unit it was copied from...
var source_seat := -1  # ...and that seat (-1: not a copy, or a PvE enemy)
# Which team the viewer plays (the visible board's colours: yours blue and green, theirs orange and red).
# 1 while a lobby client watches a fight from the away side; game logic never reads it.
static var viewer_team := 0
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
@onready var bar_bg: Sprite3D = $Bars/BarBg   # the bars are nodes in unit.tscn, sharing one white texture
@onready var bar_fill: Sprite3D = $Bars/BarFill
@onready var shield_fill: Sprite3D = $Bars/ShieldFill   # white overlay on the health bar: the shield left, as a share of max HP
var _last_shield := -1.0
var _last_ratio := -1.0
var stat_scale := 1.0
@onready var mana_bg: Sprite3D = $Bars/ManaBg
@onready var mana_fill: Sprite3D = $Bars/ManaFill
@onready var ring: MeshInstance3D = $Ring   # the team ring at a model's feet (hidden for the capsule)
var _last_mana_ratio := -1.0
var bonus_hp := 0.0
var bonus_dmg := 0.0
var bonus_as := 0.0
var bonus_mana := 0.0
var dmg_reduction := 0.0
var lifesteal := 0.0
# Synergy mechanics (docs/synergies-v2.md), set by apply_synergy and cleared with the bonuses above.
var shield_pct := 0.0   # shield at the start of a fight, share of max HP
var regen := 0.0        # share of max HP healed per second
var ramp := 0.0         # attack speed gained per attack
var ramp_max := 0       # stacks
var crit_every := 0     # every Nth attack deals double (0 = never)
var execute := 0.0      # kill a target left below this share of its max HP
var revive := 0.0       # once per fight, a killing blow leaves this share of max HP
var burn := 0.0         # attacks burn the target for this share of its max HP per second
var chill := 0.0        # attacks cut the target's attack speed by this much
var dodge_every := 0    # every Nth attack against this unit misses (0 = never)
var curse := 0.0        # attacks make the target take this much more damage
var range_bonus := 0    # tiles
var kill_heal := 0.0    # share of max HP healed on a kill
# Per-fight state of those mechanics (reset in _reset_fight_state). All stepped by the fixed combat
# tick, so fights stay deterministic.
var shield := 0.0
var revived := false
var ramp_stacks := 0
var attacks_made := 0
var attacks_taken := 0
var burn_dps := 0.0
var burn_left := 0.0
var burn_by: Unit
var chill_on := 0.0
var chill_left := 0.0
var curse_on := 0.0
var curse_left := 0.0
const BURN_TIME := 3.0
const CHILL_TIME := 2.0
const CURSE_TIME := 3.0
const CHILL_CAP := 0.8
# Abilities (abilities.gd): crowd control, timed buffs, ability shields and the later hits of a cast.
# All stepped by the combat tick in _tick_effects; cleared between fights.
var stun_left := 0.0      # no attacks, moves or mana
var silence_left := 0.0   # no mana
var blind_hits := 0       # this many of its next attacks miss
var taunt_by: Unit        # must target this unit while taunt_left runs
var taunt_left := 0.0
var cast_lock := 0.0      # casting: no attacks or moves
var buffs := {}           # source -> [stat ("as", "dmg", "dr", "vamp", "regen"), amount, seconds left]
var ab_shield := 0.0      # the part of `shield` from an ability; it runs out
var ab_shield_left := 0.0
var ab_shield_heals := false   # Little Prayer: whatever is left heals when it runs out
var queued: Array = []    # [seconds left, Callable]: the later hits of multi-hit casts
var next_attack_stun := 0.0    # Bamboo Calm
var untargetable_left := 0.0   # can't be picked as a target (attacks, single-target abilities); areas still hit
var empower_hits := 0     # this many next attacks deal empower_dmg more (Hare's Hop, Moonlit Hunt)
var empower_dmg := 0.0
var empower_crit := false # ...and always crit
var empower_after_stealth := false   # Moonlit Hunt: only once the unit can be targeted again
var move_rate := 0.0      # steps per second for a leap or charge (0 = its own move_speed)
var thorns := 0.0         # attackers take this much per hit while thorns_left runs (Rune Ward)
var thorns_left := 0.0
var summoned := false     # a temporary unit from an ability: no traits or items, gone when the fight ends
var summons: Array[Unit] = []   # what this unit has summoned this fight
var on_death: Callable    # runs once when it dies (the Pact Demon's explosion)
# chunk 4
var link_to: Unit         # Loyal Guard: half the damage this unit takes goes to link_to instead
var link_left := 0.0
var parry_left := 0.0     # Riposte: attacks against it are parried and countered for parry_dmg
var parry_dmg := 0.0
var doom_left := 0.0      # Doom: when it runs out, doom_by deals doom_dmg; passes on if this unit dies first
var doom_dmg := 0.0
var doom_by: Unit
var root_left := 0.0      # rooted: can attack but not move
var charm_left := 0.0     # charmed: attacks its own side (see foe_team)
var charm_by: Unit
var raised_left := 0.0    # Army of the Dead: back for this long, then falls again
var army_used := false    # the Deathlord raises the dead once per fight
var erupt_dmg := 0.0      # Molten Shell: when its ability shield breaks or runs out, adjacent enemies take this
var nova_left := 0.0      # Sunfire Nova: while it runs, allies heal 10% of the burn damage this unit deals
var nova_pool := 0.0
var _charm_fx: Node3D     # the charm's sigil and thread (visual only)
const CHARM_COLOR := Color("d98cff")
var damage_dealt := 0.0   # this fight, HP actually removed from enemies (damage meter)
var damage_taken := 0.0   # this fight, HP lost

# Items live apart from the synergy bonuses above: clear_bonuses() runs every combat and must not wipe them.
const MAX_ITEMS := 3
var items: Array[ItemData] = []
var item_stacks := {}   # bound items (items v2): item id -> stacks, grown each fight this unit survives
var item_hp := 0.0
var item_dmg := 0.0
var item_as := 0.0
var item_mana := 0.0
var item_dr := 0.0
var item_lifesteal := 0.0
var item_icons: Node3D   # row of item icons above the health bar, one per item
static var _icon_tex: ImageTexture   # plain white square (items without an icon)
const ICON_PX := 16
const ICON_SIZE := 0.6     # world size of one item icon (readable, a row of 3 stays about one tile wide)
const ICON_STEP := 0.58    # spacing between item icons
const ICON_HEIGHT := 0.45  # how far above the health bar the row sits (its middle)

const STAR_MULT := {1: 1.0, 2: 1.8, 3: 3.2}
const FIVE_COST_3STAR := 5.0   # a 3-star 5-cost is meant to win fights on its own: x5 instead of x3.2

# HP and damage multiplier for a star level (and cost: 3-star 5-costs get FIVE_COST_3STAR).
static func star_mult(star: int, cost: int) -> float:
	if star >= 3 and cost >= 5:
		return FIVE_COST_3STAR
	return STAR_MULT[clampi(star, 1, 3)]
const STAR_SIZE := {1: 1.0, 2: 1.2, 3: 1.45}
@onready var board: Board = get_parent().get_parent()
const BAR_PX_W := 100
const BAR_PX_H := 10
const BAR_HEIGHT := 2.4        # bar height for the placeholder capsule; models set bar_height from their own height
const BAR_GAP := 0.35          # bars sit this far above a model's head
const RING_COLORS := [Color("6cc4ff"), Color("ff8a4c")]   # team ring at a model's feet: you, enemy
const RING_MATS := [preload("res://tres/ring_you.tres"), preload("res://tres/ring_enemy.tres")]   # shared by every unit
const RING_CHARM := preload("res://tres/ring_charm.tres")
const RING_MESH := preload("res://tres/ring_mesh.tres")
const BAR_TEX := preload("res://textures/ui/bar_white.png")

static func bar_texture() -> Texture2D:
	return BAR_TEX
const MANA_PER_ATTACK := 10.0
const MANA_FROM_DAMAGE := 0.1   # mana per point of damage taken
const MANA_HIT_CAP := 15.0      # max mana from a single hit
const MANA_OFFSET := 0.13       # how far below the health bar the mana bar sits
const DEFAULT_ABILITY := preload("res://Scripts/ability.gd")

func max_hp() -> float:
	return (data.max_health + item_hp) * stat_scale * star_mult(star, data.cost) * (1.0 + bonus_hp)

func damage() -> float:
	return (data.attack_damage + item_dmg) * stat_scale * star_mult(star, data.cost) * damage_bonus()

# 1 + the damage bonus from synergies, items and ability buffs (attacks and ability damage).
func damage_bonus() -> float:
	return 1.0 + bonus_dmg + buff_total("dmg")

func omnivamp() -> float:
	return lifesteal + item_lifesteal + buff_total("vamp")

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
	_update_star_mark()

# Moves the health and mana bars to bar_height (models: just above the head at the current star).
func _place_bars():
	if model_view != null:
		bar_height = model_view.height * STAR_SIZE[star] + BAR_GAP
	if bar_bg == null:
		return
	bar_bg.position.y = bar_height
	bar_fill.position.y = bar_height
	shield_fill.position.y = bar_height
	mana_bg.position.y = bar_height - MANA_OFFSET
	mana_fill.position.y = bar_height - MANA_OFFSET
	_update_star_mark()

# The star level as little stars at the left end of the health bar (silver, silver, gold), so a unit's
# star reads on the board at a glance. A child of Bars, so it hides with them.
const STAR_MARK_COLORS := {1: Color("aab3c8"), 2: Color("dfe6f2"), 3: Color("f2c14e")}
var star_mark: Label3D

func _update_star_mark() -> void:
	if bar_bg == null or data == null:
		return
	if star_mark == null:
		star_mark = Label3D.new()
		star_mark.name = "StarMark"
		star_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star_mark.no_depth_test = true
		star_mark.shaded = false
		star_mark.render_priority = 3
		star_mark.outline_render_priority = 2
		star_mark.pixel_size = 0.005
		star_mark.font_size = 34
		star_mark.outline_size = 10
		star_mark.outline_modulate = Color(0.05, 0.05, 0.08, 0.95)
		star_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		star_mark.offset = Vector2(-112, 2)   # just left of the bar (pixels at pixel_size: the bar is 100 px of 0.01 wide)
		$Bars.add_child(star_mark)
	star_mark.text = "★".repeat(star)
	star_mark.modulate = STAR_MARK_COLORS[star]
	star_mark.position.y = bar_height

func _process(delta):
	if _charm_fx != null:
		_update_charm_fx(delta)
	_update_status(delta)
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
	var sh := clampf(shield / max_hp(), 0.0, 1.0) if not dead else 0.0
	if not is_equal_approx(sh, _last_shield):
		_last_shield = sh
		shield_fill.visible = sh > 0.0
		shield_fill.region_rect = Rect2(0, 0, maxf(BAR_PX_W * sh, 0.01), BAR_PX_H)
	var base_col := Color(0.3, 0.85, 0.3) if mine() else Color(0.9, 0.25, 0.25)
	bar_fill.modulate = base_col.lerp(Color(1.0, 0.55, 0.1), 0.6) if burn_left > 0.0 else base_col   # burning: orange tint
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
		bar_fill.modulate = Color(0.3, 0.85, 0.3) if mine() else Color(0.9, 0.25, 0.25)
	health = d.max_health
	var holder := get_node_or_null("ModelHolder")
	if holder == null:
		push_error("Unit was not created from unit.tscn (no ModelHolder)")
		return
	face_rest()
	var b := get_parent().get_parent() as Board if get_parent() != null else null
	if d.model and (b == null or b.visual):   # the lobby server's hidden boards skip models (visual only)
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
		if not mine():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.9, 0.25, 0.25)
			for m in holder.find_children("*", "MeshInstance3D", true, false):
				m.material_override = mat
		_make_letter()
	mana = d.start_mana

# On the viewer's side (blue ring, green bar)?
# Your own units (bench and board: they have a uid and aren't a lobby fight's copy) are always yours, even
# while you watch a lobby fight from the away side (viewer_team 1); everything else goes by team.
func mine() -> bool:
	if team == 0 and uid >= 0 and source_uid < 0:
		return true
	return team == viewer_team

# The flat ring at a model's feet (a node in unit.tscn) in the team colour, a shared material (the
# capsule is painted red for enemies instead).
func _make_ring():
	ring.visible = true
	ring.material_override = RING_MATS[0 if mine() else 1]

# Hovering a trait in the Synergies tab lights up the rings of your units that have it (synergy_panel.gd):
# gold and a little bigger. Visual only.
const RING_HIGHLIGHT := preload("res://tres/ring_highlight.tres")
var highlighted := false

func set_highlight(on: bool) -> void:
	if highlighted == on or ring == null or not ring.visible:
		return
	highlighted = on
	ring.material_override = RING_HIGHLIGHT if on else (RING_CHARM if charm_left > 0.0 else RING_MATS[0 if mine() else 1])
	ring.scale = Vector3.ONE * (1.25 if on else 1.0)

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
	_reset_fight_state()
	shield = shield_pct * max_hp()
	face_board()   # turn from the camera to the fight

# Out of a fight your units (bench and board) look at the camera; the other side's look across the board.
func face_rest():
	if not mine():
		face_board()
		return
	var b := get_parent().get_parent() as Board if get_parent() != null else null
	rotation = Vector3(0.0, 0.0 if b != null and b.view_flipped else PI, 0.0)   # world +Z either way

# Facing the other side of the board (in the Units node's space): how fights start.
func face_board():
	rotation = Vector3(0.0, PI if team == 1 else 0.0, 0.0)

# Clears burns, chills, curses, shields, ramp and counters between fights.
func _reset_fight_state():
	shield = 0.0
	revived = false
	ramp_stacks = 0
	attacks_made = 0
	attacks_taken = 0
	burn_dps = 0.0
	burn_left = 0.0
	burn_by = null
	chill_on = 0.0
	chill_left = 0.0
	curse_on = 0.0
	curse_left = 0.0
	stun_left = 0.0
	silence_left = 0.0
	blind_hits = 0
	taunt_by = null
	taunt_left = 0.0
	cast_lock = 0.0
	buffs.clear()
	ab_shield = 0.0
	ab_shield_left = 0.0
	ab_shield_heals = false
	queued.clear()
	next_attack_stun = 0.0
	untargetable_left = 0.0
	empower_hits = 0
	empower_dmg = 0.0
	empower_crit = false
	empower_after_stealth = false
	move_rate = 0.0
	thorns = 0.0
	thorns_left = 0.0
	summons.clear()
	link_to = null
	link_left = 0.0
	parry_left = 0.0
	doom_left = 0.0
	doom_by = null
	root_left = 0.0
	if charm_left > 0.0:
		charm_left = 0.0
		_show_charm(false)
	charm_by = null
	raised_left = 0.0
	army_used = false
	erupt_dmg = 0.0
	nova_left = 0.0
	nova_pool = 0.0

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
	if not dead and team == 0:
		grow_bound_items()   # survived the fight
	moving = false
	dead = false
	visible = true
	_hide_in = -1.0
	face_rest()   # back to the camera
	if model_view != null:
		model_view.on_fight_over(celebrate)
	clear_bonuses()   # synergies are re-applied at the next combat start
	_reset_fight_state()
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
	_tick_effects(delta)
	if dead:
		return   # burned out
	if moving:
		move_progress += delta * (move_rate if move_rate > 0.0 else data.move_speed)
		if move_progress >= 1.0:
			position = move_to
			moving = false
			move_rate = 0.0
		else:
			position = move_from.lerp(move_to, move_progress)
		return
	if stun_left > 0.0 or cast_lock > 0.0:
		return   # stunned or casting (both counted down in _tick_effects)
	cooldown = maxf(0.0, cooldown - delta)

	if taunt_left > 0.0 and charm_left <= 0.0 and is_instance_valid(taunt_by) and not taunt_by.dead and taunt_by.coord.x >= 0:
		target = taunt_by
	if is_instance_valid(target) and target.untargetable_left > 0.0:
		target = null   # it vanished: pick another
	if not is_instance_valid(target) or target.dead:
		target = board.nearest_enemy(self)
		if target == null:
			return

	var rng := roundi(data.attack_range) + range_bonus
	if Board.hex_distance(coord, target.coord) <= rng:
		_face(target)
		if data.max_mana > 0.0 and mana >= data.max_mana and charm_left <= 0.0:   # charmed units don't cast
			_cast(target)
			return
		if cooldown <= 0.0:
			cooldown = attack_interval()
			if model_view != null:
				model_view.on_attack(cooldown)
			_attack(target)
	else:
		if root_left > 0.0:
			return   # rooted: can't step
		var next := board.next_step(coord, target.coord, rng)
		if next == Board.NO_STEP:
			return   # blocked; try again next tick
		board.claim(self, next)
		moving = true
		move_from = position
		move_to = board.grid_to_world(next)
		move_progress = 0.0
		_face_point(_world(move_to))

# One attack on `t`: crits, dodges, damage, omnivamp, then the on-hit effects (burn, chill, curse,
# execute) and kill heals. Part of the fixed combat tick.
# fixed >= 0: a strike from an ability (Monkey Barrage) with that damage; it counts as an attack for
# the on-hit effects but gives no mana.
func _attack(t: Unit, fixed := -1.0):
	attacks_made += 1
	if fixed < 0.0:
		gain_mana(MANA_PER_ATTACK)
	if ramp > 0.0 and ramp_stacks < ramp_max:
		ramp_stacks += 1
	if blind_hits > 0:
		blind_hits -= 1
		t._popup("MISS", Color(0.8, 0.85, 1.0))
		return
	if t.dodges_next():
		t._popup("MISS", Color(0.8, 0.85, 1.0))
		return
	if t.parry_left > 0.0:
		t._popup("PARRY", Color(0.95, 0.9, 0.6))
		Abilities.hit(t, self, t.parry_dmg)   # Riposte: no damage, a counter instead
		return
	var dmg := fixed if fixed >= 0.0 else damage()
	var crit := crit_every > 0 and attacks_made % crit_every == 0
	if fixed < 0.0:
		Sfx.play(&"swing")
	if empower_hits > 0 and not (empower_after_stealth and untargetable_left > 0.0):
		empower_hits -= 1
		dmg += empower_dmg
		crit = crit or empower_crit
	if crit:
		dmg *= 2.0
	Sfx.play(&"crit" if crit else &"hit")
	damage_dealt += t.take_damage(dmg, self, true)
	var steal := omnivamp()
	if steal > 0.0:
		health = minf(health + dmg * steal, max_hp())
	if next_attack_stun > 0.0 and not t.dead:
		t.apply_stun(next_attack_stun)
		next_attack_stun = 0.0
	if not t.dead:
		if burn > 0.0:
			t.apply_burn(burn * t.max_hp(), self)
		if chill > 0.0:
			t.apply_chill(chill)
		if curse > 0.0:
			t.apply_curse(curse)
		if execute > 0.0 and t.health < t.max_hp() * execute:
			damage_dealt += t.take_damage(t.health + t.shield, self, false, true)
	if t.dead and kill_heal > 0.0:
		health = minf(health + max_hp() * kill_heal, max_hp())

# Counts an attack aimed at this unit; true when it misses (Trickster: every Nth attack).
func dodges_next() -> bool:
	attacks_taken += 1
	return dodge_every > 0 and attacks_taken % dodge_every == 0

func apply_burn(dps: float, by: Unit, secs := BURN_TIME):
	burn_dps = maxf(burn_dps, dps) if burn_left > 0.0 else dps
	burn_left = maxf(burn_left, secs)
	burn_by = by

func apply_chill(amount: float, secs := CHILL_TIME):
	chill_on = minf(maxf(chill_on, amount), CHILL_CAP)
	chill_left = maxf(chill_left, secs)

func apply_curse(amount: float, secs := CURSE_TIME):
	curse_on = maxf(curse_on, amount)
	curse_left = maxf(curse_left, secs)

# Crowd control from abilities: the same kind doesn't stack, the longer one wins.
func apply_stun(secs: float):
	if not dead:
		stun_left = maxf(stun_left, secs)

func apply_silence(secs: float):
	silence_left = maxf(silence_left, secs)

func apply_blind(hits: int):
	blind_hits = maxi(blind_hits, hits)

func apply_taunt(by: Unit, secs: float):
	taunt_by = by
	taunt_left = maxf(taunt_left, secs)
	target = by

# A timed buff from an ability; casting the same one again refreshes it instead of stacking.
func add_buff(source: String, stat: String, amount: float, secs: float):
	buffs[source] = [stat, amount, secs]

func buff_total(stat: String) -> float:
	var sum := 0.0
	for b in buffs.values():
		if b[0] == stat:
			sum += b[1]
	return sum

# A shield from an ability that runs out after secs; a new one replaces it (the bigger amount stays).
func add_timed_shield(amount: float, secs: float, heals := false):
	shield -= ab_shield
	ab_shield = maxf(amount, ab_shield)
	shield += ab_shield
	ab_shield_left = secs
	ab_shield_heals = heals

# Heals up to max HP; returns the HP restored.
func heal(amount: float) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var before := health
	health = minf(health + amount, max_hp())
	return health - before

# Leap, teleport or charge to tile c: the tile is claimed now, and the model flies there in secs
# (stepped by the combat tick like a normal step, just faster).
func leap_to(c: Vector2i, secs := 0.25):
	if c == coord or root_left > 0.0:
		return
	Vfx.burst(self, global_position + Vector3(0, 0.4, 0), Vfx.color_of(self), 6, 0.5)
	Vfx.ring(self, board.display_pos(c) + Vector3(0, 0.08, 0), 0.3, 0.9, Vfx.color_of(self), 0.4)
	board.claim(self, c)
	moving = true
	move_from = position
	move_to = board.grid_to_world(c)
	move_progress = 0.0
	move_rate = 1.0 / secs
	_face_point(_world(move_to))
	if board.runner != null:   # it dashed out of reach: whoever was attacking it picks a target again
		for other in board.runner.combatants:
			if other != self and is_instance_valid(other) and other.target == self:
				other.target = null

# Runs fn after secs (the later hits of a multi-hit cast); a delay of 0 runs it now.
func queue_action(secs: float, fn: Callable):
	if secs <= 0.0:
		fn.call()
	else:
		queued.append([secs, fn])

# Regen, burn damage, the chill / curse timers and the ability timers, once per combat tick.
func _tick_effects(delta: float):
	var regen_now := regen + buff_total("regen")
	if regen_now > 0.0:
		health = minf(health + max_hp() * regen_now * delta, max_hp())
	if burn_left > 0.0:
		burn_left -= delta
		var by: Unit = burn_by if is_instance_valid(burn_by) else null
		var removed := take_damage(burn_dps * delta, by)
		if by != null:
			by.damage_dealt += removed
			if by.nova_left > 0.0:
				by.nova_pool += removed   # Sunfire Nova heals its side from it
	if chill_left > 0.0:
		chill_left -= delta
		if chill_left <= 0.0:
			chill_on = 0.0
	if curse_left > 0.0:
		curse_left -= delta
		if curse_left <= 0.0:
			curse_on = 0.0
	stun_left = maxf(0.0, stun_left - delta)
	silence_left = maxf(0.0, silence_left - delta)
	untargetable_left = maxf(0.0, untargetable_left - delta)
	thorns_left = maxf(0.0, thorns_left - delta)
	root_left = maxf(0.0, root_left - delta)
	parry_left = maxf(0.0, parry_left - delta)
	if link_left > 0.0:
		link_left -= delta
		if link_left <= 0.0:
			link_to = null
	if charm_left > 0.0:
		charm_left -= delta
		if charm_left <= 0.0:
			charm_left = 0.0
			charm_by = null
			target = null
			_popup("FREED", CHARM_COLOR)
			_show_charm(false)
	if nova_left > 0.0:
		nova_left -= delta
		if nova_pool > 0.0:
			for a in Abilities.allies(self):
				a.heal(nova_pool * 0.1)
			nova_pool = 0.0
	if doom_left > 0.0:
		doom_left -= delta
		if doom_left <= 0.0001:
			doom_left = 0.0
			var dby: Unit = doom_by if is_instance_valid(doom_by) else null
			Vfx.burst(self, global_position + Vector3(0, 1.0, 0), Color("b0306a"), 12, 1.0)
			Vfx.pillar(self, global_position, Color("b0306a"), 2.7, 0.2)
			var removed := take_damage(doom_dmg, dby)
			if dby != null:
				dby.damage_dealt += removed
			if dead:
				return
	if raised_left > 0.0:
		raised_left -= delta
		if raised_left <= 0.0001:
			health = 0.0
			_fall()   # Army of the Dead ends
			return
	cast_lock = maxf(0.0, cast_lock - delta)
	if taunt_left > 0.0:
		taunt_left -= delta
		if taunt_left <= 0.0:
			taunt_by = null
	for source in buffs.keys():
		buffs[source][2] -= delta
		if buffs[source][2] <= 0.0:
			buffs.erase(source)
	if ab_shield_left > 0.0:
		ab_shield_left -= delta
		if ab_shield_left <= 0.0:
			var left := minf(ab_shield, shield)
			shield -= left
			ab_shield = 0.0
			if ab_shield_heals:
				heal(left)
			if erupt_dmg > 0.0:
				_erupt()
	if not queued.is_empty():
		var due: Array = []
		for q in queued:
			q[0] -= delta
			if q[0] <= 0.0001:
				due.append(q)
		for q in due:
			queued.erase(q)
			if not dead:
				q[1].call()

# Returns the damage actually taken (after curse and damage reduction, shield included, without
# overkill), for the damage meter. by: the attacker (or burner); attack: a hit (gives mana, flinches);
# pierce: ignores curse and damage reduction (executes). A killing blow is survived once with revive.
func take_damage(amount: float, by: Unit = null, attack := false, pierce := false) -> float:
	if dead:
		return 0.0
	if not pierce:
		# synergies and items share the 60% cap; ability buffs (Shell Up) reduce what is left
		amount *= (1.0 + curse_on) * (1.0 - minf(dmg_reduction + item_dr, 0.6)) * (1.0 - minf(buff_total("dr"), 0.9))
	if attack:
		gain_mana(minf(amount * MANA_FROM_DAMAGE, MANA_HIT_CAP))
	if link_left > 0.0 and is_instance_valid(link_to) and not link_to.dead and link_to != self:
		var share := amount * 0.5   # Loyal Guard: the Paladin takes half (through its own armour and shield)
		amount -= share
		link_to.take_damage(share, by)
	var absorbed := minf(shield, amount)
	shield -= absorbed
	ab_shield = maxf(0.0, ab_shield - absorbed)   # ability shields are used up first
	if erupt_dmg > 0.0 and ab_shield <= 0.0:
		_erupt()   # Molten Shell broke
	amount -= absorbed
	var removed := absorbed + minf(amount, maxf(health, 0.0))
	damage_taken += removed
	if attack and thorns_left > 0.0 and is_instance_valid(by) and not by.dead:
		damage_dealt += by.take_damage(thorns, self)   # not an attack, so thorns never bounce back
	health -= amount
	if health <= 0.0:
		if revive > 0.0 and not revived:
			revived = true
			health = max_hp() * revive
			burn_left = 0.0
			_popup("REVIVE", Color(0.75, 1.0, 0.75))
			return removed
		_fall()
	elif model_view != null and attack:
		model_view.on_hit()
	return removed

# Dies now (no revive): leaves its tile, passes on a Doom, runs on_death, then the model falls.
func _fall():
	dead = true
	Sfx.play(&"death")
	raised_left = 0.0
	board.vacate(self)
	if charm_left > 0.0:
		charm_left = 0.0
		_show_charm(false)
	if doom_left > 0.0:
		Abilities.pass_doom(self)
	if on_death.is_valid():
		on_death.call()
	if model_view != null:
		model_view.on_death()   # stays visible while it falls; _process hides it after
		_hide_in = model_view.death_left() + 0.4
	else:
		visible = false

# Molten Shell: the shield broke or ran out; adjacent enemies take what it started as, and burn.
func _erupt():
	var d := erupt_dmg
	erupt_dmg = 0.0
	Vfx.pillar(self, global_position, Color("ff6a1f"), 2.1, 0.2)
	Vfx.shockwave(self, board, coord, 1, Color("ff6a1f"), 0.6, 2)
	for e in Abilities.enemies_within(self, coord, 1):
		Abilities.hit(self, e, d)
		e.apply_burn(0.03 * e.max_hp(), self)

# The side this unit attacks: the other team, or its own while charmed.
func foe_team() -> int:
	return team if charm_left > 0.0 else 1 - team

func apply_root(secs: float):
	root_left = maxf(root_left, secs)

# Moonlit Charm: for secs this unit attacks its own side (it doesn't cast). Marked as hexed.
func apply_charm(by: Unit, secs: float):
	if dead:
		return
	var fresh := charm_left <= 0.0
	charm_left = maxf(charm_left, secs)
	charm_by = by
	target = null
	if fresh:
		_popup("CHARMED", CHARM_COLOR)
		_show_charm(true)

# The hexed look (visual only): a turning pink-violet hex sigil above it, its team ring turns
# pink-violet, and a faint thread runs to the Faerie Queen. Reduce motion: the sigil stands still.
func _show_charm(on: bool):
	if ring != null and ring.visible:
		ring.material_override = RING_CHARM if on else RING_MATS[0 if mine() else 1]
	if _charm_fx != null:
		_charm_fx.queue_free()
		_charm_fx = null
	if not on or not is_inside_tree():
		return
	_charm_fx = Node3D.new()
	add_child(_charm_fx)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = CHARM_COLOR
	mat.no_depth_test = true
	mat.render_priority = 3
	var sigil := MeshInstance3D.new()
	sigil.name = "Sigil"
	var hexm := CylinderMesh.new()
	hexm.top_radius = 0.3
	hexm.bottom_radius = 0.3
	hexm.height = 0.06
	hexm.radial_segments = 6
	hexm.rings = 1
	sigil.mesh = hexm
	sigil.material_override = mat
	sigil.rotation.x = PI / 2.0   # stands up like a coin, facing the camera side
	sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charm_fx.add_child(sigil)
	var tmat := mat.duplicate() as StandardMaterial3D
	tmat.albedo_color = Color(CHARM_COLOR, 0.55)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var thread := MeshInstance3D.new()
	thread.name = "Thread"
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 1.0)
	thread.mesh = box
	thread.material_override = tmat
	thread.top_level = true
	thread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charm_fx.add_child(thread)

# Status marks (visual only), read from the unit's state each frame:
# stunned (stars circling the head), rooted (vines ring), silenced (a violet cross), taunted (a red
# "!"), blinded (a grey cloud), doomed (a countdown), guarded by a Paladin (a gold thread), parrying
# (crossed blades), thorns (a spiked ring), hidden (a dark ring), raised (a pale ring), buffed (a ring
# in the buff's colour) and an ability shield (a bubble). Reduce motion: nothing turns.
var _status: Node3D
var _status_t := 0.0
const BUFF_COLORS := {"as": Color("ffe066"), "dmg": Color("ff6b5a"), "dr": Color("6cb4ff"), "vamp": Color("d0304a"), "regen": Color("7dff9a")}

func _update_status(delta: float):
	if not Vfx.enabled:
		return
	var active := not dead and (stun_left > 0.0 or root_left > 0.0 or silence_left > 0.0 or taunt_left > 0.0 \
		or blind_hits > 0 or doom_left > 0.0 or link_left > 0.0 or parry_left > 0.0 or thorns_left > 0.0 \
		or untargetable_left > 0.0 or raised_left > 0.0 or not buffs.is_empty() or ab_shield > 0.0)
	if not active:
		if _status != null:
			_status.queue_free()
			_status = null
		return
	if _status == null:
		_status = Node3D.new()
		_status.top_level = true
		add_child(_status)
	_status_t += delta if not Settings.reduce_motion else 0.0
	_status.global_position = global_position
	var head := bar_height + 0.55
	_piece("stun", stun_left > 0.0, func():
		var n := Node3D.new()
		for i in 3:
			var s := Vfx.cube(0.14, Color("ffe066"))
			s.position = Vector3(cos(i * TAU / 3) * 0.35, 0, sin(i * TAU / 3) * 0.35)
			n.add_child(s)
		return [n, Vector3(0, head, 0), true])
	_piece("root", root_left > 0.0, func(): return [_flat_ring(Color("4f9a3a"), 0.75), Vector3(0, 0.1, 0), false])
	_piece("silence", silence_left > 0.0, func():
		var n := Node3D.new()
		for a in [PI / 4, -PI / 4]:
			var bar := Vfx.cube(1.0, Color("b07cff"))
			bar.scale = Vector3(0.5, 0.09, 0.09)
			bar.rotation.z = a
			n.add_child(bar)
		return [n, Vector3(-0.45, head, 0), false])
	_piece("taunt", taunt_left > 0.0, func():
		var l := Label3D.new()
		l.text = "!"
		l.font_size = 96
		l.pixel_size = 0.01
		l.outline_size = 18
		l.modulate = Color("ff4a3a")
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		return [l, Vector3(0.45, head, 0), false])
	_piece("blind", blind_hits > 0, func():
		var n := Node3D.new()
		for i in 4:
			var s := Vfx.cube(0.2, Color(0.35, 0.35, 0.4, 0.8))
			s.position = Vector3(cos(i * 1.6) * 0.25, 0.08 * i, sin(i * 1.6) * 0.25)
			n.add_child(s)
		return [n, Vector3(0, bar_height - 0.2, 0), true])
	_piece("doom", doom_left > 0.0, func():
		var l := Label3D.new()
		l.font_size = 64
		l.pixel_size = 0.01
		l.outline_size = 16
		l.modulate = Color("e04a9a")
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		return [l, Vector3(0, head + 0.35, 0), false])
	if _status.has_node("doom"):
		(_status.get_node("doom") as Label3D).text = "DOOM %d" % ceili(doom_left)
	_piece("parry", parry_left > 0.0, func():
		var n := Node3D.new()
		for a in [PI / 5, -PI / 5]:
			var blade := Vfx.cube(1.0, Color("fff0b0"))
			blade.scale = Vector3(0.08, 0.7, 0.04)
			blade.rotation.z = a
			n.add_child(blade)
		return [n, Vector3(0, 1.0, 0), true])
	_piece("thorns", thorns_left > 0.0, func():
		var n := Node3D.new()
		for i in 8:
			var spike := Vfx.cube(0.14, Color("b98a4a"))
			spike.position = Vector3(cos(i * TAU / 8) * 0.8, 0.1, sin(i * TAU / 8) * 0.8)
			spike.rotation = Vector3(0.6, i, 0.6)
			n.add_child(spike)
		return [n, Vector3.ZERO, true])
	_piece("hidden", untargetable_left > 0.0, func(): return [_flat_ring(Color(0.15, 0.1, 0.25, 0.85), 0.9), Vector3(0, 0.12, 0), false])
	_piece("raised", raised_left > 0.0, func(): return [_flat_ring(Color("cfffe0"), 0.95), Vector3(0, 0.14, 0), false])
	var buff_stat := ""
	for b in buffs.values():
		buff_stat = b[0]
	_piece("buff", buff_stat != "", func(): return [_flat_ring(Color.WHITE, 0.65), Vector3(0, 0.16, 0), false])
	if _status.has_node("buff") and buff_stat != "":
		((_status.get_node("buff") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = BUFF_COLORS.get(buff_stat, Color.WHITE)
	_piece("shield", ab_shield > 0.0, func():
		var m := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.85
		sph.height = 1.9
		sph.radial_segments = 12
		sph.rings = 6
		m.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.75, 0.9, 1.0, 0.18)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return [m, Vector3(0, 0.95, 0), false])
	_piece("link", link_left > 0.0 and is_instance_valid(link_to) and not link_to.dead, func():
		var m := Vfx.cube(1.0, Color(1.0, 0.85, 0.4, 0.6))
		m.top_level = true
		return [m, Vector3.ZERO, false])
	if _status.has_node("link"):
		var lk := _status.get_node("link") as Node3D
		if lk.visible:
			var a := global_position + Vector3(0, 1.0, 0)
			var b := link_to.global_position + Vector3(0, 1.0, 0)
			lk.global_position = (a + b) * 0.5
			if a.distance_to(b) > 0.01:
				lk.look_at(b)
			lk.scale = Vector3(0.05, 0.05, a.distance_to(b))

# One status mark: made on first use (make returns [node, offset, spins]), shown while `on`.
func _piece(id: String, on: bool, make: Callable):
	var n := _status.get_node_or_null(id) as Node3D
	if n == null:
		if not on:
			return
		var made: Array = make.call()
		n = made[0]
		n.name = id
		n.position = made[1]
		n.set_meta("spins", made[2])
		_status.add_child(n)
	n.visible = on
	if on and n.get_meta("spins", false):
		n.rotation.y = _status_t * 3.0

func _flat_ring(c: Color, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = r - 0.12
	tor.outer_radius = r
	tor.rings = 24
	tor.ring_segments = 6
	m.mesh = tor
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	if c.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	m.scale = Vector3(1, 0.2, 1)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

func _update_charm_fx(delta: float):
	var sigil := _charm_fx.get_node("Sigil") as Node3D
	sigil.global_position = global_position + Vector3(0, bar_height + 1.0, 0)
	if not Settings.reduce_motion:
		sigil.global_rotation = Vector3(PI / 2.0, sigil.global_rotation.y + delta * 3.0, 0)
	var thread := _charm_fx.get_node("Thread") as Node3D
	thread.visible = is_instance_valid(charm_by) and not charm_by.dead
	if thread.visible:
		var a := global_position + Vector3(0, 1.0, 0)
		var b := charm_by.global_position + Vector3(0, 1.0, 0)
		thread.global_position = (a + b) * 0.5
		if a.distance_to(b) > 0.01:
			thread.look_at(b)
		thread.scale = Vector3(1, 1, a.distance_to(b))

func _face(u: Unit):
	_face_point(u.global_position)

# A point in the Units node's space (move_to, grid_to_world) in world space: they differ while a lobby
# client watches a fight from the away side (the board is turned), where facing a local point walked
# units backwards.
func _world(local_p: Vector3) -> Vector3:
	return get_parent().to_global(local_p) if get_parent() is Node3D else local_p

# Turns to face world point p (on the ground plane).
func _face_point(p: Vector3):
	var flat := Vector3(p.x, global_position.y, p.z)
	if flat.distance_to(global_position) > 0.01:
		look_at(flat)

func gain_mana(n: float):
	if data == null or data.max_mana <= 0.0 or stun_left > 0.0 or silence_left > 0.0:
		return
	mana = minf(mana + n, data.max_mana)

func clear_bonuses():
	bonus_hp = 0.0
	bonus_dmg = 0.0
	bonus_as = 0.0
	bonus_mana = 0.0
	dmg_reduction = 0.0
	lifesteal = 0.0
	apply_synergy({})

# Sets this unit's synergy bonuses from Synergies.effects_for (effect keys as in Synergies.DEFS).
func apply_synergy(fx: Dictionary):
	bonus_hp = fx.get("hp", 0.0)
	bonus_dmg = fx.get("dmg", 0.0)
	bonus_as = fx.get("as", 0.0)
	dmg_reduction = fx.get("dr", 0.0)
	lifesteal = fx.get("vamp", 0.0)
	shield_pct = fx.get("shield", 0.0)
	regen = fx.get("regen", 0.0)
	ramp = fx.get("ramp", 0.0)
	ramp_max = int(fx.get("ramp_max", 0))
	crit_every = int(fx.get("crit", 0))
	execute = fx.get("execute", 0.0)
	revive = fx.get("revive", 0.0)
	burn = fx.get("burn", 0.0)
	chill = fx.get("chill", 0.0)
	dodge_every = int(fx.get("dodge", 0))
	curse = fx.get("curse", 0.0)
	range_bonus = int(fx.get("range", 0))
	kill_heal = fx.get("kill_heal", 0.0)

func attack_interval() -> float:
	var speed := 1.0 + bonus_as + item_as + ramp * ramp_stacks + buff_total("as")
	return 1.0 / (data.attacks_per_second * speed * (1.0 - chill_on))

func can_equip() -> bool:
	return items.size() < MAX_ITEMS

# Room and rules for one more item: a free slot, at most one of each bound item and one synergy
# bender per unit, and never Tinker's Tongs (they are used, not worn).
func can_take(item: ItemData) -> bool:
	if item == null or not item.takes_slot() or not can_equip():
		return false
	if item.kind == &"bound" and items.any(func(i): return i.id == item.id):
		return false
	if item.kind == &"bender" and items.any(func(i): return i.kind == &"bender"):
		return false
	return true

# in_combat: the unit is mid-fight, so keep its current health and mana and add the boost on top.
func equip(item: ItemData, in_combat := false) -> bool:
	if item == null or dead or not can_take(item):
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

# Removes and returns every item (selling, merging, Tinker's Tongs). Bound items lose their stacks
# (a merge copies them over first: Board._move_items_to).
func take_items() -> Array[ItemData]:
	var out: Array[ItemData] = items.duplicate()
	items.clear()
	item_stacks.clear()
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
		var stacks := int(item_stacks.get(it.id, 0))
		item_hp += it.hp + it.stack_hp * stacks
		item_dmg += it.dmg + it.stack_dmg * stacks
		item_as += it.attack_speed
		item_mana += it.mana
		item_dr += it.damage_reduction
		item_lifesteal += it.lifesteal
	_update_item_icons()

# The items as their icon images (textures/ui/items/<id>.png) in a row above the health bar: flat,
# always facing the camera, drawn over the models. Bound items show their stack count (resonances are listed
# in the inspector and the Items tab, not on the board). The row is top_level so it stays level when the unit
# turns; _process moves it along with the unit.
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
		var it: ItemData = items[i]
		var pos := Vector3((i - (n - 1) / 2.0) * ICON_STEP, 0, 0)
		var s := Sprite3D.new()
		var tex := DockKit.item_icon(it)
		if tex != null:
			s.texture = tex
			s.pixel_size = ICON_SIZE / tex.get_width()
		else:   # no icon yet: a square in the item's colour
			s.texture = _white_square()
			s.pixel_size = ICON_SIZE * 0.6 / ICON_PX
			s.modulate = it.color
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.no_depth_test = true   # draw over the model
		s.render_priority = 2
		s.position = pos
		item_icons.add_child(s)
		if it.kind == &"bound":
			var l := Label3D.new()
			l.text = str(stacks_of(it))
			l.font_size = 48
			l.pixel_size = 0.006
			l.outline_size = 12
			l.modulate = HudStyle.GOLD
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.render_priority = 3
			l.position = pos + Vector3(ICON_SIZE * 0.36, -ICON_SIZE * 0.3, 0)
			item_icons.add_child(l)

static func _white_square() -> ImageTexture:
	if _icon_tex == null:
		var img := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_icon_tex = ImageTexture.create_from_image(img)
	return _icon_tex

func _ability() -> Ability:
	if data.ability != null:
		return data.ability
	return DEFAULT_ABILITY.new()

func _cast(target_unit: Unit):
	mana = 0.0
	_last_mana_ratio = -1.0
	if Abilities.has(data):   # no name popup: each ability's own effect shows the cast (vfx.gd)
		if Abilities.enabled:
			cast_lock = Abilities.cast(self, target_unit)   # locked while casting (longer for channels)
			Vfx.cast_flash(self)
	else:
		_ability().cast(self, target_unit)   # units whose ability isn't built yet: the placeholder
	if model_view != null:
		model_view.on_cast()
	Sfx.play(&"cast")

# A word that floats up from the unit and fades ("CAST", "MISS", "REVIVE"). Visual only.
func _popup(text: String, color: Color):
	if not is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.01
	l.outline_size = 16
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, bar_height + 0.3, 0)
	add_child(l)
	var t := create_tween()
	if not Settings.reduce_motion:   # Reduce motion: the word fades in place instead of floating up
		t.tween_property(l, "position:y", bar_height + 0.9, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)

# Bound items (Hero's Blade, Heartwood Charm) gain a stack, up to their maximum.
func grow_bound_items() -> void:
	var grew := false
	for it in items:
		if it.kind == &"bound":
			var s := int(item_stacks.get(it.id, 0))
			if s < it.max_stacks:
				item_stacks[it.id] = s + 1
				grew = true
	if grew:
		_recalc_items()

func stacks_of(item: ItemData) -> int:
	return int(item_stacks.get(item.id, 0))
