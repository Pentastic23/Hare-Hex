# shop_slot.gd
class_name ShopSlot extends Button

var offer: UnitData

func show_offer(d: UnitData):
	offer = d
	text = "%s\n%d g" % [d.display_name, d.cost]
	disabled = false

func clear_offer():
	offer = null
	text = ""
	disabled = true

func _pressed():
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.phase != Events.Phase.PREP:
		_flash("Fighting...")
		return
	if offer == null:
		return
	if GameState.gold < offer.cost:
		_flash("Not enough\ngold")
		return
	var board := get_tree().get_first_node_in_group("board") as Board
	if board != null and board.first_free_bench() == -1 and not board.would_complete_merge(offer):
		_flash("Bench full")
		return
	Events.unit_bought.emit(offer)
	disabled = true
	text = ""

func _flash(msg: String):
	var original := text
	text = msg
	await get_tree().create_timer(0.8).timeout
	if text == msg:   # only restore if nothing else changed it meanwhile
		text = original
