# campaign_checks.gd
# Dev tool, not part of the game: headless regression checks for opponents, campaign and saves.
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/campaign_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses a throwaway save file, not yours.

extends Node

var fails := 0
var main: Node
var gm
var board: Board

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func L(n: String) -> CampaignLevel:
	return load("res://tres/campaign/levels/%s.tres" % n)

# Loads main.tscn like a fresh scene. Debug Level is overridden (main.tscn may have one set), and
# GameState.run_carry is cleared unless keep_carry, so each start is independent.
func start(level: CampaignLevel, debug: CampaignLevel = null, keep_carry := false):
	if main != null:
		main.free()
	GameState.run_level = level
	GameState.run_campaign = null
	if not keep_carry:
		GameState.run_carry = {}
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = debug
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await get_tree().create_timer(0.3).timeout

func enemies() -> Array:
	return board.get_node("Units").get_children().filter(func(n): return n is Unit and n.team == 1 and not n.is_queued_for_deletion())

func clear_enemies():
	for e in enemies():
		board.vacate(e)
		e.free()

func _ready():
	_run.call_deferred()

func _run():
	SaveGame.path = "user://test_save.json"
	SaveGame.reset_progress()
	var camp: Campaign = load("res://tres/campaign/campaign.tres")
	var l1 := L("ch1_l1")
	var l2 := L("ch1_l2")
	var l3 := L("ch1_l3")

	print("--- data")
	var c2: Array = [L("ch2_l1"), L("ch2_l2"), L("ch2_l3")]
	var c3: Array = [L("ch3_l1"), L("ch3_l2"), L("ch3_l3")]
	chk("campaign has 3 chapters, 9 levels, linked files", camp.chapters.size() == 3 and camp.all_levels().size() == 9 and camp.all_levels()[0] == l1)
	chk("chapters 2 and 3 hold their levels in order", camp.chapters[1].levels.map(func(x): return x.id) == [&"ch2_l1", &"ch2_l2", &"ch2_l3"] and camp.chapters[2].levels.map(func(x): return x.id) == [&"ch3_l1", &"ch3_l2", &"ch3_l3"])
	chk("find_level by id", camp.find_level(&"ch1_l2") == l2 and camp.find_level(&"ch3_l3") == c3[2] and camp.find_level(&"nope") == null)
	chk("next_level chain crosses chapters", camp.next_level(l1) == l2 and camp.next_level(l2) == l3 and camp.next_level(l3) == c2[0] and camp.next_level(c2[2]) == c3[0] and camp.next_level(c3[2]) == null)
	chk("next_in_chapter stops at a chapter's end", camp.next_in_chapter(l3) == null and camp.next_in_chapter(c2[0]) == c2[1] and camp.next_in_chapter(c3[2]) == null)
	chk("wave counts 5/6/7, 6/7/8, 7/8/9", l1.waves.size() == 5 and l2.waves.size() == 6 and l3.waves.size() == 7 and c2.map(func(x): return x.waves.size()) == [6, 7, 8] and c3.map(func(x): return x.waves.size()) == [7, 8, 9])
	chk("every chapter's final wave is a boss with an HP pack", [l3, c2[2], c3[2]].all(func(x): return x.waves.back().hp_reward == 10))
	chk("each chapter's last level unlocks its completion flag", c2[2].unlocks == [&"chapter_2_complete"] and c3[2].unlocks == [&"chapter_3_complete"] and l3.unlocks == [&"chapter_1_complete"])

	var boss: EnemyBoard = l1.waves[4]
	var d := boss.to_dict()
	var tmp_main = load("res://scenes/main.tscn").instantiate()
	var roster: Array = tmp_main.get_node("Game Manager").unit_pool
	tmp_main.free()
	var items: Array = []
	for n in ["iron_belt", "longsword", "quick_bow", "mana_charm", "chain_vest", "blood_fang"]:
		items.append(load("res://tres/items/%s.tres" % n))
	var back := EnemyBoard.from_dict(JSON.parse_string(JSON.stringify(d)), roster, items)
	chk("EnemyBoard survives to_dict -> JSON -> from_dict", JSON.stringify(back.to_dict()) == JSON.stringify(d), JSON.stringify(d).left(110))
	chk("round trip keeps star, coord, items", back.units[0].star == 2 and back.units[0].coord == Vector2i(3, 3) and back.units[0].items[0].id == &"chain_vest")

	var wp := WaveOpponents.new(l1.waves, 2.0)
	chk("WaveOpponents: wave per round, stat multiplier, source untouched", wp.board_for_round(1).display_name == "Scouts" and is_equal_approx(wp.board_for_round(1).stat_scale, 1.0) and is_equal_approx(l1.waves[0].stat_scale, 0.5))
	chk("WaveOpponents: rounds past the end repeat the last wave", wp.board_for_round(99).display_name == "Raid Captain")

	print("--- validation")
	var problems := camp.validate()
	chk("sample campaign validates clean", problems.is_empty(), " | ".join(problems))
	var bad := CampaignLevel.new()
	bad.display_name = "Bad"
	var bw := EnemyBoard.new()
	for c in [Vector2i(3, 5), Vector2i(1, 1), Vector2i(1, 1), Vector2i(-1, -1)]:
		var b := BoardUnit.new()
		b.unit = load("res://tres/knight.tres")
		b.coord = c
		bw.units.append(b)
	bw.units.append(BoardUnit.new())
	bad.waves.append(bw)
	bad.item_drop_rounds = [3]
	problems = bad.validate()
	print("  bad level reports: ", " | ".join(problems))
	chk("bad level: missing id", problems.has("Level 'Bad': missing id"))
	chk("bad level: player-side coord", " ".join(problems).contains("(3, 5) is not on the enemy half"))
	chk("bad level: duplicate coord", " ".join(problems).contains("two units at (1, 1)"))
	chk("bad level: unit without data", " ".join(problems).contains("has no UnitData"))
	chk("bad level: too many units for open tiles", " ".join(problems).contains("4 units but only 2 enemy tiles open"))
	chk("bad level: drop round out of range", " ".join(problems).contains("item drop round 3"))
	var dup := Campaign.new()
	var dch := CampaignChapter.new()
	dch.id = &"x"
	dch.levels.append(l1)
	dch.levels.append(l1)
	dup.chapters.append(dch)
	chk("duplicate level ids reported", " ".join(dup.validate()).contains("used twice"))

	print("--- save + unlocks")
	chk("first level open, others locked", camp.is_unlocked(l1) and not camp.is_unlocked(l2) and not camp.is_unlocked(l3))
	SaveGame.record_level_complete(l1.id, 60)
	SaveGame.record_level_complete(l1.id, 80)
	SaveGame.record_level_complete(l1.id, 70)
	chk("completing l1 unlocks l2 only", camp.is_unlocked(l2) and not camp.is_unlocked(l3))
	SaveGame.record_level_complete(&"ch1_l2", 80)
	chk("chapter 2 stays locked until chapter 1's last level is complete", camp.is_unlocked(l3) and not camp.is_unlocked(c2[0]))
	SaveGame.record_level_complete(&"ch1_l3", 80)
	chk("completing ch1_l3 unlocks chapter 2's first level, but not its second", camp.is_unlocked(c2[0]) and not camp.is_unlocked(c2[1]) and not camp.is_unlocked(c3[0]))
	SaveGame.record_level_complete(&"ch2_l1", 80)
	SaveGame.record_level_complete(&"ch2_l2", 80)
	SaveGame.record_level_complete(&"ch2_l3", 80)
	chk("and chapter 3 follows chapter 2", camp.is_unlocked(c3[0]) and not camp.is_unlocked(c3[1]))
	SaveGame._loaded = false   # force a reload from disk
	chk("progress survives reload from disk", SaveGame.is_level_complete(&"ch1_l1") and SaveGame.best_hp(&"ch1_l1") == 80 and int(SaveGame.data().completed_levels["ch1_l1"].times) == 3)
	var f := FileAccess.open(SaveGame.path, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	SaveGame.load_game()
	chk("corrupt save: starts fresh and keeps a .corrupt copy", not SaveGame.is_level_complete(&"ch1_l1") and FileAccess.file_exists(SaveGame.path + ".corrupt"))
	f = FileAccess.open(SaveGame.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 0, "completed_levels": {"ch1_l1": {"best_hp": "55"}, "bad": 3}, "unlocks": ["a", "a", 7]}))
	f.close()
	SaveGame.load_game()
	chk("old/odd save is cleaned up on load", SaveGame.best_hp(&"ch1_l1") == 55 and not SaveGame.is_level_complete(&"bad") and SaveGame.data().unlocks == ["a", "7"], JSON.stringify(SaveGame.data()))
	SaveGame.reset_progress()

	print("--- campaign run: level 1")
	await start(l1)
	chk("level modifiers: start gold 4, level 1, hp 100", GameState.me.gold == 4 and GameState.me.level == 1 and GameState.me.player_hp == 100, "gold %d" % GameState.me.gold)
	chk("campaign loss damage from the level (6 + stars)", GameState.damage_for_loss(4) == 7)
	chk("campaign rounds = waves", GameState.total_rounds() == 5)
	var music_first: String = Music.current
	GameState.round_number = 5
	var boss_last: bool = gm.is_boss_round()
	GameState.round_number = 1
	chk("music: the run track on wave 1, boss music on a chapter level's last wave", music_first == "game" and not gm.is_boss_round() and boss_last)
	chk("item drop rounds from level", GameState.item_drop_rounds() == [2, 4])
	var tracker = main.get_node("UI/TopBar").rounds
	chk("round tracker shows the wave", tracker.stage_label.text == "WAVE" and tracker.count_label.text == "1/5" and tracker.pips.states.size() == 5 and tracker.pips.states[0] == "current" and tracker.pips.states[4] == "boss", "%s %s %s" % [tracker.stage_label.text, tracker.count_label.text, tracker.pips.states])
	var opp_row = main.get_node("UI/Standings").opponent_row()
	chk("standings name the wave as the opponent", opp_row != null and opp_row.name_text == "Scouts" and opp_row.hp_lbl.text == "1/5" and opp_row.vs_tag.visible, opp_row.name_text if opp_row else "no row")
	var tip: String = tracker.tooltip_text
	chk("round tracker tooltip names the level and wave and lists the enemies", tip == "First Blood
Wave 1/5: Scouts
Enemies this wave:
Knight *", tip.replace("
", " | "))
	chk("provider is WaveOpponents", gm.opponents is WaveOpponents)
	chk("run_campaign found from the default path", GameState.run_campaign != null and GameState.run_campaign.find_level(&"ch1_l1") != null)

	# Boss wave with 9 open enemy tiles: authored coords, star, items, enemy synergies.
	GameState.me.level = 3
	board.refresh_unlocks(3, false)
	var spawned: Array = gm.spawn_board(l1.waves[4])
	var guardian: Unit = spawned.filter(func(u): return u.data.display_name == "Guardian")[0]
	chk("boss wave: all 4 placed", spawned.size() == 4)
	chk("authored coords used", guardian.coord == Vector2i(3, 3) and spawned.map(func(u): return u.coord).has(Vector2i(3, 2)))
	chk("enemy star and item", guardian.star == 2 and guardian.items.size() == 1 and guardian.items[0].id == &"chain_vest")
	chk("enemy stat_scale from wave", is_equal_approx(guardian.stat_scale, 0.6))
	chk("enemy synergies: Order (Guardian+Knight) +15% HP", is_equal_approx(guardian.bonus_hp, 0.15), "bonus_hp %s" % guardian.bonus_hp)
	chk("enemy health full", is_equal_approx(guardian.health, guardian.max_hp()))
	clear_enemies()

	# Locked tiles: at level 1 only 2 enemy tiles are open.
	GameState.me.level = 1
	board.refresh_unlocks(1, false)
	spawned = gm.spawn_board(l1.waves[2])   # Patrol: 3 units, one wants (3,2) which is locked
	chk("too many units: fills open tiles, skips the rest", spawned.size() == 2 and spawned.all(func(u): return board.is_unlocked(u.coord) and not board.is_player_side(u.coord)), str(spawned.map(func(u): return u.coord)))
	clear_enemies()

	# Final wave lost -> defeat, not saved.
	var lost := [false]
	Events.run_lost.connect(func(): lost[0] = true, CONNECT_ONE_SHOT)
	GameState.round_number = 5
	gm.fighting = true
	gm._end_combat(false, 0)
	chk("losing the final wave is a defeat", lost[0] and gm.game_over and not SaveGame.is_level_complete(&"ch1_l1"))
	var es = main.get_node("UI/End Screen")
	chk("end screen: DEFEAT + Restart chapter", es.visible and es.title.text == "DEFEAT" and es.restart_button.text == "Restart chapter" and es.restart_button.visible and not es.next_button.visible)

	await start(l1)
	GameState.round_number = 5
	gm.fighting = true
	gm._end_combat(true, 0)
	es = main.get_node("UI/End Screen")
	chk("winning the final wave completes the level and saves it", gm.game_over and SaveGame.is_level_complete(&"ch1_l1") and SaveGame.best_hp(&"ch1_l1") == GameState.me.player_hp)
	chk("end screen: LEVEL COMPLETE + Next level only", es.title.text == "LEVEL COMPLETE" and es.next_button.visible and not es.restart_button.visible and es._next() == l2, es.detail.text.replace("\n", " | "))

	print("--- level 2 and 3 started directly (Debug Level)")
	await start(l2)
	chk("l2 direct: level 3, gold 10 + bonus 1 + interest 1 = 12, income +1", GameState.me.level == 3 and GameState.me.gold == 12 and GameState.base_income_for_round(2) == 3, "level %d gold %d base(2) %d" % [GameState.me.level, GameState.me.gold, GameState.base_income_for_round(2)])
	chk("l2 direct: not a carried run, round-1 shop is 1-cost only", not GameState.run_carried and GameState.me.cheap_shop)
	await start(l3)
	chk("l3 direct: level 5, gold 20 + interest 2 = 22, drops 2/4/6, loss damage 14", GameState.me.level == 5 and GameState.me.gold == 22 and GameState.item_drop_rounds() == [2, 4, 6] and GameState.damage_for_loss(0) == 14)
	chk("l3 direct: board unlocked for level 5", Board.tiles_open_for_level(5) == board.player_order.filter(func(c): return board.is_unlocked(c)).size())

	print("--- chapter run: carrying the board")
	SaveGame.reset_progress()
	await start(l1)
	var knight_data: UnitData = load("res://tres/knight.tres")
	GameState.me.gold = 50
	for i in 3:
		Events.unit_bought.emit(knight_data)
	Events.unit_bought.emit(load("res://tres/cleric.tres"))
	var knight: Unit = board.all_player_units().filter(func(u): return u.data.display_name == "Knight")[0]
	var cleric: Unit = board.all_player_units().filter(func(u): return u.data.display_name == "Cleric")[0]
	knight.equip(load("res://tres/items/iron_belt.tres"))
	knight.equip(load("res://tres/items/longsword.tres"))
	board.detach(knight)
	board.put_on_tile(knight, Vector2i(3, 4))
	var cleric_slot := board.bench.find(cleric)
	GameState.me.items.append(load("res://tres/items/quick_bow.tres"))
	GameState.me.xp = 1
	GameState.me.player_hp = 80
	GameState.round_number = 5
	gm.current_board = l1.waves[4]   # the boss wave: hp_reward 10
	gm.fighting = true
	gm._end_combat(true, 0)
	var carry: Dictionary = GameState.run_carry
	chk("boss HP pack: 80 + 10 = 90", GameState.me.player_hp == 90, "hp %d" % GameState.me.player_hp)
	chk("carry targets level 2", str(carry.get("level", "")) == "ch1_l2")
	chk("carry: HP, gold, level, XP", int(carry.hp) == 90 and int(carry.gold) == GameState.me.gold and int(carry.player_level) == GameState.me.level and int(carry.xp) == 1)
	chk("carry: 2-star Knight with 2 items on (3,4), Cleric on its bench slot, Quick Bow in the bar",
		carry.units.size() == 2 and carry.items == ["quick_bow"]
		and carry.units.any(func(e): return e.unit == "Knight" and e.star == 2 and e.coord == [3, 4] and e.items == ["iron_belt", "longsword"])
		and carry.units.any(func(e): return e.unit == "Cleric" and e.star == 1 and e.bench == cleric_slot), JSON.stringify(carry))
	chk("chapter run saved", str(SaveGame.chapter_run().get("level", "")) == "ch1_l2")

	SaveGame._loaded = false   # continue from the save file (JSON numbers come back as floats)
	GameState.run_carry = SaveGame.chapter_run()
	var g0 := int(carry.gold)
	await start(l2, null, true)
	knight = board.all_player_units().filter(func(u): return u.data.display_name == "Knight")[0]
	cleric = board.all_player_units().filter(func(u): return u.data.display_name == "Cleric")[0]
	chk("level 2 continues the run", GameState.run_carried and GameState.run_level == l2 and GameState.run_carry.is_empty())
	chk("arrival heal: 90 + 10 = 100 (capped at 100)", GameState.me.player_hp == 100, "hp %d" % GameState.me.player_hp)
	chk("gold carried (+ round 1 income: bonus 1 + interest)", GameState.me.gold == g0 + 1 + mini(g0 / 10, 5), "gold %d from %d" % [GameState.me.gold, g0])
	chk("level and XP carried", GameState.me.level == int(carry.player_level) and GameState.me.xp == 1)
	chk("Knight restored: 2-star, 2 items, same tile", knight.star == 2 and knight.items.size() == 2 and knight.coord == Vector2i(3, 4) and is_equal_approx(knight.health, knight.max_hp()))
	chk("Cleric restored on its bench slot", board.bench.find(cleric) == cleric_slot)
	chk("item bar restored", GameState.me.items.size() == 1 and GameState.me.items[0].id == &"quick_bow")
	chk("owned copies taken from the shared pool (3 Knights)", gm.shared_pool.count(knight_data) + GameState.me.shop_offers.count(knight_data) == 27, "pool %d" % gm.shared_pool.count(knight_data))
	chk("carried run: round-1 shop is not limited to 1-cost", not GameState.me.cheap_shop)

	GameState.round_number = 6
	gm.fighting = true
	gm._end_combat(false, 0)
	es = main.get_node("UI/End Screen")
	chk("defeat ends the chapter run (save cleared)", SaveGame.chapter_run().is_empty() and GameState.run_carry.is_empty())
	chk("restart goes to the chapter's first level", es.restart_button.text == "Restart chapter" and GameState.run_campaign.first_of_chapter(l2) == l1)

	await start(l3)
	GameState.round_number = 7
	gm.fighting = true
	gm._end_combat(true, 0)
	es = main.get_node("UI/End Screen")
	chk("chapter 1's last level: CHAPTER COMPLETE with Next chapter (chapter 2's first level) and Play chapter again", es.title.text == "CHAPTER COMPLETE" and es.next_button.visible and es.next_button.text == "Next chapter" and es._next() == c2[0] and es.restart_button.text == "Play chapter again" and SaveGame.chapter_run().is_empty(), es.detail.text)

	await start(c3[2])
	GameState.round_number = 9
	gm.fighting = true
	gm._end_combat(true, 0)
	es = main.get_node("UI/End Screen")
	chk("the last chapter's last level: CHAPTER COMPLETE and no Next chapter", es.title.text == "CHAPTER COMPLETE" and not es.next_button.visible and es.restart_button.text == "Play chapter again" and SaveGame.chapter_run().is_empty())

	# A new chapter starts fresh: its first level's own gold, level and 100 HP, no carried board.
	await start(c2[0])
	chk("chapter 2 starts fresh: 10 gold (+1 interest), level 2, 100 HP, empty board", not GameState.run_carried and GameState.me.gold == 11 and GameState.me.level == 2 and GameState.me.player_hp == 100 and board.all_player_units().is_empty() and GameState.total_rounds() == 6)
	var tip2: String = main.get_node("UI/TopBar").rounds.tooltip_text
	chk("chapter 2 level 1 round tracker", tip2.begins_with("Smoke on the Horizon
Wave 1/6: Scouts"), tip2.replace("
", " | "))
	var scouts: Array = gm.spawn_board(c2[0].waves[0])
	chk("chapter 2 enemies spawn from the new waves", scouts.size() == 2 and scouts.all(func(u): return u.team == 1))
	clear_enemies()

	# Launching with Debug Level continues a saved run in the same chapter.
	SaveGame.set_chapter_run({"level": "ch1_l3", "hp": 70, "max_hp": 100, "gold": 5, "player_level": 5, "xp": 0, "items": [], "units": [{"unit": "Archer", "star": 2, "items": [], "coord": [3, 4]}]})
	await start(null, l1)
	chk("Debug Level continues the saved run", GameState.run_level == l3 and GameState.run_carried and GameState.me.player_hp == 80 and board.all_player_units().size() == 1, "level %s hp %d" % [GameState.run_level.id if GameState.run_level else "none", GameState.me.player_hp])
	SaveGame.clear_chapter_run()
	await start(null, l1)
	chk("Debug Level without a saved run starts level 1 fresh", GameState.run_level == l1 and not GameState.run_carried)

	var custom := CampaignLevel.new()
	custom.id = &"test_only"
	custom.waves.append(l1.waves[0])
	custom.allowed_units.append(load("res://tres/knight.tres"))
	await start(custom)
	var offers := []
	for i in 5:
		gm.roll_shop()
		offers.append_array(GameState.me.shop_offers)
	chk("allowed_units: shop only offers those units", not offers.is_empty() and offers.all(func(u): return u.display_name == "Knight"), "%d offers" % offers.size())

	await start(CampaignLevel.new())   # an empty "New CampaignLevel" in Debug Level
	chk("level with no waves falls back to free play", GameState.run_level == null and gm.opponents is RandomOpponents and GameState.total_rounds() == 39)

	print("--- board themes")
	var missing: PackedStringArray = []
	for id in BoardThemes.ORDER:
		for part in ["board_1", "board_2", "board_3", "board_side", "bench", "bench_side", "sell", "sell_side"]:
			if not ResourceLoader.exists(BoardThemes.texture_path(id, part)):
				missing.append("%s/%s" % [id, part])
	chk("10 themes, each with all 8 textures", BoardThemes.ORDER.size() == 10 and BoardThemes.THEMES.size() == 10 and missing.is_empty(), ", ".join(missing))
	var camp_all: Campaign = load("res://tres/campaign/campaign.tres")
	var bad_theme: PackedStringArray = []
	var used := {}
	var levels: Array = camp_all.all_levels().duplicate()
	levels.append(load("res://tres/campaign/tutorial.tres"))
	for lv in levels:
		if not BoardThemes.has(lv.theme):
			bad_theme.append(String(lv.id))
		used[lv.theme] = true
	chk("every campaign level and the tutorial has its own theme", bad_theme.is_empty() and used.size() == levels.size(), ", ".join(bad_theme))
	await start(load("res://tres/campaign/levels/ch2_l3.tres"))
	var tile0: Tile = board.tiles[Vector2i(3, 4)]
	var top_mat := (tile0.get_node("MeshInstance3D") as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	chk("a level dresses the board in its theme (Throne of Cinders: volcano)", board.theme == &"volcano" and top_mat != null and top_mat.albedo_texture != null and top_mat.albedo_texture.resource_path.contains("/volcano/"))
	chk("the board hexes are voxel blocks with a top and sides", (tile0.get_node("MeshInstance3D") as MeshInstance3D).mesh.get_surface_count() == 2)
	chk("free play picks a theme from the run seed", BoardThemes.for_run(null, 12) == BoardThemes.for_run(null, 12) and BoardThemes.has(BoardThemes.for_run(null, 12)) and BoardThemes.for_run(null, 3) != BoardThemes.for_run(null, 4))

	print("--- free play")
	await start(null)
	var ft = main.get_node("UI/TopBar").rounds
	var free_text: String = "%s %s" % [ft.stage_label.text, ft.count_label.text]
	chk("free play: RandomOpponents, 39 rounds, normal start", gm.opponents is RandomOpponents and GameState.total_rounds() == 39 and GameState.me.gold == 2 and free_text == "STAGE 1 1-1" and ft.pips.states.size() == 3 and ft.tooltip_text == "", free_text)
	GameState.round_number = 39
	var free_boss: bool = gm.is_boss_round()
	GameState.round_number = 1
	chk("music: free play's final round is the boss round", free_boss and not gm.is_boss_round())
	var free_opp = main.get_node("UI/Standings").opponent_row()
	chk("free play standings: you and Random enemies", free_opp.name_text == "Random enemies" and free_opp.hp_lbl.text == "" and main.get_node("UI/Standings").you_row().hp_lbl.text == "100")
	var rb: EnemyBoard = gm.opponents.board_for_round(1)
	chk("random board: no synergies, auto placement, scale 0.4", not rb.use_synergies and rb.units.all(func(b): return b.coord == Vector2i(-1, -1)) and is_equal_approx(rb.stat_scale, 0.4))
	spawned = gm.spawn_board(rb)
	chk("random board spawns on open enemy tiles", spawned.size() >= 1 and spawned.all(func(u): return board.is_unlocked(u.coord) and not board.is_player_side(u.coord)))
	clear_enemies()
	var frames := 0
	while GameState.round_number < 2 and frames < 6000:
		await get_tree().process_frame
		frames += 1
	chk("free play reaches round 2 (combat ran and ended)", GameState.round_number == 2)

	SaveGame.reset_progress()
	for p in [SaveGame.path, SaveGame.path + ".corrupt"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
