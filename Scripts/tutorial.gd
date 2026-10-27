# tutorial.gd
extends HudPlate

# Step-by-step guide shown only in the tutorial level (CampaignLevel id "tutorial", started from
# the main menu's Tutorial button). Each step explains one mechanic and moves on by itself once the
# player has done it (checked a few times a second). Start fight ends prep early, so nobody has to
# race the prep timer while reading. Steps that talk about a panel open it (the Damage window, the Synergies
# and Items tabs, the planner, the shop odds). The level is only won once every step is done: until then
# its last wave comes again (GameManager asks finished()). The items come from the steps (a Longsword,
# then a Quick Bow), never from drops.
# Styled like the side boxes (a HUD plate with a gold top edge, DockKit text and buttons).

const TUTORIAL_ID := &"tutorial"
const LEVEL_PATH := "res://tres/campaign/tutorial.tres"
var step := 0
var title_label: Label
var body_label: Label
var progress_label: Label   # "3 / 12"
var progress_bar: DockKit.SegBar
var next_button: Button
var fight_button: Button
var _timer := 0.0
var _level_at_step := 1
var _sold := false       # a unit was sold since the sell step began
var _saw_lock := false   # the shop was locked since the lock step began
var _planned := false    # the team plan was changed since the planner step began
var _stars_at_step := 0  # 2-star units when the merge step began: it waits for a new merge
var _inspected := false  # the inspector was opened since the inspect step began
var _start_step := 3     # the "Start the fight" step: Start fight shows from there on
var _steps: Array[Dictionary] = []

static func is_tutorial_run() -> bool:
	return GameState.run_level != null and GameState.run_level.id == TUTORIAL_ID

func _ready():
	add_to_group("tutorial")
	visible = is_tutorial_run()
	set_process(visible)
	if not visible:
		return
	setup_plate(10, 12, 12, DockKit.PANEL_FILL)
	set_edge(HudStyle.EDGE_GOLD)
	mouse_filter = Control.MOUSE_FILTER_STOP   # the panel itself is solid: clicks on it don't reach the board
	custom_minimum_size = Vector2(320, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
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
	title_label = DockKit.text(17, HudStyle.INK)
	box.add_child(title_label)
	body_label = DockKit.wrapping(13, HudStyle.MUTED, 296)
	body_label.add_theme_constant_override("line_spacing", 2)
	box.add_child(body_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	next_button = _button(row, "Next", func(): _advance())
	fight_button = _button(row, "Start fight", func():
		var gm = _gm()
		if gm != null:
			gm.end_prep_early())
	Events.unit_sold.connect(func(_d, _s, _r): _sold = true)
	Events.shop_lock_changed.connect(func(on):
		if on:
			_saw_lock = true)
	Events.team_plan_changed.connect(func(): _planned = true)
	_build_steps()
	for i in _steps.size():
		if _steps[i].get("start", false):
			_start_step = i
	_enter_step(0)

func _build_steps():
	_steps = [
		{"title": "Welcome!", "text": "This short tutorial teaches the basics. Most steps move on by themselves once you've done them; the others wait for Next.\n\nYour units fight automatically. Your job is to build the strongest team between fights.", "next": true},
		{"title": "Buy a unit", "text": "The shop is at the bottom. Click a unit to buy it (its cost is under the name). Bought units go to your bench, the row of framed hexes below the board.", "done": func(): return _board().all_player_units().size() >= 1},
		{"title": "Place it on the board", "text": "Drag the unit from the bench onto one of the glowing tiles of your half of the board (the bottom half). Your level (bottom left) decides how many units you can field: try to place one more and BOARD FULL flashes.", "done": func(): return _board().units_on_board() >= 1},
		{"title": "Start the fight", "start": true, "text": "Fights start when the prep timer runs out. In the tutorial you can press Start fight whenever you're ready.", "done": func(): return _gm().phase == Events.Phase.COMBAT},
		# Waits for Next (enabled once the fight is over), so a quick win doesn't skip the explanation.
		{"title": "Watch the fight", "text": "Units walk to the nearest enemy and attack. The Damage window (open on the right) shows who did the most. Losing a fight costs HP (the You row, top right); winning gives +1 gold. A banner over the board says how each fight went.\n\nClick Next once the fight is over.", "enter": func(): _open_right("damage"), "next": true, "next_when": func(): return _gm().phase == Events.Phase.PREP and GameState.round_number >= 2},
		{"title": "Inspect a unit", "text": "Right-click any unit, yours or an enemy's, to open the inspector (bottom right): its stats, traits, ability and items. Right-click empty ground to close it. Try it on one of your units.", "enter": func(): _inspected = false, "done": func(): return _inspected},
		# Waits for a merge made during this step (merging earlier doesn't skip it), or for Next if one was made already.
		{"title": "Merge three into a star", "text": "Three copies of the same unit merge into a stronger 2-star unit, and three 2-stars of a unit merge into a 3-star, the strongest it gets. Stars show beside a unit's health bar. Buy Knights until three of them merge (the shop only sells Knights and Militia here).", "enter": func(): _enter_merge(), "done": func(): return _star_count() > _stars_at_step},
		{"title": "Synergies", "text": "Units share traits like Order or Warrior. With enough different units of one trait on the board, the whole group gets a bonus. Put a Knight and a Militia on the board together to activate Order (see the Synergies tab, open on the left; hover a trait to light up its units).", "enter": func(): _open_left("synergies"), "done": func(): return Synergies.active_tier("Order", int(Synergies.count(_board().all_player_units().filter(func(u): return u.coord.x >= 0)).get("Order", 0))) >= 0},
		# Done once a unit is planned and the planner is closed again (it would cover the next step).
		{"title": "Plan your team", "text": "The team planner (open on the right) helps you aim for a team. Click a unit's portrait in it to add it to your plan: planned units get a star and a gold border in the shop, and the planner shows the synergies your plan would make. Then close it with the Planner tab or P.", "enter": func(): _open_right("planner"), "done": func(): return _planned and not _planner_open()},
		{"title": "Equip an item", "text": "Items give stat boosts. Drag the Longsword from the Items tab (open on the left) onto one of your units. A unit holds up to 3 items, and items can't be taken off (outside the tutorial, Tinker's Tongs can).", "enter": func(): _enter_items(false), "done": func(): return _board().all_player_units().any(func(u): return not u.items.is_empty())},
		{"title": "Resonance", "text": "Two items with different elements (the tag by an item's name) on one unit make a resonance. Put this Quick Bow on your Longsword unit to make Flurry.\n\nSee them under RESONANCE in the Items tab (Book lists all 16) and in the inspector.", "enter": func(): _enter_items(true), "done": func(): return _board().all_player_units().any(func(u): return not Resonance.keys_for(u.items).is_empty())},
		{"title": "Sell a unit", "text": "Sell units you don't need for gold: drag one onto the red SELL tile next to the bench, or point at it and press F. You get its cost back, and more for 2-star and 3-star units. Buy a spare unit and sell it now.", "enter": func(): _sold = false, "done": func(): return _sold},
		{"title": "Lock the shop", "text": "Like these offers but can't afford them yet? Click Lock (next to Reroll) to keep them for the next round. While locked, Reroll is greyed out. Lock the shop now, then click it again to unlock.", "enter": func(): _saw_lock = false, "done": func(): return _saw_lock and not GameState.me.shop_locked},
		{"title": "Interest", "text": "Saved gold earns interest: +1 gold each round for every 10 you keep, up to +5 at 50. Bank gold when you can instead of spending it all.\n\nHover your gold (bottom left) to see next round's income.", "next": true},
		{"title": "Level up", "text": "Buy XP (4 gold, in the shop bar) to level up. Higher levels let you field more units and find stronger ones in the shop.", "enter": func(): _level_at_step = GameState.me.level, "done": func(): return GameState.me.level > _level_at_step},
		{"title": "Shop odds", "text": "The strip above the shop shows the chance of each cost (1 to 5 gold) in every shop slot at your level. Each level up moves the odds toward costlier, stronger units: at level 1 the shop only has 1-cost units.", "enter": func(): _open_odds(), "next": true},
		{"title": "Win the last wave", "text": "That's everything! Fight through the remaining waves. The tutorial ends when you beat the final wave. Press Start fight when you're ready.", "last": true},
	]

func _process(delta):
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	_process_inspector()
	var s: Dictionary = _steps[step]
	if s.has("done") and s.done.call():
		_advance()
	_update_buttons()

# Next is greyed out until a step's next_when is true. Start fight shows during prep once a unit
# has been placed, except on steps waiting for Next.
func _update_buttons():
	var s: Dictionary = _steps[step]
	next_button.disabled = s.has("next_when") and not s.next_when.call()
	next_button.tooltip_text = Tip.wrap("After the fight.") if next_button.disabled else ""
	next_button.modulate.a = 0.45 if next_button.disabled else 1.0   # primary buttons look the same when disabled
	var gm = _gm()
	fight_button.visible = gm != null and gm.phase == Events.Phase.PREP and step >= _start_step and not gm.game_over and not next_button.visible

func _advance():
	if step + 1 < _steps.size():
		_enter_step(step + 1)

func _enter_step(i: int):
	step = i
	var s: Dictionary = _steps[i]
	progress_label.text = "%d / %d" % [i + 1, _steps.size()]
	progress_bar.segments = _steps.size()
	progress_bar.set_ratio(float(i + 1) / _steps.size())
	title_label.text = s.title
	body_label.text = s.text
	next_button.visible = s.get("next", false)
	if s.has("enter"):
		s.enter.call()
	Telemetry.tutorial_step(i, s.title)   # the tutorial funnel on the stats page
	if fight_button != null:
		_update_buttons()

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

func _star_count() -> int:
	return _board().all_player_units().filter(func(u): return u.star >= 2).size()

# The merge step: a merge made during it moves on. If one was made earlier, the step says so and waits for Next.
func _enter_merge() -> void:
	_stars_at_step = _star_count()
	if _stars_at_step > 0:
		body_label.text += "\n\nYou've already merged one, so click Next."
		next_button.visible = true

func _enter_items(bow: bool) -> void:
	if bow:
		_give_resonance_item()
	else:
		_give_item()
	_open_left("items")

# Opens a panel of the right box (damage, planner) without changing the saved choice of panel.
func _open_right(p: String) -> void:
	if p == "planner":
		_planned = false
	var dock = get_tree().get_first_node_in_group("right_dock")
	if dock != null:
		dock._show(p)

# Unfolds the left box on a tab (synergies, items) without changing the saved dock layout.
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
