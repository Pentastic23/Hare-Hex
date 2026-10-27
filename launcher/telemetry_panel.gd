# telemetry_panel.gd
extends VBoxContainer

# The launcher's STATS panel, for the developer only (shown with the RELEASE button, when the launcher
# knows the project folder). It gets the testers' telemetry (docs/telemetry.md) for parsing:
#   DOWNLOAD    GET <server>/v1/events?key=<stats key>&days=N from the ghost service (SnapshotServer)
#   THIS PC     the events still queued on this PC by the game (Hare&Hex's user://telemetry_queue.json)
#   STATS PAGE  opens <server>/stats?key=...&days=N in the browser
# Each load is saved to <project>/telemetry/ as JSON lines (as the server stores them) and as a CSV
# with one row per event and one column per field, and summed up here. The server address is the game's
# OnlineConfig.SNAPSHOT_URL unless one is typed in; it and the stats key are kept on this PC only
# (user://stats_panel.cfg), never in the project.

signal closed

const CFG := "user://stats_panel.cfg"
const BASE_COLUMNS := ["time_utc", "received_utc", "event", "player", "session", "version"]

var host
var project_dir := ""
var last_files := PackedStringArray()   # the files the last load wrote (tests)

var _server: LineEdit
var _key: LineEdit
var _days: LineEdit
var _status: Label
var _summary: RichTextLabel
var _get: HTTPRequest
var _buttons: Array[Button] = []


func build(launcher) -> void:
	host = launcher
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_status = host._label("", host.LABEL_FONT, 17, host.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	var form := HBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	add_child(form)
	form.add_child(host._label("SERVER", host.LABEL_FONT, 12, host.GOLD))
	_server = _field("https://your-server (not hosted yet)")
	_server.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_server)
	form.add_child(host._label("KEY", host.LABEL_FONT, 12, host.GOLD))
	_key = _field("stats key")
	_key.secret = true
	_key.custom_minimum_size = Vector2(110, 0)
	form.add_child(_key)
	form.add_child(host._label("DAYS", host.LABEL_FONT, 12, host.GOLD))
	_days = _field("30")
	_days.custom_minimum_size = Vector2(44, 0)
	form.add_child(_days)
	for f in [_server, _key, _days]:
		f.text_changed.connect(func(_t): _save())

	var well := PanelContainer.new()
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.add_theme_stylebox_override("panel", host._flat(Color(0.04, 0.045, 0.07, 0.8), 8))
	add_child(well)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.selection_enabled = true
	_summary.add_theme_font_override("normal_font", host.LABEL_FONT)
	_summary.add_theme_font_size_override("normal_font_size", 13)
	_summary.add_theme_color_override("default_color", host.INK)
	well.add_child(_summary)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for spec in [["DOWNLOAD", _download, true], ["THIS PC", _load_local, false], ["STATS PAGE", _open_page, false], ["FOLDER", _open_folder, false]]:
		var b: Button = host._button(spec[0], spec[2])
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(spec[1])
		row.add_child(b)
		_buttons.append(b)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var back: Button = host._button("BACK", false)
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(func(): closed.emit())
	row.add_child(back)

	_get = HTTPRequest.new()
	_get.timeout = 60.0
	_get.request_completed.connect(_on_downloaded)
	add_child(_get)
	_load_cfg()


func open() -> void:
	if _server.text.strip_edges() == "":
		_server.text = _project_server()
	if _server.text.strip_edges() == "":
		_set_status("No server yet. Once the ghost service is hosted, put its address and stats key here. Until then THIS PC exports the events this PC's game has queued.", host.MUTED)
	else:
		_set_status("Download the testers' events, or open the stats page.", host.MUTED)
	if _summary.text == "":
		_summary.text = "[color=#%s]Nothing loaded yet. Each load is saved to %s as .jsonl and .csv.[/color]" % [host.MUTED.to_html(false), _out_dir()]


# --- Loading ----------------------------------------------------------------------------------

func _download() -> void:
	var server := _server_url()
	if server == "":
		_set_status("No server address yet: the ghost service isn't hosted. Use THIS PC for now.", host.RED)
		return
	var url := "%s/v1/events?key=%s&days=%d" % [server, _key.text.strip_edges().uri_encode(), _day_count()]
	_set_busy(true)
	_set_status("Downloading the events...", host.GOLD)
	var err := _get.request(url, ["User-Agent: HareHex-Launcher"])
	if err != OK:
		_set_busy(false)
		_set_status("Couldn't start the download (error %d)." % err, host.RED)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_set_busy(false)
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status(host._network_problem(result).replace("GitHub", "the server"), host.RED)
		return
	if code == 401:
		_set_status("The server wants the stats key it was started with (--stats-key).", host.RED)
		return
	if code == 404:
		_set_status("That server has no /v1/events: is it an older build of the ghost service?", host.RED)
		return
	if code != 200:
		_set_status("The server answered %d." % code, host.RED)
		return
	var events := parse_lines(body.get_string_from_utf8())
	_show(events, "server", "Downloaded %d events from the last %d days." % [events.size(), _day_count()])


func _load_local() -> void:
	var path := game_user_dir().path_join("telemetry_queue.json")
	if not FileAccess.file_exists(path):
		_set_status("This PC has no queued events (%s). The game queues them while no server answers; a build with telemetry has to be played first." % path, host.MUTED)
		return
	var list = JSON.parse_string(FileAccess.get_file_as_string(path))
	var events: Array = list.filter(func(e): return e is Dictionary) if list is Array else []
	_show(events, "this_pc", "Loaded %d events queued on this PC (not sent yet)." % events.size())


func _show(events: Array, source: String, message: String) -> void:
	if events.is_empty():
		_set_status(message + " Nothing to save.", host.MUTED)
		_summary.text = ""
		return
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var base := _out_dir().path_join("events_%s_%s" % [source, stamp])
	var problem := save_files(events, base)
	if problem != "":
		_set_status(problem, host.RED)
		return
	last_files = PackedStringArray([base + ".jsonl", base + ".csv"])
	_set_status("%s Saved %s.jsonl and .csv." % [message, base.get_file()], host.GREEN)
	_summary.text = summary_bbcode(events)


# --- Files (static, so tests and tools can use them) -------------------------------------------

static func parse_lines(text: String) -> Array:
	var out: Array = []
	for line in text.split("\n", false):
		var e = JSON.parse_string(line)
		if e is Dictionary:
			out.append(e)
	return out


# Writes <base>.jsonl and <base>.csv; returns "" or what went wrong.
static func save_files(events: Array, base: String) -> String:
	DirAccess.make_dir_recursive_absolute(base.get_base_dir())
	var jsonl := FileAccess.open(base + ".jsonl", FileAccess.WRITE)
	var csv := FileAccess.open(base + ".csv", FileAccess.WRITE)
	if jsonl == null or csv == null:
		return "Couldn't write to %s." % base.get_base_dir()
	for e in events:
		jsonl.store_line(JSON.stringify(e))
	csv.store_string(to_csv(events))
	return ""


# One row per event: the common fields, then one column per property name seen (sorted); nested
# values (the board's units, traits) stay as JSON in their cell.
static func to_csv(events: Array) -> String:
	var keys := {}
	for e in events:
		var p = e.get("p", {})
		if p is Dictionary:
			for k in p:
				keys[str(k)] = true
	var props := keys.keys()
	props.sort()
	var rows := PackedStringArray()
	rows.append(",".join(PackedStringArray(BASE_COLUMNS + props.map(func(k): return _cell(k)))))
	for e in events:
		var p = e.get("p", {})
		var cells := PackedStringArray([_time(e.get("t")), _time(e.get("rt")), _cell(e.get("e", "")),
				_cell(e.get("pid", "")), _cell(e.get("sid", "")), _cell(e.get("v", ""))])
		for k in props:
			cells.append(_cell(p.get(k, "")) if p is Dictionary and p.has(k) else "")
		rows.append(",".join(cells))
	return "\n".join(rows) + "\n"


static func _time(t) -> String:
	if t == null or str(t) == "":
		return ""
	return Time.get_datetime_string_from_unix_time(int(t), true)


static func _cell(v) -> String:
	var s := ""
	if v is Dictionary or v is Array:
		s = JSON.stringify(v)
	elif v is float and v == floorf(v) and absf(v) < 1e15:
		s = str(int(v))
	else:
		s = str(v)
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r"):
		s = "\"%s\"" % s.replace("\"", "\"\"")
	return s


# A few totals, so a load can be judged before opening the CSV.
static func summary_bbcode(events: Array) -> String:
	var players := {}
	var sessions := {}
	var names := {}
	var modes := {}
	var fights := 0
	var won := 0
	var first := 0
	var last := 0
	for e in events:
		players[str(e.get("pid", ""))] = true
		sessions[str(e.get("sid", ""))] = true
		var n := str(e.get("e", ""))
		names[n] = int(names.get(n, 0)) + 1
		var t := int(e.get("t", 0))
		if t > 0:
			first = t if first == 0 else mini(first, t)
			last = maxi(last, t)
		var p = e.get("p", {})
		if not p is Dictionary:
			continue
		if n == "run_end":
			var m := str(p.get("mode", "?"))
			if not modes.has(m):
				modes[m] = {}
			var r := str(p.get("result", "?"))
			modes[m][r] = int(modes[m].get(r, 0)) + 1
		elif n == "fight":
			fights += 1
			if p.get("won", false):
				won += 1
	var out := PackedStringArray()
	out.append("[b]%d events[/b] · %d testers · %d sessions" % [events.size(), players.size(), sessions.size()])
	if first > 0:
		out.append("From %s to %s (UTC)" % [Time.get_datetime_string_from_unix_time(first, true), Time.get_datetime_string_from_unix_time(last, true)])
	var counts := PackedStringArray()
	var sorted := names.keys()
	sorted.sort()
	for n in sorted:
		counts.append("%s %d" % [n, names[n]])
	out.append("Events: " + ", ".join(counts))
	if fights > 0:
		out.append("Fights: %d, won %d%%" % [fights, roundi(100.0 * won / fights)])
	for m in modes:
		var results := PackedStringArray()
		for r in modes[m]:
			results.append("%s %d" % [r, modes[m][r]])
		out.append("Runs ended, %s: %s" % [m, ", ".join(results)])
	if names.has("unclean_exit"):
		out.append("[color=#ff6b5e]Crashes or force-quits noticed: %d[/color]" % names.unclean_exit)
	return "\n".join(out)


# The game's user folder (where its telemetry queue is), beside this launcher's own.
static func game_user_dir() -> String:
	return OS.get_data_dir().path_join("Godot/app_userdata/Hare&Hex")


# --- Helpers ----------------------------------------------------------------------------------

func _out_dir() -> String:
	return project_dir.path_join("telemetry")


func _server_url() -> String:
	return _server.text.strip_edges().trim_suffix("/")


func _day_count() -> int:
	return clampi(int(_days.text) if _days.text.is_valid_int() else 30, 1, 3650)


# OnlineConfig.SNAPSHOT_URL from the project, if it is set yet.
func _project_server() -> String:
	var text := FileAccess.get_file_as_string(project_dir.path_join("Scripts/online/online_config.gd"))
	var m := RegEx.create_from_string("(?m)^const SNAPSHOT_URL := \"([^\"]*)\"").search(text)
	return m.get_string(1) if m != null else ""


func _open_page() -> void:
	var server := _server_url()
	if server == "":
		_set_status("No server address yet: the stats page lives on the ghost service once it's hosted.", host.RED)
		return
	OS.shell_open("%s/stats?key=%s&days=%d" % [server, _key.text.strip_edges().uri_encode(), _day_count()])


func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir())
	OS.shell_open(_out_dir())


func _set_busy(on: bool) -> void:
	for b in _buttons:
		b.disabled = on


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _field(placeholder: String) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = placeholder
	f.add_theme_font_override("font", host.LABEL_FONT)
	f.add_theme_font_size_override("font_size", 13)
	f.add_theme_color_override("font_color", host.INK)
	f.add_theme_color_override("font_placeholder_color", Color(host.MUTED, 0.6))
	f.add_theme_color_override("caret_color", host.GOLD)
	var box: StyleBoxFlat = host._flat(Color("0d0f17"), 6)
	box.border_color = Color("3d4566")
	box.set_border_width_all(1)
	f.add_theme_stylebox_override("normal", box)
	f.add_theme_stylebox_override("focus", box)
	return f


func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		_server.text = str(cfg.get_value("stats", "server", ""))
		_key.text = str(cfg.get_value("stats", "key", ""))
		_days.text = str(cfg.get_value("stats", "days", "30"))
	else:
		_days.text = "30"


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "server", _server.text.strip_edges())
	cfg.set_value("stats", "key", _key.text.strip_edges())
	cfg.set_value("stats", "days", _days.text.strip_edges())
	cfg.save(CFG)
