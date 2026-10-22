# hud_checks.gd
# Dev tool, not part of the game: headless checks for the shop lock, damage meter and team planner.
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
	Settings._loaded = true
	Settings.show_damage_meter = true
	Settings.show_synergies = true
	Settings.show_items = true
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

	print("--- damage meter")
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
	var meter = main.get_node("UI/DamageMeter")
	await wait_phase(Events.Phase.COMBAT)
	await get_tree().create_timer(0.6).timeout
	chk("meter shows during combat with one row per unit that fights", meter.visible and meter.header.text.begins_with("Damage dealt  (") and meter.rows.get_child_count() == gm.snapshot.size(), "%s, %d rows, %d fighting" % [meter.header.text, meter.rows.get_child_count(), gm.snapshot.size()])
	await wait_phase(Events.Phase.PREP)
	await get_tree().process_frame
	var fought: Array = gm.snapshot.keys()
	var total_dealt := 0.0
	for p in fought:
		total_dealt += p.damage_dealt
	chk("after the fight: 'last fight', numbers kept", meter.visible and meter.header.text.contains("last fight") and total_dealt > 0.0, "%s, dealt %d" % [meter.header.text, total_dealt])
	var first_row: HBoxContainer = meter.rows.get_child(0)
	var top_unit: Unit = fought.reduce(func(a, b): return a if a.damage_dealt >= b.damage_dealt else b)
	chk("rows sorted, top row is the top damage dealer", (first_row.get_child(0) as Label).text.begins_with(top_unit.data.display_name) and (first_row.get_child(2) as Label).text == str(roundi(top_unit.damage_dealt)))
	meter.header.pressed.emit()
	await get_tree().process_frame
	chk("header switches to damage taken", meter.show_taken and meter.header.text.begins_with("Damage taken"))
	meter.header.pressed.emit()

	print("--- top-right bar and layout")
	var bar = main.get_node("UI/TopRightBar")
	var planner = main.get_node("UI/TeamPlanner")
	var hp_label: Control = main.get_node("UI/HpLabel")
	chk("bar has Damage, Planner and Menu", bar.damage_button.text == "Damage" and bar.planner_button.text == "Planner" and bar.menu_button.text == "Menu")
	chk("button bar sits above the meter", bar.get_global_rect().end.y <= meter.get_global_rect().position.y, "%s / %s" % [bar.get_global_rect(), meter.get_global_rect()])
	# Worst case in a 1152x648 window: 10 units in the meter vs the HP display above the shop.
	var meter_bottom: float = meter.get_global_rect().end.y + (10 - meter.rows.get_child_count()) * (meter.ROW_H + 3)
	var hp_top: float = 648.0 - 96.0 - hp_label.size.y
	chk("meter with 10 units still ends above the HP display", meter_bottom < hp_top, "meter bottom %d, HP top %d" % [meter_bottom, hp_top])
	chk("HP display is at the bottom right", hp_label.anchor_top == 1.0 and hp_label.anchor_left == 1.0)
	bar.damage_button.button_pressed = false
	Settings._loaded = false
	Settings.load_settings()
	chk("Damage button hides the meter, and it's remembered", not meter.visible and not Settings.show_damage_meter)
	bar.damage_button.button_pressed = true
	chk("Damage button shows it again", meter.visible and Settings.show_damage_meter)
	bar.planner_button.button_pressed = true
	chk("Planner button opens the team planner", planner.visible)
	bar.planner_button.button_pressed = false
	chk("Planner button closes it", not planner.visible)
	bar.menu_button.pressed.emit()
	await get_tree().process_frame
	chk("Menu button opens the pause menu", get_tree().paused and main.get_node("UI/PauseMenu").visible)
	await esc()

	print("--- team planner")
	await key(KEY_P)
	await get_tree().process_frame
	chk("P opens the planner with every unit the shop can offer", planner.visible and planner.grid.get_child_count() == gm.roster.size(), "%d buttons" % planner.grid.get_child_count())
	chk("Planner button lights up when P opens it", bar.planner_button.button_pressed)
	var btn_for := func(unit_name: String) -> Button:
		for b in planner.grid.get_children():
			if not b.is_queued_for_deletion() and (b.text.begins_with(unit_name) or b.text.begins_with("* " + unit_name)):
				return b
		return null
	btn_for.call("Knight").pressed.emit()
	await get_tree().process_frame
	chk("clicking a unit adds it to the plan", SaveGame.team_plan() == ["Knight"] and planner.synergy_label.text.contains("Order 1/2") and planner.summary_label.text.contains("1 units (1 owned)"), "%s | %s" % [planner.summary_label.text, planner.synergy_label.text])
	btn_for.call("Cleric").pressed.emit()
	await get_tree().process_frame
	chk("planned synergies update (Order 2/3 active)", planner.synergy_label.text.contains("Order 2/3 (active)"), planner.synergy_label.text)
	slots[0].show_offer(knight_data)
	slots[1].show_offer(load("res://tres/thief.tres"))
	chk("shop: planned unit gets a star and the gold border", slots[0].text.begins_with("* Knight") and slots[0].has_theme_stylebox_override("normal"))
	chk("shop: other units unchanged", slots[1].text.begins_with("Thief") and not slots[1].has_theme_stylebox_override("normal"))
	btn_for.call("Knight").pressed.emit()
	await get_tree().process_frame
	chk("clicking again removes it, and the shop updates", SaveGame.team_plan() == ["Cleric"] and slots[0].text.begins_with("Knight") and not slots[0].has_theme_stylebox_override("normal"))
	await esc()
	chk("Esc closes the planner without pausing", not planner.visible and not get_tree().paused)
	await esc()
	chk("Esc again pauses as usual", get_tree().paused)
	await esc()
	SaveGame._loaded = false
	chk("the plan is saved to disk", SaveGame.team_plan() == ["Cleric"])
	SaveGame.reset_progress()
	chk("Reset campaign progress keeps the team plan", SaveGame.team_plan() == ["Cleric"])
	await get_tree().process_frame
	chk("Planner button goes dark once the planner is closed", not bar.planner_button.button_pressed)

	print("--- fold-out lists")
	var syn = main.get_node("UI/SynergyBox/SynergyPanel")
	syn._last_sig = ""
	syn._refresh()
	chk("synergy list starts open", syn.list.visible and syn.header.text == "Synergies  [-]" and syn.list.get_child_count() > 0)
	syn.header.pressed.emit()
	chk("clicking the header folds it and shows the active count", not syn.list.visible and syn.header.text.begins_with("Synergies (") and syn.header.text.ends_with("active)  [+]") and not Settings.show_synergies, syn.header.text)
	syn.header.pressed.emit()
	chk("clicking again unfolds it", syn.list.visible and Settings.show_synergies)
	var ib = main.get_node("UI/ItemBar")
	GameState.me.items.clear()
	GameState.me.items.append(load("res://tres/items/longsword.tres"))
	GameState.me.items.append(load("res://tres/items/iron_belt.tres"))
	Events.items_changed.emit()
	await get_tree().process_frame
	chk("item bar starts open with its grid", ib.visible and ib.grid.visible and ib.header.text == "Items  [-]")
	ib.header.pressed.emit()
	chk("clicking the header folds it and shows the item count", not ib.grid.visible and ib.header.text == "Items (2)  [+]" and not Settings.show_items, ib.header.text)
	ib.header.pressed.emit()
	chk("clicking again unfolds it", ib.grid.visible and Settings.show_items)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
