# screen_filter.gd
extends CanvasLayer

# Autoload ScreenFilter: the colour-blind filter (Settings.colorblind). A full-screen rect on top of
# everything runs a daltonize shader (tres/colorblind.gdshader): it simulates how the chosen colour
# vision deficiency sees the frame and shifts the lost difference into colours that still read, so
# reds and greens (team rings, health bars, the HP standings) stay apart. Hidden when the filter is
# off, and it never takes the mouse.

const SHADER := preload("res://tres/colorblind.gdshader")

var rect: ColorRect

func _ready():
	layer = 128   # above every HUD layer
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	add_child(rect)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.ensure_loaded()
	refresh()

func refresh() -> void:
	if rect == null:
		return
	var mode := Settings.COLORBLIND_MODES.find(Settings.colorblind)
	rect.visible = mode > 0
	(rect.material as ShaderMaterial).set_shader_parameter("mode", maxi(mode, 0))
