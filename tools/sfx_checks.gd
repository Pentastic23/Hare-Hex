# sfx_checks.gd
# Dev tool, not part of the game: checks the sound effects (sfx.gd): the pack loads, the SFX bus follows
# its setting, cooldowns, muting, and that the game's actions make their sounds. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/sfx_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway save and settings files.

extends Node

const ALL := [&"click", &"buy", &"sell", &"reroll", &"xp", &"lock", &"unlock", &"error", &"pickup", &"place", &"equip",
	&"merge", &"levelup", &"win", &"lose", &"round", &"swing", &"hit", &"crit", &"death", &"cast", &"heal"]

var fails := 0
var main: Node
var gm
var board: Board

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func frames(n := 2):
	for i in n:
		await get_tree().process_frame

func load_main():
	if main != null:
		main.free()
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 4242
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await frames(3)

# Plays `s` with the cooldown cleared; true if it counted.
func fresh(s: StringName) -> bool:
	Sfx._last_ms.erase(s)
	var before := int(Sfx.played.get(s, 0))
	Sfx.play(s)
	return int(Sfx.played.get(s, 0)) == before + 1

func count(s: StringName) -> int:
	return int(Sfx.played.get(s, 0))

func clear():
	Sfx.played.clear()
	Sfx._last_ms.clear()

func _run():
	SaveGame.path = "user://sfx_test_save.json"
	SaveGame.reset_progress()
	Settings.path = "user://sfx_test_settings.cfg"
	Settings._loaded = true
	Settings.reduce_motion = false
	Settings.reset_options()

	print("--- the pack")
	chk("every sound is in the pack and loads", ALL.all(func(s): return Sfx._stream(s) is AudioStream), str(ALL.filter(func(s): return Sfx._stream(s) == null)))
	chk("none is empty or long (under 2 s)", ALL.all(func(s): var l := Sfx._stream(s).get_length(); return l > 0.03 and l < 2.0))
	chk("an unknown name is ignored, not an error", not Sfx.play(&"no_such_sound"))

	print("--- the SFX bus and its setting")
	chk("sfx volume defaults to 0.8", is_equal_approx(Settings.sfx_volume, 0.8))
	Settings.sfx_volume = 0.3
	Settings.apply()
	Settings.save_settings()
	Settings.sfx_volume = 0.8
	Settings._loaded = false
	Settings.load_settings()
	chk("it comes back from disk", is_equal_approx(Settings.sfx_volume, 0.3))
	var bus := AudioServer.get_bus_index("SFX")
	chk("the SFX bus sends to Master and follows the slider", bus > 0 and AudioServer.get_bus_send(bus) == &"Master" and is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.3)))
	Settings.sfx_volume = 0.0
	Settings.apply()
	chk("at 0 only the SFX bus is muted", AudioServer.is_bus_mute(bus) and not AudioServer.is_bus_mute(0) and not AudioServer.is_bus_mute(Settings.music_bus()))
	Settings.reset_options()
	Settings.apply()
	chk("Reset settings puts it back to 0.8", is_equal_approx(Settings.sfx_volume, 0.8) and not AudioServer.is_bus_mute(bus))
	chk("the players use the SFX bus", Sfx.get_children().all(func(p): return (p as AudioStreamPlayer).bus == &"SFX"))

	print("--- playing")
	clear()
	chk("a sound plays", Sfx.play(&"click") and count(&"click") == 1)
	chk("the same sound again at once is held back by its cooldown", not Sfx.play(&"click") and count(&"click") == 1)
	chk("a different sound is not", Sfx.play(&"buy") and count(&"buy") == 1)
	Sfx.muted += 1
	chk("muted: nothing plays", not fresh(&"sell"))
	Sfx.muted -= 1
	chk("unmuted again", fresh(&"sell"))
	chk("overlapping sounds use separate players", (func():
		for s in [&"buy", &"sell", &"xp", &"merge"]:
			fresh(s)
		return Sfx.get_children().filter(func(p): return (p as AudioStreamPlayer).playing).size() >= 3).call())
	chk("jingles keep their pitch", (func():
		fresh(&"merge")
		return is_equal_approx(Sfx._players.filter(func(p): return p.playing and p.stream == Sfx._stream(&"merge"))[0].pitch_scale, 1.0)).call())

	print("--- the game makes its sounds")
	await load_main()
	var me = GameState.me
	me.gold = 100
	clear()
	Events.reroll_pressed.emit()
	chk("Reroll", count(&"reroll") == 1)
	me.gold = 0
	me.free_rerolls = 0
	Sfx._last_ms.clear()
	Events.reroll_pressed.emit()
	chk("a Reroll you can't afford makes the error sound", count(&"error") == 1 and count(&"reroll") == 1)
	me.gold = 100
	Events.buy_xp_pressed.emit()
	chk("Buy XP", count(&"xp") == 1)
	me.gold = 0
	Sfx._last_ms.clear()
	Events.buy_xp_pressed.emit()
	chk("Buy XP without gold: error", count(&"error") == 2)
	gm.set_shop_locked(true)
	chk("locking the shop", count(&"lock") == 1)
	Events.shop_lock_changed.emit(false)
	chk("unlocking it", count(&"unlock") == 1)
	Sfx._last_ms.clear()
	Events.unit_sold.emit(load("res://tres/knight.tres"), 1, 1)
	Events.unit_bought.emit(load("res://tres/knight.tres"))
	chk("buying and selling", count(&"buy") == 1 and count(&"sell") == 1)
	Sfx._last_ms.clear()
	Events.board_limit_hit.emit()
	chk("a full board", count(&"error") == 3)
	Events.xp_changed.emit(me.level, 0, 10)
	Sfx._last_ms.clear()
	Sfx.played.erase(&"levelup")
	Events.xp_changed.emit(me.level + 1, 0, 10)
	chk("a level-up (and only a level-up)", count(&"levelup") == 1)
	Events.run_won.emit()
	Events.run_lost.emit()
	chk("winning and losing the run", count(&"win") == 1 and count(&"lose") == 1)

	for i in 3:
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(load("res://tres/knight.tres"), 0)
		board.put_on_bench(u, i)
	clear()
	board.merge_all()
	chk("three of a kind merge with a sound", count(&"merge") == 1)

	print("--- a fight")
	GameState.me.level = 5
	board.refresh_unlocks(5, false)
	for i in 3:
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(load("res://tres/%s.tres" % ["archer", "mage", "thief"][i]), 0)
		board.put_on_tile(u, board.player_order[i])
	var wave := EnemyBoard.new()
	wave.display_name = "Test wave"
	wave.stat_scale = 0.9
	for e in [["guardian", Vector2i(3, 3)], ["knight", Vector2i(4, 3)]]:
		var bu := BoardUnit.new()
		bu.unit = load("res://tres/%s.tres" % e[0])
		bu.coord = e[1]
		bu.star = 1
		wave.units.append(bu)
	var waves: Array[EnemyBoard] = [wave]
	gm.opponents = WaveOpponents.new(waves, 1.0)
	clear()
	Events.phase_changed.emit(Events.Phase.COMBAT)
	chk("a fight starting sounds the horn", count(&"round") == 1)
	gm.start_combat()
	gm.resolve_combat()
	chk("an instant fight (resolve_combat) is silent", count(&"hit") == 0 and count(&"death") == 0 and Sfx.muted == 0)
	await frames(2)
	await load_main()
	for i in 2:
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(load("res://tres/%s.tres" % ["knight", "thief"][i]), 0)
		board.put_on_tile(u, board.player_order[i])
	gm.opponents = WaveOpponents.new(waves, 1.0)
	clear()
	gm.start_combat()
	for i in 600:
		if not gm.fighting:
			break
		await get_tree().physics_frame
		Sfx._last_ms.clear()
	chk("a live fight has hits and a death", count(&"hit") + count(&"crit") > 0 and count(&"death") > 0, str(Sfx.played))

	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

func _ready():
	_run.call_deferred()
