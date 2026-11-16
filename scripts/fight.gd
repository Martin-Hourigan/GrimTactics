class_name Fight
extends RefCounted
## The rules of one fight: the hero against the boss in one hex room.
## No drawing here; main.gd shows it, tests.gd checks it.

const ROOM := 3  ## room radius in hexes (PLACEHOLDER)
## Axial directions, counter-clockwise from the right. Facing f points along DIRS[f].
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

const DICE := {  ## faces (PLACEHOLDER)
	"black": [0, 1, 1, 1, 2, 2],
	"blue": [1, 1, 2, 2, 2, 3],
}

# ---- hero (all PLACEHOLDER) ----
const HERO_HP := 20
const STAMINA := 6  ## the stamina bar; the fight starts with it full
const STAMINA_BACK := 2  ## stamina regained at the start of every hero turn
const REST_BONUS := 2  ## extra stamina back after a turn with no attack
const FLASKS := 2
const FLASK_HEAL := 10
const DODGE_COST := 1  ## the first dodge in a boss turn; each further dodge costs this much more
const WEAPONS := {
	"longsword": {"label": "Longsword & shield", "block": ["black"], "acts": [
		{"label": "Slash", "st": 1, "dice": ["black", "black"]},
		{"label": "Heavy slash", "st": 2, "dice": ["black", "blue"]},
	]},
	"claymore": {"label": "Claymore", "block": [], "acts": [
		{"label": "Swing", "st": 1, "dice": ["black", "blue"]},
		{"label": "Heavy swing", "st": 3, "dice": ["black", "blue", "blue"]},
	]},
}
## window: how wide the dodge sweet spot is
const ARMOURS := {
	"light": {"label": "Light armour", "block": ["black"], "window": 1.4},
	"heavy": {"label": "Heavy armour", "block": ["black", "blue"], "window": 0.7},
}

# ---- boss (all PLACEHOLDER) ----
const BOSS_HP := 40
const BOSS_BLOCK := 1
const HEAT_AT := 18  ## heats up at this health or below
const DECK_SIZE := 4
## Behaviour cards. Steps run left to right:
##   move n (towards the hero, or away if negative), turn k (60 degrees each,
##   counter-clockwise), leap (next to the hero, facing kept),
##   aim [turns, steps]: before the next attack it may turn up to this many
##     times and step up to this many hexes (facing kept) to bring the hero
##     into that attack,
##   attack dmg within range: the hero only, or every hex in the listed arcs.
## dodge = how hard the dodge check is (1-3). weak = arcs that take an extra die.
const CARDS := [
	{"name": "Lunge", "dodge": 1, "weak": ["back"], "steps": [{"move": 2}, {"aim": [1, 0]}, {"attack": 5, "range": 1, "arcs": ["front"]}]},
	{"name": "Sweep", "dodge": 1, "weak": ["back"], "steps": [{"aim": [1, 0]}, {"attack": 4, "range": 1, "arcs": ["front", "left", "right"]}]},
	{"name": "Turn and cut", "dodge": 2, "weak": ["left", "right"], "steps": [{"turn": 3}, {"aim": [1, 0]}, {"attack": 6, "range": 1, "arcs": ["front"], "push": true}]},
	{"name": "Overhead", "dodge": 1, "weak": ["left", "right"], "steps": [{"aim": [1, 1]}, {"attack": 8, "range": 1, "arcs": ["front"]}]},
	{"name": "Shield bash", "dodge": 2, "weak": ["back"], "steps": [{"aim": [2, 1]}, {"attack": 3, "range": 1, "arcs": ["front"], "push": true}]},
	{"name": "Step back, thrust", "dodge": 2, "weak": ["left"], "steps": [{"move": -1}, {"aim": [1, 0]}, {"attack": 5, "range": 2, "arcs": ["front"]}]},
]
const HEAT_CARDS := [
	{"name": "Leap", "dodge": 2, "weak": ["back"], "steps": [{"leap": true}, {"attack": 6, "range": 1, "arcs": ["front", "left", "right", "back"]}]},
	{"name": "Flurry", "dodge": 3, "weak": ["back"], "repeat": 2, "steps": [{"aim": [1, 1]}, {"attack": 4, "range": 1, "arcs": ["front"]}]},
]

var weapon: String
var armour: String
var hp := HERO_HP
var stamina := STAMINA
var dodges := 0  ## dodges made this boss turn
var flasks := FLASKS
var hero := Vector2i(0, 3)
var free_step := true
var attacked := false
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


func _init(weapon_ := "longsword", armour_ := "light", seed_ := 1) -> void:
	weapon = weapon_
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


# ---- dice ----

## Chance of each total for these dice.
static func spread(dice: Array) -> Dictionary:
	var out := {0: 1.0}
	for die in dice:
		var next := {}
		for total in out:
			for face in DICE[die]:
				next[total + face] = next.get(total + face, 0.0) + out[total] / 6.0
		out = next
	return out


## Lowest, highest and average damage when these dice attack something with this block.
static func hit_odds(dice: Array, block: int) -> Dictionary:
	return _odds(spread(dice), func(total): return maxi(0, total - block))


## Lowest, highest and average damage taken from dmg when blocking with these dice.
static func block_odds(dmg: int, dice: Array) -> Dictionary:
	return _odds(spread(dice), func(total): return maxi(0, dmg - total))


static func _odds(sp: Dictionary, f: Callable) -> Dictionary:
	var lo := 999
	var hi := -1
	var avg := 0.0
	for total in sp:
		var v: int = f.call(total)
		lo = mini(lo, v)
		hi = maxi(hi, v)
		avg += v * sp[total]
	return {"min": lo, "max": hi, "avg": avg}


func roll(dice: Array) -> int:
	var total := 0
	for die in dice:
		total += DICE[die][rng.randi_range(0, 5)]
	return total


# ---- the hero's turn ----

func move_cost(c: Vector2i) -> int:
	var n := steps(c)
	if n < 0:
		return -1
	return maxi(0, n - (1 if free_step else 0))


func can_move(c: Vector2i) -> bool:
	if phase != "hero" or not open_hex(c):
		return false
	var cost := move_cost(c)
	return cost >= 0 and cost <= stamina


func move(c: Vector2i) -> void:
	if not can_move(c):
		return
	stamina -= move_cost(c)
	free_step = false
	hero = c


func weak() -> bool:
	return weak_at(hero)


## Whether hex c is in one of the weak arcs the last card left.
func weak_at(c: Vector2i) -> bool:
	for a in arcs_of(c):
		if a in card.get("weak", []):
			return true
	return false


## The dice attack i would roll from where the hero stands now.
func attack_dice(i: int) -> Array:
	var dice: Array = WEAPONS[weapon].acts[i].dice.duplicate()
	if weak():
		dice.append("black")
	return dice


func can_attack(i: int) -> bool:
	return phase == "hero" and dist(hero, boss) == 1 \
		and stamina >= WEAPONS[weapon].acts[i].st


func attack(i: int) -> void:
	if not can_attack(i):
		return
	stamina -= WEAPONS[weapon].acts[i].st
	attacked = true
	var dice := attack_dice(i)
	var total := roll(dice)
	var dmg := maxi(0, total - BOSS_BLOCK)
	boss_hp = maxi(0, boss_hp - dmg)
	events.append({"type": "hit_boss", "dmg": dmg, "rolled": total})
	if boss_hp <= 0:
		phase = "win"
		return
	if boss_hp <= HEAT_AT and not heated:
		heated = true
		deck.append(HEAT_CARDS[rng.randi_range(0, HEAT_CARDS.size() - 1)])
		_shuffle(deck)
		events.append({"type": "heat_up"})


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
		free_step = true
		attacked = false
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


func block_dice() -> Array:
	return WEAPONS[weapon].block + ARMOURS[armour].block


func defend_block() -> void:
	if phase != "defend":
		return
	var dmg := maxi(0, incoming.dmg - roll(block_dice()))
	_hurt(dmg)
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
const SWEET_WIDTH := {1: 0.16, 2: 0.12, 3: 0.08}


## How full the bar is t seconds in: it speeds up the fuller it gets.
static func bar(t: float, diff: int) -> float:
	return pow(t / BAR_TIME[diff], 2.0)


## The sweet spot as (start, end) along the bar.
static func sweet(diff: int, armour_: String) -> Vector2:
	var w: float = SWEET_WIDTH[diff] * ARMOURS[armour_].window
	return Vector2(SWEET_START, minf(1.0, SWEET_START + w))
