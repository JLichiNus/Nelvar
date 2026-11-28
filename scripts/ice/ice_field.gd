class_name NelvarIceField
extends RefCounted
## What the ground shader needs to know about the valley floor, one pixel per art pixel
## of the world grid:
##   R — lake: 128 + art pixels into its ice (above 128 is ice), down to 128 - BAND by
##       its shore, 0 further away;
##   G — distance from a trail's centre line in its half widths × 64, 255 far away;
##   B — crevasse: 128 + art pixels into the crack (above 128 is the crack, bridges
##       ignored), down to 128 - BAND by its edge, 0 further away;
##   A — 0 plain snow or ice, 1..100 thin ice (how far inside the patch), 101..200
##       wind-blown snow (how deep), 255 a snow bridge's deck.
## Built on a worker thread; texture() is made on the main thread.

const STEP := NelvarIceData.PIXEL
## Ground kept round the valley so trails running into the mountains are covered.
const MARGIN := 64
## Art pixels of exact depth kept outside the lakes and the crevasses.
const BAND := 24
const BRIDGE := 255
const THIN_MAX := 100
const BANK_FROM := 101

## World texel of the image's top-left pixel.
var origin: Vector2i
var size: Vector2i
var data: PackedByteArray


static func build(ice: NelvarIceData) -> NelvarIceField:
	var field := NelvarIceField.new()
	var bounds := Rect2(ice.boundary[0], Vector2.ZERO)
	for point in ice.boundary:
		bounds = bounds.expand(point)
	field.origin = Vector2i((bounds.position / STEP).floor()) - Vector2i.ONE * MARGIN
	field.size = Vector2i((bounds.size / STEP).ceil()) + Vector2i.ONE * MARGIN * 2
	# Defaults: no lake, no trail, no crevasse, plain ground.
	var blank := Image.create(field.size.x, field.size.y, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 1.0, 0.0, 0.0))
	field.data = blank.get_data()
	field._lakes(ice)
	field._trails(ice)
	field._banks(ice)
	field._crevasses(ice)
	return field


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(
		Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data))


## Pixel coordinates of a world point.
func _pixel(point: Vector2) -> Vector2i:
	return Vector2i((point / STEP).floor()) - origin


func _world(x: int, y: int) -> Vector2:
	return (Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * STEP


func _lakes(ice: NelvarIceData) -> void:
	for lake in ice.lakes:
		var shape := lake.shape
		var reach := Vector2.ONE * (shape.reach() + BAND * STEP + 8.0)
		var from := _pixel(shape.center - reach).max(Vector2i.ZERO)
		var to := _pixel(shape.center + reach).min(size - Vector2i.ONE)
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var depth := shape.signed_distance(_world(x, y)) / STEP
				if depth < -BAND:
					continue
				var index := (y * size.x + x) * 4
				data[index] = maxi(data[index], clampi(128 + roundi(depth), 0, 255))
		# Thin ice: the deeper inside its patch, the thinner (darker, clearer).
		for patch in lake.thin:
			var patch_reach := Vector2.ONE * (patch.reach() + 8.0)
			var patch_from := _pixel(patch.center - patch_reach).max(Vector2i.ZERO)
			var patch_to := _pixel(patch.center + patch_reach).min(size - Vector2i.ONE)
			for y in range(patch_from.y, patch_to.y + 1):
				for x in range(patch_from.x, patch_to.x + 1):
					var depth := patch.signed_distance(_world(x, y)) / STEP
					if depth < 0.0:
						continue
					var index := (y * size.x + x) * 4 + 3
					data[index] = maxi(data[index], clampi(1 + roundi(depth * 8.0), 1, THIN_MAX))


func _trails(ice: NelvarIceData) -> void:
	for trail in ice.trails:
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


## Wind-blown snow: deepest in the middle of a field, never on the ice.
func _banks(ice: NelvarIceData) -> void:
	for bank in ice.snow_banks:
		var center := Vector2(bank.x, bank.y)
		var reach := Vector2.ONE * bank.z
		var from := _pixel(center - reach).max(Vector2i.ZERO)
		var to := _pixel(center + reach).min(size - Vector2i.ONE)
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var index := (y * size.x + x) * 4
				if data[index] >= 128 - 4 or data[index + 3] != 0:
					continue
				var d := (_world(x, y) - center).length_squared() / (bank.z * bank.z)
				if d >= 1.0:
					continue
				data[index + 3] = BANK_FROM + roundi((1.0 - d) * 99.0)


## Each crevasse by its nearest segment, as NelvarIceData.crevasse_sample: the crack's
## depth without the bridges in B, the bridges' decks in A.
func _crevasses(ice: NelvarIceData) -> void:
	for crevasse in ice.crevasses:
		var grow := crevasse.widest() + BAND * STEP + 8.0
		var low := crevasse.points[0]
		var high := crevasse.points[0]
		for point in crevasse.points:
			low = low.min(point)
			high = high.max(point)
		var from := _pixel(low - Vector2.ONE * grow).max(Vector2i.ZERO)
		var to := _pixel(high + Vector2.ONE * grow).min(size - Vector2i.ONE)
		var w := to.x - from.x + 1
		var h := to.y - from.y + 1
		if w <= 0 or h <= 0:
			continue
		var nearest := PackedFloat32Array()
		nearest.resize(w * h)
		nearest.fill(INF)
		var alongs := PackedFloat32Array()
		alongs.resize(w * h)
		for i in crevasse.points.size() - 1:
			var a := crevasse.points[i]
			var b := crevasse.points[i + 1]
			var reach := maxf(crevasse.half_widths[i], crevasse.half_widths[i + 1]) + BAND * STEP + 8.0
			var seg_from := (_pixel(a.min(b) - Vector2.ONE * reach) - from).max(Vector2i.ZERO)
			var seg_to := (_pixel(a.max(b) + Vector2.ONE * reach) - from).min(Vector2i(w - 1, h - 1))
			var span := b - a
			var length_squared := maxf(span.length_squared(), 0.0001)
			for y in range(seg_from.y, seg_to.y + 1):
				for x in range(seg_from.x, seg_to.x + 1):
					var point := _world(from.x + x, from.y + y)
					var t := clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
					var distance := point.distance_to(a + span * t)
					var k := y * w + x
					if distance < nearest[k]:
						nearest[k] = distance
						alongs[k] = crevasse.lengths[i] + sqrt(length_squared) * t
		for y in h:
			for x in w:
				var k := y * w + x
				if nearest[k] == INF:
					continue
				var raw := crevasse.raw_depth(nearest[k], alongs[k]) / STEP
				if raw < -BAND:
					continue
				var index := ((from.y + y) * size.x + from.x + x) * 4
				data[index + 2] = maxi(data[index + 2], clampi(128 + roundi(raw), 0, 255))
				if raw > -1.5 and crevasse.depth_at(nearest[k], alongs[k]) < 0.0:
					data[index + 3] = BRIDGE
