class_name Art
## Pixel sprites built from a few simple shapes, sampled at pixel centres,
## seen from straight above. Only the right and up-right facings are drawn;
## the other four are mirror flips of those, so no pixel is ever rotated.

const BG := Color("0a0a0c")
const STEEL := Color("8e949c")
const DARK := Color("4a4e58")
const EDGE := Color("cdd0d4")
const HERO := Color("d2b47a")
const SCALE := 1.4  ## boss size (PLACEHOLDER)
const R := 16  ## boss image half size

static var _cache := {}


## The boss facing hex direction f (0 right, counter-clockwise).
static func boss(f: int) -> ImageTexture:
	if not _cache.has(f):
		_cache[f] = ImageTexture.create_from_image(boss_image(f))
	return _cache[f]


static func boss_image(f: int) -> Image:
	var hflip := f in [2, 3, 4]
	var vflip := f in [4, 5]
	var base := 0 if f in [0, 3] else 60
	# a single flip would move the shield to its right arm; draw it mirrored first
	var mirror := hflip != vflip
	var img := Image.create_empty(2 * R, 2 * R, false, Image.FORMAT_RGBA8)
	var a := deg_to_rad(base)
	var c := cos(a)
	var s := sin(a)
	for py in 2 * R:
		for px in 2 * R:
			var dx := px + 0.5 - R
			var dy := py + 0.5 - R
			var y := (dx * s + dy * c) / SCALE
			var col: Variant = _boss_at((dx * c - dy * s) / SCALE, -y if mirror else y)
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


## The hero: 5x5 figure and a 2-pixel weapon on the side facing the boss.
static func hero(pos: Vector2i, side: int, canvas: CanvasItem) -> void:
	for p in [Vector2i(0, -2), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 2), Vector2i(1, 2)]:
		canvas.draw_rect(Rect2(pos + p, Vector2.ONE), HERO)
	for dy in [-1, -2]:
		canvas.draw_rect(Rect2(pos + Vector2i(2 * side, dy), Vector2.ONE), HERO)
