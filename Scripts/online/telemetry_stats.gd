# telemetry_stats.gd
class_name TelemetryStats extends RefCounted

# Sums up the testers' telemetry (telemetry.gd sends it, SnapshotServer stores it as one JSON line per event
# under <data>/events/YYYY-MM-DD.jsonl) into the numbers the /stats page shows: which modes get played,
# finished and replayed, where runs end, which fights beat people, how far the tutorial gets, frame rates,
# crashes, and one row per tester. Pure functions, so the server, a tool and the checks can all use them.

# Event names the game sends; the service stores nothing else.
const EVENTS := ["session_start", "session_end", "unclean_exit", "menu", "run_start", "fight", "run_end", "tutorial_step", "endless"]
const MODES := ["tutorial", "campaign", "free", "async", "lobby"]
const MODE_NAMES := {"tutorial": "Tutorial", "campaign": "Campaign", "free": "Free Play", "async": "Async PvP", "lobby": "Lobby"}
const MIN_FIGHTS := 3   # a fight needs this many plays before it counts as one of the hardest

# Every event from the last `days` days in `dir` (the service's events folder), oldest first.
static func load_dir(dir: String, days := 30) -> Array:
	var out: Array = []
	var root := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(root):
		return out
	var cutoff := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - days * 86400)
	var files := Array(DirAccess.get_files_at(root)).filter(func(f): return f.ends_with(".jsonl") and f.get_basename() >= cutoff)
	files.sort()
	for f in files:
		for line in FileAccess.get_file_as_string(root + "/" + f).split("\n", false):
			var e = JSON.parse_string(line)
			if e is Dictionary:
				out.append(e)
	return out

# The numbers for the stats page (also served as JSON by GET /v1/stats).
static func summarize(events: Array) -> Dictionary:
	var players := {}    # pid -> per-tester row
	var sessions := {}   # sid -> {pid, first, last}
	var runs := {}       # run id -> {start, end, pid}
	var fights := {}     # "mode|level|round" -> {mode, level, round, n, won, prep}
	var steps := {}      # tutorial step -> {title, players, secs, timed}
	var menu := {}       # screen -> {opens, players}
	var unclean: Array = []
	var versions := {}
	var gpus := {}       # GPU -> {players, fps, fps_n}
	var first_t := 0
	var last_t := 0
	for x in events:
		if not x is Dictionary:
			continue
		var e: Dictionary = x
		var p: Dictionary = e.get("p", {}) if e.get("p") is Dictionary else {}
		var pid := str(e.get("pid", ""))
		var sid := str(e.get("sid", ""))
		var t := int(e.get("t", 0))
		if t > 0:
			first_t = t if first_t == 0 else mini(first_t, t)
			last_t = maxi(last_t, t)
		var pl: Dictionary = players.get(pid, {})
		if pl.is_empty():
			pl = {"pid": pid, "first": t, "last": t, "sessions": {}, "runs": 0, "modes": {}, "version": "", "os": "", "gpu": "", "fps": 0.0, "fps_n": 0}
			players[pid] = pl
		pl.first = mini(int(pl.first), t) if t > 0 else pl.first
		pl.last = maxi(int(pl.last), t)
		if str(e.get("v", "")) != "":
			pl.version = str(e.v)
		if sid != "":
			pl.sessions[sid] = true
			var s: Dictionary = sessions.get(sid, {"pid": pid, "first": t, "last": t})
			s.first = mini(int(s.first), t)
			s.last = maxi(int(s.last), t)
			if str(e.get("e", "")) == "session_end":
				s["secs"] = int(p.get("secs", 0))
			sessions[sid] = s
		match str(e.get("e", "")):
			"session_start":
				var v := str(e.get("v", "dev"))
				versions[v] = int(versions.get(v, 0)) + 1
				pl.os = str(p.get("os", ""))
				pl.gpu = str(p.get("gpu", ""))
			"unclean_exit":
				unclean.append(p)
			"menu":
				var name := str(p.get("screen", "?"))
				var m: Dictionary = menu.get(name, {"opens": 0, "players": {}})
				m.opens += 1
				m.players[pid] = true
				menu[name] = m
			"run_start":
				var r: Dictionary = runs.get(str(p.get("run", "")), {"pid": pid})
				r["start"] = p
				runs[str(p.get("run", ""))] = r
			"run_end":
				var r: Dictionary = runs.get(str(p.get("run", "")), {"pid": pid})
				r["end"] = p   # endless async runs end twice: the last one counts
				runs[str(p.get("run", ""))] = r
				var fps := float(p.get("fps_avg", 0.0))
				if fps > 0.0:
					pl.fps += fps
					pl.fps_n += 1
			"fight":
				var key := "%s|%s|%d" % [p.get("mode", "?"), p.get("level", ""), int(p.get("round", 0))]
				var f: Dictionary = fights.get(key, {"mode": str(p.get("mode", "?")), "level": str(p.get("level", "")), "round": int(p.get("round", 0)), "n": 0, "won": 0, "prep": 0.0})
				f.n += 1
				if bool(p.get("won", false)):
					f.won += 1
				f.prep += float(p.get("prep_secs", 0.0))
				fights[key] = f
			"tutorial_step":
				var i := int(p.get("step", 0))
				var st: Dictionary = steps.get(i, {"title": str(p.get("title", "")), "players": {}, "secs": 0.0, "timed": 0})
				st.players[pid] = true
				steps[i] = st
				if i > 0 and p.has("prev_secs"):   # time spent on the step before this one
					var prev: Dictionary = steps.get(i - 1, {"title": "", "players": {}, "secs": 0.0, "timed": 0})
					prev.secs += float(p.prev_secs)
					prev.timed += 1
					steps[i - 1] = prev

	# --- modes, campaign levels and where runs end ---
	var modes := {}
	var levels := {}
	for m in MODES:
		modes[m] = {"runs": 0, "players": {}, "per_player": {}, "won": 0, "lost": 0, "quit": 0, "unknown": 0, "placed": 0, "place_sum": 0, "secs": 0.0, "timed": 0, "rounds": 0, "ends": {}}
	for id in runs:
		var r: Dictionary = runs[id]
		if not r.has("start"):
			continue
		var start: Dictionary = r.start
		var m := str(start.get("mode", "free"))
		if not modes.has(m):
			continue
		var mm: Dictionary = modes[m]
		var pid := str(r.pid)
		mm.runs += 1
		mm.players[pid] = true
		mm.per_player[pid] = int(mm.per_player.get(pid, 0)) + 1
		if players.has(pid):
			players[pid].runs += 1
			players[pid].modes[m] = int(players[pid].modes.get(m, 0)) + 1
		var end: Dictionary = r.get("end", {})
		var result := str(end.get("result", "unknown"))
		var round := int(end.get("round", start.get("round", 0)))
		match result:
			"won": mm.won += 1
			"lost", "disconnected": mm.lost += 1
			"quit": mm.quit += 1
			"placed":
				mm.placed += 1
				mm.place_sum += int(end.get("place", 0))
			_: mm.unknown += 1
		if not end.is_empty():
			mm.secs += float(end.get("secs", 0.0))
			mm.timed += 1
			mm.rounds += round
		if result in ["lost", "quit", "unknown", "disconnected"]:
			var why := "lost" if result == "disconnected" else result
			var at: Dictionary = mm.ends.get(round, {"lost": 0, "quit": 0, "unknown": 0})
			at[why] += 1
			mm.ends[round] = at
		if m == "campaign":
			var lid := str(start.get("level", "?"))
			var lv: Dictionary = levels.get(lid, {"level": lid, "chapter": str(start.get("chapter", "")), "starts": 0, "players": {}, "won": 0, "lost": 0, "quit": 0, "unknown": 0, "secs": 0.0, "timed": 0, "ends": {}})
			lv.starts += 1
			lv.players[pid] = true
			if result in ["won", "lost", "quit"]:
				lv[result] += 1
			else:
				lv.unknown += 1
			if not end.is_empty():
				lv.secs += float(end.get("secs", 0.0))
				lv.timed += 1
			if result in ["lost", "quit", "unknown"]:
				var at: Dictionary = lv.ends.get(round, {"lost": 0, "quit": 0, "unknown": 0})
				at[result] += 1
				lv.ends[round] = at
			levels[lid] = lv

	var mode_rows: Array = []
	for m in MODES:
		var mm: Dictionary = modes[m]
		var repeat := 0
		for pid in mm.per_player:
			if int(mm.per_player[pid]) >= 2:
				repeat += 1
		mode_rows.append({
			"mode": m, "name": MODE_NAMES[m], "runs": mm.runs, "players": mm.players.size(), "repeat_players": repeat,
			"won": mm.won, "lost": mm.lost, "quit": mm.quit, "unknown": mm.unknown, "placed": mm.placed,
			"win_rate": _ratio(mm.won, mm.won + mm.lost), "quit_rate": _ratio(mm.quit + mm.unknown, mm.runs),
			"avg_place": _ratio(mm.place_sum, mm.placed), "avg_minutes": _ratio(mm.secs, mm.timed) / 60.0,
			"avg_round": _ratio(mm.rounds, mm.timed), "ends": _ends_list(mm.ends),
		})

	var level_rows: Array = []
	var level_ids := levels.keys()
	level_ids.sort()
	for lid in level_ids:
		var lv: Dictionary = levels[lid]
		level_rows.append({"level": lid, "chapter": lv.chapter, "starts": lv.starts, "players": lv.players.size(), "won": lv.won, "lost": lv.lost,
			"quit": lv.quit, "unknown": lv.unknown, "clear_rate": _ratio(lv.won, lv.starts), "avg_minutes": _ratio(lv.secs, lv.timed) / 60.0, "ends": _ends_list(lv.ends)})

	# --- the fights people lose most, and the rounds they think longest about ---
	var fight_rows: Array = []
	for key in fights:
		var f: Dictionary = fights[key]
		fight_rows.append({"mode": f.mode, "level": f.level, "round": f.round, "fights": f.n, "win_rate": _ratio(f.won, f.n), "avg_prep": _ratio(f.prep, f.n)})
	var hardest := fight_rows.filter(func(f): return int(f.fights) >= MIN_FIGHTS)
	hardest.sort_custom(func(a, b): return a.win_rate < b.win_rate or (a.win_rate == b.win_rate and a.fights > b.fights))
	var slowest := fight_rows.filter(func(f): return int(f.fights) >= MIN_FIGHTS)
	slowest.sort_custom(func(a, b): return a.avg_prep > b.avg_prep)

	# --- the tutorial funnel ---
	var funnel: Array = []
	var step_ids := steps.keys()
	step_ids.sort()
	var top := 0
	for i in step_ids:
		top = maxi(top, steps[i].players.size())
	var quits := {}   # tutorial step -> runs left there
	for id in runs:
		var r: Dictionary = runs[id]
		var end: Dictionary = r.get("end", {})
		if str(r.get("start", {}).get("mode", "")) == "tutorial" and str(end.get("result", "unknown")) != "won" and end.has("tutorial_step"):
			var s := int(end.tutorial_step)
			quits[s] = int(quits.get(s, 0)) + 1
	for i in step_ids:
		var st: Dictionary = steps[i]
		funnel.append({"step": int(i) + 1, "title": st.title, "players": st.players.size(), "share": _ratio(st.players.size(), top),
			"avg_secs": _ratio(st.secs, st.timed), "left_here": int(quits.get(int(i), 0))})

	# --- testers ---
	var play_secs := {}   # pid -> seconds played (session_end, else first to last event of the session)
	var total_secs := 0.0
	for sid in sessions:
		var s: Dictionary = sessions[sid]
		var secs := float(s.get("secs", int(s.last) - int(s.first)))
		play_secs[s.pid] = float(play_secs.get(s.pid, 0.0)) + secs
		total_secs += secs
	var player_rows: Array = []
	var week_ago := last_t - 7 * 86400
	var new_week := 0
	for pid in players:
		var pl: Dictionary = players[pid]
		if pid == "":
			continue
		if int(pl.first) >= week_ago:
			new_week += 1
		var fps := _ratio(pl.fps, pl.fps_n)
		player_rows.append({"pid": pid, "first": int(pl.first), "last": int(pl.last), "sessions": pl.sessions.size(), "runs": pl.runs,
			"minutes": float(play_secs.get(pid, 0.0)) / 60.0, "modes": pl.modes, "version": pl.version, "os": pl.os, "gpu": pl.gpu, "fps": fps})
		if pl.gpu != "":
			var g: Dictionary = gpus.get(pl.gpu, {"gpu": pl.gpu, "players": 0, "fps": 0.0, "fps_n": 0})
			g.players += 1
			if fps > 0.0:
				g.fps += fps
				g.fps_n += 1
			gpus[pl.gpu] = g
	player_rows.sort_custom(func(a, b): return a.last > b.last)
	var gpu_rows: Array = []
	for g in gpus.values():
		gpu_rows.append({"gpu": g.gpu, "players": g.players, "fps": _ratio(g.fps, g.fps_n)})
	gpu_rows.sort_custom(func(a, b): return a.fps < b.fps)

	var crash_where := {}
	for c in unclean:
		var where := "Main menu"
		if str(c.get("where", "")) == "run":
			where = "%s, round %d, %s" % [MODE_NAMES.get(str(c.get("mode", "")), "Run"), int(c.get("round", 0)), str(c.get("phase", "?"))]
		crash_where[where] = int(crash_where.get(where, 0)) + 1
	var crash_rows: Array = []
	for w in crash_where:
		crash_rows.append({"where": w, "count": crash_where[w]})
	crash_rows.sort_custom(func(a, b): return a.count > b.count)

	var menu_rows: Array = []
	for name in menu:
		menu_rows.append({"screen": name, "opens": menu[name].opens, "players": menu[name].players.size()})
	menu_rows.sort_custom(func(a, b): return a.opens > b.opens)

	return {
		"overview": {"players": player_rows.size(), "new_this_week": new_week, "sessions": sessions.size(), "runs": runs.size(),
			"hours": total_secs / 3600.0, "avg_session_minutes": _ratio(total_secs, sessions.size()) / 60.0, "events": events.size(),
			"unclean_exits": unclean.size(), "from": first_t, "to": last_t, "versions": versions},
		"modes": mode_rows, "levels": level_rows, "hardest": hardest.slice(0, 12), "slowest_prep": slowest.slice(0, 8),
		"tutorial": funnel, "players": player_rows, "gpus": gpu_rows, "crashes": crash_rows, "menu": menu_rows,
	}

static func _ratio(a: float, b: float) -> float:
	return a / b if b > 0 else 0.0

# {round: {lost, quit, unknown}} -> rows sorted by round
static func _ends_list(ends: Dictionary) -> Array:
	var out: Array = []
	var rounds := ends.keys()
	rounds.sort()
	for r in rounds:
		var at: Dictionary = ends[r]
		out.append({"round": int(r), "lost": at.lost, "quit": at.quit, "unknown": at.unknown, "total": int(at.lost) + int(at.quit) + int(at.unknown)})
	return out

# --- the page ---------------------------------------------------------------------------------------

# The stats page: plain HTML (no scripts), dark like the game's HUD.
static func html(s: Dictionary, days := 30) -> String:
	var o: Dictionary = s.overview
	var h := PackedStringArray()
	h.append("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Tester Stats</title><style>")
	h.append(":root{--bg:#0b0c12;--plate:#171923;--edge:#2a2e3d;--ink:#e8e6df;--muted:#9a9cab;--gold:#e8b04a;--red:#e0605a;--green:#6cc48a;--blue:#6cc4ff}")
	h.append("body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 system-ui,sans-serif}main{max-width:1100px;margin:0 auto;padding:20px 16px 60px}")
	h.append("h1{color:var(--gold);font-size:26px;margin:0 0 4px}h2{color:var(--gold);font-size:15px;letter-spacing:.08em;text-transform:uppercase;margin:32px 0 6px}")
	h.append("p.note{color:var(--muted);margin:0 0 10px;font-size:13px}.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:8px;margin-top:14px}")
	h.append(".tile{background:var(--plate);border-top:2px solid var(--gold);padding:10px 12px}.tile b{display:block;font-size:22px}.tile span{color:var(--muted);font-size:12px}")
	h.append(".wrap{overflow-x:auto}table{border-collapse:collapse;width:100%;background:var(--plate)}th,td{padding:6px 10px;text-align:left;border-bottom:1px solid var(--edge);white-space:nowrap}")
	h.append("th{color:var(--muted);font-weight:600;font-size:12px}td.n{text-align:right;font-variant-numeric:tabular-nums}.bad{color:var(--red)}.good{color:var(--green)}")
	h.append(".bar{display:inline-block;height:9px;background:var(--gold);vertical-align:middle;margin-right:6px}.bar.red{background:var(--red)}.bar.blue{background:var(--blue)}.empty{color:var(--muted);padding:10px;background:var(--plate)}")
	h.append("</style></head><body><main>")
	h.append("<h1>Hare &amp; Hex tester stats</h1><p class=\"note\">The last %d days%s. Anonymous: each tester is a random id made on their first launch (shown in their Settings &gt; Privacy).</p>" % [days,
		(", " + _date(int(o.from)) + " to " + _date(int(o.to))) if int(o.from) > 0 else ""])
	h.append("<div class=\"tiles\">")
	for t in [[o.players, "testers"], [o.new_this_week, "new in the last week"], [o.sessions, "sessions"], [o.runs, "runs"], ["%.1f" % o.hours, "hours played"],
			["%.0f min" % o.avg_session_minutes, "average session"], [o.unclean_exits, "crashes or force quits"]]:
		h.append("<div class=\"tile\"><b>%s</b><span>%s</span></div>" % [str(t[0]), t[1]])
	h.append("</div>")

	h.append("<h2>Modes</h2><p class=\"note\">Played by how many testers, how often they come back to it (2+ runs), and how runs end. Left = quit to the menu, closed the game or crashed partway.</p>")
	var rows: Array = []
	for m in s.modes:
		if int(m.runs) == 0:
			rows.append([m.name, "0", "", "", "", "", "", "", ""])
			continue
		var result := ("%d won · %d lost" % [m.won, m.lost]) if m.mode != "lobby" else ("avg place %.1f" % m.avg_place)
		rows.append([m.name, str(m.runs), str(m.players), "%d (%s)" % [m.repeat_players, _pct(_ratio(m.repeat_players, m.players))], result,
			_pct(m.win_rate) if m.mode != "lobby" else "", _bar(m.quit_rate, "red") + _pct(m.quit_rate), "%.1f" % m.avg_round, "%.0f min" % m.avg_minutes])
	h.append(_table(["Mode", "Runs", "Testers", "Came back", "Results", "Win rate", "Left partway", "Avg round reached", "Avg length"], rows, [1, 2, 3, 5, 7, 8]))

	h.append("<h2>Where runs end</h2><p class=\"note\">The rounds where runs were lost or left, per mode. A spike is where people get stuck.</p>")
	var any_end := false
	for m in s.modes:
		if (m.ends as Array).is_empty():
			continue
		any_end = true
		h.append("<p class=\"note\"><b style=\"color:var(--ink)\">%s</b></p>" % m.name)
		h.append(_ends_table(m.ends))
	if not any_end:
		h.append("<div class=\"empty\">No runs lost or left yet.</div>")

	h.append("<h2>Campaign levels</h2>")
	rows = []
	for l in s.levels:
		var worst := ""
		var most := 0
		for e in l.ends:
			if int(e.total) > most:
				most = int(e.total)
				worst = "wave %d (%d)" % [e.round, e.total]
		rows.append([l.level, str(l.starts), str(l.players), _bar(l.clear_rate) + _pct(l.clear_rate), str(l.lost), str(l.quit + l.unknown), worst, "%.0f min" % l.avg_minutes])
	h.append(_table(["Level", "Attempts", "Testers", "Cleared", "Lost", "Left", "Most runs end at", "Avg length"], rows, [1, 2, 4, 5, 7]))

	h.append("<h2>Hardest fights</h2><p class=\"note\">Lowest win rate, fought at least %d times.</p>" % MIN_FIGHTS)
	rows = []
	for f in s.hardest:
		rows.append([MODE_NAMES.get(f.mode, f.mode), _esc(f.level), str(f.round), str(f.fights), _bar(f.win_rate, "red" if f.win_rate < 0.5 else "") + _pct(f.win_rate)])
	h.append(_table(["Mode", "Level", "Round", "Fights", "Win rate"], rows, [2, 3]))

	h.append("<h2>Longest thinking</h2><p class=\"note\">Average seconds spent in prep before these fights. Free play has a 30 s timer, campaign and async PvP wait for Start fight.</p>")
	rows = []
	for f in s.slowest_prep:
		rows.append([MODE_NAMES.get(f.mode, f.mode), _esc(f.level), str(f.round), str(f.fights), "%.0f s" % f.avg_prep])
	h.append(_table(["Mode", "Level", "Round", "Fights", "Avg prep"], rows, [2, 3, 4]))

	h.append("<h2>Tutorial</h2><p class=\"note\">How many testers reached each step, how long they spent on it, and how many tutorial runs ended there without finishing.</p>")
	rows = []
	for st in s.tutorial:
		rows.append([str(st.step), _esc(st.title), str(st.players), _bar(st.share, "blue") + _pct(st.share), "%.0f s" % st.avg_secs if st.avg_secs > 0 else "", str(st.left_here) if st.left_here > 0 else ""])
	h.append(_table(["Step", "Title", "Testers", "Reached", "Time on step", "Left here"], rows, [0, 2, 4, 5]))

	h.append("<h2>Stability and frame rate</h2>")
	rows = []
	for c in s.crashes:
		rows.append([c.where, str(c.count)])
	h.append("<p class=\"note\">Sessions that ended without the game closing normally (a crash, a freeze that was force-quit, or the PC turned off), and where they were.</p>")
	h.append(_table(["Where", "Times"], rows, [1]))
	rows = []
	for g in s.gpus:
		rows.append([g.gpu, str(g.players), ("<span class=\"bad\">%.0f</span>" if g.fps > 0 and g.fps < 30 else "%.0f") % g.fps if g.fps > 0 else ""])
	h.append("<p class=\"note\" style=\"margin-top:14px\">Average frame rate in runs, by graphics card (lowest first).</p>")
	h.append(_table(["Graphics card", "Testers", "Avg FPS"], rows, [1, 2]))

	h.append("<h2>Menu screens</h2>")
	rows = []
	for m in s.menu:
		rows.append([m.screen, str(m.opens), str(m.players)])
	h.append(_table(["Screen", "Opened", "Testers"], rows, [1, 2]))

	h.append("<h2>Testers</h2>")
	rows = []
	for p in s.players:
		var modes := PackedStringArray()
		for m in MODES:
			if p.modes.has(m):
				modes.append("%s %d" % [MODE_NAMES[m], p.modes[m]])
		rows.append([(p.pid as String).left(8), _date(p.first), _date(p.last), str(p.sessions), str(p.runs), "%.0f" % p.minutes, ", ".join(modes), _esc(p.version), "%.0f" % p.fps if p.fps > 0 else "", _esc(p.os)])
	h.append(_table(["Id", "First seen", "Last seen", "Sessions", "Runs", "Minutes", "Modes", "Build", "FPS", "OS"], rows, [3, 4, 5, 8]))

	var vers := PackedStringArray()
	for v in o.versions:
		vers.append("%s (%d)" % [_esc(str(v)), o.versions[v]])
	h.append("<p class=\"note\" style=\"margin-top:24px\">Builds seen: %s. %d events.</p></main></body></html>" % [", ".join(vers) if not vers.is_empty() else "none", o.events])
	return "".join(h)

static func _ends_table(ends: Array) -> String:
	var most := 1
	for e in ends:
		most = maxi(most, int(e.total))
	var rows: Array = []
	for e in ends:
		rows.append([str(e.round), _bar(float(e.total) / most, "red") + str(e.total), str(e.lost), str(e.quit), str(e.unknown) if int(e.unknown) > 0 else ""])
	return _table(["Round", "Runs ended", "Lost", "Left", "No end (crash?)"], rows, [2, 3, 4])

# A table; cells are already HTML except the first column, which is escaped. `numeric` columns align right.
static func _table(head: Array, rows: Array, numeric: Array) -> String:
	if rows.is_empty():
		return "<div class=\"empty\">Nothing yet.</div>"
	var h := PackedStringArray(["<div class=\"wrap\"><table><tr>"])
	for i in head.size():
		h.append("<th%s>%s</th>" % [" class=\"n\"" if i in numeric else "", head[i]])
	h.append("</tr>")
	for r in rows:
		h.append("<tr>")
		for i in r.size():
			var cell := str(r[i])
			h.append("<td%s>%s</td>" % [" class=\"n\"" if i in numeric else "", _esc(cell) if i == 0 else cell])
		h.append("</tr>")
	h.append("</table></div>")
	return "".join(h)

static func _bar(ratio: float, kind := "") -> String:
	return "<span class=\"bar %s\" style=\"width:%dpx\"></span>" % [kind, int(clampf(ratio, 0.0, 1.0) * 60.0)]

static func _pct(r: float) -> String:
	return "%d%%" % roundi(r * 100.0)

static func _date(t: int) -> String:
	return Time.get_date_string_from_unix_time(t) if t > 0 else ""

static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
