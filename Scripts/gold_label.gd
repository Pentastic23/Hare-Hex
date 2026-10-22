# gold_label.gd
extends Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP   # labels ignore the mouse by default
	Events.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(GameState.me.gold)
	custom_minimum_size = Vector2(110, 32)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _on_gold_changed(amount: int):
	text = "Gold: %d" % amount

func _get_tooltip(_at_position: Vector2) -> String:
	var next_round: int = GameState.round_number + 1
	var base: int = GameState.base_income_for_round(next_round)
	var interest: int = GameState.me.interest_gold()
	var streak: int = GameState.me.streak_bonus()
	return Tip.wrap("Next round income\nBase: %d\nInterest: %d\nStreak: %d\nTotal: %d" % [
		base, interest, streak, base + interest + streak])
