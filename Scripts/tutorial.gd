# tutorial.gd
extends HudPlate

# The guided tutorial level (CampaignLevel id "tutorial", started from the main menu's Tutorial button).
# Each step opens as a card in the middle of the screen: the game pauses and everything is dimmed except a
# box round the thing the step is about (Spotlight; the card moves above or below that box when it would
# cover it). The step's words are linked like the inspector's (Glossary, with the game's own words too:
# gold, bench, interest...): hover one for what it means.
#   - Info steps ("next") wait for Next.
#   - Action steps have Got it: the dim lifts, the game goes on, and the card shrinks to a strip at the top
#     with the task while the box keeps pulsing round the target; the step moves on by itself once it is
#     done (checked a few times a second; "?" opens the explanation again).
#   - Steps with "dim": false never dim (watching a fight, the last wave).
# Start fight ends prep early. Steps that talk about a panel open it (Damage, Synergies, Items, King,
# the planner, the shop odds). The level is only won once every step is done: until then its last wave
# comes again (GameManager asks finished()). The two items come from the steps (a Longsword, then a Quick
# Bow, which must go on the same unit: equip_rule), never from drops; every shop offers a Knight and a
# Militia (GameManager sets PlayerRules.must_offer).

const TUTORIAL_ID := &"tutorial"
const LEVEL_PATH := "res://tres/campaign/tutorial.tres"
const CARD_W := 400.0         # the card in the middle
const CARD_W_WIDE := 600.0    # ... beside a tall box
const STRIP_W := 380.0        # the card as a strip at the top while you do the task
const STRIP_TOP := 58.0       # under the top bar
const DIM := Color(0.02, 0.024, 0.04, 0.72)
const HOLE_PAD := 8.0         # room between the target and the box round it

var step := 0
var explaining := false       # the card is up in the middle: game paused, screen dimmed
var title_label: Label
var body_label: RichTextLabel # the explanation (in the middle)
var task_label: RichTextLabel # the task (in the strip)
var progress_label: Label     # "3 / 19"
var progress_bar: DockKit.SegBar
var next_button: Button
var go_button: Button         # Got it: from the explanation to doing it
var fight_button: Button
var help_button: Button       # "?" in the strip: the explanation again
var spot: Spotlight
var _timer := 0.0
var _level_at_step := 1
var _sold := false       # a unit was sold since the sell step began
var _saw_lock := false   # the shop was locked since the lock step began
var _planned := false    # the team plan was changed since the planner step began
var _stars_at_step := 0  # 2-star units when the merge step began: it waits for a new merge
var _inspected := false  # the inspector was opened since the inspect step began
var _wait_next := false  # this step waits for Next after all (a merge made before the merge step)
var _start_step := 3     # the "Start the fight" step: Start fight shows from there on
var _inspect_step := 5   # the "Inspect a unit" step: the step after it may keep the inspector up, later ones close it
var _watch_seen := false # the Watch step has seen its fight running
var _watch_over := false # ... and seen it end: the card is open again with Next
var _slide := 0.0        # tweened offset of the card as it drops in or pops open
var _steps: Array[Dictionary] = []

static func is_tutorial_run() -> bool:
	return GameState.run_level != null and GameState.run_level.id == TUTORIAL_ID

func _ready():
	add_to_group("tutorial")
	visible = is_tutorial_run()
	set_process(visible)
	if not visible:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS   # it runs (and takes clicks) while it pauses the game
	setup_plate(12, 14, 14, PLATE)
	set_edge(HudStyle.EDGE_GOLD)
	mouse_filter = Control.MOUSE_FILTER_STOP   # the card is solid: clicks on it don't reach the board
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	z_index = 31
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var caps := HudStyle.caps(11, HudStyle.GOLD)
	caps.text = "TUTORIAL"
	caps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caps)
	progress_label = HudStyle.number(18, HudStyle.MUTED)
	head.add_child(progress_label)
	progress_bar = DockKit.SegBar.new(12, 4.0)
	progress_bar.color = HudStyle.GOLD
	box.add_child(progress_bar)
	title_label = DockKit.text(19, HudStyle.INK)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_label)
	body_label = DockKit.rich(14, HudStyle.INK)
	body_label.add_theme_constant_override("line_separation", 3)
	box.add_child(body_label)
	task_label = DockKit.rich(13, HudStyle.INK)
	box.add_child(task_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	go_button = _button(row, "Got it", func():
		_set_explaining(false)
		if _steps[step].get("watch", false):
			_animate(-160.0))   # the strip drops in from above
	next_button = _button(row, "Next", func(): _advance())
	fight_button = _button(row, "Start fight", _start_fight)
	help_button = DockKit.secondary_button("?")
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.custom_minimum_size = Vector2(34, 30)
	help_button.tooltip_text = Tip.wrap("Show this step's explanation again.")
	help_button.pressed.connect(func(): _set_explaining(true))
	row.add_child(help_button)
	spot = Spotlight.new()
	spot.name = "TutorialSpotlight"
	get_parent().add_child.call_deferred(spot)
	Events.unit_sold.connect(func(_d, _s, _r): _sold = true)
	Events.shop_lock_changed.connect(func(on):
		if on:
			_saw_lock = true)
	Events.team_plan_changed.connect(func(): _planned = true)
	Events.phase_changed.connect(func(p):   # straight to Watch as the fight starts, before anything moves
		if p == Events.Phase.COMBAT and step == _start_step:
			_advance())
	_build_steps()
	for i in _steps.size():
		if _steps[i].get("start", false):
			_start_step = i
		if _steps[i].get("inspect", false):
			_inspect_step = i
	_enter_step.call_deferred(0)

const PLATE := Color(0.098, 0.110, 0.161, 0.98)   # nearly solid, like the inspector

# Each step: title; text (the explanation); task (the strip's line while you do it); target (what the
# box goes round: _target_rect); next (waits for Next) or done (moves on when true); next_when (Next is
# greyed out until true); enter (on arrival); start (the Start fight step); dim (false: never dims);
# last (the final step).
func _build_steps():
	_steps = [
		{"title": "Welcome!", "next": true,
			"text": "You lead a small army on a hex board. Between fights you buy units, place them and plan your team; when a fight starts, your units battle on their own.\n\nWin fights to keep your HP and grow stronger every round. This tutorial shows one thing at a time. Hover any gold word to see what it means."},
		{"title": "Buy a unit", "target": "shop", "task": "Click a unit in the shop to buy it.",
			"text": "This is the shop: five units for sale each round. Each card shows the unit's cost, and your gold is at the bottom left.\n\nClick a card to buy it. The unit appears on your bench, the framed row of hexes below the board.",
			"done": func(): return _board().all_player_units().size() >= 1},
		{"title": "Place it on the board", "target": "bench_board", "task": "Drag the unit from your bench onto a bright hex of your half.",
			"text": "Only units on the board fight; the bench is a waiting room. Drag your unit from the bench onto one of the bright hexes of your half of the board, the half nearest you.\n\nYour level is your unit cap: at level 1 you may field one unit. Try to place more and BOARD FULL flashes.",
			"done": func(): return _board().units_on_board() >= 1},
		{"title": "Start the fight", "start": true, "target": "topbar", "task": "Press Start fight.",
			"text": "Normally a fight starts when the prep timer at the top runs out. In the tutorial you start it yourself, whenever you're ready.\n\nPress Start fight.",
			"done": func(): return _gm().phase == Events.Phase.COMBAT},
		# Entered as the fight starts, paused before the first move; Watch drops it to a small strip at the top
		# while the fight runs, and it opens again with "after" and Next once the next PREP starts (_process_watch).
		{"title": "Watch the fight", "watch": true, "target": "right",
			"text": "Units walk to the nearest enemy and attack by themselves; when their mana is full they cast their ability. The Damage window on the right shows who dealt the most.\n\nPress Watch: this card gets out of the way and comes back when the fight is over.",
			"task": "Watching the fight. This card opens again when it's over.",
			"after": "A banner over the board said how it went: a win gives +1 gold, a loss costs HP (the You row at the top right). The Damage window still shows who did the most.\n\nClick Next to go on.",
			"enter": func():
				_watch_seen = false
				_watch_over = false
				_open_right("damage")},
		{"title": "Inspect a unit", "inspect": true, "target": "my_units", "task": "Right-click one of your units.",
			"text": "Right-click any unit, yours or an enemy's, to open the inspector: its health, damage, traits, ability and items. Gold words in it can be hovered too.\n\nRight-click empty ground to close it. Try it on one of your units.",
			"enter": func(): _inspected = false, "done": func(): return _inspected},
		# Waits for a merge made during this step (merging earlier doesn't skip it), or for Next if one was made already.
		{"title": "Merge three into a star", "target": "merge", "task": "Buy Knights until three of them merge.",
			"text": "Three copies of the same unit merge into one 2-star unit, much stronger than the three apart. Three 2-stars merge into a 3-star, the strongest a unit gets. It happens by itself, on the bench or the board, and the stars show beside a unit's health bar.\n\nEvery shop here has Knights and Militia. Buy Knights until three of them merge.",
			"enter": func(): _enter_merge(), "done": func(): return _star_count() > _stars_at_step},
		{"title": "Synergies", "target": "left", "task": "Put a Knight and a Militia on the board together.",
			"text": "Every unit has traits: an origin, like Order, and a class, like Warrior. Field enough different units of one trait and they all get its bonus. The Synergies tab on the left counts them; hover a trait to light up its units.\n\nThe Knight and the Militia are both Order. Put one of each on the board to wake it.",
			"enter": func(): _open_left("synergies"), "done": func(): return Synergies.active_tier("Order", int(Synergies.count(_board().all_player_units().filter(func(u): return u.coord.x >= 0)).get("Order", 0))) >= 0},
		# Done once a unit is planned and the planner is closed again.
		{"title": "Plan your team", "target": "right", "task": "Plan a unit in the planner, then close it (Planner tab or P).",
			"text": "The planner helps you aim for a team. Click a unit's portrait in it to add it to your plan: planned units get a gold star in the shop, and the planner lists the traits your plan would wake.\n\nPlan a unit, then close the planner with the Planner tab or P.",
			"enter": func(): _open_right("planner"), "done": func(): return _planned and not _planner_open()},
		{"title": "Equip an item", "target": "left", "task": "Drag the Longsword from the Items tab onto one of your units.",
			"text": "Items make a unit stronger. Here is a Longsword: +20% attack power, so its attacks hit 20% harder. Drag it from the Items tab on the left onto one of your units.\n\nA unit carries up to 3 items. Items stay on unless Tinker's Tongs take them off; you'll find those in later runs.",
			"enter": func(): _enter_items(false), "done": func(): return _board().all_player_units().any(func(u): return not u.items.is_empty())},
		{"title": "Resonance", "target": "items_unit", "task": "Put the Quick Bow on the unit holding the Longsword.",
			"text": "Every basic item has an element, shown beside its name. Two items with different elements on the same unit wake a resonance, a bonus of its own.\n\nPut this Quick Bow (Swift) on the unit holding the Longsword (Might) to wake Flurry. The Items tab lists your resonances, and its Book shows all 16.",
			"enter": func(): _enter_items(true), "done": func(): return _board().all_player_units().any(func(u): return not Resonance.keys_for(u.items).is_empty())},
		{"title": "Your king", "next": true, "target": "king",
			"text": "Each side has a king, on its own hex at the left edge of its half. Every 10 seconds of a fight it strikes a random enemy, harder at higher levels, and it can't be hurt. Your Golden Lion also shields an ally each time.\n\nOther kings bring powers of their own to Free Play and Async PvP: choose yours on the main menu's King screen. The King tab on the left shows your king.",
			"enter": func(): _open_left("king")},
		{"title": "Sell a unit", "target": "sell", "task": "Sell a unit: drag it onto the sell hex, or point at it and press F.",
			"text": "Sell units you no longer need: drag one onto the sell hex beside the bench (the one with the gold coin), or point at it and press F.\n\nYou get its cost back, three times as much for each star above 1. Buy a spare unit and sell it.",
			"enter": func(): _sold = false, "done": func(): return _sold},
		{"title": "Lock the shop", "target": "lock", "task": "Lock the shop, then click Lock again to unlock it.",
			"text": "Like these offers but can't afford them yet? Lock keeps them into the next round instead of rolling new ones; while the shop is locked you can't reroll.\n\nLock the shop, then click it again to unlock it.",
			"enter": func(): _saw_lock = false, "done": func(): return _saw_lock and not GameState.me.shop_locked},
		{"title": "Income and interest", "next": true, "target": "income",
			"text": "Every round pays gold: a base amount, plus interest, +1 for every 10 gold you have saved (up to +5; the coins pile up on the hex beside your half), plus a bonus while you're on a win or loss streak.\n\nSaving up to 50 earns the most. Hover your gold to see next round's income."},
		{"title": "Level up", "target": "level", "task": "Buy XP until you level up.",
			"text": "Buy XP gives 4 XP for 4 gold, and every round gives 2 XP for free. Fill the bar to level up; each segment of the bar is one Buy XP.\n\nA higher level lets you field more units and finds stronger ones in the shop. Buy XP until you level up.",
			"enter": func(): _level_at_step = GameState.me.level, "done": func(): return GameState.me.level > _level_at_step},
		{"title": "The board grows", "next": true, "target": "board",
			"text": "Each level opens more hexes of your half of the board, from the middle outwards, until all of it is open at level 8. The enemy's half grows the same way, and each king moves out to the new edge.\n\nYou can always field as many units as your level."},
		{"title": "Shop odds", "next": true, "target": "odds",
			"text": "The strip above the shop shows the chance of each cost, 1 to 5 gold, in every shop slot at your level.\n\nLevelling up moves the odds toward costlier, stronger units: at level 1 the shop only sells 1-cost units.",
			"enter": func(): _open_odds()},
		{"title": "Win the last wave", "dim": false, "last": true, "target": "",
			"text": "That's everything you need! Fight through the remaining waves; the tutorial ends when you beat the last one. Press Start fight when you're ready.",
			"task": "Win the remaining waves. Press Start fight when you're ready."},
	]

func _process(delta):
	if spot == null or not spot.is_inside_tree():
		return
	var gm = _gm()
	if gm != null and gm.game_over:
		_set_explaining(false)
		spot.visible = false
		visible = false
		return
	if explaining and not get_tree().paused:
		get_tree().paused = true   # (the pause menu closing unpauses)
	var s: Dictionary = _steps[step]
	if s.get("watch", false):
		_process_watch(gm)
	if s.get("last", false):
		visible = gm == null or gm.phase == Events.Phase.PREP   # out of the way while the last waves fight; back for Start fight
	spot.hole = _target_rect(str(s.get("target", "")))
	spot.dim = explaining
	spot.mouse_filter = Control.MOUSE_FILTER_STOP if explaining else Control.MOUSE_FILTER_IGNORE
	_layout()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	_process_inspector()
	if s.has("done") and s.done.call():
		_advance()
	_update_buttons()

# The card: in the middle (above or below the box when it would cover it) while explaining, else a strip
# at the top.
func _layout() -> void:
	var view := get_viewport_rect().size
	var w := CARD_W if explaining else STRIP_W
	if explaining and spot.hole.size.y > view.y * 0.4:
		w = CARD_W_WIDE   # a tall box (the board): a wider, shorter card fits above or below it
	custom_minimum_size = Vector2(w, 0)
	size = Vector2(w, 0)
	var h := get_combined_minimum_size().y
	size = Vector2(w, h)
	var at := Vector2((view.x - w) * 0.5, STRIP_TOP)
	if explaining:
		at.y = (view.y - h) * 0.5
		var hole := spot.hole
		if hole.has_area() and Rect2(at, Vector2(w, h)).grow(12.0).intersects(hole):
			# Above, below, left or right of the box (kept on screen): the spot that covers the least of it.
			var mid := Vector2((view.x - w) * 0.5, (view.y - h) * 0.5)
			var spots := [
				Vector2(mid.x, hole.position.y - 16.0 - h), Vector2(mid.x, hole.end.y + 16.0),
				Vector2(hole.position.x - 16.0 - w, mid.y), Vector2(hole.end.x + 16.0, mid.y)]
			var best := INF
			for c in spots:
				var p := _on_screen(c, Vector2(w, h), view)
				var cover := Rect2(p, Vector2(w, h)).intersection(hole).get_area()
				var score := cover + p.distance_to(mid) * 0.01   # (equal cover: the one nearer the middle)
				if score < best:
					best = score
					at = p
	else:
		at.y += _slide   # (the strip may sit above the screen while it drops in)
		position = at.round()
		return
	position = (_on_screen(at, Vector2(w, h), view) + Vector2(0, _slide)).round()

# The Watch step: once its fight has run and the next PREP starts, the card opens again with Next.
func _process_watch(gm) -> void:
	if _watch_over or gm == null:
		return
	if gm.phase == Events.Phase.COMBAT:
		_watch_seen = true
	elif _watch_seen and gm.phase == Events.Phase.PREP:
		_watch_over = true
		DockKit.set_rich(body_label, _steps[step].after, true)
		_set_explaining(true)
		_animate(24.0)

# Slides the card from `from` px off its place back to it (and fades it in); none with Reduce motion.
func _animate(from: float) -> void:
	if Settings.reduce_motion:
		_slide = 0.0
		return
	_slide = from
	modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(self, "_slide", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.2)

static func _on_screen(p: Vector2, s: Vector2, view: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 8.0, maxf(view.x - s.x - 8.0, 8.0)), clampf(p.y, 8.0, maxf(view.y - s.y - 8.0, 8.0)))

# Next is greyed out until a step's next_when is true. Got it while explaining an action step. Start fight
# in prep from the Start fight step on (while explaining, only on that step itself), not while a step
# waits for Next.
func _update_buttons():
	var s: Dictionary = _steps[step]
	var watch: bool = s.get("watch", false)
	var waits: bool = s.get("next", false) or _wait_next or (watch and _watch_over)
	var action: bool = not waits and not s.get("last", false)
	go_button.text = "Watch" if watch else "Got it"
	progress_bar.visible = explaining or not watch   # the Watch strip is kept as small as it gets
	next_button.visible = waits
	next_button.disabled = s.has("next_when") and not s.next_when.call()
	next_button.tooltip_text = Tip.wrap("After the fight.") if next_button.disabled else ""
	next_button.modulate.a = 0.45 if next_button.disabled else 1.0   # primary buttons look the same when disabled
	var gm = _gm()
	var prep: bool = gm != null and gm.phase == Events.Phase.PREP and not gm.game_over
	fight_button.visible = prep and step >= _start_step and not waits and (not explaining or step == _start_step)
	go_button.visible = explaining and action and step != _start_step
	help_button.visible = not explaining and not waits and s.get("dim", true) and not watch
	body_label.visible = explaining or not s.get("dim", true) and not s.has("task")
	task_label.visible = not body_label.visible

func _advance():
	if step + 1 < _steps.size():
		_enter_step(step + 1)

func _enter_step(i: int):
	step = i
	_wait_next = false
	if i > _inspect_step + 1:
		_close_inspector()   # left open from the Inspect step it would cover the panels later steps open
	var s: Dictionary = _steps[i]
	progress_label.text = "%d / %d" % [i + 1, _steps.size()]
	progress_bar.segments = _steps.size()
	progress_bar.set_ratio(float(i + 1) / _steps.size())
	title_label.text = s.title
	DockKit.set_rich(body_label, s.text, true)
	DockKit.set_rich(task_label, str(s.get("task", "")), true)
	if s.has("enter"):
		s.enter.call()
	_set_explaining(s.get("dim", true))
	Telemetry.tutorial_step(i, s.title)   # the tutorial funnel on the stats page

func _exit_tree() -> void:
	if explaining and is_inside_tree():
		get_tree().paused = false   # never leave the game paused behind us

func body_text() -> String:   # (tests)
	return body_label.get_parsed_text()

# In the middle with the game paused and the screen dimmed, or a strip at the top with the game running.
func _set_explaining(on: bool) -> void:
	explaining = on
	var gm = _gm()
	get_tree().paused = on and not (gm != null and gm.game_over)
	if spot != null:
		spot.dim = on
		if spot.is_inside_tree() and spot.get_parent() == get_parent():   # the dim, then the card, over the rest of the HUD (also for clicks)
			get_parent().move_child(spot, -1)
			get_parent().move_child(self, -1)
	if go_button != null:
		_update_buttons()

func _start_fight() -> void:
	_set_explaining(false)
	var gm = _gm()
	if gm != null:
		gm.end_prep_early()

# The items step hands out a Longsword if the player has no item to practise with (the tutorial has no
# item drops: GameManager clears them).
func _give_item():
	if not GameState.me.items.is_empty() or _board().all_player_units().any(func(u): return not u.items.is_empty()):
		return
	var got: Array[ItemData] = [load("res://tres/items/longsword.tres")]
	GameState.me.receive(got)

# True once the last step is reached: the level may end (GameManager: until then its last wave comes again).
func finished() -> bool:
	return not _steps.is_empty() and step >= _steps.size() - 1

func _process_inspector() -> void:
	var insp = get_parent().get_node_or_null("UnitInspector")   # a sibling in the UI
	if insp != null and insp.visible and insp.shown != null:
		_inspected = true

func _close_inspector() -> void:
	var insp = get_parent().get_node_or_null("UnitInspector")
	if insp != null and insp.visible:
		insp._close()

func _star_count() -> int:
	return _board().all_player_units().filter(func(u): return u.star >= 2).size()

# The merge step: a merge made during it moves on. If one was made earlier, the step says so and waits for Next.
func _enter_merge() -> void:
	_stars_at_step = _star_count()
	if _stars_at_step > 0:
		DockKit.set_rich(body_label, _steps[step].text + "\n\nYou've already merged one, so click Next.", true)
		_wait_next = true

func _enter_items(bow: bool) -> void:
	if bow:
		_give_resonance_item()
	else:
		_give_item()
	_open_left("items")
	var gm = _gm()
	if gm != null and gm.rules != null:
		gm.rules.equip_check = equip_rule

# The tutorial's two items go on one unit: whichever unit gets the first holds the second too (else
# Flurry could never wake and the step would never end). Returns why not, or "" if it may go on.
const PAIR := [&"longsword", &"quick_bow"]
func equip_rule(u: Unit, item: ItemData) -> String:
	if not PAIR.has(item.id):
		return ""
	for other in _board().all_player_units():
		if other == u:
			continue
		for it in other.items:
			if PAIR.has(it.id) and it.id != item.id:
				return "PUT IT ON THE %s WITH THE %s" % [other.data.display_name.to_upper(), it.display_name.to_upper()]
	return ""

# Opens a panel of the right box (damage, planner) without changing the saved choice of panel.
func _open_right(p: String) -> void:
	if p == "planner":
		_planned = false
	var dock = get_tree().get_first_node_in_group("right_dock")
	if dock != null:
		dock._show(p)

# Unfolds the left box on a tab (synergies, items, king) without changing the saved dock layout.
func _open_left(tab: String) -> void:
	var left = get_parent().get_node_or_null("LeftDock")
	if left != null:
		left.collapsed = false
		left.tab = tab
		left._apply()

func _open_odds() -> void:
	var odds = get_parent().get_node_or_null("BottomInfo/OddsLabel")
	if odds != null and odds.has_method("set_open"):
		odds.set_open(true)

func _gm():
	return get_tree().get_first_node_in_group("game_manager")

func _board() -> Board:
	return get_tree().get_first_node_in_group("board") as Board

func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := DockKit.primary_button(text)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 30)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _planner_open() -> bool:
	var dock := get_tree().get_first_node_in_group("right_dock")
	return dock != null and dock.current == "planner"

# The resonance step hands out a Quick Bow (Swift) unless a unit already has a resonance, so the
# Longsword (Might) from the items step can make Flurry.
func _give_resonance_item():
	if _board().all_player_units().any(func(u): return not Resonance.keys_for(u.items).is_empty()):
		return
	var got: Array[ItemData] = [load("res://tres/items/quick_bow.tres")]
	GameState.me.receive(got)

# --- what each step's box goes round (viewport coordinates; empty = the whole screen dims) -------------

func _target_rect(key: String) -> Rect2:
	var ui := get_parent()
	var shop = ui.get_node_or_null("ShopPanel")
	var b := _board()
	var r := Rect2()
	match key:
		"shop":
			for sl in shop.slots:
				r = _union(r, (sl as Control).get_global_rect())
		"bench_board":
			r = _world_rect(_bench_points(b) + _tile_points(b, true))
		"topbar":
			r = _ctl(ui, "TopBar")
		"right":
			r = _ctl(ui, "RightDock")
		"left":
			r = _ctl(ui, "LeftDock")
		"my_units":
			r = _world_rect(_unit_points(b.all_player_units().filter(func(u): return u.coord.x >= 0)))
			if not r.has_area():
				r = _world_rect(_tile_points(b, true))
		"merge":
			for sl in shop.slots:
				r = _union(r, (sl as Control).get_global_rect())
			r = _union(r, _world_rect(_bench_points(b)))
		"items_unit":
			r = _ctl(ui, "LeftDock")
			var holders: Array = b.all_player_units().filter(func(u): return u.items.any(func(it): return PAIR.has(it.id)))
			r = _union(r, _world_rect(_unit_points(holders)))
		"king":
			if not b.kings.is_empty():
				r = _world_rect(_hex_points(b.kings[0].global_position, 1.6))
			r = _union(r, _ctl(ui, "LeftDock"))
		"sell":
			r = _world_rect(_hex_points(b.to_global(b.sell_zone_pos()), 0.4))
		"lock":
			r = _union(shop.lock_button.get_global_rect(), shop.reroll_button.get_global_rect())
		"income":
			r = shop.gold_row.get_global_rect()
			if b.interest != null:
				r = _union(r, _world_rect(_hex_points(b.interest.global_position, 0.8)))
		"level":
			r = _union(shop.row.get_child(0).get_global_rect(), shop.buy_xp_button.get_global_rect())
		"board":
			r = _world_rect(_tile_points(b, false))
		"odds":
			r = _ctl(ui, "BottomInfo/OddsLabel")
	return r.grow(HOLE_PAD) if r.has_area() else Rect2()

func _ctl(ui: Node, path: String) -> Rect2:
	var c := ui.get_node_or_null(path) as Control
	return c.get_global_rect() if c != null and c.is_visible_in_tree() else Rect2()

static func _union(a: Rect2, b: Rect2) -> Rect2:
	if not a.has_area():
		return b
	if not b.has_area():
		return a
	return a.merge(b)

# The screen box round some world points (behind the camera ones are skipped).
func _world_rect(points: Array) -> Rect2:
	var cam := get_viewport().get_camera_3d()
	if cam == null or points.is_empty():
		return Rect2()
	var r := Rect2()
	var first := true
	for p in points:
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		if first:
			r = Rect2(s, Vector2.ZERO)
			first = false
		else:
			r = r.expand(s)
	return r

const HEX_R := 0.85   # a hex's reach from its centre, for the box
func _hex_points(c: Vector3, height := 0.0) -> Array:
	var out := []
	for k in 6:
		var a := k * TAU / 6.0
		out.append(c + Vector3(sin(a) * HEX_R, 0, cos(a) * HEX_R))
	if height > 0.0:
		out.append(c + Vector3(0, height, 0))
	return out

func _bench_points(b: Board) -> Array:
	var out := []
	for i in Board.BENCH_SLOTS:
		out += _hex_points(b.to_global(b.bench_to_world(i)), 1.2)
	return out

# Your open tiles (mine), or the whole board (both halves, open or not).
func _tile_points(b: Board, mine: bool) -> Array:
	var out := []
	for c in b.tiles:
		var cc: Vector2i = c
		if mine and (not b.is_player_side(cc) or not b.is_unlocked(cc)):
			continue
		out += _hex_points((b.tiles[c] as Node3D).global_position)
	return out

func _unit_points(units: Array) -> Array:
	var out := []
	for u in units:
		out += _hex_points((u as Node3D).global_position, 1.8)
	return out

# The dim over the whole screen with a clear box round the target, and a pulsing gold frame round that box
# (the frame stays, without the dim, while you do the task). Takes the mouse only while it dims.
class Spotlight extends Control:
	var hole := Rect2()
	var dim := true
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS
		z_index = 30
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		_t += delta
		position = Vector2.ZERO
		size = get_viewport_rect().size   # (anchors alone left it at no size under the CanvasLayer)
		queue_redraw()

	func _draw() -> void:
		var all := Rect2(Vector2.ZERO, size)
		if dim:
			if hole.has_area():
				var h := hole.intersection(all)
				draw_rect(Rect2(0, 0, size.x, h.position.y), DIM)
				draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), DIM)
				draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), DIM)
				draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), DIM)
			else:
				draw_rect(all, DIM)
		if hole.has_area():
			var pulse := 0.5 + 0.5 * sin(_t * 4.0)
			var gold := Color(HudStyle.GOLD, 0.55 + 0.45 * pulse)
			draw_rect(hole, gold, false, 2.0)
			draw_rect(hole.grow(3.0 + 3.0 * pulse), Color(HudStyle.GOLD, 0.25 * (1.0 - pulse)), false, 2.0)
