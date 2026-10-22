# enemy_board.gd
class_name EnemyBoard extends Resource

# A full enemy side for one fight. Opponent providers return these; campaign waves are
# authored as these; PvP snapshots will be saved in the same shape via to_dict().

@export var display_name := ""
@export var units: Array[BoardUnit] = []
@export var stat_scale := 1.0        # multiplies every unit's HP and damage
@export var use_synergies := true    # enemies get synergy bonuses from their own tags
@export var hp_reward := 0           # campaign "HP pack": player HP restored for beating this board (max 100)

# Plain data with stable ids, for saves and snapshots. Units are referenced by
# UnitData.display_name (unique per CLAUDE.md), items by ItemData.id.
func to_dict() -> Dictionary:
	var list := []
	for bu in units:
		if bu == null or bu.unit == null:
			continue
		var item_ids := []
		for item in bu.items:
			item_ids.append(String(item.id))
		list.append({
			"unit": bu.unit.display_name,
			"star": bu.star,
			"coord": [bu.coord.x, bu.coord.y],
			"items": item_ids,
		})
	return {
		"name": display_name,
		"stat_scale": stat_scale,
		"use_synergies": use_synergies,
		"hp_reward": hp_reward,
		"units": list,
	}

# Rebuilds a board from to_dict() output. Unknown units or items are skipped with a warning.
static func from_dict(d: Dictionary, unit_roster: Array, item_roster: Array) -> EnemyBoard:
	var b := EnemyBoard.new()
	b.display_name = str(d.get("name", ""))
	b.stat_scale = float(d.get("stat_scale", 1.0))
	b.use_synergies = bool(d.get("use_synergies", true))
	b.hp_reward = int(d.get("hp_reward", 0))
	for e in d.get("units", []):
		if not e is Dictionary:
			continue
		var ud := lookup_unit(unit_roster, str(e.get("unit", "")))
		if ud == null:
			push_warning("EnemyBoard: unknown unit '%s' skipped" % e.get("unit", ""))
			continue
		var bu := BoardUnit.new()
		bu.unit = ud
		bu.star = clampi(int(e.get("star", 1)), 1, 3)
		var c = e.get("coord", [-1, -1])
		if c is Array and c.size() == 2:
			bu.coord = Vector2i(int(c[0]), int(c[1]))
		for id in e.get("items", []):
			var item := lookup_item(item_roster, StringName(str(id)))
			if item != null:
				bu.items.append(item)
			else:
				push_warning("EnemyBoard: unknown item '%s' skipped" % id)
		b.units.append(bu)
	return b

# Id lookups shared with GameManager (carried boards) and future snapshot loading.
static func lookup_unit(roster: Array, unit_name: String) -> UnitData:
	for x in roster:
		var ud := x as UnitData
		if ud != null and ud.display_name == unit_name:
			return ud
	return null

static func lookup_item(roster: Array, id: StringName) -> ItemData:
	for x in roster:
		var item := x as ItemData
		if item != null and item.id == id:
			return item
	return null
