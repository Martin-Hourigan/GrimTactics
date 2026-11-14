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
		else:
			f.defend_block()
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
	for i in range(acts.size() - 1, -1, -1):
		# keep a point back for a dodge
		if f.can_attack(i) and f.stamina - acts[i].st >= Fight.DODGE_COST:
			f.attack(i)
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

	print("dice and odds")
	var o := Fight.hit_odds(["black", "black"], 1)
	check(o.min == 0 and o.max == 3, "two black dice against block 1 hit for 0-3")
	var sp := Fight.spread(["black"])
	var total := 0.0
	for k in sp:
		total += sp[k]
	check(absf(total - 1.0) < 0.0001, "chances add up to 1")
	check(Fight.block_odds(5, ["blue"]).max == 4 and Fight.block_odds(5, ["blue"]).min == 2, "blocking 5 with a blue die takes 2-4")

	print("moving")
	f = Fight.new("longsword", "light", 1)
	check(f.move_cost(f.hero + Fight.DIRS[2]) == 0, "first step is free")
	check(f.move_cost(Vector2i(0, 1)) == 1, "two steps cost 1 stamina")
	f.move(Vector2i(0, 2))
	check(f.stamina == Fight.STAMINA and f.hero == Vector2i(0, 2), "free step taken")
	check(f.move_cost(Vector2i(0, 1)) == 1, "after the free step every step costs 1")
	check(not f.can_move(f.boss), "can't stand on the boss")
	f.move(Vector2i(0, 1))
	check(f.stamina == Fight.STAMINA - 1, "paid for the second step")

	print("attacking")
	check(f.can_attack(0), "next to the boss it can attack")
	f.attack(0)
	check(not f.can_attack(0) and not f.can_attack(1), "one attack a turn")
	f = Fight.new("claymore", "heavy", 1)
	check(not f.can_attack(0), "not from across the room")
	f.hero = Vector2i(0, 1)
	f.card = {"weak": ["back"]}
	f.facing = 2  # faces up-left, so (0, 1) is behind it
	check(f.weak() and f.attack_dice(0).size() == 3, "a weak arc adds a black die")
	f.facing = 5
	check(not f.weak() and f.attack_dice(0).size() == 2, "not weak from the front")
	f.stamina = 2
	check(not f.can_attack(1), "the heavy swing needs 3 stamina")

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
	f = _attacked("longsword", "light", 6, false)
	check(f.phase == "defend" and f.incoming.dmg == 6, "standing in the attack has to be defended")
	var hp := f.hp
	f.defend_block()
	check(f.hp >= hp - 6 and f.hp <= hp - 6 + 4, "blocking takes off what it rolled")
	check(f.phase == "boss", "then the boss carries on")
	f = _attacked("longsword", "light", 6, false)
	var to: Vector2i = f.dodge_hexes()[1]
	f.defend_dodge(to, true)
	check(f.hp == Fight.HERO_HP and f.hero == to and f.stamina == Fight.STAMINA - 1, "a good dodge takes nothing, moves and costs 1 stamina")
	f = _attacked("longsword", "light", 6, false)
	f.defend_dodge(f.hero, false)
	check(f.hp == Fight.HERO_HP - 6, "a missed dodge takes the full hit")
	f = _attacked("longsword", "light", 6, false)
	f.stamina = 0
	check(not f.can_dodge(), "no stamina, no dodge")
	f = _attacked("longsword", "light", 6, true)
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
	var light := Fight.sweet(2, "light")
	var heavy := Fight.sweet(2, "heavy")
	check(light.y - light.x > heavy.y - heavy.x, "light armour has a wider sweet spot")
	check(Fight.sweet(3, "light").y - Fight.sweet(3, "light").x < light.y - light.x, "harder attacks have a narrower one")
	var early := Fight.bar(0.2, 1) - Fight.bar(0.1, 1)
	var late := Fight.bar(1.2, 1) - Fight.bar(1.1, 1)
	check(late > early, "the bar speeds up as it fills")

	print("flask")
	f = Fight.new("longsword", "light", 1)
	check(not f.can_flask(), "no flask at full health")
	f.hp = 5
	f.flask()
	check(f.hp == 5 + Fight.FLASK_HEAL and f.flasks == Fight.FLASKS - 1, "a flask heals")

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

	print("art")
	var img := Art.boss_image(0)
	check(img.get_width() == 2 * Art.R, "boss image drawn")
	check(Art.boss_image(3).get_pixel(2 * Art.R - 1 - 25, Art.R) == img.get_pixel(25, Art.R), "facing left is a mirror of facing right")
	check(Art.hero_image(0, "longsword").get_width() == 2 * Art.HR and Art.hero_image(1, "claymore").get_width() == 2 * Art.HR, "hero drawn with each weapon")
	check(Art.hero_image(0, "longsword").get_data() != Art.hero_image(0, "claymore").get_data(), "the two weapons look different")

	print("updates")
	check(Update.newer("v0.3", "0.2") and not Update.newer("v0.2", "0.2") and not Update.newer("v0.1", "0.2"), "compares versions")
	check(Update.newer("v0.10", "0.9") and Update.newer("v1.0", "0.9.9"), "numbers, not letters")
	var rel := Update.read_release('{"tag_name": "v0.3", "html_url": "page", "assets": [{"name": "GrimTactics.apk", "browser_download_url": "apk"}]}')
	check(rel.tag == "v0.3" and rel.url == "apk", "reads the APK link from a release")
	check(Update.read_release("not json").is_empty(), "ignores a bad reply")
	check(Update.current() != "0.0", "this build has a version")

	print("PASS" if fails == 0 else "%d FAILED" % fails)
	return fails


static func _finish_boss_turn(f: Fight) -> void:
	for k in 50:
		if f.phase == "defend":
			f.defend_block()
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
