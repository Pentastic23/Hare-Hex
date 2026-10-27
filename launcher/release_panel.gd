# release_panel.gd
extends VBoxContainer

# The launcher's release panel, for the developer only. It is reachable (the RELEASE button in the
# header) when the launcher knows where the game's project is: launcher.cfg's project_dir (picked with
# Ctrl+Shift+D), or found by itself when the launcher runs from <project>/build or from the editor.
# Testers have no project, so they never see it. It runs tools/release.ps1 with -Yes, after showing
# its own warnings (uncommitted changes, unpushed commits, no token), and shows the script's output.

signal closed
signal finished(ok: bool, dry_run: bool)

const VERSION_RE := "^\\d+(\\.\\d+){1,3}$"
const MAX_LINES := 250
const SKIP := ["savepack |", "Storing File", "reimport |", "loading_editor_layout", "[ DONE ]"]

var host                   # the launcher: its fonts, colours and widget helpers
var project_dir := ""
var latest_tag := ""       # the newest tag on GitHub, for suggesting the next version

var running := false
var _confirming := false
var _dry_run := false
var _pid := -1
var _pipes: Array[Thread] = []
var _lines := PackedStringArray()
var _last_error := ""
var _ansi := RegEx.create_from_string("\u001b\\[[0-9;?]*[A-Za-z]")
var _version_re := RegEx.create_from_string(VERSION_RE)

var _status: Label
var _where: Label
var _version: LineEdit
var _full: CheckBox
var _dry: CheckBox
var _notes: TextEdit
var _log: RichTextLabel
var _back: Button
var _go: Button


func build(launcher) -> void:
	host = launcher
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_status = host._label("Release a new version to your testers.", host.LABEL_FONT, 17, host.MUTED)
	add_child(_status)

	var form := HBoxContainer.new()
	form.add_theme_constant_override("separation", 12)
	add_child(form)
	form.add_child(host._label("VERSION", host.LABEL_FONT, 12, host.GOLD))
	_version = LineEdit.new()
	_version.custom_minimum_size = Vector2(110, 0)
	_version.placeholder_text = "0.1.4"
	_style_field(_version)
	_version.text_changed.connect(func(_t): _unconfirm())
	form.add_child(_version)
	_full = _check_box("Full release (not pre-release)")
	form.add_child(_full)
	_dry = _check_box("Dry run (build only)")
	form.add_child(_dry)

	var well := PanelContainer.new()
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.add_theme_stylebox_override("panel", host._flat(Color(0.04, 0.045, 0.07, 0.8), 8))
	add_child(well)
	_notes = TextEdit.new()
	_notes.placeholder_text = "What changed? (Leave empty and GitHub writes the notes from your commits.)"
	_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_style_field(_notes)
	_notes.text_changed.connect(_unconfirm)
	well.add_child(_notes)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.add_theme_font_override("normal_font", host.LABEL_FONT)
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_color_override("default_color", host.MUTED)
	_log.visible = false
	well.add_child(_log)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_where = host._label("", host.LABEL_FONT, 11, host.MUTED)
	_where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_where.clip_text = true
	row.add_child(_where)
	_back = host._button("BACK", false)
	_back.pressed.connect(func(): if not running: closed.emit())
	row.add_child(_back)
	_go = host._button("RELEASE", true)
	_go.custom_minimum_size = Vector2(150, 44)
	_go.pressed.connect(_on_go)
	row.add_child(_go)


# Called each time the panel is shown.
func open() -> void:
	if not running:
		if _version.text == "" and latest_tag != "":
			_version.text = next_version(latest_tag)
		_show_editing()
		_set_status("Release a new version to your testers.", host.MUTED)
	var token := "token found" if _token_present() else "NO TOKEN: put one in release_token.txt"
	_where.text = "%s  ·  %s" % [project_dir, token]


# "v0.1.3" -> "0.1.4"
static func next_version(tag: String) -> String:
	var digits := ""
	for c in tag:
		if c in "0123456789.":
			digits += c
	var parts := digits.strip_edges().trim_prefix(".").trim_suffix(".").split(".", false)
	if parts.is_empty():
		return ""
	parts[parts.size() - 1] = str(int(parts[parts.size() - 1]) + 1)
	return ".".join(parts)


func _process(_delta: float) -> void:
	if running and _pid > 0 and not OS.is_process_running(_pid):
		_finish(OS.get_process_exit_code(_pid))


# --- Starting ---------------------------------------------------------------------------------

func _on_go() -> void:
	if running:
		return
	if _log.visible:   # after a run: back to the form
		_show_editing()
		return
	var version := _version.text.strip_edges()
	if _version_re.search(version) == null:
		_set_status("The version should look like 0.1.4.", host.RED)
		return
	_dry_run = _dry.button_pressed
	if _dry_run or _confirming:
		_start(version)
		return
	# First press: say what will happen. Second press: do it.
	var warnings := PackedStringArray()
	if not _token_present():
		_set_status("No GitHub token: put one in release_token.txt in the project folder.", host.RED)
		return
	if not FileAccess.file_exists(project_dir.path_join("bug_report_webhook.txt")):
		_set_status("bug_report_webhook.txt is missing: put the bug report webhook URL in it first.", host.RED)
		return
	if "v" + version == latest_tag:
		_set_status("v%s is already released. Pick a new version." % version, host.RED)
		return
	var dirty := _git(["status", "--porcelain"]).split("\n", false).size()
	if dirty > 0:
		warnings.append("%d uncommitted file%s go into the build but not the tag." % [dirty, "" if dirty == 1 else "s"])
	var ahead := _git(["rev-list", "--count", "@{u}..HEAD"]).strip_edges()
	if ahead.is_valid_int() and int(ahead) > 0:
		warnings.append("%s commit%s will be pushed." % [ahead, "" if ahead == "1" else "s"])
	var kind := "full release" if _full.button_pressed else "pre-release"
	_set_status("Publish v%s (%s) to every tester? %s" % [version, kind, " ".join(warnings)], host.GOLD)
	_confirming = true
	_go.text = "CONFIRM"


func _start(version: String) -> void:
	var notes_path := ProjectSettings.globalize_path("user://release_notes.txt")
	var f := FileAccess.open(notes_path, FileAccess.WRITE)
	if f == null:
		_set_status("Couldn't write the notes file.", host.RED)
		return
	f.store_string(_notes.text)
	f.close()
	# Bypass only for this one PowerShell process: Windows blocks scripts by default, and this is our own.
	var args := PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", project_dir.path_join("tools/release.ps1"),
			"-Version", version, "-NotesFile", notes_path, "-Yes"])
	if _full.button_pressed:
		args.append("-Full")
	if _dry_run:
		args.append("-DryRun")
	# The script exports the launcher to build/; it can't overwrite this one while it runs.
	var own := OS.get_executable_path().replace("\\", "/").to_lower()
	if own == project_dir.path_join("build/HareHex-Launcher.exe").replace("\\", "/").to_lower():
		args.append("-SkipLauncher")
	var p := OS.execute_with_pipe("powershell.exe", args)
	if p.is_empty():
		_set_status("Couldn't start PowerShell.", host.RED)
		return
	running = true
	_pid = int(p.pid)
	_lines.clear()
	_last_error = ""
	_log.text = ""
	_show_running()
	_set_status("Starting%s..." % (" a dry run" if _dry_run else ""), host.GOLD)
	for key in ["stdio", "stderr"]:
		var t := Thread.new()
		t.start(_read_pipe.bind(p[key], key == "stderr"))
		_pipes.append(t)


# Runs on a thread: hands each line of one pipe to the panel.
func _read_pipe(pipe: FileAccess, is_error: bool) -> void:
	while pipe.is_open() and pipe.get_error() == OK:
		var line := pipe.get_line()
		if pipe.get_error() != OK and line == "":
			break
		_add_line.call_deferred(line, is_error)
	pipe.close()


func _add_line(raw: String, is_error: bool) -> void:
	var line := _ansi.sub(raw, "", true).strip_edges(false, true)
	if line.strip_edges() == "":
		return
	for s in SKIP:
		if line.contains(s):
			return
	var safe := line.replace("[", "[lb]")
	if line.begins_with("== "):
		_set_status(line.substr(3) + "...", host.GOLD)
		safe = "[color=#%s]%s[/color]" % [host.GOLD.to_html(false), safe]
	elif is_error or line.begins_with("WARNING") or line.contains("ERROR"):
		# The first real error line says why (PowerShell follows it with position details).
		if is_error and _last_error == "" and not line.begins_with("WARNING"):
			_last_error = line.strip_edges()
		safe = "[color=#%s]%s[/color]" % [host.RED.to_html(false), safe]
	_lines.append(safe)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_log.text = "\n".join(_lines)


func _finish(code: int) -> void:
	running = false
	_pid = -1
	for t in _pipes:
		t.wait_to_finish()
	_pipes.clear()
	_confirming = false
	_back.disabled = false
	_go.disabled = false
	_go.text = "NEW RELEASE"
	_version.editable = true
	_full.disabled = false
	_dry.disabled = false
	if code == 0:
		_set_status("Dry run done: the build is in build\\." if _dry_run else "Released! Your testers get it the next time they start.", host.GREEN)
		if not _dry_run:
			_version.text = ""
			_notes.text = ""
	else:
		var why := _last_error if _last_error != "" else "see the log"
		_set_status("The release failed: %s" % why, host.RED)
	finished.emit(code == 0, _dry_run)


# --- Helpers ----------------------------------------------------------------------------------

func _unconfirm() -> void:
	if _log.visible and not running:
		_show_editing()
	if _confirming:
		_confirming = false
		_go.text = "RELEASE"
		_set_status("Release a new version to your testers.", host.MUTED)


func _show_editing() -> void:
	_notes.visible = true
	_log.visible = false
	_version.editable = true
	_full.disabled = false
	_dry.disabled = false
	_go.text = "RELEASE"
	_confirming = false


func _show_running() -> void:
	_notes.visible = false
	_log.visible = true
	_version.editable = false
	_full.disabled = true
	_dry.disabled = true
	_back.disabled = true
	_go.disabled = true


func _token_present() -> bool:
	return OS.get_environment("GITHUB_TOKEN") != "" or FileAccess.file_exists(project_dir.path_join("release_token.txt"))


func _git(args: Array) -> String:
	var out := []
	OS.execute("git", PackedStringArray(["-C", project_dir]) + PackedStringArray(args), out)
	return "" if out.is_empty() else str(out[0])


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _check_box(text: String) -> CheckBox:
	var b := CheckBox.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", host.LABEL_FONT)
	b.add_theme_font_size_override("font_size", 13)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, host.INK if key != "font_color" else host.MUTED)
	b.add_theme_color_override("checkbox_checked_color", host.GOLD)
	b.add_theme_color_override("checkbox_unchecked_color", host.MUTED)
	b.toggled.connect(func(_on): _unconfirm())
	return b


func _style_field(field: Control) -> void:
	field.add_theme_font_override("font", host.LABEL_FONT)
	field.add_theme_font_size_override("font_size", 14)
	field.add_theme_color_override("font_color", host.INK)
	field.add_theme_color_override("font_placeholder_color", Color(host.MUTED, 0.6))
	field.add_theme_color_override("caret_color", host.GOLD)
	field.add_theme_color_override("selection_color", Color(host.GOLD, 0.3))
	var box: StyleBoxFlat = host._flat(Color("0d0f17"), 6)
	box.border_color = Color("3d4566")
	box.set_border_width_all(1)
	field.add_theme_stylebox_override("normal", box)
	field.add_theme_stylebox_override("focus", box)
	field.add_theme_stylebox_override("read_only", box)
