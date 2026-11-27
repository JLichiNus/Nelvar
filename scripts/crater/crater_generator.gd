class_name NelvarCraterGenerator
extends RefCounted
## Lays out the volcano from a seed: the crater lake and its vent, the capes reaching
## into it, the broad rim with its terraces, the spawn on the southern terrace, boiling
## patches, broad floes of magma crust sharing out the lake and stones of crust in the
## open lava (some of the stones sink now and then and come up again), roads of cooled
## lava (a ring along the rim, spurs to the capes and terraces), geysers, fumaroles under
## smoke banks, and the rocks, snags and few plants of the top.
##
## Every stage draws from its own seeded generator, so changing one leaves the others.

const Kind = NelvarFireData.Kind
const Species = NelvarFireData.Species
const Stone = NelvarFireData.Stone

const GRID := 160.0
const PROFILE_SAMPLES := 1440
## Stones: tries along the shore, misses before a floe stops growing others; the grid
## floes are filed by (their places).
const FLOE_SHORE_TRIES := 90
const FLOE_MISSES := 10
const FLOE_CELL := 256.0
## Broad floes: darts thrown for their places, how round their corners are, the step of
## the march out along each ray from a place, and how long a ford runs along its channel.
const ISLE_DARTS := 2400
const ISLE_ROUND := 140.0
const ISLE_MARCH := 12.0
const FORD_REACH := 40.0
## Passes of the blur a broad floe's outline is held under (_isle_outline).
const ISLE_BLUR := 2
## The gap a broad floe no step reaches swells out to (_reach_out): to a floe, and to the
## shore (between the reach + 10 a floe keeps from it and a run less the reach).
const REACH_FLOE := 22.0
const REACH_SHORE := 27.0
## A broad floe keeps within this many of its place's reach (a soft, warped disc): the
## far corners of its share are trimmed and it rounds into a blob. Within FORD_PULL of a
## ford it reaches further, out to the ford: a tongue of crust a step from the other side.
const ISLE_BULK := 1.3
const FORD_PULL := 300.0
const TRUNK := Vector2(11.0, 15.0)
const CROWN := Vector2(34.0, 50.0)
const HEIGHT := Vector2(150.0, 200.0)

var _config: NelvarCraterConfig
var _data: NelvarCraterData
var _grid := {}
## Rim width without the terraces, per profile sample.
var _plain := PackedFloat32Array()
## Broad floes while they are made: places (x, y, reach), the places near each, the
## fords of each place's channels and the shore's fords (directions).
var _sites: Array[Vector3] = []
var _site_near: Array[PackedInt32Array] = []
var _site_fords: Array[PackedVector2Array] = []
## The same, ready for _isle_margin: places, their reach squared (the power diagram's
## weights), and per neighbour 1 / (2 × the distance to it).
var _site_centers := PackedVector2Array()
var _site_weights := PackedFloat32Array()
var _site_lines: Array[PackedFloat32Array] = []
var _shore_fords := PackedFloat32Array()
## The warp bending the lines between the broad floes, the wander of their channels'
## width and of the ring of open lava along the shore.
var _warp_x := FastNoiseLite.new()
var _warp_y := FastNoiseLite.new()
var _narrow := FastNoiseLite.new()
var _ring := FastNoiseLite.new()
## The broadest floe so far: how far to look for a floe's neighbours.
var _widest := 0.0


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
	_capes(_rng("capes"))
	_summit(_rng("summit"))
	_spawn()
	_boils(_rng("boils"))
	_floes(_rng("floes"))
	_data.index_floes()
	_flows(_rng("flows"))
	_data.index_flows()
	_geysers(_rng("geysers"))
	_vents(_rng("vents"))
	_rocks(_rng("rocks"))
	_crystals(_rng("crystals"))
	_snags(_rng("snags"))
	_plants(_rng("plants"))
	_data.finish()
	for i in _data.floes.size():
		_data.floes[i].id = i
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


# --- The lake and its floes ------------------------------------------------------

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


## Capes along the shore, reaching into the lake.
func _capes(rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(_config.capes.x, _config.capes.y)
	var angles: Array[float] = []
	for attempt in 300:
		if angles.size() >= count:
			break
		var angle := rng.randf() * TAU
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
		var length := rng.randf_range(_config.cape_length.x, _config.cape_length.y)
		cape.tip = _data.vent + direction * (_data.lake.radius_at(angle) - length + cape.width_at(1.0))
		_data.capes.append(cape)


## Floes of magma crust. The broad ones share out the lake (_isles); stones, small floes,
## lie in the open lava left between them and the shore, each a step from the shore or
## from a floe (_stones). One can walk from the shore to every floe and to the vent's
## moat, no step wider than a run. All of them sway on one slow swell: its wave is far
## longer than a floe, so neighbours sway almost together and the steps between them
## hold. Wherever the swell takes it, a floe stays in the lava, clear of the shore, the
## capes, the vent's moat, the boiling patches and the other floes. Some of the stones
## (more of the small ones) sink now and then and come up again.
func _floes(rng: RandomNumberGenerator) -> void:
	var drift := Vector4(rng.randf_range(_config.floe_drift.x, _config.floe_drift.y),
		rng.randf_range(_config.floe_drift.x, _config.floe_drift.y),
		TAU / rng.randf_range(_config.floe_period.x, _config.floe_period.y),
		TAU / rng.randf_range(_config.floe_period.x, _config.floe_period.y))
	var wave := TAU / _config.floe_swell
	var wave_x := Vector2.from_angle(rng.randf() * TAU) * wave
	var wave_y := Vector2.from_angle(rng.randf() * TAU) * wave
	var base := Vector2(rng.randf() * TAU, rng.randf() * TAU)
	var place := func(floe: NelvarCraterData.Isle) -> void:
		floe.drift = drift
		floe.drift_phase = base + Vector2(wave_x.dot(floe.center), wave_y.dot(floe.center))
	var reach := Vector2(drift.x, drift.y).length()
	var cells := {}
	_widest = 0.0
	_isles(rng, place, reach)
	for floe in _data.floes:
		_file_floe(floe, cells)
	_stones(rng, place, reach, cells)
	_keep_floes_on_foot(cells, reach)
	for floe in _data.floes:
		if floe.broad:
			continue
		var share := _config.sinking_share * lerpf(1.3, 0.7, inverse_lerp(_config.floe_radius.x, _config.floe_radius.y * 1.2, floe.outer))
		if rng.randf() < share:
			floe.sink_period = rng.randf_range(_config.sink_period.x, _config.sink_period.y)
			floe.sink_phase = rng.randf() * floe.sink_period
			floe.sink_under = rng.randf_range(_config.sink_time.x, _config.sink_time.y)


## The broad floes. Places are scattered over the lake, each with its own reach, and the
## lake is shared out between them, the bigger taking more (a power diagram), along
## lines bent by a slow warp. Between neighbours runs a channel of lava, a step wide at
## its ford (where the two shares meet in the middle) and wandering up to channel.y
## elsewhere; along the shore lies a ring of open lava, a step wide at the shore's fords;
## the vent's moat and the boiling patches stay open. Corners are rounded. A floe is the
## part of its share seen from its place (a fine table of radii); where the warp
## squeezed a channel, the two give way to each other.
func _isles(rng: RandomNumberGenerator, place: Callable, reach: float) -> void:
	for noise: FastNoiseLite in [_warp_x, _warp_y, _narrow, _ring]:
		noise.seed = rng.randi()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 2
		noise.fractal_lacunarity = 2.5
		noise.fractal_gain = 0.3
	# One slow octave: the lines bend in broad curves, not in jags.
	for noise: FastNoiseLite in [_warp_x, _warp_y]:
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		noise.frequency = 1.0 / 640.0
	_narrow.frequency = 1.0 / 240.0
	_ring.frequency = 1.0 / 300.0
	_shore_fords.clear()
	var fords := rng.randi_range(_config.shore_fords.x, _config.shore_fords.y)
	var first := rng.randf() * TAU
	for i in fords:
		_shore_fords.append(first + TAU * (i + rng.randf_range(-0.3, 0.3)) / fords)
	# Places: darts over the lake, each with its own reach, well in from the open lava.
	_sites.clear()
	var span := _data.lake.reach()
	for dart in ISLE_DARTS:
		var size := rng.randf_range(_config.isle_reach.x, _config.isle_reach.y)
		var point := _data.vent + Vector2(rng.randf_range(-span, span), rng.randf_range(-span, span))
		if _open_lava(point, reach) < size * 0.4:
			continue
		var apart := true
		for site in _sites:
			if point.distance_to(Vector2(site.x, site.y)) < (size + site.z) * 0.9:
				apart = false
				break
		if apart:
			_sites.append(Vector3(point.x, point.y, size))
	var count := _sites.size()
	_site_near.resize(count)
	_site_fords.resize(count)
	_site_lines.resize(count)
	_site_centers.resize(count)
	_site_weights.resize(count)
	for i in count:
		_site_near[i] = PackedInt32Array()
		_site_fords[i] = PackedVector2Array()
		_site_lines[i] = PackedFloat32Array()
		_site_centers[i] = _site_at(i)
		_site_weights[i] = _sites[i].z * _sites[i].z
	for i in count:
		for j in range(i + 1, count):
			var distance := _site_at(i).distance_to(_site_at(j))
			if distance < (_sites[i].z + _sites[j].z) * 2.0:
				_site_near[i].append(j)
				_site_near[j].append(i)
				_site_lines[i].append(0.5 / distance)
				_site_lines[j].append(0.5 / distance)
	for i in count:
		for j in _site_near[i]:
			if j > i:
				var ford := _ford(i, j)
				if ford.is_finite():
					_site_fords[i].append(ford)
					_site_fords[j].append(ford)
	# The shore's fords: the nearest floe reaches out to a step from the shore there.
	for angle in _shore_fords:
		var ford := _data.vent + Vector2.from_angle(angle) * (_data.lake.radius_at(angle)
			- _config.shore_ring.x - reach - 30.0)
		var nearest := -1
		for i in count:
			if nearest < 0 or ford.distance_to(_site_at(i)) - _sites[i].z < ford.distance_to(_site_at(nearest)) - _sites[nearest].z:
				nearest = i
		if nearest >= 0:
			_site_fords[nearest].append(ford)
	var isles: Array[NelvarCraterData.Isle] = []
	for i in count:
		if _isle_margin(i, _site_at(i), reach) <= 0.0:
			continue
		var floe := NelvarCraterData.Isle.new()
		floe.broad = true
		floe.center = _site_at(i)
		floe.radii = _isle_outline(i, reach)
		floe.tabulate()
		floe.appearance_seed = rng.randi()
		place.call(floe)
		isles.append(floe)
	_part_isles(isles)
	_data.floes.append_array(isles)
	_sites.clear()
	_site_near.clear()
	_site_fords.clear()
	_site_lines.clear()


func _site_at(i: int) -> Vector2:
	return Vector2(_sites[i].x, _sites[i].y)


func _warp(point: Vector2) -> Vector2:
	return Vector2(_warp_x.get_noise_2dv(point), _warp_y.get_noise_2dv(point)) * _config.isle_wander


## Where the channel between two neighbouring places is a step: the middle of the line
## their shares meet on (unless a third place takes it), brought back through the warp.
## INF when they do not meet.
func _ford(i: int, j: int) -> Vector2:
	var a := _site_at(i)
	var b := _site_at(j)
	var wa := _sites[i].z * _sites[i].z
	var wb := _sites[j].z * _sites[j].z
	var t := clampf(0.5 + (wa - wb) / (2.0 * a.distance_squared_to(b)), 0.15, 0.85)
	var middle := a.lerp(b, t)
	var power := middle.distance_squared_to(a) - wa
	for k in _site_near[i]:
		if k != j and middle.distance_squared_to(_site_at(k)) - _sites[k].z * _sites[k].z < power:
			return Vector2.INF
	var point := middle
	for step in 3:
		point = middle - _warp(point)
	return point


## Positive on place i's broad floe, roughly world units: in its share of the lake with
## half a channel to spare from every neighbour's, within its bulk, and in the open lava
## (_open_lava), the corners rounded over ISLE_ROUND. The channel's width wanders between
## channel.x and channel.y and narrows to a step at the fords (both sides of a channel
## read the same, so they never overlap); round each ford a smooth hump (no point at its
## top) lets the floe reach out to it, so the tongue ends round.
func _isle_margin(i: int, point: Vector2, reach: float) -> float:
	var own := _site_centers[i]
	var warped := point + _warp(point)
	var width := lerpf(_config.channel.x, _config.channel.y, smoothstep(0.25, 0.75, _narrow.get_noise_2dv(point) * 0.5 + 0.5))
	var pull := 0.0
	for ford in _site_fords[i]:
		var near := point.distance_squared_to(ford)
		if near < FORD_PULL * FORD_PULL:
			if near < 9.0 * FORD_REACH * FORD_REACH:
				width = lerpf(width, _config.channel.x, _hump(sqrt(near), FORD_REACH))
			near = 1.0 - near / (FORD_PULL * FORD_PULL)
			pull = maxf(pull, near * near * FORD_PULL)
	var half := width * 0.5
	var power := warped.distance_squared_to(own) - _site_weights[i]
	var margin := INF
	var near_sites := _site_near[i]
	var lines := _site_lines[i]
	for n in near_sites.size():
		var j := near_sites[n]
		var line := (warped.distance_squared_to(_site_centers[j]) - _site_weights[j] - power) * lines[n]
		margin = _smooth_min(margin, line - half, ISLE_ROUND)
	margin = _smooth_min(margin, _sites[i].z * ISLE_BULK + pull * 1.2 - warped.distance_to(own), ISLE_ROUND)
	return _smooth_min(margin, _open_lava(point, reach), ISLE_ROUND)


## How far a point lies inside the lava the broad floes may take (positive inside): in
## from the ring of open lava along the shore, out of the vent's moat and the boiling
## patches, with the swell's reach to spare.
func _open_lava(point: Vector2, reach: float) -> float:
	var room := point.distance_to(_data.vent) - (_data.vent_radius + _config.vent_moat + reach)
	# Far in from the shore the ring's wander cannot matter: its widest will do.
	var shore := _data.lava_depth(point) - reach - _config.shore_ring.y
	if shore < 500.0:
		shore += _config.shore_ring.y - _ring_at(point)
	room = _smooth_min(room, shore, ISLE_ROUND)
	for boil in _data.boils:
		room = _smooth_min(room, point.distance_to(Vector2(boil.x, boil.y)) - (boil.z + reach + 10.0), ISLE_ROUND)
	return room


## Width of the open lava along the shore in the direction of `point`: wandering between
## shore_ring.x and shore_ring.y round the lake, a step at the shore's fords.
func _ring_at(point: Vector2) -> float:
	var angle := (point - _data.vent).angle()
	var n := _ring.get_noise_2d(cos(angle) * 500.0, sin(angle) * 500.0) * 0.5 + 0.5
	var ring := lerpf(_config.shore_ring.x, _config.shore_ring.y, smoothstep(0.3, 0.7, n))
	var shore := _data.lake.radius_at(angle)
	for ford in _shore_fords:
		ring = lerpf(ring, _config.shore_ring.x, _hump(absf(angle_difference(angle, ford)) * shore, FORD_REACH * 4.0))
	return ring


## 1 within `flat` of a ford, easing down to 0 over twice as much: no corner anywhere, so
## the floes round off where they come close.
static func _hump(distance: float, flat: float) -> float:
	var t := clampf((distance - flat) / (flat * 2.0), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## Radii of place i's broad floe: out along each ray to where it first ends (marched in
## steps of a share of the margin, at least ISLE_MARCH, then halved down to a fraction
## of a unit). Then no ray runs out further than a little past the blurred outline: thin
## spikes and slivers between two neighbours' shares are cut back and steps round off
## (radii only shrink: nothing comes closer to anything).
func _isle_outline(i: int, reach: float) -> PackedFloat32Array:
	var center := _site_at(i)
	var count := NelvarCraterData.ISLE_SAMPLES
	var radii := PackedFloat32Array()
	radii.resize(count)
	var at_center := _isle_margin(i, center, reach)
	for k in count:
		var direction := Vector2.from_angle(TAU * k / count)
		var inside := 0.0
		var outside := 0.0
		var margin := at_center
		while margin > 0.0 and outside < 2400.0:
			inside = outside
			outside += maxf(margin * 0.4, ISLE_MARCH)
			margin = _isle_margin(i, center + direction * outside, reach)
		for halving in 5:
			var middle := (inside + outside) * 0.5
			if _isle_margin(i, center + direction * middle, reach) > 0.0:
				inside = middle
			else:
				outside = middle
		radii[k] = inside
	var blurred := radii.duplicate()
	var weights := [1.0, 2.0, 3.0, 4.0, 3.0, 2.0, 1.0]
	for blur_pass in ISLE_BLUR:
		var source := blurred.duplicate()
		for k in count:
			var sum := 0.0
			for o in 7:
				sum += source[(k + o - 3 + count) % count] * weights[o]
			blurred[k] = sum / 16.0
	for k in count:
		radii[k] = minf(radii[k], blurred[k] + 6.0)
	return radii


## Where the warp squeezed a channel, the two broad floes give way to each other until
## MIN_GAP is left however the swell moves them.
func _part_isles(isles: Array[NelvarCraterData.Isle]) -> void:
	for round_index in 6:
		var moved := false
		for a in isles.size():
			for b in range(a + 1, isles.size()):
				var first := isles[a]
				var second := isles[b]
				if first.center.distance_to(second.center) > first.outer + second.outer + 40.0:
					continue
				if _give_way(first, second):
					moved = true
				if _give_way(second, first):
					moved = true
		if not moved:
			break


## Pulls `a`'s outline back wherever it comes closer than MIN_GAP to `b`'s, wherever the
## swell takes them.
func _give_way(a: NelvarCraterData.Isle, b: NelvarCraterData.Isle) -> bool:
	var sway := NelvarCraterData.sway_between(a, b)
	var offset := b.center - a.center
	var moved := false
	for k in a.radii.size():
		var point := a.outline[k] - offset
		var gap := point.length() - b.radius_at(point.angle())
		if gap > NelvarCraterData.MIN_GAP + sway * 3.0 + 12.0:
			continue
		for s in 8:
			var shifted := point - Vector2.from_angle(TAU * s / 8.0) * sway
			gap = minf(gap, shifted.length() - b.radius_at(shifted.angle()))
		if gap < NelvarCraterData.MIN_GAP + 1.0:
			a.radii[k] = maxf(a.radii[k] - (NelvarCraterData.MIN_GAP + 1.0 - gap) * 0.6 - 0.5, 0.0)
			moved = true
	if moved:
		a.tabulate()
	return moved


## The narrowest gap between two floes wherever the swell takes them: floe_gap's measure
## at their places and shifted by the sway between them every way round (near a steep
## wall of a lobed outline the measure leaps with a small shift).
static func _clearance(a: NelvarCraterData.Isle, b: NelvarCraterData.Isle) -> float:
	var sway := NelvarCraterData.sway_between(a, b)
	var offset := b.center - a.center
	var best := NelvarCraterData.gap_at(a, b, offset)
	for s in 8:
		best = minf(best, NelvarCraterData.gap_at(a, b, offset + Vector2.from_angle(TAU * s / 8.0) * sway))
	return best


static func _smooth_min(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


## Stones: small floes in the open lava, a step from the shore where the ring along it is
## wide, and a step from the broad floes and from each other in the pools between them;
## `stones` of them at most.
func _stones(rng: RandomNumberGenerator, place: Callable, reach: float, cells: Dictionary) -> void:
	var wanted := rng.randi_range(_config.stones.x, _config.stones.y)
	var frontier: Array[NelvarCraterData.Isle] = []
	var misses: Array[int] = []
	for floe in _data.floes:
		frontier.append(floe)
		misses.append(0)
	var sow := func(floe: NelvarCraterData.Isle) -> bool:
		place.call(floe)
		if not _floe_fits(floe, cells):
			return false
		_add_floe(floe, cells)
		frontier.append(floe)
		misses.append(0)
		return true
	var placed := 0
	# Along the shore first: a step from it however the swell moves the stone.
	for i in FLOE_SHORE_TRIES:
		if placed * 2 >= wanted:
			break
		var angle := rng.randf() * TAU
		var floe := _floe_shape(rng)
		floe.center = _data.vent + Vector2.from_angle(angle) * (_data.lake.radius_at(angle)
			- floe.radius_at(angle) - reach - rng.randf_range(10.5, 14.0))
		if sow.call(floe):
			placed += 1
	# Then each beside a floe already there.
	for attempt in wanted * 80:
		if placed >= wanted or frontier.is_empty():
			break
		var k := rng.randi() % frontier.size()
		var parent := frontier[k]
		var floe := _floe_shape(rng)
		var angle := rng.randf() * TAU
		var gap := rng.randf_range(_config.floe_gap.x, _config.floe_gap.y)
		floe.center = parent.center + Vector2.from_angle(angle) * (parent.radius_at(angle) + gap
			+ floe.radius_at(angle + PI))
		if sow.call(floe):
			placed += 1
		else:
			misses[k] += 1
			if misses[k] >= FLOE_MISSES:
				frontier.remove_at(k)
				misses.remove_at(k)


## Only the floes one can walk to from the shore stay: steps of at most a run however the
## swell moves them. A broad floe no step reaches (its fords fell where a third share or
## the open lava took them) first reaches out (_reach_out); a floe still walled off goes.
func _keep_floes_on_foot(cells: Dictionary, reach: float) -> void:
	var reached := _on_foot(cells, reach)
	for attempt in 3:
		var grew := false
		for floe in _data.floes:
			if floe.broad and not reached.has(floe) and _reach_out(floe, reached, cells, reach):
				grew = true
		if not grew:
			break
		reached = _on_foot(cells, reach)
	var kept: Array[NelvarCraterData.Isle] = []
	for floe in _data.floes:
		if reached.has(floe):
			kept.append(floe)
	_data.floes = kept


## The floes one can walk to from the shore, in steps of at most a run however the swell
## moves them.
func _on_foot(cells: Dictionary, reach: float) -> Dictionary:
	var reached := {}
	var queue: Array[NelvarCraterData.Isle] = []
	for floe in _data.floes:
		if _data.lava_depth(floe.center) > floe.outer + NelvarCraterData.RUN_GAP + 20.0:
			continue
		for point in floe.outline:
			if _data.lava_depth(floe.center + point) <= NelvarCraterData.RUN_GAP - reach:
				reached[floe] = true
				queue.append(floe)
				break
	while not queue.is_empty():
		var floe: NelvarCraterData.Isle = queue.pop_back()
		var around := floe.outer + _widest + NelvarCraterData.RUN_GAP
		var lo := ((floe.center - Vector2.ONE * around) / FLOE_CELL).floor()
		var hi := ((floe.center + Vector2.ONE * around) / FLOE_CELL).floor()
		for y in range(int(lo.y), int(hi.y) + 1):
			for x in range(int(lo.x), int(hi.x) + 1):
				for other: NelvarCraterData.Isle in cells.get(Vector2i(x, y), []):
					var offset := other.center - floe.center
					var distance := offset.length()
					if reached.has(other) or distance > floe.outer + other.outer + NelvarCraterData.RUN_GAP:
						continue
					var step := NelvarCraterData.RUN_GAP - NelvarCraterData.sway_between(floe, other)
					# The line between them first: the gap is never wider there.
					var angle := offset.angle()
					if distance - floe.radius_at(angle) - other.radius_at(angle + PI) <= step \
							or NelvarCraterData.floe_gap(floe, other, 0.0) <= step:
						reached[other] = true
						queue.append(other)
	return reached


## A broad floe no step reaches swells out where it comes nearest a floe one can walk to
## (to a gap of REACH_FLOE) or the shore (REACH_SHORE), in a smooth bulge over a few rays.
## It stays only if the floe still keeps clear of everything; else the outline is put back.
func _reach_out(floe: NelvarCraterData.Isle, reached: Dictionary, cells: Dictionary, reach: float) -> bool:
	var before := floe.radii.duplicate()
	var others := _floes_around(floe, cells).filter(func(other: NelvarCraterData.Isle) -> bool: return reached.has(other))
	var count := floe.radii.size()
	for bulge in 2:
		var best := INF
		var best_k := -1
		for k in count:
			var point := floe.center + floe.outline[k]
			var short := _data.lava_depth(point) - REACH_SHORE
			for other: NelvarCraterData.Isle in others:
				var local := point - other.center
				short = minf(short, local.length() - other.radius_at(local.angle()) - REACH_FLOE)
			if short < best:
				best = short
				best_k = k
		if best_k < 0 or best > 400.0:
			break
		if best <= 0.5:
			continue
		for o in range(-6, 7):
			var k := (best_k + o + count) % count
			floe.radii[k] += best * _hump(absf(o), 2.0)
		floe.tabulate()
	if _isle_clear(floe, cells, reach):
		_widest = maxf(_widest, floe.outer)
		return true
	floe.radii = before
	floe.tabulate()
	return false


## Whether a broad floe keeps clear of the other floes however the swell moves them, of
## the shore, the vent's moat and the boiling patches.
func _isle_clear(floe: NelvarCraterData.Isle, cells: Dictionary, reach: float) -> bool:
	for other: NelvarCraterData.Isle in _floes_around(floe, cells):
		if other != floe and _clearance(floe, other) < NelvarCraterData.MIN_GAP:
			return false
	for point in floe.outline:
		var at := floe.center + point
		if _data.lava_depth(at) < reach + 10.0:
			return false
		if at.distance_to(_data.vent) < _data.vent_radius + _config.vent_moat + reach - 1.0:
			return false
		for boil in _data.boils:
			if at.distance_to(Vector2(boil.x, boil.y)) < boil.z + reach + 9.0:
				return false
	return true


## The floes filed in the cells round `floe` that could come near it.
func _floes_around(floe: NelvarCraterData.Isle, cells: Dictionary) -> Array[NelvarCraterData.Isle]:
	var found: Array[NelvarCraterData.Isle] = []
	var around := floe.outer + _widest + 200.0
	var lo := ((floe.center - Vector2.ONE * around) / FLOE_CELL).floor()
	var hi := ((floe.center + Vector2.ONE * around) / FLOE_CELL).floor()
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			for other: NelvarCraterData.Isle in cells.get(Vector2i(x, y), []):
				if other != floe and other.center.distance_to(floe.center) < floe.outer + other.outer + 200.0:
					found.append(other)
	return found


## A stone of a random size and shape: round, oval, a long slab, three-cornered or
## lobed, with a ragged edge. The bends (k = 2 stretches it, k = 3 gives it corners) keep
## the radius above half its mean, so no part of it is too thin to stand on.
func _floe_shape(rng: RandomNumberGenerator) -> NelvarCraterData.Isle:
	var floe := NelvarCraterData.Isle.new()
	var radius := lerpf(_config.floe_radius.x, _config.floe_radius.y, pow(rng.randf(), 1.2))
	var shape := NelvarEarthData.Radial.new()
	shape.axes = Vector2(radius, radius)
	shape.amplitudes.resize(NelvarEarthData.HARMONICS)
	shape.phases.resize(NelvarEarthData.HARMONICS)
	var stretch := 0.0
	var corners := 0.0
	match rng.randi() % 5:
		1:
			stretch = rng.randf_range(0.12, 0.22)
		2:
			stretch = rng.randf_range(0.26, 0.38)
		3:
			corners = rng.randf_range(0.09, 0.15)
		4:
			stretch = rng.randf_range(0.1, 0.2)
			corners = rng.randf_range(0.06, 0.11)
	for i in NelvarEarthData.HARMONICS:
		var amplitude := rng.randf_range(0.0, 0.05 / float(i))
		if i == 0:
			amplitude = stretch + rng.randf_range(0.0, 0.05)
		elif i == 1:
			amplitude = corners + rng.randf_range(0.0, 0.03)
		shape.amplitudes[i] = amplitude
		shape.phases[i] = rng.randf() * TAU
	floe.radii.resize(NelvarCraterData.STONE_SAMPLES)
	for i in NelvarCraterData.STONE_SAMPLES:
		floe.radii[i] = shape.radius_at(TAU * i / NelvarCraterData.STONE_SAMPLES)
	floe.tabulate()
	floe.appearance_seed = rng.randi()
	return floe


## Whether the stone keeps clear of everything wherever the swell takes it.
func _floe_fits(floe: NelvarCraterData.Isle, cells: Dictionary) -> bool:
	var reach := floe.drift_reach()
	if floe.center.distance_to(_data.vent) < _data.vent_radius + _config.vent_moat + floe.outer + reach:
		return false
	for boil in _data.boils:
		if floe.center.distance_to(Vector2(boil.x, boil.y)) < boil.z + floe.outer + reach + 10.0:
			return false
	var around := floe.outer + _widest + NelvarCraterData.MIN_GAP + 30.0
	var lo := ((floe.center - Vector2.ONE * around) / FLOE_CELL).floor()
	var hi := ((floe.center + Vector2.ONE * around) / FLOE_CELL).floor()
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			for other: NelvarCraterData.Isle in cells.get(Vector2i(x, y), []):
				var offset := other.center - floe.center
				var distance := offset.length()
				var need := NelvarCraterData.MIN_GAP + NelvarCraterData.sway_between(floe, other)
				if distance > floe.outer + other.outer + need:
					continue
				# Along the line between them first: the gap is never wider there.
				var angle := offset.angle()
				if distance - floe.radius_at(angle) - other.radius_at(angle + PI) < need:
					return false
				if _clearance(floe, other) < NelvarCraterData.MIN_GAP:
					return false
	# Deep in the lake its outline need not be walked.
	if _data.lava_depth(floe.center) > floe.outer + reach + 40.0:
		return true
	for point in floe.outline:
		if _data.lava_depth(floe.center + point) < reach + 10.0:
			return false
	return true


func _add_floe(floe: NelvarCraterData.Isle, cells: Dictionary) -> void:
	_data.floes.append(floe)
	_file_floe(floe, cells)


## Files the floe by the cell of its place.
func _file_floe(floe: NelvarCraterData.Isle, cells: Dictionary) -> void:
	_widest = maxf(_widest, floe.outer)
	var key := Vector2i((floe.center / FLOE_CELL).floor())
	if not cells.has(key):
		cells[key] = []
	cells[key].append(floe)


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
	for attempt in 200:
		if _data.boils.size() >= wanted:
			break
		var angle := rng.randf() * TAU
		var shore := _data.lake.radius_at(angle)
		var radius := rng.randf_range(40.0, 76.0)
		var distance := rng.randf_range(_data.vent_radius + 150.0, shore - 70.0)
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

## A few on the capes (springboards out over the floes), the rest along the rim, mostly
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
		var point := _data.vent + Vector2.from_angle(angle) * (_data.lake.radius_at(angle) + rng.randf_range(54.0, 170.0))
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


## Shared rules for anything on the rim. `trail_gap` is the free ground kept
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


## A random point of the rim.
func _random_ground(rng: RandomNumberGenerator) -> Vector2:
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
		var point := _random_ground(rng)
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
		# On the shore: _scatter moves it in off the lava.
		return _rim_point(rng.randf() * TAU, 0.0)
	var in_open := func() -> Vector2:
		if rng.randf() < 0.4 and not _data.flows.is_empty():
			var flow := _data.flows[rng.randi_range(0, _data.flows.size() - 1)]
			var i := rng.randi_range(0, flow.points.size() - 2)
			var along := flow.points[i].lerp(flow.points[i + 1], rng.randf())
			var side := flow.points[i].direction_to(flow.points[i + 1]).orthogonal()
			return along + side * (1.0 if rng.randf() < 0.5 else -1.0) * (flow.half_width + rng.randf_range(16.0, 40.0))
		return _random_ground(rng)
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
