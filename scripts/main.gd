extends Node2D
## The game on screen: pick a weapon and armour, then the fight.
## Everything is a left click (or Space for the dodge check), so it can move to a phone later.

const CENTRE := Vector2(156, 138)
const HR := 18.0  ## hex radius
const BOSS_STEP := 0.45  ## seconds between the steps of the boss's card
const HEX := Color("1c1c22")
const HEX_REACH := Color("2c2c36")
const HEX_WEAK := Color("1d2b24")
const HEX_HIT := Color("5a2c26")
const HIT_EDGE := Color("c0745e")
const ARC_LINE := Color("3c3c48")
const TEXT := Color("d8d4cc")
const DIM := Color("5a5852")
const HURT := Color("d06a5a")
const GOOD := Color("8cbf8a")
const PANEL := Color("16161a")
const OFF := Color("2a2a30")

var screen := "menu"  ## menu, fight
var weapon := "longsword"
var armour := "light"
var fight: Fight
var font: Font
var t := 0.0
var pause := 0.0
var flash := 0.0
var flash_hexes: Array[Vector2i] = []
var popups: Array[Dictionary] = []  ## {text, pos, colour, t}
var picking_dodge := false
var check := {}  ## the dodge check while it runs: {to, t, diff, sweet, done, ok}
var shot := ""
var shot_at := 60
var frames := 0
var auto := 0  ## --auto N: a bot plays N hero turns (for screenshots)
var update_state := "idle"  ## idle, checking, latest, new, failed
var update_url := ""
var update_tag := ""
var http: HTTPRequest
var shot_dodge := false  ## --dodge: the bot opens the dodge check instead (for screenshots)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--smoke" in args:
		set_process(false)
		visible = false
		var fails: int = load("res://scripts/tests.gd").run()
		get_tree().quit(0 if fails == 0 else 1)
		return
	var si := args.find("--shot")
	if si >= 0 and si + 1 < args.size():
		shot = args[si + 1]
		if si + 2 < args.size() and args[si + 2].is_valid_int():
			shot_at = int(args[si + 2])
	var ai := args.find("--auto")
	if ai >= 0 and ai + 1 < args.size():
		auto = int(args[ai + 1])
	shot_dodge = "--dodge" in args
	if "--fight" in args or auto > 0:
		start()
	font = ThemeDB.fallback_font
	_check_update()


func start() -> void:
	fight = Fight.new(weapon, armour, randi())
	popups.clear()
	check = {}
	picking_dodge = false
	screen = "fight"


static func hex_pos(c: Vector2i) -> Vector2:
	return (CENTRE + HR * Fight.flat(c) * Vector2(1, -1)).round()


func _process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta)
	if screen == "fight":
		_tick(delta)
	for p in popups:
		p.t += delta
	popups = popups.filter(func(p): return p.t < 0.9)
	queue_redraw()
	frames += 1
	if shot != "" and frames == shot_at:
		RenderingServer.frame_post_draw.connect(func():
			get_viewport().get_texture().get_image().save_png(shot)
			get_tree().quit(), CONNECT_ONE_SHOT)


func _tick(delta: float) -> void:
	if not check.is_empty():
		check.t += delta
		if check.done:
			if check.t > 0.35:
				fight.defend_dodge(check.to, check.ok)
				check = {}
		elif Fight.bar(check.t, check.diff) >= 1.0:
			_stop_check()
	elif fight.phase == "boss":
		pause += delta
		if pause >= BOSS_STEP:
			pause = 0.0
			fight.step()
	elif shot_dodge and fight.phase == "defend":
		_start_check(fight.hero)
	elif auto > 0 and fight.phase in ["hero", "defend"]:
		pause += delta
		if pause >= 0.3:
			pause = 0.0
			if fight.phase == "hero":
				auto -= 1
			load("res://scripts/tests.gd").bot(fight)
	_take_events()


func _take_events() -> void:
	for e in fight.events:
		match e.type:
			"hit_boss":
				_popup(str(e.dmg), hex_pos(fight.boss) + Vector2(0, -12), TEXT)
			"hit_hero":
				_popup(str(e.dmg), hex_pos(fight.hero) + Vector2(0, -8), HURT)
			"dodged":
				_popup("dodged", hex_pos(fight.hero) + Vector2(0, -8), GOOD)
			"heal":
				_popup("+" + str(Fight.FLASK_HEAL), hex_pos(fight.hero) + Vector2(0, -8), GOOD)
			"attack":
				flash = 0.4
				flash_hexes = e.hexes
	fight.events.clear()


func _popup(text: String, pos: Vector2, colour: Color) -> void:
	popups.append({"text": text, "pos": pos, "colour": colour, "t": 0.0})


func _start_check(to: Vector2i) -> void:
	picking_dodge = false
	var diff: int = fight.incoming.dodge
	check = {"to": to, "t": 0.0, "diff": diff, "sweet": Fight.sweet(diff, fight.armour), "done": false, "ok": false, "at": 0.0}


func _stop_check() -> void:
	var p := minf(1.0, Fight.bar(check.t, check.diff))
	check.at = p
	check.ok = p >= check.sweet.x and p <= check.sweet.y
	check.done = true
	check.t = 0.0


# ---- input ----

func _unhandled_input(ev: InputEvent) -> void:
	var tap: bool = ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT
	var space: bool = ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE
	if screen == "fight" and not check.is_empty():
		if (tap or space) and not check.done:
			_stop_check()
		return
	if not tap:
		return
	var p: Vector2 = ev.position
	if screen == "menu":
		_menu_tap(p)
		return
	if fight.phase in ["win", "lose"]:
		screen = "menu"
		return
	if auto > 0:
		return
	if fight.phase == "defend":
		_defend_tap(p)
	elif fight.phase == "hero":
		_hero_tap(p)


func _check_update() -> void:
	if http == null:
		http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(_on_release)
	update_state = "checking"
	if http.request(Update.API, ["User-Agent: GrimTactics", "Accept: application/vnd.github+json"]) != OK:
		update_state = "failed"


func _on_release(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var rel := {}
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		rel = Update.read_release(body.get_string_from_utf8())
	if rel.is_empty():
		update_state = "failed"
		return
	update_tag = rel.tag
	update_url = rel.url
	update_state = "new" if Update.newer(update_tag, Update.current()) else "latest"


func _update_button() -> Rect2:
	return Rect2(330, 240, 142, 22)


func _menu_tap(p: Vector2) -> void:
	if _update_button().has_point(p):
		if update_state == "new":
			OS.shell_open(update_url)
		elif update_state != "checking":
			_check_update()
		return
	var keys := Fight.WEAPONS.keys()
	for i in keys.size():
		if _menu_button(0, i).has_point(p):
			weapon = keys[i]
	keys = Fight.ARMOURS.keys()
	for i in keys.size():
		if _menu_button(1, i).has_point(p):
			armour = keys[i]
	if _fight_button().has_point(p):
		start()


func _hero_tap(p: Vector2) -> void:
	var acts: Array = Fight.WEAPONS[fight.weapon].acts
	for i in acts.size():
		if _button(i).has_point(p):
			fight.attack(i)
			return
	if _button(2).has_point(p):
		fight.flask()
		return
	if _button(3).has_point(p):
		fight.end_turn()
		return
	var c: Variant = _hex_at(p)
	if c != null and fight.can_move(c):
		fight.move(c)


func _defend_tap(p: Vector2) -> void:
	if picking_dodge:
		var c: Variant = _hex_at(p)
		if c != null and c in fight.dodge_hexes():
			_start_check(c)
			return
	if _button(1).has_point(p):
		picking_dodge = false
		fight.defend_block()
	elif _button(2).has_point(p) and fight.can_dodge():
		picking_dodge = true


func _hex_at(p: Vector2) -> Variant:
	for c in Fight.room():
		if p.distance_to(hex_pos(c)) < HR * 0.9:
			return c
	return null


func _button(i: int) -> Rect2:
	return Rect2(300, 128 + i * 26, 172, 22)


func _menu_button(row: int, i: int) -> Rect2:
	return Rect2(90 + i * 154, 96 + row * 54, 146, 24)


func _fight_button() -> Rect2:
	return Rect2(190, 210, 100, 26)


# ---- drawing ----

func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), Art.BG)
	if screen == "menu":
		_draw_menu()
		return
	_draw_room()
	_draw_panel()
	if not check.is_empty():
		_draw_check()
	for p in popups:
		var a: float = 1.0 - p.t / 0.9
		var c: Color = p.colour
		c.a = a
		_text(p.text, p.pos + Vector2(0, -8.0 * p.t), c, true)
	if fight.phase in ["win", "lose"]:
		draw_rect(Rect2(0, 120, 480, 30), Color(0, 0, 0, 0.8))
		_text("BOSS DOWN" if fight.phase == "win" else "YOU FELL", Vector2(240, 139), TEXT, true)


func _text(s: String, pos: Vector2, c: Color, centred := false) -> void:
	var x := pos.x
	if centred:
		x -= font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / 2.0
	draw_string(font, Vector2(roundf(x), roundf(pos.y)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)


func _box(r: Rect2, label: String, on: bool, picked := false) -> void:
	var c := TEXT if on else DIM
	draw_rect(r, PANEL)
	draw_rect(r, c if picked or on else DIM, false, 2.0 if picked else 1.0)
	_text(label, r.position + Vector2(r.size.x / 2, 14), c, true)


func _draw_menu() -> void:
	_text("GrimTactics", Vector2(240, 50), TEXT, true)
	var keys := Fight.WEAPONS.keys()
	for i in keys.size():
		_box(_menu_button(0, i), Fight.WEAPONS[keys[i]].label, true, keys[i] == weapon)
	keys = Fight.ARMOURS.keys()
	for i in keys.size():
		_box(_menu_button(1, i), Fight.ARMOURS[keys[i]].label, true, keys[i] == armour)
	_box(_fight_button(), "FIGHT", true)
	_text("v" + Update.current(), Vector2(8, 258), DIM)
	var label: String = {"idle": "Check for updates", "checking": "Checking...", "latest": "Up to date",
		"new": "Update to " + update_tag, "failed": "Check for updates"}[update_state]
	_box(_update_button(), label, update_state == "new", update_state == "new")


func _hex_poly(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(60.0 * k + 30.0)
		pts.append((c + r * Vector2(cos(a), sin(a))).round())
	return pts


func _draw_room() -> void:
	var hitting: Array = fight.incoming.get("hexes", flash_hexes if flash > 0.0 else [])
	var dodging: Array = fight.dodge_hexes() if picking_dodge else []
	for c in Fight.room():
		var col := HEX
		if c in hitting:
			col = HEX_HIT
		elif c in dodging:
			col = HEX_REACH
		elif fight.phase == "hero" and fight.can_move(c):
			col = HEX_REACH
		if c != fight.boss and fight.phase == "hero" and fight.weak_at(c) and not c in hitting:
			col = col.lerp(HEX_WEAK, 0.7)
		draw_colored_polygon(_hex_poly(hex_pos(c), HR - 1.0), col)
		if c in hitting and fmod(t, 0.5) < 0.35:
			var edge := _hex_poly(hex_pos(c), HR - 1.0)
			edge.append(edge[0])
			draw_polyline(edge, HIT_EDGE, 1.0)
		# stamina a move there costs
		if fight.phase == "hero" and fight.can_move(c):
			var n := fight.move_cost(c)
			var base := hex_pos(c) + Vector2(0, 8)
			for k in n:
				draw_rect(Rect2((base + Vector2(k * 3 - n * 1.5, 0)).round(), Vector2.ONE), DIM)
	_draw_arc_lines()
	var bp := hex_pos(fight.boss)
	draw_texture(Art.boss(fight.facing), bp - Vector2(Art.R, Art.R))
	draw_texture(Art.hero(_hero_facing(), fight.weapon), hex_pos(fight.hero) - Vector2(Art.HR, Art.HR))


## The hero turns to whichever of the 6 directions points most at the boss.
func _hero_facing() -> int:
	var to := Fight.flat(fight.boss - fight.hero).normalized()
	var best := 0
	for i in 6:
		if Fight.flat(Fight.DIRS[i]).dot(to) > Fight.flat(Fight.DIRS[best]).dot(to):
			best = i
	return best


## The lines between the boss's four arcs.
func _draw_arc_lines() -> void:
	var o := hex_pos(fight.boss)
	for rel in [30.0, -30.0, 150.0, -150.0]:
		var a := deg_to_rad(60.0 * fight.facing + rel)
		var d := Vector2(cos(a), -sin(a))
		draw_line(o + d * HR * 0.8, o + d * HR * 2.2, ARC_LINE, 1.0)


func _bar(pos: Vector2, w: float, v: float, vmax: float, c: Color) -> void:
	draw_rect(Rect2(pos, Vector2(w, 4)), OFF)
	draw_rect(Rect2(pos, Vector2(roundf(w * v / vmax), 4)), c)


func _odds(o: Dictionary) -> String:
	return "%d-%d  avg %.1f" % [o.min, o.max, o.avg]


func _draw_panel() -> void:
	_text("Boss", Vector2(300, 16), TEXT)
	_bar(Vector2(330, 10), 142, fight.boss_hp, Fight.BOSS_HP, Art.STEEL)
	var cname: String = fight.card.get("name", "-")
	_text(cname, Vector2(300, 32), TEXT if fight.phase in ["boss", "defend"] else DIM)
	_text("deck %d" % fight.deck.size(), Vector2(440, 32), DIM)
	_text("You", Vector2(300, 60), TEXT)
	_bar(Vector2(330, 54), 142, fight.hp, Fight.HERO_HP, Art.HERO)
	_text(str(fight.hp), Vector2(300, 74), Art.HERO)
	for k in Fight.STAMINA:
		draw_rect(Rect2(330 + k * 10, 66, 7, 7), GOOD if k < fight.stamina else OFF)
	for k in Fight.FLASKS:
		draw_rect(Rect2(330 + k * 10, 80, 7, 7), HURT if k < fight.flasks else OFF)
	if fight.phase == "hero":
		var acts: Array = Fight.WEAPONS[fight.weapon].acts
		for i in acts.size():
			var a: Dictionary = acts[i]
			var r := _button(i)
			var ok := fight.can_attack(i)
			_box(r, "", ok)
			var c := TEXT if ok else DIM
			_text(a.label, r.position + Vector2(6, 14), c)
			for k in a.st:
				draw_rect(Rect2(r.position + Vector2(70 + k * 5, 9), Vector2(3, 3)), c)
			_text(_odds(Fight.hit_odds(fight.attack_dice(i), Fight.BOSS_BLOCK)), r.position + Vector2(96, 14), c)
		_box(_button(2), "Flask", fight.can_flask())
		_box(_button(3), "End turn", true)
	elif fight.phase == "defend" and check.is_empty():
		var inc := fight.incoming
		_text("%s  %d" % [inc.name, inc.dmg], Vector2(300, 118), HURT)
		var r := _button(1)
		_box(r, "", true)
		_text("Block", r.position + Vector2(6, 14), TEXT)
		_text(_odds(Fight.block_odds(inc.dmg, fight.block_dice())), r.position + Vector2(96, 14), TEXT)
		_box(_button(2), "Dodge", fight.can_dodge(), picking_dodge)
		if fight.can_dodge():
			draw_rect(Rect2(_button(2).position + Vector2(140, 9), Vector2(3, 3)), TEXT)


func _draw_check() -> void:
	var r := Rect2(298, 232, 176, 30)
	draw_rect(r, PANEL)
	draw_rect(r, TEXT, false, 1.0)
	var bar := Rect2(306, 242, 160, 10)
	draw_rect(bar, OFF)
	var s: Vector2 = check.sweet
	draw_rect(Rect2(bar.position.x + roundf(bar.size.x * s.x), bar.position.y, maxf(1.0, roundf(bar.size.x * (s.y - s.x))), bar.size.y), GOOD.darkened(0.4))
	var p: float = check.at if check.done else minf(1.0, Fight.bar(check.t, check.diff))
	var c := TEXT
	if check.done:
		c = GOOD if check.ok else HURT
	draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * p), bar.size.y)).grow_individual(0, -3, 0, -3), c)
	draw_rect(Rect2(bar.position.x + roundf(bar.size.x * p), bar.position.y - 2, 1, bar.size.y + 4), c)
