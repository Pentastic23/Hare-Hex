# music.gd
extends Node

# Autoload Music: the soundtrack. Lost Kingdom on the main menu, Aspiration Woods during a run, and
# Final Struggle for boss rounds (GameManager.is_boss_round: a chapter level's last wave, free play's
# final round). Tracks loop seamlessly (their .import sets a forward loop) and crossfade when they
# change. Everything plays on the "Music" bus (Settings.music_bus, sent to Master), so Settings > Audio
# has a Music slider of its own (Settings.music_volume). Keeps playing while the game is paused.
# Tracks from the "Free Orchestral Music Pack" (in the user's Desktop/Art assets).

const TRACKS := {
	"menu": preload("res://audio/music/lost_kingdom.wav"),
	"game": preload("res://audio/music/aspiration_woods.wav"),
	"boss": preload("res://audio/music/final_struggle.wav"),
}
const BUS := "Music"
const FADE := 1.2   # seconds to crossfade between tracks

var current := ""   # "menu", "game", "boss" or ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tween: Tween

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.music_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)

# Switches to a track ("menu", "game", "boss"), crossfading; the same track keeps playing.
func play(track: String) -> void:
	if track == current or not TRACKS.has(track):
		return
	current = track
	var old := _players[_active]
	_active = 1 - _active
	var new := _players[_active]
	new.stream = TRACKS[track]
	new.volume_db = -40.0
	new.play()
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(new, "volume_db", 0.0, FADE).set_trans(Tween.TRANS_SINE)
	if old.playing:
		_tween.tween_property(old, "volume_db", -60.0, FADE).set_trans(Tween.TRANS_SINE)
		_tween.chain().tween_callback(old.stop)

func stop() -> void:
	current = ""
	for p in _players:
		p.stop()

func playing_stream() -> AudioStream:
	return _players[_active].stream if _players[_active].playing else null
