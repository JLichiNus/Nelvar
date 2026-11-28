class_name NelvarMountainField
extends RefCounted
## What the ground shader needs to know about the mountains, one texel per SCALE art
## pixels of the world grid (the shader filters it and dithers the edges per pixel):
##   R — the foot of the range: how far under the bases of the peaks the ground lies.
##       The shader lays scree, dark firs and shade there, so the peaks rise out of one
##       rocky, wooded massif instead of standing on the meadow one by one;
##   G — the shadows the peaks cast on the ground, down and to the left, away from the
##       sun of the menu art. Each shadow is the peak's own relief (NelvarEarthArt.relief)
##       laid down on the ground and slanted, the way sprite games cast shadows;
##   B — unused (0), A — 255.
## Built on a worker thread once every peak is painted; texture() is made on the main
## thread.

const STEP := NelvarEarthData.PIXEL
const SCALE := 4
## Ground shift of a cast shadow per art pixel of a peak's height.
const SHADOW := Vector2(-0.42, 0.38)
const MARGIN := 4
const Peak = NelvarEarthData.Peak

## World art pixel of the first texel's top-left corner.
var origin: Vector2i
var size: Vector2i
var data: PackedByteArray


## `arts[i]` is the painted art of `peaks[i]`; peaks without relief (boulders) are left
## out.
static func build(peaks: Array[NelvarEarthData.Thing], arts: Array) -> NelvarMountainField:
	var field := NelvarMountainField.new()
	var bounds := Rect2()
	var first := true
	for i in peaks.size():
		var art: NelvarEarthArt = arts[i]
		if art == null or art.relief.is_empty():
			continue
		var area := _area(peaks[i], art)
		bounds = area if first else bounds.merge(area)
		first = false
	if first:
		bounds = Rect2(0, 0, SCALE, SCALE)
	field.origin = Vector2i((bounds.position / SCALE).floor()) * SCALE - Vector2i.ONE * MARGIN * SCALE
	field.size = Vector2i(((bounds.end - Vector2(field.origin)) / SCALE).ceil()) + Vector2i.ONE * MARGIN
	field.data = PackedByteArray()
	field.data.resize(field.size.x * field.size.y * 4)
	for i in field.size.x * field.size.y:
		field.data[i * 4 + 3] = 255
	for i in peaks.size():
		var art: NelvarEarthArt = arts[i]
		if art == null or art.relief.is_empty():
			continue
		field._foot(peaks[i])
		field._shadow(peaks[i], art)
	return field


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(
		Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data))


## Half-width and half-depth of a peak's base, art pixels (as NelvarMountainPainter).
static func base_of(peak: NelvarEarthData.Thing) -> Vector2:
	var half := peak.size.x / STEP * 0.5
	return Vector2(half, half * NelvarMountainPainter.DEPTH)


## Everything a peak touches on the ground, world art pixels.
static func _area(peak: NelvarEarthData.Thing, art: NelvarEarthArt) -> Rect2:
	var at := peak.position / STEP
	var base := base_of(peak)
	var tallest := 0.0
	for value in art.relief:
		tallest = maxf(tallest, value)
	var foot := Rect2(at + Vector2(-base.x, -base.y) - _foot_axes(base),
		_foot_axes(base) * 2.0)
	var shadow := Rect2(at + Vector2(art.local_rect.position.x / STEP + SHADOW.x * tallest, -base.y),
		Vector2(art.relief.size() - SHADOW.x * tallest, SHADOW.y * tallest))
	return foot.merge(shadow)


static func _foot_axes(base: Vector2) -> Vector2:
	return Vector2(base.x * 1.3, base.y * 1.9)


## World art pixel at the centre of a texel.
func _center(x: int, y: int) -> Vector2:
	return Vector2(origin) + (Vector2(x, y) + Vector2(0.5, 0.5)) * SCALE


func _texel(point: Vector2) -> Vector2i:
	return Vector2i(((point - Vector2(origin)) / SCALE).floor())


## The rocky, wooded foot round the base: deepest under the peak, fading outwards.
## Crags on the uplands get a lighter one.
func _foot(peak: NelvarEarthData.Thing) -> void:
	var base := base_of(peak)
	var center := peak.position / STEP + Vector2(0.0, -base.y)
	var axes := _foot_axes(base)
	var strength := 0.75 if peak.variant == Peak.CRAG else 1.0
	var from := _texel(center - axes).max(Vector2i.ZERO)
	var to := _texel(center + axes).min(size - Vector2i.ONE)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var d := ((_center(x, y) - center) / axes).length()
			if d >= 1.0:
				continue
			var value := roundi((1.0 - smoothstep(0.5, 1.0, d)) * strength * 255.0)
			var index := (y * size.x + x) * 4
			data[index] = maxi(data[index], value)


## The peak's relief laid on the ground from the middle of its base and slanted away
## from the sun: a column `h` pixels high shades the ground up to `h` steps of SHADOW
## from its foot. Full near the peak, fading towards the tip of the shadow.
func _shadow(peak: NelvarEarthData.Thing, art: NelvarEarthArt) -> void:
	var base := base_of(peak)
	var at := peak.position / STEP
	var left := at.x + art.local_rect.position.x / STEP
	var line := at.y - base.y
	var area := _area(peak, art)
	var from := _texel(area.position).max(Vector2i.ZERO)
	var to := _texel(area.end).min(size - Vector2i.ONE)
	var columns: int = art.relief.size()
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var point := _center(x, y)
			var t := (point.y - line) / SHADOW.y
			if t < 0.0:
				continue
			var column := int(floor(point.x - t * SHADOW.x - left))
			if column < 0 or column >= columns:
				continue
			var high: float = art.relief[column]
			if t >= high:
				continue
			var value := roundi(clampf((high - t) / maxf(3.0, high * 0.35), 0.0, 1.0) * 255.0)
			var index := (y * size.x + x) * 4 + 1
			data[index] = maxi(data[index], value)
