class_name NelvarCaveField
extends RefCounted
## What the cave's shaders need to know about the floor, one pixel per art pixel:
##   field — the layout NelvarIceField uses for the valley, so ice_common.gdshaderinc
##   draws the lakes, the crevasses and the bridges as they are there:
##     R  lake: 128 + art pixels into it (any kind), down to 128 - BAND by its shore;
##     G  the lake's kind (Pool, bits 0–1), smooth ice of an icy passage (bit 2), snow
##        (bits 3–7: 0 none, 1..31 deeper and deeper);
##     B  crevasse: 128 + art pixels into the crack (bridges ignored), as R;
##     A  1..100 thin ice (how far inside the patch), 255 a snow bridge's deck;
##   zone —
##     R  chasm: 128 + art pixels into it (arches ignored), as above;
##     G  255 on an arch's deck;
##     B  open water: 128 + art pixels in from its melting rim.
## And a coarse light map, one texel per LIGHT_SCALE art pixels (the light overlays and
## the floor's frost and warmth): R the sun, G the cold glow of the crystals and of the
## ice by the sun, B the geysers' warmth, A the cold of the big halls.
## The walls are the data's distance field itself (sdf_texture()).
## Built on a worker thread; the textures are made on the main thread.

const STEP := NelvarIceData.PIXEL
const BAND := 24
const THIN_MAX := 100
const BRIDGE := 255
const ARCH := 255
const LIGHT_SCALE := 4
## The ice glows this far from a sunny spot.
const SUN_GLOW := 240.0

## Art pixel of the first texel.
var origin: Vector2i
var size: Vector2i
var field := PackedByteArray()
var zone := PackedByteArray()
var light_origin: Vector2i
var light_size: Vector2i
var light := PackedByteArray()
var _cave: NelvarCaveData
var _snow_boxes: Array[Rect2i] = []
var _glows := PackedFloat32Array()


static func build(cave: NelvarCaveData) -> NelvarCaveField:
	var built := NelvarCaveField.new()
	built._cave = cave
	built.origin = Vector2i((cave.bounds.position / STEP).floor())
	built.size = Vector2i((cave.bounds.size / STEP).ceil()) + Vector2i.ONE
	var blank := Image.create(built.size.x, built.size.y, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 0.0, 0.0, 0.0))
	built.field = blank.get_data()
	built.zone = blank.get_data()
	built._lakes()
	built._crevasses()
	built._snow()
	built._icy()
	built._chasms()
	built._light()
	built._cave = null
	return built


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, field))


func zone_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, zone))


func light_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(light_size.x, light_size.y, false,
		Image.FORMAT_RGBA8, light))


## The walls' distance field as a float texture (one texel per sample).
static func sdf_texture(cave: NelvarCaveData) -> ImageTexture:
	var image := Image.create_from_data(cave.sdf_size.x, cave.sdf_size.y, false, Image.FORMAT_RF,
		cave.sdf.to_byte_array())
	return ImageTexture.create_from_image(image)


func _pixel(point: Vector2) -> Vector2i:
	return Vector2i((point / STEP).floor()) - origin


func _world(x: int, y: int) -> Vector2:
	return (Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)) * STEP


func _box(center: Vector2, reach: float) -> Rect2i:
	var from := _pixel(center - Vector2.ONE * reach).max(Vector2i.ZERO)
	var to := _pixel(center + Vector2.ONE * reach).min(size - Vector2i.ONE)
	return Rect2i(from, to - from)


func _lakes() -> void:
	for l in _cave.lakes.size():
		var shape := _cave.lakes[l].shape
		var kind := _cave.pools[l]
		var box := _box(shape.center, shape.reach() + BAND * STEP + 8.0)
		for y in range(box.position.y, box.end.y + 1):
			for x in range(box.position.x, box.end.x + 1):
				var point := _world(x, y)
				var depth := shape.signed_distance(point) / STEP
				if depth < -BAND:
					continue
				var index := (y * size.x + x) * 4
				var value := clampi(128 + roundi(depth), 0, 255)
				if value >= field[index]:
					field[index] = value
					field[index + 1] = (field[index + 1] & 0xfc) | kind
				if kind == NelvarCaveData.Pool.OPEN:
					var water := depth - _cave.rims[l] / STEP
					if water > -BAND:
						zone[index + 2] = maxi(zone[index + 2], clampi(128 + roundi(water), 1, 255))
		for patch in _cave.lakes[l].thin:
			var patch_box := _box(patch.center, patch.reach() + 8.0)
			for y in range(patch_box.position.y, patch_box.end.y + 1):
				for x in range(patch_box.position.x, patch_box.end.x + 1):
					var depth := patch.signed_distance(_world(x, y)) / STEP
					if depth < 0.0:
						continue
					var index := (y * size.x + x) * 4 + 3
					field[index] = maxi(field[index], clampi(1 + roundi(depth * 8.0), 1, THIN_MAX))


## Each crevasse by its nearest segment, as NelvarIceData.crevasse_sample: the crack's
## depth without the bridges, the bridges' decks.
func _crevasses() -> void:
	for crevasse in _cave.crevasses:
		var deck := func(raw: float, distance: float, along: float, index: int) -> void:
			if raw > -1.5 and crevasse.depth_at(distance, along) < 0.0:
				field[index + 3] = BRIDGE
		_line(crevasse, 2, deck, field)


## The chasms by their nearest segment (arches ignored), then the arches' decks.
func _chasms() -> void:
	for chasm in _cave.chasms:
		_line(chasm, 0, Callable(), zone)
		for arch in chasm.arches:
			var reach := arch.length() * 0.5 + arch.half_width + 8.0
			var box := _box((arch.a + arch.b) * 0.5, reach)
			for y in range(box.position.y, box.end.y + 1):
				for x in range(box.position.x, box.end.x + 1):
					if arch.distance(_world(x, y)) < arch.half_width:
						zone[(y * size.x + x) * 4 + 1] = ARCH


## Writes 128 + art pixels into the line (nearest segment) in `channel` of `target`,
## calling `extra` with (raw depth, distance, along, index) where it is written.
func _line(line: NelvarIceData.Crevasse, channel: int, extra: Callable, target: PackedByteArray) -> void:
	_nearest(line, BAND * STEP + 8.0, func(raw: float, distance: float, along: float, index: int) -> void:
		if raw < -BAND:
			return
		target[index + channel] = maxi(target[index + channel], clampi(128 + roundi(raw), 1, 255))
		if extra.is_valid():
			extra.call(raw, distance, along, index))


## Calls `visit` with (raw depth in art pixels, distance, along, field index) for every
## pixel within `reach` of the line, by its nearest segment.
func _nearest(line: NelvarIceData.Crevasse, reach_out: float, visit: Callable) -> void:
	var grow := line.widest() + reach_out
	var low := line.points[0]
	var high := line.points[0]
	for point in line.points:
		low = low.min(point)
		high = high.max(point)
	var from := _pixel(low - Vector2.ONE * grow).max(Vector2i.ZERO)
	var to := _pixel(high + Vector2.ONE * grow).min(size - Vector2i.ONE)
	var w := to.x - from.x + 1
	var h := to.y - from.y + 1
	if w <= 0 or h <= 0:
		return
	var nearest := PackedFloat32Array()
	nearest.resize(w * h)
	nearest.fill(INF)
	var alongs := PackedFloat32Array()
	alongs.resize(w * h)
	for i in line.points.size() - 1:
		var a := line.points[i]
		var b := line.points[i + 1]
		var reach := maxf(line.half_widths[i], line.half_widths[i + 1]) + reach_out
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
					alongs[k] = line.lengths[i] + sqrt(length_squared) * t
	for y in h:
		for x in w:
			var k := y * w + x
			if nearest[k] == INF:
				continue
			var index := ((from.y + y) * size.x + from.x + x) * 4
			visit.call(line.raw_depth(nearest[k], alongs[k]) / STEP, nearest[k], alongs[k], index)


## Snow round the sunny spots and in its tongues: how deep (NelvarCaveData.snow_depth),
## row by row on several cores; the walls are skipped.
func _snow() -> void:
	_snow_boxes.clear()
	for skylight in _cave.skylights:
		_snow_boxes.append(_box(skylight.spot.center, skylight.spot.reach() + skylight.reach + 40.0))
	for tongue in _cave.tongues:
		var from := _pixel(tongue.box.position - Vector2.ONE * 30.0).max(Vector2i.ZERO)
		var to := _pixel(tongue.box.end + Vector2.ONE * 30.0).min(size - Vector2i.ONE)
		_snow_boxes.append(Rect2i(from, to - from))
	var group := WorkerThreadPool.add_group_task(_snow_row, size.y, NelvarPaintQueue.threads, true, "Cave snow")
	WorkerThreadPool.wait_for_group_task_completion(group)


func _snow_row(y: int) -> void:
	for box in _snow_boxes:
		if y < box.position.y or y > box.end.y:
			continue
		for x in range(box.position.x, box.end.x + 1):
			var index := (y * size.x + x) * 4 + 1
			if field[index] >> 3 != 0:
				continue
			var point := _world(x, y)
			if _cave.wall_depth(point) > 8.0:
				continue
			var depth := _cave.snow_depth(point)
			if depth > 0.0:
				field[index] = (field[index] & 0x07) | (clampi(1 + int(depth / 4.0), 1, 31) << 3)


## The smooth ice of the icy passages (as NelvarCaveData.icy_at: in a corridor and
## ICY_SPARE past it, out of the halls).
func _icy() -> void:
	for passage in _cave.passages:
		if not passage.icy:
			continue
		var mark := func(raw: float, _distance: float, _along: float, index: int) -> void:
			if raw * STEP <= -NelvarCaveData.ICY_SPARE or field[index + 1] & 4 != 0:
				return
			var pixel := index / 4
			if _cave.hall_depth(_world(pixel % size.x, pixel / size.x)) < -10.0:
				field[index + 1] |= 4
		_nearest(passage, NelvarCaveData.ICY_SPARE + 8.0, mark)


## The coarse light map from the queries; the crystals' glow and the ice glowing by the
## sun on top.
func _light() -> void:
	light_origin = Vector2i((Vector2(origin) / LIGHT_SCALE).floor()) * LIGHT_SCALE
	light_size = Vector2i((Vector2(size) / LIGHT_SCALE).ceil()) + Vector2i.ONE * 2
	light.resize(light_size.x * light_size.y * 4)
	var glows := PackedFloat32Array()
	glows.resize(light_size.x * light_size.y)
	for thing in _cave.things:
		if thing.kind != NelvarIceData.Kind.CRYSTAL or thing.size.y < 0.5:
			continue
		var reach := 60.0 + thing.radius * 3.0
		var center := thing.position + Vector2(0.0, -thing.radius)
		var from := Vector2i(((center - Vector2.ONE * reach) / STEP / LIGHT_SCALE - Vector2(light_origin) / LIGHT_SCALE).floor()).max(Vector2i.ZERO)
		var to := Vector2i(((center + Vector2.ONE * reach) / STEP / LIGHT_SCALE - Vector2(light_origin) / LIGHT_SCALE).ceil()).min(light_size - Vector2i.ONE)
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var point := (Vector2(light_origin) + (Vector2(x, y) + Vector2(0.5, 0.5)) * LIGHT_SCALE) * STEP
				var d := point.distance_to(center)
				if d < reach:
					var k := y * light_size.x + x
					glows[k] = maxf(glows[k], pow(1.0 - d / reach, 1.4) * (0.55 + thing.radius / 80.0))
	_glows = glows
	var group := WorkerThreadPool.add_group_task(_light_row, light_size.y, NelvarPaintQueue.threads, true, "Cave light")
	WorkerThreadPool.wait_for_group_task_completion(group)
	_glows = PackedFloat32Array()


func _light_row(y: int) -> void:
	for x in light_size.x:
		var point := (Vector2(light_origin) + (Vector2(x, y) + Vector2(0.5, 0.5)) * LIGHT_SCALE) * STEP
		var index := (y * light_size.x + x) * 4
		light[index] = roundi(_cave.sun_at(point) * 255.0)
		light[index + 2] = roundi(_cave.warmth_at(point) * 255.0)
		light[index + 3] = roundi(_cave.cold_at(point) * 255.0)
		var glow := _glows[y * light_size.x + x]
		if _cave.wall_depth(point) > -6.0:
			for skylight in _cave.skylights:
				var gap := -skylight.spot.signed_distance(point)
				if gap < SUN_GLOW:
					glow = maxf(glow, (1.0 - maxf(gap, 0.0) / SUN_GLOW) * 0.75)
		light[index + 1] = roundi(clampf(glow, 0.0, 1.0) * 255.0)
