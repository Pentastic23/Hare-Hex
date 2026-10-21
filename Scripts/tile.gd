# tile.gd
class_name Tile extends StaticBody3D

var coord: Vector2i
var occupant: Unit = null
var unlocked := true

func set_unlocked(v: bool, animate := true):
	if v:
		if unlocked and visible:
			return
		unlocked = true
		visible = true
		if animate:
			scale = Vector3.ONE * 0.01
			var t := create_tween()
			t.tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			scale = Vector3.ONE
	else:
		unlocked = false
		visible = false
