extends RefCounted
## Headless checks that the fight works (not how it plays or balances).
## godot --headless --path . -- --smoke

static var fails := 0


static func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


## A simple stand-in player. On its turn: get next to the boss, ideally in a
## weak arc, hit it, drink when low. When attacked: dodge when it can, half
## the dodge checks are hit.
static func bot(f: Fight) -> void:
	if f.phase == "defend":
		if f.can_dodge():
			f.defend_dodge(f.dodge_hexes().back(), f.rng.randf() < 0.5)
		elif f.can_block():
			f.defend_block()
		else:
			f.take_hit()
		return
	if f.phase != "hero":
		return
	if f.hp <= 8:
		f.flask()
	if Fight.dist(f.hero, f.boss) > 1 or not f.weak():
		var best := f.hero
		var score := -1
		for d in Fight.DIRS:
			var c := f.boss + d
			if not f.can_move(c):
				continue
			var s := 10 - f.move_cost(c) + (5 if f.weak_at(c) else 0)
			if s > score:
				best = c
				score = s
		if best != f.hero:
			f.move(best)
	var acts: Array = Fight.WEAPONS[f.weapon].acts
	var hit := true
	while hit:
		hit = false
		for i in range(acts.size() - 1, -1, -1):
			# keep a point back for a dodge
			if f.can_attack(i) and f.stamina - acts[i].st >= Fight.DODGE_COST:
				f.attack(i)
				hit = true
				break
	if not f.attacked and f.can_attack(0):
		f.attack(0)
	f.end_turn()


static func run() -> int:
	fails = 0
	print("GrimTactics tests")

	print("room and arcs")
	check(Fight.room().size() == 37, "room of radius 3 has 37 hexes")
	var f := Fight.new("longsword", "light", 1)
	f.facing = 0
	check(f.arcs_of(Vector2i(1, 0)) == ["front"], "the hex it faces is front only")
	check(f.arcs_of(Vector2i(-1, 0)) == ["back"], "the hex behind is back only")
	check(f.arcs_of(Vector2i(1, -1)) == ["left"] and f.arcs_of(Vector2i(0, -1)) == ["left"], "two hexes on its left")
	check(f.arcs_of(Vector2i(0, 1)) == ["right"] and f.arcs_of(Vector2i(-1, 1)) == ["right"], "two hexes on its right")
	check(f.arcs_of(Vector2i(2, -1)).size() == 2 and "front" in f.arcs_of(Vector2i(2, -1)) and "left" in f.arcs_of(Vector2i(2, -1)), "a hex on the line between front and left is in both")
	f.facing = 3
	check(f.arcs_of(Vector2i(1, 0)) == ["back"], "turned round, front becomes back")

	print("moving")
	f = Fight.new("longsword", "light", 1)
	check(f.move_cost(f.hero + Fight.DIRS[2]) == 1, "one step costs 1 stamina")
	check(f.move_cost(Vector2i(0, 1)) == 2, "two steps cost 2")
	f.move(Vector2i(0, 2))
	check(f.stamina == Fight.STAMINA - 1 and f.hero == Vector2i(0, 2), "paid for the step")
	check(not f.can_move(f.boss), "can't stand on the boss")
	f.move(Vector2i(0, 1))
	check(f.stamina == Fight.STAMINA - 2, "paid for the second step")

	print("attacking")
	check(f.can_attack(0), "next to the boss it can attack")
	f.attack(0)
	f.stamina = 0
	check(not f.can_attack(0) and not f.can_attack(1), "no attack without the stamina")
	f = Fight.new("claymore", "heavy", 1)
	check(not f.can_attack(0), "not from across the room")
	f.hero = Vector2i(0, 1)
	f.card = {"weak": ["back"]}
	f.facing = 2  # faces up-left, so (0, 1) is behind it
	var base: int = Fight.WEAPONS.claymore.acts[0].dmg
	check(f.weak() and f.attack_damage(0) == base + Fight.WEAK_BONUS - Fight.BOSS_BLOCK, "a weak arc adds damage")
	f.facing = 5
	check(not f.weak() and f.attack_damage(0) == base - Fight.BOSS_BLOCK, "not weak from the front, and no dice")
	f.stamina = 2
	check(not f.can_attack(1), "the claymore heavy attack needs more stamina")

	print("combos and running attacks")
	f = Fight.new("longsword", "light", 1)
	f.hero = f.boss + Fight.DIRS[0]
	f.facing = 0
	base = Fight.WEAPONS.longsword.acts[0].dmg
	var dealt: Array[int] = []
	for k in 5:
		var hp0 := f.boss_hp
		f.stamina = Fight.STAMINA  # enough for every hit
		f.attack(0)
		dealt.append(hp0 - f.boss_hp)
	check(dealt[0] == base - Fight.BOSS_BLOCK, "the first hit has no bonus")
	check(dealt[1] == roundi(base * 1.1) - Fight.BOSS_BLOCK, "the second hit +10%")
	check(dealt[2] == roundi(base * 1.2) - Fight.BOSS_BLOCK, "the third hit +20%")
	check(dealt[3] == dealt[0] and dealt[4] == dealt[1], "after the third hit the combo starts again")
	f.stamina = Fight.STAMINA
	f.move(f.boss + Fight.DIRS[1])
	check(f.attack_bonus(0) == 0.0, "a step breaks the combo")
	f = Fight.new("longsword", "light", 1)
	f.facing = 0
	f.hero = f.boss + Fight.DIRS[0]
	check(not f.boss + Fight.DIRS[1] in f.run_hexes(), "the running attack needs a run of at least 2 hexes")
	f.hero = f.boss + Fight.DIRS[0] * 3
	var run_to := f.boss + Fight.DIRS[0]
	check(run_to in f.run_hexes() and f.run_damage(run_to) == roundi(base * 1.2) - Fight.BOSS_BLOCK, "from 2 hexes off it can run in and hit, +20%")
	var hp0 := f.boss_hp
	f.run_attack(run_to)
	check(f.hero == run_to and f.boss_hp == hp0 - f.run_damage(run_to), "it runs there and hits")
	check(f.stamina == Fight.STAMINA - 2 - Fight.WEAPONS.longsword.acts[0].st, "paying for the steps and the light attack")
	check(f.attack_bonus(0) == 0.1, "after a running attack the next hit is the second in the combo")
	f.attack(0)
	f.end_turn()
	f.queue = []
	f.step()
	check(f.hits == 0, "a new turn starts a new combo")
	f = Fight.new("bow", "light", 1)
	f.hero = f.boss + Fight.DIRS[0] * 3
	check(not f.can_run_attack() and Fight.new("claymore", "light", 1).has_run(), "every melee weapon has the running attack, the bow doesn't")
	f = Fight.new("claymore", "light", 1)
	f.hero = f.boss + Fight.DIRS[0] * 3
	f.stamina = 3
	check(not f.can_run_attack(), "not without the stamina for the run and the hit")

	print("behaviour deck")
	f = Fight.new("longsword", "light", 3)
	f.hero = Vector2i(0, -3)  # far away, so nothing is defended
	var first: Array = []
	for k in Fight.DECK_SIZE:
		f.end_turn()
		first.append(f.card.name)
		_finish_boss_turn(f)
		f.hero = _far_hex(f)
	var second: Array = []
	for k in Fight.DECK_SIZE:
		f.end_turn()
		second.append(f.card.name)
		_finish_boss_turn(f)
		f.hero = _far_hex(f)
	check(first.size() == Fight.DECK_SIZE and first == second, "the deck comes round again in the same order")
	f.boss_hp = Fight.HEAT_AT + 1
	var before := f.deck.size() + f.played.size()
	f.hero = f.boss + Fight.DIRS[0]
	f.phase = "hero"
	f.attacked = false
	f.stamina = 5
	while f.boss_hp > Fight.HEAT_AT:
		f.attacked = false
		f.attack(1)
	check(f.heated and f.deck.size() + f.played.size() == before + 1, "heat up adds one card")

	print("the boss moves and attacks")
	f = Fight.new("longsword", "light", 1)
	f.hero = Vector2i(0, 3)
	f.facing = 0
	f.phase = "boss"
	f.card = {"name": "test", "dodge": 1, "weak": []}
	f.queue = [{"move": 2}]
	f.step()
	check(Fight.dist(f.boss, f.hero) == 1, "moving towards it closes 2 hexes")
	check(f.boss + Fight.DIRS[f.facing] == f.hero or Fight.dist(f.boss + Fight.DIRS[f.facing], f.hero) < Fight.dist(f.boss, f.hero) + 1, "it faces where it went")
	f.queue = [{"move": 1}]
	f.step()
	check(f.boss + Fight.DIRS[f.facing] == f.hero, "next to the hero it turns to face it")
	var was := f.boss
	f.queue = [{"move": -1}]
	f.step()
	check(Fight.dist(f.boss, f.hero) == 2 and f.boss != was, "backing off moves it away")
	f.boss = Vector2i(0, -2)
	f.queue = [{"leap": true}]
	f.step()
	check(Fight.dist(f.boss, f.hero) == 1, "a leap lands next to the hero")

	print("aiming")
	f = _aiming([1, 0], Vector2i(1, -1))  # one turn left of its front
	check(f.phase == "defend" and f.facing == 1, "one turn brings a hex beside its front into the attack")
	f = _aiming([1, 0], Vector2i(-1, 0))  # right behind it
	check(f.phase == "boss" and f.hp == Fight.HERO_HP, "one turn can't reach right behind it")
	f = _aiming([3, 0], Vector2i(-1, 0))
	check(f.phase == "defend", "three turns can")
	f = _aiming([0, 1], Vector2i(2, 0))  # two hexes in front
	check(f.phase == "defend" and Fight.dist(f.boss, f.hero) == 1 and f.facing == 0, "a step closes the gap without turning")
	f = _aiming([0, 0], Vector2i(1, -1))
	check(f.phase == "boss" and f.facing == 0, "no budget, no aiming")
	f = _aiming([2, 0], Vector2i(1, 0))
	check(f.phase == "defend" and f.facing == 0, "already lined up, it doesn't turn")

	print("blocking and dodging")
	f = _attacked("longsword", "light", 60, false)
	check(f.phase == "defend" and f.incoming.dmg == 60, "standing in the attack has to be defended")
	var hp := f.hp
	f.defend_block()
	check(f.hp == hp - 60 + f.block() and f.block() == Fight.WEAPONS.longsword.block + Fight.ARMOURS.light.block, "blocking takes off a set amount: shield plus armour")
	check(f.phase == "boss", "then the boss carries on")
	check(f.stamina == Fight.STAMINA - Fight.BLOCK_COST, "blocking costs stamina")
	f = _attacked("longsword", "light", 60, false)
	f.stamina = Fight.BLOCK_COST - 1
	check(not f.can_block(), "not enough stamina, no block")
	f.defend_block()
	check(f.phase == "defend", "so blocking does nothing")
	f.take_hit()
	check(f.hp == Fight.HERO_HP - 60 and f.phase == "boss" and f.stamina == Fight.BLOCK_COST - 1, "taking the hit is the full hit for no stamina")
	f = _attacked("longsword", "light", 60, false)
	f.incoming.heavy = true
	check(f.block_cost() == Fight.HEAVY_BLOCK_COST, "a heavy attack costs more to block")
	f = _attacked("longsword", "light", 60, false)
	var to: Vector2i = f.dodge_hexes()[1]
	f.defend_dodge(to, true)
	check(f.hp == Fight.HERO_HP and f.hero == to and f.stamina == Fight.STAMINA - 1, "a good dodge takes nothing, moves and costs 1 stamina")
	f = _attacked("longsword", "light", 60, false)
	f.defend_dodge(f.hero, false)
	check(f.hp == Fight.HERO_HP - 60, "a missed dodge takes the full hit")
	f = _attacked("longsword", "light", 60, false)
	f.stamina = 0
	check(not f.can_dodge(), "no stamina, no dodge")
	f = _attacked("longsword", "light", 60, true)
	var d0 := Fight.dist(f.hero, f.boss)
	f.defend_block()
	check(Fight.dist(f.hero, f.boss) == d0 + 1, "a push moves it a hex away")
	f = Fight.new("longsword", "light", 1)
	f.facing = 0
	f.hero = Vector2i(-1, 0)
	f.phase = "boss"
	f.card = {"name": "test", "dodge": 1, "weak": []}
	f.queue = [{"attack": 4, "range": 1, "arcs": ["front", "left", "right"]}]
	f.step()
	check(f.phase == "boss" and f.hp == Fight.HERO_HP, "behind an arc attack is safe")

	print("the dodge check")
	var sw := Fight.sweet(2)
	check(Fight.sweet(3).y - Fight.sweet(3).x < sw.y - sw.x, "harder attacks have a narrower sweet spot")
	check(Fight.bar(0.5, 2, Fight.ARMOURS.heavy.bar) > Fight.bar(0.5, 2, Fight.ARMOURS.light.bar), "heavy armour fills the bar sooner")
	f = _attacked("longsword", "heavy", 3, false)
	check(f.dodge_pace() == "slow" and f.dodge_time() == Fight.ARMOURS.heavy.bar * Fight.PACE.slow, "a full bar of stamina, a slow dodge bar")
	f.stamina = 4
	check(f.dodge_pace() == "mid", "3 or 4 left after the dodge, the middle one")
	f.stamina = 2
	check(f.dodge_pace() == "fast", "1 or 2 left, the fast one")
	var early := Fight.bar(0.2, 1) - Fight.bar(0.1, 1)
	var late := Fight.bar(1.2, 1) - Fight.bar(1.1, 1)
	check(late > early, "the bar speeds up as it fills")

	print("stamina")
	f = Fight.new("longsword", "light", 1)
	check(f.stamina == Fight.STAMINA, "the fight starts with full stamina")
	f.stamina = 1
	f.attacked = true
	f.end_turn()
	f.queue = []
	f.step()
	check(f.phase == "hero" and f.stamina == 1 + Fight.STAMINA_BACK, "a new turn gives back only a little")
	f.stamina = 0
	f.end_turn()
	f.queue = []
	f.step()
	check(f.stamina == Fight.STAMINA_BACK + Fight.REST_BONUS and f.stamina == Fight.STAMINA, "a turn with no attack fills the bar")
	f.hero = f.boss + Fight.DIRS[0]
	f.stamina = Fight.STAMINA
	f.attack(0)
	check(f.can_attack(0), "more than one attack a turn")
	f.attack(0)
	check(f.stamina == Fight.STAMINA - 2 * Fight.WEAPONS.longsword.acts[0].st, "each attack pays its stamina")
	f.attacked = true
	f.stamina = Fight.STAMINA - 1
	f.end_turn()
	f.queue = []
	f.step()
	check(f.stamina == Fight.STAMINA, "never more than the bar holds")
	for i in Fight.WEAPONS.longsword.acts.size():
		check(Fight.WEAPONS.longsword.acts[i].st >= 1 and Fight.WEAPONS.claymore.acts[i].st >= 1, "every attack costs stamina (%d)" % i)
	f = _attacked("longsword", "light", 3, false)
	f.queue = [{"attack": 3, "range": 1, "arcs": ["front"]}, {"attack": 3, "range": 1, "arcs": ["front"]}]
	check(f.dodge_cost() == 1, "the first dodge costs 1")
	f.defend_dodge(f.hero, true)
	f.step()
	check(f.phase == "defend" and f.dodge_cost() == 2, "the second costs 2")
	f.defend_dodge(f.hero, true)
	check(f.stamina == Fight.STAMINA - 3, "two dodges took 3")
	f.step()
	check(f.dodge_cost() == 3, "the third costs 3")
	f.stamina = 2
	check(not f.can_dodge(), "too dear, so block")
	f.defend_block()
	f.queue = []
	f.step()
	f.end_turn()
	check(f.dodge_cost() == 1, "next boss turn it's back to 1")

	print("the bow")
	f = Fight.new("bow", "light", 1)
	f.facing = 0
	f.hero = f.boss + Fight.DIRS[0]
	check(f.can_attack(0), "it shoots from right next to it")
	f.boss = Vector2i(-3, 0)
	f.hero = Vector2i(3, 0)
	check(Fight.dist(f.hero, f.boss) == 2 * Fight.ROOM and f.can_attack(0), "and from across the whole room")
	f.boss = Vector2i.ZERO
	f.hero = f.boss + Fight.DIRS[0] * 2
	var hp1 := f.boss_hp
	f.attack(0)
	check(f.boss_hp == hp1 - (Fight.WEAPONS.bow.acts[0].dmg - Fight.BOSS_BLOCK) and f.stamina == Fight.STAMINA - 3, "a shot costs 3 stamina")
	check(f.arrows == Fight.ARROWS - 1, "and one arrow")
	f.attack(0)
	check(not f.can_attack(0), "two shots and the bar is empty")
	f.stamina = Fight.STAMINA
	f.arrows = 0
	check(not f.can_attack(0), "no arrows, no shot")
	check(Fight.new("longsword", "light", 1, "bow").arrows == Fight.ARROWS and Fight.new("longsword", "light", 1, "claymore").arrows == 0, "arrows only come with a bow")
	check(Fight.WEAPONS.bow.block == 0, "no shield with a bow")

	print("swapping weapons")
	f = Fight.new("longsword", "light", 1)
	check(not f.can_swap(), "no second set, no swap")
	f = Fight.new("longsword", "light", 1, "claymore")
	f.hero = f.boss + Fight.DIRS[0]
	f.facing = 0
	f.attack(0)
	var st := f.stamina
	f.swap()
	check(f.weapon == "claymore" and f.spare == "longsword" and f.stamina == st - Fight.SWAP_COST, "swap to the other set for 1 stamina")
	check(f.block() == Fight.ARMOURS.light.block, "no shield in hand, no shield block")
	check(f.attack_bonus(0) == 0.0, "swapping breaks the combo")
	f.swap()
	check(f.weapon == "longsword", "and back again")
	f = Fight.new("longsword", "light", 1, "claymore")
	f.stamina = 1
	f.swap()
	f.end_turn()
	f.queue = []
	f.step()
	check(f.stamina == Fight.STAMINA_BACK + Fight.REST_BONUS, "a swap isn't an attack, so the full stamina comes back")
	f.stamina = 0
	check(not f.can_swap(), "no stamina, no swap")

	print("flask")
	f = Fight.new("longsword", "light", 1)
	check(not f.can_flask(), "no flask at full health")
	f.hp = 50
	f.flask()
	check(f.hp == 50 + Fight.FLASK_HEAL and f.flasks == Fight.FLASKS - 1, "a flask heals")

	print("one attack a turn")
	f = Fight.new("longsword", "light", 1, "claymore", "one")
	f.hero = f.boss + Fight.DIRS[0] * 3
	f.facing = 0
	check(f.can_run_attack(), "the running attack works without stamina")
	f.moved = 2
	check(not f.can_run_attack(), "but not with only 1 hex of the 3 left")
	f.moved = 0
	check(not f.can_move(Vector2i(-1, 3)) and f.can_move(f.boss + Fight.DIRS[1] * 3), "up to 3 hexes")
	f.move(f.boss + Fight.DIRS[0])
	check(f.stamina == Fight.STAMINA and f.moved == 2, "moving costs no stamina")
	f.attack(0)
	check(not f.can_attack(0) and not f.can_attack(1), "then no more attacks this turn")
	check(f.can_move(f.boss + Fight.DIRS[1]) and not f.can_move(f.boss + Fight.DIRS[0] * 3), "but the hex left to move")
	f.move(f.boss + Fight.DIRS[1])
	check(not f.can_move(f.boss + Fight.DIRS[2]), "3 hexes and that's it")
	check(f.dodge_pace() == "slow", "a longsword light attack, a slow dodge bar")
	f.swap()
	check(f.weapon == "claymore" and f.stamina == Fight.STAMINA, "swapping is free")
	f.end_turn()
	f.queue = []
	f.step()
	check(f.phase == "hero" and f.can_attack(0) and f.moved == 0, "a new turn, a new attack and 3 more hexes")
	f.attack(1)
	check(f.dodge_pace() == "fast", "after a heavy attack, a fast one")
	f.end_turn()
	f.queue = []
	f.step()
	f.attack(0)
	f.end_turn()
	f.queue = []
	f.step()
	f.attack(0)
	check(f.attack_bonus(0) == 0.0, "no combos")
	f.hp = 50
	check(not f.can_flask(), "the flask takes the attack")
	f = Fight.new("longsword", "light", 1, "", "one")
	f.hp = 50
	f.flask()
	f.hero = f.boss + Fight.DIRS[0]
	check(not f.can_attack(0), "so drinking means no attack")
	f = _attacked("longsword", "light", 60, false)
	f.mode = "one"
	f.stamina = 0
	check(f.can_block() and f.can_dodge(), "block and dodge need no stamina")
	f.defend_block()
	check(f.stamina == 0 and f.phase == "boss", "and take none")

	print("turn order")
	f = Fight.new("longsword", "light", 1, "claymore", "order")
	check(f.turn_order(5) == ["hero", "boss", "hero", "boss", "hero"], "the first turn is the hero's")
	var order := f.turn_order(20)
	check(order.count("hero") > order.count("boss"), "a longsword is quicker than the boss")
	f.swap()
	order = f.turn_order(20)
	check(order.count("hero") < order.count("boss"), "a claymore is slower")
	f.swap()
	f.hero = _far_hex(f)
	var seen: Array[String] = []
	for k in 12:
		seen.append(f.phase)
		if f.phase == "hero":
			f.end_turn()
		else:
			_finish_boss_turn(f)
			f.hero = _far_hex(f)
	check(seen.slice(0, 5) == ["hero", "boss", "hero", "boss", "hero"] and "hero" in seen, "turns come in that order")
	var two := false
	for k in seen.size() - 1:
		if seen[k] == "hero" and seen[k + 1] == "hero":
			two = true
	check(two, "sometimes the hero goes twice in a row")
	check(f.stamina == Fight.STAMINA, "no stamina used")

	print("the longsword combo attack")
	for m in ["one", "stamina"]:
		f = Fight.new("longsword", "light", 1, "claymore", m)
		f.facing = 0
		f.hero = f.boss + Fight.DIRS[3]  # behind, not a weak arc for an empty card
		base = Fight.WEAPONS.longsword.acts[0].dmg
		var want := (base - Fight.BOSS_BLOCK) + (roundi(base * 1.1) - Fight.BOSS_BLOCK) + (roundi(base * 1.2) - Fight.BOSS_BLOCK)
		check(f.can_skill("combo") and f.combo_damage() == want, "%s: three light hits with the combo bonuses" % m)
		var hp2 := f.boss_hp
		f.combo_attack()
		check(f.boss_hp == hp2 - want, "%s: they all land" % m)
		if m == "one":
			check(not f.can_attack(0) and f.stamina == Fight.STAMINA, "one: it's the turn's attack, no stamina")
		else:
			check(f.stamina == Fight.STAMINA - Fight.SKILLS.combo.st, "stamina: it costs 5")
		f.end_turn()
		f.phase = "boss"
		f.card = {"name": "test", "dodge": 1, "weak": []}
		f.queue = [{"attack": 10, "range": 1}]
		f.step()
		check(f.phase == "defend" and not f.can_block() and not f.can_dodge(), "%s: then no block or dodge" % m)
		f.take_hit()
		f.queue = []
		f.step()
		check(f.phase == "hero" and not f.exposed, "%s: back next turn" % m)
	f = Fight.new("longsword", "light", 1, "", "one")
	f.facing = 0
	f.hero = f.boss + Fight.DIRS[3]
	f.combo_attack()
	f.end_turn()
	f.queue = []
	f.step()
	check(not f.can_skill("combo") and f.waiting("combo"), "the next turn it sits out")
	f.end_turn()
	f.queue = []
	f.step()
	check(f.can_skill("combo"), "the turn after it's back")

	print("claymore sweep")
	f = Fight.new("claymore", "light", 1, "", "one")
	f.facing = 0
	f.hero = f.boss + Fight.DIRS[3]  # the boss is in direction 0 from the hero
	check(f.sweep_aims() == [5, 0, 1] or (f.sweep_aims().size() == 3 and 0 in f.sweep_aims()), "a sweep catches the boss centred on it or either side")
	check(f.sweep_hexes(1).has(f.boss) and not f.sweep_hexes(3).has(f.boss), "the 3 hexes round the hero")
	var hp3 := f.boss_hp
	f.sweep(1)
	check(f.boss_hp == hp3 - (Fight.SKILLS.sweep.dmg - Fight.BOSS_BLOCK) and f.attacked, "it hits, and it's the turn's attack")
	check(f.waiting("sweep"), "then it sits out a turn")

	print("aiming the bow")
	check(Fight.line(Vector2i(0, 0), Vector2i(3, 0)) == [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], "a straight line of hexes")
	check(Fight.line(Vector2i(0, 0), Vector2i(2, -1)).size() == 2 and Fight.line(Vector2i(0, 0), Vector2i(2, -1)).back() == Vector2i(2, -1), "a slanted line ends on its target")
	f = Fight.new("bow", "light", 1, "", "one")
	f.hero = f.boss + Fight.DIRS[0] * 3
	check(f.can_aim(f.boss) and not f.can_aim(f.boss + Fight.DIRS[1]), "aimed at an enemy, not an empty hex")
	check(f.shot_path(f.boss).back() == f.boss and f.shot_path(f.boss).size() == 3, "the arrow flies until it enters the enemy's hex")
	check(f.shot_path(f.boss + Fight.DIRS[3] * 2).back() == f.boss, "aimed past it, it stops at the first enemy")
	hp3 = f.boss_hp
	f.shoot(0, f.boss)
	check(f.boss_hp < hp3 and f.arrows == Fight.ARROWS - 1, "the shot lands")
	check(not Fight.new("longsword", "light", 1).can_aim(Vector2i.ZERO), "melee weapons aren't aimed")

	print("bow aimed shot")
	f = Fight.new("bow", "light", 1, "", "one")
	f.facing = 0
	f.hero = f.boss + Fight.DIRS[3] * 3
	hp3 = f.boss_hp
	f.aimed_shot()
	check(f.boss_hp == hp3 - Fight.SKILLS.aimed.dmg, "goes through the boss's block")
	check(f.arrows == Fight.ARROWS - 1, "uses an arrow")
	f = Fight.new("bow", "light", 1, "", "one")
	f.arrows = 0
	check(not f.can_skill("aimed"), "no arrows, no aimed shot")

	print("the keep")
	f = Fight.new("longsword", "light", 1, "claymore", "one", "keep")
	check(f.phase == "explore" and f.can_rest(), "it starts out of a fight, next to the bonfire")
	check(f.on_ground(Fight.KEEP_DOOR) and not f.on_ground(Fight.KEEP_DOOR + Vector2i(3, 0)), "walls round the rooms and the hallway")
	var into := 0
	for d in Fight.DIRS:
		if f.on_ground(Fight.KEEP_BONFIRE_DOOR + d) and Fight.dist(Fight.KEEP_BONFIRE_DOOR + d, Fight.KEEP_BONFIRE) <= 2:
			into += 1
	check(into == 1 and not f.on_ground(Fight.KEEP_BONFIRE_DOOR + Fight.DIRS[0]) and not f.on_ground(Fight.KEEP_BONFIRE_DOOR + Fight.DIRS[3]), "a one-hex door into the bonfire room")
	var way := f.path(f.hero, Fight.KEEP_DOOR + Vector2i(-1, 2))
	check(not way.is_empty(), "a way from the bonfire up to the boss's door")
	for c in way:
		f.walk(c)
		if f.phase != "explore":
			break
	check(f.phase == "hero" and f.foes[0].awake, "the swordsman wakes once he can see the hero, and the fight starts")
	check(Fight.dist(f.hero, f.foes[0].at) == Fight.WAKE and not f.foes[1].awake and not f.boss_awake, "5 hexes off; the crossbowman and the boss are too far")
	var g := Fight.new("longsword", "light", 1)
	g.hero = Vector2i(0, 2)
	check(g.sees(Vector2i.ZERO), "nothing in the way, it sees")
	g.ground.erase(Vector2i(0, 1))
	check(not g.sees(Vector2i.ZERO), "a wall in the way, it doesn't")
	f = Fight.new("longsword", "light", 1, "", "one", "keep")
	f.hero = Fight.KEEP_DOOR
	f._wake()
	check(f.boss_awake and f.phase == "hero", "the boss wakes at its door")

	print("the swordsman")
	f = Fight.new("longsword", "light", 1, "", "one", "keep")
	f.hero = Vector2i(0, 14)
	f._wake()
	check(f.foes[0].awake and not f.foes[1].awake and Fight.dist(f.hero, f.foes[0].at) == 4, "awake, 4 hexes off")
	f.end_turn()
	for k in 5:
		f.step()
	check(f.phase == "hero" and Fight.dist(f.hero, f.foes[0].at) == 2, "he comes 2 hexes closer")
	f.end_turn()
	for k in 5:
		f.step()
	check(f.phase == "defend" and Fight.dist(f.hero, f.foes[0].at) == 1 and f.incoming.name == "Sword", "then he's next to the hero and attacks")
	f.take_hit()
	check(f.hp == Fight.HERO_HP - Fight.FOE_ATTACKS.sword.dmg, "for his sword's damage")

	print("the crossbowman")
	f = Fight.new("longsword", "light", 1, "", "one", "keep")
	f.foes[0].hp = 0
	f.hero = Vector2i(1, 11)
	f._wake()
	check(f.foes[1].awake, "awake")
	f.end_turn()
	for k in 5:
		f.step()
	check(f.phase == "defend" and f.incoming.name == "Crossbow", "he shoots from where he stands")
	f.take_hit()
	for k in 5:
		f.step()
	f.hero = f.foes[1].at + Fight.DIRS[5]
	f.end_turn()
	for k in 5:
		f.step()
	check(f.foes[1].held == "shortsword" and f.phase == "defend" and f.incoming.name == "Shortsword", "next to him, he pulls out a shortsword")
	f.take_hit()
	for k in 5:
		f.step()
	f.hero = Vector2i(1, 11)
	f.end_turn()
	for k in 5:
		f.step()
	check(f.foes[1].held == "crossbow" and f.incoming.name == "Crossbow", "and back to the crossbow when the hero steps off")
	f = Fight.new("longsword", "light", 1, "", "one", "keep")
	f.hero = Vector2i(1, 11)
	f.foes[0].at = Fight.line(f.foes[1].at, f.hero)[1]
	f.foes[0].awake = true
	f.foes[1].awake = true
	f.phase = "hero"
	f._enemy_turn(["f1"])
	for k in 5:
		f.step()
	check(f.foes[0].hp == Fight.FOES.swordsman.hp - Fight.FOE_ATTACKS.crossbow.dmg and f.hp == Fight.HERO_HP, "the bolt hits the swordsman in the way")

	print("several enemies")
	f = Fight.new("claymore", "light", 1, "", "one")
	f.facing = 2
	f.hero = Vector2i(0, 1)
	var foe_at := f.hero + Fight.DIRS[0]
	f.foes.append({"kind": "swordsman", "at": foe_at, "start": foe_at, "hp": 80, "held": "sword", "facing": 3, "awake": true})
	check(f.targets().size() == 2, "both enemies next to the hero can be hit")
	f.attack(0, foe_at)
	check(f.foes[0].hp == 80 - Fight.WEAPONS.claymore.acts[0].dmg and f.boss_hp == Fight.BOSS_HP, "the attack hits the one picked, with no block")
	f.end_turn()
	f.queue = []
	f.to_go = []
	f.step()
	f.foes[0].hp = 80
	f.foes[0].at = foe_at
	f.hero = Vector2i(0, 1)
	var both := false
	for i in f.sweep_aims():
		if f.boss in f.sweep_hexes(i) and foe_at in f.sweep_hexes(i):
			both = true
			f.sweep(i)
			break
	check(both and f.foes[0].hp == 80 - Fight.SKILLS.sweep.dmg and f.boss_hp == Fight.BOSS_HP - (Fight.SKILLS.sweep.dmg - Fight.BOSS_BLOCK), "a sweep hits both")
	f = Fight.new("bow", "light", 1, "", "one")
	f.hero = Vector2i(0, 3)
	f.foes.append({"kind": "swordsman", "at": Vector2i(0, 2), "start": Vector2i(0, 2), "hp": 80, "held": "sword", "facing": 3, "awake": true})
	f.shoot(0, f.boss)
	check(f.foes[0].hp < 80 and f.boss_hp == Fight.BOSS_HP, "an arrow at the boss hits the enemy in front of it")
	f = Fight.new("longsword", "light", 1, "", "one", "order")
	f.foes.append({"kind": "swordsman", "at": Vector2i(2, 0), "start": Vector2i(2, 0), "hp": 80, "held": "sword", "facing": 3, "awake": true})
	check("f0" in f.turn_order(6) and "boss" in f.turn_order(6), "turn order: each enemy has its own turns")

	print("after the fight")
	f = Fight.new("claymore", "light", 1, "", "one", "keep")
	f.foes[1].hp = 0
	f.hero = f.foes[0].at + Fight.DIRS[5]
	f._wake()
	f.foes[0].hp = 10
	f.attack(0, f.foes[0].at)
	check(f.phase == "explore", "no enemy left awake, the fight is over")
	f.hp = 20
	f.flasks = 0
	f.hero = Fight.KEEP_START
	f.rest()
	check(f.hp == Fight.HERO_HP and f.flasks == Fight.FLASKS, "resting at the bonfire brings back health and flasks")
	check(f.foes[0].hp == Fight.FOES.swordsman.hp and f.foes[1].hp > 0 and f.foes[0].at == f.foes[0].start and not f.foes[0].awake, "and the enemies")

	print("whole fights")
	var ended := 0
	for s in 20:
		f = Fight.new(["longsword", "claymore"][s % 2], ["light", "heavy"][s / 2 % 2], s + 10)
		for k in 2000:
			if f.phase in ["win", "lose"]:
				break
			if f.phase == "boss":
				f.step()
			else:
				bot(f)
		if f.phase in ["win", "lose"]:
			ended += 1
	check(ended == 20, "20 bot fights all end")
	ended = 0
	for s in 20:
		f = Fight.new(["longsword", "claymore", "bow"][s % 3], "light", s + 10, "", ["one", "order"][s % 2])
		for k in 3000:
			if f.phase in ["win", "lose"]:
				break
			if f.phase == "boss":
				f.step()
			else:
				bot(f)
		if f.phase in ["win", "lose"]:
			ended += 1
	check(ended == 20, "20 more in the other two modes all end")

	print("square grid")
	f = Fight.new("longsword", "light", 1, "", "square")
	check(Fight.SQUARE and Fight.room().size() == 49 and Fight.DIRS.size() == 8, "a 7 by 7 room, 8 ways to step")
	check(Fight.dist(Vector2i.ZERO, Vector2i(2, 1)) == 2 and Fight.dist(Vector2i.ZERO, Vector2i(3, -3)) == 3, "a diagonal step counts 1")
	check(not f.uses_stamina() and f.can_move(Vector2i(3, 0)) and not f.can_move(Vector2i(-3, -1)), "move 3, diagonals too")
	f.facing = 0
	check(f.arcs_of(Vector2i(1, 0)) == ["front"] and f.arcs_of(Vector2i(0, -1)) == ["left"] and f.arcs_of(Vector2i(-1, 0)) == ["back"], "front, left and back")
	check(f.arcs_of(Vector2i(1, -1)).size() == 2 and "front" in f.arcs_of(Vector2i(1, -1)), "a front corner is front and side")
	f.hero = Vector2i(1, 1)
	check(f.can_attack(0) and f.targets() == [f.boss], "hits from a diagonal")
	check(Fight.line(Vector2i.ZERO, Vector2i(3, 0)) == [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] and Fight.line(Vector2i.ZERO, Vector2i(2, 2)) == [Vector2i(1, 1), Vector2i(2, 2)], "straight and diagonal lines")
	f.phase = "boss"
	f.card = {"name": "test", "dodge": 1, "weak": []}
	f.queue = [{"turn": 3}]
	f.step()
	check(f.facing == 2, "a card's turn round is a half turn")
	f = Fight.new("claymore", "light", 1, "", "square")
	f.hero = Vector2i(0, 1)
	check(f.sweep_aims().size() == 3, "a sweep catches the boss from 3 aims")
	print("the keep on squares")
	f = Fight.new("longsword", "light", 1, "", "square", "keep")
	check(f.phase == "explore" and f.bonfire == Vector2i(5, 22) and f.hero == Vector2i(5, 23), "starts at the bonfire")
	check(f.gate == Vector2i(8, 22) and not f.on_ground(f.gate) and f.boss == Vector2i(28, 16) and f.big == Vector2i(11, 34), "gate shut, knight and big boss placed")
	var kinds := {}
	for fo in f.foes:
		kinds[fo.kind] = kinds.get(fo.kind, 0) + 1
	check(kinds == {"swordsman": 2, "crossbowman": 4, "hound": 5, "shieldman": 2}, "every room's enemies")
	var straight := true
	for c in f.path(Vector2i(5, 19), Vector2i(5, 15)):
		straight = straight and c.x == 5
	check(straight, "the hallway is a straight walk")
	var hall := f.foes[0]
	for fo in f.foes:
		if fo.at == Vector2i(5, 14):
			hall = fo
	for c in f.path(f.hero, Vector2i(5, 9)):
		f.walk(c)
		if f.phase != "explore":
			break
	check(f.phase == "hero" and hall.awake and Fight.dist(f.hero, hall.at) == Fight.WAKE, "the hallway swordsman wakes at 5 squares")
	f = Fight.new("longsword", "light", 1, "", "square", "keep")
	f.hero = Vector2i(7, 22)
	check(not f.can_open_gate(), "the gate won't open from the bonfire side")
	f.hero = Vector2i(9, 22)
	f.open_gate()
	check(f.gate_open and f.on_ground(f.gate) and f.steps(Vector2i(7, 22)) == 2, "from the gatehouse it opens, and the way through is short")
	# the knight falls for good
	f.hero = Vector2i(28, 17)
	f._wake()
	f.boss_hp = 1
	f.facing = 1
	check(f.phase == "hero" and f.can_attack(0, f.boss), "the knight wakes and can be hit")
	f.attack(0, f.boss)
	check(f.knight_dead and f.phase == "explore" and f.boss == f.big and f.boss_size == 2 and f.boss_hp == Fight.BIG_HP, "he falls, the fight ends, the big boss waits")
	check(not f.boss_awake and f.phase != "win", "felling the knight isn't the end")
	var kept := f.progress()
	f = Fight.new("longsword", "light", 2, "", "square", "keep")
	f.apply_progress(kept)
	check(f.knight_dead and f.gate_open and f.boss == f.big and f.on_ground(f.gate), "after dying the knight stays dead and the gate open")
	f.hero = Vector2i(6, 22)
	f.rest()
	check(f.knight_dead and f.gate_open, "resting doesn't bring him back")
	# the big boss: 4 squares
	check(f.is_boss(Vector2i(12, 35)) and f.enemy_at(Vector2i(11, 35)) and not f.is_boss(Vector2i(13, 35)), "the big boss stands on 4 squares")
	check(not f._walkable(Vector2i(12, 34)), "nobody walks through it")
	f.hero = Vector2i(13, 36)
	f._wake()
	check(f.phase == "hero" and f.boss_awake and f.can_attack(0, Vector2i(12, 35)) and f.targets().size() == 1, "hit from next to any of its squares")
	f.hero = Vector2i(13, 34)
	check(f.targets().size() == 2 and f.run_targets(Vector2i(13, 34)).size() == 1, "two of its squares in reach, still one enemy to run at")
	f.phase = "boss"
	f.card = {"name": "test", "dodge": 1, "weak": []}
	f.facing = 0
	f.queue = [{"attack": 5, "range": 1, "arcs": ["front"]}]
	f.step()
	check(f.phase == "defend" and f.incoming.from == Vector2i(12, 34), "its front reaches the squares beside it")
	f.take_hit()
	f.hero = Vector2i(11, 38)
	f.boss_hp = Fight.BIG_HP
	f.queue = [{"move": 2}]
	var gap := f.boss_dist(f.hero)
	f.step()
	check(f.boss_dist(f.hero) == gap - 2, "it walks up to the hero")
	ended = 0
	for s in 5:
		f = Fight.new(["longsword", "claymore", "bow"][s % 3], "light", s + 30, "", "square", "keep")
		f.apply_progress({"knight_dead": true})
		f.hero = Vector2i(11, 31)
		f._wake()
		for k in 3000:
			if f.phase in ["win", "lose"]:
				break
			if f.phase == "boss":
				f.step()
			else:
				bot(f)
		if f.phase in ["win", "lose"]:
			ended += 1
	check(ended == 5, "5 bot fights with the big boss all end")
	# the shield man and the hounds
	f = Fight.new("longsword", "light", 1, "", "square", "keep")
	var sh := -1
	for k in f.foes.size():
		if f.foes[k].kind == "shieldman" and sh < 0:
			sh = k
	var at: Vector2i = f.foes[sh].at
	f.foes[sh].facing = 0
	check(f.shielded(at, at + Vector2i(1, 0)) and f.shielded(at, at + Vector2i(1, 1)), "the shield covers his front")
	check(not f.shielded(at, at + Vector2i(-1, 0)) and not f.shielded(at, at + Vector2i(0, 1)), "but not his back or sides")
	f.hero = at + Vector2i(1, 0)
	f._wake()
	check(f.attack_damage(0, at) == 0, "a hit on the shield does nothing")
	f.hero = at + Vector2i(-1, 0)
	check(f.attack_damage(0, at) > 0, "a hit from behind lands")
	f = Fight.new("longsword", "light", 1, "", "square", "keep")
	var hd := -1
	for k in f.foes.size():
		if f.foes[k].kind == "hound" and hd < 0:
			hd = k
	f.hero = f.foes[hd].at + Vector2i(-6, 1)
	f.foes[hd].awake = true
	f.phase = "boss"
	f.actor = "f%d" % hd
	f.to_go = []
	f.queue = [{"move": 4}]
	f.step()
	check(Fight.dist(f.foes[hd].at, f.hero) == 2, "a hound runs 4")
	ended = 0
	for s in 10:
		f = Fight.new(["longsword", "claymore", "bow"][s % 3], "light", s + 10, "", "square")
		for k in 3000:
			if f.phase in ["win", "lose"]:
				break
			if f.phase == "boss":
				f.step()
			else:
				bot(f)
		if f.phase in ["win", "lose"]:
			ended += 1
	check(ended == 10, "10 bot fights on squares all end")
	Fight.set_grid(false)

	print("art")
	var img := Art.boss_image(0)
	check(img.get_width() == 2 * Art.R, "boss image drawn")
	check(Art.boss_image(3).get_pixel(2 * Art.R - 1 - 25, Art.R) == img.get_pixel(25, Art.R), "facing left is a mirror of facing right")
	check(Art.hero_image(0, "longsword").get_width() == 2 * Art.HR and Art.hero_image(1, "claymore").get_width() == 2 * Art.HR, "hero drawn with each weapon")
	check(Art.hero_image(0, "longsword").get_data() != Art.hero_image(0, "claymore").get_data(), "the two weapons look different")
	check(Art.foe_image("swordsman", "sword", 0).get_data() != Art.foe_image("crossbowman", "crossbow", 0).get_data(), "the two enemies look different")
	check(Art.foe_image("crossbowman", "shortsword", 0).get_data() != Art.foe_image("crossbowman", "crossbow", 0).get_data(), "the shortsword shows")
	check(Art.foe_image("hound", "bite", 0).get_data() != Art.foe_image("shieldman", "mace", 0).get_data(), "hound and shield man drawn")
	check(Art.big_boss(0).get_width() == 2 * Art.BIG_R, "big boss drawn")
	check(not Art.bonfire().get_image().is_invisible(), "bonfire drawn")
	var icons := {}
	for k in Fight.WEAPONS.keys() + Fight.ARMOURS.keys():
		var ic := Art.icon_image(k)
		check(ic.get_width() == Art.ICON and not ic.is_invisible(), "%s has an icon" % k)
		icons[ic.get_data()] = true
	check(icons.size() == Fight.WEAPONS.size() + Fight.ARMOURS.size(), "every icon is different")

	print("updates")
	check(Update.newer("v0.3", "0.2") and not Update.newer("v0.2", "0.2") and not Update.newer("v0.1", "0.2"), "compares versions")
	check(Update.newer("v0.10", "0.9") and Update.newer("v1.0", "0.9.9"), "numbers, not letters")
	var rel := Update.read_release('{"tag_name": "v0.3", "html_url": "page", "assets": [{"name": "GrimTactics.apk", "browser_download_url": "apk"}]}')
	check(rel.tag == "v0.3" and rel.url == "apk" and rel.page == "page", "reads the APK link from a release")
	check(Update.read_release('{"tag_name": "v0.3", "assets": []}').is_empty(), "a release without an APK is ignored")
	check(Update.read_release("not json").is_empty(), "ignores a bad reply")
	check(Update.current() != "0.0", "this build has a version")

	print("PASS" if fails == 0 else "%d FAILED" % fails)
	return fails


static func _finish_boss_turn(f: Fight) -> void:
	for k in 50:
		if f.phase == "defend":
			f.take_hit()
		if f.phase != "boss":
			break
		f.step()
	f.hp = Fight.HERO_HP


## A free hex as far from the boss as it gets.
static func _far_hex(f: Fight) -> Vector2i:
	var best := f.hero
	for c in Fight.room():
		if f.open_hex(c) and Fight.dist(c, f.boss) > Fight.dist(best, f.boss):
			best = c
	return best


## The boss facing right aims with budget [turns, steps] and attacks its front,
## the hero standing at c.
static func _aiming(budget: Array, c: Vector2i) -> Fight:
	var f := Fight.new("longsword", "light", 1)
	f.facing = 0
	f.hero = c
	f.phase = "boss"
	f.card = {"name": "test", "dodge": 1, "weak": []}
	f.queue = [{"aim": budget}, {"attack": 5, "range": 1, "arcs": ["front"]}]
	f.step()
	f.step()
	return f


## A fight where the hero stands in front of the boss and is being hit for dmg.
static func _attacked(w: String, a: String, dmg: int, push: bool) -> Fight:
	var f := Fight.new(w, a, 1)
	f.facing = 0
	f.hero = Vector2i(1, 0)
	f.phase = "boss"
	f.card = {"name": "test", "dodge": 1, "weak": []}
	f.queue = [{"attack": dmg, "range": 1, "push": push}]
	f.step()
	return f
