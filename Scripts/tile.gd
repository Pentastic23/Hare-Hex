# tile.gd
class_name Tile extends StaticBody3D

var coord: Vector2i
var occupant: Unit = null
var unlocked := true
var _tw: Tween

const RISE_DEPTH := 0.7    # a rising tile starts this far under the ground
const RISE_OVER := 0.45    # and shoots this far over its place before it drops in
const RISE_UP := 0.22      # seconds to rise
const RISE_DROP := 0.32    # seconds to fall into place (with a little bounce)

# `rise`: instead of the pop, the tile rises out of the ground after `delay` seconds, overshoots and falls
# into place (the enemy half's tiles, staggered row by row: Board.refresh_unlocks' waterfall).
func set_unlocked(v: bool, animate := true, delay := 0.0, rise := false):
	if v:
		if unlocked and visible:
			return
		unlocked = true
		visible = true
		if _tw != null:
			_tw.kill()
		position.y = 0.0
		if animate and not Settings.reduce_motion:   # Reduce motion: tiles appear without the pop
			_tw = create_tween()
			if rise:
				scale = Vector3.ONE
				position.y = -RISE_DEPTH
				if delay > 0.0:
					_tw.tween_interval(delay)
				_tw.tween_property(self, "position:y", RISE_OVER, RISE_UP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				_tw.tween_property(self, "position:y", 0.0, RISE_DROP).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			else:
				scale = Vector3.ONE * 0.01
				_tw.tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			scale = Vector3.ONE
	else:
		unlocked = false
		visible = false
		if _tw != null:
			_tw.kill()
			_tw = null
		position.y = 0.0
		scale = Vector3.ONE
