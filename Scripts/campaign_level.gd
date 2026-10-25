# campaign_level.gd
class_name CampaignLevel extends Resource

# One campaign level: its waves (one per round) and the modifiers that make it different
# from free play. A level is completed by surviving every wave and winning the last one.
#
# A chapter is one continuous run: after the first level, the player's board, items, gold,
# level, XP and HP carry over from the previous level. The start_* fields and player_hp only
# apply when a level starts a run (the chapter's first level, or Debug Level); for later levels
# start_level is the level the player is expected to arrive at (used by validate()).

@export var id: StringName              # stable, unique; used by the save file. Never rename.
@export var display_name := ""
@export_multiline var description := ""
@export var theme: StringName = &""            # the board's biome (BoardThemes.ORDER: forest, autumn, snow, swamp, volcano, cave, mushroom, mushroom_cave, jungle, desert, salt_flats, parasitic)
@export var waves: Array[EnemyBoard] = []

@export_group("Modifiers")
@export var start_gold := 2
@export_range(1, 9) var start_level := 1
@export var player_hp := 100
@export var start_heal := 0                   # HP pack when arriving from the previous level (max 100)
@export var income_bonus := 0                 # extra gold every round
@export var enemy_stat_mult := 1.0            # multiplies every wave's stat_scale
@export var loss_damage := 0                  # HP lost per lost wave (+0.25 per surviving enemy star); 0 = free-play formula (5 x stage)
@export var prep_time := 0                    # seconds; 0 = GameManager default
@export var item_drop_rounds: Array[int] = [] # empty = the free-play drop rounds
@export var allowed_units: Array[UnitData] = [] # empty = the full roster in the shop

@export_group("Rewards")
@export var unlocks: Array[StringName] = []   # saved on completion (e.g. unit or mode ids)

# Authoring check. Returns one line per problem; empty means the level is fine.
# "Too many units" uses the lowest level the player can be at that round (no XP bought),
# because units that don't fit on the open enemy tiles are skipped.
func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	var tag := "Level '%s'" % (display_name if display_name != "" else str(id))
	if id == &"":
		out.append("%s: missing id" % tag)
	if waves.is_empty():
		out.append("%s: no waves" % tag)
	if start_gold < 0 or player_hp <= 0 or enemy_stat_mult <= 0.0:
		out.append("%s: start_gold, player_hp and enemy_stat_mult must be positive" % tag)
	var lvl := start_level
	var xp := 0
	for w in waves.size():
		var wave: EnemyBoard = waves[w]
		var wtag := "%s wave %d" % [tag, w + 1]
		if wave == null:
			out.append("%s: empty slot" % wtag)
		else:
			var seen := {}
			var count := 0
			for bu in wave.units:
				if bu == null or bu.unit == null:
					out.append("%s: a unit has no UnitData" % wtag)
					continue
				count += 1
				if bu.coord == Vector2i(-1, -1):
					continue
				if bu.coord.x < 0 or bu.coord.x >= Board.COLS or bu.coord.y < 0 or bu.coord.y >= Board.ROWS / 2:
					out.append("%s: %s at %s is not on the enemy half (x 0-%d, y 0-%d)" % [wtag, bu.unit.display_name, bu.coord, Board.COLS - 1, Board.ROWS / 2 - 1])
				if seen.has(bu.coord):
					out.append("%s: two units at %s" % [wtag, bu.coord])
				seen[bu.coord] = true
			var open := Board.tiles_open_for_level(lvl)
			if count > open:
				out.append("%s: %d units but only %d enemy tiles open at player level %d; %d would be skipped" % [wtag, count, open, lvl, count - open])
			if wave.stat_scale <= 0.0:
				out.append("%s: stat_scale must be positive" % wtag)
		# +2 XP after every round (GameManager RESULT phase)
		xp += 2
		while GameState.XP_TABLE.has(lvl) and xp >= GameState.XP_TABLE[lvl]:
			xp -= GameState.XP_TABLE[lvl]
			lvl += 1
	for r in item_drop_rounds:
		if r < 1 or r > waves.size():
			out.append("%s: item drop round %d is outside 1-%d" % [tag, r, waves.size()])
	return out
