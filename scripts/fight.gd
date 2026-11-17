class_name Fight
extends RefCounted
## The rules of one fight: the hero against the boss in one hex room.
## No drawing here; main.gd shows it, tests.gd checks it.

const ROOM := 3  ## room radius in hexes (PLACEHOLDER)
## Axial directions, counter-clockwise from the right. Facing f points along DIRS[f].
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

# ---- hero (all PLACEHOLDER) ----
const HERO_HP := 200
const STAMINA := 6  ## the stamina bar; the fight starts with it full
const STAMINA_BACK := 2  ## stamina regained at the start of every hero turn
const REST_BONUS := 4  ## extra stamina back after a turn with no attack
const FLASKS := 2
const FLASK_HEAL := 100
const DODGE_COST := 1  ## the first dodge in a boss turn; each further dodge costs this much more
const SWAP_COST := 1  ## swapping to the other weapon set
const WEAK_BONUS := 10  ## extra damage from a weak arc
const COMBO := [0.0, 0.1, 0.2]  ## damage bonus on the 1st, 2nd and 3rd hit in a row; then it starts again
const RUN_STEPS := 2  ## hexes moved since the last attack that turn the first attack into a running one
const RUN_BONUS := 0.2  ## a running attack's damage bonus; it counts as the 1st hit of a combo
## Each weapon's first attack becomes its "run" attack after a run.
const WEAPONS := {
	"longsword": {"label": "Longsword & shield", "block": 10, "acts": [
		{"label": "Slash", "st": 1, "dmg": 25, "run": "Running slash"},
		{"label": "Heavy slash", "st": 2, "dmg": 35},
	]},
	"claymore": {"label": "Claymore", "block": 0, "acts": [
		{"label": "Swing", "st": 1, "dmg": 35, "run": "Running swing"},
		{"label": "Heavy swing", "st": 3, "dmg": 55},
	]},
}
## block: damage taken off each blocked hit. bar: how long the dodge bar takes to fill (x)
const ARMOURS := {
	"light": {"label": "Light armour", "block": 10, "bar": 1.0},
	"heavy": {"label": "Heavy armour", "block": 30, "bar": 0.75},
}

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
##   attack dmg within range: the hero only, or every hex in the listed arcs.
## dodge = how hard the dodge check is (1-3). weak = arcs that take extra damage.
const CARDS := [
	{"name": "Lunge", "dodge": 1, "weak": ["back"], "steps": [{"move": 2}, {"aim": [1, 0]}, {"attack": 50, "range": 1, "arcs": ["front"]}]},
	{"name": "Sweep", "dodge": 1, "weak": ["back"], "steps": [{"aim": [1, 0]}, {"attack": 40, "range": 1, "arcs": ["front", "left", "right"]}]},
	{"name": "Turn and cut", "dodge": 2, "weak": ["left", "right"], "steps": [{"turn": 3}, {"aim": [1, 0]}, {"attack": 60, "range": 1, "arcs": ["front"], "push": true}]},
	{"name": "Overhead", "dodge": 1, "weak": ["left", "right"], "steps": [{"aim": [1, 1]}, {"attack": 80, "range": 1, "arcs": ["front"]}]},
	{"name": "Shield bash", "dodge": 2, "weak": ["back"], "steps": [{"aim": [2, 1]}, {"attack": 30, "range": 1, "arcs": ["front"], "push": true}]},
	{"name": "Step back, thrust", "dodge": 2, "weak": ["left"], "steps": [{"move": -1}, {"aim": [1, 0]}, {"attack": 50, "range": 2, "arcs": ["front"]}]},
]
const HEAT_CARDS := [
	{"name": "Leap", "dodge": 2, "weak": ["back"], "steps": [{"leap": true}, {"attack": 60, "range": 1, "arcs": ["front", "left", "right", "back"]}]},
	{"name": "Flurry", "dodge": 3, "weak": ["back"], "repeat": 2, "steps": [{"aim": [1, 1]}, {"attack": 40, "range": 1, "arcs": ["front"]}]},
]

var weapon: String  ## the weapon in hand
var spare: String  ## the other weapon set; empty if there isn't one
var armour: String
var hp := HERO_HP
var stamina := STAMINA
var dodges := 0  ## dodges made this boss turn
var flasks := FLASKS
var hero := Vector2i(0, 3)
var attacked := false
var hits := 0  ## hits in a row this turn without moving
var run := 0  ## hexes moved since the last attack this turn
var boss := Vector2i.ZERO
var facing := 5
var boss_hp := BOSS_HP
var heated := false
var deck: Array = []
var played: Array = []  ## this loop's cards, in the order they came
var card: Dictionary = {}  ## the card on top of the discard pile
var queue: Array = []  ## steps left on the boss's turn
var incoming: Dictionary = {}  ## the attack the hero has to block or dodge now
var phase := "hero"  ## hero, boss, defend, win, lose
var events: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


func _init(weapon_ := "longsword", armour_ := "light", seed_ := 1, spare_ := "") -> void:
	weapon = weapon_
	spare = spare_
	armour = armour_
	rng.seed = seed_
	var pool := CARDS.duplicate()
	_shuffle(pool)
	deck = pool.slice(0, DECK_SIZE)
	_shuffle(deck)


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


static func in_room(c: Vector2i) -> bool:
	return dist(c, Vector2i.ZERO) <= ROOM


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
	return in_room(c) and c != boss and c != hero


## Steps from the hero to c, going round the boss. -1 if it can't get there.
func steps(c: Vector2i) -> int:
	if not in_room(c) or c == boss:
		return -1
	var seen := {hero: 0}
	var open: Array[Vector2i] = [hero]
	while not open.is_empty():
		var at: Vector2i = open.pop_front()
		if at == c:
			return seen[at]
		for d in DIRS:
			var n := at + d
			if in_room(n) and n != boss and not seen.has(n):
				seen[n] = seen[at] + 1
				open.append(n)
	return -1


# ---- the hero's turn ----

func move_cost(c: Vector2i) -> int:
	var n := steps(c)
	if n < 0:
		return -1
	return n


func can_move(c: Vector2i) -> bool:
	if phase != "hero" or not open_hex(c):
		return false
	var cost := move_cost(c)
	return cost >= 0 and cost <= stamina


func move(c: Vector2i) -> void:
	if not can_move(c):
		return
	stamina -= move_cost(c)
	run += steps(c)
	hits = 0
	hero = c


func weak() -> bool:
	return weak_at(hero)


## Whether hex c is in one of the weak arcs the last card left.
func weak_at(c: Vector2i) -> bool:
	for a in arcs_of(c):
		if a in card.get("weak", []):
			return true
	return false


## Whether attack i would be a running attack now.
func running(i: int) -> bool:
	return WEAPONS[weapon].acts[i].has("run") and run >= RUN_STEPS


func attack_label(i: int) -> String:
	var a: Dictionary = WEAPONS[weapon].acts[i]
	return a.run if running(i) else a.label


## The damage bonus attack i gets now: running, or its place in the combo.
func attack_bonus(i: int) -> float:
	if running(i):
		return RUN_BONUS
	return COMBO[hits % COMBO.size()]


## The damage attack i does to the boss from where the hero stands now.
func attack_damage(i: int) -> int:
	var dmg: int = WEAPONS[weapon].acts[i].dmg + (WEAK_BONUS if weak() else 0)
	return maxi(0, roundi(dmg * (1.0 + attack_bonus(i))) - BOSS_BLOCK)


func can_attack(i: int) -> bool:
	return phase == "hero" and dist(hero, boss) == 1 \
		and stamina >= WEAPONS[weapon].acts[i].st


func attack(i: int) -> void:
	if not can_attack(i):
		return
	var dmg := attack_damage(i)
	stamina -= WEAPONS[weapon].acts[i].st
	attacked = true
	hits = 1 if running(i) else hits + 1
	run = 0
	boss_hp = maxi(0, boss_hp - dmg)
	events.append({"type": "hit_boss", "dmg": dmg})
	if boss_hp <= 0:
		phase = "win"
		return
	if boss_hp <= HEAT_AT and not heated:
		heated = true
		deck.append(HEAT_CARDS[rng.randi_range(0, HEAT_CARDS.size() - 1)])
		_shuffle(deck)
		events.append({"type": "heat_up"})


func can_swap() -> bool:
	return phase == "hero" and spare != "" and stamina >= SWAP_COST


## Swap to the other weapon set. It breaks the combo but isn't an attack,
## so it doesn't cut the stamina back next turn.
func swap() -> void:
	if not can_swap():
		return
	stamina -= SWAP_COST
	var w := weapon
	weapon = spare
	spare = w
	hits = 0
	events.append({"type": "swap"})


func can_flask() -> bool:
	return phase == "hero" and flasks > 0 and hp < HERO_HP


func flask() -> void:
	if not can_flask():
		return
	flasks -= 1
	hp = mini(HERO_HP, hp + FLASK_HEAL)
	events.append({"type": "heal"})


func end_turn() -> void:
	if phase != "hero":
		return
	dodges = 0
	phase = "boss"
	if deck.is_empty():
		deck = played  # face down again without shuffling: same order
		played = []
	card = deck.pop_front()
	played.append(card)
	queue = []
	for k in card.get("repeat", 1):
		queue.append_array(card.steps)
	events.append({"type": "card"})


# ---- the boss's turn ----

## Resolve the next step of the boss's card. When the card is done, the hero's turn starts.
func step() -> void:
	if phase != "boss":
		return
	if queue.is_empty():
		phase = "hero"
		stamina = mini(STAMINA, stamina + STAMINA_BACK + (0 if attacked else REST_BONUS))
		attacked = false
		hits = 0
		run = 0
		return
	var s: Dictionary = queue.pop_front()
	if s.has("move"):
		_boss_move(s.move)
	elif s.has("turn"):
		facing = posmod(facing + s.turn, 6)
	elif s.has("leap"):
		_leap()
	elif s.has("aim"):
		_aim(s.aim[0], s.aim[1])
	elif s.has("attack"):
		_boss_attack(s)


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


## The facing that points most nearly at hex c.
func _facing_to(c: Vector2i) -> int:
	var to := flat(c - boss).normalized()
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
	for c in room():
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
		incoming = {"name": card.name, "dmg": s.attack, "dodge": card.dodge, "push": s.get("push", false), "hexes": hexes}
		phase = "defend"


## Damage taken off a blocked hit: shield plus armour.
func block() -> int:
	return WEAPONS[weapon].block + ARMOURS[armour].block


## What blocking the incoming hit would cost in health.
func block_damage() -> int:
	return maxi(0, incoming.dmg - block())


func defend_block() -> void:
	if phase != "defend":
		return
	_hurt(block_damage())
	if incoming.push:
		_push()
	_defended()


func can_dodge() -> bool:
	return phase == "defend" and stamina >= dodge_cost()


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


## Push the hero one hex farther from the boss, as straight away as it can.
func _push() -> void:
	var away := flat(hero - boss).normalized()
	var best := hero
	var score := -INF
	for d in DIRS:
		var c := hero + d
		if open_hex(c) and dist(c, boss) > dist(hero, boss) and flat(d).dot(away) > score:
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


## How full the bar is t seconds in: it speeds up the fuller it gets.
## Heavy armour fills it sooner, so there's less time to react.
static func bar(t: float, diff: int, armour_ := "light") -> float:
	return pow(t / (BAR_TIME[diff] * ARMOURS[armour_].bar), 2.0)


## The sweet spot as (start, end) along the bar; the same whatever the armour.
static func sweet(diff: int) -> Vector2:
	return Vector2(SWEET_START, SWEET_START + SWEET_WIDTH[diff])
