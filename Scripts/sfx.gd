# sfx.gd  (autoload "Sfx")
# Sound effects: Sfx.play(&"hit") plays res://audio/sfx/hit.wav on the "SFX" bus (Settings > Audio > Sound
# effects). A small pool of players lets sounds overlap; each sound has a short cooldown so a big fight
# doesn't pile hundreds of hits on top of each other, and a little pitch variety keeps repeats from
# sounding mechanical (own seeded RNG: audio never touches the game's random numbers).
# Sfx.muted > 0 silences it (resolve_combat, which runs a whole fight in an instant, mutes while it runs).
# The pack is made by code (tools/synth_sfx.py), so it can be remade or retuned.
extends Node

const DIR := "res://audio/sfx/"
const POOL := 12
# Seconds before the same sound may play again; sounds not listed use DEFAULT_COOLDOWN.
const DEFAULT_COOLDOWN := 0.04
const COOLDOWN := {&"hit": 0.05, &"crit": 0.08, &"swing": 0.09, &"death": 0.12, &"cast": 0.12, &"heal": 0.12, &"click": 0.03}
# Per-sound loudness trim in dB (the pack is normalised, so the busy ones are turned down).
const GAIN := {&"hit": -7.0, &"swing": -13.0, &"crit": -4.0, &"death": -5.0, &"cast": -6.0, &"heal": -8.0, &"click": -8.0, &"place": -5.0, &"pickup": -9.0}
# Sounds that keep one pitch (jingles with melodies); the rest vary a little.
const FIXED_PITCH := [&"buy", &"sell", &"xp", &"merge", &"levelup", &"win", &"lose", &"round", &"equip", &"heal", &"lock", &"unlock", &"error"]

var muted := 0                 # > 0: nothing plays
var played := {}               # sound -> times it played (for tests)
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _last_ms := {}
var _rng := RandomNumberGenerator.new()
var _last_level := 0

func _ready():
	_rng.seed = 90210
	var bus := Settings.sfx_bus()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = AudioServer.get_bus_name(bus)
		add_child(p)
		_players.append(p)
	Events.unit_bought.connect(func(_d): play(&"buy"))
	Events.unit_sold.connect(func(_d, _s, _r): play(&"sell"))
	Events.shop_lock_changed.connect(func(on): play(&"lock" if on else &"unlock"))
	Events.board_limit_hit.connect(func(): play(&"error"))
	Events.run_won.connect(func(): play(&"win"))
	Events.run_lost.connect(func(): play(&"lose"))
	Events.xp_changed.connect(_on_xp_changed)
	Events.phase_changed.connect(func(p): if p == Events.Phase.COMBAT: play(&"round"))

func _on_xp_changed(level: int, _xp: int, _needed: int) -> void:
	if _last_level != 0 and level > _last_level:
		play(&"levelup")
	_last_level = level

# Plays `sound` (a file name without .wav). `gain_db` adds to its trim. Returns true if it started.
func play(sound: StringName, gain_db := 0.0) -> bool:
	if muted > 0:
		return false
	var now := Time.get_ticks_msec()
	var cd := float(COOLDOWN.get(sound, DEFAULT_COOLDOWN)) * 1000.0
	if now - int(_last_ms.get(sound, -100000)) < cd:
		return false
	var stream := _stream(sound)
	if stream == null:
		return false
	_last_ms[sound] = now
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[0]   # all busy: cut the oldest-started slot
	player.stream = stream
	player.volume_db = float(GAIN.get(sound, 0.0)) + gain_db
	player.pitch_scale = 1.0 if sound in FIXED_PITCH else _rng.randf_range(0.93, 1.07)
	player.play()
	played[sound] = int(played.get(sound, 0)) + 1
	return true

func _stream(sound: StringName) -> AudioStream:
	if not _streams.has(sound):
		var path := DIR + String(sound) + ".wav"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]
