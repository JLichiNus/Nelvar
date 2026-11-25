class_name NelvarCraterGenerator
extends RefCounted
## Lays out the volcano from a seed: the crater lake and its vent, the anchors round the
## vent and the rings of floating islands round them, the capes reaching for the outer
## ring, the narrow rim with its terraces, the spawn on the southern terrace, boiling
## patches, roads of cooled lava (a ring along the rim, spurs to the capes and terraces),
## geysers, fumaroles under smoke banks, and the stones, snags and few plants of the top.
##
## The rings are set so that nothing ever collides: each ring keeps to its own band of
## distance from the vent, `ring_gap` from the next one, the anchors inside the first and
## the capes' tips outside the last. Every island spans its band (its size differs from
## the ring's biggest by `ring_slack` at most), so it comes within a short run of each
## island of the neighbouring rings as they pass each other, of the anchors or of the
## capes. The generator samples every pair over a full turn to make sure.
##
## Every stage draws from its own seeded generator, so changing one leaves the others.

const Kind = NelvarFireData.Kind
const Species = NelvarFireData.Species
const Stone = NelvarFireData.Stone
const IsleKind = NelvarCraterData.IsleKind

const GRID := 160.0
const PROFILE_SAMPLES := 1440
## Islands are almost round: their gaps are tight. Bounds on how far their outline
## strays from the radius (the bends, and the short axis).
const ISLE_WOBBLE := 0.03
const ISLE_REACH := 1.045
## Samples of a full turn when gaps are checked.
const GAP_SAMPLES := 360
const TRUNK := Vector2(11.0, 15.0)
const CROWN := Vector2(34.0, 50.0)
const HEIGHT := Vector2(150.0, 200.0)

var _config: NelvarCraterConfig
var _data: NelvarCraterData
var _grid := {}
## Rim width without the terraces, per profile sample.
var _plain := PackedFloat32Array()


func generate(config: NelvarCraterConfig, world_seed: int) -> NelvarCraterData:
	var error := config.validation_error()
	if not error.is_empty():
		push_error("Crater config: " + error)
		return null
	_config = config
	_data = NelvarCraterData.new()
	_data.world_seed = world_seed
	_grid.clear()
	_lake(_rng("lake"))
	if not _rings(_rng("rings")):
		push_error("Crater %d: the islands' rings do not fit in the lake." % world_seed)
		_data = null
		return null
	_capes(_rng("capes"))
	_check_gaps()
	_summit(_rng("summit"))
	_spawn()
	_boils(_rng("boils"))
	_flows(_rng("flows"))
	_data.index_flows()
	_geysers(_rng("geysers"))
	_vents(_rng("vents"))
	_rocks(_rng("rocks"))
	_crystals(_rng("crystals"))
	_snags(_rng("snags"))
	_plants(_rng("plants"))
	_data.finish()
	for i in _data.isles.size():
		_data.isles[i].id = i
	var result := _data
	_data = null
	_grid.clear()
	return result


func _rng(stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:crater:%s" % [_data.world_seed, stage]).hash()
	return rng


## Slow bends: harmonic k gets a share of `depth` falling with k; the sum stays below
## `limit`, so the shape never pinches.
static func _bend(shape: NelvarEarthData.Radial, rng: RandomNumberGenerator, depth: float, limit: float) -> void:
	shape.amplitudes.resize(NelvarEarthData.HARMONICS)
	shape.phases.resize(NelvarEarthData.HARMONICS)
	var total := 0.0
	for i in NelvarEarthData.HARMONICS:
		shape.amplitudes[i] = depth * rng.randf_range(0.3, 1.0) / pow(float(i + 1), 0.9)
		shape.phases[i] = rng.randf() * TAU
		total += shape.amplitudes[i]
	if total > limit:
		for i in NelvarEarthData.HARMONICS:
			shape.amplitudes[i] *= limit / total


# --- The lake and its islands ------------------------------------------------------

func _lake(rng: RandomNumberGenerator) -> void:
	var lake := NelvarEarthData.Radial.new()
	lake.center = Vector2.ZERO
	lake.axes = _config.lake_radius * Vector2(rng.randf_range(0.97, 1.03), rng.randf_range(0.97, 1.03))
	_bend(lake, rng, _config.lake_wobble, _config.lake_wobble * 1.6)
	_data.lake = lake
	_data.lakes.append(lake)
	_data.lake_polygons.append(lake.polygon(_config.shore_vertices))
	_data.vent = lake.center
	_data.vent_radius = rng.randf_range(_config.vent_radius.x, _config.vent_radius.y)


## Nearest the shore comes to the vent.
func _lake_min() -> float:
	var best := INF
	for i in 720:
		best = minf(best, _data.lake.radius_at(TAU * i / 720.0))
	return best


## Anchors round the vent, then three rings: big plates, rafts, smaller plates. The sizes
## shrink towards their smallest until the capes fit between the last ring and the shore.
func _rings(rng: RandomNumberGenerator) -> bool:
	var gap := _config.ring_gap
	var room := _lake_min() - _config.cape_min_length - gap
	var anchor_top := rng.randf_range(_config.anchor_radius.x, _config.anchor_radius.y)
	var tops: Array[float] = [rng.randf_range(_config.inner_plate_radius.x, _config.inner_plate_radius.y),
		rng.randf_range(_config.raft_radius.x, _config.raft_radius.y),
		rng.randf_range(_config.outer_plate_radius.x, _config.outer_plate_radius.y)]
	var lows: Array[float] = [_config.inner_plate_radius.x, _config.raft_radius.x, _config.outer_plate_radius.x]
	var sizes: Array[float] = []
	var anchor_size := 0.0
	for attempt in 11:
		var t := attempt / 10.0
		anchor_size = lerpf(anchor_top, _config.anchor_radius.x, t)
		sizes.clear()
		var edge := _config.vent_clearance + anchor_size * 2.0 * ISLE_REACH
		for k in 3:
			sizes.append(lerpf(tops[k], lows[k], t))
			edge += gap + sizes[k] * 2.0 * ISLE_REACH
		if edge <= room:
			break
		if attempt == 10:
			return false
	# Room left over pushes everything out from the vent, so the capes stay short.
	var used := _config.vent_clearance + anchor_size * 2.0 * ISLE_REACH
	for k in 3:
		used += gap + sizes[k] * 2.0 * ISLE_REACH
	var spare := maxf(0.0, room - used - rng.randf_range(0.0, 40.0))
	_data.anchor_reach = _config.vent_clearance + spare + anchor_size * 2.0 * ISLE_REACH
	_anchors(rng, anchor_size)
	var inner := _data.anchor_reach + gap
	var way := 1.0 if rng.randf() < 0.5 else -1.0
	var kinds: Array[int] = [IsleKind.PLATE, IsleKind.RAFT, IsleKind.PLATE]
	var counts: Array[int] = [rng.randi_range(_config.inner_plates.x, _config.inner_plates.y),
		rng.randi_range(_config.rafts.x, _config.rafts.y),
		rng.randi_range(_config.outer_plates.x, _config.outer_plates.y)]
	for k in 3:
		var outer := inner + sizes[k] * 2.0 * ISLE_REACH
		var period := rng.randf_range(_config.ring_period.x, _config.ring_period.y)
		var speed := way * TAU / period
		way = -way
		_data.rings.append(Vector3(inner, outer, speed))
		_ring(rng, k, kinds[k], counts[k], sizes[k], (inner + outer) * 0.5, speed)
		inner = outer + gap
	return true


func _isle_shape(rng: RandomNumberGenerator, radius: float) -> NelvarEarthData.Radial:
	var shape := NelvarEarthData.Radial.new()
	shape.axes = Vector2(radius, radius * rng.randf_range(0.97, 1.0))
	if rng.randf() < 0.5:
		shape.axes = Vector2(shape.axes.y, shape.axes.x)
	_bend(shape, rng, ISLE_WOBBLE, ISLE_WOBBLE * 1.4)
	return shape


func _measure(isle: NelvarCraterData.Isle) -> void:
	isle.inner = INF
	isle.outer = 0.0
	for i in 96:
		var r := isle.shape.radius_at(TAU * i / 96.0)
		isle.inner = minf(isle.inner, r)
		isle.outer = maxf(isle.outer, r)


## Anchors stand round the vent, their outer edges all at anchor_reach.
func _anchors(rng: RandomNumberGenerator, top: float) -> void:
	var count := rng.randi_range(_config.anchors.x, _config.anchors.y)
	var start := rng.randf() * TAU
	var made: Array[NelvarCraterData.Isle] = []
	for i in count:
		for attempt in 20:
			var isle := NelvarCraterData.Isle.new()
			isle.kind = IsleKind.ANCHOR
			isle.shape = _isle_shape(rng, rng.randf_range(_config.anchor_radius.x, top))
			_measure(isle)
			var angle := start + TAU * i / count + rng.randf_range(-0.3, 0.3) * TAU / count
			# Its outer edge at anchor_reach: the inner ring passes it one gap away.
			isle.center = _data.vent + Vector2.from_angle(angle) * (_data.anchor_reach - isle.outer)
			isle.appearance_seed = rng.randi()
			var apart := true
			for other in made:
				if isle.center.distance_to(other.center) < isle.outer + other.outer + 140.0:
					apart = false
			if apart:
				made.append(isle)
				break
	_data.isles.append_array(made)


## The islands of one ring, spread round it with lava between them.
func _ring(rng: RandomNumberGenerator, ring: int, kind: int, count: int, size: float, orbit: float,
		speed: float) -> void:
	var made: Array[NelvarCraterData.Isle] = []
	for i in count:
		var isle := NelvarCraterData.Isle.new()
		isle.kind = kind
		isle.ring = ring
		isle.center = _data.vent
		isle.orbit = orbit
		isle.speed = speed
		isle.shape = _isle_shape(rng, size - rng.randf() * _config.ring_slack)
		_measure(isle)
		isle.appearance_seed = rng.randi()
		if kind == IsleKind.RAFT:
			isle.hold_time = 1.0
		else:
			isle.hold_time = lerpf(3.5, 5.0, clampf((isle.outer - 70.0) / 70.0, 0.0, 1.0))
			isle.sink_period = rng.randf_range(_config.sink_period.x, _config.sink_period.y)
			isle.sink_phase = rng.randf() * isle.sink_period
			isle.sink_under = rng.randf_range(_config.sink_time.x, _config.sink_time.y)
		made.append(isle)
	# Angles: each neighbour at least the smallest spacing away; the rest spread at random.
	var needs := PackedFloat32Array()
	while not made.is_empty():
		needs.clear()
		var total := 0.0
		for i in made.size():
			var a := made[i]
			var b := made[(i + 1) % made.size()]
			var chord := a.outer + b.outer + _config.ring_spacing.x
			var need := 2.0 * asin(minf(1.0, chord / (2.0 * orbit)))
			needs.append(need)
			total += need
		if total < TAU * 0.96 or made.size() == 1:
			break
		made.pop_back()
	var weights := PackedFloat32Array()
	var weight_sum := 0.0
	for i in made.size():
		weights.append(rng.randf_range(0.25, 1.0))
		weight_sum += weights[i]
	var leftover := TAU
	for need in needs:
		leftover -= need
	var angle := rng.randf() * TAU
	for i in made.size():
		made[i].phase = angle
		angle += needs[i] + leftover * weights[i] / weight_sum
	_data.isles.append_array(made)


## Capes along the shore, their tips one gap outside the last ring.
func _capes(rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(_config.capes.x, _config.capes.y)
	var tip_reach := _data.rings[_data.rings.size() - 1].y + _config.ring_gap
	var angles: Array[float] = []
	for attempt in 300:
		if angles.size() >= count:
			break
		var angle := rng.randf() * TAU
		# Short capes first: where the shore lies close to the rings.
		if attempt < 200 and _data.lake.radius_at(angle) - tip_reach > _config.cape_max_length:
			continue
		var apart := true
		for other in angles:
			if absf(angle_difference(angle, other)) < TAU / (count + 1.5):
				apart = false
		if apart:
			angles.append(angle)
	angles.sort()
	for angle in angles:
		var cape := NelvarCraterData.Cape.new()
		cape.angle = angle
		cape.half_width = rng.randf_range(_config.cape_half_width.x, _config.cape_half_width.y)
		cape.tip_width = cape.half_width * rng.randf_range(0.7, 0.85)
		cape.wobble = rng.randf_range(0.03, 0.08)
		cape.wobble_phase = rng.randf() * TAU
		var direction := Vector2.from_angle(angle)
		cape.base = _data.vent + direction * (_data.lake.radius_at(angle) + 50.0)
		cape.tip = _data.vent + direction * (tip_reach + cape.width_at(1.0))
		_data.capes.append(cape)


## Every pair that could meet is sampled over a full turn: nothing may touch, and every
## floating island must come within a run of something (a neighbour, an anchor or a
## cape). An island that does not is dropped.
func _check_gaps() -> void:
	var moving := _data.moving_isles()
	var closest := {}
	var dropped := {}
	for a in moving:
		closest[a] = INF
	for i in moving.size():
		var a := moving[i]
		for j in range(i + 1, moving.size()):
			var b := moving[j]
			if absi(a.ring - b.ring) > 1:
				continue
			var gap := _pair_gap(a, b)
			if gap < NelvarCraterData.MIN_GAP:
				dropped[b] = true
			closest[a] = minf(closest[a], gap)
			closest[b] = minf(closest[b], gap)
		for anchor in _data.anchors():
			if a.ring != 0:
				continue
			var gap := INF
			for s in GAP_SAMPLES:
				gap = minf(gap, NelvarCraterData.isle_gap(a, anchor, TAU / absf(a.speed) * s / GAP_SAMPLES))
			if gap < NelvarCraterData.MIN_GAP:
				dropped[a] = true
			closest[a] = minf(closest[a], gap)
		if a.ring == _data.rings.size() - 1:
			for cape in _data.capes:
				var gap := INF
				for s in GAP_SAMPLES:
					gap = minf(gap, NelvarCraterData.cape_gap(a, cape, TAU / absf(a.speed) * s / GAP_SAMPLES))
				if gap < NelvarCraterData.MIN_GAP:
					dropped[a] = true
				closest[a] = minf(closest[a], gap)
	for a in moving:
		if closest[a] > NelvarCraterData.RUN_GAP:
			dropped[a] = true
	for isle: NelvarCraterData.Isle in dropped:
		_data.isles.erase(isle)


## Smallest gap between two floating islands over the time it takes them to meet again.
static func _pair_gap(a: NelvarCraterData.Isle, b: NelvarCraterData.Isle) -> float:
	if a.ring == b.ring:
		return NelvarCraterData.isle_gap(a, b, 0.0)
	var period := TAU / absf(a.speed - b.speed)
	var best := INF
	for s in GAP_SAMPLES:
		best = minf(best, NelvarCraterData.isle_gap(a, b, period * s / GAP_SAMPLES))
	return best


# --- The rim -----------------------------------------------------------------------

## The summit's edge: the lake's shore plus the rim's width, which bends slowly and
## bulges out at the terraces (the first one in the south, for the spawn).
func _summit(rng: RandomNumberGenerator) -> void:
	var base := rng.randf_range(_config.rim_width.x, _config.rim_width.y)
	var bends: Array[Vector3] = []
	for i in 3:
		bends.append(Vector3(rng.randi_range(2, 7), rng.randf_range(10.0, 26.0), rng.randf() * TAU))
	var count := rng.randi_range(_config.terraces.x, _config.terraces.y)
	var places: Array[Vector3] = []
	for attempt in 120:
		if places.size() >= count:
			break
		var angle := PI * 0.5 + rng.randf_range(-0.22, 0.22) if places.is_empty() else rng.randf() * TAU
		var apart := true
		for other in places:
			if absf(angle_difference(angle, other.x)) < 1.15:
				apart = false
		if apart:
			places.append(Vector3(angle, rng.randf_range(_config.terrace_spread.x, _config.terrace_spread.y),
				rng.randf_range(_config.terrace_bulge.x, _config.terrace_bulge.y)))
	var profile := NelvarCraterData.Profile.new()
	profile.center = _data.lake.center
	profile.axes = _data.lake.axes
	profile.radii.resize(PROFILE_SAMPLES)
	_plain.resize(PROFILE_SAMPLES)
	for i in PROFILE_SAMPLES:
		var angle := TAU * i / PROFILE_SAMPLES
		var width := base
		for bend in bends:
			width += bend.y * sin(bend.x * angle + bend.z)
		width = maxf(width, _config.rim_min)
		_plain[i] = width
		for place in places:
			width += place.z * smoothstep(place.y, place.y * 0.3, absf(angle_difference(angle, place.x)))
		profile.radii[i] = _data.lake.radius_at(angle) + width
	_data.summit = profile
	_data.basin = profile
	_data.boundary = profile.polygon(_config.shore_vertices)
	for place in places:
		_data.terraces.append(Vector2(place.x, place.y))


func _plain_width(angle: float) -> float:
	var t := fposmod(angle, TAU) / TAU * PROFILE_SAMPLES
	var i := int(t) % PROFILE_SAMPLES
	return lerpf(_plain[i], _plain[(i + 1) % PROFILE_SAMPLES], t - floorf(t))


## A point of the rim: `across` 0 at the shore, 1 at the edge.
func _rim_point(angle: float, across: float) -> Vector2:
	var shore := _data.lake.radius_at(angle)
	return _data.vent + Vector2.from_angle(angle) * (shore + _data.rim_width_at(angle) * across)


## On the southern terrace, near the lake: the camera looks north over the lava.
func _spawn() -> void:
	var angle := _data.terraces[0].x
	var shore := _data.lake.radius_at(angle)
	var spot := _data.vent + Vector2.from_angle(angle) * (shore + minf(150.0, _data.rim_width_at(angle) * 0.4))
	# Clear of a cape's root.
	for step in 12:
		if _data.lava_depth(spot) < -110.0:
			break
		spot += Vector2.from_angle(angle) * 20.0
	_data.spawn_position = spot


func _boils(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.boils.x, _config.boils.y)
	var outer := _data.rings[_data.rings.size() - 1].y + _config.ring_gap
	for attempt in 200:
		if _data.boils.size() >= wanted:
			break
		var angle := rng.randf() * TAU
		var shore := _data.lake.radius_at(angle)
		var radius := rng.randf_range(40.0, 76.0)
		var distance := rng.randf_range(outer + 30.0, shore - 70.0) if rng.randf() < 0.6 \
			else rng.randf_range(_data.vent_radius + 150.0, shore - 70.0)
		var center := _data.vent + Vector2.from_angle(angle) * distance
		if _data.lava_depth(center) < radius + 30.0:
			continue
		var apart := true
		for other in _data.boils:
			if center.distance_to(Vector2(other.x, other.y)) < 320.0:
				apart = false
		if apart:
			_data.boils.append(Vector3(center.x, center.y, radius))


# --- Roads --------------------------------------------------------------------------

## A ring of cooled lava along the rim, wandering from side to side (never quite to an
## edge), and spurs from it to the capes' roots and out onto the terraces.
func _flows(rng: RandomNumberGenerator) -> void:
	var ring := NelvarEarthData.Trail.new()
	ring.half_width = rng.randf_range(_config.flow_half_width.x, _config.flow_half_width.y)
	var k1 := rng.randi_range(3, 5)
	var k2 := rng.randi_range(7, 10)
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var steps := 180
	for i in steps + 1:
		var angle := TAU * (i % steps) / steps
		var across := 0.5 + 0.16 * sin(k1 * angle + p1) + 0.07 * sin(k2 * angle + p2)
		var width := _plain_width(angle)
		var shore := _data.lake.radius_at(angle)
		ring.points.append(_data.vent + Vector2.from_angle(angle) * (shore + width * across))
	_data.flows.append(ring)
	for terrace in _data.terraces:
		var from := _nearest_on(ring, _rim_point(terrace.x, 0.5))
		var to := _rim_point(terrace.x + rng.randf_range(-0.3, 0.3) * terrace.y, 0.72)
		_spur(rng, from, to)
	for cape in _data.capes:
		var shore := _data.vent + Vector2.from_angle(cape.angle) * (_data.lake.radius_at(cape.angle) - 30.0)
		var from := _nearest_on(ring, shore)
		_spur(rng, from, shore)


func _nearest_on(flow: NelvarEarthData.Trail, point: Vector2) -> Vector2:
	var best := flow.points[0]
	for i in flow.points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(point, flow.points[i], flow.points[i + 1])
		if closest.distance_to(point) < best.distance_to(point):
			best = closest
	return best


## A short road from `a` to `b` with a gentle bend; dropped if it would leave the rock.
func _spur(rng: RandomNumberGenerator, a: Vector2, b: Vector2) -> void:
	var flow := NelvarEarthData.Trail.new()
	flow.half_width = rng.randf_range(_config.flow_half_width.x, _config.flow_half_width.y) * 0.85
	var normal := a.direction_to(b).orthogonal()
	var bend := rng.randf_range(-0.12, 0.12) * a.distance_to(b)
	var count := maxi(3, int(a.distance_to(b) / 24.0))
	for i in count + 1:
		var t := float(i) / count
		flow.points.append(a.lerp(b, t) + normal * sin(PI * t) * bend)
	for point in flow.points:
		if _data.rim_depth(point) < flow.half_width + 20.0 or _data.lava_depth(point) > -flow.half_width * 0.6:
			return
	_data.flows.append(flow)


# --- Geysers and fumaroles ------------------------------------------------------------

## A few on the capes (springboards to the islands), the rest along the rim, mostly
## near the lake.
func _geysers(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.geysers.x, _config.geysers.y)
	var order: Array[int] = []
	for i in _data.capes.size():
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := order[i]
		order[i] = order[j]
		order[j] = swap
	for c in order:
		if _data.geysers.size() >= mini(_config.cape_geysers, wanted):
			break
		var cape := _data.capes[c]
		var shore := _data.vent + Vector2.from_angle(cape.angle) * _data.lake.radius_at(cape.angle)
		var radius := rng.randf_range(_config.geyser_radius.x, _config.geyser_radius.y)
		var point := shore.lerp(cape.apex(), rng.randf_range(0.42, 0.52))
		if _geyser_fits(point, radius, 26.0):
			_add_geyser(rng, point, radius, c)
	for attempt in 300:
		if _data.geysers.size() >= wanted:
			break
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(_config.geyser_radius.x, _config.geyser_radius.y)
		var point := _data.vent + Vector2.from_angle(angle) * (_data.lake.radius_at(angle) + rng.randf_range(54.0, 120.0))
		if _geyser_fits(point, radius, 34.0) and _data.flow_clearance(point) > radius + 10.0:
			_add_geyser(rng, point, radius, -1)


func _geyser_fits(point: Vector2, radius: float, lava_gap: float) -> bool:
	if not _data.is_open_ground(point, radius + 24.0) or _data.lava_depth(point) > -(radius + lava_gap):
		return false
	if point.distance_to(_data.spawn_position) < _config.geyser_spacing:
		return false
	for other in _data.geysers:
		if point.distance_to(other.position) < _config.geyser_spacing:
			return false
	return true


func _add_geyser(rng: RandomNumberGenerator, point: Vector2, radius: float, cape: int) -> void:
	var geyser := NelvarCraterData.Geyser.new()
	geyser.position = point
	geyser.radius = radius
	geyser.period = rng.randf_range(_config.geyser_period.x, _config.geyser_period.y)
	geyser.phase = rng.randf() * geyser.period
	geyser.cape = cape
	_data.geysers.append(geyser)


## Fumarole fields on the broad places (not the spawn's terrace): vents over yellow
## sulfur under a bank of smoke.
func _vents(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.vent_fields.x, _config.vent_fields.y)
	var places: Array[float] = []
	for i in range(1, _data.terraces.size()):
		places.append(_data.terraces[i].x)
	for i in 6:
		places.append(rng.randf() * TAU)
	for angle in places:
		if _data.smoke_banks.size() >= wanted:
			break
		var radius := rng.randf_range(100.0, 140.0)
		var center := _rim_point(angle, 0.55)
		if _data.rim_width_at(angle) < radius * 1.6 or center.distance_to(_data.spawn_position) < radius + 380.0:
			continue
		var apart := true
		for other in _data.smoke_banks:
			if center.distance_to(Vector2(other.x, other.y)) < radius + other.z + 500.0:
				apart = false
		if not apart:
			continue
		var vents := 0
		var count := rng.randi_range(_config.vents_per_field.x, _config.vents_per_field.y)
		for k in count * 14:
			if vents >= count:
				break
			var point := center + Vector2.from_angle(rng.randf() * TAU) * radius * 0.7 * sqrt(rng.randf())
			var vent := NelvarFireData.Thing.new()
			vent.kind = Kind.VENT
			vent.radius = rng.randf_range(13.0, 20.0)
			vent.position = point
			vent.accent = rng.randf() < 0.35
			vent.appearance_seed = rng.randi()
			if _fits(point, vent.radius + 8.0, false, 6.0, 40.0, 1.6):
				_add(vent)
				vents += 1
		if vents > 0:
			_data.smoke_banks.append(Vector3(center.x, center.y, radius))


# --- Placement rules ------------------------------------------------------------

func _add(thing: NelvarFireData.Thing) -> void:
	_data.things.append(thing)
	var cell := Vector2i((thing.position / GRID).floor())
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append(thing)


func _nearby(point: Vector2, reach: float) -> Array:
	var result := []
	var from := Vector2i(((point - Vector2.ONE * reach) / GRID).floor())
	var to := Vector2i(((point + Vector2.ONE * reach) / GRID).floor())
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			result.append_array(_grid.get(Vector2i(x, y), []))
	return result


## Shared rules for anything on the rim or an anchor. `trail_gap` is the free ground kept
## beside roads (negative: none), `lava_gap` the ground kept from lava. Solid things keep
## a passage between each other; the ring road keeps the way round free of them.
func _fits(point: Vector2, radius: float, solid: bool, trail_gap: float, lava_gap: float,
		plant_spacing: float = 0.7) -> bool:
	if _data.rim_depth(point) < radius + (18.0 if solid else 10.0):
		return false
	if _data.lava_depth(point) > -(radius + lava_gap):
		return false
	var spawn_gap := _config.spawn_clearance if solid else 50.0
	if point.distance_to(_data.spawn_position) < spawn_gap + radius:
		return false
	for geyser in _data.geysers:
		if point.distance_to(geyser.position) < geyser.radius + radius + (40.0 if solid else 16.0):
			return false
	if trail_gap >= 0.0 and _data.flow_clearance(point) < radius + trail_gap:
		return false
	for other: NelvarFireData.Thing in _nearby(point, 200.0):
		var distance := point.distance_to(other.position)
		if other.solid and solid:
			if distance < radius + other.spread() + _config.passage_width:
				return false
		elif other.solid or solid:
			if distance < (radius + other.spread()) * 0.85:
				return false
		elif distance < (radius + other.radius) * plant_spacing:
			return false
		if other.crown_hides(point, radius * 0.3):
			return false
	return true


## A random point of the rim, or of an anchor now and then.
func _random_ground(rng: RandomNumberGenerator, anchors_share: float = 0.0) -> Vector2:
	var anchors := _data.anchors()
	if not anchors.is_empty() and rng.randf() < anchors_share:
		var anchor := anchors[rng.randi_range(0, anchors.size() - 1)]
		return anchor.center + Vector2.from_angle(rng.randf() * TAU) * anchor.inner * 0.8 * sqrt(rng.randf())
	return _rim_point(rng.randf() * TAU, rng.randf_range(0.06, 0.94))


func _rocks(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.rocks.x, _config.rocks.y)
	var placed := 0
	for attempt in wanted * 16:
		if placed >= wanted:
			break
		var radius := rng.randf_range(28.0, 40.0) if rng.randf() < 0.2 else rng.randf_range(14.0, 26.0)
		var roll := rng.randf()
		var look := Stone.PLAIN if roll < 0.5 else (Stone.ASHEN if roll < 0.82 else Stone.EMBER)
		# A third of them sit near the edge, where the slope begins.
		var point := _rim_point(rng.randf() * TAU, rng.randf_range(0.7, 0.92)) if rng.randf() < 0.33 \
			else _random_ground(rng)
		if _try_rock(rng, point, radius, look, 30.0):
			placed += 1
	for anchor in _data.anchors():
		var count := rng.randi_range(_config.anchor_rocks.x, _config.anchor_rocks.y)
		var done := 0
		for attempt in count * 20:
			if done >= count:
				break
			var radius := rng.randf_range(16.0, 30.0)
			var point := anchor.center + Vector2.from_angle(rng.randf() * TAU) * anchor.inner * 0.6 * sqrt(rng.randf())
			if _try_rock(rng, point, radius, Stone.EMBER if rng.randf() < 0.5 else Stone.PLAIN, 34.0):
				done += 1


func _try_rock(rng: RandomNumberGenerator, point: Vector2, radius: float, look: int, lava_gap: float) -> bool:
	if not _fits(point, radius, true, _config.path_clearance, lava_gap):
		return false
	var rock := NelvarFireData.Thing.new()
	rock.kind = Kind.ROCK
	rock.variant = look
	rock.position = point
	rock.radius = radius
	rock.solid = true
	rock.appearance_seed = rng.randi()
	_add(rock)
	return true


## Blue-green crystals by the vents, the geysers and at the foot of boulders.
func _crystals(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.crystal_clusters.x, _config.crystal_clusters.y)
	var rocks: Array[NelvarFireData.Thing] = []
	for thing in _data.things:
		if thing.kind == Kind.ROCK:
			rocks.append(thing)
	var placed := 0
	for attempt in wanted * 24:
		if placed >= wanted:
			break
		var point := _random_ground(rng, 0.15)
		var roll := rng.randf()
		if roll < 0.3 and not _data.geysers.is_empty():
			var geyser := _data.geysers[rng.randi_range(0, _data.geysers.size() - 1)]
			point = geyser.position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(70.0, 120.0)
		elif roll < 0.8 and not rocks.is_empty():
			var rock := rocks[rng.randi_range(0, rocks.size() - 1)]
			point = rock.position + Vector2.from_angle(rng.randf_range(-0.3, PI + 0.3)) \
				* (rock.spread() + rng.randf_range(50.0, 80.0))
		var crystal := NelvarFireData.Thing.new()
		crystal.kind = Kind.CRYSTALS
		crystal.radius = rng.randf_range(12.0, 20.0)
		crystal.position = point
		crystal.solid = true
		crystal.variant = rng.randi_range(0, 1)
		crystal.appearance_seed = rng.randi()
		if _fits(point, crystal.radius, true, _config.path_clearance, 30.0):
			_add(crystal)
			placed += 1


## Snags of burnt trunks (сухостой), and the odd charred tree.
func _snags(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.snags.x, _config.snags.y)
	var placed := 0
	for attempt in wanted * 20:
		if placed >= wanted:
			break
		var snag := NelvarFireData.Thing.new()
		snag.kind = Kind.SNAG
		snag.solid = true
		snag.position = _random_ground(rng)
		snag.radius = rng.randf_range(13.0, 19.0)
		snag.size = Vector2(0.0, rng.randf_range(34.0, 64.0))
		snag.accent = rng.randf() < 0.5
		snag.appearance_seed = rng.randi()
		if _fits(snag.position, snag.radius, true, _config.path_clearance, 40.0):
			_add(snag)
			placed += 1
	var trees := rng.randi_range(_config.trees.x, _config.trees.y)
	var grown := 0
	for attempt in trees * 30:
		if grown >= trees:
			break
		var tree := NelvarFireData.Thing.new()
		tree.kind = Kind.TREE
		tree.variant = Species.CHARRED if rng.randf() < 0.6 else Species.SMOULDERING
		tree.solid = true
		var scale := rng.randf()
		tree.radius = lerpf(TRUNK.x, TRUNK.y, scale)
		tree.size = Vector2(lerpf(CROWN.x, CROWN.y, scale), lerpf(HEIGHT.x, HEIGHT.y, rng.randf()))
		tree.position = _rim_point(rng.randf() * TAU, rng.randf_range(0.25, 0.75))
		tree.accent = tree.variant == Species.SMOULDERING
		tree.appearance_seed = rng.randi()
		if _fits(tree.position, tree.radius, true, _config.path_clearance, 60.0) and _crown_is_clear(tree):
			_add(tree)
			grown += 1


func _crown_is_clear(tree: NelvarFireData.Thing) -> bool:
	for other: NelvarFireData.Thing in _nearby(tree.crown_center(), tree.size.x + 120.0):
		if other.kind != Kind.TREE and tree.crown_hides(other.position):
			return false
	return true


## Ember grass along the lava, ash flowers in the open and by the roads, scorched shrubs
## at the foot of stones and snags.
func _plants(rng: RandomNumberGenerator) -> void:
	var hosts: Array[NelvarFireData.Thing] = []
	for thing in _data.things:
		if thing.kind in [Kind.ROCK, Kind.SNAG, Kind.TREE]:
			hosts.append(thing)
	var by_lava := func() -> Vector2:
		var anchors := _data.anchors()
		if rng.randf() < 0.2 and not anchors.is_empty():
			var anchor := anchors[rng.randi_range(0, anchors.size() - 1)]
			return anchor.center + Vector2.from_angle(rng.randf() * TAU) * (anchor.inner - rng.randf_range(24.0, 60.0))
		# On the shore: _scatter moves it in off the lava.
		return _rim_point(rng.randf() * TAU, 0.0)
	var in_open := func() -> Vector2:
		if rng.randf() < 0.4 and not _data.flows.is_empty():
			var flow := _data.flows[rng.randi_range(0, _data.flows.size() - 1)]
			var i := rng.randi_range(0, flow.points.size() - 2)
			var along := flow.points[i].lerp(flow.points[i + 1], rng.randf())
			var side := flow.points[i].direction_to(flow.points[i + 1]).orthogonal()
			return along + side * (1.0 if rng.randf() < 0.5 else -1.0) * (flow.half_width + rng.randf_range(16.0, 40.0))
		return _random_ground(rng, 0.1)
	var by_host := func() -> Vector2:
		if hosts.is_empty():
			return _random_ground(rng)
		var host: NelvarFireData.Thing = hosts[rng.randi_range(0, hosts.size() - 1)]
		return host.position + Vector2.from_angle(rng.randf_range(-0.2, PI + 0.2)) \
			* (host.spread() + rng.randf_range(14.0, 46.0))
	_scatter(rng, Kind.EMBER_GRASS, rng.randi_range(_config.ember_grass.x, _config.ember_grass.y),
		Vector2(12.0, 20.0), 2, by_lava, 2.0, 14.0)
	_scatter(rng, Kind.ASH_FLOWER, rng.randi_range(_config.ash_flowers.x, _config.ash_flowers.y),
		Vector2(10.0, 16.0), 3, in_open, 0.0, 30.0)
	_scatter(rng, Kind.SHRUB, rng.randi_range(_config.shrubs.x, _config.shrubs.y),
		Vector2(16.0, 24.0), 2, by_host, 4.0, 30.0)


func _scatter(rng: RandomNumberGenerator, kind: Kind, count: int, radius_range: Vector2,
		variants: int, pick: Callable, trail_gap: float, lava_gap: float) -> void:
	var placed := 0
	for attempt in count * 14:
		if placed >= count:
			break
		var point: Vector2 = pick.call()
		var radius := rng.randf_range(radius_range.x, radius_range.y)
		# Ember grass hugs the shore: pushed in from the lava's edge by its own size.
		if kind == Kind.EMBER_GRASS:
			var depth := _data.lava_depth(point)
			if depth > -(radius + lava_gap):
				var away := Vector2(_data.lava_depth(point + Vector2(4, 0)) - _data.lava_depth(point - Vector2(4, 0)),
					_data.lava_depth(point + Vector2(0, 4)) - _data.lava_depth(point - Vector2(0, 4)))
				if away.length_squared() > 0.0001:
					point -= away.normalized() * (depth + radius + lava_gap + rng.randf_range(2.0, 40.0))
		if not _fits(point, radius, false, trail_gap, lava_gap):
			continue
		var plant := NelvarFireData.Thing.new()
		plant.kind = kind
		plant.position = point
		plant.radius = radius
		plant.variant = rng.randi_range(0, variants - 1)
		plant.accent = rng.randf() < 0.5
		plant.appearance_seed = rng.randi()
		_add(plant)
		placed += 1
