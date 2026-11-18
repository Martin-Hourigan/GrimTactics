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
	check(Fight.new("claymore", "light", 1).skills().is_empty(), "only the longsword has it")

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

	print("art")
	var img := Art.boss_image(0)
	check(img.get_width() == 2 * Art.R, "boss image drawn")
	check(Art.boss_image(3).get_pixel(2 * Art.R - 1 - 25, Art.R) == img.get_pixel(25, Art.R), "facing left is a mirror of facing right")
	check(Art.hero_image(0, "longsword").get_width() == 2 * Art.HR and Art.hero_image(1, "claymore").get_width() == 2 * Art.HR, "hero drawn with each weapon")
	check(Art.hero_image(0, "longsword").get_data() != Art.hero_image(0, "claymore").get_data(), "the two weapons look different")
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
