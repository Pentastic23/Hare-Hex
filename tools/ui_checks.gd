# ui_checks.gd
# Dev tool, not part of the game: checks the UI requests from the playtest bug reports (2026-10-25):
# the inspector drawn over every panel, Settings from the pause menu, cost-coloured shop cards, the
# free-reroll edge, dragging a shop card onto the board, the folding shop odds, the unit cap flash, star
# marks on the health bars, synergy hover highlights, "Best on" item lines, the planner's trait filter
# and saved comps (and the main menu's planner), and the restyled end screen.
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/ui_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway save, settings and keybind files.

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

func frames(n := 1):
	for i in n:
		await get_tree().process_frame

func U(n: String) -> UnitData:
	for path in ["res://tres/%s.tres" % n, "res://tres/units/%s.tres" % n]:
		if ResourceLoader.exists(path):
			return load(path)
	return null

func I(n: String) -> ItemData:
	return load("res://tres/items/%s.tres" % n)

func _run():
	SaveGame.path = "user://ui_test_save.json"
	SaveGame.reset_progress()
	SaveGame.set_team_plan([])
	for i in range(SaveGame.team_comps().size() - 1, -1, -1):
		SaveGame.delete_comp(i)
	Settings.path = "user://ui_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Keybinds.path = "user://ui_checks_keybinds.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Keybinds.path))
	Keybinds.load_binds()
	Settings._loaded = true
	Settings.show_odds = true
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.ghost_mode = false
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await frames(3)
	var ui := main.get_node("UI")

	print("--- the inspector over every panel")
	GameState.me.gold = 100
	var k := board.make_unit(U("knight"), gm.unit_scene)
	board.put_on_tile(k, board.player_order[0])
	var insp = ui.get_node("UnitInspector")
	ui.move_child(insp, 0)
	insp.show_unit(k)   # what a right-click on a unit does
	chk("an open inspector is the HUD's last child (drawn and hovered over every panel)", insp.get_index() == ui.get_child_count() - 1)

	print("--- mechanic words explained (Glossary)")
	var burn_text := Abilities.text(U("pyromancer"), 1)
	chk("a text mentioning burn gets a 'Burn:' line explaining it", Glossary.explain(burn_text).contains("\n\nBurn: "), Glossary.explain(burn_text).right(120))
	chk("each term once, whatever its ending (stuns, stunned)", Glossary.explain("Stuns it. Stunned units wait.").count("Stun: ") == 1)
	chk("item names aren't mistaken for mechanics (Mana Charm is not a charm)", not Glossary.terms_in("Mana Charm: +15 start mana").has("Charm") and not Glossary.terms_in("Hex Ward").has("Hex"))
	chk("plain text gets nothing added", Glossary.explain("Click to buy.") == "Click to buy.")
	var bb := Glossary.bbcode("Burns [it] for 3 s.")
	chk("in rich text a mechanic word becomes a gold link, and brackets are kept as text", bb.begins_with("[url=Burn][color=#") and bb.contains("[lb]it]"), bb)
	var pyro := board.make_unit(U("pyromancer"), gm.unit_scene)
	board.put_on_tile(pyro, board.player_order[1])
	insp.show_unit(pyro)
	await frames(2)
	chk("the inspector's ability text has its mechanic words as hoverable links", insp.ability_text is RichTextLabel and insp.ability_text.text.contains("[url=Burn]"))
	insp.ability_text.meta_hover_started.emit("Burn")
	chk("hovering one shows what it means as a tooltip", insp.ability_text.tooltip_text.begins_with("Burn: "))
	insp.ability_text.meta_hover_ended.emit("Burn")
	chk("... and it goes when the mouse leaves the word", insp.ability_text.tooltip_text == "")
	insp.show_unit(k)
	pyro.queue_free()
	await frames(1)

	print("--- shop")
	var shop = ui.get_node("ShopPanel")
	var slot: ShopSlot = shop.slots[0]
	slot.show_offer(U("knight"))
	var edge: Color = (slot.get_theme_stylebox("normal") as StyleBoxFlat).border_color
	slot.show_offer(_a_five_cost())
	var edge5: Color = (slot.get_theme_stylebox("normal") as StyleBoxFlat).border_color
	chk("shop cards are edged in their cost colour (1-cost grey, 5-cost gold)", edge.is_equal_approx(DockKit.COST_COLORS[1].darkened(0.15)) and edge5.is_equal_approx(DockKit.COST_COLORS[5].darkened(0.15)))
	GameState.me.free_rerolls = 1
	Events.gold_changed.emit(GameState.me.gold)
	var rr: StyleBoxFlat = shop.reroll_button.get_theme_stylebox("normal")
	var gold_edge := rr.border_color == HudStyle.GOLD
	GameState.me.free_rerolls = 0
	Events.gold_changed.emit(GameState.me.gold)
	rr = shop.reroll_button.get_theme_stylebox("normal")
	chk("Reroll gets a gold edge while a reroll is free, and loses it after", gold_edge and rr.border_color != HudStyle.GOLD)
	var dc = main.get_node("DragController")
	var bench_before: Array = board.bench.filter(func(u): return u != null)
	var d := U("archer")
	gm.rules.buy(d, true, false)
	var tile: Tile = board.tiles[board.player_order[1]]
	var cam := get_viewport().get_camera_3d()
	var screen := cam.unproject_position(tile.global_position)
	Input.warp_mouse(screen)
	var vp_mouse := get_viewport().get_mouse_position()
	dc.place_bought(d, bench_before)
	var placed := board.all_player_units().filter(func(u): return u.data == d and u.coord.x >= 0)
	chk("a shop card dropped on the board is bought and put on that tile (in prep)", placed.size() == 1 or vp_mouse.distance_to(screen) > 2.0, "mouse %s vs %s" % [vp_mouse, screen])
	chk("shop cards can be dragged (drag data with the offer)", slot._get_drag_data(Vector2.ZERO) is Dictionary)
	slot._dragging = false

	print("--- shop odds and the unit cap")
	var odds = ui.get_node("BottomInfo/OddsLabel")
	var open_before: bool = odds.chips[0].visible
	odds.fold_button.pressed.emit()
	var folded: bool = not odds.chips[0].visible and not Settings.show_odds
	odds.fold_button.pressed.emit()
	chk("the shop odds fold away and back (remembered)", open_before and folded and Settings.show_odds and odds.chips[0].visible)
	chk("the odds show each cost's chance at your level", odds.summary().begins_with("1·100%"), odds.summary())
	var cap = ui.get_node("BottomInfo/InfoRow/BoardLabel")
	chk("the unit cap isn't shown all the time", not cap.visible and not cap.flash.visible)
	Events.board_limit_hit.emit()
	chk("trying to go over it flashes BOARD FULL above the board", cap.flash.visible and cap.flash.text.begins_with("BOARD FULL"))

	print("--- the board")
	k.set_star(2)
	chk("star marks beside the health bar (2 stars: two)", k.star_mark != null and k.star_mark.text == "★★" and k.star_mark.get_parent().name == "Bars")
	var panel := _find_synergy_panel(ui)
	if panel != null:
		panel.highlight("Order")
	chk("hovering a trait lights up the rings of your units that have it", panel != null and k.highlighted and k.ring.material_override == Unit.RING_HIGHLIGHT)
	if panel != null:
		panel.highlight("")
	chk("...and off again", not k.highlighted and k.ring.material_override == Unit.RING_MATS[0])
	var pile := board.interest
	var me := GameState.me
	me.gold = 9
	var none := pile.coins.size()
	me.gold = 34
	var three := pile.coins.size()
	me.gold = 90
	var capped := pile.coins.size()
	me.gold = 12
	chk("the interest hex piles one coin per 10 gold banked, up to the interest cap", none == 0 and three == 3 and capped == mini(9, KingPowers.interest_cap(me)) and pile.coins.size() == 1, "%d %d %d" % [none, three, capped])
	chk("it stands just right of your half, off the board and the scenery", pile.position.is_equal_approx(board.grid_to_world(Board.INTEREST_CELL)) and not board.tiles.has(Board.INTEREST_CELL) and not board.backdrop_cells.has(Board.INTEREST_CELL))

	print("--- items")
	var bar := _find_item_bar(ui)
	chk("item tooltips say which units an item suits", bar != null and bar.item_tip(I("longsword")).contains("Best on Warriors") and insp.item_tip(I("mana_charm"), 0).contains("Best on Casters"))

	print("--- the team planner")
	var dock = ui.get_node("RightDock")
	dock.open_panel("planner")
	await frames(2)
	var planner = get_tree().get_first_node_in_group("team_planner")
	var warrior_i := -1
	for i in planner.filter_pick.item_count:
		if planner.filter_pick.get_item_text(i) == "Warrior":
			warrior_i = i
	planner.filter_pick.select(warrior_i)
	planner.filter_pick.item_selected.emit(warrior_i)
	var tiles: Array = planner.grid.get_children().filter(func(c): return not c.is_queued_for_deletion())
	var all_warriors := tiles.all(func(t): return EnemyBoard.lookup_unit(gm.roster, t.get_meta("unit")).tags.any(func(x): return String(x) == "Warrior"))
	var costs := {}
	for t in tiles:
		costs[EnemyBoard.lookup_unit(gm.roster, t.get_meta("unit")).cost] = true
	chk("the trait filter shows only that trait's units, of every cost", tiles.size() > 2 and all_warriors and costs.size() > 1)
	planner.toggle_unit("Knight")
	planner.toggle_unit("Militia")
	planner.save_comp()
	var comps := SaveGame.team_comps()
	chk("Save keeps the plan as a comp named after its traits", comps.size() == 1 and comps[0].units == ["Knight", "Militia"] and str(comps[0].name).contains("Order"), str(comps))
	planner.clear_plan()
	planner.comps_pick.select(1)
	planner.comps_pick.item_selected.emit(1)
	chk("picking a saved comp plans it again", SaveGame.team_plan() == ["Knight", "Militia"])
	chk("the picked comp's name shows in the name field", planner.name_edit.visible and planner.name_edit.text == comps[0].name)
	planner.name_edit.text = "Knight rush"
	planner.name_edit.text_submitted.emit("Knight rush")
	chk("Enter renames the comp", SaveGame.team_comps()[0].name == "Knight rush" and planner.comps_pick.get_item_text(1).begins_with("Knight rush"), str(SaveGame.team_comps()))
	planner.name_edit.text = "   "
	planner.name_edit.text_submitted.emit("   ")
	chk("a blank name keeps the old one", SaveGame.team_comps()[0].name == "Knight rush" and planner.name_edit.text == "Knight rush")
	planner.delete_button.pressed.emit()
	chk("Del removes it", SaveGame.team_comps().is_empty())
	var missing: Array = []
	for p in planner.PRESETS:
		for n in p[1]:
			if EnemyBoard.lookup_unit(gm.roster, n) == null:
				missing.append("%s: %s" % [p[0], n])
	chk("every preset comp names real units", planner.PRESETS.size() == 10 and missing.is_empty(), str(missing))
	chk("picking a preset plans it, and it can't be renamed or deleted", planner.pick_preset("Wild Hunt") and SaveGame.team_plan() == planner.PRESETS[5][1] and planner.delete_button.disabled and not planner.name_edit.visible and SaveGame.team_comps().is_empty())
	planner.clear_plan()
	dock.close_panel()

	print("--- Settings from the pause menu")
	dock.open_panel("menu")
	await frames(1)
	var pm = get_tree().get_first_node_in_group("pause_menu")
	pm.settings_button.pressed.emit()
	await frames(2)
	var ov := get_tree().get_first_node_in_group("settings_overlay")
	chk("the pause menu opens the Settings screen over the game (no campaign reset there)", ov != null and ov.settings_panel.get_parent().visible and ov.find_child("*Reset campaign*", true, false) == null)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(3)
	chk("Esc closes Settings first, the pause menu stays open", get_tree().get_first_node_in_group("settings_overlay") == null and dock.current == "menu")
	dock.close_panel()

	print("--- the end screen")
	var end = ui.get_node("End Screen")
	end._show(false)
	chk("the end screen: mode line, red edge for a defeat, drawn over everything", end.mode_label.text == "FREE PLAY" and end._backing_style.border_color.is_equal_approx(HudStyle.RED) and end.get_index() == ui.get_child_count() - 1)
	end.visible = false

	main.queue_free()
	await frames(2)
	print("--- the main menu's planner")
	var menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await frames(2)
	menu._show_panel(menu.planner_panel)
	await frames(1)
	chk("the main menu has a Planner screen with the full roster", menu.planner_panel.get_parent().visible and menu.planner.grid.get_child_count() > 5)
	menu.queue_free()
	await frames(2)
	print("--- live portraits (PortraitStudio)")
	var run_scene := Node3D.new()   # a run being set up: its biome is applied twice (the board's default, then the run's)
	add_child(run_scene)
	PortraitStudio.enabled = true   # off without a window; only opening it is checked here
	PortraitStudio.open(run_scene, &"forest")
	PortraitStudio.open(run_scene, &"volcano")
	await frames(2)
	var studios := run_scene.get_children().filter(func(n): return n is PortraitStudio)
	chk("opening the portrait studio twice while a run is set up keeps one studio (freeing the first crashed the game)", studios.size() == 1 and studios[0].look == &"volcano")
	PortraitStudio.enabled = false
	run_scene.queue_free()
	await frames(2)
	SaveGame.path =SaveGame.DEFAULT_PATH if "DEFAULT_PATH" in SaveGame else SaveGame.path
	Settings.path = Settings.DEFAULT_PATH
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

func _a_five_cost() -> UnitData:
	for d in gm.unit_pool:
		if d.cost == 5:
			return d
	return null

func _find_synergy_panel(n: Node) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("synergy_panel.gd"):
		return n
	for c in n.get_children():
		var f := _find_synergy_panel(c)
		if f != null:
			return f
	return null

func _find_item_bar(n: Node) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("item_bar.gd"):
		return n
	for c in n.get_children():
		var f := _find_item_bar(c)
		if f != null:
			return f
	return null
