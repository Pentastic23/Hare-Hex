# tutorial_checks.gd
# Dev tool, not part of the game: plays the tutorial level through every step with game actions
# (buy, place, merge, equip, buy XP, Start fight) and checks the end screen and that a saved
# campaign run is never touched. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/tutorial_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway save and settings files.

extends Node

var fails := 0
var main: Node
var gm
var board: Board
var tut

const FAKE_RUN := {"level": "ch1_l2", "hp": 77, "max_hp": 100, "gold": 9, "player_level": 3, "xp": 0, "items": [], "units": []}

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func start_tutorial():
	if main != null:
		main.free()
	GameState.run_level = load("res://tres/campaign/tutorial.tres")
	GameState.run_campaign = load("res://tres/campaign/campaign.tres")
	GameState.run_carry = {}
	GameState.launched_from_menu = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	tut = main.get_node("UI/TutorialPanel")
	await get_tree().create_timer(0.4).timeout

func poll():
	await get_tree().create_timer(0.3).timeout   # the panel checks its step a few times a second

func U(n: String) -> UnitData:
	return load("res://tres/%s.tres" % n)

func place(u: Unit, i: int):
	board.detach(u)
	board.put_on_tile(u, board.player_order[i])

func wait_phase(p: int):
	if gm.phase == p:
		return
	while true:
		var ph = await Events.phase_changed
		if ph == p or gm.game_over:
			return

func _run():
	SaveGame.path = "user://tutorial_test_save.json"
	SaveGame.reset_progress()
	SaveGame.set_chapter_run(FAKE_RUN)   # a campaign run in progress must survive the tutorial
	SaveGame.set_team_plan([])   # (the plan survives reset_progress: start from an empty one)
	Settings.path = "user://tutorial_test_settings.cfg"
	Settings._loaded = true

	await start_tutorial()
	chk("tutorial panel shows in the tutorial", tut.visible and tut.title_label.text == "Welcome!" and tut.progress_label.text == "1 / 17")
	for k in 3:
		await get_tree().process_frame
	var tut_rect: Rect2 = tut.get_global_rect()
	chk("the step panel sits under the right box and ends above the bench and the SELL tile (y 451 at the default camera); damage panel closed", main.get_node("UI/RightDock").current == "" and tut_rect.end.y <= 440.0 and main.get_node("UI/Standings").visible, str(tut_rect))
	chk("tutorial settings: Knights and Militia only, 5 waves", gm.roster.size() == 2 and GameState.total_rounds() == 5)
	tut.next_button.pressed.emit()
	chk("Next moves to 'Buy a unit'", tut.title_label.text == "Buy a unit")
	chk("Start fight is hidden before a unit is placed", not tut.fight_button.visible)

	Events.unit_bought.emit(U("knight"))
	await poll()
	chk("buying a unit moves to 'Place it on the board'", tut.title_label.text == "Place it on the board")
	place(board.all_player_units()[0], 0)
	await poll()
	chk("placing it moves to 'Start the fight', with the button", tut.title_label.text == "Start the fight" and tut.fight_button.visible)

	tut.fight_button.pressed.emit()
	await get_tree().process_frame
	chk("Start fight starts combat right away", gm.phase == Events.Phase.COMBAT or GameState.round_number == 2)
	await poll()
	chk("during the fight: 'Watch the fight' with Next greyed out", tut.title_label.text == "Watch the fight" and tut.next_button.visible and (tut.next_button.disabled or gm.phase == Events.Phase.PREP))
	await wait_phase(Events.Phase.PREP)
	await get_tree().create_timer(1.5).timeout
	chk("after the fight it waits on 'Watch the fight' with Next enabled", tut.title_label.text == "Watch the fight" and not tut.next_button.disabled, tut.title_label.text)
	chk("'Watch the fight' opens the Damage window it talks about", main.get_node("UI/RightDock").current == "damage")
	chk("Start fight is hidden while the step waits for Next", not tut.fight_button.visible)
	chk("the old prep timer didn't start a second fight", gm.phase == Events.Phase.PREP and GameState.round_number == 2)
	tut.next_button.pressed.emit()
	chk("Next moves to 'Inspect a unit'", tut.title_label.text == "Inspect a unit", tut.title_label.text)
	main.get_node("UI/UnitInspector").show_unit(board.all_player_units()[0])
	await poll()
	chk("opening the inspector on a unit moves to 'Merge three into a star'", tut.title_label.text == "Merge three into a star", tut.title_label.text)
	chk("the merge step explains 3-star units too", tut.body_label.text.contains("3-star"))

	GameState.me.gold = 30
	Events.unit_bought.emit(U("knight"))
	Events.unit_bought.emit(U("knight"))
	await poll()
	var knights := board.all_player_units().filter(func(u): return u.data.display_name == "Knight")
	chk("three Knights merge and the step moves to 'Synergies'", knights.size() == 1 and knights[0].star == 2 and tut.title_label.text == "Synergies")
	var left = main.get_node("UI/LeftDock")
	chk("'Synergies' opens the Synergies tab", not left.collapsed and left.tab == "synergies")

	Events.unit_bought.emit(load("res://tres/units/militia.tres"))
	var cleric = board.all_player_units().filter(func(u): return u.data.display_name == "Militia")[0]
	if knights[0].coord.x < 0:
		place(knights[0], 0)
	place(cleric, 1)
	await poll()
	chk("Knight + Militia on the board activates Order: 'Plan your team'", tut.title_label.text == "Plan your team", tut.title_label.text)
	var dock = main.get_node("UI/RightDock")
	await poll()
	chk("'Plan your team' opens the planner, and that alone doesn't finish the step", dock.current == "planner" and tut.title_label.text == "Plan your team" and tut.body_label.text.contains("Click a unit's portrait in it"))
	dock.planner.tile_for("Knight").pressed.emit()
	await poll()
	chk("planning a unit with the planner still open waits (the planner would cover the next step)", tut.title_label.text == "Plan your team" and SaveGame.team_plan().has("Knight"))
	dock.close_panel()
	await poll()
	chk("closing the planner moves to 'Equip an item'", tut.title_label.text == "Equip an item", tut.title_label.text)
	chk("the items step hands out the Longsword (no random drops in the tutorial) and opens the Items tab", GameState.me.items.size() == 1 and GameState.me.items[0].id == &"longsword" and left.tab == "items", str(GameState.me.items.map(func(i): return i.id)))

	main.get_node("DragController").equip_item_on(knights[0], GameState.me.items[0])
	await poll()
	chk("equipping it moves to 'Resonance', which hands out a Quick Bow", tut.title_label.text == "Resonance" and GameState.me.items.has(load("res://tres/items/quick_bow.tres")), tut.title_label.text)
	main.get_node("DragController").equip_item_on(knights[0], load("res://tres/items/quick_bow.tres"))
	await poll()
	chk("Longsword + Quick Bow on one unit (Flurry) moves to 'Sell a unit'", tut.title_label.text == "Sell a unit" and Resonance.keys_for(knights[0].items) == ["Might+Swift"], tut.title_label.text)

	Events.unit_bought.emit(U("cleric"))
	var spare: Unit = board.bench.filter(func(u): return u != null)[0]
	var gold_before := GameState.me.gold
	board.sell_unit(spare)
	await poll()
	chk("selling a unit refunds its cost and moves to 'Lock the shop'", GameState.me.gold == gold_before + 1 and tut.title_label.text == "Lock the shop", tut.title_label.text)

	var shop = main.get_node("UI/ShopPanel")
	shop.lock_button.button_pressed = true
	await poll()
	chk("locking alone doesn't finish the step (unlock it too)", tut.title_label.text == "Lock the shop" and GameState.me.shop_locked)
	shop.lock_button.button_pressed = false
	await poll()
	chk("lock then unlock moves to 'Interest', shop left unlocked", tut.title_label.text == "Interest" and not GameState.me.shop_locked and tut.next_button.visible and not tut.next_button.disabled, tut.title_label.text)
	tut.next_button.pressed.emit()
	await poll()
	chk("Next after Interest moves to 'Level up'", tut.title_label.text == "Level up", tut.title_label.text)
	Events.buy_xp_pressed.emit()
	Events.buy_xp_pressed.emit()
	await poll()
	chk("buying XP to the next level moves to 'Shop odds' (Next), with the odds strip open", tut.title_label.text == "Shop odds" and tut.next_button.visible and Settings.show_odds, tut.title_label.text)
	tut.next_button.pressed.emit()
	await poll()
	chk("then the last step", tut.title_label.text == "Win the last wave" and not tut.next_button.visible)

	# Play the rest with Start fight. Make the team strong enough that the test is about the flow.
	GameState.me.gold = 60
	for i in 3:
		Events.buy_xp_pressed.emit()
	for n in ["knight", "knight", "knight", "cleric", "cleric"]:
		Events.unit_bought.emit(U(n))
	var bench := board.bench.filter(func(u): return u != null)
	for u in bench:
		if board.units_on_board() >= GameState.me.max_board_units():
			break
		for c in board.player_order:
			if board.is_unlocked(c) and board.tiles[c].occupant == null:
				board.detach(u)
				board.put_on_tile(u, c)
				break
	var guard := 0
	while not gm.game_over and guard < 10:
		guard += 1
		gm.end_prep_early()
		# Wait until this fight is over: back in PREP, or the run ended (no PREP after the last wave).
		var frames := 0
		while frames < 20000 and not gm.game_over and (gm.fighting or gm.phase != Events.Phase.PREP):
			await get_tree().process_frame
			frames += 1
	var es = main.get_node("UI/End Screen")
	chk("the tutorial ends with TUTORIAL COMPLETE", es.visible and es.title.text == "TUTORIAL COMPLETE", es.title.text)
	chk("end screen offers Replay tutorial and Main menu, no Next level", es.restart_button.text == "Replay tutorial" and es.menu_button.visible and not es.next_button.visible)
	chk("tutorial completion is saved", SaveGame.is_level_complete(&"tutorial"))
	chk("winning the tutorial leaves the saved campaign run alone", str(SaveGame.chapter_run().get("level", "")) == "ch1_l2" and int(SaveGame.chapter_run().hp) == 77)

	print("--- merging early and finishing early")
	await start_tutorial()
	var k1 := board.make_unit(U("knight"), gm.unit_scene)
	board.put_on_bench(k1, 0)
	k1.set_star(2)
	var merge_i := -1
	for i in tut._steps.size():
		if tut._steps[i].title == "Merge three into a star":
			merge_i = i
	tut._enter_step(merge_i)
	await poll()
	chk("a merge made before the merge step doesn't skip it: it waits for Next", tut.title_label.text == "Merge three into a star" and tut.next_button.visible)
	GameState.round_number = 5
	gm.fighting = true
	gm._end_combat(true, 0)
	await get_tree().process_frame
	chk("beating the last wave before the steps are done doesn't end the tutorial: the wave comes again", not gm.game_over and gm.phase == Events.Phase.PREP and GameState.round_number == 5 and not main.get_node("UI/End Screen").visible)

	await start_tutorial()
	GameState.round_number = 5
	GameState.me.player_hp = 1   # out of HP (a lost last wave with HP left comes again)
	gm.fighting = true
	gm._end_combat(false, 0)
	es = main.get_node("UI/End Screen")
	chk("losing the tutorial: DEFEAT with Try again", es.title.text == "DEFEAT" and es.restart_button.text == "Try again")
	chk("losing the tutorial leaves the saved campaign run alone", str(SaveGame.chapter_run().get("level", "")) == "ch1_l2")

	# Outside the tutorial the panel stays hidden.
	main.free()
	GameState.run_level = null
	GameState.run_campaign = null
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	add_child(main)
	await get_tree().process_frame
	chk("no tutorial panel in free play", not main.get_node("UI/TutorialPanel").visible)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
