# keybinds.gd
class_name Keybinds extends RefCounted

# Rebindable controls, shown and edited in the main menu (Keybinds). Static, like Settings; stored in
# user://keybinds.cfg (separate from settings.cfg so the two never overwrite each other).
#
# Keyboard: each action is an InputMap action (created here on first use), so scripts test it with
# Keybinds.pressed(event, "sell_unit"). Controller: each action is one pad button, read by
# gamepad_controls.gd through Keybinds.pad_action(button).
# Fixed (shown, not rebindable): the mouse, Esc (menu / back: never rebindable, so you can't lock
# yourself out of the menu), the sticks and the triggers.

const DEFAULT_PATH := "user://keybinds.cfg"

# id -> [label, default key, extra default keys]
const KEYS := {
	"sell_unit":    ["Sell unit (under the pointer, or the one you drag)", KEY_F, []],
	"buy_xp":       ["Buy XP", KEY_E, []],
	"reroll":       ["Reroll the shop", KEY_D, []],
	"lock_shop":    ["Lock / unlock the shop", KEY_L, []],
	"team_planner": ["Team planner", KEY_P, []],
	"zoom_in":      ["Zoom in", KEY_EQUAL, [KEY_KP_ADD]],
	"zoom_out":     ["Zoom out", KEY_MINUS, [KEY_KP_SUBTRACT]],
	"reset_view":   ["Reset the view", KEY_HOME, []],
	"scout_home":   ["Back to your own board (after scouting in a lobby)", KEY_SPACE, []],
}
const KEY_ORDER := ["sell_unit", "buy_xp", "reroll", "lock_shop", "team_planner", "zoom_in", "zoom_out", "reset_view", "scout_home"]

# id -> [label, default pad button]
const PAD := {
	"click":        ["Select (hold to drag)", JOY_BUTTON_A],
	"inspect":      ["Inspect unit", JOY_BUTTON_X],
	"sell_unit":    ["Sell unit", JOY_BUTTON_Y],
	"back":         ["Back", JOY_BUTTON_B],
	"menu":         ["Menu", JOY_BUTTON_START],
	"team_planner": ["Team planner", JOY_BUTTON_BACK],
	"buy_xp":       ["Buy XP", JOY_BUTTON_LEFT_SHOULDER],
	"reroll":       ["Reroll the shop", JOY_BUTTON_RIGHT_SHOULDER],
	"lock_shop":    ["Lock / unlock the shop", JOY_BUTTON_LEFT_STICK],
	"reset_view":   ["Reset the view", JOY_BUTTON_RIGHT_STICK],
}
const PAD_ORDER := ["click", "inspect", "sell_unit", "back", "menu", "team_planner", "buy_xp", "reroll", "lock_shop", "reset_view"]

const FIXED_KEYS := [["Left mouse", "Select, drag units and items, pan the view"], ["Right mouse", "Inspect a unit"],
	["Mouse wheel", "Zoom"], ["Esc", "Menu / back"]]
const FIXED_PAD := [["Left stick", "Move the pointer"], ["D-pad", "Move the pointer slowly"],
	["Right stick", "Pan the view"], ["LT / RT", "Zoom out / in"]]

static var path := DEFAULT_PATH   # tests point this elsewhere
static var keys := {}     # id -> Key (the main binding; the extra defaults stay unless it's rebound)
static var pad := {}      # id -> JoyButton
static var _loaded := false

static func ensure() -> void:
	if not _loaded:
		load_binds()

static func load_binds() -> void:
	_loaded = true
	keys.clear()
	pad.clear()
	for id in KEYS:
		keys[id] = KEYS[id][1]
	for id in PAD:
		pad[id] = PAD[id][1]
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		for id in KEYS:
			keys[id] = int(cfg.get_value("keyboard", id, keys[id]))
		for id in PAD:
			pad[id] = int(cfg.get_value("controller", id, pad[id]))
	_apply()

static func save_binds() -> void:
	var cfg := ConfigFile.new()
	for id in keys:
		cfg.set_value("keyboard", id, keys[id])
	for id in pad:
		cfg.set_value("controller", id, pad[id])
	var err := cfg.save(path)
	if err != OK:
		push_warning("Keybinds: can't write %s (%s)" % [path, error_string(err)])

static func reset_defaults() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	load_binds()

# Writes the keyboard binds into the InputMap (one action per id, prefixed "kb_").
static func _apply() -> void:
	for id in KEYS:
		var action: String = "kb_" + str(id)
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		var list: Array = [keys[id]]
		if keys[id] == KEYS[id][1]:
			list.append_array(KEYS[id][2])   # default binding: the keypad variants too
		for k in list:
			var e := InputEventKey.new()
			e.keycode = k
			InputMap.action_add_event(action, e)

# True when `event` is a fresh press of the keyboard action `id`.
static func pressed(event: InputEvent, id: String) -> bool:
	ensure()
	return event is InputEventKey and event.is_action_pressed("kb_" + id, false, true)

# Rebinds keyboard action `id`. A key already used by another action swaps over to it. Esc can't be bound.
static func set_key(id: String, k: Key) -> bool:
	ensure()
	if k == KEY_ESCAPE or not keys.has(id):
		return false
	for other in keys:
		if other != id and keys[other] == k:
			keys[other] = keys[id]
	keys[id] = k
	_apply()
	save_binds()
	return true

# Rebinds controller action `id`, swapping with an action that already uses that button. Not the D-pad.
static func set_pad(id: String, b: JoyButton) -> bool:
	ensure()
	if not pad.has(id) or b in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		return false   # the D-pad moves the pointer
	for other in pad:
		if other != id and pad[other] == b:
			pad[other] = pad[id]
	pad[id] = b
	save_binds()
	return true

# The controller action on `b`, or "" (gamepad_controls.gd).
static func pad_action(b: int) -> String:
	ensure()
	for id in pad:
		if pad[id] == b:
			return id
	return ""

# While the keybinds screen waits for a pad button, gamepad_controls.gd hands the press here instead.
static var pad_capture := Callable()

static func key_name(k: int) -> String:
	var short := {KEY_EQUAL: "=", KEY_MINUS: "-", KEY_KP_ADD: "Num +", KEY_KP_SUBTRACT: "Num -", KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_BACKSLASH: "\\", KEY_QUOTELEFT: "`"}
	if short.has(k):
		return short[k]
	var s := OS.get_keycode_string(k)
	return s if s != "" else "?"

static func pad_name(b: int) -> String:
	match b:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "Back / Select"
		JOY_BUTTON_GUIDE: return "Guide"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-pad up"
		JOY_BUTTON_DPAD_DOWN: return "D-pad down"
		JOY_BUTTON_DPAD_LEFT: return "D-pad left"
		JOY_BUTTON_DPAD_RIGHT: return "D-pad right"
		JOY_BUTTON_MISC1: return "Share"
		JOY_BUTTON_PADDLE1: return "Paddle 1"
		JOY_BUTTON_PADDLE2: return "Paddle 2"
		JOY_BUTTON_PADDLE3: return "Paddle 3"
		JOY_BUTTON_PADDLE4: return "Paddle 4"
		JOY_BUTTON_TOUCHPAD: return "Touchpad"
	return "Button %d" % b

# [button, what it does] for the pause menu's controller list.
static func pad_help() -> Array:
	ensure()
	var out: Array = [["L stick", "Pointer (D-pad: fine)"]]
	for id in PAD_ORDER:
		out.append([pad_name(pad[id]), PAD[id][0]])
	out.append(["LT / RT", "Zoom"])
	out.append(["R stick", "Pan view"])
	return out
