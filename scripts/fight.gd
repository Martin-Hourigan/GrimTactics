class_name Fight
extends RefCounted
## The rules of a level: the hero walks about, and fights the enemies that
## wake up, the boss and the small ones.
## No drawing here; main.gd shows it, tests.gd checks it.

const ROOM := 3  ## room radius in hexes (PLACEHOLDER)
## The ways to play, picked after Play (PLACEHOLDER names):
##   stamina: the stamina bar pays for moving, attacks, blocks and dodges;
##   one: no stamina, move up to MOVES hexes and attack once a turn;
##   order: as one, but who goes next is set by speed.
const MODES := {"stamina": "Stamina", "one": "One attack", "order": "Turn order"}
const MOVES := 3  ## hexes a turn without stamina
## How long the dodge bar takes to fill, times this (PLACEHOLDER).
const PACE := {"slow": 1.2, "mid": 1.0, "fast": 0.8}
const BOSS_SPEED := 8  ## turn order speed (PLACEHOLDER)
## Axial directions, counter-clockwise from the right. Facing f points along DIRS[f].
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const NONE := Vector2i(-99, -99)  ## no hex
## Places to play:
##   arena: the boss alone in a round room, fighting from the start;
##   keep: the bonfire room, a hallway with two small enemies, then the boss's room.
const LEVELS := {"arena": "Arena", "keep": "Keep"}
const WAKE := 5  ## an enemy joins the fight once it's this near the hero with no wall between

# ---- hero (all PLACEHOLDER) ----
const HERO_HP := 200
const STAMINA := 6  ## the stamina bar; the fight starts with it full
const STAMINA_BACK := 2  ## stamina regained at the start of every hero turn
const REST_BONUS := 4  ## extra stamina back after a turn with no attack
const FLASKS := 2
const FLASK_HEAL := 100
const DODGE_COST := 1  ## the first dodge in a boss turn; each further dodge costs this much more
const BLOCK_COST := 2  ## blocking a boss attack
const HEAVY_BLOCK_COST := 3  ## blocking one of its heavy attacks
const SWAP_COST := 1  ## swapping to the other weapon set
const WEAK_BONUS := 10  ## extra damage from a weak arc
const COMBO := [0.0, 0.1, 0.2]  ## damage bonus on the 1st, 2nd and 3rd hit in a row; then it starts again
const RUN_STEPS := 2  ## the running attack runs at least this many hexes, then hits
const RUN_BONUS := 0.2  ## a running attack's damage bonus; it counts as the 1st hit of a combo
## pace: the dodge bar after that attack, without stamina. speed: for the turn order.
## skills: the weapon's own skills, from SKILLS.
const WEAPONS := {
	"longsword": {"label": "Longsword & shield", "block": 10, "speed": 10, "skills": ["combo"], "acts": [
		{"label": "Light attack", "st": 2, "dmg": 25, "pace": "slow"},
		{"label": "Heavy attack", "st": 3, "dmg": 45, "pace": "fast"},
	]},
	"claymore": {"label": "Claymore", "block": 0, "speed": 6, "skills": ["sweep"], "acts": [
		{"label": "Light attack", "st": 2, "dmg": 35, "pace": "mid"},
		{"label": "Heavy attack", "st": 4, "dmg": 70, "pace": "fast"},
	]},
	"bow": {"label": "Bow", "block": 0, "speed": 8, "range": [1, 2 * ROOM], "arrows": true, "skills": ["aimed"], "acts": [
		{"label": "Light attack", "st": 3, "dmg": 40, "pace": "mid"},
	]},
}
## Every skill sits out SKILL_WAIT turns after it's used.
## combo: the light attack hits times in a row with the combo bonuses, and
##   then the hero can't block or dodge until their next turn.
## sweep: hits the 3 hexes round the hero centred on the one picked.
## aimed: a harder shot that goes through the boss's block (pierce).
## (st, dmg: PLACEHOLDER)
const SKILLS := {
	"combo": {"label": "Combo attack", "st": 5, "hits": 3},
	"sweep": {"label": "Sweep", "st": 3, "dmg": 35},
	"aimed": {"label": "Aimed shot", "st": 4, "dmg": 50, "pierce": true},
}
const SKILL_WAIT := 1
const ARROWS := 10  ## arrows for the fight (later: from leaving the bonfire)
## block: damage taken off each blocked hit. bar: how long the dodge bar takes to fill (x)
const ARMOURS := {
	"light": {"label": "Light armour", "block": 10, "bar": 1.0},
	"heavy": {"label": "Heavy armour", "block": 30, "bar": 0.75},
}

# ---- small enemies (all PLACEHOLDER) ----
## held: the weapon it starts with, from FOE_ATTACKS. steps: its turn, in order:
##   move n: up to n hexes towards the hero,
##   arm: the crossbow, or the shortsword when the hero is next to it,
##   attack: with the weapon held; a crossbow bolt hits the first body on its line.
const FOES := {
	"swordsman": {"label": "Swordsman", "hp": 80, "block": 0, "speed": 8, "held": "sword",
		"steps": [{"move": 2}, {"attack": true}]},
	"crossbowman": {"label": "Crossbowman", "hp": 80, "block": 0, "speed": 6, "held": "crossbow",
		"steps": [{"arm": true}, {"attack": true}]},
}
const FOE_ATTACKS := {
	"sword": {"name": "Sword", "dmg": 40, "dodge": 1},
	"crossbow": {"name": "Crossbow", "dmg": 30, "dodge": 2, "range": 6},
	"shortsword": {"name": "Shortsword", "dmg": 25, "dodge": 1},
}
## The keep's layout (PLACEHOLDER): the boss's room round 0,0, a door, the
## hallway, and the bonfire room at the bottom.
const KEEP_DOOR := Vector2i(-2, 4)
const KEEP_HALL := [5, 15]  ## the hallway's first and last rows
const KEEP_BONFIRE := Vector2i(-9, 18)
const KEEP_START := Vector2i(-9, 19)
const KEEP_FOES := [["swordsman", Vector2i(-5, 10)], ["crossbowman", Vector2i(-3, 7)]]

# ---- boss (all PLACEHOLDER) ----
const BOSS_HP := 400
const BOSS_BLOCK := 10
const HEAT_AT := 180  ## heats up at this health or below
const DECK_SIZE := 4
## Behaviour cards. Steps run left to right:
##   move n (towards the hero, or away if negative), turn k (60 degrees each,
##   counter-clockwise), leap (next to the hero, facing kept),
##   aim [turns, steps]: before the next attack it may turn up to this many
##     times and step up to this many hexes (facing kept) to bring the hero
##     into that attack,
##   attack dmg within range: the hero only, or every hex in the listed arcs;
##     heavy attacks cost more stamina to block.
## dodge = how hard the dodge check is (1-3). weak = arcs that take extra damage.
const CARDS := [
	{"name": "Lunge", "dodge": 1, "weak": ["back"], "steps": [{"move": 2}, {"aim": [1, 0]}, {"attack": 60, "range": 1, "arcs": ["front"]}]},
	{"name": "Sweep", "dodge": 1, "weak": ["back"], "steps": [{"aim": [1, 0]}, {"attack": 48, "range": 1, "arcs": ["front", "left", "right"]}]},
	{"name": "Turn and cut", "dodge": 2, "weak": ["left", "right"], "steps": [{"turn": 3}, {"aim": [1, 0]}, {"attack": 72, "range": 1, "arcs": ["front"], "push": true, "heavy": true}]},
	{"name": "Overhead", "dodge": 1, "weak": ["left", "right"], "steps": [{"aim": [1, 1]}, {"attack": 96, "range": 1, "arcs": ["front"], "heavy": true}]},
	{"name": "Shield bash", "dodge": 2, "weak": ["back"], "steps": [{"aim": [2, 1]}, {"attack": 36, "range": 1, "arcs": ["front"], "push": true}]},
	{"name": "Step back, thrust", "dodge": 2, "weak": ["left"], "steps": [{"move": -1}, {"aim": [1, 0]}, {"attack": 60, "range": 2, "arcs": ["front"]}]},
]
const HEAT_CARDS := [
	{"name": "Leap", "dodge": 2, "weak": ["back"], "steps": [{"leap": true}, {"attack": 72, "range": 1, "arcs": ["front", "left", "right", "back"], "heavy": true}]},
	{"name": "Flurry", "dodge": 3, "weak": ["back"], "repeat": 2, "steps": [{"aim": [1, 1]}, {"attack": 48, "range": 1, "arcs": ["front"]}]},
]

var mode := "stamina"
var level := "arena"
var ground := {}  ## every hex that can be walked on -> true
var bonfire := NONE
var weapon: String  ## the weapon in hand
var spare: String  ## the other weapon set; empty if there isn't one
var armour: String
var hp := HERO_HP
var stamina := STAMINA
var dodges := 0  ## dodges made this enemy turn
var flasks := FLASKS
var hero := Vector2i(0, 3)
var attacked := false
var arrows := 0  ## arrows left; only given when a bow is taken
var hits := 0  ## hits in a row this turn without moving
var moved := 0  ## hexes moved this turn
var turn_no := 0  ## the hero's turns so far
var ready_at := {}  ## skill -> the hero turn it can be used again
var exposed := false  ## used a skill that leaves no block or dodge until the next turn
var pace := "slow"  ## the dodge bar after this turn's attack, without stamina
var waits := {}  ## turn order: hero, boss or f0, f1... -> wait; the least waited goes next
var boss := Vector2i.ZERO
var facing := 5
var boss_hp := BOSS_HP
var boss_awake := false
var heated := false
var deck: Array = []
var played: Array = []  ## this loop's cards, in the order they came
var card: Dictionary = {}  ## the card on top of the discard pile
## The small enemies: {kind, at, start, hp, facing, awake, held}.
var foes: Array[Dictionary] = []
var actor := "boss"  ## whose steps the queue holds: boss, or f0, f1...
var to_go: Array = []  ## the enemies still to go this enemy turn
var queue: Array = []  ## steps left on this enemy's turn
var incoming: Dictionary = {}  ## the attack the hero has to block or dodge now
var phase := "hero"  ## explore (no fight on), hero, boss (the enemies' turn), defend, win, lose
var events: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _dist_key := ""
var _dist_map := {}


func _init(weapon_ := "longsword", armour_ := "light", seed_ := 1, spare_ := "", mode_ := "stamina", level_ := "arena") -> void:
	mode = mode_
	weapon = weapon_
	spare = spare_
	if _has_bow():
		arrows = ARROWS
	armour = armour_
	rng.seed = seed_
	var pool := CARDS.duplicate()
	_shuffle(pool)
	deck = pool.slice(0, DECK_SIZE)
	_shuffle(deck)
	level = level_
	if level == "keep":
		_build_keep()
	else:
		for c in room():
			ground[c] = true
		boss_awake = true


func _has_bow() -> bool:
	return WEAPONS[weapon].has("arrows") or (spare != "" and WEAPONS[spare].has("arrows"))


func _build_keep() -> void:
	for c in near(Vector2i.ZERO, ROOM):
		ground[c] = true
	ground[KEEP_DOOR] = true
	for r in range(KEEP_HALL[0], KEEP_HALL[1] + 1):
		for q in range(-r, 1):
			if absf(flat(Vector2i(q, r)).x) <= 1.8:
				ground[Vector2i(q, r)] = true
	for c in near(KEEP_BONFIRE, 2):
		ground[c] = true
	bonfire = KEEP_BONFIRE
	hero = KEEP_START
	facing = 4  # towards the door
	for k in KEEP_FOES:
		foes.append({"kind": k[0], "at": k[1], "start": k[1]})
	_reset_foes()
	phase = "explore"


func _reset_foes() -> void:
	for f in foes:
		f.at = f.start
		f.hp = FOES[f.kind].hp
		f.held = FOES[f.kind].held
		f.facing = 5
		f.awake = false


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# ---- hexes ----

static var _room: Array[Vector2i] = []


static func room() -> Array[Vector2i]:
	if _room.is_empty():
		for q in range(-ROOM, ROOM + 1):
			for r in range(-ROOM, ROOM + 1):
				if dist(Vector2i(q, r), Vector2i.ZERO) <= ROOM:
					_room.append(Vector2i(q, r))
	return _room


static func dist(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## The hexes a straight line from a to b goes through, a left out.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := dist(a, b)
	# nudged off the hex edges so a line along one picks a side the same way each time
	var fa := Vector2(a) + Vector2(1e-4, 2e-4)
	var fb := Vector2(b) + Vector2(1e-4, 2e-4)
	for k in range(1, n + 1):
		var p := fa.lerp(fb, float(k) / n)
		out.append(_round_hex(p.x, p.y))
	return out


static func _round_hex(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


## The hexes within r of c.
static func near(c: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-r, r + 1):
		for s in range(-r, r + 1):
			if dist(Vector2i(q, s), Vector2i.ZERO) <= r:
				out.append(c + Vector2i(q, s))
	return out


func on_ground(c: Vector2i) -> bool:
	return ground.has(c)


## Flat position of an axial hex (unit hex radius, y up).
static func flat(c: Vector2i) -> Vector2:
	return Vector2(sqrt(3.0) * (c.x + c.y / 2.0), -1.5 * c.y)


static func _turns(a: int, b: int) -> int:
	return mini(posmod(a - b, 6), posmod(b - a, 6))


## Which of the boss's arcs hex c is in. Hexes on the line between two arcs are in both.
func arcs_of(c: Vector2i, f := -1) -> Array[String]:
	if f < 0:
		f = facing
	var out: Array[String] = []
	if c == boss:
		return out
	var d := flat(c - boss)
	var rel := wrapf(rad_to_deg(atan2(d.y, d.x)) - 60.0 * f, -180.0, 180.0)
	var e := 0.5
	if absf(rel) <= 30.0 + e:
		out.append("front")
	if rel >= 30.0 - e and rel <= 150.0 + e:
		out.append("left")
	if rel <= -30.0 + e and rel >= -150.0 - e:
		out.append("right")
	if absf(rel) >= 150.0 - e:
		out.append("back")
	return out


func open_hex(c: Vector2i) -> bool:
	return _walkable(c) and c != hero


## Ground with no enemy or bonfire on it.
func _walkable(c: Vector2i) -> bool:
	return ground.has(c) and c != bonfire and not enemy_at(c)


## Steps from the hero to c, going round enemies. -1 if it can't get there.
func steps(c: Vector2i) -> int:
	var key := "%s %s" % [hero, enemies()]
	if key != _dist_key:
		_dist_key = key
		_dist_map = {hero: 0}
		var open: Array[Vector2i] = [hero]
		while not open.is_empty():
			var at: Vector2i = open.pop_front()
			for d in DIRS:
				var n := at + d
				if _walkable(n) and not _dist_map.has(n):
					_dist_map[n] = _dist_map[at] + 1
					open.append(n)
	if c != hero and not _walkable(c):
		return -1
	return _dist_map.get(c, -1)


## The hexes walked from a to b, b last, going round everything in the way
## but b itself; empty if there's no way.
func path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var from := {a: a}
	var open: Array[Vector2i] = [a]
	while not open.is_empty():
		var at: Vector2i = open.pop_front()
		if at == b:
			break
		for d in DIRS:
			var n := at + d
			if not from.has(n) and (n == b or (_walkable(n) and n != hero)):
				from[n] = at
				open.append(n)
	var out: Array[Vector2i] = []
	if a == b or not from.has(b):
		return out
	var c := b
	while c != a:
		out.push_front(c)
		c = from[c]
	return out


# ---- the hero's turn ----

func uses_stamina() -> bool:
	return mode == "stamina"

func move_cost(c: Vector2i) -> int:
	var n := steps(c)
	if n < 0:
		return -1
	return n


func can_move(c: Vector2i) -> bool:
	if phase != "hero" or not open_hex(c):
		return false
	var cost := move_cost(c)
	return cost >= 0 and cost <= (stamina if uses_stamina() else MOVES - moved)


func move(c: Vector2i) -> void:
	if not can_move(c):
		return
	if uses_stamina():
		stamina -= move_cost(c)
	moved += steps(c)
	hits = 0
	hero = c
	_wake()


func weak() -> bool:
	return weak_at(hero)


## Whether hex c is in one of the weak arcs the last card left.
func weak_at(c: Vector2i) -> bool:
	if not boss_in_fight():
		return false
	for a in arcs_of(c):
		if a in card.get("weak", []):
			return true
	return false


func attack_label(i: int) -> String:
	return WEAPONS[weapon].acts[i].label


## The damage bonus attack i gets now: its place in the combo.
func attack_bonus(_i := 0) -> float:
	if not uses_stamina():
		return 0.0  # one attack a turn, so no combos
	return COMBO[hits % COMBO.size()]


## The damage attack i does to the enemy at target (the first in reach if
## none is given) from where the hero stands now.
func attack_damage(i: int, target := NONE) -> int:
	if target == NONE:
		target = _default_target()
	return _damage(i, hero, attack_bonus(i), target)


## Weak arcs are the boss's only.
func _damage(i: int, at: Vector2i, bonus: float, target: Vector2i) -> int:
	var dmg: int = WEAPONS[weapon].acts[i].dmg + (WEAK_BONUS if target == boss and weak_at(at) else 0)
	return maxi(0, roundi(dmg * (1.0 + bonus)) - block_of(target))


## Damage taken off every hit on the enemy at c.
func block_of(c: Vector2i) -> int:
	var f := foe_at(c)
	if f >= 0:
		return FOES[foes[f].kind].block
	return BOSS_BLOCK if c == boss else 0


## How near and how far the weapon in hand reaches, in hexes.
func reach() -> Array:
	return WEAPONS[weapon].get("range", [1, 1])


## Whether the weapon in hand can hit the enemy at c from here: next to the
## hero, or for the bow, aimed at it within reach.
func in_reach(c: Vector2i) -> bool:
	if ranged():
		return can_aim(c)
	return enemy_at(c) and dist(hero, c) == 1


## The enemies the weapon in hand can hit from here.
func targets() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in enemies():
		if in_reach(c):
			out.append(c)
	return out


## The enemy an attack's numbers are shown against: the first in reach, else
## the nearest one in the fight.
func _default_target() -> Vector2i:
	var ts := targets()
	if not ts.is_empty():
		return ts[0]
	var best := NONE
	for c in fighting():
		if best == NONE or dist(hero, c) < dist(hero, best):
			best = c
	return best


func can_attack(i: int, target := NONE) -> bool:
	var w: Dictionary = WEAPONS[weapon]
	var paid: bool = stamina >= w.acts[i].st if uses_stamina() else not attacked
	var near_: bool = in_reach(target) if target != NONE else not targets().is_empty()
	return phase == "hero" and near_ and paid and (arrows > 0 or not w.has("arrows"))


## Attack i on the enemy at target (the first in reach if none is given).
## A bow shot hits the first enemy on its way.
func attack(i: int, target := NONE) -> void:
	if target == NONE:
		target = _default_target()
	if not can_attack(i, target):
		return
	if ranged():
		target = shot_path(target).back()
	_strike(i, attack_damage(i, target), target)
	hits += 1


## Every melee weapon has the running attack (its light attack's cost and damage).
func has_run() -> bool:
	return not WEAPONS[weapon].has("range")


## The hexes the running attack can run to: next to an enemy, at least
## RUN_STEPS away, and paid for (the run's steps plus the light attack).
func run_hexes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if phase != "hero" or not has_run() or (attacked and not uses_stamina()):
		return out
	for e in enemies():
		for d in DIRS:
			var c := e + d
			var n := steps(c)
			if c in out or not open_hex(c) or n < RUN_STEPS:
				continue
			if (n + WEAPONS[weapon].acts[0].st <= stamina) if uses_stamina() else (n <= MOVES - moved):
				out.append(c)
	return out


func can_run_attack() -> bool:
	return not run_hexes().is_empty()


## The enemies a running attack ending at c could hit.
func run_targets(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in enemies():
		if dist(c, e) == 1:
			out.append(e)
	return out


## What the running attack would do ending at hex c, on target (the first
## there if none is given).
func run_damage(c: Vector2i, target := NONE) -> int:
	if target == NONE and not run_targets(c).is_empty():
		target = run_targets(c)[0]
	return _damage(0, c, RUN_BONUS, target)


## Run to c and hit target: it counts as the 1st hit of a combo.
func run_attack(c: Vector2i, target := NONE) -> void:
	if target == NONE and not run_targets(c).is_empty():
		target = run_targets(c)[0]
	if not c in run_hexes() or not target in run_targets(c):
		return
	var n := steps(c)
	if uses_stamina():
		stamina -= n
	moved += n
	hero = c
	_strike(0, run_damage(c, target), target)
	hits = 1
	_wake()


## The weapon's own skills.
func skills() -> Array:
	return WEAPONS[weapon].get("skills", [])


func can_skill(key: String) -> bool:
	var paid: bool = stamina >= SKILLS[key].st if uses_stamina() else not attacked
	var near_: bool = not sweep_aims().is_empty() if key == "sweep" else not targets().is_empty()
	if key == "aimed":
		near_ = near_ and arrows > 0
	return phase == "hero" and key in skills() and near_ and paid and not waiting(key)


## Whether skill key is sitting out this turn.
func waiting(key: String) -> bool:
	return turn_no < ready_at.get(key, 0)


## Pay for skill key and start its wait.
func _use_skill(key: String) -> void:
	if uses_stamina():
		stamina -= SKILLS[key].st
	attacked = true
	ready_at[key] = turn_no + SKILL_WAIT + 1
	hits = 0


## A skill's own damage from hex at on target: no combo bonus; pierce skips
## the enemy's block.
func skill_damage(key: String, at := NONE, target := NONE) -> int:
	if at == NONE:
		at = hero
	if target == NONE:
		target = _default_target()
	var s: Dictionary = SKILLS[key]
	var weak_: bool = target == boss and weak_at(at)
	return maxi(0, s.dmg + (WEAK_BONUS if weak_ else 0) - (0 if s.get("pierce", false) else block_of(target)))


## The 3 hexes a sweep centred on the hex in direction i hits.
func sweep_hexes(i: int) -> Array[Vector2i]:
	return [hero + DIRS[posmod(i - 1, 6)], hero + DIRS[i], hero + DIRS[posmod(i + 1, 6)]]


## The directions a sweep can be centred on to catch an enemy.
func sweep_aims() -> Array[int]:
	var out: Array[int] = []
	for i in 6:
		for c in sweep_hexes(i):
			if enemy_at(c):
				out.append(i)
				break
	return out


## A sweep hits every enemy in its 3 hexes.
func sweep(i: int) -> void:
	if not can_skill("sweep") or not i in sweep_aims():
		return
	_use_skill("sweep")
	pace = "mid"
	for c in sweep_hexes(i):
		if enemy_at(c) and phase == "hero":
			_hit(skill_damage("sweep", hero, c), 0, c)


func aimed_shot(target := NONE) -> void:
	if target == NONE:
		target = _default_target()
	if not can_skill("aimed") or not can_aim(target):
		return
	_use_skill("aimed")
	pace = "mid"
	arrows -= 1
	var c: Vector2i = shot_path(target).back()
	_hit(skill_damage("aimed", hero, c), 0, c)


## What the combo attack would do from here: each hit with its combo bonus.
func combo_damage(target := NONE) -> int:
	if target == NONE:
		target = _default_target()
	var total := 0
	for k in SKILLS.combo.hits:
		total += _damage(0, hero, COMBO[k % COMBO.size()], target)
	return total


func combo_attack(target := NONE) -> void:
	if target == NONE:
		target = _default_target()
	if not can_skill("combo") or not in_reach(target):
		return
	_use_skill("combo")
	exposed = true
	pace = "fast"
	for k in SKILLS.combo.hits:
		if phase != "hero" or not enemy_at(target):
			return
		_hit(_damage(0, hero, COMBO[k % COMBO.size()], target), k, target)


func _strike(i: int, dmg: int, target: Vector2i) -> void:
	if uses_stamina():
		stamina -= WEAPONS[weapon].acts[i].st
	attacked = true
	pace = WEAPONS[weapon].acts[i].pace
	if WEAPONS[weapon].has("arrows"):
		arrows -= 1
	_hit(dmg, 0, target)


## Hurt the enemy at hex at; by is where the blow came from (the hero if not
## given). k: which hit of a string this is, so the numbers don't sit on each other.
func _hit(dmg: int, k := 0, at := NONE, by := NONE) -> void:
	if at == NONE:
		at = boss
	events.append({"type": "hit", "dmg": dmg, "from": hero if by == NONE else by, "at": at, "k": k})
	var f := foe_at(at)
	if f >= 0:
		foes[f].hp = maxi(0, foes[f].hp - dmg)
		foes[f].awake = true
		if foes[f].hp <= 0:
			events.append({"type": "foe_down", "at": at})
			if phase == "hero":
				_check_clear()
		return
	if at != boss or boss_hp <= 0:
		return
	boss_awake = true
	boss_hp = maxi(0, boss_hp - dmg)
	if boss_hp <= 0:
		phase = "win"
		return
	if boss_hp <= HEAT_AT and not heated:
		heated = true
		deck.append(HEAT_CARDS[rng.randi_range(0, HEAT_CARDS.size() - 1)])
		_shuffle(deck)
		events.append({"type": "heat_up"})


# ---- enemies ----

## The living enemies' hexes: the boss and the small ones.
func enemies() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if boss_hp > 0:
		out.append(boss)
	for f in foes:
		if f.hp > 0:
			out.append(f.at)
	return out


## The living enemies that are in the fight.
func fighting() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if boss_in_fight():
		out.append(boss)
	for f in foes:
		if f.hp > 0 and f.awake:
			out.append(f.at)
	return out


func enemy_at(c: Vector2i) -> bool:
	return (c == boss and boss_hp > 0) or foe_at(c) >= 0


## Which of the small enemies is on hex c, or -1.
func foe_at(c: Vector2i) -> int:
	for k in foes.size():
		if foes[k].at == c and foes[k].hp > 0:
			return k
	return -1


func boss_in_fight() -> bool:
	return boss_hp > 0 and boss_awake


# ---- shooting ----

func ranged() -> bool:
	return WEAPONS[weapon].has("range")


## The hexes an arrow aimed at target flies over, up to and with the first
## enemy it enters; a wall stops it.
func shot_path(target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in line(hero, target):
		if not on_ground(c):
			break
		out.append(c)
		if enemy_at(c):
			break
	return out


## Whether the bow can be aimed at hex c: an enemy within its reach, with an
## enemy on the line before any wall.
func can_aim(c: Vector2i) -> bool:
	var d := dist(hero, c)
	if not ranged() or not enemy_at(c) or d < reach()[0] or d > reach()[1]:
		return false
	var sp := shot_path(c)
	return not sp.is_empty() and enemy_at(sp.back())


## Shoot attack i at target; it hits the first enemy on the way.
func shoot(i: int, target: Vector2i) -> void:
	attack(i, target)


# ---- out of a fight ----

## Whether an enemy at hex at can see the hero: within WAKE hexes, no wall between.
func sees(at: Vector2i) -> bool:
	if dist(at, hero) > WAKE:
		return false
	for c in line(at, hero):
		if not on_ground(c):
			return false
	return true


## Wake every enemy that can see the hero. Out of a fight, that starts one.
func _wake() -> void:
	if phase in ["win", "lose"]:
		return
	var woke := false
	if boss_hp > 0 and not boss_awake and sees(boss):
		boss_awake = true
		woke = true
		waits["boss"] = waits.get("hero", 0.0)
	for k in foes.size():
		var f := foes[k]
		if f.hp > 0 and not f.awake and sees(f.at):
			f.awake = true
			woke = true
			waits["f%d" % k] = waits.get("hero", 0.0)
	if woke and phase == "explore":
		waits = {}
		events.append({"type": "fight"})
		_hero_turn()


## Once no enemy is left in the fight, it's over.
func _check_clear() -> void:
	if phase in ["win", "lose", "explore"] or not fighting().is_empty():
		return
	phase = "explore"
	queue = []
	to_go = []
	incoming = {}
	stamina = STAMINA
	attacked = false
	exposed = false
	hits = 0
	moved = 0
	pace = "slow"
	events.append({"type": "clear"})


## Out of a fight: one step to the next hex c (main walks a path a hex at a time).
func walk(c: Vector2i) -> void:
	if phase != "explore" or dist(hero, c) != 1 or not open_hex(c):
		return
	hero = c
	_wake()


func can_rest() -> bool:
	return phase == "explore" and bonfire != NONE and dist(hero, bonfire) == 1


## Rest at the bonfire: health, flasks and arrows back, skills ready, and the
## small enemies back where they started.
func rest() -> void:
	if not can_rest():
		return
	hp = HERO_HP
	flasks = FLASKS
	stamina = STAMINA
	if _has_bow():
		arrows = ARROWS
	ready_at = {}
	_reset_foes()
	events.append({"type": "rest"})


func can_swap() -> bool:
	return phase in ["hero", "explore"] and spare != "" and (stamina >= SWAP_COST or not uses_stamina() or phase == "explore")


## Swap to the other weapon set. It breaks the combo but isn't an attack,
## so it doesn't cut the stamina back next turn. Free out of a fight.
func swap() -> void:
	if not can_swap():
		return
	if uses_stamina() and phase == "hero":
		stamina -= SWAP_COST
	var w := weapon
	weapon = spare
	spare = w
	hits = 0
	events.append({"type": "swap"})


func can_flask() -> bool:
	return phase in ["hero", "explore"] and flasks > 0 and hp < HERO_HP and (uses_stamina() or not attacked)


## Without stamina a flask takes the turn's attack.
func flask() -> void:
	if not can_flask():
		return
	if not uses_stamina() and phase == "hero":
		attacked = true
	flasks -= 1
	hp = mini(HERO_HP, hp + FLASK_HEAL)
	events.append({"type": "heal"})


func end_turn() -> void:
	if phase != "hero":
		return
	if mode == "order":
		waits["hero"] = waits.get("hero", 0.0) + 100.0 / speed_of("hero")
		_next_turn()
	else:
		_enemy_turn(_actors())


## The enemies in the fight, as turn order keys: boss, f0, f1...
func _actors() -> Array:
	var out := []
	for k in foes.size():
		if foes[k].hp > 0 and foes[k].awake:
			out.append("f%d" % k)
	if boss_in_fight():
		out.append("boss")
	return out


func speed_of(key: String) -> int:
	if key == "hero":
		return WEAPONS[weapon].speed
	if key == "boss":
		return BOSS_SPEED
	return FOES[foes[int(key.substr(1))].kind].speed


## Turn order: whoever has waited least goes; the hero on a tie.
func _next_turn() -> void:
	var best := "hero"
	for k in _actors():
		if waits.get(k, 0.0) < waits.get(best, 0.0):
			best = k
	if best == "hero":
		_hero_turn()
	else:
		_enemy_turn([best])


## Who has the next n turns, starting with this one.
func turn_order(n: int) -> Array[String]:
	var w := {"hero": waits.get("hero", 0.0)}
	for k in _actors():
		w[k] = waits.get(k, 0.0)
	var out: Array[String] = []
	while out.size() < n:
		var best := "hero"
		for k in w:
			if w[k] < w[best]:
				best = k
		out.append(best)
		w[best] += 100.0 / speed_of(best)
	return out


func _hero_turn() -> void:
	phase = "hero"
	turn_no += 1
	if uses_stamina():
		stamina = mini(STAMINA, stamina + STAMINA_BACK + (0 if attacked else REST_BONUS))
	attacked = false
	exposed = false
	hits = 0
	moved = 0
	pace = "slow"
	_wake()


## The enemies in keys go one after the other: the small ones, then the boss.
func _enemy_turn(keys: Array) -> void:
	dodges = 0
	phase = "boss"
	to_go = keys.duplicate()
	queue = []
	_next_actor()


## Load the next enemy's steps; the boss draws its card.
func _next_actor() -> void:
	queue = []
	if to_go.is_empty():
		return
	actor = to_go.pop_front()
	if actor == "boss":
		if deck.is_empty():
			deck = played  # face down again without shuffling: same order
			played = []
		card = deck.pop_front()
		played.append(card)
		for k in card.get("repeat", 1):
			queue.append_array(card.steps)
		events.append({"type": "card"})
	else:
		queue = FOES[foes[int(actor.substr(1))].kind].steps.duplicate()


# ---- the enemies' turn ----

## Resolve the next step of this enemy's turn. When every enemy is done, the
## hero's turn starts (or, in turn order, whoever is next).
func step() -> void:
	if phase != "boss":
		return
	if queue.is_empty():
		if mode == "order":
			waits[actor] = waits.get(actor, 0.0) + 100.0 / speed_of(actor)
		if not to_go.is_empty():
			_next_actor()
			return
		_check_clear()
		if phase != "boss":
			return
		if mode == "order":
			_next_turn()
		else:
			_hero_turn()
		return
	var s: Dictionary = queue.pop_front()
	if actor != "boss":
		_foe_step(int(actor.substr(1)), s)
	elif s.has("move"):
		_boss_move(s.move)
	elif s.has("turn"):
		facing = posmod(facing + s.turn, 6)
	elif s.has("leap"):
		_leap()
	elif s.has("aim"):
		_aim(s.aim[0], s.aim[1])
	elif s.has("attack"):
		_boss_attack(s)


func _foe_step(k: int, s: Dictionary) -> void:
	var f := foes[k]
	if f.hp <= 0:
		queue = []
		return
	if s.has("move"):
		var way := path(f.at, hero)
		for n in mini(s.move, way.size() - 1):
			f.at = way[n]
		if way.size() > 1 and s.move > 0:
			events.append({"type": "foe_move"})
	elif s.has("arm"):
		var want := "shortsword" if dist(f.at, hero) == 1 else "crossbow"
		if want != f.held:
			f.held = want
			events.append({"type": "foe_arm"})
	elif s.has("attack"):
		var a: Dictionary = FOE_ATTACKS[f.held]
		if not a.has("range"):
			if dist(f.at, hero) == 1:
				_hits_hero(a, f.at)
		elif dist(f.at, hero) <= a.range:
			_bolt(a, f.at)
	f.facing = _facing_from(f.at, hero)


## A bolt from hex from at the hero hits the first body on its line; a wall
## in the way means no shot.
func _bolt(a: Dictionary, from: Vector2i) -> void:
	for c in line(from, hero):
		if not on_ground(c):
			return
		if c == hero or enemy_at(c):
			events.append({"type": "bolt", "from": from, "to": c})
			if c == hero:
				_hits_hero(a, from)
			else:
				_hit(a.dmg, 0, c, from)
			return


## A small enemy's attack a, from hex from, reaches the hero.
func _hits_hero(a: Dictionary, from: Vector2i) -> void:
	events.append({"type": "attack", "hexes": [hero], "hit": true})
	incoming = {"name": a.name, "dmg": a.dmg, "dodge": a.dodge, "push": false, "heavy": false, "hexes": [hero], "from": from}
	phase = "defend"


func _boss_move(n: int) -> void:
	for k in absi(n):
		var here := dist(boss, hero)
		if n > 0 and here == 1:
			facing = DIRS.find(hero - boss)
			return
		var best := -1
		for i in 6:
			var c := boss + DIRS[i]
			if not open_hex(c):
				continue
			var d := dist(c, hero)
			if (n > 0 and d >= here) or (n < 0 and d <= here):
				continue
			# moving forward the boss faces where it goes; backing off, its back does
			var f := i if n > 0 else (i + 3) % 6
			var bf := best if n > 0 else (best + 3) % 6
			if best < 0 or _turns(f, facing) < _turns(bf, facing):
				best = i
		if best < 0:
			return
		facing = best if n > 0 else (best + 3) % 6
		boss += DIRS[best]
		events.append({"type": "boss_move"})


func _leap() -> void:
	var best := boss
	var bd := 999
	for d in DIRS:
		var c := hero + d
		if (open_hex(c) or c == boss) and dist(c, boss) < bd:
			best = c
			bd = dist(c, boss)
	boss = best
	events.append({"type": "boss_move"})


## Turn and step, within the budget, so the next attack in the queue hits the
## hero, with as few moves as it can. If nothing reaches, end up as close and
## as nearly facing the hero as the budget allows.
func _aim(turns: int, moves: int) -> void:
	var s: Dictionary = {}
	for q in queue:
		if q.has("attack"):
			s = q
			break
	if s.is_empty():
		return
	var start := [boss, facing]
	var best := start
	var best_score := INF
	# [position, facing, turns used, steps used]
	var open: Array = [[boss, facing, 0, 0]]
	var seen := {}
	while not open.is_empty():
		var st: Array = open.pop_front()
		var key := "%s %d" % [st[0], st[1]]
		if seen.has(key):
			continue
		seen[key] = true
		boss = st[0]
		facing = st[1]
		var score: float
		if hero in attack_hexes(s):
			score = st[2] + st[3] * 1.5
		else:
			score = 100.0 + dist(boss, hero) * 10.0 + _turns(facing, _facing_to(hero))
		if score < best_score:
			best_score = score
			best = [st[0], st[1]]
		if st[2] < turns:
			for k in [1, -1]:
				open.append([st[0], posmod(st[1] + k, 6), st[2] + 1, st[3]])
		if st[3] < moves:
			for d in DIRS:
				if open_hex(st[0] + d):
					open.append([st[0] + d, st[1], st[2], st[3] + 1])
	boss = best[0]
	facing = best[1]
	if best != start:
		events.append({"type": "boss_move"})


## The facing that points the boss most nearly at hex c.
func _facing_to(c: Vector2i) -> int:
	return _facing_from(boss, c)


static func _facing_from(a: Vector2i, c: Vector2i) -> int:
	var to := flat(c - a).normalized()
	var best := 0
	for i in 6:
		if flat(DIRS[i]).dot(to) > flat(DIRS[best]).dot(to):
			best = i
	return best


## The hexes attack step s covers: its arcs within range, or just the hero.
func attack_hexes(s: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not s.has("arcs"):
		if dist(hero, boss) <= s["range"]:
			out.append(hero)
		return out
	for c in ground:
		if c != boss and dist(c, boss) <= s["range"]:
			for a in arcs_of(c):
				if a in s.arcs:
					out.append(c)
					break
	return out


func _boss_attack(s: Dictionary) -> void:
	var hexes := attack_hexes(s)
	var hit := hexes.has(hero)
	events.append({"type": "attack", "hexes": hexes, "hit": hit})
	if hit:
		incoming = {"name": card.name, "dmg": s.attack, "dodge": card.dodge, "push": s.get("push", false), "heavy": s.get("heavy", false), "hexes": hexes, "from": boss}
		phase = "defend"


## Damage taken off a blocked hit: shield plus armour.
func block() -> int:
	return WEAPONS[weapon].block + ARMOURS[armour].block


## What blocking the incoming hit would cost in health.
func block_damage() -> int:
	return maxi(0, incoming.dmg - block())


## Stamina it takes to block the incoming hit.
func block_cost() -> int:
	return HEAVY_BLOCK_COST if incoming.get("heavy", false) else BLOCK_COST


func can_block() -> bool:
	return phase == "defend" and not exposed and (stamina >= block_cost() or not uses_stamina())


func defend_block() -> void:
	if not can_block():
		return
	if uses_stamina():
		stamina -= block_cost()
	_hurt(block_damage())
	if incoming.push:
		_push()
	_defended()


## Neither block nor dodge: the full hit, for no stamina.
func take_hit() -> void:
	if phase != "defend":
		return
	_hurt(incoming.dmg)
	if incoming.push:
		_push()
	_defended()


func can_dodge() -> bool:
	return phase == "defend" and not exposed and (stamina >= dodge_cost() or not uses_stamina())


## What the next dodge this boss turn costs: 1, then 2, then 3...
func dodge_cost() -> int:
	return DODGE_COST * (dodges + 1)


## Where a dodge can land: stay put, or one hex.
func dodge_hexes() -> Array[Vector2i]:
	var out: Array[Vector2i] = [hero]
	for d in DIRS:
		if open_hex(hero + d):
			out.append(hero + d)
	return out


## Dodge to c; ok is whether the timing check was hit.
func defend_dodge(c: Vector2i, ok: bool) -> void:
	if not can_dodge() or not c in dodge_hexes():
		return
	if uses_stamina():
		stamina -= dodge_cost()
	dodges += 1
	hero = c
	if ok:
		events.append({"type": "dodged"})
	else:
		_hurt(incoming.dmg)
		if incoming.push:
			_push()
	_defended()


func _hurt(dmg: int) -> void:
	hp = maxi(0, hp - dmg)
	events.append({"type": "hit_hero", "dmg": dmg})


## Push the hero one hex farther from whoever hit it, as straight away as it can.
func _push() -> void:
	var by: Vector2i = incoming.get("from", boss)
	var away := flat(hero - by).normalized()
	var best := hero
	var score := -INF
	for d in DIRS:
		var c := hero + d
		if open_hex(c) and dist(c, by) > dist(hero, by) and flat(d).dot(away) > score:
			best = c
			score = flat(d).dot(away)
	hero = best


func _defended() -> void:
	incoming = {}
	phase = "lose" if hp <= 0 else "boss"


# ---- the dodge check ----

## How long the bar takes to fill, by the attack's dodge difficulty (PLACEHOLDER).
const BAR_TIME := {1: 1.3, 2: 1.1, 3: 0.9}
const SWEET_START := 0.72
const SWEET_WIDTH := {1: 0.11, 2: 0.08, 3: 0.06}


## How the next dodge's bar is paced: by the stamina left after paying for
## it, or without stamina by this turn's attack.
func dodge_pace() -> String:
	if not uses_stamina():
		return pace
	var left := stamina - dodge_cost()
	return "slow" if left >= 5 else ("mid" if left >= 3 else "fast")


## How long the next dodge's bar takes, times the attack's own time.
## Heavy armour fills it sooner, so there's less time to react.
func dodge_time() -> float:
	return ARMOURS[armour].bar * PACE[dodge_pace()]


## How full the bar is t seconds in: it speeds up the fuller it gets.
static func bar(t: float, diff: int, time := 1.0) -> float:
	return pow(t / (BAR_TIME[diff] * time), 2.0)


## The sweet spot as (start, end) along the bar; the same whatever the armour.
static func sweet(diff: int) -> Vector2:
	return Vector2(SWEET_START, SWEET_START + SWEET_WIDTH[diff])
