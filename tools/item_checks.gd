# item_checks.gd
# Dev tool, not part of the game: checks items v2 (docs/items-v2.md): the 15 item types (the Ancient Sigil and 4-star units too), resonance
# (pairs, Prism, the Crystal), bound items growing (survive, cap, sell resets, merge keeps), the
# equip rules, Tinker's Tongs, synergy benders, the economy items, the 14-drop table and saving
# stacks in chapter runs and snapshots. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/item_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway save and snapshot files.

extends Node

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

func I(id: String) -> ItemData:
	return load("res://tres/items/%s.tres" % id)

func UD(n: String) -> UnitData:
	var p := "res://tres/units/%s.tres" % n
	return load(p if ResourceLoader.exists(p) else "res://tres/%s.tres" % n)

func load_main(seed := 0):
	if main != null:
		main.free()
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.ghost_mode = false
	GameState.next_seed = seed
	GameState.reset()
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

func place(n: String, i: int) -> Unit:
	var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(u)
	u.setup(UD(n), 0)
	if i >= 0:
		board.put_on_tile(u, board.player_order[i])
	else:
		board.put_on_bench(u, board.first_free_bench())
	return u

func _run():
	SaveGame.path = "user://item_test_save.json"
	SaveGame.reset_progress()
	LocalSnapshotStore.root = "user://item_test_snapshots"
	await load_main(5)

	print("--- the 45 items (items v3: 4 per stat, plus the 9 unique items)")
	var roster: Array = gm.item_roster
	var kinds := {}
	for it in roster:
		kinds[String(it.kind)] = int(kinds.get(String(it.kind), 0)) + 1
	chk("45 item types: 36 stat items, 2 bound, 2 economy, 2 benders, the Crystal, the Tongs and the Ancient Sigil", roster.size() == 45 and kinds == {"basic": 36, "bound": 2, "economy": 2, "bender": 2, "crystal": 1, "remover": 1, "ascension": 1}, str(kinds))
	# Each stat's four items, the element that stat belongs to, and the property it raises.
	var by_stat := {
		"attack power": [&"Might", "attack_power", ["longsword", "war_axe", "serrated_dirk", "giants_maul"]],
		"HP": [&"Vigor", "hp", ["iron_belt", "troll_hide", "heart_locket", "ogres_girdle"]],
		"mitigation": [&"Vigor", "mitigation", ["leather_jerkin", "hide_bracers", "padded_gambeson", "stone_ring"]],
		"attack speed": [&"Swift", "attack_speed", ["quick_bow", "swift_gloves", "wind_charm", "feather_boots"]],
		"armour": [&"Guard", "armor", ["chain_vest", "tower_shield", "bronze_buckler", "plate_cuirass"]],
		"magic resist": [&"Guard", "magic_resist", ["warding_cloak", "silver_circlet", "spellward_talisman", "nullstone_amulet"]],
		"omnivamp": [&"Blood", "lifesteal", ["blood_fang", "vampire_ring", "hungering_blade", "sanguine_tome"]],
		"ability power": [&"Arcane", "ability_power", ["apprentice_wand", "sages_staff", "hex_orb", "archmages_tome"]],
		"mana": [&"Arcane", "mana", ["mana_charm", "spirit_bead", "moon_tear", "focus_gem"]],
	}
	var wrong: Array = []
	var listed := {}
	for stat in by_stat:
		var row: Array = by_stat[stat]
		for id in row[2]:
			var it := I(id)
			listed[id] = true
			if it == null or it.kind != &"basic" or it.element != row[0] or float(it.get(row[1])) <= 0.0 or not roster.has(it):
				wrong.append(id)
	chk("4 items for each of the 9 stats, each in its stat's element and in the roster", wrong.is_empty() and listed.size() == 36, str(wrong))
	var weight := {}
	for it in roster.filter(func(i): return i.kind == &"basic"):
		weight[it.element] = float(weight.get(it.element, 0.0)) + it.drop_weight
	chk("every element drops as often as the others (equal drop weight), so resonances stay evenly spread", Resonance.ELEMENTS.all(func(e): return is_equal_approx(float(weight.get(e, 0.0)), 4.0)), str(weight))
	var no_icon: Array = roster.filter(func(i): return not ResourceLoader.exists("res://textures/ui/items/%s.png" % i.id)).map(func(i): return i.id)
	chk("every item has an icon", no_icon.is_empty(), str(no_icon))
	chk("Mana Charm: +15 start mana, +8% ability power", is_equal_approx(I("mana_charm").mana, 15.0) and is_equal_approx(I("mana_charm").ability_power, 0.08))
	chk("every stat item has a Best on line", roster.filter(func(i): return i.kind == &"basic" and i.best_on() == "").is_empty())

	print("--- resonance")
	chk("Longsword + Quick Bow: Flurry", Resonance.keys_for([I("longsword"), I("quick_bow")]) == ["Might+Swift"] and Resonance.unit_effects([I("longsword"), I("quick_bow")]).get("crit") == 3.0)
	chk("two of the same element: nothing", Resonance.keys_for([I("longsword"), I("heros_blade")]).is_empty())
	var three := Resonance.keys_for([I("iron_belt"), I("chain_vest"), I("blood_fang")])
	chk("three different elements: three pairs and Prism", three == ["Vigor+Guard", "Vigor+Blood", "Guard+Blood", "Prism"], str(three))
	chk("all 15 pairs exist", Resonance.PAIRS.size() == 15)
	var doubled := Resonance.unit_effects([I("longsword"), I("quick_bow"), I("resonance_crystal")])
	chk("the Crystal doubles: every 3rd attack becomes every 2nd", doubled.get("crit") == 2)
	var shielded := Resonance.unit_effects([I("iron_belt"), I("chain_vest"), I("resonance_crystal")])
	chk("the Crystal doubles amounts: Bulwark's shield 25% -> 50%", is_equal_approx(float(shielded.get("shield", 0.0)), 0.5))
	var alone := Resonance.unit_effects([I("resonance_crystal")])
	chk("the Crystal with no resonance: +8% HP, attack power and ability power", is_equal_approx(float(alone.get("hp", 0.0)), 0.08) and is_equal_approx(float(alone.get("ad", 0.0)), 0.08) and is_equal_approx(float(alone.get("ap", 0.0)), 0.08))
	var k := place("knight", 0)
	k.equip(I("iron_belt"))
	k.equip(I("chain_vest"))
	Synergies.apply([k])
	k.begin_combat()
	chk("resonance reaches the fight: Bulwark gives a 25% shield", is_equal_approx(k.shield_pct, 0.25) and is_equal_approx(k.shield, k.max_hp() * 0.25))
	k.end_combat()

	print("--- equip rules and bound items")
	await load_main(6)
	var a := place("knight", 0)
	chk("a bound item equips", a.equip(I("heros_blade")))
	chk("a second copy of the same bound item fits", a.can_take(I("heros_blade")))
	chk("Tinker's Tongs are never worn", not a.can_take(I("tinkers_tongs")))
	var b := place("archer", 1)
	b.equip(I("twin_sigil"))
	chk("one synergy bender per unit", not b.can_take(I("twin_crest")))
	var dmg0 := a.damage()
	a.end_combat()
	chk("surviving a fight adds a stack: +4% attack power", a.stacks_of(I("heros_blade")) == 1 and is_equal_approx(a.damage() - dmg0, a.data.attack_damage * 0.04))
	a.dead = true
	a.end_combat()
	chk("a fight it doesn't survive adds nothing", a.stacks_of(I("heros_blade")) == 1)
	for i in 30:
		a.end_combat()
	chk("stacks stop at 15", a.stacks_of(I("heros_blade")) == 15)
	board.sell_unit(a)
	chk("selling returns the item with no stacks", GameState.me.items.has(I("heros_blade")))
	GameState.me.items.clear()
	# Two Hero's Blades on one unit grow apart.
	var two := place("knight", 2)
	two.equip(I("heros_blade"))
	two.end_combat()
	two.equip(I("heros_blade"))
	var dmg2 := two.damage()
	two.end_combat()
	chk("two Hero's Blades on one unit keep their own stacks (2 and 1)", two.stacks_at(0) == 2 and two.stacks_at(1) == 1, str(two.item_stacks))
	chk("both add their stacks to attack power", is_equal_approx(two.damage() - dmg2, two.data.attack_damage * 0.08), str(two.damage() - dmg2))
	board.sell_unit(two)
	GameState.me.items.clear()
	# Merge: three Knights, each blade keeps its own stacks on the kept unit.
	var ks: Array = []
	for i in 3:
		ks.append(place("knight", -1))
	ks[1].equip(I("heros_blade"))
	ks[1].item_stacks[&"heros_blade"] = 9
	ks[2].equip(I("heros_blade"))
	ks[2].item_stacks[&"heros_blade"] = 4
	for i in 2:
		ks[2].equip(I("longsword"))
	board.merge_all()
	var merged: Array = board.all_player_units().filter(func(u): return u.data.display_name == "Knight" and u.star == 2)
	var got: Array = []
	if merged.size() == 1:
		for i in merged[0].items.size():
			if merged[0].items[i].id == &"heros_blade":
				got.append(merged[0].stacks_at(i))
	got.sort()
	chk("merging keeps both blades with their own stacks (4 and 9)", got == [4, 9], str(merged[0].item_stacks) if not merged.is_empty() else "no merge")
	chk("an item past the 3-item limit goes back to the inventory", GameState.me.items.has(I("longsword")))

	print("--- Tinker's Tongs")
	await load_main(7)
	var t := place("knight", 0)
	t.equip(I("longsword"))
	t.equip(I("heartwood_charm"))
	t.item_stacks[&"heartwood_charm"] = 3
	var dc = main.get_node("DragController")
	GameState.me.items.append(I("tinkers_tongs"))
	chk("Tongs on a unit with items, in prep: items back, Tongs used up", dc.equip_item_on(t, I("tinkers_tongs")) and t.items.is_empty() and t.item_stacks.is_empty() and GameState.me.items.has(I("longsword")) and GameState.me.items.has(I("heartwood_charm")) and not GameState.me.items.has(I("tinkers_tongs")))
	GameState.me.items.append(I("tinkers_tongs"))
	chk("Tongs on a unit with no items do nothing", not dc.equip_item_on(t, I("tinkers_tongs")) and GameState.me.items.has(I("tinkers_tongs")))
	t.equip(I("longsword"))
	dc.in_prep = false
	chk("Tongs don't work during a fight", not dc.equip_item_on(t, I("tinkers_tongs")) and t.items.size() == 1)
	dc.in_prep = true

	print("--- synergy benders")
	var k1 := place("knight", 1)
	var m1 := place("militia", 2)
	chk("Knight + Militia: Order 2", Synergies.count([k1, m1]).get("Order") == 2)
	k1.equip(I("twin_sigil"))
	chk("Twin Sigil on the Knight: Order counts 3", Synergies.count([k1, m1]).get("Order") == 3)
	var k2 := place("knight", 3)
	chk("a second Knight without the sigil doesn't add more", Synergies.count([k1, k2, m1]).get("Order") == 3)
	m1.equip(I("twin_crest"))
	chk("Twin Crest on the Militia: Protector (its first class) counts 2", Synergies.count([k1, m1]).get("Protector") == 2)

	print("--- economy items")
	await load_main(8)
	var p := place("knight", 0)
	p.equip(I("coin_purse"))
	var benched := place("archer", -1)
	benched.equip(I("coin_purse"))
	chk("Coin Purse pays only from the board: 1 gold", gm.item_income() == 1)
	GameState.me.gold = 0
	var expected: int = GameState.me.total_income_for_round(GameState.round_number + 1) + 1
	GameState.round_number += 1
	gm._enter(Events.Phase.PREP)
	chk("next round's income includes the purse", GameState.me.gold == expected, "%d vs %d" % [GameState.me.gold, expected])
	p.equip(I("merchants_ledger"))
	gm._enter(Events.Phase.PREP)
	GameState.me.gold = 10
	Events.reroll_pressed.emit()
	var after_free: int = GameState.me.gold
	Events.reroll_pressed.emit()
	chk("Merchant's Ledger: the first reroll is free, the second costs 2", after_free == 10 and GameState.me.gold == 8, "%d then %d" % [after_free, GameState.me.gold])
	var p2 := place("archer", 1)
	p2.equip(I("merchants_ledger"))
	gm._enter(Events.Phase.PREP)
	chk("two Ledgers on the board give two free rerolls", GameState.me.free_rerolls == 2)
	gm._enter(Events.Phase.PREP)
	chk("unused free rerolls carry into the next round", GameState.me.free_rerolls == 4, str(GameState.me.free_rerolls))
	GameState.me.free_rerolls = 0

	print("--- drops")
	chk("14 drop rounds in a free-play run, Tongs at the end of stages 2 to 6 (and one in each chapter level)", GameState.ITEM_DROP_ROUNDS.size() == 14 and GameState.TONGS_ROUNDS == [9, 15, 21, 27, 33] and GameState.CAMPAIGN_TONGS_ROUND == 3)
	var popup = main.get_node_or_null("UI/ItemPopup")
	if popup != null:
		popup._queue.clear()   # (an earlier PREP's drop may still be showing)
		popup._busy = false
	var shown_before: int = popup.shown if popup != null else -1
	var got_before := GameState.me.items.size()
	gm.rules.drop_item(9)   # a drop round and a Tongs round: two items at once
	await get_tree().process_frame
	chk("a drop pops up its items side by side", popup != null and popup.shown == shown_before + 1 and GameState.me.items.size() == got_before + 2 and popup._cards.size() == 2, "popup %s, %d cards" % [popup != null, popup._cards.size() if popup != null else 0])
	if popup != null and popup._cards.size() == 2:
		var gap: float = popup._cards[1].position.x - popup._cards[0].position.x
		chk("the cards stand far enough apart that their names don't overlap", gap >= ItemPopup.NAME_W + 8.0, str(gap))
	GameState.me.items.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var early := true
	for i in 300:
		early = early and gm.pick_drop(2, rng, {}).kind == &"basic"
	chk("stages 1-2: basic items only", early)
	var specials := 0
	var benders := 0
	var tongs := 0
	for i in 600:
		var it: ItemData = gm.pick_drop(3, rng, {})
		specials += int(it.is_special())
		benders += int(it.kind == &"bender")
		tongs += int(it.kind == &"remover")
	chk("stage 3: about 30% special items, no benders or Tongs", specials > 120 and specials < 240 and benders == 0 and tongs == 0, "%d of 600" % specials)
	var seen := {}
	var late_benders := 0
	for i in 600:
		var it: ItemData = gm.pick_drop(5, rng, seen)
		if it.kind == &"bender":
			late_benders += 1
			seen[it.id] = 1
	chk("stage 5: each bender drops at most once a run", late_benders >= 1 and late_benders <= 2, str(late_benders))
	GameState.me.items.clear()
	GameState.round_number = 15
	gm._drop_item()
	chk("round 3-6 drops an item and Tinker's Tongs", GameState.me.items.size() == 2 and GameState.me.items.has(I("tinkers_tongs")))

	print("--- saving stacks")
	await load_main(9)
	var s := place("knight", 0)
	s.equip(I("heros_blade"))
	s.item_stacks[&"heros_blade"] = 6
	s._recalc_items()
	var carry: Dictionary = gm.make_carry(load("res://tres/campaign/levels/ch1_l2.tres"))
	var json_carry = JSON.parse_string(JSON.stringify(carry))   # through the save format
	await load_main(10)
	gm._restore_carry(json_carry)
	var back: Array = board.all_player_units().filter(func(u): return u.data.display_name == "Knight")
	chk("a chapter run carries bound stacks to the next level", back.size() == 1 and back[0].stacks_of(I("heros_blade")) == 6, str(back[0].item_stacks) if not back.is_empty() else "missing")
	var snap := BoardSnapshot.capture(back, {"name": "You", "run": "r", "round": 5, "level": 5, "hp": 80, "balance": "x"})
	var eb := BoardSnapshot.to_board(JSON.parse_string(JSON.stringify(snap)), gm.unit_pool, gm.item_roster)
	chk("a ghost snapshot keeps the stacks", eb.units.size() == 1 and int(eb.units[0].stacks.get(&"heros_blade", 0)) == 6)
	var old_dict := {"units": [{"unit": "Knight", "star": 1, "coord": [3, 3], "items": ["longsword"]}]}
	var old_eb := EnemyBoard.from_dict(old_dict, gm.unit_pool, gm.item_roster)
	chk("an old board without stacks still loads", old_eb.units.size() == 1 and old_eb.units[0].stacks.is_empty() and old_eb.units[0].items.size() == 1)

	print("--- the Ancient Sigil and 4 stars")
	await load_main(12)
	var sig := I("ancient_sigil")
	chk("the Ancient Sigil is in the roster: very rare, from stage 4, 8 marks", gm.item_roster.has(sig) and sig.kind == &"ascension" and sig.min_stage == 4 and sig.max_stacks == 8 and sig.drop_weight < 0.5 and sig.once_a_run())
	var low := place("knight", 0)
	low.set_star(2)
	var hero := place("archer", 1)
	hero.set_star(3)
	chk("a sigil goes on any unit, one a unit", low.can_take(sig) and hero.equip(sig) and not hero.can_take(sig))
	low.equip(sig)
	for i in 3:
		low.count_sigil_win()
	chk("marks only count on a 3-star unit", low.stacks_of(sig) == 0 and low.star == 2)
	var base_hp: float = hero.max_hp()
	for i in 7:
		hero.count_sigil_win()
	chk("7 wins: 7 marks, still 3 stars", hero.stacks_of(sig) == 7 and hero.star == 3 and hero.items.has(sig))
	var ascended := []
	Events.unit_ascended.connect(func(u): ascended.append(u), CONNECT_ONE_SHOT)
	chk("the 8th win ascends it", hero.count_sigil_win() and hero.star == 4 and ascended == [hero])
	chk("the sigil is used up (its slot and marks gone)", not hero.items.has(sig) and not hero.item_stacks.has(sig.id) and hero.can_equip())
	chk("4 stars: x5 HP and damage (3 stars x3.2)", is_equal_approx(hero.max_hp(), base_hp / 3.2 * 5.0) and is_equal_approx(Unit.star_mult(4, 1), 5.0))
	chk("a 5-cost at 4 stars: x7.5", is_equal_approx(Unit.star_mult(4, 5), 7.5) and is_equal_approx(Unit.star_mult(3, 5), 5.0))
	chk("an ascended unit can't take another sigil", not hero.can_take(sig))
	chk("its model is the astral form, bigger", hero.model_view == null or (hero.model_view.star_scenes.size() == 4 and hero.model_view._star == 4 and is_equal_approx(hero.get_node("ModelHolder").scale.x, Unit.STAR_SIZE[4])))
	chk("its ability numbers scale with it", Abilities.value_at(100, 4, 1) == 500.0 and Abilities.value_at([1, 2, 3], 4, 1) == 3.0)
	var ally := place("knight", 2)
	ally.set_star(3)
	ally.equip(sig)
	ally.end_combat(false)
	chk("a lost fight adds no mark", ally.stacks_of(sig) == 0)
	ally.end_combat(true)
	chk("a won fight it survives adds one", ally.stacks_of(sig) == 1)
	ally.dead = true
	ally.end_combat(true)
	chk("not if it fell", ally.stacks_of(sig) == 1)
	var five := place("knight", 3)
	five.set_star(3)
	board.merge_all()
	chk("merging never makes a 4-star", board.all_player_units().all(func(u): return u.star <= 4) and hero.star == 4 and five.star == 3)
	gm.shared_pool.take_copies(hero.data, 9)   # (placed by hand: take its copies out as buying would)
	var gold_before: int = GameState.me.gold
	var copies_before: int = gm.shared_pool.remaining.get(hero.data, 0)
	board.sell_unit(hero)
	chk("selling a 4-star is selling its 3-star: 9 copies back, 9x its cost", GameState.me.gold - gold_before == hero.data.cost * 9 and gm.shared_pool.remaining.get(hero.data, 0) - copies_before == 9)
	var asc := place("archer", 4)
	asc.set_star(4)
	var carry4: Dictionary = gm.make_carry(load("res://tres/campaign/levels/ch1_l2.tres"))
	var json4 = JSON.parse_string(JSON.stringify(carry4))
	await load_main(13)
	gm._restore_carry(json4)
	chk("a chapter run keeps a 4-star", board.all_player_units().any(func(u): return u.data.display_name == "Archer" and u.star == 4))
	var eb4 := EnemyBoard.from_dict({"units": [{"unit": "Archer", "star": 4, "coord": [3, 3], "items": []}]}, gm.unit_pool, gm.item_roster)
	chk("waves and ghosts can field a 4-star", eb4.units.size() == 1 and eb4.units[0].star == 4)
	var rng5 := RandomNumberGenerator.new()
	rng5.seed = 3
	var sigils := 0
	var seen5 := {}
	for i in 400:
		var it: ItemData = gm.pick_drop(6, rng5, seen5)
		if it.id == &"ancient_sigil":
			sigils += 1
			seen5[it.id] = 1
	chk("the sigil drops at most once a run", sigils == 1, str(sigils))
	chk("its tooltip counts the marks", main.get_node("UI/UnitInspector").item_tip(sig, 3, 3).contains("3 / 8 marks") and main.get_node("UI/UnitInspector").item_tip(sig, 0, 2).contains("only count on a 3-star"))

	print("--- a fight with resonances is deterministic")
	var sigs: PackedStringArray = []
	for i in 2:
		await load_main(77)
		var picks := [["knight", ["longsword", "quick_bow", "resonance_crystal"]], ["guardian", ["iron_belt", "chain_vest"]], ["archer", ["blood_fang", "mana_charm"]]]
		for j in picks.size():
			var u := place(picks[j][0], j)
			for id in picks[j][1]:
				u.equip(I(id))
		var wave := EnemyBoard.new()
		for e in [["thief", Vector2i(3, 3)], ["assassin", Vector2i(4, 3)], ["guardian", Vector2i(3, 2)]]:
			var bu := BoardUnit.new()
			bu.unit = UD(e[0])
			bu.coord = e[1]
			bu.items = [I("heros_blade")] as Array[ItemData]
			bu.stacks = {&"heros_blade": 5}
			wave.units.append(bu)
		gm.opponents = WaveOpponents.new([wave] as Array[EnemyBoard], 1.0)
		gm.start_combat()
		gm.resolve_combat()
		var parts: PackedStringArray = ["won=%s ticks=%d" % [GameState.me.last_combat_won, gm.combat_ticks]]
		for u in gm.combatants:
			parts.append("%s%d dealt=%.3f taken=%.3f" % [u.data.display_name, u.team, u.damage_dealt, u.damage_taken])
		sigs.append(" | ".join(parts))
		await get_tree().process_frame
	chk("the same fight twice gives the same result", sigs[0] == sigs[1] and sigs[0].contains("dealt="), sigs[0].left(110))

	print("--- the item UI")
	await load_main(11)
	var w := place("knight", 0)
	w.equip(I("longsword"))
	w.equip(I("quick_bow"))
	w.equip(I("heros_blade"))
	var icons := w.item_icons.get_children().filter(func(c): return c is Sprite3D and c.render_priority == 2)
	chk("each item on a unit is its icon image above it (bigger, static), the bound one with its stack count", icons.size() == 3 and icons.all(func(s): return s.texture != null and s.billboard == BaseMaterial3D.BILLBOARD_ENABLED and is_equal_approx(s.pixel_size * s.texture.get_width(), Unit.ICON_SIZE)) and w.item_icons.get_children().any(func(c): return c is Label3D and c.text == "0"))
	chk("no coloured square behind the icons, resonance or not", w.item_icons.get_children().filter(func(c): return c is Sprite3D and c.render_priority == 1).is_empty())
	var bar = main.get_node("UI").find_children("*", "VBoxContainer", true, false).filter(func(n): return n.has_method("toggle_book"))[0]
	GameState.me.items.append(I("blood_fang"))
	Events.items_changed.emit()
	await get_tree().process_frame
	chk("the Items tab lists the resonances on your units", bar.resonance_list.get_children().any(func(l): var said := "|".join(DockKit.texts_in(l)); return said.begins_with("Knight") and said.contains("Flurry")))
	chk("an item's tooltip lists what it resonates with", bar.item_tip(I("blood_fang")).contains("Hemorrhage") and bar.item_tip(I("tinkers_tongs")).contains("use it"))
	gm.start_combat()
	chk("bringing a resonance into a fight marks it found in the book", SaveGame.has_unlock(&"resonance:Might+Swift"))
	gm.resolve_combat()
	await get_tree().process_frame
	bar.toggle_book()
	await get_tree().process_frame
	var cells: Array = bar.book.find_children("*", "PanelContainer", true, false)
	chk("the book shows all 16 resonances", bar.book.visible and cells.size() == 16, str(cells.size()))
	bar.toggle_book()

	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	LocalSnapshotStore.root = ""
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
