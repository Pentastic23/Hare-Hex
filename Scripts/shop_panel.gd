# shop_panel.gd
extends HudPlate

# The shop bar at the bottom, in the style of the shop mockup in the Art assets folder ("autochess
# ui"; the same images are in textures/ui/shop/): a dark plate holding the level panel (LVL, XP
# progress, gold), Buy XP, Reroll, Lock and five unit cards (shop_slot.gd). Everything is built in
# code; the mockup images have their numbers painted in, so only the silhouettes are used (empty
# slots). Kept from before: Lock keeps the offers into the next round and disables Reroll; Reroll
# and Buy XP emit Events.reroll_pressed / buy_xp_pressed; the gold row's tooltip shows next round's
# income. Node names HBoxContainer/BuyXPButton and HBoxContainer/RerollButton are kept for the
# tutorial and the checks.

const GAP := 6
const XP_PER_BUY := 4      # GameManager._on_buy_xp adds 4 XP
const PANEL := Color("1d2030")
const PANEL_EDGE := Color("2c3249")

var row: HBoxContainer
var slots: Array = []
var lock_button: Button
var buy_xp_button: Button
var reroll_button: Button
var level_label: Label
var xp_label: Label
var xp_bar: Control
var gold_label: Label
var gold_row: HBoxContainer
var _timer := 0.0
var _lock_icon_off: Texture2D
var _lock_icon_on: Texture2D

func _ready():
	setup_plate(4, 6, 6)
	offset_bottom = -6
	row = HBoxContainer.new()
	row.name = "HBoxContainer"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", GAP)
	add_child(row)

	row.add_child(_level_panel())

	buy_xp_button = _panel_button("BuyXPButton", Vector2(88, ShopSlot.H))
	buy_xp_button.add_child(_price_content("BUY XP", _gm_const("BUY_XP_COST", 4), "+%d XP" % XP_PER_BUY))
	buy_xp_button.tooltip_text = Tip.wrap("Buy %d XP for %d gold. Higher levels field more units and find stronger ones." % [XP_PER_BUY, _gm_const("BUY_XP_COST", 4)])
	buy_xp_button.pressed.connect(func(): Events.buy_xp_pressed.emit())
	row.add_child(buy_xp_button)

	reroll_button = _panel_button("RerollButton", Vector2(82, ShopSlot.H))
	reroll_button.add_child(_price_content("REROLL", _gm_const("REROLL_COST", 2), ""))
	reroll_button.pressed.connect(func(): Events.reroll_pressed.emit())
	row.add_child(reroll_button)

	# The Lock button sits right after Reroll.
	_lock_icon_off = DockKit.padlock(HudStyle.MUTED)
	_lock_icon_on = DockKit.padlock(HudStyle.GOLD)
	lock_button = _panel_button("LockButton", Vector2(56, ShopSlot.H))
	lock_button.text = "Lock"
	lock_button.icon = _lock_icon_off
	lock_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	lock_button.add_theme_font_override("font", HudStyle.label_font())
	lock_button.add_theme_font_size_override("font_size", 11)
	lock_button.add_theme_constant_override("h_separation", 6)
	lock_button.toggle_mode = true
	lock_button.tooltip_text = Tip.wrap("Keep these offers for the next round. While locked you can't reroll.")
	lock_button.toggled.connect(func(on):
		var gm := get_tree().get_first_node_in_group("game_manager")
		if gm != null:
			gm.set_shop_locked(on))
	row.add_child(lock_button)

	for i in 5:
		var s := ShopSlot.new()
		s.name = "Slot %d" % (i + 1)
		s.index = i
		row.add_child(s)
		s.clear_offer()
		slots.append(s)

	Events.shop_lock_changed.connect(_on_lock_changed)
	Events.shop_rolled.connect(_on_shop_rolled)
	Events.gold_changed.connect(func(_g): _refresh_stats())
	Events.xp_changed.connect(func(_l, _x, _n): _refresh_stats())
	Events.round_changed.connect(func(_s, _r): _refresh_stats())
	Events.phase_changed.connect(func(_p): _refresh_stats())   # the opening's shut shop opens with round 2
	Events.streak_changed.connect(func(_w, _l): _refresh_stats())
	_on_lock_changed(GameState.me.shop_locked)
	_refresh_stats()
	if not GameState.me.shop_offers.is_empty():
		_on_shop_rolled(GameState.me.shop_offers)

# Shop shortcuts (main menu > Keybinds): Buy XP (E), Reroll (D), Lock (L) by default.
func _unhandled_input(event):
	if not event is InputEventKey or get_tree().paused:
		return
	if Keybinds.pressed(event, "buy_xp"):
		Events.buy_xp_pressed.emit()
	elif Keybinds.pressed(event, "reroll"):
		if not reroll_button.disabled:
			Events.reroll_pressed.emit()
	elif Keybinds.pressed(event, "lock_shop"):
		lock_button.button_pressed = not lock_button.button_pressed
	else:
		return
	get_viewport().set_input_as_handled()

func _process(delta):
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.3
	for s in slots:
		s.refresh_owned()   # pips follow buys, sells and merges
	_refresh_affordable()

func _gm_const(n: String, fallback: int) -> int:
	var gm := get_tree().get_first_node_in_group("game_manager")
	return int(gm.get(n)) if gm != null and gm.get(n) != null else fallback

# LVL 5 (8/20), a segmented XP bar, and your gold under it.
func _level_panel() -> Control:
	var p := PanelContainer.new()
	p.name = "LevelPanel"
	p.custom_minimum_size = Vector2(108, ShopSlot.H)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _panel_box(PANEL, Vector4(5, 8, 5, 8)))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 5)
	v.add_child(top)
	level_label = HudStyle.number(20, HudStyle.INK)
	top.add_child(level_label)
	xp_label = HudStyle.number(13, HudStyle.MUTED)
	xp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(xp_label)
	xp_bar = DockKit.SegBar.new(6, 4)
	v.add_child(xp_bar)
	gold_row = HBoxContainer.new()
	gold_row.mouse_filter = Control.MOUSE_FILTER_STOP   # for the income tooltip
	gold_row.add_theme_constant_override("separation", 6)
	v.add_child(gold_row)
	gold_row.add_child(DockKit.Coin.new(14))
	gold_label = HudStyle.number(22, HudStyle.INK)
	gold_row.add_child(gold_label)
	return p

# Caption, price with a coin, and an optional note (Buy XP and Reroll).
func _price_content(caption: String, price: int, note: String) -> Control:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	var cap := HudStyle.caps(10, HudStyle.MUTED)
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 5)
	v.add_child(h)
	var num := HudStyle.number(22, HudStyle.INK)
	num.name = "Price"
	num.text = str(price)
	h.add_child(num)
	h.add_child(DockKit.Coin.new(13))
	if note != "":
		var n := DockKit.text(10, HudStyle.MUTED)
		n.text = note
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
	return v

func _panel_box(bg: Color, pad := Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := DockKit.flat(bg, 3, pad)
	s.set_border_width_all(1)
	s.border_color = PANEL_EDGE
	return s

func _panel_button(n: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.name = n
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_panel_button(b, false)
	return b

func _style_panel_button(b: Button, gold: bool) -> void:
	var n := _panel_box(PANEL)
	if gold:
		n.set_border_width_all(2)
		n.border_color = HudStyle.GOLD
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = PANEL.lightened(0.06)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = DockKit.WELL
	var d := n.duplicate() as StyleBoxFlat
	d.bg_color = PANEL.darkened(0.3)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p if not gold else n)
	b.add_theme_stylebox_override("hover_pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", DockKit.empty_box())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, HudStyle.GOLD if gold else HudStyle.MUTED)
	b.add_theme_color_override("font_disabled_color", DockKit.DIM_TEXT)

func _refresh_stats() -> void:
	if level_label == null:
		return
	var me := GameState.me
	level_label.text = "LVL %d" % me.level
	if GameState.XP_TABLE.has(me.level):
		xp_label.text = "(%d/%d)" % [me.xp, me.xp_needed()]
		xp_bar.set_steps(me.xp, me.xp_needed(), XP_PER_BUY)   # one segment per Buy XP (4 XP)
	else:
		xp_label.text = "MAX"
		xp_bar.set_steps(1.0, 1.0, 1.0)
	gold_label.text = str(me.gold)
	var next_round: int = GameState.round_number + 1
	var base: int = GameState.base_income_for_round(next_round)
	var interest: int = me.interest_gold()
	var streak: int = me.streak_bonus()
	var gm = get_tree().get_first_node_in_group("game_manager")
	var purse: int = gm.item_income() if gm != null else 0   # Coin Purses on the board (items v2)
	var lines := "Next round income\nBase: %d\nInterest: %d (max %d)\nStreak: %d" % [base, interest, KingPowers.interest_cap(me), streak]
	if purse > 0:
		lines += "\nCoin Purse: %d" % purse
	gold_row.tooltip_text = Tip.wrap(lines + "\nTotal: %d" % (base + interest + streak + purse))
	var free := me.free_rerolls > 0   # Merchant's Ledger: this reroll costs nothing
	var price_l := reroll_button.find_child("Price", true, false) as Label
	if price_l != null:
		price_l.text = "0" if free else str(_gm_const("REROLL_COST", 2))
		price_l.add_theme_color_override("font_color", HudStyle.GOLD if free else HudStyle.INK)
	_style_panel_button(reroll_button, free and not me.shop_locked)   # a gold edge while a reroll is free (Merchant's Ledger)
	if not me.shop_locked:
		reroll_button.tooltip_text = Tip.wrap("Free reroll (Merchant's Ledger): %d saved up." % me.free_rerolls) if free else Tip.wrap("New offers for %d gold." % _gm_const("REROLL_COST", 2))
	_refresh_affordable()

# Buy XP and Reroll dim when you can't pay for them (they stay clickable; the game ignores it), and in the
# PvP opening, when the shop is shut.
func _refresh_affordable() -> void:
	var g := GameState.me.gold
	var shut := GameState.me.opening
	var maxed := GameState.me.is_max_level()   # level 10: nothing to buy, so greyed out and switched off
	buy_xp_button.disabled = maxed
	buy_xp_button.tooltip_text = Tip.wrap("You are at the highest level.") if maxed else Tip.wrap("Buy %d XP for %d gold. Higher levels field more units and find stronger ones." % [XP_PER_BUY, _gm_const("BUY_XP_COST", 4)])
	buy_xp_button.modulate.a = 1.0 if g >= _gm_const("BUY_XP_COST", 4) and not shut and not maxed else 0.55
	reroll_button.modulate.a = 1.0 if (g >= _gm_const("REROLL_COST", 2) or GameState.me.free_rerolls > 0 or reroll_button.disabled) and not shut else 0.55

func _on_lock_changed(on: bool):
	lock_button.set_pressed_no_signal(on)
	lock_button.text = "Locked" if on else "Lock"
	lock_button.icon = _lock_icon_on if on else _lock_icon_off
	_style_panel_button(lock_button, on)
	# A locked shop can't be rerolled; unlocking and rerolling replaces all five offers.
	reroll_button.disabled = on
	reroll_button.tooltip_text = Tip.wrap("Unlock the shop to reroll.") if on else Tip.wrap("New offers for %d gold." % _gm_const("REROLL_COST", 2))
	_refresh_affordable()

func _on_shop_rolled(offers: Array):
	for i in slots.size():
		if i < offers.size() and offers[i] != null:
			slots[i].show_offer(offers[i])
		else:
			slots[i].clear_offer()   # pool ran dry; don't leave last roll's offer up
