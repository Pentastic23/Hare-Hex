# roster_checks.gd
# Dev tool, not part of the game: checks the unit roster in main.tscn (Game Manager's unit_pool) and the
# synergy table. Names and body labels are unique, every tag exists, every synergy can be reached, the
# unique (1/1) synergies each have exactly one holder. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/roster_checks.tscn
# Prints PASS/FAIL per check and RESULT at the end.

extends Node

# Units per cost the finished roster has.
const EXPECT := {1: 14, 2: 13, 3: 14, 4: 14, 5: 10}
# How many of each cost carry a unique (1/1) tag.
const EXPECT_UNIQUE := {3: 2, 5: 6}
const EXPECT_TRAITS := {"origin": 11, "class": 16, "unique": 8}   # 35 in all (docs/synergies-v2.md)
const EFFECT_KEYS := ["hp", "ad", "ap", "as", "armor", "mr", "mit", "sunder", "shred", "summon", "vamp", "shield", "regen", "ramp", "ramp_max", "crit", "execute", "revive", "burn", "chill", "dodge", "curse", "range", "kill_heal"]

var fails := 0

func chk(name: String, cond: bool, detail := ""):
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		fails += 1

func _ready():
	_run.call_deferred()

func _run():
	var main = load("res://scenes/main.tscn").instantiate()
	var roster: Array = main.get_node("Game Manager").unit_pool
	main.free()

	var by_cost := {}
	var names := {}
	var labels := {}
	var holders := {}   # tag -> units holding it
	var dup_names: Array = []
	var dup_labels: Array = []
	var bad_stats: Array = []
	var bad_tags: Array = []
	var bad_shape: Array = []
	for x in roster:
		var d := x as UnitData
		by_cost[d.cost] = int(by_cost.get(d.cost, 0)) + 1
		if names.has(d.display_name):
			dup_names.append(d.display_name)
		names[d.display_name] = true
		var lab := d.label()
		if labels.has(lab):
			dup_labels.append("%s/%s" % [labels[lab], d.display_name])
		labels[lab] = d.display_name
		if d.max_health <= 0 or d.attack_damage <= 0 or d.armor < 0 or d.magic_resist < 0 or d.attacks_per_second <= 0 or d.attack_range < 1 or d.move_speed <= 0 or d.max_mana <= 0 or d.start_mana > d.max_mana or lab.length() > 3:
			bad_stats.append(d.display_name)
		var kinds := {"origin": 0, "class": 0, "unique": 0}
		for t in d.tags:
			var key := String(t)
			if not Synergies.DEFS.has(key):
				bad_tags.append("%s:%s" % [d.display_name, key])
				continue
			if not holders.has(key):
				holders[key] = []
			holders[key].append(d)
			kinds[Synergies.DEFS[key]["kind"]] += 1
		if kinds.origin != 1 or kinds.class < 1 or kinds.class > 2 or kinds.unique > 1 or d.tags.size() > 3:
			bad_shape.append(d.display_name)

	chk("%d units in the roster" % roster.size(), roster.size() > 0)
	for cost in EXPECT:
		chk("cost %d: %d units" % [cost, EXPECT[cost]], int(by_cost.get(cost, 0)) == EXPECT[cost], "found %d" % int(by_cost.get(cost, 0)))
	chk("display names are unique", dup_names.is_empty(), str(dup_names))
	chk("body labels are unique, 3 letters at most", dup_labels.is_empty(), str(dup_labels))
	chk("stats are sane", bad_stats.is_empty(), str(bad_stats))
	chk("every tag exists in Synergies.DEFS", bad_tags.is_empty(), str(bad_tags))
	chk("every unit has one origin, one or two classes, at most one unique, at most 3 traits", bad_shape.is_empty(), str(bad_shape))

	var by_kind := {}
	var bad_defs: Array = []
	for tag in Synergies.DEFS:
		var def: Dictionary = Synergies.DEFS[tag]
		by_kind[def.kind] = int(by_kind.get(def.kind, 0)) + 1
		var tiers: Array = def.tiers
		if tiers.size() != (def.thresholds as Array).size() or (def.kind == "unique") != (def.thresholds == [1]):
			bad_defs.append(tag)
		for tier in tiers:
			if str(tier.get("text", "")) == "":
				bad_defs.append(tag)
			for part in ["self", "team"]:
				for k in tier.get(part, {}):
					if not EFFECT_KEYS.has(k):
						bad_defs.append("%s:%s" % [tag, k])
			for other in tier.get("tags", {}):
				if not Synergies.DEFS.has(other):
					bad_defs.append("%s->%s" % [tag, other])
	chk("35 traits: 11 origins, 16 classes, 8 uniques", Synergies.DEFS.size() == 35 and by_kind == EXPECT_TRAITS, str(by_kind))
	chk("every trait has one tier per threshold, with text and known effects", bad_defs.is_empty(), str(bad_defs))

	# No two traits give the same bonus: each (scope, effect key) pair belongs to one trait
	# (ramp_max only goes with ramp).
	var owner := {}
	var shared: Array = []
	for tag in Synergies.DEFS:
		for tier in Synergies.DEFS[tag].tiers:
			for part in ["self", "team", "tags"]:
				var fx: Dictionary = tier.get(part, {})
				var keys: Array = fx.keys() if part != "tags" else (["revive"] if not fx.is_empty() else [])
				for k in keys:
					if k == "ramp_max":
						continue
					var slot := "%s:%s" % [part, k]
					if owner.has(slot) and owner[slot] != tag and not shared.has(slot):
						shared.append("%s (%s, %s)" % [slot, owner[slot], tag])
					owner[slot] = tag
	chk("no two traits give the same bonus", shared.is_empty(), str(shared))

	var unreachable: Array = []
	for tag in Synergies.DEFS:
		var th: Array = Synergies.DEFS[tag]["thresholds"]
		var n := (holders[tag] as Array).size() if holders.has(tag) else 0
		if n < int(th.back()):
			unreachable.append("%s (%d holders, needs %d)" % [tag, n, int(th.back())])
	chk("every synergy tier can be reached", unreachable.is_empty(), str(unreachable))

	var unique_by_cost := {}
	var odd_unique: Array = []
	for tag in Synergies.DEFS:
		if Synergies.DEFS[tag]["thresholds"] != [1]:
			continue
		var hs: Array = holders.get(tag, [])
		if hs.size() != 1:
			odd_unique.append("%s (%d)" % [tag, hs.size()])
		else:
			var c: int = hs[0].cost
			unique_by_cost[c] = int(unique_by_cost.get(c, 0)) + 1
	chk("each unique synergy has exactly one holder", odd_unique.is_empty(), str(odd_unique))
	for cost in EXPECT_UNIQUE:
		chk("cost %d: %d unique synergies" % [cost, EXPECT_UNIQUE[cost]], int(unique_by_cost.get(cost, 0)) == EXPECT_UNIQUE[cost], "found %d" % int(unique_by_cost.get(cost, 0)))
	chk("no other cost has a unique synergy", unique_by_cost.size() == EXPECT_UNIQUE.size(), str(unique_by_cost))

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
