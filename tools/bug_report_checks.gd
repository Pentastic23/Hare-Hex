# bug_report_checks.gd
# Dev tool, not part of the game: checks the bug report panel (autoload BugReporter,
# Scripts/BugReportUI.gd). It never sends anything: the webhook is pointed at a non-https address,
# so submit() stops before the request. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/bug_report_checks.tscn --fixed-fps 60
# With a window (no --headless) and "-- shots <folder>", it also saves screenshots of the menu and a
# run with the panel open. "-- send" posts ONE real test report to the webhook (see _send_test).

extends Node

var fails := 0

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func frames(n := 2):
	for i in n:
		await get_tree().process_frame

func key(code: Key):
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	get_viewport().push_input(e)
	await frames()
	e = e.duplicate()
	e.pressed = false
	get_viewport().push_input(e)
	await frames()

func _run():
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] == "send":
		await _send_test()
		return
	var shots := args[1] if args.size() > 1 and args[0] == "shots" else ""
	get_tree().root.size = Vector2i(1152, 648)
	var br = BugReporter
	br.url_override = "http://not-sent.invalid"   # never the real webhook
	br.name_cfg = "user://bug_report_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(br.name_cfg))
	SaveGame.path = "user://bug_test_save.json"

	print("--- the button and the panel")
	await frames()
	chk("the BUG button is there and the panel starts folded", br.toggle.visible and not br.panel.visible and not br.is_open)
	var tr: Rect2 = br.toggle.get_global_rect()
	chk("the button sits in the bottom-left corner, on screen", tr.position.x < 20 and tr.end.y < 648 and tr.end.y > 500, str(tr))
	br.toggle.pressed.emit()
	await frames()
	var pr: Rect2 = br.panel.get_global_rect()
	chk("pressing it unfolds the panel above the button, inside the window", br.is_open and br.panel.visible and pr.position.y >= 0 and pr.end.y <= tr.position.y + 1 and pr.end.x <= 1152, str(pr))
	chk("the title field has the focus, so you can type at once", br.typing())
	if shots != "":
		await _shot(shots + "/bug_menu.png")
	br.toggle.pressed.emit()
	await frames()
	chk("pressing it again folds it", not br.is_open and not br.panel.visible and not br.typing())

	print("--- the form")
	br.open_panel()
	br.title_edit.text = ""
	br.description.text = ""
	chk("no title: nothing is sent, and it says why", not br.submit() and br.status_label.text.contains("title") and not br.sending)
	br.title_edit.text = "Units walk through walls"
	chk("no description: nothing is sent", not br.submit() and br.status_label.text.contains("happened"))
	br.description.text = "I dragged a knight and it went through the wall."
	chk("no https webhook: nothing is sent, it says so", not br.submit() and br.status_label.text.contains("set up") and not br.sending)
	br.name_edit.text = "Tester"
	br.severity.select(1)
	br.info_check.button_pressed = true
	br.shot_check.button_pressed = false
	var req: Dictionary = br.build_request()
	var embed: Dictionary = req.payload.embeds[0]
	chk("the report is a Discord embed: severity in the title, tester and game info as fields", embed.title == "[High] Units walk through walls" and embed.fields[0].value == "High" and embed.fields[1].value == "Tester" and embed.fields[2].name == "Game" and embed.color == 0xff8a4c)
	chk("no mentions can be triggered from a report", req.payload.allowed_mentions.parse.is_empty())
	chk("without a screenshot it is plain JSON", req.headers[0] == "Content-Type: application/json" and JSON.parse_string(req.body.get_string_from_utf8()) != null)
	br._shot = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	br.shot_check.button_pressed = true
	req = br.build_request()
	var text: String = req.body.get_string_from_ascii()
	chk("with a screenshot it is multipart: the JSON and the PNG", req.headers[0].begins_with("Content-Type: multipart/form-data; boundary=") and text.contains("name=\"payload_json\"") and text.contains("filename=\"screenshot.png\"") and req.payload.embeds[0].image.url == "attachment://screenshot.png")
	br.description.text = "x".repeat(5000)
	chk("a very long description is cut to fit Discord's limit", (br.build_request().payload.embeds[0].description as String).length() < 4096)
	br.info_check.button_pressed = false
	chk("game info can be left out", br.build_request().payload.embeds[0].fields.size() == 2)
	br._save_name("Tester")
	chk("your name is remembered for next time", br._saved_name() == "Tester")
	br._on_request_completed(HTTPRequest.RESULT_SUCCESS, 204, PackedStringArray(), PackedByteArray())
	chk("a sent report clears the form (not your name) and thanks you", br.title_edit.text == "" and br.description.text == "" and br.name_edit.text == "Tester" and br.status_label.text.begins_with("Sent"))
	br.title_edit.text = "Again"
	br.description.text = "Again"
	chk("then waits a little before the next one", not br.submit() and br.status_label.text.begins_with("Wait"))
	br._cooldown_left = 0.0
	br._on_request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	chk("a failed send keeps your text", br.title_edit.text == "Again" and br.status_label.text.contains("kept"))
	br.close_panel()

	print("--- in a run")
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 5
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	await frames(3)
	var board: Board = main.get_node("Board")
	var dock = main.get_node("UI/RightDock")
	var info: String = br.game_info()
	chk("game info names the mode, round and board", info.contains("Mode: Free play") and info.contains("Round 1") and info.contains("Board ("), info.replace("\n", " | "))
	var u := (load("res://scenes/unit.tscn").instantiate() as Unit)
	board.get_node("Units").add_child(u)
	u.setup(load("res://tres/knight.tres"), 0)
	board.put_on_bench(u, 0)
	br.open_panel()
	await frames()
	if shots != "":
		br.title_edit.text = "Example: a knight walked through the bench"
		br.description.text = "What I did, what I expected, what happened."
		await _shot(shots + "/bug_run.png")
	var dc = main.get_node("DragController")
	dc.dragging = u   # a held unit is what F sells
	br.title_edit.grab_focus()
	await key(KEY_F)
	chk("typing F in the report doesn't sell a unit", is_instance_valid(u) and not u.is_queued_for_deletion() and board.bench[0] == u)
	await key(KEY_ESCAPE)
	chk("Esc closes the report, not into the pause menu", not br.is_open and dock.current != "menu" and not get_tree().paused)
	await key(KEY_ESCAPE)
	chk("with it closed, Esc opens the pause menu as before", dock.current == "menu")
	dock.close_panel()
	get_tree().paused = false
	br.open_panel()
	get_tree().paused = true
	await frames()
	chk("it works while the game is paused", br.is_open and br.process_mode == Node.PROCESS_MODE_ALWAYS)
	get_tree().paused = false
	br.close_panel()
	dc.dragging = u
	await key(KEY_F)
	chk("with it closed, F sells as before", not is_instance_valid(u) or u.is_queued_for_deletion())

	main.queue_free()
	await frames()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(br.name_cfg))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()

func _shot(path: String):
	await frames(4)
	get_viewport().get_texture().get_image().save_png(path)
	print("shot -> ", path)

# "-- send": sends ONE real test report to the configured webhook (bug_report_webhook.txt), from a
# free-play run with a screenshot when there is a window, and prints what the server answered.
# Only run this on purpose: it posts to the Discord channel.
func _send_test():
	get_tree().root.size = Vector2i(1152, 648)
	GameState.run_level = null
	GameState.run_carry = {}
	GameState.next_seed = 5
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Game Manager").prep_time = 9999
	add_child(main)
	await frames(10)
	var br = BugReporter
	br.url_override = ""
	br.name_cfg = "user://bug_report_test.cfg"
	br.open_panel()
	br.title_edit.text = "TEST: bug report panel works"
	br.name_edit.text = "Claude (test send)"
	br.severity.select(4)
	br.description.text = "A test report sent from tools/bug_report_checks (-- send) to check the webhook, the embed, the game info and the screenshot. You can delete this message."
	br.info_check.button_pressed = true
	br.shot_check.button_pressed = true
	print("screenshot bytes: ", br._shot.size())
	if not br.submit():
		print("NOT SENT: ", br.status_label.text)
	else:
		var res: Array = await br.http.request_completed
		await frames()
		print("HTTP result %d, code %d" % [res[0], res[1]])
		print("STATUS: ", br.status_label.text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(br.name_cfg))
	get_tree().quit()
