# unit_model.gd
class_name UnitModel extends Node3D

# The visual body of a unit (UnitData.model is a scene with this script as its root). Holds one
# animated glTF per star level and swaps them on merges. Purely visual: it reads the Unit and is
# told about attacks, casts, hits and deaths, but never changes anything combat uses, so combat
# stays deterministic (tools/combat_checks).
#
# The models (models/units/*.glb) face +Z with their feet at the origin; Unit.look_at points -Z
# at the target, so each model is turned 180 degrees here.

@export var star_scenes: Array[PackedScene] = []   # index 0 = 1 star, 1 = 2 stars, 2 = 3 stars

const LOOPING := ["idle", "walk", "victory"]
const HIT_COOLDOWN := 0.6     # seconds between flinches, so a unit under fire doesn't jitter
const VICTORY_TIME := 2.6     # how long winners celebrate after a fight (two loops)
const GLOW_ENERGY := 2.2      # the glow_<hex> surfaces (blades, crystals, eyes, halos): bright enough to bloom with Glow & fog

var unit: Unit                # null once the model is a stand-in left behind by a removed enemy
var height := 1.6             # top of the current model, before the star scale
var _body: Node3D
var _anim: AnimationPlayer
var _star := 0
var _one_shot := ""           # attack / skill / hit / death while it plays; walk and idle wait for it
var _hit_wait := 0.0
var _victory_left := 0.0

func set_star(s: int) -> void:
	s = clampi(s, 1, star_scenes.size())
	if s == _star and _body != null:
		return
	_star = s
	if _body != null:
		remove_child(_body)
		_body.queue_free()
	_body = star_scenes[s - 1].instantiate()
	_body.rotation.y = PI
	add_child(_body)
	_anim = _body.find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer
	height = 0.0
	for m in _body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		height = maxf(height, mi.get_aabb().end.y)
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null:
				mat.vertex_color_use_as_albedo = true   # the importer leaves it off; the colours are all vertex colours
				if mat.emission_enabled and mat.resource_name.begins_with("glow_"):
					mat.emission_energy_multiplier = GLOW_ENERGY
	if _anim != null:
		for a in LOOPING:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_one_shot = ""
	_play("death" if unit != null and unit.dead else "idle")
	if unit != null and unit.dead and _anim != null:
		_anim.seek(_anim.current_animation_length, true)   # already lying down

func _play(clip: String, speed := 1.0, restart := false) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_anim.speed_scale = speed
	_anim.play(clip, 0.1)
	if restart:
		_anim.seek(0.0, true)   # a second swing in a row starts from the top
	if not LOOPING.has(clip):
		_one_shot = clip

# --- told by Unit (visual only) ---

func on_attack(interval: float) -> void:
	if _one_shot == "death" or _one_shot == "skill":
		return
	var length := _anim.get_animation("attack").length if _anim != null and _anim.has_animation("attack") else 0.9
	_play("attack", maxf(1.0, length / maxf(interval, 0.05)), true)   # fit fast attackers' swings into their interval

func on_cast() -> void:
	if _one_shot == "death":
		return
	_play("skill", 1.0, true)

func on_hit() -> void:
	if _one_shot != "" or _hit_wait > 0.0:
		return   # never cut off a swing, a cast or a death to flinch
	_hit_wait = HIT_COOLDOWN
	_play("hit")

func on_death() -> void:
	_victory_left = 0.0
	_play("death", 1.0, true)

# The fight is over and the unit is back in its spot: winners celebrate, everyone else stands up.
func on_fight_over(celebrate: bool) -> void:
	_one_shot = ""
	_victory_left = VICTORY_TIME if celebrate else 0.0
	_play("victory" if celebrate else "idle")

# Seconds of the death animation still to play (0 when not dying).
func death_left() -> float:
	if _anim == null or _one_shot != "death":
		return 0.0
	return maxf(0.0, (_anim.current_animation_length - _anim.current_animation_position) / maxf(_anim.speed_scale, 0.01))

func _process(delta: float) -> void:
	_hit_wait = maxf(0.0, _hit_wait - delta)
	if _anim == null:
		return
	if _one_shot != "":
		if _anim.is_playing() and _anim.current_animation == _one_shot:
			return
		if _one_shot == "death":
			return   # stays lying down until the fight ends
		_one_shot = ""
	if _victory_left > 0.0:
		_victory_left -= delta
		if _victory_left > 0.0:
			return
	var want := "walk" if unit != null and unit.moving else "idle"
	if _anim.current_animation != want:
		_play(want)
