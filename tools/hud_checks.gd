# hud_checks.gd
# Dev tool, not part of the game: headless checks for the shop lock, the side boxes (damage, planner,
# menu, synergies, items), the top bar and the camera.
# Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/hud_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses a throwaway save file.

extends Node

var fails := 0
var main: Node
var gm
var board: Board

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func key(code: Key):
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame

func esc():
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame

# Waits for the phase signal, not by polling: a fight with no units ends within one physics frame.
func wait_phase(p: int):
	if gm.phase == p:
		return
	while true:
		var ph = await Events.phase_changed
		if ph == p:
			return

func offer_names() -> Array:
	return GameState.me.shop_offers.map(func(d): return d.display_name)

func _ready():
	_run.call_deferred()

func _run():
	SaveGame.path = "user://hud_test_save.json"
	SaveGame.reset_progress()
	SaveGame.set_team_plan([])
	Settings.path = "user://hud_test_settings.cfg"   # never touch the player's settings
	Keybinds.path = "user://hud_checks_keybinds.cfg"   # default binds, whatever the player has set
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Keybinds.path))
	Keybinds.load_binds()
	Settings._loaded = true
	Settings.show_damage_meter = true
	Settings.dock_collapsed = false
	Settings.dock_tab = "synergies"
	GameState.run_level = null
	GameState.run_carry = {}
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 3
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await get_tree().create_timer(0.3).timeout
	var shop = main.get_node("UI/ShopPanel")
	var slots: Array = shop.slots

	print("--- shop lock")
	chk("Lock button in the shop bar", shop.lock_button.text == "Lock")
	var shop_w: float = shop.get_combined_minimum_size().x
	chk("shop bar still fits a 1152 px window", shop_w <= 1120, "min width %d" % shop_w)
	GameState.me.gold = 50
	var before := offer_names()
	shop.lock_button.button_pressed = true
	chk("pressing Lock locks the shop", GameState.me.shop_locked and shop.lock_button.text == "Locked")
	var bought_slot = slots.filter(func(s): return s.offer != null)[0]
	var bought_name: String = bought_slot.offer.display_name
	bought_slot._pressed()
	var rolls := [0]
	Events.shop_rolled.connect(func(_o): rolls[0] += 1)
	GameState.me.level = 3   # room on the board isn't needed; keep the fight short
	await wait_phase(Events.Phase.COMBAT)
	await wait_phase(Events.Phase.PREP)
	var after := offer_names()
	var expected := before.duplicate()
	expected.erase(bought_name)
	chk("locked: next round keeps the same offers (minus the one bought)", rolls[0] == 0 and after == expected, "%s -> %s" % [before, after])
	chk("locked: the bought slot stays empty", bought_slot.offer == null and bought_slot.disabled)
	GameState.me.gold = 50
	var reroll_btn: Button = shop.get_node("HBoxContainer/RerollButton")
	chk("locked: the Reroll button is disabled", reroll_btn.disabled)
	Events.reroll_pressed.emit()
	chk("locked: a reroll does nothing (no roll, no gold spent, same offers)", rolls[0] == 0 and GameState.me.gold == 50 and offer_names() == expected and GameState.me.shop_locked)
	slots.filter(func(s): return s.offer != null)[0]._pressed()   # a second empty slot
	var empties := slots.filter(func(s): return s.offer == null).size()
	shop.lock_button.button_pressed = false
	chk("pressing again unlocks and re-enables Reroll", not GameState.me.shop_locked and shop.lock_button.text == "Lock" and not reroll_btn.disabled)
	var gold_before_reroll := GameState.me.gold
	Events.reroll_pressed.emit()
	chk("unlock + reroll replaces the whole shop: all 5 slots filled and buyable", empties == 2 and rolls[0] == 1 and GameState.me.gold == gold_before_reroll - 2 and GameState.me.shop_offers.size() == 5 and slots.all(func(s): return s.offer != null and not s.disabled), "%d empty before, offers %s" % [empties, offer_names()])
	await wait_phase(Events.Phase.COMBAT)
	await wait_phase(Events.Phase.PREP)
	chk("unlocked: the next round rolls a new shop", rolls[0] == 2)

	print("--- damage numbers")
	var knight_data: UnitData = load("res://tres/knight.tres")
	var t := main.get_node("Board/Units")
	var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
	t.add_child(u)
	u.setup(knight_data, 1)
	u.begin_combat()
	var hp0 := u.health
	var removed := u.take_damage(100.0)
	chk("take_damage returns the HP removed and counts damage_taken", is_equal_approx(removed, 100.0) and is_equal_approx(u.damage_taken, 100.0) and is_equal_approx(u.health, hp0 - 100.0))
	u.health = 30.0
	removed = u.take_damage(100.0)
	chk("no overkill: only the 30 HP left count", is_equal_approx(removed, 30.0) and u.dead)
	u.free()

	print("--- damage panel (right box)")
	GameState.me.gold = 50
	for n in ["knight", "archer"]:
		Events.unit_bought.emit(load("res://tres/%s.tres" % n))
	var mine := board.all_player_units()
	var c := 0
	for p in mine:
		if p.coord.x < 0 and c < 2:
			board.detach(p)
			board.put_on_tile(p, board.player_order[c])
			c += 1
	var dock = main.get_node("UI/RightDock")
	var meter = dock.damage
	chk("the right box opens on the damage panel (remembered as on)", dock.current == "damage" and meter.visible and dock.panel.visible)
	await wait_phase(Events.Phase.COMBAT)
	await get_tree().create_timer(0.6).timeout
	chk("damage panel shows during combat with one row per unit that fights", meter.is_visible_in_tree() and meter.caption.text == "THIS FIGHT · DAMAGE DEALT" and meter.rows.get_child_count() == gm.snapshot.size(), "%s, %d rows, %d fighting" % [meter.caption.text, meter.rows.get_child_count(), gm.snapshot.size()])
	await wait_phase(Events.Phase.PREP)
	await get_tree().process_frame
	var fought: Array = gm.snapshot.keys()
	var total_dealt := 0.0
	for p in fought:
		total_dealt += p.damage_dealt
	chk("after the fight: 'last fight', numbers kept, total shown", meter.caption.text.begins_with("LAST FIGHT") and total_dealt > 0.0 and meter.total_label.text == str(roundi(total_dealt)), "%s, dealt %d, total %s" % [meter.caption.text, total_dealt, meter.total_label.text])
	var first_row: Control = meter.rows.get_child(0)
	var top_unit: Unit = fought.reduce(func(a, b): return a if a.damage_dealt >= b.damage_dealt else b)
	chk("rows sorted, top row is the top damage dealer", first_row.get_meta("unit") == top_unit)
	meter.taken_button.pressed.emit()
	await get_tree().process_frame
	chk("Taken switches the view", meter.show_taken and meter.caption.text.ends_with("DAMAGE TAKEN"))
	meter.dealt_button.pressed.emit()
	chk("Dealt switches back", not meter.show_taken)

	print("--- right box: tabs and layout")
	var planner = dock.planner
	var standings: Control = main.get_node("UI/Standings")
	chk("tabs: Damage, Planner, Menu", dock.tabs.has("damage") and dock.tabs.has("planner") and dock.tabs.has("menu"))
	var drect: Rect2 = dock.get_global_rect()
	chk("the right box sits top right, 236 px wide", is_equal_approx(drect.size.x, 236.0) and is_equal_approx(drect.end.x, 1142.0) and is_equal_approx(drect.position.y, 10.0), str(drect))
	var srect: Rect2 = standings.get_global_rect()
	chk("HP standings: 210 px wide at the right edge, below the right box", is_equal_approx(srect.size.x, 210.0) and is_equal_approx(srect.end.x, 1150.0) and srect.position.y >= 129.0, str(srect))
	chk("standings show your HP", standings.you_row() != null and standings.you_row().hp_lbl.text == str(GameState.me.player_hp) and standings.opponent_row() != null)
	var insp_layout = main.get_node("UI/UnitInspector")
	chk("the unit inspector sits bottom right, clear of the standings", insp_layout.anchor_top == 1.0 and insp_layout.anchor_left == 1.0 and insp_layout.offset_bottom == -96)
	dock.tabs["damage"].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	Settings._loaded = false
	Settings.load_settings()
	chk("clicking the open Damage tab closes it, and it's remembered", dock.current == "" and not dock.panel.visible and not Settings.show_damage_meter)
	chk("with no panel open the standings move back up to y = 129", is_equal_approx(standings.get_global_rect().position.y, 129.0), str(standings.get_global_rect()))
	dock.tabs["damage"].pressed.emit()
	chk("clicking it again opens it", dock.current == "damage" and Settings.show_damage_meter)
	dock.tabs["planner"].pressed.emit()
	chk("Planner tab opens the planner and closes the damage panel", dock.current == "planner" and planner.visible and not meter.visible)
	dock.tabs["planner"].pressed.emit()
	chk("clicking it again closes it, and the damage panel comes back", dock.current == "damage" and not planner.visible and meter.visible)
	dock.tabs["menu"].pressed.emit()
	await get_tree().process_frame
	chk("Menu tab opens the menu, pauses and dims the board", get_tree().paused and dock.current == "menu" and dock.menu.visible and dock.dim.visible)
	chk("the dim sits under the whole HUD", dock.dim.get_index() == 0)
	await esc()
	chk("Esc resumes and the damage panel comes back", not get_tree().paused and dock.current == "damage" and not dock.dim.visible)

	print("--- team planner")
	await key(KEY_P)
	await get_tree().process_frame
	var at1: int = gm.roster.filter(func(d): return d.cost == 1).size()
	chk("P opens the planner on the 1-gold tab with every 1-gold unit", dock.current == "planner" and planner.cost == 1 and planner.grid.get_child_count() == at1, "%d tiles, %d units" % [planner.grid.get_child_count(), at1])
	planner.show_cost(5)
	chk("cost tabs switch the grid", planner.grid.get_children().all(func(t): return gm.roster.filter(func(d): return d.display_name == t.get_meta("unit"))[0].cost == 5))
	planner.show_cost(1)
	planner.tile_for("Knight").pressed.emit()
	await get_tree().process_frame
	chk("clicking a unit adds it to the plan", SaveGame.team_plan() == ["Knight"] and planner.summary_label.text == "1 of %d planned at 1 gold" % at1 and planner.planned_label.text == "1 unit planned", "%s | %s" % [planner.summary_label.text, planner.planned_label.text])
	chk("planned synergy chips (Order 1/2, not active)", planner.chip_entries([load("res://tres/knight.tres")]).has(["Order", "1/2", false]))
	planner.tile_for("Militia").pressed.emit()
	await get_tree().process_frame
	var ents: Array = planner.chip_entries(gm.roster.filter(func(d): return SaveGame.team_plan().has(d.display_name)))
	chk("planned synergies update (Order 2/3 active, listed first)", ents[0] == ["Order", "2/3", true], str(ents))
	chk("a planned tile gets the gold outline", (planner.tile_for("Militia").get_theme_stylebox("normal") as StyleBoxFlat).border_color == HudStyle.GOLD)
	slots[0].show_offer(knight_data)
	slots[1].show_offer(load("res://tres/thief.tres"))
	chk("shop: planned unit gets a star and the gold border", slots[0].shown_name() == "Knight" and slots[0].planned and slots[0].star_label.visible and (slots[0].get_theme_stylebox("normal") as StyleBoxFlat).border_color == HudStyle.GOLD)
	chk("shop: other units unchanged", slots[1].shown_name() == "Thief" and not slots[1].planned and not slots[1].star_label.visible and (slots[1].get_theme_stylebox("normal") as StyleBoxFlat).border_color != HudStyle.GOLD)
	planner.tile_for("Knight").pressed.emit()
	await get_tree().process_frame
	chk("clicking again removes it, and the shop updates", SaveGame.team_plan() == ["Militia"] and slots[0].shown_name() == "Knight" and not slots[0].planned and not slots[0].star_label.visible)
	await esc()
	chk("Esc closes the planner without pausing", dock.current == "damage" and not get_tree().paused)
	await esc()
	chk("Esc again pauses as usual", get_tree().paused and dock.current == "menu")
	await esc()
	SaveGame._loaded = false
	chk("the plan is saved to disk", SaveGame.team_plan() == ["Militia"])
	SaveGame.reset_progress()
	chk("Reset campaign progress keeps the team plan", SaveGame.team_plan() == ["Militia"])
	await get_tree().process_frame
	chk("the Planner tab is no longer active once the planner is closed", dock.current != "planner")

	print("--- left box (synergies / items)")
	var left = main.get_node("UI/LeftDock")
	var lrect: Rect2 = left.get_global_rect()
	chk("left box at the top left, 232 px wide", is_equal_approx(lrect.position.x, 10.0) and is_equal_approx(lrect.position.y, 10.0) and is_equal_approx(lrect.size.x, 232.0), str(lrect))
	var syn = left.synergies
	syn._last_sig = ""
	syn._refresh()
	left._update_badges()
	var cnt: Dictionary = syn.counts()
	var shown: Array = syn.shown_tags()
	var act: Array = shown.map(func(t): return Synergies.active_tier(t, cnt[t]) >= 0)
	chk("Synergies tab: a row per tag on the board, active ones first", shown.size() == cnt.keys().filter(func(t): return Synergies.DEFS.has(t)).size() and shown.size() > 0 and not (act.find(false) != -1 and act.rfind(true) > act.find(false)), "%s %s" % [shown, act])
	chk("the Synergies badge counts active synergies", left.synergy_badge.text == str(act.count(true)) and syn.active_count == act.count(true))
	chk("tier effect text picks the reached tier", DockKit.effect_text("Order", 1) == "Order +25% HP" and DockKit.effect_text("Order", 0) == "Order +15% HP")
	GameState.me.items.clear()
	for it in ["longsword", "iron_belt", "longsword"]:
		GameState.me.items.append(load("res://tres/items/%s.tres" % it))
	Events.items_changed.emit()
	await get_tree().process_frame
	left._update_badges()
	chk("the Items badge counts items, duplicates included", left.items_badge.text == "3")
	left.items_tab.pressed.emit()
	chk("Items tab: one row per item type", left.items.visible and not syn.visible and left.items.list.get_child_count() == 2 and Settings.dock_tab == "items")
	var dragged := [-1]
	Events.item_drag_started.connect(func(i): dragged[0] = i, CONNECT_ONE_SHOT)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	left.items.list.get_child(1).gui_input.emit(press)
	chk("pressing an item row starts dragging that item", dragged[0] == 1, str(dragged[0]))
	Events.item_drag_ended.emit()
	left.collapse_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	Settings._loaded = false
	Settings.load_settings()
	chk("collapse folds it to a 46 px rail, remembered", left.collapsed and left.rail.is_visible_in_tree() and not left.open_box.visible and is_equal_approx(left.get_global_rect().size.x, 46.0) and Settings.dock_collapsed, str(left.get_global_rect()))
	chk("the rail buttons carry the badges", left.rail_items_badge.text == "3" and left.rail_synergy_badge.text == str(syn.active_count))
	left.rail_synergies.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	chk("a rail button expands the box on its tab", not left.collapsed and left.tab == "synergies" and syn.visible and is_equal_approx(left.get_global_rect().size.x, 232.0) and not Settings.dock_collapsed)

	print("--- timer label and inspector (fresh scene, 3 s prep)")
	main.free()
	GameState.run_level = null
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 3
	add_child(main)
	gm = main.get_node("Game Manager")
	board = main.get_node("Board")
	await get_tree().create_timer(0.5).timeout
	var timer = main.get_node("UI/TopBar").timer
	chk("prep shows a countdown", timer.visible and timer.phase_label.text == "PREP" and timer.time_label.text.begins_with("0:"), "%s %s" % [timer.phase_label.text, timer.time_label.text])
	var top = main.get_node("UI/TopBar")
	chk("the top bar is flush with the top of the screen", is_equal_approx(top.get_global_rect().position.y, 0.0), str(top.get_global_rect()))
	top.fold_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	chk("folding the top bar leaves just the round and the time, and is remembered", not top.expanded and not top.rounds.pips.visible and not top.rounds.stage_label.visible and not top.timer.phase_label.visible and top.rounds.count_label.visible and top.timer.time_label.visible and not Settings.show_top_bar)
	var folded_rect: Rect2 = top.get_global_rect()
	chk("the folded bar is centred on the screen", absf(folded_rect.get_center().x - 576.0) <= 1.0, str(folded_rect))
	top.fold_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	chk("unfolding brings it all back", top.expanded and top.rounds.pips.visible and top.timer.phase_label.visible and Settings.show_top_bar)
	chk("the unfolded bar is centred too", absf(top.get_global_rect().get_center().x - 576.0) <= 1.0, str(top.get_global_rect()))
	var rig = main.get_node("CameraRig")
	rig.zoom_by(-100.0)
	var zmin: float = rig.zoom
	rig.zoom_by(100.0)
	var zmax: float = rig.zoom
	rig.zoom = 1.0
	chk("camera zoom is clamped", is_equal_approx(zmin, rig.ZOOM_MIN) and is_equal_approx(zmax, rig.ZOOM_MAX))
	rig.drag(Vector2(576, 300), Vector2(976, 600))
	chk("at the default zoom the view can't be dragged", rig.position.distance_to(rig.target) < 0.001, str(rig.position))
	rig.zoom = rig.ZOOM_MIN
	rig._zoom_now = rig.ZOOM_MIN
	rig._place()
	var centre: Vector3 = rig.position
	rig.drag(Vector2(576, 300), Vector2(526, 330))
	chk("zoomed in, a small drag moves the view", rig.position.distance_to(centre) > 0.1, "%s -> %s" % [centre, rig.position])
	for i in 30:
		rig.drag(Vector2(576, 300), Vector2(176, 600))
	var far_pos: Vector3 = rig.position
	rig.drag(Vector2(576, 300), Vector2(176, 600))
	chk("dragging far stops at the edge of the default view", far_pos.distance_to(rig.position) < 0.001 and far_pos.distance_to(centre) < 8.0, str(far_pos))
	rig.pan = Vector3.ZERO
	rig.zoom = 1.0
	rig._zoom_now = 1.0
	rig._place()
	var left0: float = gm.prep_left
	get_tree().paused = true
	await get_tree().create_timer(0.5, true, false, true).timeout
	chk("pausing stops the prep countdown", is_equal_approx(gm.prep_left, left0), "%s -> %s" % [left0, gm.prep_left])
	get_tree().paused = false

	# Inspector: synergy bonuses are folded into the stats, with no extra wording.
	GameState.me.gold = 50
	GameState.me.level = 3
	Events.unit_bought.emit(load("res://tres/knight.tres"))
	Events.unit_bought.emit(load("res://tres/units/militia.tres"))
	var k: Unit = board.all_player_units().filter(func(x): return x.data.display_name == "Knight")[0]
	var cl: Unit = board.all_player_units().filter(func(x): return x.data.display_name == "Militia")[0]
	var insp2 = main.get_node("UI/UnitInspector")
	insp2.shown = k
	insp2._fill()
	chk("benched Knight: base stats, no synergy", insp2.stats_label.text.begins_with("Health: 650\nDamage: 50"), insp2.stats_label.text.replace("\n", " | "))
	board.detach(k); board.put_on_tile(k, board.player_order[0])
	insp2._fill()
	chk("alone on the board: still base stats", insp2.stats_label.text.begins_with("Health: 650"))
	board.detach(cl); board.put_on_tile(cl, board.player_order[1])
	insp2._fill()
	chk("Knight + Militia (Order 2): Knight health is 650 x 1.15", insp2.stats_label.text.begins_with("Health: %d
Damage: 50" % roundi(650.0 * 1.15)), insp2.stats_label.text.replace("
", " | "))
	chk("the synergy isn't called out in the text", not insp2.stats_label.text.to_lower().contains("synerg") and not insp2.stats_label.text.contains("(+"))
	var gold_item := load("res://tres/items/iron_belt.tres")
	k.equip(gold_item)
	insp2._fill()
	chk("an item stacks with it: (650 + 150) x 1.15, item note kept", insp2.stats_label.text.begins_with("Health: %d  (+%d items)" % [roundi(800.0 * 1.15), roundi(150.0 * 1.15)]), insp2.stats_label.text.split("\n")[0])
	var timed := [false]
	Events.phase_changed.connect(func(p):
		if p == Events.Phase.COMBAT:
			timed[0] = true, CONNECT_ONE_SHOT)
	var waited := 0
	while not timed[0] and waited < 600:
		await get_tree().process_frame
		waited += 1
	chk("the prep timer runs out by itself and the fight starts", timed[0])
	await get_tree().process_frame
	chk("fight: the timer counts down the fight (COMBAT m:ss)", (timer.phase_label.text == "COMBAT" and (timer.time_label.text == "1:00" or timer.time_label.text.begins_with("0:"))) or gm.phase != Events.Phase.COMBAT, "%s %s" % [timer.phase_label.text, timer.time_label.text])
	if gm.fighting:
		insp2._fill()
		chk("during the fight the inspector shows the same real bonuses", insp2.stats_label.text.begins_with("Health: %d" % roundi(800.0 * 1.15)), insp2.stats_label.text.split("\n")[0])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
