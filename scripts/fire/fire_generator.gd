class_name NelvarFireGenerator
extends RefCounted
## Lays out the fire forge from a seed: the ridges' foot, the spawn, the great
## volcanoes' places, lava lakes and their islands, lava streams with crossings, the
## clearings and the roads of cooled lava between them, magma fissures and fields,
## fumaroles under smoke banks, burnt trees, boulders, crystals, the few plants of the
## heat, and the ridges, volcanoes and cinder cones round it all.
##
## Every stage draws from its own seeded generator, so changing one stage leaves the
## others as they were. Solid things always keep a passage wider than the player
## between them; roads, clearings and the spawn stay free of anything solid. Every
## stretch of a stream inside the basin has a crossing within `crossing_spacing`.

const Kind = NelvarFireData.Kind
const Species = NelvarFireData.Species
const Stone = NelvarFireData.Stone
const Peak = NelvarEarthData.Peak

## How far placed things look for neighbours (largest branches plus margins).
const GRID := 160.0
## Ridges: distance of each row from the foot and its base width range (as the earth's).
const ROW_OFFSET: Array[float] = [12.0, 230.0, 480.0, 760.0]
const ROW_WIDTH: Array[Vector2] = [Vector2(260.0, 400.0), Vector2(380.0, 560.0),
	Vector2(500.0, 720.0), Vector2(620.0, 860.0)]
## Each look of a ridge (Peak order up to GIANT): base width and height factors.
const PEAK_LOOK: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(1.45, 0.6), Vector2(0.8, 1.3),
	Vector2(1.3, 0.55), Vector2(1.65, 1.0)]
## Base width of a great volcano.
const VOLCANO_WIDTH := Vector2(780.0, 920.0)
const PLATEAU_DEPTH := 3600.0

## Trunk radius, reach of the branches and height of each species (Species order).
const TRUNK: Array[Vector2] = [Vector2(11, 15), Vector2(13, 18), Vector2(11, 15), Vector2(13, 17)]
const CROWN: Array[Vector2] = [Vector2(34, 50), Vector2(30, 44), Vector2(32, 48), Vector2(52, 70)]
const HEIGHT: Array[Vector2] = [Vector2(150, 210), Vector2(110, 160), Vector2(150, 200), Vector2(140, 180)]

var _config: NelvarFireConfig
var _data: NelvarFireData
var _grid := {}
var _stands: Array[Vector2] = []


func generate(config: NelvarFireConfig, world_seed: int) -> NelvarFireData:
	var error := config.validation_error()
	if not error.is_empty():
		push_error("Fire config: " + error)
		return null
	_config = config
	_data = NelvarFireData.new()
	_data.world_seed = world_seed
	_grid.clear()
	_stands.clear()
	_basin(_rng("basin"))
	_volcano_places(_rng("volcanoes"))
	_lakes(_rng("lakes"))
	_islands(_rng("islands"))
	_streams(_rng("streams"))
	_data.index_streams()
	_clearings(_rng("clearings"))
	_flows(_rng("flows"))
	_crossings(_rng("crossings"))
	_data.index_flows()
	_fissures(_rng("fissures"))
	_magma_fields(_rng("magma"))
	_vents(_rng("vents"))
	_trees(_rng("trees"))
	_rocks(_rng("rocks"))
	_crystals(_rng("crystals"))
	_snags(_rng("snags"))
	_plants(_rng("plants"))
	_peaks(_rng("peaks"))
	_data.finish()
	var result := _data
	_data = null
	_grid.clear()
	return result


func _rng(stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:fire:%s" % [_data.world_seed, stage]).hash()
	return rng


# --- Basin, volcanoes, lakes, islands -------------------------------------------

func _basin(rng: RandomNumberGenerator) -> void:
	var basin := _data.basin
	basin.center = Vector2.ZERO
	basin.axes = _config.basin_radius * Vector2(rng.randf_range(0.96, 1.04), rng.randf_range(0.96, 1.04))
	_bend(basin, rng, _config.basin_wobble, 0.2)
	_data.boundary = basin.polygon(_config.boundary_vertices)
	var spawn_angle := rng.randf() * TAU
	_data.spawn_position = basin.center + Vector2.from_angle(spawn_angle) \
		* basin.axes * rng.randf_range(0.0, 0.1)


## Slow bends: harmonic k gets a share of `depth` falling with k; the sum stays below
## `limit`, so the shape never pinches.
func _bend(shape: NelvarEarthData.Radial, rng: RandomNumberGenerator, depth: float, limit: float) -> void:
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


## The great volcanoes stand in the north of the ring: their lit fronts face the basin
## and the camera, and the lava down them meets a stream at the foot.
func _volcano_places(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.volcanoes.x, _config.volcanoes.y)
	for attempt in 40:
		if _data.volcano_angles.size() >= wanted:
			break
		var angle := rng.randf_range(-PI * 0.84, -PI * 0.16)
		var apart := true
		for other in _data.volcano_angles:
			if absf(angle_difference(angle, other)) < 0.95:
				apart = false
		if apart:
			_data.volcano_angles.append(angle)


func _lakes(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.lake_count.x, _config.lake_count.y)
	for attempt in 500:
		if _data.lakes.size() >= wanted:
			break
		var radius := rng.randf_range(_config.lake_radius.x, _config.lake_radius.y)
		var center := _random_basin_point(rng, 0.84)
		if _data.basin.signed_distance(center) < _config.lake_margin + radius:
			continue
		if center.distance_to(_data.spawn_position) < _config.spawn_clearance + radius + 220.0:
			continue
		var apart := true
		for other in _data.lakes:
			if center.distance_to(other.center) < radius + other.reach() + _config.lake_gap:
				apart = false
				break
		if not apart:
			continue
		var lake := NelvarEarthData.Radial.new()
		lake.center = center
		lake.axes = Vector2(radius, radius * rng.randf_range(0.66, 0.82))
		_bend(lake, rng, 0.1, 0.17)
		_data.lakes.append(lake)
		_data.lake_polygons.append(lake.polygon(_config.lake_vertices))


## Rafts of plates far enough out in the bigger lakes that only the flight reaches them.
func _islands(rng: RandomNumberGenerator) -> void:
	for l in _data.lakes.size():
		var lake := _data.lakes[l]
		if lake.axes.x < 175.0:
			continue
		var wanted := rng.randi_range(_config.islands_per_lake.x, _config.islands_per_lake.y)
		var placed: Array[NelvarEarthData.Radial] = []
		for attempt in 60:
			if placed.size() >= wanted:
				break
			var radius := rng.randf_range(_config.island_radius.x, _config.island_radius.y)
			var center := lake.center + Vector2.from_angle(rng.randf() * TAU) * lake.axes * sqrt(rng.randf()) * 0.55
			if lake.signed_distance(center) < radius * 1.3 + 70.0:
				continue
			var apart := true
			for other in placed:
				if center.distance_to(other.center) < radius + other.reach() + 60.0:
					apart = false
			if not apart:
				continue
			var island := NelvarFireData.Island.new()
			island.lake = l
			island.shape.center = center
			island.shape.axes = Vector2(radius, radius * rng.randf_range(0.7, 0.85))
			_bend(island.shape, rng, 0.12, 0.2)
			placed.append(island.shape)
			_data.islands.append(island)
			_data.island_polygons.append(island.shape.polygon(40))


# --- Streams --------------------------------------------------------------------

## A stream from under each great volcano into the nearest lake, and now and then one
## from a lake into another.
func _streams(rng: RandomNumberGenerator) -> void:
	for angle in _data.volcano_angles:
		var start := _data.basin.point_at(angle, -70.0)
		var order: Array[int] = []
		for i in _data.lakes.size():
			order.append(i)
		order.sort_custom(func(a: int, b: int) -> bool:
			return _data.lakes[a].center.distance_to(start) < _data.lakes[b].center.distance_to(start))
		var made := false
		for attempt in 6:
			var target := order[attempt % order.size()]
			var lake := _data.lakes[target]
			var toward := (start - lake.center).angle() + rng.randf_range(-0.3, 0.3)
			var half_width := rng.randf_range(_config.stream_half_width.x, _config.stream_half_width.y)
			var end := lake.point_at(toward, half_width + 40.0)
			if _try_stream(rng, start, end, half_width, [target], true):
				made = true
				break
		# No lake within reach: the stream runs out onto the basin and sets in a lobe.
		for attempt in 6:
			if made:
				break
			var half_width := rng.randf_range(_config.stream_half_width.x, _config.stream_half_width.y)
			var end := start.lerp(_data.basin.center, rng.randf_range(0.3, 0.5)) \
				+ Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 200.0)
			made = _try_stream(rng, start, end, half_width, [], true)
	if _data.lakes.size() >= 2 and rng.randf() < _config.lake_stream_chance:
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for a in _data.lakes.size():
			for b in range(a + 1, _data.lakes.size()):
				var distance := _data.lakes[a].center.distance_to(_data.lakes[b].center)
				if distance < best_distance:
					best_distance = distance
					best = Vector2i(a, b)
		if best_distance < 1500.0:
			var from := _data.lakes[best.x]
			var to := _data.lakes[best.y]
			var half_width := rng.randf_range(_config.stream_half_width.x, _config.stream_half_width.x + 6.0)
			var start := from.point_at((to.center - from.center).angle(), half_width + 40.0)
			var end := to.point_at((from.center - to.center).angle(), half_width + 40.0)
			_try_stream(rng, start, end, half_width, [best.x, best.y], false)


func _nearest_lake(point: Vector2) -> int:
	var best := -1
	for i in _data.lakes.size():
		if best < 0 or _data.lakes[i].signed_distance(point) > _data.lakes[best].signed_distance(point):
			best = i
	return best


func _try_stream(rng: RandomNumberGenerator, start: Vector2, end: Vector2, half_width: float,
		ends_in: Array, from_ridge: bool) -> bool:
	var points := _route(start, end, half_width, rng, ends_in, from_ridge, true)
	for point in points:
		if not from_ridge or point.distance_to(start) > 260.0:
			if _data.basin.signed_distance(point) < half_width + 70.0:
				return false
		if point.distance_to(_data.spawn_position) < _config.spawn_clearance + half_width + 90.0:
			return false
		for i in _data.lakes.size():
			if not ends_in.has(i) and _data.lakes[i].signed_distance(point) > -(half_width + 140.0):
				return false
		for other in _data.streams:
			if NelvarFireData.polyline_distance(other.points, point) < half_width + other.half_width + 200.0:
				return false
	var stream := NelvarFireData.Stream.new()
	stream.points = points
	stream.half_width = half_width
	stream.measure()
	_data.streams.append(stream)
	return true


## A gently bending line from a to b that keeps clear of the lakes (but those in
## `ends_in`), of the spawn and of the ridges' foot (a stream from the ridges may start
## beyond it). Streams bend more than roads.
func _route(a: Vector2, b: Vector2, half_width: float, rng: RandomNumberGenerator,
		ends_in: Array, from_ridge: bool, lava: bool) -> PackedVector2Array:
	var length := a.distance_to(b)
	var count := maxi(3, int(length / 60.0))
	var normal := a.direction_to(b).orthogonal()
	var amplitude := minf(length * (0.14 if lava else 0.09), 140.0) * rng.randf_range(0.4, 1.0)
	var waves := rng.randf_range(0.7, 1.9)
	var phase := rng.randf() * TAU
	var points: Array[Vector2] = []
	for i in count + 1:
		var t := float(i) / count
		var bend := sin(PI * t) * sin(phase + t * PI * waves) * amplitude
		points.append(a.lerp(b, t) + normal * bend)
	var keep_out := half_width + (90.0 if lava else 44.0)
	for iteration in 8:
		for i in range(1, points.size() - 1):
			var p := points[i]
			for l in _data.lakes.size():
				if ends_in.has(l):
					continue
				var lake := _data.lakes[l]
				var depth := lake.signed_distance(p)
				if depth > -keep_out:
					p += lake.center.direction_to(p) * (depth + keep_out)
			if lava:
				var spawn_gap := _config.spawn_clearance + half_width + 110.0
				if p.distance_to(_data.spawn_position) < spawn_gap:
					p = _data.spawn_position + _data.spawn_position.direction_to(p) * spawn_gap
			# The first stretch of a stream from the ridges may lie under them.
			if not (from_ridge and float(i) / points.size() < 0.18):
				var inside := _data.basin.signed_distance(p)
				var limit := half_width + 100.0
				if inside < limit:
					p += p.direction_to(_data.basin.center) * (limit - inside)
			points[i] = p
		var smooth: Array[Vector2] = points.duplicate()
		for i in range(1, points.size() - 1):
			smooth[i] = points[i - 1] * 0.25 + points[i] * 0.5 + points[i + 1] * 0.25
		points = smooth
	# Two rounds of Chaikin's corner cutting.
	for pass_index in 2:
		var cut: Array[Vector2] = [points[0]]
		for i in points.size() - 1:
			cut.append(points[i].lerp(points[i + 1], 0.25))
			cut.append(points[i].lerp(points[i + 1], 0.75))
		cut.append(points[points.size() - 1])
		points = cut
	return PackedVector2Array(points)


## Where a crossing may lie on a stream: well inside the basin, away from the lakes and
## the other crossings, on a straight enough stretch.
func _crossing_fits(stream: NelvarFireData.Stream, along: float, half_length: float) -> bool:
	if along < half_length + 10.0 or along > stream.length() - half_length - 10.0:
		return false
	var center := stream.point_at(along)
	if _data.basin.signed_distance(center) < stream.half_width + 150.0:
		return false
	for lake in _data.lakes:
		if lake.signed_distance(center) > -(half_length + stream.half_width + 70.0):
			return false
	for other in stream.crossings:
		if absf(other.along - along) < half_length + other.half_length + 60.0:
			return false
	var before := stream.direction_at(along - half_length)
	var after := stream.direction_at(along + half_length)
	return before.dot(after) > 0.86


func _add_crossing(stream: NelvarFireData.Stream, along: float, half_length: float) -> void:
	var crossing := NelvarFireData.Crossing.new()
	crossing.along = along
	crossing.center = stream.point_at(along)
	crossing.direction = stream.direction_at(along)
	crossing.half_length = half_length
	stream.crossings.append(crossing)
	stream.crossings.sort_custom(func(a: NelvarFireData.Crossing, b: NelvarFireData.Crossing) -> bool:
		return a.along < b.along)


## Every stretch of a stream inside the basin gets a crossing within crossing_spacing.
func _crossings(rng: RandomNumberGenerator) -> void:
	for stream in _data.streams:
		var half_length := _config.crossing_half_length
		# The stretch inside the basin and away from the lakes.
		var first := -1.0
		var last := -1.0
		var along := 0.0
		while along <= stream.length():
			var point := stream.point_at(along)
			var open := _data.basin.signed_distance(point) > stream.half_width + 150.0
			for lake in _data.lakes:
				if lake.signed_distance(point) > -(half_length + stream.half_width + 70.0):
					open = false
			if open:
				if first < 0.0:
					first = along
				last = along
			along += 10.0
		if first < 0.0 or last - first < half_length * 2.0 + 40.0:
			continue
		for guard in 12:
			var stops: Array[float] = [first]
			for crossing in stream.crossings:
				stops.append(crossing.along)
			stops.append(last)
			stops.sort()
			var widest := 0
			for i in stops.size() - 1:
				if stops[i + 1] - stops[i] > stops[widest + 1] - stops[widest]:
					widest = i
			var gap := stops[widest + 1] - stops[widest]
			if gap <= _config.crossing_spacing and not stream.crossings.is_empty():
				break
			var middle := (stops[widest] + stops[widest + 1]) * 0.5
			var placed := false
			for shift: float in [0.0, 40.0, -40.0, 80.0, -80.0, 130.0, -130.0]:
				var at := middle + shift * rng.randf_range(0.8, 1.2)
				if _crossing_fits(stream, at, half_length):
					_add_crossing(stream, at, half_length)
					placed = true
					break
			if not placed:
				break


# --- Clearings and roads ----------------------------------------------------------

func _clearings(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.clearing_count.x, _config.clearing_count.y)
	var taken: Array[Vector2] = [_data.spawn_position]
	for lake in _data.lakes:
		taken.append(lake.center)
	var candidates: Array[Vector2] = []
	for i in 80:
		var point := _random_basin_point(rng, 0.85)
		if _data.basin.signed_distance(point) > 300.0 and _data.lava_depth(point) < -220.0:
			candidates.append(point)
	# Farthest-point sampling: every clearing as far as possible from the others.
	for i in wanted:
		var best := -1
		var best_distance := 0.0
		for c in candidates.size():
			var nearest := INF
			for point in taken:
				nearest = minf(nearest, candidates[c].distance_to(point))
			if nearest > best_distance:
				best_distance = nearest
				best = c
		if best < 0 or best_distance < 420.0:
			break
		var clearing := NelvarEarthData.Clearing.new()
		clearing.center = candidates[best]
		clearing.radius = rng.randf_range(_config.clearing_radius.x, _config.clearing_radius.y)
		_data.clearings.append(clearing)
		taken.append(clearing.center)
		candidates.remove_at(best)


## Roads of cooled lava join the spawn, the clearings and the lake shores (a spanning
## tree plus a loop or two); some run off into the ridges. Where one crosses a stream,
## the stream gets a crossing there; a road that would meet a stream badly is dropped.
func _flows(rng: RandomNumberGenerator) -> void:
	var nodes: Array[Vector2] = [_data.spawn_position]
	for clearing in _data.clearings:
		nodes.append(clearing.center)
	for lake in _data.lakes:
		var toward := (_data.spawn_position - lake.center).angle() + rng.randf_range(-0.6, 0.6)
		nodes.append(lake.center + Vector2.from_angle(toward) * (lake.radius_at(toward) + 46.0))
	var edges: Array[Vector2i] = []
	var joined := {0: true}
	while joined.size() < nodes.size():
		var best := Vector2i(-1, -1)
		var best_length := INF
		for a: int in joined:
			for b in nodes.size():
				if joined.has(b):
					continue
				var length := nodes[a].distance_to(nodes[b])
				if length < best_length:
					best_length = length
					best = Vector2i(a, b)
		joined[best.y] = true
		edges.append(best)
	var extra: Array[Vector2i] = []
	for a in nodes.size():
		for b in range(a + 1, nodes.size()):
			if not edges.has(Vector2i(a, b)) and not edges.has(Vector2i(b, a)):
				extra.append(Vector2i(a, b))
	extra.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return nodes[p.x].distance_to(nodes[p.y]) < nodes[q.x].distance_to(nodes[q.y]))
	var added := 0
	for edge in extra:
		if added >= _config.extra_flows:
			break
		if _clear_angle(edge, edges, nodes):
			edges.append(edge)
			added += 1
	for edge in edges:
		var flow := NelvarEarthData.Trail.new()
		flow.half_width = rng.randf_range(_config.flow_half_width.x, _config.flow_half_width.y)
		flow.points = _route(nodes[edge.x], nodes[edge.y], flow.half_width, rng, [], false, false)
		_try_flow(flow)
	for i in _config.ridge_flows:
		var angle := rng.randf_range(-PI, PI)
		var foot := _data.basin.point_at(angle, -50.0)
		var nearest := 0
		for n in nodes.size():
			if nodes[n].distance_to(foot) < nodes[nearest].distance_to(foot):
				nearest = n
		var flow := NelvarEarthData.Trail.new()
		flow.half_width = rng.randf_range(_config.flow_half_width.x, _config.flow_half_width.y) * 0.8
		flow.into_mountains = true
		# Routed from the foot (its first stretch may reach it), then turned round.
		var points := _route(foot, nodes[nearest], flow.half_width, rng, [], true, false)
		points.reverse()
		flow.points = points
		_try_flow(flow)


func _clear_angle(edge: Vector2i, edges: Array[Vector2i], nodes: Array[Vector2]) -> bool:
	for end: int in [edge.x, edge.y]:
		var other: int = edge.y if end == edge.x else edge.x
		var direction := nodes[end].direction_to(nodes[other])
		for existing in edges:
			if existing.x != end and existing.y != end:
				continue
			var far: int = existing.y if existing.x == end else existing.x
			if absf(direction.angle_to(nodes[end].direction_to(nodes[far]))) < deg_to_rad(40.0):
				return false
	return true


## Keeps a road that stays out of the lakes and meets every stream it crosses at a
## crossing (made where needed); drops it otherwise.
func _try_flow(flow: NelvarEarthData.Trail) -> void:
	for point in flow.points:
		for lake in _data.lakes:
			if lake.signed_distance(point) > -flow.half_width - 6.0:
				return
		if _data.on_island(point, flow.half_width):
			return
	var made: Array = []
	for stream in _data.streams:
		for i in flow.points.size() - 1:
			var a := flow.points[i]
			var b := flow.points[i + 1]
			for j in stream.points.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, stream.points[j], stream.points[j + 1])
				if hit == null:
					continue
				var along := stream.lengths[j] + stream.points[j].distance_to(hit)
				var nearby: NelvarFireData.Crossing = null
				for crossing in stream.crossings:
					if absf(crossing.along - along) < crossing.half_length + 70.0:
						nearby = crossing
				if nearby != null and absf(nearby.along - along) < nearby.half_length * 0.5:
					continue
				if nearby != null:
					_undo_crossings(made)
					return
				var crossing_angle := absf(a.direction_to(b).dot(stream.points[j].direction_to(stream.points[j + 1])))
				var half_length := maxf(_config.crossing_half_length, flow.half_width + 30.0)
				if crossing_angle > 0.82 or not _crossing_fits(stream, along, half_length):
					_undo_crossings(made)
					return
				_add_crossing(stream, along, half_length)
				made.append([stream, stream.crossings[stream.crossings.size() - 1]])
	# The road never runs in a stream's lava outside its crossings.
	for point in flow.points:
		for stream in _data.streams:
			var distance := INF
			var along := 0.0
			for j in stream.points.size() - 1:
				var closest := Geometry2D.get_closest_point_to_segment(point, stream.points[j], stream.points[j + 1])
				if point.distance_to(closest) < distance:
					distance = point.distance_to(closest)
					along = stream.lengths[j] + stream.points[j].distance_to(closest)
			if stream.depth_at(distance, along) > -flow.half_width * 0.6:
				_undo_crossings(made)
				return
	_data.flows.append(flow)


func _undo_crossings(made: Array) -> void:
	for entry: Array in made:
		var stream: NelvarFireData.Stream = entry[0]
		stream.crossings.erase(entry[1])


func _random_basin_point(rng: RandomNumberGenerator, reach: float) -> Vector2:
	var angle := rng.randf() * TAU
	return _data.basin.point_at(angle, 0.0).lerp(_data.basin.center, 1.0 - sqrt(rng.randf()) * reach)


# --- Magma and smoke ------------------------------------------------------------------

## Jagged cracks on open ground; some of them erupt now and then.
func _fissures(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.fissures.x, _config.fissures.y)
	for attempt in wanted * 30:
		if _data.fissures.size() >= wanted:
			break
		var start := _random_basin_point(rng, 0.88)
		if not _fissure_ground(start, 110.0) \
				or start.distance_to(_data.spawn_position) < _config.spawn_clearance + 200.0:
			continue
		var far := true
		for other in _data.fissures:
			if other.center.distance_to(start) < other.reach + 220.0:
				far = false
		if not far:
			continue
		var points := PackedVector2Array([start])
		var heading := rng.randf() * TAU
		var point := start
		for k in rng.randi_range(7, 13):
			heading += rng.randf_range(-0.55, 0.55)
			point += Vector2.from_angle(heading) * rng.randf_range(14.0, 26.0)
			if not _fissure_ground(point, 90.0):
				break
			points.append(point)
		if points.size() < 6:
			continue
		var fissure := NelvarFireData.Fissure.new()
		fissure.points = points
		fissure.active = rng.randf() < _config.active_share
		fissure.period = rng.randf_range(5.5, 9.5)
		fissure.phase = rng.randf() * fissure.period
		var center := Vector2.ZERO
		for p in points:
			center += p
		fissure.center = center / points.size()
		for p in points:
			fissure.reach = maxf(fissure.reach, p.distance_to(fissure.center))
		_data.fissures.append(fissure)


func _fissure_ground(point: Vector2, lava_gap: float) -> bool:
	if _data.basin.signed_distance(point) < 130.0 or _data.lava_depth(point) > -lava_gap:
		return false
	if _data.on_island(point, 40.0) or _data.flow_clearance(point) < 34.0:
		return false
	for clearing in _data.clearings:
		if point.distance_to(clearing.center) < clearing.radius * 0.6:
			return false
	return true


## Patches where the basalt's joints glow with magma underneath: by some fissures and
## lakes, never at the spawn.
func _magma_fields(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.magma_fields.x, _config.magma_fields.y)
	for attempt in 80:
		if _data.magma_fields.size() >= wanted:
			break
		var radius := rng.randf_range(110.0, 200.0)
		var center := _random_basin_point(rng, 0.85)
		if attempt < 40 and not _data.fissures.is_empty():
			var fissure := _data.fissures[rng.randi_range(0, _data.fissures.size() - 1)]
			center = fissure.center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 120.0)
		if _data.basin.signed_distance(center) < radius * 0.6 + 80.0 or _data.lava_depth(center) > -40.0:
			continue
		if center.distance_to(_data.spawn_position) < radius + _config.spawn_clearance + 60.0:
			continue
		var apart := true
		for other in _data.magma_fields:
			if center.distance_to(Vector2(other.x, other.y)) < radius + other.z + 200.0:
				apart = false
		if apart:
			_data.magma_fields.append(Vector3(center.x, center.y, radius))


## Fumarole fields: vents with sulfur round them and a bank of smoke over them.
func _vents(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.vent_fields.x, _config.vent_fields.y)
	for attempt in 120:
		if _data.smoke_banks.size() >= wanted:
			break
		var radius := rng.randf_range(150.0, 210.0)
		var center := _random_basin_point(rng, 0.82)
		if _data.basin.signed_distance(center) < radius + 60.0:
			continue
		if _data.lava_depth(center) > -(radius * 0.6 + 60.0) or _data.on_island(center, radius):
			continue
		if center.distance_to(_data.spawn_position) < radius + 420.0:
			continue
		if _data.flow_clearance(center) < 60.0:
			continue
		var apart := true
		for other in _data.smoke_banks:
			if center.distance_to(Vector2(other.x, other.y)) < radius + other.z + 450.0:
				apart = false
		if not apart:
			continue
		var vents := 0
		var count := rng.randi_range(_config.vents_per_field.x, _config.vents_per_field.y)
		for k in count * 12:
			if vents >= count:
				break
			var point := center + Vector2.from_angle(rng.randf() * TAU) * radius * 0.65 * sqrt(rng.randf())
			var vent := NelvarFireData.Thing.new()
			vent.kind = Kind.VENT
			vent.radius = rng.randf_range(13.0, 21.0)
			vent.position = point
			vent.accent = rng.randf() < 0.35
			vent.appearance_seed = rng.randi()
			if _fits(point, vent.radius + 10.0, false, 6.0, 40.0, 1.6):
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


## Shared rules for anything placed in the basin. `trail_gap` is the free ground kept
## beside roads, `lava_gap` the ground kept from lava (negative: may stand at its edge).
func _fits(point: Vector2, radius: float, solid: bool, trail_gap: float, lava_gap: float,
		plant_spacing: float = 0.7) -> bool:
	if _data.basin.signed_distance(point) < radius + (60.0 if solid else 24.0):
		return false
	if _data.lava_depth(point) > -(radius + lava_gap):
		return false
	if _data.on_island(point, radius + 30.0):
		return false
	var spawn_gap := _config.spawn_clearance if solid else 60.0
	if point.distance_to(_data.spawn_position) < spawn_gap + radius:
		return false
	if solid:
		for clearing in _data.clearings:
			if point.distance_to(clearing.center) < clearing.radius + radius:
				return false
		if _data.fissure_distance(point) < radius + 22.0:
			return false
	elif _data.fissure_distance(point) < radius * 0.5 + 6.0:
		return false
	if trail_gap >= 0.0 and _data.flow_clearance(point) < radius + trail_gap:
		return false
	for other: NelvarFireData.Thing in _nearby(point, 280.0):
		var distance := point.distance_to(other.position)
		if other.solid and solid:
			var gap := _config.passage_width
			if other.kind == Kind.TREE and radius > 0.0:
				gap = maxf(gap, _config.tree_spacing - other.radius - radius)
			if distance < radius + other.spread() + gap:
				return false
		elif other.solid or solid:
			if distance < (radius + other.spread()) * 0.85:
				return false
		elif distance < (radius + other.radius) * plant_spacing:
			return false
		if other.crown_hides(point, radius * 0.3):
			return false
	return true


func _crown_is_clear(tree: NelvarFireData.Thing) -> bool:
	for other: NelvarFireData.Thing in _nearby(tree.crown_center(), tree.size.x + 120.0):
		if other.kind != Kind.TREE and tree.crown_hides(other.position):
			return false
	return true


# --- Trees, stone, snags --------------------------------------------------------------

func _trees(rng: RandomNumberGenerator) -> void:
	# Stands of burnt trees: one main kind each, some of another mixed in.
	var wanted := rng.randi_range(_config.tree_stands.x, _config.tree_stands.y)
	for attempt in 300:
		if _stands.size() >= wanted:
			break
		var center := _random_basin_point(rng, 0.9)
		if not _stand_ground(center):
			continue
		_stands.append(center)
		var main := _stand_species(rng)
		var radius := rng.randf_range(_config.stand_radius.x, _config.stand_radius.y)
		var count := rng.randi_range(_config.stand_trees.x, _config.stand_trees.y)
		var grown := 0
		for t in count * 8:
			if grown >= count:
				break
			var species := main
			if rng.randf() < 0.25:
				species = _stand_species(rng)
			var point := center + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf())
			if _try_tree(rng, species, point) != null:
				grown += 1
	# The emberleaves grow in small groups near the heat.
	var groves := rng.randi_range(_config.emberleaf_groves.x, _config.emberleaf_groves.y)
	var planted := 0
	for attempt in 200:
		if planted >= groves:
			break
		var center := _random_basin_point(rng, 0.88)
		if attempt < 120 and not _data.lakes.is_empty():
			var lake := _data.lakes[rng.randi_range(0, _data.lakes.size() - 1)]
			center = lake.point_at(rng.randf() * TAU, -rng.randf_range(110.0, 220.0))
		if not _stand_ground(center):
			continue
		var grown := 0
		for t in 24:
			if grown >= rng.randi_range(1, 3):
				break
			var point := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 130.0)
			if _try_tree(rng, Species.EMBERLEAF, point) != null:
				grown += 1
		if grown > 0:
			_stands.append(center)
			planted += 1
	var lone := rng.randi_range(_config.lone_trees.x, _config.lone_trees.y)
	var grown_lone := 0
	for attempt in lone * 10:
		if grown_lone >= lone:
			break
		var species := _stand_species(rng)
		if _try_tree(rng, species, _random_basin_point(rng, 0.95)) != null:
			grown_lone += 1


func _stand_ground(center: Vector2) -> bool:
	if _data.basin.signed_distance(center) < 160.0 or _data.lava_depth(center) > -110.0:
		return false
	if center.distance_to(_data.spawn_position) < _config.spawn_clearance + 220.0:
		return false
	for other in _stands:
		if center.distance_to(other) < 420.0:
			return false
	for clearing in _data.clearings:
		if center.distance_to(clearing.center) < clearing.radius + 140.0:
			return false
	return true


func _stand_species(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if roll < 0.45:
		return Species.CHARRED
	if roll < 0.72:
		return Species.SMOULDERING
	return Species.ASHEN


func _try_tree(rng: RandomNumberGenerator, species: int, point: Vector2) -> NelvarFireData.Thing:
	var tree := NelvarFireData.Thing.new()
	tree.kind = Kind.TREE
	tree.variant = species
	tree.solid = true
	var scale := rng.randf()
	tree.radius = lerpf(TRUNK[species].x, TRUNK[species].y, scale)
	tree.size = Vector2(lerpf(CROWN[species].x, CROWN[species].y, scale * 0.7 + rng.randf() * 0.3),
		lerpf(HEIGHT[species].x, HEIGHT[species].y, scale * 0.6 + rng.randf() * 0.4))
	tree.position = point
	tree.accent = species == Species.SMOULDERING and rng.randf() < 0.6
	tree.appearance_seed = rng.randi()
	if not _fits(point, tree.radius, true, _config.path_clearance, _config.lava_clearance + 20.0):
		return null
	if not _crown_is_clear(tree):
		return null
	_add(tree)
	return tree


func _rocks(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.rocks.x, _config.rocks.y)
	var placed := 0
	for attempt in wanted * 12:
		if placed >= wanted:
			break
		var radius := rng.randf_range(30.0, 44.0) if rng.randf() < 0.22 else rng.randf_range(14.0, 26.0)
		var roll := rng.randf()
		var look := Stone.PLAIN if roll < 0.5 else (Stone.ASHEN if roll < 0.8 else Stone.EMBER)
		if _try_rock(rng, _random_basin_point(rng, 0.94), radius, look, _config.lava_clearance):
			placed += 1
	# Scree at the ridges' foot, in loose heaps.
	var scree := rng.randi_range(_config.scree_rocks.x, _config.scree_rocks.y)
	var heaped := 0
	for attempt in 260:
		if heaped >= scree:
			break
		var angle := rng.randf() * TAU
		var heap := _data.basin.point_at(angle, rng.randf_range(80.0, 170.0))
		for k in rng.randi_range(2, 4):
			var radius := rng.randf_range(12.0, 34.0)
			var point := heap + Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-50.0, 50.0))
			if _data.basin.signed_distance(point) < radius + 60.0:
				continue
			if _try_rock(rng, point, radius, Stone.ASHEN if rng.randf() < 0.4 else Stone.PLAIN,
					_config.lava_clearance):
				heaped += 1
	# Boulders on the lava shores, often still glowing inside.
	var shore := rng.randi_range(_config.shore_rocks.x, _config.shore_rocks.y)
	var lined := 0
	for attempt in shore * 16:
		if lined >= shore or _data.lakes.is_empty():
			break
		var lake := _data.lakes[rng.randi_range(0, _data.lakes.size() - 1)]
		var radius := rng.randf_range(14.0, 28.0)
		var point := lake.point_at(rng.randf() * TAU, -(radius + rng.randf_range(34.0, 70.0)))
		if _try_rock(rng, point, radius, Stone.EMBER if rng.randf() < 0.6 else Stone.PLAIN, 26.0):
			lined += 1


func _try_rock(rng: RandomNumberGenerator, point: Vector2, radius: float, look: int,
		lava_gap: float) -> bool:
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


## Clusters of blue-green crystals: by the vents and at the foot of boulders.
func _crystals(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.crystal_clusters.x, _config.crystal_clusters.y)
	var rocks: Array[NelvarFireData.Thing] = []
	for thing in _data.things:
		if thing.kind == Kind.ROCK:
			rocks.append(thing)
	var placed := 0
	for attempt in wanted * 20:
		if placed >= wanted:
			break
		var point := _random_basin_point(rng, 0.9)
		var roll := rng.randf()
		if roll < 0.45 and not _data.smoke_banks.is_empty():
			var bank := _data.smoke_banks[rng.randi_range(0, _data.smoke_banks.size() - 1)]
			point = Vector2(bank.x, bank.y) + Vector2.from_angle(rng.randf() * TAU) * bank.z * rng.randf_range(0.3, 1.0)
		elif roll < 0.85 and not rocks.is_empty():
			var rock := rocks[rng.randi_range(0, rocks.size() - 1)]
			point = rock.position + Vector2.from_angle(rng.randf_range(-0.3, PI + 0.3)) \
				* (rock.spread() + rng.randf_range(50.0, 80.0))
		var crystal := NelvarFireData.Thing.new()
		crystal.kind = Kind.CRYSTALS
		crystal.radius = rng.randf_range(12.0, 22.0)
		crystal.position = point
		crystal.solid = true
		crystal.variant = rng.randi_range(0, 1)
		crystal.appearance_seed = rng.randi()
		if _fits(point, crystal.radius, true, _config.path_clearance, _config.lava_clearance):
			_add(crystal)
			placed += 1


## Broken burnt trunks and fallen logs near the stands.
func _snags(rng: RandomNumberGenerator) -> void:
	if _stands.is_empty():
		return
	var wanted := rng.randi_range(_config.snags_and_logs.x, _config.snags_and_logs.y)
	var placed := 0
	for attempt in wanted * 20:
		if placed >= wanted:
			break
		var stand := _stands[rng.randi_range(0, _stands.size() - 1)]
		var point := stand + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 340.0)
		var thing := NelvarFireData.Thing.new()
		thing.solid = true
		thing.position = point
		thing.appearance_seed = rng.randi()
		thing.accent = rng.randf() < 0.5
		if rng.randf() < 0.55:
			thing.kind = Kind.SNAG
			thing.radius = rng.randf_range(13.0, 19.0)
			thing.size = Vector2(0.0, rng.randf_range(34.0, 64.0))
		else:
			thing.kind = Kind.LOG
			thing.radius = rng.randf_range(12.0, 15.0)
			thing.size = Vector2(rng.randf_range(80.0, 124.0), 0.0)
		if _fits(point, thing.spread(), true, _config.path_clearance, _config.lava_clearance):
			_add(thing)
			placed += 1


# --- Plants -------------------------------------------------------------------------

## The few plants that live here: ember grass by the lava and the cracks, ash flowers
## in the open and by the roads, scorched shrubs at the foot of trees and boulders.
func _plants(rng: RandomNumberGenerator) -> void:
	var hosts: Array[NelvarFireData.Thing] = []
	for thing in _data.things:
		if thing.kind in [Kind.TREE, Kind.ROCK, Kind.SNAG]:
			hosts.append(thing)
	var by_heat := func() -> Vector2:
		var roll := rng.randf()
		if roll < 0.45 and not _data.lakes.is_empty():
			var lake := _data.lakes[rng.randi_range(0, _data.lakes.size() - 1)]
			return lake.point_at(rng.randf() * TAU, -rng.randf_range(30.0, 90.0))
		if roll < 0.75 and not _data.fissures.is_empty():
			var fissure := _data.fissures[rng.randi_range(0, _data.fissures.size() - 1)]
			var p := fissure.points[rng.randi_range(0, fissure.points.size() - 1)]
			return p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(16.0, 40.0)
		return _random_basin_point(rng, 0.92)
	var in_open := func() -> Vector2:
		if rng.randf() < 0.4 and not _data.flows.is_empty():
			var flow := _data.flows[rng.randi_range(0, _data.flows.size() - 1)]
			var i := rng.randi_range(0, flow.points.size() - 2)
			var along := flow.points[i].lerp(flow.points[i + 1], rng.randf())
			var side := flow.points[i].direction_to(flow.points[i + 1]).orthogonal()
			return along + side * (1.0 if rng.randf() < 0.5 else -1.0) * (flow.half_width + rng.randf_range(16.0, 40.0))
		if rng.randf() < 0.5 and not _data.clearings.is_empty():
			var clearing := _data.clearings[rng.randi_range(0, _data.clearings.size() - 1)]
			return clearing.center + Vector2.from_angle(rng.randf() * TAU) * clearing.radius * sqrt(rng.randf())
		return _random_basin_point(rng, 0.9)
	var by_host := func() -> Vector2:
		if hosts.is_empty():
			return _random_basin_point(rng, 0.9)
		var host: NelvarFireData.Thing = hosts[rng.randi_range(0, hosts.size() - 1)]
		return host.position + Vector2.from_angle(rng.randf_range(-0.2, PI + 0.2)) \
			* (host.spread() + rng.randf_range(14.0, 50.0))
	_scatter(rng, Kind.EMBER_GRASS, rng.randi_range(_config.ember_grass.x, _config.ember_grass.y),
		Vector2(12.0, 20.0), 2, by_heat, 2.0, 14.0)
	_scatter(rng, Kind.ASH_FLOWER, rng.randi_range(_config.ash_flowers.x, _config.ash_flowers.y),
		Vector2(10.0, 16.0), 3, in_open, 0.0, 24.0)
	_scatter(rng, Kind.SHRUB, rng.randi_range(_config.shrubs.x, _config.shrubs.y),
		Vector2(16.0, 26.0), 2, by_host, 4.0, 24.0)


func _scatter(rng: RandomNumberGenerator, kind: Kind, count: int, radius_range: Vector2,
		variants: int, pick: Callable, trail_gap: float, lava_gap: float) -> void:
	var placed := 0
	for attempt in count * 12:
		if placed >= count:
			break
		var point: Vector2 = pick.call()
		var radius := rng.randf_range(radius_range.x, radius_range.y)
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


# --- Ridges ---------------------------------------------------------------------------

## Rows of ridges along the foot with the great volcanoes in the nearest row, then
## crags, cinder cones and boulders on the plateau beyond. Ridges on the south side are
## lower: they stand between the camera and the basin.
func _peaks(rng: RandomNumberGenerator) -> void:
	var basin := _data.basin
	var rows := _config.peak_rows
	var volcano_reach: Array[float] = []
	for angle in _data.volcano_angles:
		var width := rng.randf_range(VOLCANO_WIDTH.x, VOLCANO_WIDTH.y)
		var volcano := NelvarEarthData.Thing.new()
		volcano.kind = NelvarEarthData.Kind.PEAK
		volcano.variant = Peak.GIANT
		volcano.row = 0
		volcano.position = basin.point_at(angle, -ROW_OFFSET[0])
		volcano.radius = width * 0.5
		volcano.size = Vector2(width, width * rng.randf_range(0.95, 1.08))
		volcano.accent = true
		volcano.appearance_seed = rng.randi()
		_data.peaks.append(volcano)
		volcano_reach.append(width * 0.36 / maxf(basin.radius_at(angle), 1.0))
	for row in rows:
		var angle := rng.randf() * TAU
		var travelled := 0.0
		var widths := ROW_WIDTH[row]
		var last := Peak.SUMMIT
		while travelled < TAU:
			var shape := _peak_shape(rng, last)
			last = shape
			var look: Vector2 = PEAK_LOOK[shape]
			var width := rng.randf_range(widths.x, widths.y) * look.x
			var outward := Vector2.from_angle(angle)
			var south := maxf(0.0, outward.y)
			var offset := ROW_OFFSET[row] + width * 0.36 * absf(outward.x) * (1.0 if row == 0 else 0.5)
			var spacing := width * (rng.randf_range(0.36, 0.5) if row == 0 else rng.randf_range(0.42, 0.58))
			# The nearest row leaves room for the great volcanoes.
			var hidden := false
			if row == 0:
				for v in _data.volcano_angles.size():
					var half := width * 0.3 / maxf(basin.radius_at(angle), 1.0)
					if absf(angle_difference(angle, _data.volcano_angles[v])) < volcano_reach[v] + half:
						hidden = true
			if not hidden:
				var peak := NelvarEarthData.Thing.new()
				peak.kind = NelvarEarthData.Kind.PEAK
				peak.variant = shape
				peak.row = row
				peak.position = basin.point_at(angle, -offset)
				peak.radius = width * 0.5
				var height := width * rng.randf_range(0.92, 1.25) * look.y * lerpf(1.0, 0.58, south)
				peak.size = Vector2(width, height)
				# Now and then a summit is a cinder cone (a small volcano, the giant's shape),
				# mostly still glowing; a molten massif or mesa pours a lavafall (only in
				# the nearest row: further back the ridges in front hide it).
				match shape:
					Peak.SUMMIT:
						if rng.randf() < 0.12:
							peak.variant = Peak.GIANT
							peak.accent = rng.randf() < 0.7
					Peak.MASSIF, Peak.MESA:
						peak.accent = row == 0 and rng.randf() < 0.14
				peak.appearance_seed = rng.randi()
				_data.peaks.append(peak)
			if row == rows - 1 and row > 0 and rng.randf() < 0.3:
				spacing += width * rng.randf_range(0.4, 0.9)
			var step := spacing / maxf(basin.radius_at(angle) + offset, 1.0)
			# Under a volcano the ring only creeps on, so the next ridge stands right at
			# its side.
			if hidden:
				step = 0.025
			angle = wrapf(angle + step, -PI, PI)
			travelled += step
	_plateau(rng, rows)


## Look of the next ridge: mostly summits, the others never twice in a row. The giant's
## shape is the volcanoes' in the forge.
func _peak_shape(rng: RandomNumberGenerator, last: int) -> int:
	for attempt in 4:
		var roll := rng.randf()
		var shape := Peak.SUMMIT
		if roll < 0.2:
			shape = Peak.MASSIF
		elif roll < 0.42:
			shape = Peak.NEEDLES
		elif roll < 0.56:
			shape = Peak.MESA
		if shape == Peak.SUMMIT or shape != last:
			return shape
	return Peak.SUMMIT


## The plateau beyond the ridges: basalt crags with boulders round them, cinder cones
## (some still glowing) and boulders strewn on their own.
func _plateau(rng: RandomNumberGenerator, rows: int) -> void:
	var basin := _data.basin
	var near := ROW_OFFSET[rows - 1] + ROW_WIDTH[rows - 1].y * 0.6
	var placed: Array[NelvarEarthData.Thing] = []
	var crags := rng.randi_range(_config.plateau_crags.x, _config.plateau_crags.y)
	var cones := rng.randi_range(_config.cinder_cones.x, _config.cinder_cones.y)
	var boulders := rng.randi_range(_config.plateau_boulders.x, _config.plateau_boulders.y)
	for attempt in cones * 20:
		if cones <= 0:
			break
		var width := rng.randf_range(200.0, 340.0)
		var point := basin.point_at(rng.randf() * TAU, -rng.randf_range(near + 100.0, near + PLATEAU_DEPTH))
		if not _plateau_free(placed, point, width * 0.5 + 160.0):
			continue
		var cone := _plateau_thing(rng, Peak.GIANT, point, width * 0.5, rows)
		cone.size = Vector2(width, width * rng.randf_range(0.55, 0.8))
		cone.accent = rng.randf() < 0.5
		placed.append(cone)
		cones -= 1
	for attempt in crags * 20:
		if crags <= 0:
			break
		var width := rng.randf_range(240.0, 560.0)
		var point := basin.point_at(rng.randf() * TAU, -rng.randf_range(near, near + PLATEAU_DEPTH))
		if not _plateau_free(placed, point, width * 0.5 + 120.0):
			continue
		var crag := _plateau_thing(rng, Peak.CRAG, point, width * 0.5, rows)
		crag.size = Vector2(width, width * rng.randf_range(0.45, 0.8))
		placed.append(crag)
		crags -= 1
		for k in rng.randi_range(0, 3):
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var radius := rng.randf_range(20.0, 40.0)
			var spot := point + Vector2(side * rng.randf_range(0.5, 0.8) * width, rng.randf_range(10.0, 70.0))
			if _plateau_free(placed, spot, radius + 20.0):
				placed.append(_plateau_thing(rng, Peak.BOULDER, spot, radius, rows))
				boulders -= 1
	for attempt in maxi(0, boulders) * 20:
		if boulders <= 0:
			break
		var radius := rng.randf_range(44.0, 70.0) if rng.randf() < 0.25 else rng.randf_range(18.0, 40.0)
		var point := basin.point_at(rng.randf() * TAU, -rng.randf_range(near - 150.0, near + PLATEAU_DEPTH))
		if _plateau_free(placed, point, radius + 60.0):
			placed.append(_plateau_thing(rng, Peak.BOULDER, point, radius, rows))
			boulders -= 1


func _plateau_free(placed: Array[NelvarEarthData.Thing], point: Vector2, reach: float) -> bool:
	for other in placed:
		if point.distance_to(other.position) < reach + other.radius:
			return false
	return true


func _plateau_thing(rng: RandomNumberGenerator, shape: int, point: Vector2, radius: float,
		row: int) -> NelvarEarthData.Thing:
	var thing := NelvarEarthData.Thing.new()
	thing.kind = NelvarEarthData.Kind.PEAK
	thing.variant = shape
	thing.row = row
	thing.position = point
	thing.radius = radius
	thing.accent = rng.randf() < 0.4
	thing.appearance_seed = rng.randi()
	_data.peaks.append(thing)
	return thing
