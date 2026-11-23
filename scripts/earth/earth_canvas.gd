class_name NelvarEarthCanvas
extends RefCounted
## Pixels of one baked sprite on the world pixel grid, with the drawing primitives of
## the menu art (tools/gen_menu_backgrounds.py): blobs lit like spheres from the upper
## right and Bayer-dithered, soft ground shadows, outlines on shaded edges.
##
## Coordinates are art pixels relative to the sprite's ground origin (x right, y
## down). Dithering and grain follow the world grid, so neighbouring sprites match.
## Pure pixel work: safe to use from a worker thread.

const STEP := NelvarEarthData.PIXEL
## Ground shadow on the grass; translucent, so the player's outline ignores it.
const SHADOW := Color(0.07, 0.17, 0.1, 0.3)
const WOBBLE_BINS := 48


## A wobbly ellipse lit like a sphere. `flat`: cut off below this unit height.
class Blob:
	var center := Vector2.ZERO
	var axes := Vector2.ONE
	var flat := 2.0
	var wobble := 0.12
	var texture := 0.15
	## Added to the light level: positive is brighter.
	var bias := 0.0
	var salt := 0
	var phase := Vector2.ZERO
	## Shaded rim of this blob (where it meets what is behind it); none when alpha is 0.
	var rim := Color(0, 0, 0, 0)
	var rim_level := 0.6


var image: Image
var size: Vector2i
## World texel of the image's top-left pixel.
var grid: Vector2i
## Position of the image's top-left corner, art pixels from the origin.
var offset: Vector2
## 1 where opaque art is painted (shadows excluded) and the light level there.
var body: PackedByteArray
var levels: PackedFloat32Array


## `bounds`: the area to paint, art pixels around the origin.
func _init(origin: Vector2, bounds: Rect2) -> void:
	var world_from := ((origin + bounds.position * STEP) / STEP).floor() * STEP
	size = Vector2i(((origin + bounds.end * STEP - world_from) / STEP).ceil()).max(Vector2i.ONE)
	grid = Vector2i((world_from / STEP).round())
	offset = (world_from - origin) / STEP
	image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	body.resize(size.x * size.y)
	levels.resize(size.x * size.y)


func local_rect() -> Rect2:
	return Rect2(offset * STEP, Vector2(size) * STEP)


## Pixel under a point in art pixels around the origin.
func pixel(point: Vector2) -> Vector2i:
	return Vector2i((point - offset).floor())


func center_of(x: int, y: int) -> Vector2:
	return offset + Vector2(x + 0.5, y + 0.5)


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size.x and y < size.y


func is_body(x: int, y: int) -> bool:
	return inside(x, y) and body[y * size.x + x] == 1


func put(x: int, y: int, color: Color, level: float = 1.0) -> void:
	if not inside(x, y):
		return
	image.set_pixel(x, y, color)
	body[y * size.x + x] = 1
	levels[y * size.x + x] = level


func put_at(point: Vector2, color: Color, level: float = 1.0) -> void:
	var p := pixel(point)
	put(p.x, p.y, color, level)


func ramp(colors: Array[Color], level: float, x: int, y: int) -> Color:
	return NelvarPixelArt.ramp(colors, level, grid + Vector2i(x, y))


func grain(x: int, y: int, scale: float, salt: int) -> float:
	return NelvarPixelArt.value_noise((grid.x + x) * scale, (grid.y + y) * scale, salt) - 0.5


## Soft ground shadow: a dithered ellipse that only darkens empty pixels.
func shadow(center: Vector2, reach: Vector2) -> void:
	var from := pixel(center - reach)
	var to := pixel(center + reach)
	for y in range(maxi(0, from.y), mini(size.y, to.y + 1)):
		for x in range(maxi(0, from.x), mini(size.x, to.x + 1)):
			if body[y * size.x + x] == 1 or image.get_pixel(x, y).a > 0.0:
				continue
			var color := NelvarPixelArt.shadow_at(center_of(x, y), center, reach, grid + Vector2i(x, y))
			if color.a > 0.0:
				image.set_pixel(x, y, SHADOW)


func blob(b: Blob, colors: Array[Color]) -> void:
	var reach := b.axes * (1.0 + b.wobble)
	var from := pixel(b.center - reach)
	var to := pixel(b.center + reach)
	from = from.max(Vector2i.ZERO)
	to = to.min(size - Vector2i.ONE)
	if to.x < from.x or to.y < from.y:
		return
	var table := PackedFloat32Array()
	table.resize(WOBBLE_BINS + 1)
	for i in WOBBLE_BINS + 1:
		var angle := TAU * float(i) / WOBBLE_BINS
		table[i] = NelvarPixelArt.value_noise(cos(angle) * 1.7 + b.phase.x,
			sin(angle) * 1.7 + b.phase.y, 7) * 2.0 - 1.0
	var w := to.x - from.x + 1
	var h := to.y - from.y + 1
	var mask := PackedByteArray()
	mask.resize(w * h)
	var units := PackedVector2Array()
	units.resize(w * h)
	for y in h:
		for x in w:
			var local := (center_of(from.x + x, from.y + y) - b.center) / b.axes
			if local.y > b.flat:
				continue
			var distance := local.length()
			var edge := 1.0
			if distance > 0.0:
				var f := fposmod(atan2(local.y, local.x) / TAU, 1.0) * WOBBLE_BINS
				var i := int(f)
				edge += b.wobble * lerpf(table[i], table[i + 1], f - i)
			if distance <= edge:
				mask[y * w + x] = 1
				units[y * w + x] = local / edge
	var light := NelvarPixelArt.LIGHT
	for y in h:
		for x in w:
			if mask[y * w + x] == 0:
				continue
			var u := units[y * w + x]
			var nz := sqrt(maxf(0.0, 1.0 - u.length_squared()))
			var lit := u.x * light.x + u.y * light.y + nz * light.z
			var px := from.x + x
			var py := from.y + y
			var level := 0.35 + 0.5 * lit + b.bias + grain(px, py, 0.45, b.salt + 5) * b.texture * 2.0
			var color := ramp(colors, level, px, py)
			if b.rim.a > 0.0 and level < b.rim_level and (x == 0 or y == 0 or x == w - 1 or y == h - 1
					or mask[y * w + x - 1] == 0 or mask[y * w + x + 1] == 0
					or mask[(y - 1) * w + x] == 0 or mask[(y + 1) * w + x] == 0):
				color = b.rim
			put(px, py, color, level)


## A blob from the usual parameters; `rng` varies its edge and grain.
static func make_blob(rng: RandomNumberGenerator, center: Vector2, axes: Vector2, bias: float = 0.0,
		texture: float = 0.15, flat: float = 2.0, wobble: float = 0.12) -> Blob:
	var b := Blob.new()
	b.center = center
	b.axes = axes
	b.bias = bias
	b.texture = texture
	b.flat = flat
	b.wobble = wobble
	b.salt = rng.randi() & 0xffff
	b.phase = Vector2(rng.randf_range(0.0, 64.0), rng.randf_range(0.0, 64.0))
	return b


## Shaded pixels on the outer edge of everything painted get the dark outline; the
## brightly lit upper-right edge stays open, as in the menu art.
func outline_silhouette(color: Color, level_limit: float) -> void:
	var marks: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var index := y * size.x + x
			if body[index] == 0 or levels[index] >= level_limit:
				continue
			if not is_body(x - 1, y) or not is_body(x + 1, y) or not is_body(x, y - 1) \
					or not is_body(x, y + 1):
				marks.append(Vector2i(x, y))
	for p in marks:
		image.set_pixelv(p, color)


## Body pixels whose four neighbours are body pixels too (for speckles on top).
func interior() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			if is_body(x, y) and is_body(x - 1, y) and is_body(x + 1, y) and is_body(x, y - 1) \
					and is_body(x, y + 1):
				result.append(Vector2i(x, y))
	return result


## Vertical trunk like the menu's: outline on the shaded left edge, lit to the right,
## a root flare at the foot. `top` is negative (above the origin).
func trunk(x0: float, top: float, bottom: float, half_width: float, colors: Array[Color],
		outline: Color, salt: int, flare: bool = true, lean: float = 0.0) -> void:
	for y in range(pixel(Vector2(0, top)).y, pixel(Vector2(0, bottom)).y + 1):
		var at := center_of(0, y).y
		var progress := clampf((bottom - at) / maxf(1.0, bottom - top), 0.0, 1.0)
		var cx := x0 + lean * progress * progress
		var extra := 0.0
		if flare and at > bottom - 3.0:
			extra += 1.0
		if flare and at > bottom - 1.0:
			extra += 1.0
		var left := pixel(Vector2(cx - half_width - extra, at)).x
		var right := pixel(Vector2(cx + half_width + extra, at)).x
		for x in range(left, right + 1):
			var u := float(x - left) / maxf(1.0, right - left)
			var level := 0.15 + u * 0.75 + grain(x, y, 0.3, salt) * 0.5
			put(x, y, outline if x == left else ramp(colors, level, x, y), level)


## The palette shifted a little towards `tint` (per-tree variety).
static func tinted(colors: Array[Color], tint: Color, amount: float) -> Array[Color]:
	var result: Array[Color] = []
	for color in colors:
		result.append(color.lerp(tint, amount))
	return result
