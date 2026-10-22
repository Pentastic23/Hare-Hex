# shop_slot.gd
class_name ShopSlot extends Button

var offer: UnitData
static var _planned_style: StyleBoxFlat   # gold border for units in the team plan

func _ready():
	Events.team_plan_changed.connect(_update_text)

func show_offer(d: UnitData):
	offer = d
	disabled = false
	_update_text()

func clear_offer():
	offer = null
	text = ""
	disabled = true
	_update_text()

# Units in the team plan get a star and a gold border.
func _update_text():
	var planned := offer != null and SaveGame.team_plan().has(offer.display_name)
	if offer != null:
		text = "%s%s\n%d g" % ["* " if planned else "", offer.display_name, offer.cost]
	if planned:
		if _planned_style == null:
			_planned_style = StyleBoxFlat.new()
			_planned_style.bg_color = Color(0.25, 0.22, 0.1)
			_planned_style.border_color = Color(1.0, 0.85, 0.3)
			_planned_style.set_border_width_all(3)
			_planned_style.set_corner_radius_all(4)
		add_theme_stylebox_override("normal", _planned_style)
		add_theme_stylebox_override("hover", _planned_style)
	else:
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("hover")

func _pressed():
	if offer == null:
		return
	if GameState.gold < offer.cost:
		_flash("Not enough\ngold")
		return
	var gm := get_tree().get_first_node_in_group("game_manager")
	var in_prep: bool = gm == null or gm.phase == Events.Phase.PREP
	var board := get_tree().get_first_node_in_group("board") as Board
	# During combat a purchase must land on the bench, so completing a merge doesn't help.
	if board != null and board.first_free_bench() == -1 and not (in_prep and board.would_complete_merge(offer)):
		_flash("Bench full")
		return
	Events.unit_bought.emit(offer)
	clear_offer()   # also forgets the offer, so a team plan change can't bring its name back

func _flash(msg: String):
	var original := text
	text = msg
	await get_tree().create_timer(0.8).timeout
	if text == msg:   # only restore if nothing else changed it meanwhile
		text = original
