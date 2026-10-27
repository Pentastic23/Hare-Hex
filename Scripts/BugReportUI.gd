# BugReportUI.gd
extends CanvasLayer

# Autoload BugReporter (scenes/BugReportUI.tscn): a small "BUG" button in the bottom-left corner, on
# the menu and in a run. It folds out a report panel (title, your name, severity, what happened,
# optional game info and screenshot) that posts to a Discord webhook. Built in code in the HUD look
# (HudPlate, DockKit). The webhook URL is a secret, so it isn't in the code: it is read from
# WEBHOOK_FILE, which git ignores (exports need "bug_report_webhook.txt" in the export filter).
# While the panel is open, typing never reaches the game's hotkeys (DragController and RightDock
# check `is_open`), and Esc closes the panel first.

const WEBHOOK_FILE := "res://bug_report_webhook.txt"
var name_cfg := "user://bug_report.cfg"   # remembers the tester's name (tests point it elsewhere)
const SEVERITIES := ["Critical", "High", "Medium", "Low", "Cosmetic", "Suggestion"]
const SEVERITY_COLORS := [0xe03131, 0xff8a4c, 0xf2c14e, 0x6cc4ff, 0xa9aec4, 0x7bd88f]
const COOLDOWN := 10.0          # seconds between reports, so a stuck key can't flood the channel
const SHOT_WIDTH := 960         # screenshots are scaled down to this width
const MAX_DESCRIPTION := 3500   # Discord allows 4096 in an embed description
const PANEL_W := 340.0

var is_open := false
var sending := false
var url_override := ""          # tests point this somewhere harmless; "" = the webhook file
var _cooldown_left := 0.0
var _shot: PackedByteArray = [] # taken the moment the panel opens, before it covers the screen

var root: Control
var toggle: Button
var panel: HudPlate
var title_edit: LineEdit
var name_edit: LineEdit
var severity: OptionButton
var description: TextEdit
var info_check: CheckBox
var shot_check: CheckBox
var send_button: Button
var status_label: Label
@onready var http: HTTPRequest = $HTTPRequest

func _ready():
	layer = 100   # over the HUD, under the colour-blind filter (128)
	process_mode = Node.PROCESS_MODE_ALWAYS   # usable while the pause menu is open
	_build()
	http.request_completed.connect(_on_request_completed)
	http.timeout = 20.0

func _process(delta):
	_cooldown_left = maxf(0.0, _cooldown_left - delta)

# --- the panel ---------------------------------------------------------------------------------

func _build():
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	toggle = DockKit.secondary_button("BUG")
	toggle.name = "BugToggle"
	toggle.custom_minimum_size = Vector2(52, 26)
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.tooltip_text = Tip.wrap("Report a bug: what happened, with a screenshot. Goes straight to the developers.")
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	toggle.offset_left = 8
	toggle.offset_bottom = -92   # clear of the shop bar's top-left corner
	toggle.offset_top = -118
	toggle.offset_right = 60
	toggle.pressed.connect(toggle_panel)
	root.add_child(toggle)

	panel = HudPlate.new()
	panel.name = "BugPanel"
	panel.setup_plate(12, 14, 12, DockKit.PANEL_FILL)
	panel.set_edge(HudStyle.ENEMY_EDGE)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 8
	panel.offset_bottom = -124
	panel.visible = false
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var heading := HudStyle.caps(12, HudStyle.GOLD)
	heading.text = "REPORT A BUG"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var close := DockKit.secondary_button("X")
	close.custom_minimum_size = Vector2(26, 22)
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = Tip.wrap("Close (Esc). What you typed stays for next time.")
	close.pressed.connect(close_panel)
	head.add_child(close)

	title_edit = _line(box, "Title", "What went wrong, in a few words")
	title_edit.max_length = 120
	name_edit = _line(box, "Your name", "Who's reporting (optional)")
	name_edit.max_length = 40
	name_edit.text = _saved_name()
	box.add_child(_caps("Severity"))
	severity = OptionButton.new()
	_style_option(severity)
	for s in SEVERITIES:
		severity.add_item(s)
	severity.select(2)
	box.add_child(severity)
	box.add_child(_caps("What happened"))
	description = TextEdit.new()
	description.placeholder_text = "What you did, what you expected, what happened instead."
	description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	description.custom_minimum_size = Vector2(0, 120)
	_style_input(description)
	box.add_child(description)
	info_check = _check(box, "Attach game info (mode, round, board)", true)
	shot_check = _check(box, "Attach a screenshot", true)
	send_button = DockKit.primary_button("Send report")
	send_button.custom_minimum_size = Vector2(0, 32)
	send_button.focus_mode = Control.FOCUS_NONE
	send_button.pressed.connect(submit)
	box.add_child(send_button)
	status_label = DockKit.text(11, HudStyle.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(PANEL_W - 28, 0)
	box.add_child(status_label)

func _caps(text: String) -> Label:
	var l := HudStyle.caps(10, HudStyle.MUTED)
	l.text = text.to_upper()
	return l

func _line(box: VBoxContainer, label: String, hint: String) -> LineEdit:
	box.add_child(_caps(label))
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.custom_minimum_size = Vector2(0, 30)
	_style_input(e)
	box.add_child(e)
	return e

func _check(box: VBoxContainer, text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_override("font", HudStyle.label_font())
	c.add_theme_font_size_override("font_size", 12)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		c.add_theme_color_override(k, HudStyle.INK)
	box.add_child(c)
	return c

func _style_input(c: Control) -> void:
	var sb := DockKit.well_box(DockKit.LINE, 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	var focus := DockKit.well_box(HudStyle.GOLD, 1)
	focus.content_margin_left = 8
	focus.content_margin_right = 8
	focus.content_margin_top = 4
	focus.content_margin_bottom = 4
	c.add_theme_stylebox_override("normal", sb)
	c.add_theme_stylebox_override("focus", focus)
	c.add_theme_stylebox_override("read_only", sb)
	c.add_theme_font_override("font", HudStyle.label_font())
	c.add_theme_font_size_override("font_size", 13)
	c.add_theme_color_override("font_color", HudStyle.INK)
	c.add_theme_color_override("font_placeholder_color", DockKit.DIM_TEXT)
	c.add_theme_color_override("caret_color", HudStyle.GOLD)

func _style_option(o: OptionButton) -> void:
	var look := DockKit.secondary_button("")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb := look.get_theme_stylebox(state).duplicate() as StyleBox
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		o.add_theme_stylebox_override(state, sb)
	look.free()
	o.add_theme_font_override("font", HudStyle.label_font())
	o.add_theme_font_size_override("font_size", 13)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		o.add_theme_color_override(k, HudStyle.INK)
	o.custom_minimum_size = Vector2(0, 30)
	o.focus_mode = Control.FOCUS_NONE

# --- opening and closing ---------------------------------------------------------------------------

func toggle_panel() -> void:
	if is_open:
		close_panel()
	else:
		open_panel()

func open_panel() -> void:
	if is_open:
		return
	_shot = _take_screenshot()   # before the panel covers anything
	is_open = true
	panel.visible = true
	toggle.text = "X"
	_set_status("" if not sending else "Sending...")
	title_edit.grab_focus()
	if not Settings.reduce_motion:   # folds up out of the button
		panel.pivot_offset = Vector2(0, panel.size.y)
		panel.scale = Vector2(1, 0.2)
		panel.modulate.a = 0.0
		var t := create_tween().set_parallel(true)
		t.tween_property(panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(panel, "modulate:a", 1.0, 0.12)

func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	toggle.text = "BUG"
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and panel.is_ancestor_of(focused):
		focused.release_focus()
	panel.visible = false

# Esc closes the panel before anything else sees it (the game's own Esc handlers skip while it is open).
func _input(event):
	if is_open and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()

# True while the player is typing into the panel, or into any text field (a comp's name in the planner);
# the game's hotkeys check this.
func typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit or f is TextEdit:
		return true
	return is_open and f != null and panel.is_ancestor_of(f)

# --- sending -------------------------------------------------------------------------------------

func webhook_url() -> String:
	if url_override != "":
		return url_override
	if not FileAccess.file_exists(WEBHOOK_FILE):
		return ""
	return FileAccess.get_file_as_string(WEBHOOK_FILE).strip_edges()

# Checks the form and posts it. Returns false (with a message) when nothing was sent.
func submit() -> bool:
	if sending:
		return false
	if title_edit.text.strip_edges() == "":
		_set_status("Give the bug a title first.", HudStyle.ENEMY)
		title_edit.grab_focus()
		return false
	if description.text.strip_edges() == "":
		_set_status("Say what happened first.", HudStyle.ENEMY)
		description.grab_focus()
		return false
	if _cooldown_left > 0.0:
		_set_status("Wait %d s before sending another." % ceili(_cooldown_left), HudStyle.ENEMY)
		return false
	var url := webhook_url()
	if not url.begins_with("https://"):
		_set_status("Bug reports aren't set up in this build (no webhook).", HudStyle.ENEMY)
		return false
	_save_name(name_edit.text.strip_edges())
	var req := build_request()
	var err := http.request_raw(url + "?wait=true", req.headers, HTTPClient.METHOD_POST, req.body)
	if err != OK:
		_set_status("Couldn't send (error %d). Check your connection." % err, HudStyle.ENEMY)
		return false
	sending = true
	send_button.disabled = true
	_set_status("Sending...")
	return true

# The webhook request: a Discord embed as JSON, plus the screenshot as a file when it is attached
# (multipart/form-data). Returns {"headers": PackedStringArray, "body": PackedByteArray, "payload": Dictionary}.
func build_request() -> Dictionary:
	var sev := severity.selected
	var desc := description.text.strip_edges()
	if desc.length() > MAX_DESCRIPTION:
		desc = desc.left(MAX_DESCRIPTION) + "\n...(cut)"
	var fields: Array = [
		{"name": "Severity", "value": SEVERITIES[sev], "inline": true},
		{"name": "Tester", "value": name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "(anonymous)", "inline": true},
	]
	if info_check.button_pressed:
		fields.append({"name": "Game", "value": game_info().left(1000), "inline": false})
	var embed := {
		"title": ("[%s] " % SEVERITIES[sev]) + title_edit.text.strip_edges().left(200),
		"description": desc,
		"color": SEVERITY_COLORS[sev],
		"fields": fields,
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",
	}
	var with_shot := shot_check.button_pressed and not _shot.is_empty()
	if with_shot:
		embed["image"] = {"url": "attachment://screenshot.png"}
	var payload := {"username": "Hare & Hex bug report", "embeds": [embed], "allowed_mentions": {"parse": []}}
	var json := JSON.stringify(payload)
	if not with_shot:
		return {"headers": PackedStringArray(["Content-Type: application/json"]), "body": json.to_utf8_buffer(), "payload": payload}
	var boundary := "----HareHexBug%d" % Time.get_ticks_usec()
	var body := PackedByteArray()
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(json.to_utf8_buffer())
	body.append_array(("\r\n--%s\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"screenshot.png\"\r\nContent-Type: image/png\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(_shot)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return {"headers": PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary]), "body": body, "payload": payload}

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	sending = false
	send_button.disabled = false
	if result == HTTPRequest.RESULT_SUCCESS and (code == 200 or code == 204):
		_cooldown_left = COOLDOWN
		_set_status("Sent. Thank you!", Color("7dff9a"))
		title_edit.text = ""
		description.text = ""
		severity.select(2)
	elif code == 429:
		_set_status("Too many reports right now. Try again in a minute.", HudStyle.ENEMY)
	elif result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Couldn't reach the server (no connection?). Your text is kept.", HudStyle.ENEMY)
	else:
		_set_status("The server said no (HTTP %d). Your text is kept." % code, HudStyle.ENEMY)

func _set_status(text: String, color := HudStyle.MUTED) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)

# --- what gets attached ------------------------------------------------------------------------

func _take_screenshot() -> PackedByteArray:
	if DisplayServer.get_name() == "headless":
		return PackedByteArray()
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return PackedByteArray()
	if img.get_width() > SHOT_WIDTH:
		img.resize(SHOT_WIDTH, roundi(img.get_height() * SHOT_WIDTH / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
	return img.save_png_to_buffer()

# A few lines about where the player is: build, screen, and the run (mode, round, phase, board).
func game_info() -> String:
	var lines: PackedStringArray = []
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	lines.append("Build: %s, Godot %s, %s" % [ver if ver != "" else "dev", Engine.get_version_info().string, OS.get_name()])
	lines.append("Window: %s, %s" % [DisplayServer.window_get_size(), Settings.display_mode])
	if Telemetry.active():
		lines.append("Telemetry id: %s" % Telemetry.player_id.left(8))   # finds this tester's row on the stats page
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		lines.append("Screen: main menu")
		return "\n".join(lines)
	var mode := "Free play"
	if gm.get("lobby") != null:
		mode = "Lobby"
	elif GameState.ghost_mode:
		mode = "Async PvP"
	if GameState.run_level != null:
		mode = "Campaign: %s (%s)" % [GameState.run_level.display_name, GameState.run_level.id]
	lines.append("Mode: " + mode)
	var phase_names := {Events.Phase.PREP: "prep", Events.Phase.COMBAT: "fight", Events.Phase.RESULT: "result"}
	lines.append("Round %d (%d-%d), %s, seed %d" % [GameState.round_number, GameState.stage(), GameState.round_in_stage(), phase_names.get(gm.phase, "?"), GameState.run_seed])
	var me: PlayerState = GameState.me
	lines.append("Level %d, %d gold, %d HP" % [me.level, me.gold, me.player_hp])
	var board := get_tree().get_first_node_in_group("board") as Board
	if board != null:
		var units: PackedStringArray = []
		for u in board.all_player_units():
			if u.coord.x >= 0:
				units.append("%s%s" % [u.data.display_name, "*".repeat(u.star)])
		lines.append("Board (%s): %s" % [board.theme, ", ".join(units) if not units.is_empty() else "empty"])
	return "\n".join(lines)

func _saved_name() -> String:
	var cfg := ConfigFile.new()
	return str(cfg.get_value("report", "name", "")) if cfg.load(name_cfg) == OK else ""

func _save_name(n: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("report", "name", n)
	cfg.save(name_cfg)
