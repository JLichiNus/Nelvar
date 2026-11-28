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
# What the row tasks read, flattened here first: on many threads a GDScript call, or a read
# of another object's field, costs far more than the arithmetic (see NelvarPaintQueue).
## The walls' distance field (NelvarCaveData.wall_depth written out).
var _sdf := PackedFloat32Array()
var _sdf_origin := Vector2.ZERO
var _sdf_size := Vector2i.ZERO
## Radial shapes (see _flatten()): the sunny spots, the halls.
var _spots: Array = []
var _halls: Array = []
var _hall_zones := PackedInt32Array()
var _hall_grid := {}
## Per sunny spot: snow reaches this much past it, and is looked for within this squared
## distance of its centre (NelvarCaveData.snow_depth).
var _spot_reaches := PackedFloat64Array()
var _spot_limits := PackedFloat64Array()
## The snow tongues: boxes, then points and half widths run together (from[t]..from[t + 1]).
var _tongue_boxes: Array[Rect2] = []
var _tongue_points := PackedVector2Array()
var _tongue_halves := PackedFloat32Array()
var _tongue_from := PackedInt32Array()
var _geyser_spots := PackedVector2Array()
var _geyser_radii := PackedFloat64Array()
## The lines of the pass running (_lines()), its kind, its first row; the arches.
var _line_data: Array = []
var _line_mode := 0
var _line_y0 := 0
var _arch_data: Array = []

enum Line { CREVASSE, CHASM, ICY }


static func build(cave: NelvarCaveData) -> NelvarCaveField:
	var built := NelvarCaveField.new()
	built._cave = cave
	built.origin = Vector2i((cave.bounds.position / STEP).floor())
	built.size = Vector2i((cave.bounds.size / STEP).ceil()) + Vector2i.ONE
	# Filled here (a write), so each buffer is its own before the row tasks write into it.
	built.field.resize(built.size.x * built.size.y * 4)
	built.field.fill(0)
	built.zone.resize(built.size.x * built.size.y * 4)
	built.zone.fill(0)
	built._flatten_cave()
	built._lakes()
	built._crevasses()
	built._snow()
	built._icy()
	built._chasms()
	built._light()
	built._cave = null
	built._sdf = PackedFloat32Array()
	built._hall_grid = {}
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


# --- Flattening --------------------------------------------------------------------

func _flatten_cave() -> void:
	_sdf = _cave.sdf
	_sdf_origin = _cave.sdf_origin
	_sdf_size = _cave.sdf_size
	var spots: Array[NelvarEarthData.Radial] = []
	for skylight in _cave.skylights:
		spots.append(skylight.spot)
		_spot_reaches.append(skylight.reach)
		_spot_limits.append(pow(skylight.spot.reach() + skylight.reach + 300.0, 2.0))
	_spots = _flatten(spots)
	var shapes: Array[NelvarEarthData.Radial] = []
	for hall in _cave.halls:
		shapes.append(hall.shape)
		_hall_zones.append(hall.zone)
	_halls = _flatten(shapes)
	_hall_grid = _cave._hall_grid
	_tongue_from.append(0)
	for tongue in _cave.tongues:
		_tongue_boxes.append(tongue.box)
		_tongue_points.append_array(tongue.points)
		_tongue_halves.append_array(tongue.half_widths)
		_tongue_from.append(_tongue_points.size())
	for geyser in _cave.geysers:
		_geyser_spots.append(geyser.position)
		_geyser_radii.append(geyser.radius)


## Radial shapes as [centres, axes, amplitudes, phases, from]: shape j's harmonics are
## from[j]..from[j + 1]. The row tasks write NelvarEarthData.Radial.signed_distance out
## over these, term for term, so the result is the same to the bit.
static func _flatten(shapes: Array[NelvarEarthData.Radial]) -> Array:
	var centers := PackedVector2Array()
	var axes := PackedVector2Array()
	var amplitudes := PackedFloat32Array()
	var phases := PackedFloat32Array()
	var from := PackedInt32Array([0])
	for shape in shapes:
		centers.append(shape.center)
		axes.append(shape.axes)
		amplitudes.append_array(shape.amplitudes)
		phases.append_array(shape.phases)
		from.append(amplitudes.size())
	return [centers, axes, amplitudes, phases, from]


# --- The lines ----------------------------------------------------------------------

## Each crevasse by its nearest segment, as NelvarIceData.crevasse_sample: the crack's
## depth without the bridges, the bridges' decks.
func _crevasses() -> void:
	_lines(_cave.crevasses, BAND * STEP + 8.0, Line.CREVASSE)


## The chasms by their nearest segment (arches ignored), and the arches' decks.
func _chasms() -> void:
	_arch_data.clear()
	for chasm in _cave.chasms:
		for arch in chasm.arches:
			var reach := arch.length() * 0.5 + arch.half_width + 8.0
			var box := _box((arch.a + arch.b) * 0.5, reach)
			_arch_data.append([arch.a, arch.b, arch.half_width, box])
	_lines(_cave.chasms, BAND * STEP + 8.0, Line.CHASM)
	_arch_data.clear()


## The smooth ice of the icy passages (as NelvarCaveData.icy_at: in a corridor and
## ICY_SPARE past it, out of the halls).
func _icy() -> void:
	var icy: Array = []
	for passage in _cave.passages:
		if passage.icy:
			icy.append(passage)
	_lines(icy, NelvarCaveData.ICY_SPARE + 8.0, Line.ICY)


## Every pixel within `reach_out` of a line, by its nearest segment (the first of the
## nearest, segment order), row by row on several cores; `mode` says what is written.
func _lines(lines: Array, reach_out: float, mode: int) -> void:
	_line_data.clear()
	var y0 := size.y
	var y1 := -1
	for line: NelvarIceData.Crevasse in lines:
		var grow := line.widest() + reach_out
		var low := line.points[0]
		var high := line.points[0]
		for point in line.points:
			low = low.min(point)
			high = high.max(point)
		var from := _pixel(low - Vector2.ONE * grow).max(Vector2i.ZERO)
		var to := _pixel(high + Vector2.ONE * grow).min(size - Vector2i.ONE)
		if to.x < from.x or to.y < from.y:
			continue
		var segments := PackedInt32Array()
		for i in line.points.size() - 1:
			var a := line.points[i]
			var b := line.points[i + 1]
			var reach := maxf(line.half_widths[i], line.half_widths[i + 1]) + reach_out
			var seg_from := _pixel(a.min(b) - Vector2.ONE * reach).max(from)
			var seg_to := _pixel(a.max(b) + Vector2.ONE * reach).min(to)
			segments.append_array([seg_from.x, seg_from.y, seg_to.x, seg_to.y])
		var bridges := PackedFloat64Array()
		for bridge in line.bridges:
			bridges.append(bridge.along)
			bridges.append(bridge.half_length)
		_line_data.append([line.points, line.half_widths, line.lengths,
			PackedInt32Array([from.x, from.y, to.x, to.y]), segments, bridges])
		y0 = mini(y0, from.y)
		y1 = maxi(y1, to.y)
	for arch: Array in _arch_data:
		var box: Rect2i = arch[3]
		y0 = mini(y0, box.position.y)
		y1 = maxi(y1, box.end.y)
	if y1 < y0:
		return
	_line_mode = mode
	_line_y0 = y0
	var group := WorkerThreadPool.add_group_task(_line_row, y1 - y0 + 1, NelvarPaintQueue.threads, true, "Cave lines")
	WorkerThreadPool.wait_for_group_task_completion(group)
	_line_data.clear()


func _line_row(r: int) -> void:
	var y := _line_y0 + r
	var mode := _line_mode
	var bytes := field
	var zones := zone
	var ox := origin.x
	var oy := origin.y
	var sx := size.x
	var half_pixel := Vector2(0.5, 0.5)
	for line: Array in _line_data:
		var box: PackedInt32Array = line[3]
		if y < box[1] or y > box[3]:
			continue
		var points: PackedVector2Array = line[0]
		var halves: PackedFloat32Array = line[1]
		var lengths: PackedFloat32Array = line[2]
		var segments: PackedInt32Array = line[4]
		var bridges: PackedFloat64Array = line[5]
		var fx := box[0]
		var w := box[2] - fx + 1
		var nearest := PackedFloat32Array()
		nearest.resize(w)
		nearest.fill(INF)
		var alongs := PackedFloat32Array()
		alongs.resize(w)
		var nearest_segment := PackedInt32Array()
		nearest_segment.resize(w)
		for i in points.size() - 1:
			var s := i * 4
			if y < segments[s + 1] or y > segments[s + 3]:
				continue
			var a := points[i]
			var span := points[i + 1] - a
			var length_squared := maxf(span.length_squared(), 0.0001)
			var segment_length := sqrt(length_squared)
			var start := lengths[i]
			for x in range(segments[s], segments[s + 2] + 1):
				var point := (Vector2(ox + x, oy + y) + half_pixel) * STEP
				var t := clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
				var distance := point.distance_to(a + span * t)
				var k := x - fx
				if distance < nearest[k]:
					nearest[k] = distance
					alongs[k] = start + segment_length * t
					nearest_segment[k] = i
		var n := lengths.size()
		for k in w:
			var distance := nearest[k]
			if distance == INF:
				continue
			var along := alongs[k]
			# Crevasse.half_width_at(along): its segment is the first j >= 1 with
			# lengths[j] >= along, less one; looked for from the nearest segment.
			var j := clampi(nearest_segment[k] + 1, 1, n - 1)
			if lengths[j] >= along:
				while j > 1 and lengths[j - 1] >= along:
					j -= 1
			else:
				while j < n and lengths[j] < along:
					j += 1
			var si := j - 1 if j < n else n - 2
			var piece := maxf(0.0001, lengths[si + 1] - lengths[si])
			var half := lerpf(halves[si], halves[si + 1], clampf((along - lengths[si]) / piece, 0.0, 1.0))
			var raw := (half - distance) / STEP
			var index := (y * sx + fx + k) * 4
			if mode == Line.ICY:
				if raw * STEP <= -NelvarCaveData.ICY_SPARE or bytes[index + 1] & 4 != 0:
					continue
				if _out_of_halls((Vector2(ox + fx + k, oy + y) + half_pixel) * STEP):
					bytes[index + 1] |= 4
				continue
			if raw < -BAND:
				continue
			var value := clampi(128 + roundi(raw), 1, 255)
			if mode == Line.CHASM:
				zones[index] = maxi(zones[index], value)
				continue
			bytes[index + 2] = maxi(bytes[index + 2], value)
			if raw > -1.5:
				# Crevasse.depth_at: the bridges are ground.
				var depth := half - distance
				for q in range(0, bridges.size(), 2):
					var off := absf(along - bridges[q])
					if off < bridges[q + 1] + 48.0:
						depth = minf(depth, off - bridges[q + 1])
				if depth < 0.0:
					bytes[index + 3] = BRIDGE
	if mode == Line.CHASM:
		for arch: Array in _arch_data:
			var box: Rect2i = arch[3]
			if y < box.position.y or y > box.end.y:
				continue
			var a: Vector2 = arch[0]
			var b: Vector2 = arch[1]
			var half_width: float = arch[2]
			for x in range(box.position.x, box.end.x + 1):
				var point := (Vector2(ox + x, oy + y) + half_pixel) * STEP
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) < half_width:
					zones[(y * sx + x) * 4 + 1] = ARCH


## NelvarCaveData.hall_depth(point) < -10, written out (the icy passages' pixels only:
## one call a pixel there is cheap enough).
func _out_of_halls(point: Vector2) -> bool:
	var list: Variant = _hall_grid.get(Vector2i((point / NelvarCaveData._HALL_CELL).floor()))
	if list == null:
		return true
	var centers: PackedVector2Array = _halls[0]
	var axes: PackedVector2Array = _halls[1]
	var amplitudes: PackedFloat32Array = _halls[2]
	var phases: PackedFloat32Array = _halls[3]
	var from: PackedInt32Array = _halls[4]
	for h: int in list:
		var offset := point - centers[h]
		var angle := 0.0
		var away := 0.0
		if offset.length_squared() >= 0.0001:
			angle = offset.angle()
			away = offset.length()
		var c := cos(angle)
		var s := sin(angle)
		var ax := axes[h]
		var bend := 1.0
		for q in range(from[h], from[h + 1]):
			bend += amplitudes[q] * cos(float(q - from[h] + 2) * angle + phases[q])
		if ax.x * ax.y / sqrt(ax.y * ax.y * c * c + ax.x * ax.x * s * s) * bend - away >= -10.0:
			return false
	return true


# --- Snow ---------------------------------------------------------------------------

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


## The boxes overlapping this row merged into spans, each pixel looked at once.
func _snow_row(y: int) -> void:
	var spans: Array[Vector2i] = []
	for box in _snow_boxes:
		if y >= box.position.y and y <= box.end.y and box.end.x >= box.position.x:
			spans.append(Vector2i(box.position.x, box.end.x))
	if spans.is_empty():
		return
	spans.sort()
	var bytes := field
	var sdf := _sdf
	var sdf_origin := _sdf_origin
	var sdf_w := _sdf_size.x
	var sdf_last := _sdf_size - Vector2i.ONE
	var spot_centers: PackedVector2Array = _spots[0]
	var spot_axes: PackedVector2Array = _spots[1]
	var spot_amplitudes: PackedFloat32Array = _spots[2]
	var spot_phases: PackedFloat32Array = _spots[3]
	var spot_from: PackedInt32Array = _spots[4]
	var spot_reaches := _spot_reaches
	var spot_limits := _spot_limits
	var spot_count := spot_centers.size()
	var tongue_boxes := _tongue_boxes
	var tongue_points := _tongue_points
	var tongue_halves := _tongue_halves
	var tongue_from := _tongue_from
	var tongue_count := tongue_boxes.size()
	var ox := origin.x
	var oy := origin.y
	var sx := size.x
	var half_pixel := Vector2(0.5, 0.5)
	var done := -1
	for span in spans:
		for x in range(maxi(span.x, done + 1), span.y + 1):
			var index := (y * sx + x) * 4 + 1
			if bytes[index] >> 3 != 0:
				continue
			var point := (Vector2(ox + x, oy + y) + half_pixel) * STEP
			# NelvarCaveData.wall_depth(point) > 8: the wall.
			var f := (point - sdf_origin) / NelvarCaveData.CELL
			var cx := floori(f.x)
			var cy := floori(f.y)
			if cx < 0 or cy < 0 or cx >= sdf_last.x or cy >= sdf_last.y:
				continue
			var tx := f.x - cx
			var i := cy * sdf_w + cx
			if lerpf(lerpf(sdf[i], sdf[i + 1], tx), lerpf(sdf[i + sdf_w], sdf[i + sdf_w + 1], tx), f.y - cy) > 8.0:
				continue
			# NelvarCaveData.snow_depth(point).
			var best := -1000.0
			for j in spot_count:
				if point.distance_squared_to(spot_centers[j]) > spot_limits[j]:
					continue
				var offset := point - spot_centers[j]
				var angle := 0.0
				var away := 0.0
				if offset.length_squared() >= 0.0001:
					angle = offset.angle()
					away = offset.length()
				var c := cos(angle)
				var s := sin(angle)
				var ax := spot_axes[j]
				var bend := 1.0
				for q in range(spot_from[j], spot_from[j + 1]):
					bend += spot_amplitudes[q] * cos(float(q - spot_from[j] + 2) * angle + spot_phases[q])
				best = maxf(best, ax.x * ax.y / sqrt(ax.y * ax.y * c * c + ax.x * ax.x * s * s) * bend - away
					+ spot_reaches[j])
			for t in tongue_count:
				if not tongue_boxes[t].has_point(point):
					continue
				for q in range(tongue_from[t], tongue_from[t + 1] - 1):
					var a := tongue_points[q]
					var along := tongue_points[q + 1] - a
					var u := clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
					var half := lerpf(tongue_halves[q], tongue_halves[q + 1], u)
					best = maxf(best, half - point.distance_to(a + along * u))
			# The noise adds at most 22: no snow below that.
			if best <= -22.0:
				continue
			# NelvarPixelArt.value_noise(point.x / 52.0, point.y / 52.0, 77).
			var nx := point.x / 52.0
			var ny := point.y / 52.0
			var ix := floori(nx)
			var iy := floori(ny)
			var fx := nx - ix
			var fy := ny - iy
			var sxn := fx * fx * (3.0 - 2.0 * fx)
			var syn := fy * fy * (3.0 - 2.0 * fy)
			var corner := ix * 374761393 + iy * 668265263 + 77 * 2246822519
			var h := corner & 0xffffffff
			h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
			var na := float((h ^ (h >> 16)) & 0xffff) / 65535.0
			h = (corner + 374761393) & 0xffffffff
			h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
			var nb := float((h ^ (h >> 16)) & 0xffff) / 65535.0
			h = (corner + 668265263) & 0xffffffff
			h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
			var nc := float((h ^ (h >> 16)) & 0xffff) / 65535.0
			h = (corner + 374761393 + 668265263) & 0xffffffff
			h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
			var nd := float((h ^ (h >> 16)) & 0xffff) / 65535.0
			var noise := na + (nb - na) * sxn + (nc - na) * syn + (na - nb - nc + nd) * sxn * syn
			var depth := best + (noise - 0.5) * 44.0
			if depth > 0.0:
				bytes[index] = (bytes[index] & 0x07) | (clampi(1 + int(depth / 4.0), 1, 31) << 3)
		done = maxi(done, span.y)


# --- Light --------------------------------------------------------------------------

## The coarse light map from the queries; the crystals' glow and the ice glowing by the
## sun on top.
func _light() -> void:
	light_origin = Vector2i((Vector2(origin) / LIGHT_SCALE).floor()) * LIGHT_SCALE
	light_size = Vector2i((Vector2(size) / LIGHT_SCALE).ceil()) + Vector2i.ONE * 2
	light.resize(light_size.x * light_size.y * 4)
	light.fill(0)
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


## NelvarCaveData.sun_at, warmth_at, cold_at and wall_depth written out; each spot's
## distance serves the sun and the glow alike.
func _light_row(y: int) -> void:
	var bytes := light
	var glows := _glows
	var sdf := _sdf
	var sdf_origin := _sdf_origin
	var sdf_w := _sdf_size.x
	var sdf_last := _sdf_size - Vector2i.ONE
	var spot_centers: PackedVector2Array = _spots[0]
	var spot_axes: PackedVector2Array = _spots[1]
	var spot_amplitudes: PackedFloat32Array = _spots[2]
	var spot_phases: PackedFloat32Array = _spots[3]
	var spot_from: PackedInt32Array = _spots[4]
	var spot_count := spot_centers.size()
	var hall_centers: PackedVector2Array = _halls[0]
	var hall_axes: PackedVector2Array = _halls[1]
	var hall_amplitudes: PackedFloat32Array = _halls[2]
	var hall_phases: PackedFloat32Array = _halls[3]
	var hall_from: PackedInt32Array = _halls[4]
	var hall_zones := _hall_zones
	var hall_grid := _hall_grid
	var geyser_spots := _geyser_spots
	var geyser_radii := _geyser_radii
	var spot_distances := PackedFloat64Array()
	spot_distances.resize(spot_count)
	var corner := Vector2(light_origin)
	var lw := light_size.x
	for x in lw:
		var point := (corner + (Vector2(x, y) + Vector2(0.5, 0.5)) * LIGHT_SCALE) * STEP
		var index := (y * lw + x) * 4
		var sun := 0.0
		for j in spot_count:
			var offset := point - spot_centers[j]
			var angle := 0.0
			var away := 0.0
			if offset.length_squared() >= 0.0001:
				angle = offset.angle()
				away = offset.length()
			var c := cos(angle)
			var s := sin(angle)
			var ax := spot_axes[j]
			var bend := 1.0
			for q in range(spot_from[j], spot_from[j + 1]):
				bend += spot_amplitudes[q] * cos(float(q - spot_from[j] + 2) * angle + spot_phases[q])
			var distance := ax.x * ax.y / sqrt(ax.y * ax.y * c * c + ax.x * ax.x * s * s) * bend - away
			spot_distances[j] = distance
			sun = maxf(sun, smoothstep(-NelvarCaveData.SUN_EDGE, NelvarCaveData.SUN_EDGE, distance))
		bytes[index] = roundi(sun * 255.0)
		var warmth := 0.0
		for g in geyser_spots.size():
			var d := point.distance_to(geyser_spots[g])
			if d < geyser_radii[g]:
				warmth = maxf(warmth, 1.0 - smoothstep(0.0, geyser_radii[g], d))
		bytes[index + 2] = roundi(warmth * 255.0)
		var cold := 0.0
		var list: Variant = hall_grid.get(Vector2i((point / NelvarCaveData._HALL_CELL).floor()))
		if list != null:
			for h: int in list:
				if hall_zones[h] != NelvarCaveData.Zone.COLD:
					continue
				var offset := point - hall_centers[h]
				var angle := 0.0
				var away := 0.0
				if offset.length_squared() >= 0.0001:
					angle = offset.angle()
					away = offset.length()
				var c := cos(angle)
				var s := sin(angle)
				var ax := hall_axes[h]
				var bend := 1.0
				for q in range(hall_from[h], hall_from[h + 1]):
					bend += hall_amplitudes[q] * cos(float(q - hall_from[h] + 2) * angle + hall_phases[q])
				var distance := ax.x * ax.y / sqrt(ax.y * ax.y * c * c + ax.x * ax.x * s * s) * bend - away
				cold = maxf(cold, smoothstep(-NelvarCaveData.COLD_EDGE, NelvarCaveData.COLD_EDGE, distance))
		bytes[index + 3] = roundi(cold * 255.0)
		var glow := glows[y * lw + x]
		# NelvarCaveData.wall_depth(point) > -6: the floor and the foot of the walls.
		var wall := 1000.0
		var f := (point - sdf_origin) / NelvarCaveData.CELL
		var cx := floori(f.x)
		var cy := floori(f.y)
		if cx >= 0 and cy >= 0 and cx < sdf_last.x and cy < sdf_last.y:
			var tx := f.x - cx
			var i := cy * sdf_w + cx
			wall = lerpf(lerpf(sdf[i], sdf[i + 1], tx), lerpf(sdf[i + sdf_w], sdf[i + sdf_w + 1], tx), f.y - cy)
		if wall > -6.0:
			for j in spot_count:
				var gap := -spot_distances[j]
				if gap < SUN_GLOW:
					glow = maxf(glow, (1.0 - maxf(gap, 0.0) / SUN_GLOW) * 0.75)
		bytes[index + 1] = roundi(clampf(glow, 0.0, 1.0) * 255.0)
