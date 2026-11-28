class_name NelvarEarthField
extends RefCounted
## What the ground shader needs to know about the valley floor, one pixel per art
## pixel of the world grid:
##   R — depth into a pond: 128 + art pixels (above 128 is water), 0 far from ponds;
##   G — distance from a trail's centre line in its half widths × 64, 255 far away;
##   B — shade of the groves: how deep under the crowns (forest floor);
##   A — unused (255).
## Built on a worker thread; texture() is made on the main thread.

const STEP := NelvarEarthData.PIXEL
## Ground kept round the valley so trails running into the mountains are covered.
const MARGIN := 64

## World texel of the image's top-left pixel.
var origin: Vector2i
var size: Vector2i
var data: PackedByteArray


static func build(earth: NelvarEarthData) -> NelvarEarthField:
	var field := NelvarEarthField.new()
	var bounds := Rect2(earth.boundary[0], Vector2.ZERO)
	for point in earth.boundary:
		bounds = bounds.expand(point)
	field.origin = Vector2i((bounds.position / STEP).floor()) - Vector2i.ONE * MARGIN
	field.size = Vector2i((bounds.size / STEP).ceil()) + Vector2i.ONE * MARGIN * 2
	# Defaults: no pond, no trail, no crowns.
	var blank := Image.create(field.size.x, field.size.y, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 1.0, 0.0, 1.0))
	field.data = blank.get_data()
	field._ponds(earth)
	field._trails(earth)
	field._groves(earth)
	return field


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(
		Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data))


## Pixel coordinates of a world point, or (-1, -1) outside the field.
func _pixel(point: Vector2) -> Vector2i:
	return Vector2i((point / STEP).floor()) - origin


func _world(x: int, y: int) -> Vector2:
	return (Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * STEP


func _ponds(earth: NelvarEarthData) -> void:
	for pond in earth.ponds:
		var reach := Vector2.ONE * (pond.reach() + 48.0)
		var from := _pixel(pond.center - reach).max(Vector2i.ZERO)
		var to := _pixel(pond.center + reach).min(size - Vector2i.ONE)
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var depth := pond.signed_distance(_world(x, y)) / STEP
				if depth < -40.0:
					continue
				var value := clampi(128 + roundi(depth), 0, 255)
				var index := (y * size.x + x) * 4
				data[index] = maxi(data[index], value)


func _trails(earth: NelvarEarthData) -> void:
	for trail in earth.trails:
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


## Under the crowns the grass is darker and strewn with leaves.
func _groves(earth: NelvarEarthData) -> void:
	for thing in earth.things:
		if thing.kind != NelvarEarthData.Kind.TREE:
			continue
		var center := thing.position + Vector2(-thing.size.x * 0.1, -thing.size.x * 0.12)
		var axes := Vector2(thing.size.x * 1.05, thing.size.x * 0.62)
		var from := _pixel(center - axes).max(Vector2i.ZERO)
		var to := _pixel(center + axes).min(size - Vector2i.ONE)
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var d := ((_world(x, y) - center) / axes).length_squared()
				if d >= 1.0:
					continue
				var index := (y * size.x + x) * 4 + 2
				data[index] = maxi(data[index], roundi((1.0 - d) * 255.0))
