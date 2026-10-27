# unit_model.gd
class_name UnitModel extends Node3D

# The visual body of a unit (UnitData.model is a scene with this script as its root). Holds one
# animated glTF per star level and swaps them on merges. Purely visual: it reads the Unit and is
# told about attacks, casts, hits and deaths, but never changes anything combat uses, so combat
# stays deterministic (tools/combat_checks).
#
# The models (models/units/*.glb) face +Z with their feet at the origin; Unit.look_at points -Z
# at the target, so each model is turned 180 degrees here.

@export var star_scenes: Array[PackedScene] = []   # index 0 = 1 star .. 3 = 4 stars (the astral form, by ascension)

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
var rest_clip := "idle"       # the clip it loops when not walking or busy ("extra/wave" after wave())

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
	if rest_clip != "idle":
		wave()   # a new star's model: make its wave again
	_play("death" if unit != null and unit.dead else rest_clip)
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
	_play("victory" if celebrate else rest_clip)

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
	var want := "walk" if unit != null and unit.moving else rest_clip
	if _anim.current_animation != want:
		_play(want)

# A friendly wave (the splash screen): the idle clip with the right arm raised as at the top of the
# victory clip, swinging side to side from the shoulder, its weapon held upright. Built from the model's
# own clips (every biped has the same rig), added as "extra/wave" and looped in place of idle.
const WAVE_SWING := [0.85, 0.1]   # radians the raised arm swings out and back (about the body's forward axis)
const WAVE_BEAT := 0.2             # seconds per swing
func wave() -> void:
	if _anim == null or not _anim.has_animation("idle") or not _anim.has_animation("victory"):
		return
	var victory := _anim.get_animation("victory")
	var arm := _rotation_track(victory, "arm_r")
	if arm < 0:
		return
	var clip := _anim.get_animation("idle").duplicate() as Animation
	for bone in ["arm_r", "weapon_r"]:
		var old := _rotation_track(clip, bone)
		if old >= 0:
			clip.remove_track(old)
	var up: Quaternion = victory.rotation_track_interpolate(arm, 0.25)   # the arm at the top of the victory clip
	var t := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(t, victory.track_get_path(arm))
	var beats := roundi(clip.length / WAVE_BEAT)
	for k in beats + 1:
		var a: float = WAVE_SWING[k % 2] if k < beats else WAVE_SWING[0]
		clip.rotation_track_insert_key(t, minf(k * WAVE_BEAT, clip.length), Quaternion(Vector3.BACK, a) * up)
	var weapon := _rotation_track(victory, "weapon_r")
	if weapon >= 0:
		var w := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(w, victory.track_get_path(weapon))
		clip.rotation_track_insert_key(w, 0.0, victory.rotation_track_interpolate(weapon, 0.25))
	clip.loop_mode = Animation.LOOP_LINEAR
	var lib := AnimationLibrary.new()
	lib.add_animation("wave", clip)
	if _anim.has_animation_library("extra"):
		_anim.remove_animation_library("extra")
	_anim.add_animation_library("extra", lib)
	rest_clip = "extra/wave"
	if _one_shot == "":
		_play(rest_clip)

static func _rotation_track(a: Animation, bone: String) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_ROTATION_3D and String(a.track_get_path(i).get_concatenated_subnames()) == bone:
			return i
	return -1
