# shop_panel.gd
extends PanelContainer

@onready var slots: Array = $HBoxContainer.get_children().filter(func(n): return n is ShopSlot)
var lock_button: Button

func _ready():
	# The Lock button sits right after Reroll. (The team planner opens from the top-right bar.)
	lock_button = _small_button("Lock", "Keep these offers for the next round. While locked you can't reroll.")
	lock_button.toggle_mode = true
	lock_button.toggled.connect(func(on):
		var gm := get_tree().get_first_node_in_group("game_manager")
		if gm != null:
			gm.set_shop_locked(on))
	Events.shop_lock_changed.connect(_on_lock_changed)
	$HBoxContainer.add_child(lock_button)
	$HBoxContainer.move_child(lock_button, $HBoxContainer/RerollButton.get_index() + 1)

	Events.shop_rolled.connect(_on_shop_rolled)
	$HBoxContainer/RerollButton.pressed.connect(func(): Events.reroll_pressed.emit())
	$HBoxContainer/BuyXPButton.pressed.connect(func(): Events.buy_xp_pressed.emit())
	$HBoxContainer/RerollButton.text = "Reroll\n2g"
	$HBoxContainer/BuyXPButton.text = "Buy XP\n4g"
	$HBoxContainer/RerollButton.custom_minimum_size = Vector2(100, 60)
	$HBoxContainer/BuyXPButton.custom_minimum_size = Vector2(100, 60)
	for s in slots:
		s.custom_minimum_size = Vector2(110, 60)

func _on_lock_changed(on: bool):
	lock_button.set_pressed_no_signal(on)
	lock_button.text = "Locked" if on else "Lock"
	lock_button.modulate = Color(1.0, 0.85, 0.3) if on else Color.WHITE
	# A locked shop can't be rerolled; unlocking and rerolling replaces all five offers.
	var reroll: Button = $HBoxContainer/RerollButton
	reroll.disabled = on
	reroll.tooltip_text = Tip.wrap("Unlock the shop to reroll.") if on else ""

func _small_button(label: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = Tip.wrap(tip)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(72, 60)
	b.add_theme_font_size_override("font_size", 15)
	return b

func _on_shop_rolled(offers: Array):
	for i in slots.size():
		if i < offers.size():
			slots[i].show_offer(offers[i])
		else:
			slots[i].clear_offer()   # pool ran dry; don't leave last roll's offer up
