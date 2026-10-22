# board_label.gd
extends Label

var board: Board

func _ready():
	board = get_tree().get_first_node_in_group("board") as Board
	Events.board_limit_hit.connect(_flash)

func _process(_delta):
	_refresh()   # cheap; keeps the count right after every drag, buy and level-up

func _refresh():
	if board == null: return
	text = "Units: %d/%d" % [board.units_on_board(), GameState.me.max_board_units()]
	if not _flashing:
		modulate = Color.WHITE

var _flashing := false
func _flash():
	_flashing = true
	modulate = Color(1, 0.3, 0.3)
	await get_tree().create_timer(0.6).timeout
	_flashing = false
