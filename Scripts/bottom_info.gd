extends VBoxContainer

func _ready():
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -84
	mouse_filter = Control.MOUSE_FILTER_IGNORE
