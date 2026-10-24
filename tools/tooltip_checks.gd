# tooltip_checks.gd
# Dev tool, not part of the game: measures every tooltip in the game and fails if one is too wide or
# too tall to fit on screen (Godot doesn't wrap tooltips, so a long single line runs off the edge).
# It builds the main menu (every panel), a free-play run with units, items, the planner, the shop lock
# and the pause menu, a campaign level, and the tutorial, then measures each Control's tooltip lines
# with the default font. New tooltips must go through Tip.wrap(). Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/tooltip_checks.tscn --fixed-fps 60
# Prints PASS/FAIL per check and RESULT at the end. Uses throwaway save, settings and snapshot files.

extends Node

const MAX_LINE_PX := 360.0   # Tip.MAX_WIDTH plus a little slack
const MAX_LINES := 14
const WINDOW := Vector2(1152, 648)

var fails := 0
var seen := {}   # tooltip text -> where it was found (each distinct tooltip is measured once)

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

# What's wrong with a tooltip, or "" if it fits.
func problem(text: String) -> String:
	var lines := text.split("\n")
	if lines.size() > MAX_LINES:
		return "%d lines" % lines.size()
	for line in lines:
		var w := Tip.width_of(line)
		if w > MAX_LINE_PX:
			return "a line is %d px wide: \"%s\"" % [w, line.left(60)]
	return ""

# Records every tooltip under `root`, and reports the ones that don't fit.
func scan(root: Node, label: String) -> int:
	var bad := 0
	var count := 0
	var nodes: Array = root.find_children("*", "Control", true, false)
	if root is Control:
		nodes.append(root)
	for n in nodes:
		var c := n as Control
		var text: String = c.get_tooltip(Vector2(4, 4))   # covers tooltip_text and _get_tooltip overrides
		if text == "":
			continue
		count += 1
		seen[text] = "%s / %s" % [label, c.name]
		var p := problem(text)
		if p != "":
			bad += 1
			print("   TOO BIG in %s, %s: %s" % [label, c.name, p])
	print("   %s: %d tooltips, %d too big" % [label, count, bad])
	return bad

func frames(n := 3):
	for i in n:
		await get_tree().process_frame

func _run():
	SaveGame.path = "user://tooltip_test_save.json"
	SaveGame.reset_progress()
	Settings.path = "user://tooltip_test_settings.cfg"
	Settings._loaded = true
	LocalSnapshotStore.root = "user://tooltip_test_snapshots"

	print("--- the measurement itself")
	var old_async := "Free-play rules, but every round you fight a ghost: a board saved from an earlier run, recorded at the same round. Your own boards are saved too. With no ghosts saved yet you meet random enemies. Boards stay on this PC for now."
	chk("the old Async PvP tooltip would not fit (a line wider than the window)", Tip.width_of(old_async) > WINDOW.x and problem(old_async) != "", "%d px on one line" % Tip.width_of(old_async))
	chk("wrapping fixes it", problem(Tip.wrap(old_async)) == "", Tip.wrap(old_async).replace("\n", " | ").left(110))
	chk("wrapping keeps every word and the author's own line breaks", Tip.wrap("a b\nc d").replace("\n", " ") == "a b c d" and Tip.wrap("one\ntwo") == "one\ntwo" and Tip.wrap("") == "")
	chk("a long word that can't be broken stays on its own line", Tip.wrap("x " + "w".repeat(80) + " y").split("\n").size() == 3)

	var probe := Control.new()
	var sloppy := Button.new()
	sloppy.name = "SloppyButton"
	sloppy.tooltip_text = old_async   # an unwrapped tooltip, like the one that ran off the screen
	probe.add_child(sloppy)
	add_child(probe)
	var probe_bad := scan(probe, "probe (expected to be flagged)")
	seen.clear()
	probe.free()
	chk("the scanner flags an unwrapped tooltip", probe_bad == 1)

	print("--- main menu")
	var menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await frames()
	var bad := scan(menu, "menu")
	menu._show_panel(menu.campaign_panel)
	await frames()
	bad += scan(menu, "campaign panel")
	menu._show_panel(menu.settings_panel)
	await frames()
	bad += scan(menu, "settings panel")
	menu._show_panel(menu.lobby_panel)
	await frames()
	bad += scan(menu, "lobby panel")
	menu.free()
	chk("main menu: every tooltip fits", bad == 0)

	print("--- a free-play run: shop, units, items, planner, lock, pause menu")
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.ghost_mode = false
	var main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").debug_level = null
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	await frames()
	var board: Board = main.get_node("Board")
	GameState.me.level = 8
	GameState.me.gold = 99
	board.refresh_unlocks(8, false)
	var c := 0
	for d in _cover_every_tag(main.get_node("Game Manager").unit_pool):
		var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
		board.get_node("Units").add_child(u)
		u.setup(d, 0)
		board.put_on_tile(u, board.player_order[c])
		c += 1
	for it in ["iron_belt", "longsword", "quick_bow", "mana_charm", "chain_vest", "blood_fang"]:
		GameState.me.items.append(load("res://tres/items/%s.tres" % it))
	Events.items_changed.emit()
	main.get_node("UI/RightDock").open_panel("planner")
	main.get_node("UI/ShopPanel").lock_button.button_pressed = true   # Reroll gets its "unlock first" tooltip
	main.get_node("Game Manager").roll_shop()
	await frames(8)   # the synergy list refreshes a few times a second
	bad = scan(main, "free play")
	main.free()
	chk("free play: every tooltip fits (every synergy tag, 6 items, the whole planner, shop, HUD, pause menu)", bad == 0)

	print("--- a campaign level with the biggest wave (stage label lists the enemies)")
	var camp: Campaign = load("res://tres/campaign/campaign.tres")
	var worst: CampaignLevel = null
	var worst_n := 0
	for lvl in camp.all_levels():
		for w in lvl.waves:
			if w.units.size() > worst_n:
				worst_n = w.units.size()
				worst = lvl
	GameState.run_level = worst
	GameState.run_campaign = camp
	GameState.launched_from_menu = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames()
	var biggest := 1
	for i in worst.waves.size():
		if worst.waves[i].units.size() == worst_n:
			biggest = i + 1
			break
	GameState.round_number = biggest
	Events.round_changed.emit(1, biggest)
	await frames()
	var stage_tip: String = main.get_node("UI/TopBar").rounds.tooltip_text
	chk("the round tracker lists a %d-unit wave" % worst_n, stage_tip.split("\n").size() == worst_n + 3, str(stage_tip.split("\n").size()))
	bad = scan(main, "campaign %s wave %d" % [worst.id, biggest])
	main.free()
	chk("campaign: every tooltip fits", bad == 0)

	print("--- the tutorial")
	GameState.run_level = load("res://tres/campaign/tutorial.tres")
	GameState.run_campaign = camp
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames()
	main.get_node("UI/TutorialPanel")._enter_step(4)   # "Watch the fight": Next is greyed out with a tooltip
	await frames()
	bad = scan(main, "tutorial")
	main.free()
	chk("tutorial: every tooltip fits", bad == 0)

	print("--- summary")
	var widest := 0.0
	var widest_text := ""
	for text in seen:
		for line in text.split("\n"):
			if Tip.width_of(line) > widest:
				widest = Tip.width_of(line)
				widest_text = line
	print("   %d distinct tooltips measured; widest line %d px: \"%s\"" % [seen.size(), widest, widest_text.left(70)])
	chk("a real number of tooltips were found (the check isn't empty)", seen.size() >= 40, str(seen.size()))
	chk("the widest line is well inside the %d px window" % WINDOW.x, widest <= MAX_LINE_PX and MAX_LINE_PX < WINDOW.x / 3.0)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	LocalSnapshotStore.root = ""
	GameState.run_level = null
	GameState.run_campaign = null
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

# A small set of units that between them carry every synergy tag, so the synergy list shows them all.
func _cover_every_tag(roster: Array) -> Array:
	var missing := {}
	for t in Synergies.DEFS:
		missing[t] = true
	var picked: Array = []
	while not missing.is_empty():
		var best: UnitData = null
		var best_n := 0
		for x in roster:
			var d := x as UnitData
			if picked.has(d):
				continue
			var n := 0
			for t in d.tags:
				if missing.has(String(t)):
					n += 1
			if n > best_n:
				best_n = n
				best = d
		if best == null:
			break
		picked.append(best)
		for t in best.tags:
			missing.erase(String(t))
	return picked
