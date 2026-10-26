# king_skins.gd
class_name KingSkins

# The kings' skins, a player unlock. Every king has the same base: it can't be hurt or targeted, and
# every 10 s of a fight it strikes a random enemy unit anywhere on the board (CombatRunner._kings_act).
# The skin picked on the main menu (SaveGame.king_skin) adds one unique effect on the same beat (act),
# and decides how the king looks (its model, baked by tools/make_voxel_tiles into models/kings/).
# Owned skins: DEFAULT always, the rest once their unlock ("king:<id>") is saved.
#
# Deterministic: act() picks with the fight's own RNG (the runner's), over its fixed acting order.

const DEFAULT: StringName = &"lion"
const ORDER: Array[StringName] = [&"lion"]

const DEFS := {
	&"lion": {"name": "Golden Lion", "text": "Every 10 s, shields a random ally with a strong shield: 35% of its max HP, for 8 s.",
		"model": "res://models/kings/lion.res", "unlock": "Owned from the start"},
}

const SHIELD_SHARE := 0.35   # the Golden Lion's shield, of the ally's max HP
const SHIELD_TIME := 8.0

static func has(id: StringName) -> bool:
	return DEFS.has(id)

static func display_name(id: StringName) -> String:
	return DEFS[id].name if has(id) else ""

static func owned(id: StringName) -> bool:
	return has(id) and (id == DEFAULT or SaveGame.has_unlock(StringName("king:" + String(id))))

# The skin this player fights with: their pick if they own it, else the default.
static func selected() -> StringName:
	var id := StringName(SaveGame.king_skin())
	return id if owned(id) else DEFAULT

static func picked() -> bool:
	return owned(StringName(SaveGame.king_skin()))

static func model(id: StringName) -> Mesh:
	var p: String = DEFS[id].model if has(id) else DEFS[DEFAULT].model
	return load(p) as Mesh if ResourceLoader.exists(p) else null

# The skin's own effect, on the king's 10 s beat (after its strike). `team` is the king's side.
static func act(id: StringName, runner: CombatRunner, team: int, rng: RandomNumberGenerator) -> void:
	match id:
		&"lion":
			var allies := runner.alive_units(team, false)
			if allies.is_empty():
				return
			var u: Unit = allies[rng.randi_range(0, allies.size() - 1)]
			u.add_timed_shield(u.max_hp() * SHIELD_SHARE, SHIELD_TIME)
			runner.king_fx(team, u, true)
