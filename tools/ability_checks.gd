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
	chk("every unit in the roster has an ability (all 65)", Abilities.DEFS.size() == roster.size() and roster.size() == 65, str(Abilities.DEFS.size()))
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

	print("--- chunk 2: leaps, charges and stealth")
	var sc := place("scout", Vector2i(3, 4))
	var near_foe := place("knight", Vector2i(3, 3), 1)
	var gap0 := Board.hex_distance(sc.coord, near_foe.coord)
	sc._cast(near_foe)
	chk("Hare's Hop leaps away from the enemy (the tile is claimed at once)", Board.hex_distance(sc.coord, near_foe.coord) > gap0 and board.tiles[sc.coord].occupant == sc and board.tiles[Vector2i(3, 4)].occupant == null, str(sc.coord))
	chk("and the model flies there", sc.moving and is_equal_approx(sc.move_rate, 4.0))
	steps([sc], 0.3)
	chk("landing on the new tile", not sc.moving and sc.position.is_equal_approx(board.grid_to_world(sc.coord)))
	var nh := near_foe.health
	sc._attack(near_foe)
	chk("its next attacks deal 40 more", is_equal_approx(nh - near_foe.health, sc.damage() + 40.0) and sc.empower_hits == 2, str(nh - near_foe.health))
	clear_units()

	var nb := place("nightblade", Vector2i(3, 6))
	var tank := place("guardian", Vector2i(3, 3), 1)
	var weak := place("thief", Vector2i(1, 2), 1)
	var too_far := place("thief", Vector2i(6, 0), 1)
	weak.health = 100.0
	too_far.health = 50.0
	nb._cast(tank)
	chk("Panther Pounce: next to the weakest enemy within 4 hexes", Board.hex_distance(nb.coord, weak.coord) == 1 and weak.dead and too_far.health == 50.0, str(nb.coord))
	chk("and it keeps fighting that enemy's side", nb.target == weak)
	clear_units()

	var asn := place("assassin", Vector2i(3, 4))
	var front := place("guardian", Vector2i(3, 3), 1)
	var backline := place("mage", Vector2i(4, 0), 1)
	asn._cast(front)
	chk("Shadowstep: behind the farthest enemy", Board.hex_distance(asn.coord, backline.coord) == 1 and asn.coord.y < backline.coord.y + 1 and backline.health < backline.max_hp(), str(asn.coord))
	clear_units()

	var wl := place("warlord", Vector2i(3, 6))
	var goal := place("mage", Vector2i(3, 0), 1)
	var side := place("thief", Vector2i(4, 4), 1)
	var aside := place("thief", Vector2i(0, 1), 1)
	var start := wl.coord
	wl._cast(goal)
	chk("Rhino Charge: up to 4 hexes towards the farthest enemy", Board.hex_distance(start, wl.coord) == 4 and Board.hex_distance(wl.coord, goal.coord) < Board.hex_distance(start, goal.coord), str(wl.coord))
	chk("enemies next to the path are hit and stunned, others not", side.stun_left == 1.0 and side.health < side.max_hp() and aside.stun_left == 0.0)
	clear_units()

	var ns := place("nightstalker", Vector2i(3, 5))
	var hunter := place("knight", Vector2i(3, 3), 1)
	var bait := place("militia", Vector2i(0, 4))
	ns._cast(hunter)
	chk("Moonlit Hunt: it can't be targeted for 2 s", board.nearest_enemy(hunter) == bait and Abilities.targets(hunter).size() == 1)
	var h0 := hunter.health
	ns._attack(hunter)
	chk("its attacks while hidden are normal ones", is_equal_approx(h0 - hunter.health, ns.damage()))
	timers([ns], 2.05)
	chk("then it can be targeted again", board.nearest_enemy(hunter) == ns)
	var h1 := hunter.health
	ns._attack(hunter)
	chk("its first attack after reappearing deals 250 more and crits", is_equal_approx(h1 - hunter.health, (ns.damage() + 250.0) * 2.0) and ns.empower_hits == 0, str(h1 - hunter.health))
	clear_units()

	var se := place("seraph", Vector2i(3, 6))
	var hurt2 := place("knight", Vector2i(3, 4))
	var ok_ally := place("militia", Vector2i(4, 4))
	var foe2 := place("thief", Vector2i(3, 3), 1)
	hurt2.health = 100.0
	ok_ally.health = 500.0
	se._cast(foe2)
	chk("Wings of Dawn heals everyone", is_equal_approx(hurt2.health, 300.0) and is_equal_approx(ok_ally.health, 600.0))
	chk("and hides the weakest ally for 1.5 s", hurt2.untargetable_left == 1.5 and ok_ally.untargetable_left == 0.0 and board.nearest_enemy(foe2) != hurt2)
	clear_units()

	print("--- chunk 3: summons, zones and thorns")
	var ne := place("necromancer", Vector2i(3, 6))
	var nfoe := place("knight", Vector2i(3, 2), 1)
	ne._cast(nfoe)
	var thrall: Unit = ne.summons[0] if not ne.summons.is_empty() else null
	chk("Raise Thrall: a Bone Thrall next to the Necromancer", thrall != null and thrall.summoned and thrall.team == 0 and Board.hex_distance(thrall.coord, ne.coord) == 1 and board.tiles[thrall.coord].occupant == thrall)
	chk("with 300 HP, 30 damage, no traits and no mana", thrall != null and is_equal_approx(thrall.max_hp(), 300.0) and is_equal_approx(thrall.damage(), 30.0) and thrall.data.tags.is_empty() and thrall.data.max_mana == 0.0)
	chk("it joins the fight's acting order", gm.new_summons.has(thrall))
	thrall.take_damage(200.0)
	ne._cast(nfoe)
	chk("one at a time: casting again heals it fully", ne.summons.size() == 1 and is_equal_approx(thrall.health, 300.0))
	chk("a summon can't be sold or given items", not (load("res://Scripts/drag_controller.gd") == null) and main.get_node("DragController").equip_item_on(thrall, null) == false)
	clear_units()
	gm.new_summons.clear()

	var dm := place("demonologist", Vector2i(3, 6))
	var dfoe := place("knight", Vector2i(3, 2), 1)
	dm._cast(dfoe)
	dm._cast(dfoe)
	dm._cast(dfoe)
	chk("Pact Demon: at most two", Abilities.living_summons(dm).size() == 2)
	var demon: Unit = dm.summons[0]
	var near_demon := place("thief", Vector2i(0, 0), 1)
	board.claim(near_demon, board.neighbors(demon.coord).filter(func(c): return board.tiles[c].occupant == null)[0])
	var nd0 := near_demon.health
	demon.take_damage(9999.0)
	chk("a dying demon explodes for 150 on adjacent enemies", demon.dead and is_equal_approx(nd0 - near_demon.health, 150.0), str(nd0 - near_demon.health))
	clear_units()
	gm.new_summons.clear()

	var bm := place("beastmaster", Vector2i(3, 6))
	var bfoe := place("knight", Vector2i(3, 2), 1)
	bm._cast(bfoe)
	chk("Jungle Call: two beasts", Abilities.living_summons(bm).size() == 2)
	bm.summons[0].take_damage(9999.0)
	bm._cast(bfoe)
	chk("casting again brings back the one that died", Abilities.living_summons(bm).size() == 2 and bm.summons.size() == 3)
	clear_units()
	gm.new_summons.clear()

	var pd := place("plague_doctor", Vector2i(3, 6))
	var lone2 := place("thief", Vector2i(0, 0), 1)
	var p1 := place("thief", Vector2i(5, 2), 1)
	var p2 := place("thief", Vector2i(5, 1), 1)
	gm.combatants.assign([pd, lone2, p1, p2])
	pd._cast(lone2)
	chk("Miasma: a zone on the cluster", gm.zones.size() == 1 and gm.zones[0].center in [p1.coord, p2.coord])
	for i in 240:
		gm._tick_zones()
	chk("enemies in it take 50 a second for 4 s (cursed by it after the first tick), the lone one nothing", is_equal_approx(p1.max_hp() - p1.health, 50.0 / 60.0 + 239.0 * 50.0 / 60.0 * 1.15) and lone2.health == lone2.max_hp(), str(p1.max_hp() - p1.health))
	chk("and the zone is gone after 4 s", gm.zones.is_empty() and pd.damage_dealt > 399.0)
	clear_units()

	var dru := place("druid", Vector2i(3, 6))
	var close_ally := place("knight", Vector2i(3, 5))
	var far_ally2 := place("knight", Vector2i(0, 7))
	var dfoe2 := place("thief", Vector2i(3, 2), 1)
	close_ally.health = 100.0
	far_ally2.health = 100.0
	gm.combatants.assign([dru, close_ally, far_ally2, dfoe2])
	dru._cast(dfoe2)
	for i in 60:
		gm._tick_zones()
	chk("Antler Grove: allies within 1 hex regenerate 3% a second", is_equal_approx(close_ally.health, 100.0 + close_ally.max_hp() * 0.03) and far_ally2.health == 100.0, str(close_ally.health))
	gm.zones.clear()
	clear_units()

	var rs := place("runesmith", Vector2i(3, 6))
	var warded := place("knight", Vector2i(3, 4))
	var brute := place("guardian", Vector2i(3, 3), 1)
	warded.health = 200.0
	rs._cast(brute)
	var b0 := brute.health
	brute._attack(warded)
	chk("Rune Ward: a shield and thorns (20 per hit back)", warded.ab_shield > 0.0 and is_equal_approx(b0 - brute.health, 20.0), str(b0 - brute.health))
	timers([warded], 4.05)
	var b1 := brute.health
	brute._attack(warded)
	chk("the thorns run out after 4 s", brute.health == b1)
	clear_units()

	print("--- summons in a real fight")
	var fsigs: PackedStringArray = []
	for i in 2:
		await load_main(4242)
		_summon_fight()
		gm.start_combat()
		gm.resolve_combat()
		fsigs.append(_signature())
		await get_tree().process_frame
	var left_over := 0
	for n in board.get_node("Units").get_children():
		if (n as Unit).summoned and not n.is_queued_for_deletion():
			left_over += 1
	var on_tiles := 0
	for t in board.tiles.values():
		if t.occupant != null and is_instance_valid(t.occupant) and t.occupant.summoned:
			on_tiles += 1
	chk("summons took part", fsigs[0].contains("Bone Thrall") or fsigs[0].contains("Jungle Beast") or fsigs[0].contains("Pact Demon"), fsigs[0].left(160))
	chk("the same fight with summons twice gives the same result", fsigs[0] == fsigs[1])
	chk("when it ends every summon is gone and your units are back on their tiles", left_over == 0 and on_tiles == 0 and board.tiles[board.player_order[0]].occupant != null)

	print("--- chunk 4: special rules")
	var th := place("thief", Vector2i(3, 4))
	var mark := place("knight", Vector2i(3, 3), 1)
	var gold0 := GameState.me.gold
	th._cast(mark)
	chk("Pickpocket without a kill: no gold", GameState.me.gold == gold0)
	mark.health = 10.0
	th._cast(mark)
	chk("Pickpocket kill: 1 gold", GameState.me.gold == gold0 + 1)
	var enemy_thief := place("thief", Vector2i(5, 3), 1)
	var mine_low := place("militia", Vector2i(5, 4))
	mine_low.health = 10.0
	enemy_thief._cast(mine_low)
	chk("an enemy Thief's kill gives you nothing", GameState.me.gold == gold0 + 1 and mine_low.dead)
	clear_units()

	var mn := place("minstrel", Vector2i(3, 6))
	var fullish := place("mage", Vector2i(2, 6))
	var half_full := place("archer", Vector2i(4, 6))
	var empty := place("knight", Vector2i(3, 5))
	var mfoe := place("thief", Vector2i(3, 2), 1)
	fullish.mana = 40.0
	half_full.mana = 30.0
	empty.mana = 0.0
	mn._cast(mfoe)
	chk("Encore: +30 mana for the two allies closest to a full bar", is_equal_approx(fullish.mana, 50.0) and is_equal_approx(half_full.mana, 60.0) and empty.mana == 0.0 and mn.mana == 0.0)
	clear_units()

	var pal := place("paladin", Vector2i(3, 6))
	var ward := place("archer", Vector2i(3, 4))
	var pfoe := place("knight", Vector2i(3, 3), 1)
	ward.health = 100.0
	pal._cast(pfoe)
	chk("Loyal Guard heals the weakest ally", is_equal_approx(ward.health, 250.0))
	var w0 := ward.health
	var pa0 := pal.health + pal.shield
	ward.take_damage(100.0)
	chk("and half of what it takes goes to the Paladin", is_equal_approx(w0 - ward.health, 50.0) and is_equal_approx(pa0 - pal.health - pal.shield, 50.0))
	timers([ward], 4.05)
	var w1 := ward.health
	ward.take_damage(100.0)
	chk("for 4 s", is_equal_approx(w1 - ward.health, 100.0))
	clear_units()

	var du := place("duelist", Vector2i(3, 4))
	var swinger := place("knight", Vector2i(3, 3), 1)
	du._cast(swinger)
	var d0 := du.health
	var s0 := swinger.health
	swinger._attack(du)
	chk("Riposte: the attack is parried and countered for 80", du.health == d0 and is_equal_approx(s0 - swinger.health, 80.0))
	timers([du], 2.05)
	swinger._attack(du)
	chk("the stance lasts 2 s", du.health < d0)
	clear_units()

	var mg := place("magma_guard", Vector2i(3, 4))
	var hugger := place("guardian", Vector2i(3, 3), 1)
	mg._cast(hugger)
	var hu0 := hugger.health
	mg.take_damage(399.0)
	chk("Molten Shell: nothing until the shield breaks", hugger.health == hu0)
	mg.take_damage(10.0)
	chk("when it breaks, adjacent enemies take 400 and burn", is_equal_approx(hu0 - hugger.health, 400.0) and hugger.burn_left > 0.0 and mg.erupt_dmg == 0.0)
	mg._cast(hugger)
	var hu1 := hugger.health
	timers([mg], 5.05)
	chk("it also erupts when it runs out", hugger.health < hu1)
	clear_units()

	var zm := place("zen_master", Vector2i(3, 4))
	var caster := place("mage", Vector2i(3, 3), 1)
	caster.mana = 45.0
	zm._cast(caster)
	chk("Pressure Point: stunned for 2 s and the mana emptied", caster.stun_left == 2.0 and caster.mana == 0.0)
	clear_units()

	var dl := place("deathlord", Vector2i(3, 5))
	var fallen_ally := place("knight", Vector2i(2, 5))
	var dfoe3 := place("guardian", Vector2i(3, 3), 1)
	var df0 := dfoe3.health
	dl._cast(dfoe3)
	chk("Army of the Dead with nobody fallen: strikes for 400", is_equal_approx(df0 - dfoe3.health, 400.0) and not dl.army_used)
	fallen_ally.take_damage(9999.0)
	dl._cast(dfoe3)
	chk("the fallen rise at 30% HP", not fallen_ally.dead and is_equal_approx(fallen_ally.health, fallen_ally.max_hp() * 0.3) and board.tiles[fallen_ally.coord].occupant == fallen_ally)
	timers([fallen_ally], 5.05)
	chk("and fall again after 5 s", fallen_ally.dead and board.tiles[Vector2i(2, 5)].occupant == null)
	var df1 := dfoe3.health
	dl._cast(dfoe3)
	chk("only once a fight: then it strikes", df1 - dfoe3.health > 0.0)
	clear_units()

	var ph := place("phoenix", Vector2i(3, 6))
	var friend := place("knight", Vector2i(3, 5))
	var b_1 := place("guardian", Vector2i(3, 2), 1)
	var b_2 := place("guardian", Vector2i(5, 1), 1)
	friend.health = 100.0
	ph._cast(b_1)
	chk("Sunfire Nova sets every enemy burning (6% a second)", is_equal_approx(b_1.burn_dps, b_1.max_hp() * 0.06) and b_2.burn_left == 6.0)
	timers([b_1, b_2, ph, friend], 1.0)
	chk("allies heal from the burn damage", friend.health > 100.0 and ph.damage_dealt > 0.0, "%.1f" % friend.health)
	clear_units()

	var ad := place("archdemon", Vector2i(3, 6))
	var big := place("titan", Vector2i(3, 2), 1)
	var small := place("thief", Vector2i(4, 2), 1)
	ad._cast(small)
	chk("Doom falls on the enemy with the most HP", big.doom_left == 4.0 and small.doom_left == 0.0)
	var bg0 := big.health
	timers([big], 4.05)
	chk("after 4 s it takes 600", is_equal_approx(bg0 - big.health, 600.0) and big.doom_left == 0.0)
	ad._cast(small)
	big.take_damage(99999.0)
	chk("if it dies first, the doom jumps to its nearest ally", small.doom_left == 4.0 and small.doom_by == ad)
	clear_units()

	var fq := place("frost_queen", Vector2i(3, 6))
	var sturdy := place("titan", Vector2i(3, 2), 1)
	var frail := place("thief", Vector2i(1, 1), 1)
	frail.health = frail.max_hp() * 0.55
	gm.combatants.assign([fq, sturdy, frail])
	fq._cast(sturdy)
	gm._tick_zones()
	chk("Eternal Winter chills every enemy", sturdy.chill_on == 0.5 and frail.chill_on == 0.5)
	for i in 240:
		gm._tick_zones()
	chk("when it ends, enemies below half HP freeze", frail.stun_left == 1.5 and sturdy.stun_left == 0.0 and gm.zones.is_empty())
	clear_units()

	var fae := place("faerie_queen", Vector2i(3, 6))
	var star_foe := place("knight", Vector2i(3, 3), 1)
	var buddy := place("knight", Vector2i(4, 3), 1)
	var meh := place("thief", Vector2i(0, 0), 1)
	var mine2 := place("militia", Vector2i(3, 4))
	star_foe.damage_dealt = 500.0
	buddy.damage_dealt = 300.0
	fae._cast(star_foe)
	chk("Moonlit Charm takes the two enemies that dealt the most", star_foe.charm_left == 3.0 and buddy.charm_left == 3.0 and meh.charm_left == 0.0)
	chk("charmed, they turn on their own side", board.nearest_enemy(star_foe) == buddy and board.nearest_enemy(mine2) == star_foe)
	chk("marked as hexed: sigil, thread and a pink-violet ring", star_foe._charm_fx != null and star_foe._charm_fx.get_node("Sigil") != null and (star_foe._ring_mat == null or star_foe._ring_mat.albedo_color == Unit.CHARM_COLOR))
	star_foe.mana = star_foe.data.max_mana
	var made2 := star_foe.attacks_made
	steps([star_foe], 0.5)
	chk("a charmed unit attacks instead of casting", star_foe.attacks_made > made2)
	timers([star_foe, buddy], 3.05)
	chk("then it is freed and fights for its side again", star_foe.charm_left == 0.0 and star_foe._charm_fx == null and board.nearest_enemy(star_foe) != buddy)
	clear_units()

	var rp := place("reaper", Vector2i(3, 4))
	var r1 := place("thief", Vector2i(3, 3), 1)
	var r2 := place("guardian", Vector2i(2, 3), 1)
	r1.health = 400.0
	rp._cast(r1)
	chk("Scythe Sweep executes the one left below 20% and refunds 40 mana", r1.dead and not r2.dead and is_equal_approx(rp.mana, 40.0), "mana %d" % rp.mana)
	clear_units()

	var tr := place("treant", Vector2i(3, 5))
	var walker := place("knight", Vector2i(3, 3), 1)
	var outside := place("archer", Vector2i(6, 0), 1)
	tr.health = 500.0
	tr._cast(walker)
	chk("Overgrowth roots enemies within 2 hexes and heals the Treant", walker.root_left == 2.0 and outside.root_left == 0.0 and tr.health > 500.0, "%s %s" % [walker.root_left, outside.root_left])
	var spot0 := walker.coord
	walker.target = tr
	steps([walker], 1.0)
	chk("a rooted unit doesn't move", walker.coord == spot0)
	clear_units()

	print("--- chunk 4 in a real fight")
	var ssigs: PackedStringArray = []
	for i in 3:
		await load_main(9090)
		_special_fight()
		gm.start_combat()
		if i < 2:
			gm.resolve_combat()
		else:
			await Events.combat_ended
		ssigs.append(_signature())
		await get_tree().process_frame
	chk("a fight full of special rules gives the same result twice", ssigs[0] == ssigs[1], ssigs[0].left(140))
	chk("and the same in real time", ssigs[0] == ssigs[2])
	var hexed_left := 0
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u != null and not u.is_queued_for_deletion() and (u.charm_left > 0.0 or u._charm_fx != null or u.raised_left > 0.0):
			hexed_left += 1
	chk("nothing is left charmed or raised after the fight", hexed_left == 0)

	print("--- spell effects (turned on in a headless run)")
	Vfx.enabled = true
	var before := main.get_child_count()
	var cast_errors := 0
	for d in roster:
		var fx_caster := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(fx_caster)
		fx_caster.setup(d, 0)
		board.put_on_tile(fx_caster, Vector2i(3, 5))
		fx_caster.begin_combat()
		var buddy2 := place("knight", Vector2i(2, 5))
		var foes2: Array[Unit] = [place("guardian", Vector2i(3, 4), 1), place("thief", Vector2i(4, 3), 1), place("archer", Vector2i(2, 1), 1)]
		buddy2.health = 100.0
		gm.combatants.assign([fx_caster, buddy2] + foes2)
		fx_caster._cast(foes2[0])
		for i in 30:
			gm._tick_zones()
		await get_tree().process_frame
		if not is_instance_valid(fx_caster):
			cast_errors += 1
		clear_units()
		gm.zones.clear()
		gm.new_summons.clear()
	await get_tree().process_frame
	chk("every ability casts with its effects on, without errors", cast_errors == 0)
	chk("the effects are made as nodes in the world", main.get_child_count() > before, "%d -> %d" % [before, main.get_child_count()])
	var st := place("knight", Vector2i(3, 5))
	st.apply_stun(1.0)
	st.add_buff("Test", "as", 0.2, 2.0)
	st.add_timed_shield(100.0, 2.0)
	st.doom_left = 3.0
	await get_tree().process_frame
	chk("status marks follow the unit's state (stun, buff, shield, doom)", st._status != null and st._status.get_node("stun").visible and st._status.get_node("buff").visible and st._status.get_node("shield").visible and (st._status.get_node("doom") as Label3D).text == "DOOM 3")
	st.stun_left = 0.0
	st.buffs.clear()
	st.ab_shield = 0.0
	st.doom_left = 0.0
	await get_tree().process_frame
	chk("and go away when it ends", st._status == null)
	clear_units()
	Vfx.enabled = false

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
	GameState.me.level = 9
	var mine := [["frost_giant", 2], ["bard", 1], ["lich", 1], ["mage", 1], ["militia", 2], ["initiate", 1], ["cleric", 1], ["warlord", 1], ["nightstalker", 1]]
	for i in mine.size():
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(UD(mine[i][0]), 0)
		u.set_star(mine[i][1])
		board.put_on_tile(u, board.player_order[i])
	var wave := EnemyBoard.new()
	wave.display_name = "Casters"
	for e in [["guardian", Vector2i(3, 3), 2], ["titan", Vector2i(4, 3), 1], ["ice_mage", Vector2i(3, 1), 2], ["skald", Vector2i(2, 3), 1], ["shadowfist", Vector2i(4, 2), 2], ["dragon", Vector2i(3, 0), 1], ["acolyte", Vector2i(5, 1), 2], ["assassin", Vector2i(1, 3), 1], ["seraph", Vector2i(1, 0), 1], ["scout", Vector2i(6, 1), 1]]:
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

# Summoners on both sides.
func _summon_fight():
	GameState.me.level = 9
	var mine := [["necromancer", 2], ["beastmaster", 1], ["knight", 2], ["druid", 1], ["runesmith", 1]]
	for i in mine.size():
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(UD(mine[i][0]), 0)
		u.set_star(mine[i][1])
		u.mana = u.data.max_mana
		board.put_on_tile(u, board.player_order[i])
	var wave := EnemyBoard.new()
	wave.display_name = "Summoners"
	for e in [["demonologist", Vector2i(3, 3), 2], ["guardian", Vector2i(4, 3), 2], ["plague_doctor", Vector2i(3, 1), 1], ["necromancer", Vector2i(2, 2), 1]]:
		var bu := BoardUnit.new()
		bu.unit = UD(e[0])
		bu.coord = e[1]
		bu.star = e[2]
		wave.units.append(bu)
	var waves: Array[EnemyBoard] = [wave]
	gm.opponents = WaveOpponents.new(waves, 1.0)

# The chunk 4 units on both sides (they start with full mana, so every one casts early).
func _special_fight():
	GameState.me.level = 9
	var mine := [["paladin", 2], ["duelist", 1], ["faerie_queen", 1], ["deathlord", 1], ["thief", 2], ["minstrel", 1], ["reaper", 1], ["phoenix", 1], ["treant", 1]]
	for i in mine.size():
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(UD(mine[i][0]), 0)
		u.set_star(mine[i][1])
		u.mana = u.data.max_mana
		board.put_on_tile(u, board.player_order[i])
	var wave := EnemyBoard.new()
	wave.display_name = "Specials"
	for e in [["magma_guard", Vector2i(3, 3), 2], ["zen_master", Vector2i(4, 3), 1], ["archdemon", Vector2i(3, 1), 1], ["frost_queen", Vector2i(4, 1), 1], ["faerie_queen", Vector2i(2, 2), 1], ["deathlord", Vector2i(5, 2), 1], ["duelist", Vector2i(2, 3), 2]]:
		var bu := BoardUnit.new()
		bu.unit = UD(e[0])
		bu.coord = e[1]
		bu.star = e[2]
		wave.units.append(bu)
	var waves: Array[EnemyBoard] = [wave]
	gm.opponents = WaveOpponents.new(waves, 1.0)
