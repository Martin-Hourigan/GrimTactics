class_name Art
## Pixel sprites built from a few simple shapes, sampled at pixel centres,
## seen from straight above. Only the right and up-right facings are drawn;
## the other four are mirror flips of those, so no pixel is ever rotated.

const BG := Color("0a0a0c")
const STEEL := Color("8e949c")
const DARK := Color("4a4e58")
const EDGE := Color("cdd0d4")
const HERO := Color("d2b47a")
const HERO_DARK := Color("7a6440")
const FOE := Color("9c6b5e")  ## the small enemies (PLACEHOLDER colours)
const FOE_DARK := Color("5e3f38")
const FIRE := Color("d9904f")
const FIRE_HOT := Color("ead08a")
const WOOD := Color("5a4630")
const SCALE := 2.9  ## boss size (PLACEHOLDER)
const R := 31  ## boss image half size
const HERO_SCALE := 2.0  ## hero size (PLACEHOLDER)
const HR := 22  ## hero image half size

static var _cache := {}


## The boss facing hex direction f (0 right, counter-clockwise).
static func boss(f: int) -> ImageTexture:
	var key := "boss %d" % f
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(boss_image(f))
	return _cache[key]


static func boss_image(f: int) -> Image:
	return _sample(f, R, SCALE, _boss_at)


## The hero facing hex direction f, holding weapon ("longsword" or "claymore").
static func hero(f: int, weapon: String) -> ImageTexture:
	var key := "hero %d %s" % [f, weapon]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(hero_image(f, weapon))
	return _cache[key]


static func hero_image(f: int, weapon: String) -> Image:
	var shape: Callable = {"longsword": _longsword_at, "claymore": _claymore_at, "bow": _bow_at}[weapon]
	return _sample(f, HR, HERO_SCALE, shape)


## A small enemy of kind (swordsman, crossbowman) holding held, facing f.
static func foe(kind: String, held: String, f: int) -> ImageTexture:
	var key := "foe %s %s %d" % [kind, held, f]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(foe_image(kind, held, f))
	return _cache[key]


static func foe_image(_kind: String, held: String, f: int) -> Image:
	var shape: Callable = {"sword": _foe_sword_at, "crossbow": _foe_crossbow_at, "shortsword": _foe_shortsword_at}[held]
	return _sample(f, HR, HERO_SCALE, shape)


const BONFIRE := 12  ## bonfire image half size


static func bonfire() -> ImageTexture:
	if not _cache.has("bonfire"):
		var img := Image.create_empty(2 * BONFIRE, 2 * BONFIRE, false, Image.FORMAT_RGBA8)
		for py in 2 * BONFIRE:
			for px in 2 * BONFIRE:
				var col: Variant = _bonfire_at(px + 0.5 - BONFIRE, py + 0.5 - BONFIRE)
				if col != null:
					img.set_pixel(px, py, col)
		_cache["bonfire"] = ImageTexture.create_from_image(img)
	return _cache["bonfire"]


## Logs crossed under a fire, seen from above.
static func _bonfire_at(x: float, y: float) -> Variant:
	if _ell(x, y, 0, 0, 2.5, 2.5):
		return FIRE_HOT
	if _ell(x, y, 0, 0, 5, 5):
		return FIRE
	if _seg(x, y, -9, -6, 9, 6, 1.6) or _seg(x, y, -9, 6, 9, -6, 1.6):
		return WOOD
	return null


const ICON := 24  ## menu icon size in pixels


## The menu icon for a weapon or armour key.
static func icon(key: String) -> ImageTexture:
	var k := "icon " + key
	if not _cache.has(k):
		_cache[k] = ImageTexture.create_from_image(icon_image(key))
	return _cache[k]


static func icon_image(key: String) -> Image:
	var shape: Callable = {
		"longsword": _longsword_icon, "claymore": _claymore_icon, "bow": _bow_icon,
		"light": _light_icon, "heavy": _heavy_icon, "cog": _cog_icon,
	}[key]
	var img := Image.create_empty(ICON, ICON, false, Image.FORMAT_RGBA8)
	for py in ICON:
		for px in ICON:
			var col: Variant = shape.call(px + 0.5 - ICON / 2.0, py + 0.5 - ICON / 2.0)
			if col != null:
				img.set_pixel(px, py, col)
	return img


# Icon shapes: pixel coordinates from the centre, y down.

static func _longsword_icon(x: float, y: float) -> Variant:
	if _seg(x, y, -0.8, 3.1, 4.3, 6.4, 0.8):
		return STEEL  # guard
	if _seg(x, y, 0, 8, 10, -9, 0.9):
		return EDGE  # blade
	if _ell(x, y, -5.5, 2, 5, 6.5):
		return HERO if not _ell(x, y, -5.5, 2, 3.8, 5.3) else HERO_DARK  # shield, rim
	return null


static func _claymore_icon(x: float, y: float) -> Variant:
	if _ell(x, y, -9.5, 9.5, 1.5, 1.5):
		return STEEL  # pommel
	if _seg(x, y, -5, 5, -9, 9, 0.9):
		return HERO_DARK  # grip
	if _seg(x, y, -8.5, 1.5, -1.5, 8.5, 0.9):
		return STEEL  # guard
	if _seg(x, y, -5, 5, 10, -10, 1.4):
		return EDGE  # blade
	return null


static func _bow_icon(x: float, y: float) -> Variant:
	if _seg(x, y, -4, 0, 9, 0, 0.6):
		return STEEL  # arrow
	if _seg(x, y, 9, 0, 7, -2, 0.6) or _seg(x, y, 9, 0, 7, 2, 0.6):
		return EDGE  # arrowhead
	if absf(Vector2(x - 9, y).length() - 14) < 0.9 and x < -1:
		return HERO  # bow
	if absf(x + 1) < 0.5 and absf(y) < 9.8:
		return HERO_DARK  # string
	return null


## The settings button in a fight.
static func _cog_icon(x: float, y: float) -> Variant:
	var d := Vector2(x, y).length()
	if d < 2.0:
		return null
	if d < 5.0:
		return STEEL
	if d < 7.0 and cos(8.0 * atan2(y, x)) > 0.2:
		return STEEL  # teeth
	return null


static func _light_icon(x: float, y: float) -> Variant:
	if _ell(x, y, 0, -9, 3, 3):
		return null  # neck
	if absf(y - 4) < 0.8 and _ell(x, y, 0, 1, 6, 9):
		return HERO_DARK  # belt
	if _ell(x, y, 0, 1, 6, 9):
		return HERO  # jerkin
	return null


static func _heavy_icon(x: float, y: float) -> Variant:
	if _ell(x, y, 0, -10, 3.5, 3.5):
		return null  # neck
	if _ell(x, y, -7.5, -5, 3.5, 3) or _ell(x, y, 7.5, -5, 3.5, 3):
		return EDGE  # pauldrons
	if _ell(x, y, 0, 1, 7, 10):
		return DARK if absf(y + 1) < 0.6 or absf(y - 4) < 0.6 else STEEL  # plates
	return null


## Draw shape (x, y -> colour or null) facing f into a (2r)^2 image.
static func _sample(f: int, r: int, scale: float, shape: Callable) -> Image:
	var hflip := f in [2, 3, 4]
	var vflip := f in [4, 5]
	var base := 0 if f in [0, 3] else 60
	# a single flip swaps left and right hands; draw it mirrored first
	var mirror := hflip != vflip
	var img := Image.create_empty(2 * r, 2 * r, false, Image.FORMAT_RGBA8)
	var a := deg_to_rad(base)
	var c := cos(a)
	var s := sin(a)
	for py in 2 * r:
		for px in 2 * r:
			var dx := px + 0.5 - r
			var dy := py + 0.5 - r
			var y := (dx * s + dy * c) / scale
			var col: Variant = shape.call((dx * c - dy * s) / scale, -y if mirror else y)
			if col != null:
				img.set_pixel(px, py, col)
	if hflip:
		img.flip_x()
	if vflip:
		img.flip_y()
	return img


## Colour at body coordinates (the boss looks along +x, its left is -y), or null.
static func _boss_at(x: float, y: float) -> Variant:
	if _ell(x, y, 0.6, 0, 2.4, 2.4):
		return EDGE  # helmet
	if _ell(x, y, 3.2, -4.8, 1.3, 3.4):
		return DARK  # shield on the left arm
	if _seg(x, y, 1.5, 4.6, 10.5, 4.6, 0.6):
		return EDGE  # sword in the right hand
	if _ell(x, y, -0.4, 0, 3.4, 5.6):
		return STEEL  # shoulders
	return null


static func _ell(x: float, y: float, cx: float, cy: float, rx: float, ry: float) -> bool:
	return pow((x - cx) / rx, 2) + pow((y - cy) / ry, 2) <= 1.0


static func _seg(x: float, y: float, ax: float, ay: float, bx: float, by: float, w: float) -> bool:
	var p := Vector2(ax, ay)
	var d := Vector2(bx, by) - p
	var t := clampf((Vector2(x, y) - p).dot(d) / d.length_squared(), 0.0, 1.0)
	return Vector2(x, y).distance_to(p + d * t) <= w


## The hero with longsword and shield (looks along +x, its left is -y).
static func _longsword_at(x: float, y: float) -> Variant:
	if _ell(x, y, 0.5, 0, 2.2, 2.2):
		return HERO  # helmet
	if _ell(x, y, 3.0, -4.4, 1.2, 3.0):
		return HERO_DARK  # shield on the left arm
	if _seg(x, y, 1.5, 4.2, 9.0, 4.2, 0.55):
		return HERO  # sword in the right hand
	if _ell(x, y, -0.4, 0, 3.0, 5.0):
		return HERO_DARK  # shoulders
	return null


## The hero holding a bow out front.
static func _bow_at(x: float, y: float) -> Variant:
	if _ell(x, y, 0.5, 0, 2.2, 2.2):
		return HERO  # helmet
	if absf(Vector2(x - 1, y).length() - 6) < 0.55 and x > 3.8:
		return HERO  # bow
	if _ell(x, y, -0.4, 0, 3.0, 5.0):
		return HERO_DARK  # shoulders
	return null


## The hero with a claymore held out front in both hands.
static func _claymore_at(x: float, y: float) -> Variant:
	if _ell(x, y, 0.5, 0, 2.2, 2.2):
		return HERO  # helmet
	if _seg(x, y, 3.0, 1.6, 10.5, 1.6, 0.75):
		return HERO  # blade
	if _seg(x, y, 2.8, -0.6, 2.8, 3.8, 0.55):
		return HERO  # crossguard
	if _ell(x, y, -0.4, 0, 3.0, 5.0):
		return HERO_DARK  # shoulders
	return null


## A small enemy with a sword (looks along +x, its left is -y).
static func _foe_sword_at(x: float, y: float) -> Variant:
	if _ell(x, y, 0.5, 0, 2.2, 2.2):
		return FOE  # helmet
	if _seg(x, y, 1.5, 4.2, 9.0, 4.2, 0.55):
		return STEEL  # sword in the right hand
	if _ell(x, y, -0.4, 0, 3.0, 5.0):
		return FOE_DARK  # shoulders
	return null


## A small enemy with a crossbow held out front.
static func _foe_crossbow_at(x: float, y: float) -> Variant:
	if _ell(x, y, 0.5, 0, 2.2, 2.2):
		return FOE  # helmet
	if _seg(x, y, 7.5, 0, 6.0, -3.6, 0.55) or _seg(x, y, 7.5, 0, 6.0, 3.6, 0.55):
		return EDGE  # the bow
	if _seg(x, y, 2.5, 0, 8.0, 0, 0.6):
		return STEEL  # the stock
	if _ell(x, y, -0.4, 0, 3.0, 5.0):
		return FOE_DARK  # shoulders
	return null


## The crossbowman with his shortsword out.
static func _foe_shortsword_at(x: float, y: float) -> Variant:
	if _ell(x, y, 0.5, 0, 2.2, 2.2):
		return FOE  # helmet
	if _seg(x, y, 1.5, 4.2, 6.5, 4.2, 0.55):
		return STEEL  # shortsword in the right hand
	if _seg(x, y, -2.5, -3.0, -2.5, 3.0, 0.5):
		return STEEL  # the crossbow on his back
	if _ell(x, y, -0.4, 0, 3.0, 5.0):
		return FOE_DARK  # shoulders
	return null
