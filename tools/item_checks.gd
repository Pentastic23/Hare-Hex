# item_checks.gd
# Dev tool, not part of the game: checks items v2 (docs/items-v2.md): the 14 item types, resonance
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

	print("--- the 14 items")
	var roster: Array = gm.item_roster
	var kinds := {}
	for it in roster:
		kinds[String(it.kind)] = int(kinds.get(String(it.kind), 0)) + 1
	chk("14 item types: 6 basic, 2 bound, 2 economy, 2 benders, the Crystal and the Tongs", roster.size() == 14 and kinds == {"basic": 6, "bound": 2, "economy": 2, "bender": 2, "crystal": 1, "remover": 1}, str(kinds))
	chk("every basic item has its own element", roster.filter(func(i): return i.kind == &"basic").map(func(i): return i.element).all(func(e): return Resonance.ELEMENTS.has(e)) and Resonance.ELEMENTS.all(func(e): return roster.filter(func(i): return i.kind == &"basic" and i.element == e).size() == 1))
	chk("Mana Charm now also gives +8% damage", is_equal_approx(float(I("mana_charm").effects.get("dmg", 0.0)), 0.08))

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
	chk("the Crystal with no resonance: +8% HP and damage", is_equal_approx(float(alone.get("hp", 0.0)), 0.08) and is_equal_approx(float(alone.get("dmg", 0.0)), 0.08))
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
	chk("a second copy of the same bound item is refused", not a.can_take(I("heros_blade")))
	chk("Tinker's Tongs are never worn", not a.can_take(I("tinkers_tongs")))
	var b := place("archer", 1)
	b.equip(I("twin_sigil"))
	chk("one synergy bender per unit", not b.can_take(I("twin_crest")))
	var dmg0 := a.damage()
	a.end_combat()
	chk("surviving a fight adds a stack: +4 damage", a.stacks_of(I("heros_blade")) == 1 and is_equal_approx(a.damage() - dmg0, 4.0))
	a.dead = true
	a.end_combat()
	chk("a fight it doesn't survive adds nothing", a.stacks_of(I("heros_blade")) == 1)
	for i in 30:
		a.end_combat()
	chk("stacks stop at 15", a.stacks_of(I("heros_blade")) == 15)
	board.sell_unit(a)
	chk("selling returns the item with no stacks", GameState.me.items.has(I("heros_blade")))
	GameState.me.items.clear()
	# Merge: three Knights, the keeper ends with the most stacks any copy had.
	var ks: Array = []
	for i in 3:
		ks.append(place("knight", -1))
	ks[1].equip(I("heros_blade"))
	ks[1].item_stacks[&"heros_blade"] = 9
	ks[2].equip(I("heros_blade"))
	ks[2].item_stacks[&"heros_blade"] = 4
	board.merge_all()
	var merged: Array = board.all_player_units().filter(func(u): return u.data.display_name == "Knight" and u.star == 2)
	chk("merging keeps the highest stacks (9) on the kept unit", merged.size() == 1 and merged[0].stacks_of(I("heros_blade")) == 9 and merged[0].items.filter(func(i): return i.id == &"heros_blade").size() == 1, str(merged[0].item_stacks) if not merged.is_empty() else "no merge")
	chk("the spare copy goes back to the inventory", GameState.me.items.has(I("heros_blade")))

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

	print("--- drops")
	chk("14 drop rounds in a free-play run, Tongs at the end of stages 3 and 5", GameState.ITEM_DROP_ROUNDS.size() == 14 and GameState.TONGS_ROUNDS == [15, 27])
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
	chk("the Items tab lists the resonances on your units", bar.resonance_list.get_children().any(func(l): return l is Label and l.text.begins_with("Knight") and l.text.contains("Flurry")))
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
