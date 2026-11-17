extends Node2D
## The game on screen: title, boss, equipment, then the fight.
## Everything is a left click (or Space for the dodge check), so it can move to a phone later.

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

const BOSSES := {"knight": "Knight"}  ## PLACEHOLDER name
const SLOTS := ["Weapon 1", "Weapon 2", "Armour"]

const SETTINGS := "user://settings.cfg"

var screen := "title"  ## title, settings, boss, equip, fight
var portrait := false  ## phone held upright: the room above the panel
var boss := "knight"
var picking := -1  ## the equipment slot whose grid is open, or -1
var weapons := ["longsword", "claymore"]  ## the two weapon sets
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
var update_state := "idle"  ## idle, checking, latest, new, failed, downloading, ready, download_failed
var update_url := ""
var update_page := ""
var update_asked := false  ## the player tapped to check, so say if nothing turned up
var update_note := 0.0  ## seconds left showing "No new version"
var download: HTTPRequest
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
	var sc := args.find("--screen")
	if sc >= 0 and sc + 1 < args.size():
		screen = args[sc + 1]
	var pk := args.find("--pick")
	if pk >= 0 and pk + 1 < args.size():
		picking = int(args[pk + 1])
	if "--fight" in args or auto > 0:
		start()
	font = ThemeDB.fallback_font
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		portrait = cfg.get_value("screen", "portrait", false)
	if "--portrait" in args:
		portrait = true
	_apply_screen()
	# an update downloaded last time has been installed (or given up on)
	if FileAccess.file_exists(Update.APK):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Update.APK))
	_check_update()


## The view size and phone orientation for the current setting.
func _apply_screen() -> void:
	get_tree().root.content_scale_size = Vector2i(_view())
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT if portrait else DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	elif DisplayServer.get_name() != "headless":
		var size := Vector2i(_view()) * (2 if portrait else 3)
		DisplayServer.window_set_size(size)
		var usable := DisplayServer.screen_get_usable_rect()
		DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("screen", "portrait", portrait)
	cfg.save(SETTINGS)


func _view() -> Vector2:
	return Vector2(270, 480) if portrait else Vector2(480, 270)


## Middle of the room on screen.
func _centre() -> Vector2:
	return Vector2(135, 112) if portrait else Vector2(156, 138)


## Top left of the fight panel (its parts sit at the same places relative to it).
func _po() -> Vector2:
	return Vector2(49, 218) if portrait else Vector2(300, 0)


func start() -> void:
	fight = Fight.new(weapons[0], armour, randi(), weapons[1])
	popups.clear()
	check = {}
	picking_dodge = false
	screen = "fight"


func hex_pos(c: Vector2i) -> Vector2:
	return (_centre() + HR * Fight.flat(c) * Vector2(1, -1)).round()


func _process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta)
	update_note = maxf(0.0, update_note - delta)
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
		elif Fight.bar(check.t, check.diff, fight.armour) >= 1.0:
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
	check = {"to": to, "t": 0.0, "diff": diff, "sweet": Fight.sweet(diff), "done": false, "ok": false, "at": 0.0}


func _stop_check() -> void:
	var p := minf(1.0, Fight.bar(check.t, check.diff, fight.armour))
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
	match screen:
		"title":
			_title_tap(p)
			return
		"settings":
			_settings_tap(p)
			return
		"boss":
			_boss_tap(p)
			return
		"equip":
			_equip_tap(p)
			return
	if fight.phase in ["win", "lose"]:
		screen = "equip"
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
	update_page = rel.page
	update_state = "new" if Update.newer(update_tag, Update.current()) else "latest"
	if update_state == "latest" and update_asked:
		update_note = 2.0
	update_asked = false


## Download the new APK in the game, then hand it to Android's installer.
func _download_update() -> void:
	if download == null:
		download = HTTPRequest.new()
		download.use_threads = true
		download.download_file = Update.APK
		add_child(download)
		download.request_completed.connect(_on_downloaded)
	update_state = "downloading"
	if download.request(update_url, ["User-Agent: GrimTactics"]) != OK:
		update_state = "download_failed"


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not FileAccess.file_exists(Update.APK):
		update_state = "download_failed"
		return
	update_state = "ready"
	Update.install()


func _update_label() -> String:
	match update_state:
		"checking":
			return "Checking..."
		"latest":
			return "No new version" if update_note > 0.0 else "Check for updates"
		"new":
			return "Update to " + update_tag
		"downloading":
			var size := download.get_body_size()
			if size > 0:
				return "Downloading %d%%" % (100 * download.get_downloaded_bytes() / size)
			return "Downloading..."
		"ready":
			return "Install " + update_tag
		"download_failed":
			return "Download failed, retry"
	return "Check for updates"


func _update_button() -> Rect2:
	return Rect2(_view().x - 150, _view().y - 30, 142, 22)


func _title_tap(p: Vector2) -> void:
	if _update_button().has_point(p):
		match update_state:
			"new", "download_failed":
				if OS.get_name() == "Android":
					_download_update()
				else:
					OS.shell_open(update_page)
			"ready":
				Update.install()
			"checking", "downloading":
				pass
			_:
				update_asked = true
				_check_update()
		return
	if _play_button().has_point(p):
		screen = "boss"
	elif _settings_button().has_point(p):
		screen = "settings"


func _settings_tap(p: Vector2) -> void:
	if _back_button().has_point(p):
		screen = "title"
		return
	for i in 2:
		if _choice(0, i).has_point(p) and portrait != (i == 1):
			portrait = i == 1
			_save_settings()
			_apply_screen()


func _boss_tap(p: Vector2) -> void:
	if _back_button().has_point(p):
		screen = "title"
		return
	var keys := BOSSES.keys()
	for i in keys.size():
		if _boss_card(i).has_point(p):
			boss = keys[i]
			screen = "equip"


func _equip_tap(p: Vector2) -> void:
	if picking >= 0:
		var keys := _choices(picking)
		for i in keys.size():
			if _grid_cell(i).has_point(p):
				if picking < 2:
					weapons[picking] = keys[i]
				else:
					armour = keys[i]
		picking = -1  # a tap anywhere closes the grid
		return
	if _back_button().has_point(p):
		screen = "boss"
		return
	for s in SLOTS.size():
		if _slot(s).has_point(p):
			picking = s
			return
	if _fight_button().has_point(p):
		start()


## What can go in equipment slot s.
func _choices(s: int) -> Array:
	return Fight.WEAPONS.keys() if s < 2 else Fight.ARMOURS.keys()


## What is in equipment slot s now.
func _equipped(s: int) -> String:
	return weapons[s] if s < 2 else armour


func _item_label(key: String) -> String:
	return Fight.WEAPONS[key].label if Fight.WEAPONS.has(key) else Fight.ARMOURS[key].label


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
	if _button(4).has_point(p):
		fight.swap()
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
	return Rect2(_po() + Vector2(0, 128 + i * 26), Vector2(172, 22))


func _play_button() -> Rect2:
	return Rect2(_view().x / 2 - 50, 130, 100, 26)


func _settings_button() -> Rect2:
	return Rect2(_view().x / 2 - 50, 164, 100, 26)


## Option i of row row on the settings page.
func _choice(row: int, i: int) -> Rect2:
	var w := 120.0 if portrait else 146.0
	return Rect2(_view().x / 2 - w - 4 + i * (w + 8), 70 + row * 36, w, 24)


func _back_button() -> Rect2:
	return Rect2(8, 8, 50, 20)


func _boss_card(i: int) -> Rect2:
	return Rect2(_view().x / 2 - 50 + i * 110, 50, 100, 120)


func _slot(s: int) -> Rect2:
	if portrait:
		return Rect2(55, 50 + s * 112, 160, 104)
	return Rect2(66 + s * 120, 60, 108, 110)


func _grid_cols() -> int:
	return 2 if portrait else 3


## The grid's panel for n choices.
func _grid_panel(n: int) -> Rect2:
	var w := _grid_cols() * 92 + 12
	return Rect2(_view().x / 2 - w / 2, 50, w, 34 + ceili(float(n) / _grid_cols()) * 92)


func _grid_cell(i: int) -> Rect2:
	var panel := _grid_panel(i + 1)
	return Rect2(panel.position + Vector2(10 + (i % _grid_cols()) * 92, 26 + (i / _grid_cols()) * 92), Vector2(84, 84))


func _fight_button() -> Rect2:
	if portrait:
		return Rect2(85, 400, 100, 26)
	return Rect2(190, 210, 100, 26)


# ---- drawing ----

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _view()), Art.BG)
	match screen:
		"title":
			_draw_title()
			return
		"settings":
			_draw_settings()
			return
		"boss":
			_draw_boss_select()
			return
		"equip":
			_draw_equip()
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
		var v := _view()
		draw_rect(Rect2(0, v.y / 2 - 15, v.x, 30), Color(0, 0, 0, 0.8))
		_text("BOSS DOWN" if fight.phase == "win" else "YOU FELL", Vector2(v.x / 2, v.y / 2 + 4), TEXT, true)


func _text(s: String, pos: Vector2, c: Color, centred := false, size := 8) -> void:
	var x := pos.x
	if centred:
		x -= font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	draw_string(font, Vector2(roundf(x), roundf(pos.y)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func _box(r: Rect2, label: String, on: bool, picked := false) -> void:
	var c := TEXT if on else DIM
	draw_rect(r, PANEL)
	draw_rect(r, c if picked or on else DIM, false, 2.0 if picked else 1.0)
	_text(label, r.position + Vector2(r.size.x / 2, 14), c, true)


func _draw_title() -> void:
	_text("GrimTactics", Vector2(_view().x / 2, 90), TEXT, true, 16)
	_box(_play_button(), "PLAY", true)
	_box(_settings_button(), "Settings", true)
	_text("v" + Update.current(), Vector2(8, _view().y - 12), DIM)
	var lit := update_state in ["new", "downloading", "ready", "download_failed"]
	_box(_update_button(), _update_label(), update_state != "checking", lit)


func _draw_settings() -> void:
	_box(_back_button(), "Back", true)
	_text("Screen", Vector2(_view().x / 2, 60), DIM, true)
	_box(_choice(0, 0), "Landscape", true, not portrait)
	_box(_choice(0, 1), "Portrait", true, portrait)


func _draw_boss_select() -> void:
	_box(_back_button(), "Back", true)
	var keys := BOSSES.keys()
	for i in keys.size():
		var r := _boss_card(i)
		_box(r, "", true, keys[i] == boss)
		var tex := Art.boss(5)
		draw_texture(tex, (r.get_center() - Vector2(0, 8) - tex.get_size() / 2).round())
		_text(BOSSES[keys[i]], Vector2(r.get_center().x, r.end.y - 8), TEXT, true)


func _draw_equip() -> void:
	_box(_back_button(), "Back", true)
	_text(BOSSES[boss], Vector2(_view().x / 2, 30), TEXT, true)
	for s in SLOTS.size():
		var r := _slot(s)
		_box(r, "", true)
		_text(SLOTS[s], Vector2(r.get_center().x, r.position.y + 14), DIM, true)
		_icon(_equipped(s), r.get_center() + Vector2(0, 2))
		_text(_item_label(_equipped(s)), Vector2(r.get_center().x, r.end.y - 8), TEXT, true)
	_box(_fight_button(), "FIGHT", true)
	if picking >= 0:
		_draw_grid()


## The grid of icons for the slot being picked, over the equipment screen.
func _draw_grid() -> void:
	draw_rect(Rect2(Vector2.ZERO, _view()), Color(0, 0, 0, 0.7))
	var keys := _choices(picking)
	var panel := _grid_panel(keys.size())
	draw_rect(panel, PANEL)
	draw_rect(panel, DIM, false, 1.0)
	_text(SLOTS[picking], Vector2(panel.get_center().x, panel.position.y + 16), DIM, true)
	for i in keys.size():
		var r := _grid_cell(i)
		_box(r, "", true, keys[i] == _equipped(picking))
		_icon(keys[i], r.get_center() - Vector2(0, 6))
		_text(_item_label(keys[i]), Vector2(r.get_center().x, r.end.y - 8), TEXT, true)


## Icon for key drawn at twice its size, centred on c.
func _icon(key: String, c: Vector2) -> void:
	var size := Vector2(Art.ICON, Art.ICON) * 2
	draw_texture_rect(Art.icon(key), Rect2((c - size / 2).round(), size), false)


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


func _draw_panel() -> void:
	var o := _po()
	_text("Boss", o + Vector2(0, 16), TEXT)
	_bar(o + Vector2(30, 10), 142, fight.boss_hp, Fight.BOSS_HP, Art.STEEL)
	var cname: String = fight.card.get("name", "-")
	_text(cname, o + Vector2(0, 32), TEXT if fight.phase in ["boss", "defend"] else DIM)
	_text("deck %d" % fight.deck.size(), o + Vector2(140, 32), DIM)
	_text("You", o + Vector2(0, 60), TEXT)
	_bar(o + Vector2(30, 54), 142, fight.hp, Fight.HERO_HP, Art.HERO)
	_text(str(fight.hp), o + Vector2(0, 74), Art.HERO)
	for k in Fight.STAMINA:
		draw_rect(Rect2(o + Vector2(30 + k * 10, 66), Vector2(7, 7)), GOOD if k < fight.stamina else OFF)
	for k in Fight.FLASKS:
		draw_rect(Rect2(o + Vector2(30 + k * 10, 80), Vector2(7, 7)), HURT if k < fight.flasks else OFF)
	if fight.phase == "hero":
		var acts: Array = Fight.WEAPONS[fight.weapon].acts
		for i in acts.size():
			var a: Dictionary = acts[i]
			var r := _button(i)
			var ok := fight.can_attack(i)
			_box(r, "", ok)
			var c := TEXT if ok else DIM
			_text(fight.attack_label(i), r.position + Vector2(6, 14), c)
			for k in a.st:
				draw_rect(Rect2(r.position + Vector2(104 + k * 5, 9), Vector2(3, 3)), c)
			_text(str(fight.attack_damage(i)), r.position + Vector2(140, 14), c)
		_box(_button(2), "Flask", fight.can_flask())
		_box(_button(3), "End turn", true)
		var sr := _button(4)
		var sc := TEXT if fight.can_swap() else DIM
		_box(sr, "", fight.can_swap())
		_text("Swap: " + Fight.WEAPONS[fight.spare].label, sr.position + Vector2(6, 14), sc)
		for k in Fight.SWAP_COST:
			draw_rect(Rect2(sr.position + Vector2(160 + k * 5, 9), Vector2(3, 3)), sc)
	elif fight.phase == "defend" and check.is_empty():
		var inc := fight.incoming
		_text("%s  %d" % [inc.name, inc.dmg], o + Vector2(0, 118), HURT)
		var r := _button(1)
		_box(r, "", true)
		_text("Block", r.position + Vector2(6, 14), TEXT)
		_text(str(fight.block_damage()), r.position + Vector2(140, 14), TEXT)
		_box(_button(2), "Dodge", fight.can_dodge(), picking_dodge)
		var dc := fight.dodge_cost()
		var dcol := TEXT if fight.can_dodge() else DIM
		for k in dc:
			draw_rect(Rect2(_button(2).position + Vector2(140 + k * 5, 9), Vector2(3, 3)), dcol)


func _draw_check() -> void:
	var r := Rect2(_po() + Vector2(-2, 232), Vector2(176, 30))
	draw_rect(r, PANEL)
	draw_rect(r, TEXT, false, 1.0)
	var bar := Rect2(_po() + Vector2(6, 242), Vector2(160, 10))
	draw_rect(bar, OFF)
	var s: Vector2 = check.sweet
	draw_rect(Rect2(bar.position.x + roundf(bar.size.x * s.x), bar.position.y, maxf(1.0, roundf(bar.size.x * (s.y - s.x))), bar.size.y), GOOD.darkened(0.4))
	var p: float = check.at if check.done else minf(1.0, Fight.bar(check.t, check.diff, fight.armour))
	var c := TEXT
	if check.done:
		c = GOOD if check.ok else HURT
	draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * p), bar.size.y)).grow_individual(0, -3, 0, -3), c)
	draw_rect(Rect2(bar.position.x + roundf(bar.size.x * p), bar.position.y - 2, 1, bar.size.y + 4), c)
