# tutorial.gd
extends HudPlate

# Step-by-step guide shown only in the tutorial level (CampaignLevel id "tutorial", started from
# the main menu's Tutorial button). Each step explains one mechanic and moves on by itself once the
# player has done it (checked a few times a second). Start fight ends prep early, so nobody has to
# race the prep timer while reading.
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
	_enter_step(0)

func _build_steps():
	_steps = [
		{"title": "Welcome!", "text": "This short tutorial teaches the basics. Most steps move on by themselves once you've done them; the others wait for Next.\n\nYour units fight automatically. Your job is to build the strongest team between fights.", "next": true},
		{"title": "Buy a unit", "text": "The shop is at the bottom. Click a unit to buy it (its cost is under the name). Bought units go to your bench, the row of blue tiles.", "done": func(): return _board().all_player_units().size() >= 1},
		{"title": "Place it on the board", "text": "Drag the unit from the bench onto one of the glowing tiles of your half of the board (the bottom half). Your level decides how many units you can field: see \"Units\" above the shop.", "done": func(): return _board().units_on_board() >= 1},
		{"title": "Start the fight", "text": "Fights start when the prep timer runs out. In the tutorial you can press Start fight whenever you're ready.", "done": func(): return _gm().phase == Events.Phase.COMBAT},
		# Waits for Next (enabled once the fight is over), so a quick win doesn't skip the explanation.
		{"title": "Watch the fight", "text": "Units walk to the nearest enemy and attack. The Damage window (top right) shows who did the most. Losing a fight costs HP (the You row, top right); winning gives +1 gold.\n\nClick Next once the fight is over.", "next": true, "next_when": func(): return _gm().phase == Events.Phase.PREP and GameState.round_number >= 2},
		{"title": "Merge three into a star", "text": "Three copies of the same unit merge into a stronger 2-star unit. Buy Knights until you have three (the shop only sells Knights and Militia here).", "done": func(): return _board().all_player_units().any(func(u): return u.star >= 2)},
		{"title": "Synergies", "text": "Units share traits like Order or Warrior. With enough different units of one trait on the board, the whole group gets a bonus. Put a Knight and a Militia on the board together to activate Order (see the top left).", "done": func(): return Synergies.active_tier("Order", int(Synergies.count(_board().all_player_units().filter(func(u): return u.coord.x >= 0)).get("Order", 0))) >= 0},
		# Done once a unit is planned and the planner is closed again (it would cover the next step).
		{"title": "Plan your team", "text": "The team planner helps you aim for a team. Open it with Planner (top right) or press P, and click a unit to add it to your plan: planned units get a star and a gold border in the shop, and the planner shows the synergies your plan would make. Then close it (P or the Planner tab).", "enter": func(): _planned = false, "done": func(): return _planned and not _planner_open()},
		{"title": "Equip an item", "text": "Items give stat boosts. Drag the item from the Items tab (top left) onto one of your units. A unit holds up to 3 items, and items can't be taken off.", "enter": func(): _give_item(), "done": func(): return _board().all_player_units().any(func(u): return not u.items.is_empty())},
		{"title": "Resonance", "text": "Two items with different elements (the tag by an item's name) on one unit make a resonance. Put this Quick Bow on your Longsword unit to make Flurry.\n\nSee them under RESONANCE in the Items tab (Book lists all 16) and in the inspector.", "enter": func(): _give_resonance_item(), "done": func(): return _board().all_player_units().any(func(u): return not Resonance.keys_for(u.items).is_empty())},
		{"title": "Sell a unit", "text": "Sell units you don't need for gold: drag one onto the red SELL tile next to the bench, or point at it and press F. You get its cost back, and more for 2-star and 3-star units. Buy a spare unit and sell it now.", "enter": func(): _sold = false, "done": func(): return _sold},
		{"title": "Lock the shop", "text": "Like these offers but can't afford them yet? Click Lock (next to Reroll) to keep them for the next round. While locked, Reroll is greyed out. Lock the shop now, then click it again to unlock.", "enter": func(): _saw_lock = false, "done": func(): return _saw_lock and not GameState.me.shop_locked},
		{"title": "Interest", "text": "Saved gold earns interest: +1 gold each round for every 10 you keep, up to +5 at 50. Bank gold when you can instead of spending it all.\n\nHover your gold (bottom left) to see next round's income.", "next": true},
		{"title": "Level up", "text": "Buy XP (4 gold, in the shop bar) to level up. Higher levels let you field more units and find stronger ones in the shop.", "enter": func(): _level_at_step = GameState.me.level, "done": func(): return GameState.me.level > _level_at_step},
		{"title": "Win the last wave", "text": "That's everything! Fight through the remaining waves. A level is won by beating its final wave. Press Start fight when you're ready.", "last": true},
	]

func _process(delta):
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
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
	fight_button.visible = gm != null and gm.phase == Events.Phase.PREP and step >= 3 and not gm.game_over and not next_button.visible

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
	if fight_button != null:
		_update_buttons()

# The items step hands out a Longsword if the player has no item to practise with.
func _give_item():
	if not GameState.me.items.is_empty() or _board().all_player_units().any(func(u): return not u.items.is_empty()):
		return
	GameState.me.items.append(load("res://tres/items/longsword.tres"))
	Events.items_changed.emit()

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
	GameState.me.items.append(load("res://tres/items/quick_bow.tres"))
	Events.items_changed.emit()
