# king_skins.gd
class_name KingSkins

# The kings' skins, a player unlock. Every king has the same base: it can't be hurt or targeted, and
# every 10 s of a fight it strikes a random enemy unit anywhere on the board (CombatRunner._kings_act),
# each skin with its own attack (King.strike: the wind-up and lunge, then the skin's shot, `attack`).
# The skin picked on the main menu (SaveGame.king_skin) adds one unique effect: the Golden Lion's works in
# the fight, on the same beat (act); the others are run powers (king_powers.gd: interest, shop odds,
# memories, quests, proclamations, the hoard, prophecies, forbidden knowledge), in free play and async PvP.
# The skin also decides how the king looks (its model, baked by tools/make_voxel_tiles into
# models/kings/). The Shadow King has no model of its own: it wears the opposing king's, in shadow (`mimic`).
# Owned skins: DEFAULT always, the rest once their unlock ("king:<id>") is saved; `unlock` "" = owned from the start.
#
# Deterministic: act() picks with the fight's own RNG (the runner's), over its fixed acting order.

const DEFAULT: StringName = &"lion"
const ORDER: Array[StringName] = [&"lion", &"merchant", &"gambler", &"necromancer", &"explorer", &"chaos", &"dragon", &"fate", &"shadow"]

# name, power (its effect's name), text (what it does), model, attack (the look of its strike: King._fire),
# colour (its shots and the King tab), unlock ("" = owned from the start). `run`: a run power (king_powers.gd).
const DEFS := {
	&"lion": {"name": "Golden Lion", "power": "Royal Guard", "text": "Every 10 s, shields a random ally with a strong shield: 35% of its max HP, for 8 s.",
		"model": "res://models/kings/lion.res", "attack": "claw", "colour": "ffd46b", "unlock": ""},
	&"merchant": {"name": "Merchant King", "power": "The King's Tax", "text": "Interest is capped at 7 gold a round instead of 5 (bank 70 gold for it all).",
		"model": "res://models/kings/merchant.res", "attack": "coins", "colour": "f2c14e", "unlock": "", "run": true},
	&"gambler": {"name": "Gambler King", "power": "Loaded Dice", "text": "Every round the dice shift your shop odds: a little, often; sometimes far better, sometimes worse. High risk, high reward.",
		"model": "res://models/kings/gambler.res", "attack": "dice", "colour": "e8443a", "unlock": "", "run": true},
	&"necromancer": {"name": "Necromancer King", "power": "Memorial Hall", "text": "Selling a unit stores its memory (1 soul a star). Every 3 souls, a free copy of a unit you sold comes back to your bench.",
		"model": "res://models/kings/necromancer.res", "attack": "souls", "colour": "7dff9a", "unlock": "", "run": true},
	&"explorer": {"name": "Explorer King", "power": "Uncharted Territory", "text": "Quests appear during the run (win with exactly 5 units, reach level 7 without rerolling...). Complete them for relics.",
		"model": "res://models/kings/explorer.res", "attack": "stone", "colour": "d9b26a", "unlock": "", "run": true},
	&"chaos": {"name": "Chaos King", "power": "Royal Proclamations", "text": "Every other round a random proclamation: cheaper units, free rerolls, an extra item, double XP, a war banner... You never know what comes next.",
		"model": "res://models/kings/chaos.res", "attack": "chaos", "colour": "ff5ad8", "unlock": "", "run": true},
	&"dragon": {"name": "Dragon King", "power": "Hoard", "text": "Gold above 50 goes into your hoard, which grows by itself and pays out treasure as it fills. Start a fight under 20 gold and it collapses: you get half back.",
		"model": "res://models/kings/dragon.res", "attack": "fire", "colour": "ff7a2a", "unlock": "", "run": true},
	&"fate": {"name": "Fate King", "power": "Threads of Destiny", "text": "Early in the run, choose one of three prophecies (reach level 9, a 3-star 5-cost, 10 wins in a row...). Fulfil it for a huge reward.",
		"model": "res://models/kings/fate.res", "attack": "thread", "colour": "b48cff", "unlock": "", "run": true},
	&"shadow": {"name": "Shadow King", "power": "Forbidden Knowledge", "text": "Takes the shape of your opponent's king, in shadow. Reveals your next reroll, the coming enemy, the drop odds and the game's hidden rules.",
		"model": "", "attack": "shadow", "colour": "8a5cff", "unlock": "", "run": true},
}

const SHIELD_SHARE := 0.35   # the Golden Lion's shield, of the ally's max HP
const SHIELD_TIME := 8.0

static func has(id: StringName) -> bool:
	return DEFS.has(id)

static func display_name(id: StringName) -> String:
	return DEFS[id].name if has(id) else ""

static func colour(id: StringName) -> Color:
	return Color(DEFS[id].colour) if has(id) else Color("ffd46b")

# True for a skin whose effect is a run power (king_powers.gd) rather than a fight effect.
static func is_run_power(id: StringName) -> bool:
	return has(id) and bool(DEFS[id].get("run", false))

static func owned(id: StringName) -> bool:
	return has(id) and (id == DEFAULT or str(DEFS[id].unlock) == "" or SaveGame.has_unlock(StringName("king:" + String(id))))

# The skin this player fights with: their pick if they own it, else the default.
static func selected() -> StringName:
	var id := StringName(SaveGame.king_skin())
	return id if owned(id) else DEFAULT

static func picked() -> bool:
	return owned(StringName(SaveGame.king_skin()))

# The skin's model. The Shadow King has none of its own: it wears `mimic`'s (the opposing king's skin).
static func model(id: StringName, mimic: StringName = DEFAULT) -> Mesh:
	if id == &"shadow":
		id = mimic if has(mimic) and mimic != &"shadow" else DEFAULT
	var p: String = DEFS[id].model if has(id) else DEFS[DEFAULT].model
	return load(p) as Mesh if ResourceLoader.exists(p) else null

# The skin's own effect in a fight, on the king's 10 s beat (after its strike). `team` is the king's side.
# Only the Golden Lion has one; the other skins' powers work between fights (KingPowers).
static func act(id: StringName, runner: CombatRunner, team: int, rng: RandomNumberGenerator) -> void:
	match id:
		&"lion":
			var allies := runner.alive_units(team, false)
			if allies.is_empty():
				return
			var u: Unit = allies[rng.randi_range(0, allies.size() - 1)]
			u.add_timed_shield(u.max_hp() * SHIELD_SHARE, SHIELD_TIME)
			runner.king_fx(team, u, true)
