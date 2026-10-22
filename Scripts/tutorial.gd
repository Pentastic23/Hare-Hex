# tutorial.gd
extends PanelContainer

# Step-by-step guide shown only in the tutorial level (CampaignLevel id "tutorial", started from
# the main menu's Tutorial button). Each step explains one mechanic and moves on by itself once the
# player has done it (checked a few times a second). Start fight ends prep early, so nobody has to
# race the prep timer while reading.

const TUTORIAL_ID := &"tutorial"
const LEVEL_PATH := "res://tres/campaign/tutorial.tres"
const GOLD := Color(1.0, 0.85, 0.3)

var step := 0
var title_label: Label
var body_label: Label
var progress_label: Label
var next_button: Button
var fight_button: Button
var _timer := 0.0
var _level_at_step := 1
var _sold := false       # a unit was sold since the sell step began
var _saw_lock := false   # the shop was locked since the lock step began
var _steps: Array[Dictionary] = []

static func is_tutorial_run() -> bool:
	return GameState.run_level != null and GameState.run_level.id == TUTORIAL_ID

func _ready():
	add_to_group("tutorial")
	visible = is_tutorial_run()
	set_process(visible)
	if not visible:
		return
	custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	progress_label = _label(14, Color(0.65, 0.65, 0.7))
	box.add_child(progress_label)
	title_label = _label(20, GOLD)
	box.add_child(title_label)
	body_label = _label(15, Color.WHITE)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(280, 0)
	box.add_child(body_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
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
	_build_steps()
	_enter_step(0)

func _build_steps():
	_steps = [
		{"title": "Welcome!", "text": "This short tutorial teaches the basics. Most steps move on by themselves once you've done them; the others wait for Next.\n\nYour units fight automatically. Your job is to build the strongest team between fights.", "next": true},
		{"title": "Buy a unit", "text": "The shop is at the bottom. Click a unit to buy it (its cost is under the name). Bought units go to your bench, the row of blue tiles.", "done": func(): return _board().all_player_units().size() >= 1},
		{"title": "Place it on the board", "text": "Drag the unit from the bench onto one of the glowing tiles of your half of the board (the bottom half). Your level decides how many units you can field: see \"Units\" above the shop.", "done": func(): return _board().units_on_board() >= 1},
		{"title": "Start the fight", "text": "Fights start when the prep timer runs out. In the tutorial you can press Start fight whenever you're ready.", "done": func(): return _gm().phase == Events.Phase.COMBAT},
		# Waits for Next (enabled once the fight is over), so a quick win doesn't skip the explanation.
		{"title": "Watch the fight", "text": "Units walk to the nearest enemy and attack. The Damage window (top right) shows who did the most. Losing a fight costs HP (bottom right); winning gives +1 gold.\n\nClick Next once the fight is over.", "next": true, "next_when": func(): return _gm().phase == Events.Phase.PREP and GameState.round_number >= 2},
		{"title": "Merge three into a star", "text": "Three copies of the same unit merge into a stronger 2-star unit. Buy Knights until you have three (the shop only sells Knights and Clerics here).", "done": func(): return _board().all_player_units().any(func(u): return u.star >= 2)},
		{"title": "Synergies", "text": "Units share traits like Order or Warrior. With enough different units of one trait on the board, the whole group gets a bonus. Put a Knight and a Cleric on the board together to activate Order (see the top left).", "done": func(): return Synergies.active_tier("Order", int(Synergies.count(_board().all_player_units().filter(func(u): return u.coord.x >= 0)).get("Order", 0))) >= 0},
		{"title": "Equip an item", "text": "Items give stat boosts. Drag the item from the item bar (left) onto one of your units. A unit holds up to 3 items, and items can't be taken off.", "enter": func(): _give_item(), "done": func(): return _board().all_player_units().any(func(u): return not u.items.is_empty())},
		{"title": "Sell a unit", "text": "Sell units you don't need for gold: drag one onto the red SELL tile next to the bench, or point at it and press F. You get its cost back, and more for 2-star and 3-star units. Buy a spare unit and sell it now.", "enter": func(): _sold = false, "done": func(): return _sold},
		{"title": "Lock the shop", "text": "Like these offers but can't afford them yet? Click Lock (next to Reroll) to keep them for the next round. While locked, Reroll is greyed out. Lock the shop now, then click it again to unlock.", "enter": func(): _saw_lock = false, "done": func(): return _saw_lock and not GameState.me.shop_locked},
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
	next_button.tooltip_text = "After the fight." if next_button.disabled else ""
	var gm = _gm()
	fight_button.visible = gm != null and gm.phase == Events.Phase.PREP and step >= 3 and not gm.game_over and not next_button.visible

func _advance():
	if step + 1 < _steps.size():
		_enter_step(step + 1)

func _enter_step(i: int):
	step = i
	var s: Dictionary = _steps[i]
	progress_label.text = "Tutorial  %d / %d" % [i + 1, _steps.size()]
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

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 36)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
