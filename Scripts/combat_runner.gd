# combat_runner.gd
class_name CombatRunner extends RefCounted

# One fight on one board: the fixed acting order, ground zones, summons joining, timed inputs and the
# end check, one fixed tick at a time. GameManager owns one for the visible board (single player, and
# a lobby client's replay); the lobby server owns one per arena board. Abilities reach the runner of
# the board a unit stands on (Board.runner), so several fights can run side by side.
#
# Deterministic: the order is by tile (row, then column), interleaved team 0 / team 1; nothing here
# depends on node order, frame rate or the clock. A fight is a pure function of the units placed on
# the board before start() plus the inputs scheduled for given ticks.

const TICK := 1.0 / 60.0   # seconds of fight per tick
const MAX_TICKS := 3600    # 60 s; reaching it ends the fight with both sides standing

var board: Board
var combatants: Array[Unit] = []   # fixed acting order for this fight
var new_summons: Array[Unit] = []  # summoned this tick; they join `combatants` (at the end) after it
var zones: Array = []              # ground effects from abilities (add_zone): ticked before the units act
var ticks := 0
var time := 0.0
var fighting := false
# Called once when a side is wiped out or time runs out: on_finish(alive: Array[int] per team,
# stars: Array[int] per team, not counting summons). It must stop the fight (fighting = false).
var on_finish: Callable
# Gold an ability earns during the fight (Pickpocket): gold_sink(team, amount). Unset: nobody gets it.
var gold_sink: Callable
var _inputs := {}   # tick -> Array[Callable]: actions applied at the start of that tick (lobby item drops)

# The kings (king_skins.gd): every KING_PERIOD ticks each side's king strikes a random enemy unit
# (KING_DAMAGE + KING_DAMAGE_PER_LEVEL x its level), then its skin's effect runs. Set before start();
# the picks come from an RNG seeded with king_seed, so every copy of a fight picks the same.
const KING_PERIOD := 600            # 10 s
const KING_DAMAGE := 30
const KING_DAMAGE_PER_LEVEL := 10
var king_skins: Array = [&"", &""]  # per team: a KingSkins id, or "" for no skin effect
var king_levels: Array = [1, 1]     # per team: the player level the strike scales with
var king_seed := 0
var _king_rng := RandomNumberGenerator.new()

func _init(b: Board = null):
	board = b
	if b != null:
		b.runner = self

# Starts the fight with every unit standing on a tile (both teams), from tick 0.
func start() -> void:
	combatants = order()
	new_summons.clear()
	zones.clear()
	ticks = 0
	time = 0.0
	_king_rng.seed = hash(["kings", king_seed])
	fighting = true

# Fixed acting order for a fight: each side sorted by tile (row, then column), then interleaved
# team 0 / team 1 so neither side always acts first. Node order never matters.
func order() -> Array[Unit]:
	var sides := [[], []]
	for n in board.get_node("Units").get_children():
		var u := n as Unit
		if u != null and u.data != null and u.coord.x >= 0 and not u.is_queued_for_deletion():
			sides[clampi(u.team, 0, 1)].append(u)
	for side in sides:
		side.sort_custom(func(a, b): return Board.tile_order(a.coord) < Board.tile_order(b.coord))
	var out: Array[Unit] = []
	for i in maxi(sides[0].size(), sides[1].size()):
		for side in sides:
			if i < side.size():
				out.append(side[i])
	return out

# Runs `fn` at the start of tick `at` (before anything acts). A tick already past runs at the next one.
func schedule(at: int, fn: Callable) -> void:
	var t := maxi(at, ticks + 1)
	if not _inputs.has(t):
		_inputs[t] = []
	_inputs[t].append(fn)

func clear_inputs() -> void:
	_inputs.clear()

func tick() -> void:
	if not fighting:
		return
	ticks += 1
	time = ticks * TICK
	if _inputs.has(ticks):
		for fn in _inputs[ticks]:
			fn.call()
		_inputs.erase(ticks)
	_tick_zones()
	if ticks % KING_PERIOD == 0:
		_kings_act()
	for u in combatants:
		if is_instance_valid(u) and not u.dead and u.coord.x >= 0:
			u.combat_step(TICK)
	if not new_summons.is_empty():
		combatants.append_array(new_summons)   # they act from the next tick
		new_summons.clear()
	var alive := [0, 0]
	var stars := [0, 0]
	for u in combatants:
		if not is_instance_valid(u) or u.dead or u.coord.x < 0:
			continue
		var side := clampi(u.team, 0, 1)
		alive[side] += 1
		if not u.summoned:
			stars[side] += u.star   # summons don't add to the loss damage
	if alive[0] == 0 or alive[1] == 0 or ticks >= MAX_TICKS:
		if on_finish.is_valid():
			on_finish.call(alive, stars)
		else:
			fighting = false

# Runs the fight to its end at once (tests, the lobby server's bot fights).
func resolve() -> void:
	while fighting:
		tick()

# Called when a fight ends: zones and pending inputs go.
func stop() -> void:
	fighting = false
	zones.clear()
	new_summons.clear()
	_inputs.clear()

func add_summon(u: Unit) -> void:
	new_summons.append(u)

# Gold an ability earns (Pickpocket kills): to whoever owns that team's side of this fight.
func credit_gold(team: int, amount: int) -> void:
	if gold_sink.is_valid():
		gold_sink.call(team, amount)

# A ground effect from an ability (Miasma, Antler Grove): every tick for `secs`, the units within
# `radius` of `center` are affected. kind "miasma": enemies of `team` take `amount` per second and are
# cursed 15%; kind "grove": allies of `team` regenerate `amount` of their max HP per second; kind
# "winter": enemies take `amount` per second and are chilled 50%, and when it ends those below half
# HP are frozen (stunned) for 1.5 s. It stays if its caster dies; `by` gets the damage credit while it lives.
func add_zone(kind: String, center: Vector2i, radius: int, secs: float, team: int, amount: float, by: Unit) -> void:
	zones.append({"kind": kind, "center": center, "radius": radius, "left": secs, "team": team, "amount": amount, "by": by})
	match kind:   # the look (visual only)
		"miasma":
			Vfx.zone(board, board, center, radius, Color("8fd14f"), secs)
		"grove":
			Vfx.zone(board, board, center, radius, Color("7dff9a"), secs)
		"winter":
			Vfx.blizzard(board, board, 1 - team, secs)

func _tick_zones() -> void:
	if zones.is_empty():
		return
	for z in zones:
		z.left -= TICK
		var by: Unit = z.by if is_instance_valid(z.by) else null
		for u in combatants:
			if not is_instance_valid(u) or u.dead or u.coord.x < 0 or Board.hex_distance(z.center, u.coord) > z.radius:
				continue
			if z.kind == "miasma" and u.team != z.team:
				var removed := u.take_damage(z.amount * TICK, by)
				if by != null:
					by.damage_dealt += removed
				u.apply_curse(0.15, 0.25)
			elif z.kind == "winter" and u.team != z.team:
				var cold := u.take_damage(z.amount * TICK, by)
				if by != null:
					by.damage_dealt += cold
				u.apply_chill(0.5, 0.25)
			elif z.kind == "grove" and u.team == z.team:
				u.heal(u.max_hp() * z.amount * TICK)
		if z.kind == "winter" and z.left <= 0.0001:   # Eternal Winter ends: the weakened freeze
			for u in combatants:
				if is_instance_valid(u) and not u.dead and u.coord.x >= 0 and u.team != z.team and u.health < u.max_hp() * 0.5:
					u.apply_stun(1.5)
	zones = zones.filter(func(z): return z.left > 0.0001)   # (float steps: 240 ticks of 1/60 leave a crumb)

# --- the kings ---------------------------------------------------------------------------------------

# Both kings act, your side first: a strike on a random targetable enemy unit, then the skin's effect.
func _kings_act() -> void:
	for team in 2:
		var foes := alive_units(1 - team, true)
		if not foes.is_empty():
			var t: Unit = foes[_king_rng.randi_range(0, foes.size() - 1)]
			var lvl: int = king_levels[team]
			t.take_damage(KING_DAMAGE + KING_DAMAGE_PER_LEVEL * lvl, null)
			king_fx(team, t, false)
		var skin: StringName = king_skins[team]
		if skin != &"":
			KingSkins.act(skin, self, team, _king_rng)

# The living units of a team in the fight's acting order; `targetable`: without the hidden ones.
func alive_units(team: int, targetable: bool) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in combatants:
		if is_instance_valid(u) and not u.dead and u.coord.x >= 0 and u.team == team and not (targetable and u.untargetable_left > 0.0):
			out.append(u)
	return out

# The look of a king acting (visual only): its attack on the unit it strikes (King.strike: a wind-up,
# a lunge and its skin's shot), or its lift for the ally it helps (King.help).
func king_fx(team: int, u: Unit, helps: bool) -> void:
	if not Vfx.enabled or board == null or board.kings.size() <= team or not is_instance_valid(board.kings[team]):
		return
	var k := board.kings[team] as King
	if k == null:
		return
	if helps:
		k.help(u)
	else:
		k.strike(u)
