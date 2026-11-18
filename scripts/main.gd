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
const WALL := Color("2e2a26")
const WALK_STEP := 0.12  ## seconds per hex walking out of a fight

const BOSSES := {"knight": "Knight"}  ## PLACEHOLDER name
const SLOTS := ["Weapon 1", "Weapon 2", "Armour"]

const SETTINGS := "user://settings.cfg"

var screen := "title"  ## title, settings, mode, boss, equip, fight
var mode := "stamina"
var level := "keep"  ## where Fight starts: keep (the bonfire), or arena (the boss alone)
var portrait := true  ## phone held upright: the room above the panel
var boss := "knight"
var picking := -1  ## the equipment slot whose grid is open, or -1
var paused := false  ## settings opened from the cog in a fight
var cam := Vector2.ZERO  ## the room is drawn so this point (the hero) is mid-screen
var pan := Vector2.ZERO  ## how far the player has dragged the view off the hero
var pan_hero := Vector2i.ZERO  ## where the hero stood when the view was dragged
var press_at := Vector2(-1, -1)  ## where a press on the room began, until it's let go
var dragged := false  ## the press has moved far enough to be a drag
var weapons := ["longsword", "claymore"]  ## the two weapon sets
var armour := "light"
var fight: Fight
var font: Font
var t := 0.0
var pause := 0.0
var flash := 0.0
var flash_hexes: Array[Vector2i] = []
var popups: Array[Dictionary] = []  ## {text, pos, colour, t}
var arrow := {}  ## an arrow flying to the boss: {from, to, t}
var picking_dodge := false
var menu := ""  ## the hero's menu: "" (top), attack, skills, items
## picking a hex for: hit0/hit1 (melee attacks), run (the running attack's
## hex), runhit (who it hits), combo, sweep, shot0/shot1 (bow attacks), aimed
var aiming := ""
var run_to := Vector2i.ZERO  ## the hex the running attack runs to, while picking who it hits
var walking: Array[Vector2i] = []  ## hexes left to walk, out of a fight
var walk_t := 0.0
var hero_face := 2  ## the way the hero looks out of a fight
var walls: Array[Vector2i] = []  ## the hexes drawn as wall round the ground
var check := {}  ## the dodge check while it runs: {to, t, diff, time, sweet, done, ok}
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
	var li := args.find("--level")
	if li >= 0 and li + 1 < args.size():
		level = args[li + 1]
	var mi := args.find("--mode")
	if mi >= 0 and mi + 1 < args.size():
		mode = args[mi + 1]
	var mn := args.find("--menu")
	var shot_menu: String = args[mn + 1] if mn >= 0 and mn + 1 < args.size() else ""
	var wi := args.find("--weapons")
	if wi >= 0 and wi + 1 < args.size():
		weapons = Array(args[wi + 1].split(","))
	if "--fight" in args or auto > 0:
		start()
	var at := args.find("--at")  # --at q,r: the hero starts there (for screenshots)
	if at >= 0 and at + 1 < args.size() and fight != null:
		var qr: PackedStringArray = args[at + 1].split(",")
		fight.hero = Vector2i(int(qr[0]), int(qr[1]))
		fight._wake()
		cam = _cam_target()
	var pn := args.find("--pan")  # --pan x,y: drag the view by x,y (for screenshots)
	if pn >= 0 and pn + 1 < args.size() and fight != null:
		var xy: PackedStringArray = args[pn + 1].split(",")
		_pan_by(Vector2(float(xy[0]), float(xy[1])))
		cam = _cam_target() + pan
	if shot_menu != "":
		menu = shot_menu.get_slice("-", 0)
		aiming = shot_menu.get_slice("-", 1) if "-" in shot_menu else ""
		if at < 0:
			fight.hero = fight.boss + Fight.FACES.back() * (1 if aiming in ["", "sweep", "hit0", "hit1", "combo"] else 3)
		cam = _cam_target()
	font = ThemeDB.fallback_font
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		portrait = cfg.get_value("screen", "portrait", true)
	if "--portrait" in args:
		portrait = true
	if "--landscape" in args:
		portrait = false
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


## Where the hero stands on screen.
func _centre() -> Vector2:
	return Vector2(135, 124) if portrait else Vector2(150, 148)


## The hero's place in the room, in pixels, which the camera follows.
func _cam_target() -> Vector2:
	return HR * Fight.flat(fight.hero) * Vector2(1, -1)


## The part of the screen the room shows in, inside its border.
func _field() -> Rect2:
	return _frame_rect().grow(-Art.FRAME)


## The room's border, outside edge.
func _frame_rect() -> Rect2:
	if portrait:
		return Rect2(0, 32, _view().x, _po().y + 76 - 32)
	return Rect2(0, 32, _po().x - 6, _view().y - 32)


## Drags the view by d, as far as putting the hero at the field's far edge.
func _pan_by(d: Vector2) -> void:
	var f := _field().grow(-HR * 1.5)
	pan = (pan - d).clamp(_centre() - f.end, _centre() - f.position)
	pan_hero = fight.hero


## Top left of the fight panel (its parts sit at the same places relative to it).
func _po() -> Vector2:
	return Vector2(49, 218) if portrait else Vector2(300, 0)


func start() -> void:
	fight = Fight.new(weapons[0], armour, randi(), weapons[1], mode, level)
	walls.clear()
	for c in fight.ground:
		for d in Fight.DIRS:
			if not fight.ground.has(c + d) and not c + d in walls:
				walls.append(c + d)
	walking.clear()
	hero_face = 1 if Fight.SQUARE else 2  # up
	popups.clear()
	check = {}
	picking_dodge = false
	menu = ""
	aiming = ""
	pan = Vector2.ZERO
	press_at = Vector2(-1, -1)
	cam = _cam_target()
	paused = false
	screen = "fight"


func hex_pos(c: Vector2i) -> Vector2:
	return _centre() + (HR * Fight.flat(c) * Vector2(1, -1)).round() - cam.round()


func _process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta)
	update_note = maxf(0.0, update_note - delta)
	if screen == "fight":
		_tick(delta)
		if not fight.phase in ["hero", "explore"]:
			menu = ""
		if fight.phase != "hero":
			aiming = ""
		if fight.phase != "explore":
			walking.clear()
		if fight.hero != pan_hero:
			pan = Vector2.ZERO  # the view goes back to the hero when they move
		var to := _cam_target() + pan
		cam = to if dragged else cam.lerp(to, minf(1.0, delta * 10.0))
		if cam.distance_to(to) < 0.5:
			cam = to
	if not arrow.is_empty():
		arrow.t += delta
		if arrow.t > 0.25:
			arrow = {}
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
		elif Fight.bar(check.t, check.diff, check.time) >= 1.0:
			_stop_check()
	elif fight.phase == "explore" and not walking.is_empty():
		walk_t += delta
		if walk_t >= WALK_STEP:
			walk_t = 0.0
			var c: Vector2i = walking.pop_front()
			hero_face = Fight._facing_from(fight.hero, c)
			fight.walk(c)
			if fight.hero != c:
				walking.clear()
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
			"hit":
				_popup(str(e.dmg), hex_pos(e.at) + Vector2([0, -12, 12][e.k % 3], -12 - e.k * 5), TEXT)
				if Fight.dist(e.from, e.at) > 1:
					arrow = {"from": hex_pos(e.from), "to": hex_pos(e.at), "t": 0.0}
			"bolt":
				arrow = {"from": hex_pos(e.from), "to": hex_pos(e.to), "t": 0.0}
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
	check = {"to": to, "t": 0.0, "diff": diff, "time": fight.dodge_time(), "sweet": Fight.sweet(diff), "done": false, "ok": false, "at": 0.0}


func _stop_check() -> void:
	var p := minf(1.0, Fight.bar(check.t, check.diff, check.time))
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
	if screen == "fight" and _room_drag(ev):
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
		"mode":
			_mode_tap(p)
			return
		"boss":
			_boss_tap(p)
			return
		"equip":
			_equip_tap(p)
			return
	if _cog_button().has_point(p):
		paused = true
		screen = "settings"
		return
	_fight_tap(p)


## A press on the room drags the view; let go without dragging, it's a tap.
func _room_drag(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and _hex_free(ev.position) and not _cog_button().has_point(ev.position):
			press_at = ev.position
			dragged = false
			return true
		if not ev.pressed and press_at.x >= 0:
			var p := press_at
			press_at = Vector2(-1, -1)
			if not dragged:
				_fight_tap(p)
			dragged = false
			return true
	if ev is InputEventMouseMotion and press_at.x >= 0:
		if not dragged and ev.position.distance_to(press_at) > 6.0:
			dragged = true
			_pan_by(ev.position - press_at)
		elif dragged:
			_pan_by(ev.relative)
		return true
	return false


func _fight_tap(p: Vector2) -> void:
	if fight.phase in ["win", "lose"]:
		if fight.phase == "lose" and fight.level == "keep":
			start()  # back at the bonfire
		else:
			screen = "equip"
		return
	if auto > 0:
		return
	if fight.phase == "defend":
		_defend_tap(p)
	elif fight.phase in ["hero", "explore"]:
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
		screen = "mode"
	elif _settings_button().has_point(p):
		screen = "settings"


func _settings_tap(p: Vector2) -> void:
	if _back_button().has_point(p):
		screen = "fight" if paused else "title"
		paused = false
		return
	if paused and _leave_button().has_point(p):
		paused = false
		screen = "title"
		return
	for i in 2:
		if _choice(0, i).has_point(p) and portrait != (i == 1):
			portrait = i == 1
			_save_settings()
			_apply_screen()


func _mode_tap(p: Vector2) -> void:
	if _back_button().has_point(p):
		screen = "title"
		return
	var keys := Fight.MODES.keys()
	for i in keys.size():
		if _mode_button(i).has_point(p):
			mode = keys[i]
			screen = "boss"


func _boss_tap(p: Vector2) -> void:
	if _back_button().has_point(p):
		screen = "mode"
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
	var c: Variant = _hex_at(p)
	if aiming != "":
		var was := aiming
		aiming = ""
		if was.begins_with("hit") and c != null and fight.can_attack(int(was.substr(3)), c):
			fight.attack(int(was.substr(3)), c)
			return
		if was == "combo" and c != null and fight.in_reach(c):
			fight.combo_attack(c)
			return
		if was == "run" and c != null and c in fight.run_hexes():
			var ts := fight.run_targets(c)
			if ts.size() == 1:
				fight.run_attack(c, ts[0])
			else:
				run_to = c
				aiming = "runhit"
			return
		if was == "runhit" and c != null and c in fight.run_targets(run_to):
			fight.run_attack(run_to, c)
			return
		if was == "sweep" and c != null and _sweep_dir(c) in fight.sweep_aims():
			fight.sweep(_sweep_dir(c))
			return
		if was.begins_with("shot") and c != null and fight.can_aim(c):
			fight.shoot(int(was.substr(4)), c)
			return
		if was == "aimed" and c != null and fight.can_aim(c):
			fight.aimed_shot(c)
			return
	var back := menu != "" and _button(4).has_point(p)
	var in_fight := fight.phase == "hero"
	match menu:
		"":
			if _button(0).has_point(p) and in_fight:
				menu = "attack"
			elif _button(1).has_point(p) and in_fight and not fight.skills().is_empty():
				menu = "skills"
			elif _button(2).has_point(p):
				menu = "items"
			elif _button(3).has_point(p):
				fight.swap()
			elif _button(4).has_point(p):
				if in_fight:
					fight.end_turn()
				else:
					fight.rest()
		"attack":
			for i in Fight.WEAPONS[fight.weapon].acts.size():
				if _button(i).has_point(p):
					if fight.can_attack(i):
						aiming = ("shot%d" if fight.ranged() else "hit%d") % i
			if _button(2).has_point(p) and fight.can_run_attack():
				aiming = "run"
		"skills":
			var sk: Array = fight.skills()
			for i in sk.size():
				if _button(i).has_point(p) and fight.can_skill(sk[i]):
					match sk[i]:
						"combo":
							aiming = "combo"
						"sweep":
							aiming = "sweep"
						"aimed":
							aiming = "aimed"
		"items":
			if _button(0).has_point(p):
				fight.flask()
	if back:
		menu = ""
		return
	if c == null or not _hex_free(p):
		return
	if fight.phase == "explore" and fight.steps(c) > 0:
		walking = fight.path(fight.hero, c)
		walk_t = WALK_STEP
	elif fight.can_move(c):
		fight.move(c)


## Which way from the hero hex c is, or -1 if it isn't next to the hero.
func _sweep_dir(c: Vector2i) -> int:
	return Fight.DIRS.find(c - fight.hero)


## Whether p is on the room and not on the panel or the bar along the top.
func _hex_free(p: Vector2) -> bool:
	return _field().has_point(p)


func _defend_tap(p: Vector2) -> void:
	if picking_dodge:
		var c: Variant = _hex_at(p)
		if c != null and c in fight.dodge_hexes():
			_start_check(c)
			return
	if _defend_button(0).has_point(p) and fight.can_block():
		picking_dodge = false
		fight.defend_block()
	elif _defend_button(1).has_point(p) and fight.can_dodge():
		picking_dodge = true
	elif _defend_button(2).has_point(p):
		picking_dodge = false
		fight.take_hit()


func _hex_at(p: Vector2) -> Variant:
	for c in fight.ground:
		var d := p - hex_pos(c)
		if (maxf(absf(d.x), absf(d.y)) < HR * Fight.SQ_SIZE / 2.0) if Fight.SQUARE else d.length() < HR * 0.9:
			return c
	return null


func _button(i: int) -> Rect2:
	return Rect2(_po() + Vector2(0, 128 + i * 26), Vector2(172, 22))


## The pop-up for defending and the dodge check: mid-screen, clear of the
## hexes round the hero.
func _defend_box() -> Rect2:
	var c := Vector2(135, 228) if portrait else Vector2(305, 200)
	var size := Vector2(184, 108)
	return Rect2((c - size / 2).round(), size)


## Block, Dodge, Take the hit.
func _defend_button(i: int) -> Rect2:
	return Rect2(_defend_box().position + Vector2(6, 26 + i * 26), Vector2(172, 22))


func _play_button() -> Rect2:
	return Rect2(_view().x / 2 - 50, 130, 100, 26)


func _settings_button() -> Rect2:
	return Rect2(_view().x / 2 - 50, 164, 100, 26)


## Option i of row row on the settings page.
func _choice(row: int, i: int) -> Rect2:
	var w := 120.0 if portrait else 146.0
	return Rect2(_view().x / 2 - w - 4 + i * (w + 8), 70 + row * 36, w, 24)


func _mode_button(i: int) -> Rect2:
	return Rect2(_view().x / 2 - 70, 70 + i * 36, 140, 24)


func _leave_button() -> Rect2:
	return Rect2(_view().x / 2 - 60, 140, 120, 24)


func _cog_button() -> Rect2:
	return Rect2(_view().x - 24, 2, 22, 22)


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
		"mode":
			_draw_modes()
			return
		"boss":
			_draw_boss_select()
			return
		"equip":
			_draw_equip()
			return
	_draw_room()
	_draw_panel()
	_draw_top()
	_draw_frame()
	if not check.is_empty():
		_draw_check()
	elif fight.phase == "defend":
		_draw_defend()
	if not arrow.is_empty():
		var head: Vector2 = arrow.from.lerp(arrow.to, minf(1.0, arrow.t / 0.15))
		draw_line(head.lerp(arrow.from, 0.3), head, TEXT)
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
	if paused:
		_box(_leave_button(), "Main menu", true)


func _draw_modes() -> void:
	_box(_back_button(), "Back", true)
	var keys := Fight.MODES.keys()
	for i in keys.size():
		_box(_mode_button(i), Fight.MODES[keys[i]], true, keys[i] == mode)


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
	if Fight.SQUARE:
		var h := roundf(r * Fight.SQ_SIZE / 2.0)
		for v in [Vector2(h, h), Vector2(-h, h), Vector2(-h, -h), Vector2(h, -h)]:
			pts.append((c + v).round())
		return pts
	for k in 6:
		var a := deg_to_rad(60.0 * k + 30.0)
		pts.append((c + r * Vector2(cos(a), sin(a))).round())
	return pts


func _draw_room() -> void:
	var hitting: Array = fight.incoming.get("hexes", flash_hexes if flash > 0.0 else [])
	var dodging: Array = fight.dodge_hexes() if picking_dodge else []
	var shots := []
	if aiming.begins_with("shot") or aiming == "aimed":
		for e in fight.targets():
			shots.append_array(fight.shot_path(e))
	for c in walls:
		draw_colored_polygon(_hex_poly(hex_pos(c), HR - 1.0), WALL)
	for c in fight.ground:
		var col := HEX
		if c in hitting:
			col = HEX_HIT
		elif c in dodging:
			col = HEX_REACH
		elif aiming == "run":
			col = HEX_REACH if c in fight.run_hexes() else HEX
		elif aiming == "sweep":
			col = HEX_REACH if _sweep_dir(c) in fight.sweep_aims() else HEX
		elif aiming.begins_with("shot") or aiming == "aimed":
			col = HEX_REACH if c in shots else HEX
		elif aiming == "runhit":
			col = HEX_REACH if c == run_to else HEX
		elif aiming != "":
			col = HEX
		elif fight.phase == "hero" and fight.can_move(c):
			col = HEX_REACH
		if c != fight.boss and fight.phase == "hero" and fight.weak_at(c) and not c in hitting:
			col = col.lerp(HEX_WEAK, 0.7)
		draw_colored_polygon(_hex_poly(hex_pos(c), HR - 1.0), col)
		if c in hitting and fmod(t, 0.5) < 0.35:
			var edge := _hex_poly(hex_pos(c), HR - 1.0)
			edge.append(edge[0])
			draw_polyline(edge, HIT_EDGE, 1.0)
		if aiming == "run" and c in fight.run_hexes():
			_text(str(fight.run_damage(c)), hex_pos(c) + Vector2(0, 3), TEXT, true)
		# stamina a move there costs
		elif fight.phase == "hero" and fight.can_move(c) and aiming == "":
			var n := fight.move_cost(c)
			var base := hex_pos(c) + Vector2(0, 8)
			for k in n:
				draw_rect(Rect2((base + Vector2(k * 3 - n * 1.5, 0)).round(), Vector2.ONE), DIM)
	if fight.bonfire != Fight.NONE:
		draw_texture(Art.bonfire(), hex_pos(fight.bonfire) - Vector2(Art.BONFIRE, Art.BONFIRE))
	if fight.boss_in_fight():
		_draw_arc_lines()
	if fight.boss_hp > 0:
		draw_texture(Art.boss(fight.facing), hex_pos(fight.boss) - Vector2(Art.R, Art.R))
	for f in fight.foes:
		if f.hp <= 0:
			continue
		var fp := hex_pos(f.at)
		draw_texture(Art.foe(f.kind, f.held, f.facing), fp - Vector2(Art.HR, Art.HR))
		if f.awake:
			var bw := 20.0
			draw_rect(Rect2(fp + Vector2(-bw / 2, -HR + 1), Vector2(bw, 2)), OFF)
			draw_rect(Rect2(fp + Vector2(-bw / 2, -HR + 1), Vector2(roundf(bw * f.hp / Fight.FOES[f.kind].hp), 2)), HURT)
	# the enemies the attack being aimed can hit
	for c in _aim_targets():
		var edge := _hex_poly(hex_pos(c), HR - 1.0)
		edge.append(edge[0])
		draw_polyline(edge, TEXT if fmod(t, 0.6) < 0.4 else DIM, 1.0)
	draw_texture(Art.hero(_hero_facing(), fight.weapon), hex_pos(fight.hero) - Vector2(Art.HR, Art.HR))


## The enemies that can be tapped for the attack being aimed.
func _aim_targets() -> Array[Vector2i]:
	if aiming.begins_with("hit") or aiming.begins_with("shot") or aiming in ["combo", "aimed"]:
		return fight.targets()
	if aiming == "runhit":
		return fight.run_targets(run_to)
	return []


## In a fight the hero looks at the nearest enemy in it; otherwise the way it walked.
func _hero_facing() -> int:
	var best := Fight.NONE
	for c in fight.fighting():
		if best == Fight.NONE or Fight.dist(fight.hero, c) < Fight.dist(fight.hero, best):
			best = c
	if best == Fight.NONE or fight.phase == "explore":
		return hero_face
	return Fight._facing_from(fight.hero, best)


## The lines between the boss's four arcs.
func _draw_arc_lines() -> void:
	var o := hex_pos(fight.boss)
	var step := 360.0 / Fight.FACES.size()
	for rel in [step / 2, -step / 2, 180.0 - step / 2, step / 2 - 180.0]:
		var a := deg_to_rad(step * fight.facing + rel)
		var d := Vector2(cos(a), -sin(a))
		draw_line(o + d * HR * 0.8, o + d * HR * 2.2, ARC_LINE, 1.0)


func _bar(pos: Vector2, w: float, v: float, vmax: float, c: Color) -> void:
	draw_rect(Rect2(pos, Vector2(w, 4)), OFF)
	draw_rect(Rect2(pos, Vector2(roundf(w * v / vmax), 4)), c)


## The boss's health along the top of the screen, and the cog.
## The stone border round the room.
func _draw_frame() -> void:
	var f := _frame_rect()
	draw_texture(Art.frame(Vector2i(f.size)), f.position)


func _draw_top() -> void:
	var w := _view().x
	draw_rect(Rect2(0, 0, w, 32), Art.BG)
	if fight.boss_in_fight() or fight.phase == "win":
		_bar(Vector2(8, 8), w - 40, fight.boss_hp, Fight.BOSS_HP, Art.STEEL)
		var cname: String = fight.card.get("name", "-")
		_text(cname, Vector2(8, 26), TEXT if fight.phase in ["boss", "defend"] and fight.actor == "boss" else DIM)
		var deck := "deck %d" % fight.deck.size()
		_text(deck, Vector2(w - 32 - font.get_string_size(deck, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, 26), DIM)
	var cog := _cog_button()
	draw_texture(Art.icon("cog"), (cog.get_center() - Vector2(Art.ICON, Art.ICON) / 2).round())


func _draw_panel() -> void:
	var o := _po()
	# the room scrolls under the panel; in portrait it shows down to the hero's rows
	if portrait:
		draw_rect(Rect2(0, o.y + 76, _view().x, _view().y - o.y - 76), Art.BG)
	else:
		draw_rect(Rect2(o.x - 6, 0, _view().x - o.x + 6, _view().y), Art.BG)
	# in portrait the hero's rows sit under the defend pop-up
	var y := 36.0 if portrait else 0.0
	_text("You", o + Vector2(0, 60 + y), TEXT)
	_bar(o + Vector2(30, 54 + y), 142, fight.hp, Fight.HERO_HP, Art.HERO)
	_text(str(fight.hp), o + Vector2(0, 74 + y), Art.HERO)
	if fight.uses_stamina():
		for k in Fight.STAMINA:
			draw_rect(Rect2(o + Vector2(30 + k * 10, 66 + y), Vector2(7, 7)), GOOD if k < fight.stamina else OFF)
	elif fight.mode == "order":
		# who goes next, this turn first
		var order := fight.turn_order(8)
		for k in order.size():
			var oc: Color = {"hero": Art.HERO, "boss": Art.STEEL}.get(order[k], Art.FOE)
			draw_rect(Rect2(o + Vector2(30 + k * 10, 66 + y), Vector2(7, 7)), oc)
		draw_rect(Rect2(o + Vector2(30, 75 + y), Vector2(7, 1)), TEXT)
	for k in Fight.FLASKS:
		draw_rect(Rect2(o + Vector2(30 + k * 10, 80 + y), Vector2(7, 7)), HURT if k < fight.flasks else OFF)
	if fight.arrows > 0 or Fight.WEAPONS[fight.weapon].has("arrows") or Fight.WEAPONS[fight.spare].has("arrows"):
		_text("arrows %d" % fight.arrows, o + Vector2(120, 87 + y), TEXT if fight.arrows > 0 else DIM)
	if fight.phase in ["hero", "explore"]:
		_draw_menu()


## The hero's menu: Attack, Skills and Items open their own lists.
func _draw_menu() -> void:
	var st := fight.uses_stamina()
	match menu:
		"":
			var in_fight := fight.phase == "hero"
			_entry(0, "Attack", in_fight, 0, "", true)
			_entry(1, "Skills", in_fight and not fight.skills().is_empty(), 0, "", true)
			_entry(2, "Items", true, 0, "", true)
			_entry(3, "Swap: " + Fight.WEAPONS[fight.spare].label, fight.can_swap(), Fight.SWAP_COST if st and in_fight else 0, "", false, false, 160)
			if in_fight:
				_entry(4, "End turn", true)
			elif fight.can_rest():
				_entry(4, "Rest", true)
		"attack":
			var acts: Array = Fight.WEAPONS[fight.weapon].acts
			for i in acts.size():
				_entry(i, fight.attack_label(i), fight.can_attack(i), acts[i].st if st else 0, str(fight.attack_damage(i)), false, aiming in ["shot%d" % i, "hit%d" % i])
			if fight.has_run():
				_entry(2, "Running attack", fight.can_run_attack(), acts[0].st if st else 0, "", false, aiming in ["run", "runhit"])
		"skills":
			var sk: Array = fight.skills()
			for i in sk.size():
				var s: Dictionary = Fight.SKILLS[sk[i]]
				var dmg := fight.combo_damage() if sk[i] == "combo" else fight.skill_damage(sk[i])
				var right := "next turn" if fight.waiting(sk[i]) else str(dmg)
				_entry(i, s.label, fight.can_skill(sk[i]), s.st if st else 0, right, false, aiming == sk[i])
		"items":
			_entry(0, "Flask", fight.can_flask(), 0, "%d left" % fight.flasks)
	if menu != "":
		_entry(4, "Back", true)


## One menu button: label, stamina pips, a number on the right, and > if it
## opens a list.
func _entry(i: int, label: String, ok: bool, pips := 0, right := "", opens := false, picked := false, pip_x := 104) -> void:
	var r := _button(i)
	var c := TEXT if ok else DIM
	_box(r, "", ok, picked)
	_text(label, r.position + Vector2(6, 14), c)
	for k in pips:
		draw_rect(Rect2(r.position + Vector2(pip_x + k * 5, 9), Vector2(3, 3)), c)
	if right != "":
		_text(right, r.position + Vector2(140, 14), c)
	if opens:
		_text(">", r.position + Vector2(r.size.x - 12, 14), c)


func _draw_defend() -> void:
	var box := _defend_box()
	draw_rect(box, PANEL)
	draw_rect(box, TEXT, false, 1.0)
	var inc := fight.incoming
	_text("%s  %d" % [inc.name, inc.dmg], box.position + Vector2(8, 16), HURT)
	var r := _defend_button(0)
	var bcol := TEXT if fight.can_block() else DIM
	_box(r, "", fight.can_block())
	_text("Block", r.position + Vector2(6, 14), bcol)
	for k in (fight.block_cost() if fight.uses_stamina() else 0):
		draw_rect(Rect2(r.position + Vector2(104 + k * 5, 9), Vector2(3, 3)), bcol)
	_text(str(fight.block_damage()), r.position + Vector2(140, 14), bcol)
	var dr := _defend_button(1)
	_box(dr, "Dodge", fight.can_dodge(), picking_dodge)
	var dcol := TEXT if fight.can_dodge() else DIM
	for k in (fight.dodge_cost() if fight.uses_stamina() else 0):
		draw_rect(Rect2(dr.position + Vector2(140 + k * 5, 9), Vector2(3, 3)), dcol)
	var th := _defend_button(2)
	_box(th, "", true)
	_text("Take the hit", th.position + Vector2(6, 14), TEXT)
	_text(str(inc.dmg), th.position + Vector2(140, 14), TEXT)


func _draw_check() -> void:
	var r := Rect2((_defend_box().get_center() - Vector2(92, 15)).round(), Vector2(184, 30))
	draw_rect(r, PANEL)
	draw_rect(r, TEXT, false, 1.0)
	var bar := Rect2(r.position + Vector2(12, 10), Vector2(160, 10))
	draw_rect(bar, OFF)
	var s: Vector2 = check.sweet
	draw_rect(Rect2(bar.position.x + roundf(bar.size.x * s.x), bar.position.y, maxf(1.0, roundf(bar.size.x * (s.y - s.x))), bar.size.y), GOOD.darkened(0.4))
	var p: float = check.at if check.done else minf(1.0, Fight.bar(check.t, check.diff, check.time))
	var c := TEXT
	if check.done:
		c = GOOD if check.ok else HURT
	draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * p), bar.size.y)).grow_individual(0, -3, 0, -3), c)
	draw_rect(Rect2(bar.position.x + roundf(bar.size.x * p), bar.position.y - 2, 1, bar.size.y + 4), c)
