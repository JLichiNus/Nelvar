class_name NelvarFireField
extends RefCounted
## What the ground shader needs to know about the basin, one pixel per art pixel of the
## world grid:
##   R — lava: 128 + art pixels into it (above 128 is lava), down to 128 - BAND near it,
##       0 further away;
##   G — off the lava: distance from a road's centre line in its half widths × 64, 255
##       far away; in the lava: the way it flows, an angle in 0..254, 255 for a still lake;
##   B — distance from a fissure's crack in sixteenths of an art pixel, 255 far away;
##   A — 0 bare ground, 1..100 sulfur round a vent, 101..200 a magma field (its joints
##       glow), 255 black plates (islands and crossings).
## And a coarse light map, one texel per GLOW_SCALE art pixels (the glow and the heat
## haze filter it):
##   R — the lava's light: full in it, falling off over GLOW_REACH;
##   G — the magma's light: fissures and magma fields;
##   B — unused, A — 255.
## Built on a worker thread; the textures are made on the main thread.

const STEP := NelvarFireData.PIXEL
## Ground kept round the basin, so roads into the ridges are covered.
const MARGIN := 64
## Art pixels of exact lava depth kept outside the lava.
const BAND := 24
const GLOW_SCALE := 8
## World units over which the lava's light fades.
const GLOW_REACH := 260.0
const STILL := 255
const PLATES := 255

var origin: Vector2i
var size: Vector2i
var data: PackedByteArray
## World art pixel of the light map's first texel corner, and its size.
var glow_origin: Vector2i
var glow_size: Vector2i
var glow: PackedByteArray


static func build(fire: NelvarFireData) -> NelvarFireField:
	var field := NelvarFireField.new()
	var bounds := Rect2(fire.boundary[0], Vector2.ZERO)
	for point in fire.boundary:
		bounds = bounds.expand(point)
	field.origin = Vector2i((bounds.position / STEP).floor()) - Vector2i.ONE * MARGIN
	field.size = Vector2i((bounds.size / STEP).ceil()) + Vector2i.ONE * MARGIN * 2
	var blank := Image.create(field.size.x, field.size.y, false, Image.FORMAT_RGBA8)
	# Defaults: no lava, no road, no fissure, bare ground.
	blank.fill(Color(0.0, 1.0, 1.0, 0.0))
	field.data = blank.get_data()
	field._flows(fire)
	field._lakes(fire)
	field._streams(fire)
	field._fissures(fire)
	field._deposits(fire)
	field._light(fire)
	return field


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(
		Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data))


func glow_texture() -> ImageTexture:
	return ImageTexture.create_from_image(
		Image.create_from_data(glow_size.x, glow_size.y, false, Image.FORMAT_RGBA8, glow))


func _pixel(point: Vector2) -> Vector2i:
	return Vector2i((point / STEP).floor()) - origin


func _world(x: int, y: int) -> Vector2:
	return (Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * STEP


func _box(from_world: Vector2, to_world: Vector2) -> Rect2i:
	var from := _pixel(from_world).max(Vector2i.ZERO)
	var to := _pixel(to_world).min(size - Vector2i.ONE)
	return Rect2i(from, to - from)


static func _depth_byte(depth_world: float) -> int:
	return clampi(128 + roundi(depth_world / STEP), 0, 255)


func _flows(fire: NelvarFireData) -> void:
	for flow in fire.flows:
		var reach := flow.half_width * 2.0
		for i in flow.points.size() - 1:
			var a := flow.points[i]
			var b := flow.points[i + 1]
			var box := _box(a.min(b) - Vector2.ONE * reach, a.max(b) + Vector2.ONE * reach)
			var along := b - a
			var length_squared := maxf(along.length_squared(), 0.0001)
			for y in range(box.position.y, box.end.y + 1):
				for x in range(box.position.x, box.end.x + 1):
					var point := _world(x, y)
					var t := clampf((point - a).dot(along) / length_squared, 0.0, 1.0)
					var value := roundi(point.distance_to(a + along * t) / flow.half_width * 64.0)
					if value > 254:
						continue
					var index := (y * size.x + x) * 4 + 1
					data[index] = mini(data[index], value)


## Lakes: their depth (islands cut out of it, lying on black plates).
func _lakes(fire: NelvarFireData) -> void:
	for lake in fire.lakes:
		var reach := Vector2.ONE * (lake.reach() + BAND * STEP)
		var box := _box(lake.center - reach, lake.center + reach)
		for y in range(box.position.y, box.end.y + 1):
			for x in range(box.position.x, box.end.x + 1):
				var depth := lake.signed_distance(_world(x, y))
				if depth < -BAND * STEP:
					continue
				var index := (y * size.x + x) * 4
				data[index] = maxi(data[index], _depth_byte(depth))
	for island in fire.islands:
		var reach := Vector2.ONE * (island.shape.reach() + BAND * STEP)
		var box := _box(island.shape.center - reach, island.shape.center + reach)
		for y in range(box.position.y, box.end.y + 1):
			for x in range(box.position.x, box.end.x + 1):
				var inside := island.shape.signed_distance(_world(x, y))
				if inside < -BAND * STEP:
					continue
				var index := (y * size.x + x) * 4
				data[index] = mini(data[index], _depth_byte(-inside))
				if inside > 0.0:
					data[index + 3] = PLATES


## Streams: the depth of their lava, the way it flows, and the plates of their crossings.
## Each pixel near a stream takes its nearest segment.
func _streams(fire: NelvarFireData) -> void:
	for stream in fire.streams:
		var reach := stream.half_width + BAND * STEP
		var nearest := {}
		for i in stream.points.size() - 1:
			var a := stream.points[i]
			var b := stream.points[i + 1]
			var box := _box(a.min(b) - Vector2.ONE * reach, a.max(b) + Vector2.ONE * reach)
			for y in range(box.position.y, box.end.y + 1):
				for x in range(box.position.x, box.end.x + 1):
					var point := _world(x, y)
					var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
					var distance := point.distance_to(closest)
					if distance > reach:
						continue
					var key := y * size.x + x
					var known: Variant = nearest.get(key)
					if known != null and (known as Vector3).x <= distance:
						continue
					nearest[key] = Vector3(distance, stream.lengths[i] + a.distance_to(closest), i)
		for key: int in nearest:
			var entry: Vector3 = nearest[key]
			var depth := stream.depth_at(entry.x, entry.y)
			var index := key * 4
			data[index] = maxi(data[index], _depth_byte(depth))
			if depth >= 0.0:
				var segment := int(entry.z)
				var angle := stream.points[segment].direction_to(stream.points[segment + 1]).angle()
				data[index + 1] = clampi(roundi(fposmod(angle, TAU) / TAU * 254.0), 0, 254)
			elif entry.x < stream.half_width + STEP:
				for crossing in stream.crossings:
					if absf(entry.y - crossing.along) < crossing.half_length:
						data[index + 3] = PLATES


func _fissures(fire: NelvarFireData) -> void:
	var reach := 16.0 * STEP
	for fissure in fire.fissures:
		for i in fissure.points.size() - 1:
			var a := fissure.points[i]
			var b := fissure.points[i + 1]
			var box := _box(a.min(b) - Vector2.ONE * reach, a.max(b) + Vector2.ONE * reach)
			for y in range(box.position.y, box.end.y + 1):
				for x in range(box.position.x, box.end.x + 1):
					var point := _world(x, y)
					var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))
					var value := roundi(distance / STEP * 16.0)
					if value > 254:
						continue
					var index := (y * size.x + x) * 4 + 2
					data[index] = mini(data[index], value)


## Sulfur round the vents; magma fields.
func _deposits(fire: NelvarFireData) -> void:
	for thing in fire.things:
		if thing.kind != NelvarFireData.Kind.VENT:
			continue
		var radius := thing.radius * (3.4 if thing.accent else 2.8)
		var box := _box(thing.position - Vector2.ONE * radius, thing.position + Vector2.ONE * radius)
		for y in range(box.position.y, box.end.y + 1):
			for x in range(box.position.x, box.end.x + 1):
				var d := (_world(x, y) - thing.position).length() / radius
				if d >= 1.0:
					continue
				var index := (y * size.x + x) * 4 + 3
				if data[index] <= 100:
					data[index] = maxi(data[index], roundi((1.0 - d) * 100.0))
	for field in fire.magma_fields:
		var center := Vector2(field.x, field.y)
		var box := _box(center - Vector2.ONE * field.z, center + Vector2.ONE * field.z)
		for y in range(box.position.y, box.end.y + 1):
			for x in range(box.position.x, box.end.x + 1):
				var d := (_world(x, y) - center).length() / field.z
				if d >= 1.0:
					continue
				var index := (y * size.x + x) * 4 + 3
				if data[index] == 0 or (data[index] > 100 and data[index] < PLATES):
					data[index] = maxi(data[index], 101 + roundi((1.0 - d) * 99.0))


## The coarse light map: how much the lava and the magma light the ground round them.
func _light(fire: NelvarFireData) -> void:
	glow_origin = Vector2i((Vector2(origin) / GLOW_SCALE).floor()) * GLOW_SCALE
	glow_size = Vector2i((Vector2(size) / GLOW_SCALE).ceil()) + Vector2i.ONE * 2
	glow = PackedByteArray()
	glow.resize(glow_size.x * glow_size.y * 4)
	for y in glow_size.y:
		for x in glow_size.x:
			var point := (Vector2(glow_origin) + (Vector2(x, y) + Vector2(0.5, 0.5)) * GLOW_SCALE) * STEP
			var index := (y * glow_size.x + x) * 4
			glow[index + 3] = 255
			if fire.basin.signed_distance(point) < -GLOW_REACH * 2.0:
				continue
			var depth := fire.lava_depth(point)
			var lava := 1.0 if depth >= 0.0 else pow(1.0 - clampf(-depth / GLOW_REACH, 0.0, 1.0), 2.0)
			glow[index] = roundi(lava * 255.0)
			var magma := 0.0
			var crack := fire.fissure_distance(point)
			if crack < 120.0:
				magma = pow(1.0 - crack / 120.0, 2.0) * 0.8
			for field in fire.magma_fields:
				var d := point.distance_to(Vector2(field.x, field.y)) / (field.z * 1.2)
				if d < 1.0:
					magma = maxf(magma, (1.0 - d) * 0.55)
			glow[index + 1] = roundi(clampf(magma, 0.0, 1.0) * 255.0)
