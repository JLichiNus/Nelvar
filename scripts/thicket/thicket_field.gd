class_name NelvarThicketField
extends RefCounted
## What the giant forest's floor shader needs to know, one pixel per art pixel:
##   R — depth into a pond: 128 + art pixels (above 128 is water), 0 far from ponds;
##   G — distance from a trail's centre line in its half widths × 64, 255 far away;
##   B — shade cast by the roots (south-west of a high root, under an arch);
##   A — churned soil along the roots' flanks (255 at the flank).
## And a coarse light map, one texel per LIGHT_SCALE art pixels (as the forge's glow):
##   R — sun through the crowns (NelvarThicketData.sun_at);
##   G — damp (damp_at);
##   B — loose earth, a signed distance: 128 + world units / 2 (above 128 is loose);
##   A — resin, the same way (resin_depth).
## The logic asks the same queries; the test checks the map against them.
## Built in bands of rows on worker threads (start(), build_band() for each band, finish());
## the textures are made on the main thread.

const STEP := NelvarEarthData.PIXEL
const LIGHT_SCALE := 4
## Ground kept round the floor so the ring's foot is covered.
const MARGIN := 96
## The way roots' shadows fall (the sun is up and to the right).
const SHADOW_DIRECTION := Vector2(-0.55, 0.83)


## Rows of both maps built on one thread, each map's in its own bytes: art pixel rows
## first..last of the floor's map, light_first..light_last of the light map.
class Band:
	var first := 0
	var last := -1
	var data := PackedByteArray()
	var light_first := 0
	var light_last := -1
	var light := PackedByteArray()
	var near := PackedByteArray()


var origin: Vector2i
var size: Vector2i
var data: PackedByteArray
var light_origin: Vector2i
var light_size: Vector2i
var light: PackedByteArray
var _bands: Array[Band] = []


## On one thread.
static func build(thicket: NelvarThicketData) -> NelvarThicketField:
	var field := start(thicket, 1)
	field.build_band(thicket, 0)
	field.finish()
	return field


## The maps' bounds, cut into `bands` bands of rows to build.
static func start(thicket: NelvarThicketData, bands: int) -> NelvarThicketField:
	var field := NelvarThicketField.new()
	var bounds := Rect2(thicket.boundary[0], Vector2.ZERO)
	for point in thicket.boundary:
		bounds = bounds.expand(point)
	field.origin = Vector2i((bounds.position / STEP).floor()) - Vector2i.ONE * MARGIN
	field.size = Vector2i((bounds.size / STEP).ceil()) + Vector2i.ONE * MARGIN * 2
	field.light_origin = Vector2i((Vector2(field.origin) / LIGHT_SCALE).floor())
	field.light_size = Vector2i((Vector2(field.size) / LIGHT_SCALE).ceil()) + Vector2i.ONE
	var count := clampi(bands, 1, field.size.y)
	for i in count:
		var band := Band.new()
		band.first = field.size.y * i / count
		band.last = field.size.y * (i + 1) / count - 1
		band.light_first = field.light_size.y * i / count
		band.light_last = field.light_size.y * (i + 1) / count - 1
		field._bands.append(band)
	return field


func band_count() -> int:
	return _bands.size()


## Builds one band; the bands build on any threads at once.
func build_band(thicket: NelvarThicketData, index: int) -> void:
	var band := _bands[index]
	var blank := Image.create(size.x, band.last - band.first + 1, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 1.0, 0.0, 0.0))
	var bytes := blank.get_data()
	blank = null
	_ponds(thicket, band, bytes)
	_trails(thicket, band, bytes)
	_roots(thicket, band, bytes)
	band.data = bytes
	_light(thicket, band)


## Lays the built bands together.
func finish() -> void:
	data = PackedByteArray()
	light = PackedByteArray()
	for band in _bands:
		data.append_array(band.data)
		light.append_array(band.light)
	_bands.clear()


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data))


func light_texture() -> ImageTexture:
	return ImageTexture.create_from_image(
		Image.create_from_data(light_size.x, light_size.y, false, Image.FORMAT_RGBA8, light))


func _pixel(point: Vector2) -> Vector2i:
	return Vector2i((point / STEP).floor()) - origin


## The rows of the band within from.y..to.y, and the clipped columns.
func _clip(band: Band, from: Vector2i, to: Vector2i) -> Array:
	return [Vector2i(from.x, maxi(from.y, band.first)), Vector2i(to.x, mini(to.y, band.last))]


## (The loops read only locals and work out each art pixel's middle in place: in the editor's
## build each call and each read of another object's property takes a lock all threads share.)
func _ponds(thicket: NelvarThicketData, band: Band, bytes: PackedByteArray) -> void:
	var first := band.first
	for pond in thicket.ponds:
		var reach := Vector2.ONE * (pond.reach() + 48.0)
		var span := _clip(band, _pixel(pond.center - reach).max(Vector2i.ZERO), _pixel(pond.center + reach).min(size - Vector2i.ONE))
		for y in range(span[0].y, span[1].y + 1):
			for x in range(span[0].x, span[1].x + 1):
				var depth := pond.signed_distance((Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * STEP) / STEP
				if depth < -40.0:
					continue
				var index := ((y - first) * size.x + x) * 4
				bytes[index] = maxi(bytes[index], clampi(128 + roundi(depth), 0, 255))


func _trails(thicket: NelvarThicketData, band: Band, bytes: PackedByteArray) -> void:
	var first := band.first
	for trail in thicket.trails:
		var half_width := trail.half_width
		var reach := half_width * 2.0
		for i in trail.points.size() - 1:
			var a := trail.points[i]
			var b := trail.points[i + 1]
			var span := _clip(band, _pixel(a.min(b) - Vector2.ONE * reach).max(Vector2i.ZERO),
				_pixel(a.max(b) + Vector2.ONE * reach).min(size - Vector2i.ONE))
			var along := b - a
			var length_squared := maxf(along.length_squared(), 0.0001)
			for y in range(span[0].y, span[1].y + 1):
				for x in range(span[0].x, span[1].x + 1):
					var point := (Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * STEP
					var t := clampf((point - a).dot(along) / length_squared, 0.0, 1.0)
					var value := roundi(point.distance_to(a + along * t) / half_width * 64.0)
					if value > 254:
						continue
					var index := ((y - first) * size.x + x) * 4 + 1
					bytes[index] = mini(bytes[index], value)


## The roots' shade and the churned soil along them.
func _roots(thicket: NelvarThicketData, band: Band, bytes: PackedByteArray) -> void:
	var first := band.first
	for root in thicket.roots:
		for i in root.points.size() - 1:
			var part := root.parts[i]
			if part == NelvarThicketData.Part.PASS:
				continue
			var a := root.points[i]
			var b := root.points[i + 1]
			var half := maxf(root.widths[i], root.widths[i + 1]) * 0.5
			var height := maxf(root.heights[i], root.heights[i + 1]) * STEP
			var shift := SHADOW_DIRECTION * height * 0.55
			var casts := part == NelvarThicketData.Part.HIGH or part == NelvarThicketData.Part.ARCH
			var arch := part == NelvarThicketData.Part.ARCH
			var shade := 190 if part == NelvarThicketData.Part.HIGH else 150
			var reach := half + 30.0 + (shift.length() if casts else 0.0)
			var span := _clip(band, _pixel(a.min(b) - Vector2.ONE * reach).max(Vector2i.ZERO),
				_pixel(a.max(b) + Vector2.ONE * reach).min(size - Vector2i.ONE))
			var along := b - a
			var length_squared := maxf(along.length_squared(), 0.0001)
			for y in range(span[0].y, span[1].y + 1):
				for x in range(span[0].x, span[1].x + 1):
					var point := (Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * STEP
					var t := clampf((point - a).dot(along) / length_squared, 0.0, 1.0)
					var distance := point.distance_to(a + along * t) - half
					var index := ((y - first) * size.x + x) * 4
					if distance < 30.0:
						bytes[index + 3] = maxi(bytes[index + 3], roundi(clampf(1.0 - distance / 30.0, 0.0, 1.0) * 255.0))
					if casts:
						var shaded := point - shift
						var ts := clampf((shaded - a).dot(along) / length_squared, 0.0, 1.0)
						var inside := shaded.distance_to(a + along * ts) - half
						if inside < 0.0 or (arch and distance < 0.0):
							bytes[index + 2] = maxi(bytes[index + 2], shade)


## The coarse light map: each channel is the query at the texel's middle, near the things
## that make it (zero, or the far value, elsewhere).
func _light(thicket: NelvarThicketData, band: Band) -> void:
	var rows := band.light_last - band.light_first + 1
	if rows <= 0:
		return
	var bytes := PackedByteArray()
	bytes.resize(light_size.x * rows * 4)
	var near := PackedByteArray()
	near.resize(light_size.x * rows)
	var cell := float(STEP * LIGHT_SCALE)
	for clearing in thicket.clearings:
		_mark(band, near, clearing.center, clearing.radius + NelvarThicketData.SUN_EDGE + cell, 1)
	for window in thicket.windows:
		_mark(band, near, Vector2(window.x, window.y), window.z + NelvarThicketData.SUN_EDGE + cell, 1)
	for pond in thicket.ponds:
		_mark(band, near, pond.center, pond.reach() + NelvarThicketData.DAMP_POND + cell, 2)
	for giant in thicket.giants:
		_mark(band, near, giant.center, giant.radius + NelvarThicketData.DAMP_TRUNK + cell, 2)
	for puffball in thicket.puffballs:
		_mark(band, near, puffball.center, puffball.radius + NelvarThicketData.DAMP_SPOT + cell, 2)
	if thicket.fallen != null:
		var fallen := thicket.fallen
		_mark(band, near, fallen.start.lerp(fallen.end, 0.5), fallen.length() * 0.5 + fallen.radius + fallen.plate_half
			+ NelvarThicketData.DAMP_SPOT + 300.0, 2)
	for patch in thicket.loose:
		_mark(band, near, patch.center, patch.reach() + 300.0, 4)
	for pool in thicket.resin:
		_mark(band, near, pool.center, pool.radius + 300.0, 8)
	for row in rows:
		var y := band.light_first + row
		for x in light_size.x:
			var flags := near[row * light_size.x + x]
			var point := (Vector2(light_origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * cell
			var index := (row * light_size.x + x) * 4
			bytes[index] = roundi(thicket.sun_at(point) * 255.0) if flags & 1 else 0
			bytes[index + 1] = roundi(thicket.damp_at(point) * 255.0) if flags & 2 else 0
			bytes[index + 2] = encode_depth(thicket.loose_depth(point)) if flags & 4 else 0
			bytes[index + 3] = encode_depth(thicket.resin_depth(point)) if flags & 8 else 0
	band.light = bytes


func _mark(band: Band, near: PackedByteArray, center: Vector2, reach: float, bit: int) -> void:
	var cell := float(STEP * LIGHT_SCALE)
	var from := (Vector2i(((center - Vector2.ONE * reach) / cell).floor()) - light_origin).max(Vector2i.ZERO)
	var to := (Vector2i(((center + Vector2.ONE * reach) / cell).floor()) - light_origin).min(light_size - Vector2i.ONE)
	for y in range(maxi(from.y, band.light_first), mini(to.y, band.light_last) + 1):
		for x in range(from.x, to.x + 1):
			near[(y - band.light_first) * light_size.x + x] |= bit


## A signed distance (world units) as a byte: 128 at the edge, 2 units a step.
static func encode_depth(depth: float) -> int:
	if not is_finite(depth):
		return 0
	return clampi(128 + roundi(depth * 0.5), 0, 255)


## The light map's texel holding the world point (for the tests).
func light_texel(point: Vector2) -> Vector2i:
	return Vector2i((point / (STEP * LIGHT_SCALE)).floor()) - light_origin


func light_at(texel: Vector2i) -> Color:
	var index := (texel.y * light_size.x + texel.x) * 4
	return Color8(light[index], light[index + 1], light[index + 2], light[index + 3])
