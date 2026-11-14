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
	var shape := _longsword_at if weapon == "longsword" else _claymore_at
	return _sample(f, HR, HERO_SCALE, shape)


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
