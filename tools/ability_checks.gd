# ability_checks.gd
# Dev tool, not part of the game: checks the unit abilities (Scripts/abilities.gd, docs/abilities.md).
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/ability_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Casts are triggered by hand on units placed on a
# real board, then the combat tick is stepped by hand, so each mechanic is checked on its own.

extends Node

const TICK := 1.0 / 60.0

var fails := 0
var main: Node
var gm
var board: Board

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func load_main(seed := 0):
	if main != null:
		main.free()
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = seed
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.me.level = 8
	board.refresh_unlocks(8, false)

func UD(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

# A unit on a tile, in fight state (full HP, start mana, nothing applied).
func place(n: String, c: Vector2i, team := 0, star := 1) -> Unit:
	var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(u)
	u.setup(UD(n), team)
	if star > 1:
		u.set_star(star)
	if team == 0:
		board.put_on_tile(u, c)
	else:
		board.put_enemy_on_tile(u, c)
	u.begin_combat()
	return u

# Steps only the timers (stuns, buffs, shields, queued hits) for secs.
func timers(units: Array, secs: float):
	for i in roundi(secs / TICK):
		for u in units:
			u._tick_effects(TICK)

# Full combat steps (moves, attacks, casts) for secs.
func steps(units: Array, secs: float):
	for i in roundi(secs / TICK):
		for u in units:
			u.combat_step(TICK)

func clear_units():
	for n in board.get_node("Units").get_children():
		board.vacate(n)
		n.free()

func _run():
	SaveGame.path = "user://ability_test_save.json"
	await load_main(1)

	print("--- the ability table")
	var roster: Array = gm.unit_pool
	var names := {}
	for d in roster:
		names[d.display_name] = d
	var unknown: PackedStringArray = []
	var unfilled: PackedStringArray = []
	for n in Abilities.DEFS:
		if not names.has(n):
			unknown.append(n)
		elif Abilities.text(names[n]).contains("{") or Abilities.text(names[n], 2).contains("{"):
			unfilled.append(n)
	chk("every ability belongs to a unit in the roster", unknown.is_empty(), ", ".join(unknown))
	chk("chunk 1: 40 units have an ability", Abilities.DEFS.size() == 40, str(Abilities.DEFS.size()))
	chk("every text has its numbers filled in", unfilled.is_empty(), ", ".join(unfilled))
	chk("shop text shows all three stars, the inspector one", Abilities.text(UD("cleric")).contains("110 / 200 / 350") and Abilities.text(UD("cleric"), 2).contains("for 200 each"), Abilities.text(UD("cleric")))
	chk("per-star arrays stay as written", Abilities.text(UD("bard"), 3).contains("50%"))

	print("--- damage and stun (Knight)")
	var k := place("knight", Vector2i(3, 4))
	var foe := place("guardian", Vector2i(3, 3), 1)
	var hp0 := foe.health
	k._cast(foe)
	chk("Lion's Roar deals 180", is_equal_approx(hp0 - foe.health, 180.0), str(hp0 - foe.health))
	chk("it stuns for 1 s and the caster is locked for 0.5 s", is_equal_approx(foe.stun_left, 1.0) and is_equal_approx(k.cast_lock, 0.5))
	chk("the cast empties the caster's mana", k.mana == 0.0)
	var made := foe.attacks_made
	var mana0 := foe.mana
	steps([foe], 0.9)
	chk("a stunned unit doesn't attack or gain mana", foe.attacks_made == made and foe.mana == mana0)
	foe.take_damage(10.0, k, true)
	chk("not even from being hit", foe.mana == mana0)
	steps([foe], 0.2)
	chk("the stun wears off", foe.stun_left == 0.0)
	var k2 := place("knight", Vector2i(4, 4), 0, 2)
	var hp1 := foe.health
	k2._cast(foe)
	chk("2 stars: 325 damage", is_equal_approx(hp1 - foe.health, 325.0), str(hp1 - foe.health))
	clear_units()

	print("--- shields and taunt (Militia, Acolyte)")
	var mi := place("militia", Vector2i(3, 4))
	var adj := place("thief", Vector2i(3, 3), 1)
	var far := place("thief", Vector2i(3, 1), 1)
	adj.target = far
	mi._cast(adj)
	chk("Dig In: a 200 shield", is_equal_approx(mi.shield, 200.0) and is_equal_approx(mi.ab_shield, 200.0))
	chk("adjacent enemies are taunted, others not", adj.target == mi and adj.taunt_left > 0.0 and far.taunt_left == 0.0)
	timers([mi, adj], 4.05)
	chk("the shield runs out after 4 s, the taunt after 2", mi.shield == 0.0 and adj.taunt_by == null)
	clear_units()
	var ac := place("acolyte", Vector2i(3, 5))
	var hurt := place("knight", Vector2i(3, 4))
	var e2 := place("thief", Vector2i(3, 3), 1)
	hurt.health = 300.0
	ac._cast(e2)
	chk("Little Prayer shields the ally with the lowest HP%", is_equal_approx(hurt.shield, 150.0) and ac.shield == 0.0)
	hurt.take_damage(50.0)
	timers([hurt], 4.05)
	chk("what is left heals when it runs out", is_equal_approx(hurt.health, 400.0) and hurt.shield == 0.0, str(hurt.health))
	clear_units()

	print("--- silence, blind, damage reduction")
	var sp := place("sprite", Vector2i(3, 5))
	var vic := place("guardian", Vector2i(3, 3), 1)
	sp._cast(vic)
	var m1 := vic.mana
	vic._attack(sp)
	chk("Acorn Hex silences: no mana from attacking", vic.mana == m1 and is_equal_approx(vic.silence_left, 2.0))
	clear_units()
	var sf := place("shadowfist", Vector2i(3, 4))
	var bl := place("knight", Vector2i(3, 3), 1)
	sf._cast(bl)
	var sh0 := sf.health
	bl._attack(sf)
	bl._attack(sf)
	chk("Stink Cloud: the next 2 attacks miss", sf.health == sh0 and bl.blind_hits == 0)
	bl._attack(sf)
	chk("the third one hits", sf.health < sh0)
	clear_units()
	var gu := place("guardian", Vector2i(3, 4))
	var hitter := place("knight", Vector2i(3, 3), 1)
	var g0 := gu.health
	gu.take_damage(100.0)
	var plain_hit := g0 - gu.health
	gu._cast(hitter)
	var g1 := gu.health
	gu.take_damage(100.0)
	chk("Shell Up halves the damage taken", is_equal_approx(g1 - gu.health, plain_hit * 0.5), "%.1f vs %.1f" % [g1 - gu.health, plain_hit])
	chk("and taunts nearby enemies", hitter.target == gu)
	clear_units()

	print("--- buffs (Bard, Berserker)")
	var ba := place("bard", Vector2i(3, 5))
	var near := place("knight", Vector2i(3, 4))
	var far_ally := place("knight", Vector2i(0, 7))
	var ee := place("thief", Vector2i(3, 2), 1)
	var iv := near.attack_interval()
	ba._cast(ee)
	chk("Dawn Chorus speeds up allies within 2 hexes", near.attack_interval() < iv and is_equal_approx(near.buff_total("as"), 0.25) and far_ally.buff_total("as") == 0.0)
	ba._cast(ee)
	chk("casting again refreshes, never stacks", is_equal_approx(near.buff_total("as"), 0.25))
	timers([near], 4.05)
	chk("the buff ends after 4 s", is_equal_approx(near.attack_interval(), iv))
	clear_units()

	print("--- areas, lines and clusters")
	var spk := place("sparkcaller", Vector2i(3, 6))
	var l1 := place("thief", Vector2i(3, 3), 1)
	var behind := Abilities._from_cube(Board.to_cube(l1.coord) + Abilities._direction(spk.coord, l1.coord))
	var l2 := place("thief", behind, 1)
	var off := place("thief", Vector2i(0, 3), 1)
	var line := Abilities.enemies_in_line(spk, l1, 3)
	spk._cast(l1)
	chk("Arc Lash hits the line through the target, not off it", line.size() == 2 and l2.health < l2.max_hp() and off.health == off.max_hp() and l1.health < l1.max_hp(), "line %d, behind %s" % [line.size(), behind])
	clear_units()
	var im := place("ice_mage", Vector2i(3, 6))
	var lone := place("thief", Vector2i(0, 1), 1)
	var c1 := place("thief", Vector2i(5, 2), 1)
	var c2 := place("thief", Vector2i(5, 1), 1)
	var c3 := place("thief", Vector2i(6, 2), 1)
	im._cast(lone)
	chk("Glacier Slam lands on the cluster, not the lone enemy", c1.stun_left > 0.0 and c2.stun_left > 0.0 and c3.stun_left > 0.0 and lone.stun_left == 0.0)
	clear_units()
	var fa := place("frost_archer", Vector2i(3, 6))
	var close := place("thief", Vector2i(3, 3), 1)
	var back := place("thief", Vector2i(3, 0), 1)
	fa._cast(close)
	chk("Piercing Icicle shoots the farthest enemy", back.health < back.max_hp() and close.health == close.max_hp() and back.chill_on > 0.0)
	clear_units()

	print("--- multi-hit casts (Initiate, Mage, Lich)")
	var ini := place("initiate", Vector2i(3, 4))
	var dummy := place("titan", Vector2i(3, 3), 1)
	ini.target = dummy
	ini._cast(dummy)
	timers([ini], 0.5)
	chk("Monkey Barrage: five strikes that count as attacks", ini.attacks_made == 5, str(ini.attacks_made))
	chk("they give no mana", ini.mana == 0.0)
	clear_units()
	var li := place("lich", Vector2i(3, 5))
	var prey := place("titan", Vector2i(3, 3), 1)
	var p0 := prey.health
	li._cast(prey)
	timers([li, prey], 0.6)
	var half := p0 - prey.health
	timers([li, prey], 1.0)
	chk("Death Roll deals its damage over 1.5 s", half > 0.0 and half < 350.0 and is_equal_approx(p0 - prey.health, 350.0), "%.1f then %.1f" % [half, p0 - prey.health])
	chk("and locks the Lich while it rolls", li.cast_lock == 0.0 and prey.stun_left == 0.0)
	clear_units()

	print("--- in the inspector")
	var dr := place("dragon", Vector2i(3, 5), 0, 2)
	var its: Array[ItemData] = []
	for n in ["longsword", "chain_vest", "mana_charm"]:
		its.append(load("res://tres/items/%s.tres" % n))
	dr.set_items(its)
	get_tree().root.size = Vector2i(1152, 648)   # the game's own size, so the HUD lays out as it does on screen
	var insp = main.get_node("UI/UnitInspector")
	insp.shown = dr
	insp.visible = true
	insp._fill()
	await get_tree().process_frame
	await get_tree().process_frame
	var standings: Control = main.get_node("UI/Standings")
	var overlaps: bool = insp.get_global_rect().intersects(standings.get_global_rect())
	insp._yield_standings()
	chk("the inspector names the ability and shows it at the unit's star", insp.ability_head.text == "ABILITY  ·  DRAGONFIRE BREATH" and insp.ability_text.text.contains("720"), insp.ability_text.text)
	chk("a tall inspector fades the HP standings out instead of covering them", standings.modulate.a == (0.0 if overlaps else 1.0), "inspector top %d, standings end %d" % [insp.get_global_rect().position.y, standings.get_global_rect().end.y])
	var no_ab := place("scout", Vector2i(0, 7))
	insp.shown = no_ab
	insp._fill()
	chk("a unit without an ability yet shows no ability lines", not insp.ability_head.visible)
	insp._close()
	chk("the standings come back when it closes", standings.modulate.a == 1.0)
	clear_units()

	print("--- switched off")
	Abilities.enabled = false
	var off_k := place("knight", Vector2i(3, 4))
	var off_e := place("guardian", Vector2i(3, 3), 1)
	off_k._cast(off_e)
	chk("Abilities.enabled = false: a cast does nothing", off_e.health == off_e.max_hp() and off_e.stun_left == 0.0 and off_k.mana == 0.0)
	Abilities.enabled = true
	clear_units()

	print("--- a fight full of casts, twice, and in real time")
	var sigs: PackedStringArray = []
	for i in 3:
		await load_main(777)
		_cast_fight()
		gm.start_combat()
		if i < 2:
			gm.resolve_combat()
			sigs.append(_signature())
		else:
			await Events.combat_ended
			sigs.append(_signature())
			await get_tree().process_frame
	chk("the same fight twice gives the same result", sigs[0] == sigs[1], sigs[0].left(140))
	chk("real time == resolve_combat()", sigs[0] == sigs[2], sigs[2].left(140))

	if main != null:
		main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

# Casters on both sides: stuns, taunts, buffs, shields, channels, areas.
func _cast_fight():
	var mine := [["frost_giant", 2], ["bard", 1], ["lich", 1], ["mage", 1], ["militia", 2], ["initiate", 1], ["cleric", 1]]
	for i in mine.size():
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(UD(mine[i][0]), 0)
		u.set_star(mine[i][1])
		board.put_on_tile(u, board.player_order[i])
	var wave := EnemyBoard.new()
	wave.display_name = "Casters"
	for e in [["guardian", Vector2i(3, 3), 2], ["titan", Vector2i(4, 3), 1], ["ice_mage", Vector2i(3, 1), 2], ["skald", Vector2i(2, 3), 1], ["shadowfist", Vector2i(4, 2), 2], ["dragon", Vector2i(3, 0), 1], ["acolyte", Vector2i(5, 1), 2]]:
		var bu := BoardUnit.new()
		bu.unit = UD(e[0])
		bu.coord = e[1]
		bu.star = e[2]
		wave.units.append(bu)
	var waves: Array[EnemyBoard] = [wave]
	gm.opponents = WaveOpponents.new(waves, 1.0)

func _signature() -> String:
	var parts: PackedStringArray = ["won=%s ticks=%d" % [GameState.me.last_combat_won, gm.combat_ticks]]
	for u in gm.combatants:
		if is_instance_valid(u):
			parts.append("%s%d@%d,%d dealt=%.3f taken=%.3f" % [u.data.display_name, u.team, u.coord.x, u.coord.y, u.damage_dealt, u.damage_taken])
	return " | ".join(parts)
