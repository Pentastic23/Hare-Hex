# launcher.gd
extends Control

# The Hare & Hex launcher: asks GitHub for the newest release of the game, downloads its Windows
# build when it differs from the installed one, unpacks it and starts the game.
#
# A release is playable when it has an asset named ASSET (a zip with the exported game in it;
# tools/release.ps1 makes and uploads it). Pre-releases count; drafts never show to testers.
# The game goes into a "game" folder next to the launcher (or the launcher's user folder when that
# one can't be written), one subfolder per version, with installed.json naming the current one.
# The game's saves live in its own app_userdata folder, so an update never touches them.
#
# The launcher also keeps itself up to date: each release carries LAUNCHER_ASSET too, and when its
# SHA-256 differs from this exe's the launcher swaps itself for it and restarts (see "Updating the
# launcher itself").
#
# Command line (after --): --releases-url URL (a test feed instead of GitHub), --install-dir DIR,
# --no-self-update.
#
# The developer also gets a RELEASE button (release_panel.gd) once the launcher knows where the
# game's project is: found by itself from <project>/build or the editor, or picked with Ctrl+Shift+D.

const REPO := "Pentastic23/Hare-Hex"
const ASSET := "HareHex-windows.zip"
const LAUNCHER_ASSET := "HareHex-Launcher.exe"
const RELEASES_URL := "https://api.github.com/repos/%s/releases?per_page=15"
const SETTINGS_PATH := "user://launcher.cfg"
const MARKER := ".hare_hex_version"          # written into every version folder we unpack
const COUNTDOWN := 3.0                       # seconds before the game starts by itself
const ReleasePanel := preload("res://release_panel.gd")

const INK := Color("ece6d6")
const MUTED := Color("a9aec4")
const GOLD := Color("f2c14e")
const RED := Color("ff6b5e")
const GREEN := Color("7bd389")
const TRACK := Color("262b3f")
const FILL := Color("171a26")
const EDGE_GOLD := Color("8a6a1f")
const LIP := Color("0a0b11")
const NUMBER_FONT := preload("res://fonts/Jersey10-Regular.ttf")
const LABEL_FONT := preload("res://fonts/AtkinsonHyperlegible-Bold.ttf")

enum State { CHECKING, DOWNLOADING, VERIFYING, EXTRACTING, READY, FAILED }

var state := State.CHECKING
var install_dir := ""
var installed := {}        # installed.json: tag, name, dir, exe, asset_id
var release := {}          # the release we want (from the API)
var asset := {}            # its ASSET entry
var auto_start := true
var countdown := -1.0      # > 0 while counting down to start the game
var project_dir := ""      # the game's project folder (developer only; "" for testers)

var _api: HTTPRequest
var _download: HTTPRequest
var _self_download: HTTPRequest
var _dl: HTTPRequest          # the download in progress (the game or the launcher), for the bar
var _dl_size := 0
var _dl_part := ""
var _self_cache := {}         # this exe's SHA-256 with the path, size and time it was taken for
var _pending := []            # the release list, while the launcher updates itself first
var _thread: Thread
var _speed_bytes := 0
var _speed_time := 0.0
var _speed := 0.0

var _status: Label
var _detail: Label
var _bar: ProgressBar
var _notes_title: Label
var _notes: RichTextLabel
var _version: Label
var _auto: CheckBox
var _retry: Button
var _play: Button
var _main: VBoxContainer
var _release: VBoxContainer
var _release_button: Button
var _close_warned := false


func _ready() -> void:
	DisplayServer.window_set_title("Hare & Hex Launcher")
	get_tree().auto_accept_quit = false
	_load_settings()
	project_dir = _find_project()
	_build_ui()
	install_dir = _pick_install_dir()
	installed = _read_installed()
	_clean_old_versions()
	_remove_old_launcher()
	_show_installed()
	_check()


func _process(delta: float) -> void:
	if state == State.DOWNLOADING and _dl != null:
		_show_progress(delta)
	if countdown > 0.0:
		countdown -= delta
		if countdown <= 0.0:
			_launch()
		else:
			_play.text = "PLAY  %d" % ceili(countdown)


func _unhandled_input(event: InputEvent) -> void:
	# Any click or key stops the countdown, so a tester can read the notes first.
	if countdown > 0.0 and (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		_stop_countdown()
	if event is InputEventKey and event.pressed and event.keycode == KEY_D and event.ctrl_pressed and event.shift_pressed:
		_pick_project()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if _release != null and _release.running and not _close_warned:
		_close_warned = true
		_release._set_status("A release is still running. Close again to quit anyway.", RED)
		return
	if state == State.DOWNLOADING and _dl != null:
		_dl.cancel_request()
		DirAccess.remove_absolute(_dl_part)
	get_tree().quit()


# --- Checking -----------------------------------------------------------------------------------

func _check() -> void:
	state = State.CHECKING
	_retry.visible = false
	_bar.visible = false
	_detail.text = ""
	_set_status("Checking for updates...", MUTED)
	_update_play()
	if _api == null:
		_api = HTTPRequest.new()
		_api.timeout = 30.0
		_api.request_completed.connect(_on_releases)
		add_child(_api)
	var url := _arg("--releases-url", RELEASES_URL % REPO)
	var err := _api.request(url, ["Accept: application/vnd.github+json", "User-Agent: HareHex-Launcher",
			"X-GitHub-Api-Version: 2022-11-28"])
	if err != OK:
		_fail("Couldn't reach GitHub (error %d)." % err)


func _on_releases(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(_network_problem(result))
		return
	if code == 403 or code == 429:
		_fail("GitHub is limiting requests right now. Try again in a few minutes.")
		return
	if code != 200:
		_fail("GitHub answered %d." % code)
		return
	var list = JSON.parse_string(body.get_string_from_utf8())
	if not list is Array:
		_fail("GitHub sent something unexpected.")
		return
	for r in list:
		if r is Dictionary and not r.get("draft", false):
			_release.latest_tag = str(r.get("tag_name", ""))
			break
	_check_launcher(list)


# After the launcher is up to date: the game.
func _pick_game(list: Array) -> void:
	# The newest release with a Windows build. GitHub lists them newest first.
	release = {}
	asset = {}
	for r in list:
		if not r is Dictionary or r.get("draft", false):
			continue
		for a in r.get("assets", []):
			if a is Dictionary and a.get("name", "") == ASSET:
				release = r
				asset = a
				break
		if not release.is_empty():
			break
	if release.is_empty():
		_fail("No release has a Windows build (%s) yet." % ASSET)
		return
	_show_notes(release)
	if _is_current():
		_ready_to_play("Up to date: %s" % release.get("tag_name", ""), false)
	else:
		_start_download()


# What went wrong, in words a tester can act on, with Godot's result number to report.
static func _network_problem(result: int) -> String:
	var text := "Couldn't reach GitHub. Check your internet connection."
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE:
			text = "Couldn't look up GitHub's address. Check your internet connection."
		HTTPRequest.RESULT_CANT_CONNECT:
			text = "Couldn't connect to GitHub. A firewall or antivirus may be blocking the launcher."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			text = "Couldn't open a secure connection to GitHub. Check the PC's date and time, or antivirus HTTPS scanning."
		HTTPRequest.RESULT_TIMEOUT:
			# Also what a blocked or refused connection looks like on Windows: Godot waits it out.
			text = "GitHub didn't answer in time. A firewall or antivirus may be blocking the launcher."
		HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_NO_RESPONSE:
			text = "The connection to GitHub dropped. A VPN, proxy or antivirus may be in the way."
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			text = "Couldn't save the download. Is the launcher's folder writable, with space left?"
	return "%s (error %d)" % [text, result]


func _is_current() -> bool:
	return not installed.is_empty() \
			and installed.get("tag", "") == release.get("tag_name", "") \
			and int(installed.get("asset_id", -1)) == int(asset.get("id", -2)) \
			and FileAccess.file_exists(_exe_path())


# --- Downloading --------------------------------------------------------------------------------

func _start_download() -> void:
	state = State.DOWNLOADING
	_stop_countdown()
	var what := "Updating to" if not installed.is_empty() else "Installing"
	_set_status("%s %s..." % [what, release.get("tag_name", "")], GOLD)
	_reset_progress()
	_update_play()
	DirAccess.make_dir_recursive_absolute(install_dir)
	if _download == null:
		_download = HTTPRequest.new()
		_download.use_threads = true
		_download.download_chunk_size = 1 << 20
		_download.request_completed.connect(_on_downloaded)
		add_child(_download)
	_download.download_file = _part_path()
	_dl = _download
	_dl_size = int(asset.get("size", 0))
	_dl_part = _part_path()
	var err := _download.request(asset.get("browser_download_url", ""), ["User-Agent: HareHex-Launcher"])
	if err != OK:
		_fail("Couldn't start the download (error %d)." % err)


func _reset_progress() -> void:
	_bar.visible = true
	_bar.value = 0.0
	_speed_bytes = 0
	_speed_time = 0.0
	_speed = 0.0
	_detail.text = ""


func _show_progress(delta: float) -> void:
	var total := float(_dl_size)
	var got := _dl.get_downloaded_bytes()
	_speed_time += delta
	if _speed_time >= 0.5:
		_speed = lerpf(_speed, (got - _speed_bytes) / _speed_time, 0.5 if _speed > 0.0 else 1.0)
		_speed_bytes = got
		_speed_time = 0.0
	if total > 0.0:
		_bar.value = got / total * 100.0
	var text := "%s / %s" % [_mb(got), _mb(int(total))]
	if _speed > 0.0:
		text += "   ·   %s/s" % _mb(int(_speed))
		if total > got:
			text += "   ·   %s left" % _duration((total - got) / _speed)
	_detail.text = text


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(_part_path())
		if result != HTTPRequest.RESULT_SUCCESS:
			_fail("The download failed: " + _network_problem(result))
		else:
			_fail("The download failed (HTTP %d). Try again." % code)
		return
	state = State.VERIFYING
	_bar.value = 100.0
	_set_status("Checking the download...", GOLD)
	_detail.text = ""
	_run_thread(_verify.bind(_part_path(), int(asset.get("size", -1)), str(asset.get("digest", ""))), _on_verified)


# Runs on a thread. Returns "" when the file is what GitHub says it is.
func _verify(path: String, size: int, digest: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "the download is missing"
	if size >= 0 and f.get_length() != size:
		return "the download is the wrong size"
	if not digest.begins_with("sha256:"):
		return ""   # older assets have no digest; the size has to do
	if _sha256(f) != digest.substr(7).to_lower():
		return "the download is damaged"
	return ""


static func _sha256(f: FileAccess) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()


func _on_verified(problem: String) -> void:
	if problem != "":
		DirAccess.remove_absolute(_part_path())
		_fail("Something went wrong: %s. Try again." % problem)
		return
	state = State.EXTRACTING
	_set_status("Unpacking...", GOLD)
	var folder := _folder_for(release.get("tag_name", "game"))
	_run_thread(_extract.bind(_part_path(), install_dir.path_join(folder)), _on_extracted.bind(folder))


# Runs on a thread. Unpacks the zip into dest (through dest + ".tmp", so a half-unpacked
# version never looks finished). Returns the game exe relative to dest, or "!" + the problem.
func _extract(zip_path: String, dest: String) -> String:
	var tmp := dest + ".tmp"
	_remove_tree(tmp)
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "!the download isn't a zip file"
	var exe := ""
	for name in zip.get_files():
		var rel := name.replace("\\", "/")
		if rel.begins_with("/") or rel.contains(":") or rel.split("/").has(".."):
			zip.close()
			return "!the zip has a bad path in it"
		var out := tmp.path_join(rel)
		if rel.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(out)
			continue
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f == null:
			zip.close()
			return "!couldn't write %s" % rel
		f.store_buffer(zip.read_file(name))
		f.close()
		# The game's exe: the shallowest .exe that isn't Godot's console wrapper.
		if rel.get_extension().to_lower() == "exe" and not rel.to_lower().ends_with(".console.exe"):
			if exe == "" or rel.count("/") < exe.count("/"):
				exe = rel
	zip.close()
	if exe == "":
		return "!there is no game in the zip"
	var marker := FileAccess.open(tmp.path_join(MARKER), FileAccess.WRITE)
	if marker != null:
		marker.store_string(dest.get_file())
		marker.close()
	_remove_tree(dest)
	if DirAccess.rename_absolute(tmp, dest) != OK:
		return "!couldn't finish unpacking (is the old version still running?)"
	return exe


func _on_extracted(exe: String, folder: String) -> void:
	DirAccess.remove_absolute(_part_path())
	if exe.begins_with("!"):
		_fail("Something went wrong: %s." % exe.substr(1))
		return
	installed = {
		"tag": release.get("tag_name", ""),
		"name": release.get("name", ""),
		"dir": folder,
		"exe": exe,
		"asset_id": asset.get("id", -1),
		"installed_at": Time.get_datetime_string_from_system(true),
	}
	_write_installed()
	_clean_old_versions()
	_show_installed()
	_ready_to_play("Updated to %s" % installed.tag, true)


# --- Updating the launcher itself ---------------------------------------------------------------
# Windows won't let a running exe be overwritten, but it can be renamed: the new launcher is
# downloaded beside this one (.new) and checked, this one becomes .old, the new one takes its name
# and is started, and this one quits. The new one deletes the .old when it starts. Anything that
# fails along the way leaves (or puts back) a working launcher and carries on with the game.

func _self_path() -> String:
	return OS.get_executable_path()


func _can_self_update() -> bool:
	var args := OS.get_cmdline_user_args()
	if not OS.has_feature("template") or args.has("--self-updated") or args.has("--no-self-update"):
		return false
	# The copy the release script just built in build/ is newer than any release.
	var own := _self_path().replace("\\", "/").to_lower()
	if project_dir != "" and own == project_dir.path_join("build").path_join(LAUNCHER_ASSET).replace("\\", "/").to_lower():
		return false
	return _writable(_self_path().get_base_dir())


func _check_launcher(list: Array) -> void:
	var newest := {}
	for r in list:
		if not r is Dictionary or r.get("draft", false):
			continue
		for a in r.get("assets", []):
			if a is Dictionary and a.get("name", "") == LAUNCHER_ASSET:
				newest = a
				break
		if not newest.is_empty():
			break
	if newest.is_empty() or not str(newest.get("digest", "")).begins_with("sha256:") or not _can_self_update():
		_pick_game(list)
		return
	# Hashing 100 MB takes a moment, so it is remembered until the exe changes.
	var stamp := _self_stamp()
	if _self_cache.get("stamp", "") == stamp:
		_on_own_hash(str(_self_cache.get("hash", "")), newest, list)
		return
	_run_thread(_hash_file.bind(_self_path()), _on_own_hash.bind(newest, list))


func _self_stamp() -> String:
	var f := FileAccess.open(_self_path(), FileAccess.READ)
	var size := f.get_length() if f != null else -1
	return "%s|%d|%d" % [_self_path(), size, FileAccess.get_modified_time(_self_path())]


# Runs on a thread.
static func _hash_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return _sha256(f) if f != null else ""


func _on_own_hash(hash: String, newest: Dictionary, list: Array) -> void:
	if hash != "" and _self_cache.get("hash", "") != hash:
		_self_cache = {"stamp": _self_stamp(), "hash": hash}
		_save_settings()
	if hash == "" or hash == str(newest.get("digest", "")).substr(7).to_lower():
		_pick_game(list)
		return
	state = State.DOWNLOADING
	_stop_countdown()
	_pending = list
	_set_status("Updating the launcher...", GOLD)
	_reset_progress()
	_update_play()
	if _self_download == null:
		_self_download = HTTPRequest.new()
		_self_download.use_threads = true
		_self_download.download_chunk_size = 1 << 20
		_self_download.request_completed.connect(_on_self_downloaded.bind(newest))
		add_child(_self_download)
	_dl = _self_download
	_dl_size = int(newest.get("size", 0))
	_dl_part = _self_path() + ".new"
	_self_download.download_file = _dl_part
	var err := _self_download.request(newest.get("browser_download_url", ""), ["User-Agent: HareHex-Launcher"])
	if err != OK:
		_self_update_failed("couldn't start the download (error %d)" % err)


func _on_self_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, newest: Dictionary) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_self_update_failed(_network_problem(result) if result != HTTPRequest.RESULT_SUCCESS else "HTTP %d" % code)
		return
	state = State.VERIFYING
	_bar.value = 100.0
	_set_status("Checking the new launcher...", GOLD)
	_detail.text = ""
	_run_thread(_verify.bind(_dl_part, int(newest.get("size", -1)), str(newest.get("digest", ""))), _on_self_verified)


func _on_self_verified(problem: String) -> void:
	if problem != "":
		_self_update_failed(problem)
		return
	var own := _self_path()
	var old := own + ".old"
	DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(own, old) != OK:
		_self_update_failed("couldn't move the old launcher aside")
		return
	if DirAccess.rename_absolute(own + ".new", own) != OK:
		DirAccess.rename_absolute(old, own)
		_self_update_failed("couldn't put the new launcher in place")
		return
	_set_status("Restarting the launcher...", GOLD)
	var args := OS.get_cmdline_args()
	args.append("--")
	args.append_array(OS.get_cmdline_user_args())
	args.append("--self-updated")
	if OS.create_process(own, args) <= 0:
		# The new launcher is in place for next time; this one carries on.
		_self_update_failed("couldn't start the new launcher")
		return
	get_tree().quit()


# Not being able to update the launcher never stops anyone playing: note it and go on to the game.
func _self_update_failed(why: String) -> void:
	print("[launcher] Couldn't update the launcher: ", why)
	DirAccess.remove_absolute(_self_path() + ".new")
	_bar.visible = false
	_dl = null
	_pick_game(_pending)


# The .old left by an update. Right after a swap the old launcher may still be closing, so try a few times.
func _remove_old_launcher() -> void:
	var old := _self_path() + ".old"
	if not OS.has_feature("template"):
		return
	for i in 20:
		if not FileAccess.file_exists(old) or DirAccess.remove_absolute(old) == OK:
			return
		await get_tree().create_timer(0.5).timeout


# --- Playing ------------------------------------------------------------------------------------

func _ready_to_play(text: String, updated: bool) -> void:
	state = State.READY
	_bar.visible = false
	_detail.text = "Your saves are kept between versions." if updated else ""
	_set_status(text, GREEN)
	_update_play()
	if auto_start and _main.visible:
		countdown = COUNTDOWN


func _launch() -> void:
	countdown = -1.0
	if not FileAccess.file_exists(_exe_path()):
		_fail("The game isn't installed yet.")
		return
	print("[launcher] Starting ", _exe_path())
	var pid := OS.create_process(_exe_path(), [])
	if pid <= 0:
		_set_status("Couldn't start the game.", RED)
		_update_play()
		return
	get_tree().quit()


func _stop_countdown() -> void:
	countdown = -1.0
	_update_play()


func _fail(text: String) -> void:
	state = State.FAILED
	_bar.visible = false
	_retry.visible = true
	_set_status(text, RED)
	if not installed.is_empty() and FileAccess.file_exists(_exe_path()):
		_detail.text = "You can still play %s." % installed.get("tag", "the installed version")
	_update_play()


# --- Files --------------------------------------------------------------------------------------

func _pick_install_dir() -> String:
	var forced := _arg("--install-dir", "")
	if forced != "":
		return forced
	# Next to the launcher when exported (easy to find), else in its user folder.
	if OS.has_feature("template"):
		var beside := OS.get_executable_path().get_base_dir().path_join("game")
		if _writable(beside):
			return beside
	return OS.get_user_data_dir().path_join("game")


func _writable(dir: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var probe := dir.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func _part_path() -> String:
	return install_dir.path_join("download.part")


func _exe_path() -> String:
	return install_dir.path_join(str(installed.get("dir", ""))).path_join(str(installed.get("exe", "")))


func _folder_for(tag: String) -> String:
	var out := ""
	for c in tag:
		out += c if (c.is_valid_identifier() or c in "0123456789.-") else "_"
	return out if out != "" else "game"


func _read_installed() -> Dictionary:
	var f := FileAccess.open(install_dir.path_join("installed.json"), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _write_installed() -> void:
	var f := FileAccess.open(install_dir.path_join("installed.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(installed, "\t"))


# Removes version folders we unpacked earlier (they hold MARKER) apart from the current one.
# A folder still in use (the old game running) stays until the next launch.
func _clean_old_versions() -> void:
	var dir := DirAccess.open(install_dir)
	if dir == null:
		return
	for sub in dir.get_directories():
		var path := install_dir.path_join(sub)
		if sub == installed.get("dir", ""):
			continue
		if sub.ends_with(".tmp") or FileAccess.file_exists(path.path_join(MARKER)):
			_remove_tree(path)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _run_thread(work: Callable, done: Callable) -> void:
	_thread = Thread.new()
	_thread.start(func():
		var result = work.call()
		_finish_thread.call_deferred(done, result))


func _finish_thread(done: Callable, result) -> void:
	_thread.wait_to_finish()
	_thread = null
	done.call(result)


# --- Settings and arguments ---------------------------------------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		auto_start = bool(cfg.get_value("launcher", "auto_start", true))
		project_dir = str(cfg.get_value("launcher", "project_dir", ""))
		var cache = cfg.get_value("launcher", "self", {})
		_self_cache = cache if cache is Dictionary else {}


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("launcher", "auto_start", auto_start)
	if project_dir != "":
		cfg.set_value("launcher", "project_dir", project_dir)
	if not _self_cache.is_empty():
		cfg.set_value("launcher", "self", _self_cache)
	cfg.save(SETTINGS_PATH)


# --- Developer: the release panel ---------------------------------------------------------------

static func _is_project(dir: String) -> bool:
	return dir != "" and FileAccess.file_exists(dir.path_join("tools/release.ps1"))


# The saved folder, else the project this launcher was built in (it runs from <project>/build) or
# runs from (the editor, res:// = <project>/launcher). Testers have none of these.
func _find_project() -> String:
	if _is_project(project_dir):
		return project_dir
	var here := OS.get_executable_path().get_base_dir() if OS.has_feature("template") \
			else ProjectSettings.globalize_path("res://").trim_suffix("/")
	return here.get_base_dir() if _is_project(here.get_base_dir()) else ""


func _pick_project() -> void:
	var picker := FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.use_native_dialog = true
	picker.title = "Pick the Hare & Hex project folder"
	picker.dir_selected.connect(func(dir: String):
		if _is_project(dir):
			project_dir = dir
			_save_settings()
			_release.project_dir = dir
			_release_button.visible = true
			_set_status("Release panel on: %s" % dir, GREEN)
		else:
			_set_status("That folder has no tools/release.ps1.", RED))
	add_child(picker)
	picker.popup_centered(Vector2i(640, 420))


func _show_release(on: bool) -> void:
	_stop_countdown()
	_main.visible = not on
	_release.visible = on
	_release_button.visible = not on   # the panel has its own BACK
	if on:
		_release.open()


func _on_release_finished(ok: bool, dry_run: bool) -> void:
	_close_warned = false
	if ok and not dry_run:
		# GitHub takes a moment to list it; then install it here too, like a tester would.
		await get_tree().create_timer(2.0).timeout
		_check()


func _arg(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


# --- UI -----------------------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0b0c12")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)

	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _plate_style())
	margin.add_child(plate)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	plate.add_child(col)

	# Header: the hare logo, the title and the installed version.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var logo := TextureRect.new()
	logo.texture = preload("res://icon.png")
	logo.custom_minimum_size = Vector2(72, 72)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(logo)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", -4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := _label("Hare & Hex", NUMBER_FONT, 46, GOLD)
	title.add_theme_color_override("font_shadow_color", LIP)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	titles.add_child(title)
	titles.add_child(_label("LAUNCHER", LABEL_FONT, 12, MUTED))
	_version = _label("", LABEL_FONT, 12, MUTED)
	_version.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_version)
	_release_button = _button("RELEASE", false)
	_release_button.custom_minimum_size = Vector2(0, 30)
	_release_button.add_theme_font_size_override("font_size", 20)
	_release_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_release_button.visible = project_dir != ""
	_release_button.pressed.connect(func(): _show_release(not _release.visible))
	head.add_child(_release_button)

	# Everything under the header: the player's view, or the release panel in its place.
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_main)
	_release = ReleasePanel.new()
	_release.project_dir = project_dir
	_release.visible = false
	col.add_child(_release)
	_release.build(self)
	_release.closed.connect(_show_release.bind(false))
	_release.finished.connect(_on_release_finished)

	# Status, progress bar and its detail line.
	_status = _label("", LABEL_FONT, 17, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # the network problems run long
	_main.add_child(_status)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 12)
	_bar.add_theme_stylebox_override("background", _flat(TRACK))
	_bar.add_theme_stylebox_override("fill", _flat(GOLD))
	_bar.visible = false
	_main.add_child(_bar)
	_detail = _label("", NUMBER_FONT, 20, MUTED)
	_main.add_child(_detail)

	# What's new in the release.
	_notes_title = _label("", LABEL_FONT, 12, GOLD)
	_main.add_child(_notes_title)
	var well := PanelContainer.new()
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.add_theme_stylebox_override("panel", _flat(Color(0.04, 0.045, 0.07, 0.8), 8))
	_main.add_child(well)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = false
	_notes.scroll_active = true
	_notes.selection_enabled = true
	_notes.add_theme_font_override("normal_font", LABEL_FONT)
	_notes.add_theme_font_size_override("normal_font_size", 13)
	_notes.add_theme_color_override("default_color", INK)
	well.add_child(_notes)

	# Bottom row: auto start, retry, play.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_main.add_child(row)
	_auto = CheckBox.new()
	_auto.text = "Start the game automatically"
	_auto.button_pressed = auto_start
	_auto.add_theme_font_override("font", LABEL_FONT)
	_auto.add_theme_font_size_override("font_size", 13)
	_auto.add_theme_color_override("font_color", MUTED)
	_auto.add_theme_color_override("font_hover_color", INK)
	_auto.add_theme_color_override("font_pressed_color", INK)
	_auto.add_theme_color_override("checkbox_checked_color", GOLD)
	_auto.add_theme_color_override("checkbox_unchecked_color", MUTED)
	_auto.toggled.connect(func(on: bool):
		auto_start = on
		_save_settings()
		if not on:
			_stop_countdown())
	_auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_auto)
	_retry = _button("RETRY", false)
	_retry.pressed.connect(_check)
	_retry.visible = false
	row.add_child(_retry)
	_play = _button("PLAY", true)
	_play.custom_minimum_size = Vector2(150, 44)
	_play.pressed.connect(_launch)
	row.add_child(_play)


func _show_installed() -> void:
	_version.text = "Installed: %s" % installed.get("tag", "none")


func _show_notes(r: Dictionary) -> void:
	var date := str(r.get("published_at", "")).substr(0, 10)
	var name := str(r.get("name", "")).strip_edges()
	if name == "":
		name = str(r.get("tag_name", ""))
	_notes_title.text = ("WHAT'S NEW · %s · %s" % [name, date]).to_upper()
	var lines := PackedStringArray()
	for line in str(r.get("body", "")).replace("\r", "").split("\n"):
		var l := line.strip_edges(false, true).replace("**", "").replace("__", "")
		var bare := l.strip_edges()
		if bare.begins_with("#"):
			l = bare.lstrip("# ").to_upper()
		elif bare.begins_with("- ") or bare.begins_with("* "):
			l = l.substr(0, l.length() - bare.length()) + "•  " + bare.substr(2)
		lines.append(l)
	var text := "\n".join(lines).strip_edges()
	_notes.text = text if text != "" else "No notes for this release."


func _update_play() -> void:
	var can := state in [State.READY, State.FAILED] and not installed.is_empty() and FileAccess.file_exists(_exe_path())
	_play.disabled = not can
	if countdown <= 0.0:
		_play.text = "PLAY"


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	print("[launcher] ", text)


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96, 44)
	b.add_theme_font_override("font", NUMBER_FONT)
	b.add_theme_font_size_override("font_size", 28)
	var base := GOLD if primary else Color("2a3048")
	var ink := Color("1a1408") if primary else INK
	b.add_theme_stylebox_override("normal", _button_style(base))
	b.add_theme_stylebox_override("hover", _button_style(base.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", _button_style(base.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", _button_style(Color("2a2e3d")))
	for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state_name, ink)
	b.add_theme_color_override("font_disabled_color", Color("5d6380"))
	return b


func _plate_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = FILL
	s.border_color = EDGE_GOLD
	s.set_border_width_all(1)
	s.border_width_top = 3
	s.border_width_bottom = 4
	s.set_corner_radius_all(4)
	s.set_content_margin_all(20)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 8
	return s


func _button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_width_bottom = 3
	s.border_color = color.darkened(0.45)
	s.set_corner_radius_all(3)
	s.content_margin_left = 16
	s.content_margin_right = 16
	return s


func _flat(color: Color, margin := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	s.set_content_margin_all(margin)
	return s


static func _mb(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0)


static func _duration(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60] if s >= 60 else "%d s" % s
