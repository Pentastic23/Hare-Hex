# shop_panel.gd
extends PanelContainer

@onready var slots: Array = $HBoxContainer.get_children().filter(func(n): return n is ShopSlot)

func _ready():
	Events.shop_rolled.connect(_on_shop_rolled)
	$HBoxContainer/RerollButton.pressed.connect(func(): Events.reroll_pressed.emit())
	$HBoxContainer/BuyXPButton.pressed.connect(func(): Events.buy_xp_pressed.emit())
	$HBoxContainer/RerollButton.text = "Reroll\n2g"
	$HBoxContainer/BuyXPButton.text = "Buy XP\n4g"
	$HBoxContainer/RerollButton.custom_minimum_size = Vector2(100, 60)
	$HBoxContainer/BuyXPButton.custom_minimum_size = Vector2(100, 60)
	for s in slots:
		s.custom_minimum_size = Vector2(110, 60)

func _on_shop_rolled(offers: Array):
	for i in slots.size():
		if i < offers.size():
			slots[i].show_offer(offers[i])
