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
## Built on a worker thread; the textures are made on the main thread.

const STEP := NelvarEarthData.PIXEL
const LIGHT_SCALE := 4
## Ground kept round the floor so the ring's foot is covered.
const MARGIN := 96
## The way roots' shadows fall (the sun is up and to the right).
const SHADOW_DIRECTION := Vector2(-0.55, 0.83)

var origin: Vector2i
var size: Vector2i
var data: PackedByteArray
var light_origin: Vector2i
var light_size: Vector2i
var light: PackedByteArray
var _near := PackedByteArray()


static func build(thicket: NelvarThicketData) -> NelvarThicketField:
	var field := NelvarThicketField.new()
	var bounds := Rect2(thicket.boundary[0], Vector2.ZERO)
	for point in thicket.boundary:
		bounds = bounds.expand(point)
	field.origin = Vector2i((bounds.position / STEP).floor()) - Vector2i.ONE * MARGIN
	field.size = Vector2i((bounds.size / STEP).ceil()) + Vector2i.ONE * MARGIN * 2
	var blank := Image.create(field.size.x, field.size.y, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 1.0, 0.0, 0.0))
	field.data = blank.get_data()
	field._ponds(thicket)
	field._trails(thicket)
	field._roots(thicket)
	field._light(thicket)
	return field


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data))


func light_texture() -> ImageTexture:
	return ImageTexture.create_from_image(
		Image.create_from_data(light_size.x, light_size.y, false, Image.FORMAT_RGBA8, light))


func _pixel(point: Vector2) -> Vector2i:
	return Vector2i((point / STEP).floor()) - origin


func _world(x: int, y: int) -> Vector2:
	return (Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * STEP


func _ponds(thicket: NelvarThicketData) -> void:
	for pond in thicket.ponds:
		var reach := Vector2.ONE * (pond.reach() + 48.0)
		var from := _pixel(pond.center - reach).max(Vector2i.ZERO)
		var to := _pixel(pond.center + reach).min(size - Vector2i.ONE)
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var depth := pond.signed_distance(_world(x, y)) / STEP
				if depth < -40.0:
					continue
				var index := (y * size.x + x) * 4
				data[index] = maxi(data[index], clampi(128 + roundi(depth), 0, 255))


func _trails(thicket: NelvarThicketData) -> void:
	for trail in thicket.trails:
		var reach := trail.half_width * 2.0
		for i in trail.points.size() - 1:
			var a := trail.points[i]
			var b := trail.points[i + 1]
			var from := _pixel(a.min(b) - Vector2.ONE * reach).max(Vector2i.ZERO)
			var to := _pixel(a.max(b) + Vector2.ONE * reach).min(size - Vector2i.ONE)
			var along := b - a
			var length_squared := maxf(along.length_squared(), 0.0001)
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var point := _world(x, y)
					var t := clampf((point - a).dot(along) / length_squared, 0.0, 1.0)
					var value := roundi(point.distance_to(a + along * t) / trail.half_width * 64.0)
					if value > 254:
						continue
					var index := (y * size.x + x) * 4 + 1
					data[index] = mini(data[index], value)


## The roots' shade and the churned soil along them.
func _roots(thicket: NelvarThicketData) -> void:
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
			var reach := half + 30.0 + (shift.length() if casts else 0.0)
			var from := _pixel(a.min(b) - Vector2.ONE * reach).max(Vector2i.ZERO)
			var to := _pixel(a.max(b) + Vector2.ONE * reach).min(size - Vector2i.ONE)
			var along := b - a
			var length_squared := maxf(along.length_squared(), 0.0001)
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var point := _world(x, y)
					var t := clampf((point - a).dot(along) / length_squared, 0.0, 1.0)
					var distance := point.distance_to(a + along * t) - half
					var index := (y * size.x + x) * 4
					if distance < 30.0:
						data[index + 3] = maxi(data[index + 3], roundi(clampf(1.0 - distance / 30.0, 0.0, 1.0) * 255.0))
					if casts:
						var shaded := point - shift
						var ts := clampf((shaded - a).dot(along) / length_squared, 0.0, 1.0)
						var inside := shaded.distance_to(a + along * ts) - half
						if inside < 0.0 or (part == NelvarThicketData.Part.ARCH and distance < 0.0):
							data[index + 2] = maxi(data[index + 2], 190 if part == NelvarThicketData.Part.HIGH else 150)


## The coarse light map: each channel is the query at the texel's middle, near the things
## that make it (zero, or the far value, elsewhere).
func _light(thicket: NelvarThicketData) -> void:
	light_origin = Vector2i((Vector2(origin) / LIGHT_SCALE).floor())
	light_size = Vector2i((Vector2(size) / LIGHT_SCALE).ceil()) + Vector2i.ONE
	light.resize(light_size.x * light_size.y * 4)
	_near.resize(light_size.x * light_size.y)
	var cell := float(STEP * LIGHT_SCALE)
	for clearing in thicket.clearings:
		_mark(clearing.center, clearing.radius + NelvarThicketData.SUN_EDGE + cell, 1)
	for window in thicket.windows:
		_mark(Vector2(window.x, window.y), window.z + NelvarThicketData.SUN_EDGE + cell, 1)
	for pond in thicket.ponds:
		_mark(pond.center, pond.reach() + NelvarThicketData.DAMP_POND + cell, 2)
	for giant in thicket.giants:
		_mark(giant.center, giant.radius + NelvarThicketData.DAMP_TRUNK + cell, 2)
	for puffball in thicket.puffballs:
		_mark(puffball.center, puffball.radius + NelvarThicketData.DAMP_SPOT + cell, 2)
	if thicket.fallen != null:
		var fallen := thicket.fallen
		_mark(fallen.start.lerp(fallen.end, 0.5), fallen.length() * 0.5 + fallen.radius + fallen.plate_half
			+ NelvarThicketData.DAMP_SPOT + 300.0, 2)
	for patch in thicket.loose:
		_mark(patch.center, patch.reach() + 300.0, 4)
	for pool in thicket.resin:
		_mark(pool.center, pool.radius + 300.0, 8)
	for y in light_size.y:
		for x in light_size.x:
			var flags := _near[y * light_size.x + x]
			var point := (Vector2(light_origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * cell
			var index := (y * light_size.x + x) * 4
			light[index] = roundi(thicket.sun_at(point) * 255.0) if flags & 1 else 0
			light[index + 1] = roundi(thicket.damp_at(point) * 255.0) if flags & 2 else 0
			light[index + 2] = encode_depth(thicket.loose_depth(point)) if flags & 4 else 0
			light[index + 3] = encode_depth(thicket.resin_depth(point)) if flags & 8 else 0


func _mark(center: Vector2, reach: float, bit: int) -> void:
	var cell := float(STEP * LIGHT_SCALE)
	var from := (Vector2i(((center - Vector2.ONE * reach) / cell).floor()) - light_origin).max(Vector2i.ZERO)
	var to := (Vector2i(((center + Vector2.ONE * reach) / cell).floor()) - light_origin).min(light_size - Vector2i.ONE)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			_near[y * light_size.x + x] |= bit


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
