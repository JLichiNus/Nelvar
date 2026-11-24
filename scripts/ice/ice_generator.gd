class_name NelvarIceGenerator
extends RefCounted
## Lays out the ice valley from a seed: the mountain foot, the spawn, frozen lakes with
## their thin ice and the creatures frozen in them, crevasses from the foot (and their
## branches) with snow bridges, clearings and the trodden trails between them,
## petrified creatures, pines under snow and dead trees, rocks, blocks of ice, drifts,
## dry grass and bare shrubs, and the rows of peaks round it all.
##
## Every stage draws from its own seeded generator, so changing one stage leaves the
## others as they were. Solid things always keep a passage wider than the player
## between them; trails, clearings and the spawn stay free of anything solid. Every
## stretch of a crevasse inside the valley has a bridge within `bridge_spacing`, trails
## cross crevasses only on bridges, and no crevasse comes within `ice_gap` of the ice.

const Kind = NelvarIceData.Kind
const Peak = NelvarEarthData.Peak

## How far placed things look for neighbours (largest branches plus margins).
const GRID := 160.0
## Peaks: distance of each row from the mountain foot and its base width range (as the
## earth's).
const ROW_OFFSET: Array[float] = [12.0, 230.0, 480.0, 760.0]
const ROW_WIDTH: Array[Vector2] = [Vector2(260.0, 400.0), Vector2(380.0, 560.0),
	Vector2(500.0, 720.0), Vector2(620.0, 860.0)]
## Each look of a peak (Peak order, ring looks only): base width and height factors.
const PEAK_LOOK: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(1.45, 0.6), Vector2(0.8, 1.3),
	Vector2(1.3, 0.55), Vector2(1.65, 1.0)]
const PLATEAU_DEPTH := 3600.0
## Trunk radius, reach of the branches and height: pines, dead trees.
const PINE_TRUNK := Vector2(11.0, 16.0)
const PINE_CROWN := Vector2(40.0, 58.0)
const PINE_HEIGHT := Vector2(170.0, 240.0)
const DEAD_TRUNK := Vector2(9.0, 13.0)
const DEAD_CROWN := Vector2(28.0, 44.0)
const DEAD_HEIGHT := Vector2(120.0, 180.0)
## A crevasse narrows to this half width at its inner end.
const TIP_HALF_WIDTH := 8.0

var _config: NelvarIceConfig
var _data: NelvarIceData
var _grid := {}
var _groves: Array[Vector2] = []


func generate(config: NelvarIceConfig, world_seed: int) -> NelvarIceData:
	var error := config.validation_error()
	if not error.is_empty():
		push_error("Ice config: " + error)
		return null
	_config = config
	_data = NelvarIceData.new()
	_data.world_seed = world_seed
	_grid.clear()
	_groves.clear()
	_valley(_rng("valley"))
	_lakes(_rng("lakes"))
	_thin_ice(_rng("thin"))
	_crevasses(_rng("crevasses"))
	_data.index_crevasses()
	_clearings(_rng("clearings"))
	_trails(_rng("trails"))
	_bridges(_rng("bridges"))
	_data.index_trails()
	_frozen(_rng("frozen"))
	_statues(_rng("statues"))
	_trees(_rng("trees"))
	_rocks(_rng("rocks"))
	_ice_blocks(_rng("blocks"))
	_drifts(_rng("drifts"))
	_plants(_rng("plants"))
	_snow_banks(_rng("banks"))
	_peaks(_rng("peaks"))
	_data.finish()
	var result := _data
	_data = null
	_grid.clear()
	return result


func _rng(stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:ice:%s" % [_data.world_seed, stage]).hash()
	return rng


# --- Valley, lakes, thin ice -----------------------------------------------------------

func _valley(rng: RandomNumberGenerator) -> void:
	var valley := _data.valley
	valley.center = Vector2.ZERO
	valley.axes = _config.valley_radius * Vector2(rng.randf_range(0.96, 1.04), rng.randf_range(0.96, 1.04))
	_bend(valley, rng, _config.valley_wobble, 0.2)
	_data.boundary = valley.polygon(_config.boundary_vertices)
	var spawn_angle := rng.randf() * TAU
	_data.spawn_position = valley.center + Vector2.from_angle(spawn_angle) \
		* valley.axes * rng.randf_range(0.0, 0.1)


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


func _lakes(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.lake_count.x, _config.lake_count.y)
	for attempt in 600:
		if _data.lakes.size() >= wanted:
			break
		# Later attempts try smaller lakes, so the least wanted always fit.
		var shrink := 1.0 - 0.45 * float(attempt) / 600.0
		var radius := lerpf(_config.lake_radius.x, _config.lake_radius.y, rng.randf() * shrink)
		var center := _random_valley_point(rng, 0.84)
		if _data.valley.signed_distance(center) < _config.lake_margin + radius:
			continue
		if center.distance_to(_data.spawn_position) < _config.spawn_clearance + radius + 160.0:
			continue
		var apart := true
		for other in _data.lakes:
			if center.distance_to(other.shape.center) < radius + other.shape.reach() + _config.lake_gap:
				apart = false
				break
		if not apart:
			continue
		var lake := NelvarIceData.Lake.new()
		lake.shape.center = center
		lake.shape.axes = Vector2(radius, radius * rng.randf_range(0.66, 0.82))
		_bend(lake.shape, rng, 0.1, 0.17)
		_data.lakes.append(lake)
		_data.lake_polygons.append(lake.shape.polygon(_config.lake_vertices))


## Patches of thin ice inside each lake: irregular, never touching the shore.
func _thin_ice(rng: RandomNumberGenerator) -> void:
	for lake in _data.lakes:
		var wanted := rng.randi_range(_config.thin_patches.x, _config.thin_patches.y)
		for attempt in 60:
			if lake.thin.size() >= wanted:
				break
			var radius := minf(rng.randf_range(_config.thin_radius.x, _config.thin_radius.y),
				lake.shape.axes.y * 0.5)
			var patch := NelvarEarthData.Radial.new()
			patch.center = lake.shape.center + Vector2.from_angle(rng.randf() * TAU) \
				* lake.shape.axes * sqrt(rng.randf()) * 0.62
			patch.axes = Vector2(radius, radius * rng.randf_range(0.6, 0.85))
			_bend(patch, rng, 0.16, 0.26)
			var inside := true
			for point in patch.polygon(24):
				if lake.shape.signed_distance(point) < 26.0:
					inside = false
					break
			for other in lake.thin:
				if patch.center.distance_to(other.center) < patch.reach() + other.reach() + 40.0:
					inside = false
			if inside:
				lake.thin.append(patch)


# --- Crevasses ----------------------------------------------------------------------

## Crevasses run from under the mountains into the valley; some branch off another.
func _crevasses(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.crevasse_count.x, _config.crevasse_count.y)
	for attempt in 80:
		if _data.crevasses.size() >= wanted:
			break
		if not _data.crevasses.is_empty() and rng.randf() < 0.35:
			_try_branch(rng)
		else:
			_try_from_foot(rng)


func _try_from_foot(rng: RandomNumberGenerator) -> bool:
	var angle := rng.randf() * TAU
	var start := _data.valley.point_at(angle, -60.0)
	var end := start.lerp(_data.valley.center, rng.randf_range(0.34, 0.6)) \
		+ Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 160.0)
	var points := _route(start, end, _config.crevasse_half_width.y + _config.ice_gap + 10.0, rng, true,
		0.14, false, _config.crevasse_half_width.y + 140.0)
	return _try_crevasse(rng, points, -1)


func _try_branch(rng: RandomNumberGenerator) -> bool:
	var parent_index := rng.randi_range(0, _data.crevasses.size() - 1)
	var parent := _data.crevasses[parent_index]
	if parent.parent >= 0 or parent.length() < 500.0:
		return false
	var along := parent.length() * rng.randf_range(0.3, 0.7)
	var start := parent.point_at(along)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var heading := parent.direction_at(along).rotated(side * rng.randf_range(0.7, 1.2))
	var end := start + heading * rng.randf_range(320.0, 620.0)
	var points := _route(start, end, _config.crevasse_half_width.y + _config.ice_gap + 10.0, rng, false,
		0.12, false, _config.crevasse_half_width.y + 140.0)
	return _try_crevasse(rng, points, parent_index)


## Keeps a crevasse that stays in the valley (but its first stretch from the foot), far
## from the ice, the spawn and the other crevasses; its width wanders along it and
## closes at its inner end.
func _try_crevasse(rng: RandomNumberGenerator, points: PackedVector2Array, parent_index: int) -> bool:
	var crevasse := NelvarIceData.Crevasse.new()
	crevasse.points = points
	crevasse.parent = parent_index
	crevasse.measure()
	var total := crevasse.length()
	if total < 260.0:
		return false
	var width := _config.crevasse_half_width
	var base := rng.randf_range(width.x, width.y)
	var salt := rng.randi() & 0xffff
	crevasse.half_widths.resize(points.size())
	for i in points.size():
		var t := crevasse.lengths[i] / total
		var wander := NelvarPixelArt.value_noise(crevasse.lengths[i] * 0.006, 0.5, salt)
		var half := clampf(base * (0.7 + 0.6 * wander), width.x, width.y)
		# The inner end closes; a branch starts as narrow as it is.
		half = lerpf(half, TIP_HALF_WIDTH, smoothstep(0.82, 1.0, t))
		crevasse.half_widths[i] = half
	var start := points[0]
	for i in points.size():
		var point := points[i]
		var half := crevasse.half_widths[i]
		var from_start := point.distance_to(start)
		if parent_index >= 0 or from_start > 220.0:
			if _data.valley.signed_distance(point) < half + 130.0:
				return false
		if _data.lake_depth(point) > -(half + _config.ice_gap):
			return false
		if point.distance_to(_data.spawn_position) < _config.spawn_clearance + half + 140.0:
			return false
		for c in _data.crevasses.size():
			var other := _data.crevasses[c]
			if c == parent_index and from_start < 160.0:
				continue
			var reach := half + other.widest() + 170.0
			if NelvarFireData.polyline_distance(other.points, point) < reach:
				return false
	_data.crevasses.append(crevasse)
	return true


## A gently bending line from a to b that keeps `keep_out` from the ice and clear of
## the mountain foot (a line from the foot may start beyond it). `bend`: how far it
## wanders, as a share of its length.
func _route(a: Vector2, b: Vector2, keep_out: float, rng: RandomNumberGenerator, from_foot: bool,
		bend: float, into_mountains: bool = false, margin: float = 130.0) -> PackedVector2Array:
	var length := a.distance_to(b)
	var count := maxi(3, int(length / 60.0))
	var normal := a.direction_to(b).orthogonal()
	var amplitude := minf(length * bend, 140.0) * rng.randf_range(0.4, 1.0)
	var waves := rng.randf_range(0.7, 1.9)
	var phase := rng.randf() * TAU
	var points: Array[Vector2] = []
	for i in count + 1:
		var t := float(i) / count
		var wave := sin(PI * t) * sin(phase + t * PI * waves) * amplitude
		points.append(a.lerp(b, t) + normal * wave)
	for iteration in 8:
		for i in range(1, points.size() - 1):
			var p := points[i]
			for lake in _data.lakes:
				var depth := lake.shape.signed_distance(p)
				if depth > -keep_out:
					p += lake.shape.center.direction_to(p) * (depth + keep_out)
			var t := float(i) / points.size()
			if not (from_foot and t < 0.18) and not (into_mountains and t > 0.8):
				var inside := _data.valley.signed_distance(p)
				if inside < margin:
					p += p.direction_to(_data.valley.center) * (margin - inside)
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


## Distance from the point to the nearest crevasse but `except` (INF without any).
func _other_crevasse_distance(point: Vector2, except: int) -> float:
	var best := INF
	for c in _data.crevasses.size():
		if c != except:
			best = minf(best, NelvarFireData.polyline_distance(_data.crevasses[c].points, point))
	return best


## Where a bridge may lie on a crevasse: well inside the valley, away from the other
## bridges and crevasses, on a straight enough stretch.
func _bridge_fits(index: int, along: float, half_length: float) -> bool:
	var crevasse := _data.crevasses[index]
	if along < half_length + 10.0 or along > crevasse.length() - half_length - 10.0:
		return false
	var center := crevasse.point_at(along)
	var half := crevasse.half_width_at(along)
	if _data.valley.signed_distance(center) < half + 130.0:
		return false
	if _other_crevasse_distance(center, index) < half + half_length + 90.0:
		return false
	for other in crevasse.bridges:
		if absf(other.along - along) < half_length + other.half_length + 60.0:
			return false
	var before := crevasse.direction_at(along - half_length)
	var after := crevasse.direction_at(along + half_length)
	return before.dot(after) > 0.86


func _add_bridge(crevasse: NelvarIceData.Crevasse, along: float, half_length: float) -> void:
	var bridge := NelvarIceData.Bridge.new()
	bridge.along = along
	bridge.center = crevasse.point_at(along)
	bridge.direction = crevasse.direction_at(along)
	bridge.half_length = half_length
	crevasse.bridges.append(bridge)
	crevasse.bridges.sort_custom(func(p: NelvarIceData.Bridge, q: NelvarIceData.Bridge) -> bool:
		return p.along < q.along)


## Every stretch of a crevasse inside the valley gets a bridge within bridge_spacing.
func _bridges(rng: RandomNumberGenerator) -> void:
	for index in _data.crevasses.size():
		var crevasse := _data.crevasses[index]
		var half_length := _config.bridge_half_length
		# The stretch well inside the valley, where the crack is wider than a step.
		var first := -1.0
		var last := -1.0
		var along := 0.0
		while along <= crevasse.length():
			var point := crevasse.point_at(along)
			var half := crevasse.half_width_at(along)
			if _data.valley.signed_distance(point) > half + 130.0 and half > TIP_HALF_WIDTH + 2.0:
				if first < 0.0:
					first = along
				last = along
			along += 10.0
		if first < 0.0 or last - first < half_length * 2.0 + 40.0:
			continue
		for guard in 14:
			var stops: Array[float] = [first]
			for bridge in crevasse.bridges:
				stops.append(bridge.along)
			stops.append(last)
			stops.sort()
			var widest := 0
			for i in stops.size() - 1:
				if stops[i + 1] - stops[i] > stops[widest + 1] - stops[widest]:
					widest = i
			var gap := stops[widest + 1] - stops[widest]
			if gap <= _config.bridge_spacing and not crevasse.bridges.is_empty():
				break
			var middle := (stops[widest] + stops[widest + 1]) * 0.5
			var placed := false
			for shift: float in [0.0, 40.0, -40.0, 80.0, -80.0, 130.0, -130.0, 180.0, -180.0]:
				var at := middle + shift * rng.randf_range(0.8, 1.2)
				if _bridge_fits(index, at, half_length):
					_add_bridge(crevasse, at, half_length)
					placed = true
					break
			if not placed:
				break


# --- Clearings and trails --------------------------------------------------------------

func _clearings(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.clearing_count.x, _config.clearing_count.y)
	var taken: Array[Vector2] = [_data.spawn_position]
	for lake in _data.lakes:
		taken.append(lake.shape.center)
	var candidates: Array[Vector2] = []
	for i in 80:
		var point := _random_valley_point(rng, 0.85)
		if _data.valley.signed_distance(point) > 300.0 and _data.lake_depth(point) < -200.0 \
				and _data.crevasse_sample(point).x < -180.0:
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


## Trodden trails join the spawn, the clearings and the lake shores (a spanning tree
## plus a few loops); some run off into the mountains. Where one crosses a crevasse,
## the crevasse gets a bridge there; a trail that would meet a crevasse badly is dropped.
func _trails(rng: RandomNumberGenerator) -> void:
	var nodes: Array[Vector2] = [_data.spawn_position]
	for clearing in _data.clearings:
		nodes.append(clearing.center)
	for lake in _data.lakes:
		var toward := (_data.spawn_position - lake.shape.center).angle() + rng.randf_range(-0.6, 0.6)
		nodes.append(lake.shape.center + Vector2.from_angle(toward) * (lake.shape.radius_at(toward) + 40.0))
	var edges: Array[Vector2i] = []
	# Prim's spanning tree.
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
		if added >= _config.extra_paths:
			break
		if _clear_angle(edge, edges, nodes):
			edges.append(edge)
			added += 1
	for edge in edges:
		var trail := NelvarEarthData.Trail.new()
		trail.half_width = rng.randf_range(_config.path_half_width.x, _config.path_half_width.y)
		trail.points = _route(nodes[edge.x], nodes[edge.y], trail.half_width + 44.0, rng, false, 0.09)
		_try_trail(trail)
	for i in _config.mountain_trails:
		var angle := -PI * 0.5 + rng.randf_range(-1.1, 1.1) if i % 2 == 0 else rng.randf_range(-PI, PI)
		var foot := _data.valley.point_at(angle, -50.0)
		var nearest := 0
		for n in nodes.size():
			if nodes[n].distance_to(foot) < nodes[nearest].distance_to(foot):
				nearest = n
		var trail := NelvarEarthData.Trail.new()
		trail.half_width = rng.randf_range(_config.path_half_width.x, _config.path_half_width.y) * 0.8
		trail.into_mountains = true
		trail.points = _route(nodes[nearest], foot, trail.half_width + 44.0, rng, false, 0.09, true)
		_try_trail(trail)


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


## Keeps a trail that stays off the ice and meets every crevasse it crosses on a bridge
## (made where needed); drops it otherwise.
func _try_trail(trail: NelvarEarthData.Trail) -> void:
	for point in trail.points:
		if _data.lake_depth(point) > -trail.half_width - 6.0:
			return
	var made: Array = []
	for index in _data.crevasses.size():
		var crevasse := _data.crevasses[index]
		for i in trail.points.size() - 1:
			var a := trail.points[i]
			var b := trail.points[i + 1]
			for j in crevasse.points.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, crevasse.points[j], crevasse.points[j + 1])
				if hit == null:
					continue
				var along := crevasse.lengths[j] + crevasse.points[j].distance_to(hit)
				var nearby: NelvarIceData.Bridge = null
				for bridge in crevasse.bridges:
					if absf(bridge.along - along) < bridge.half_length + 70.0:
						nearby = bridge
				if nearby != null and absf(nearby.along - along) < nearby.half_length * 0.5:
					continue
				if nearby != null:
					_undo_bridges(made)
					return
				var crossing_angle := absf(a.direction_to(b).dot(crevasse.points[j].direction_to(crevasse.points[j + 1])))
				var half_length := maxf(_config.bridge_half_length, trail.half_width + 30.0)
				if crossing_angle > 0.82 or not _bridge_fits(index, along, half_length):
					_undo_bridges(made)
					return
				_add_bridge(crevasse, along, half_length)
				made.append([crevasse, crevasse.bridges[crevasse.bridges.size() - 1]])
	# The trail never runs in a crack outside its bridges.
	for point in trail.points:
		if _data.crevasse_depth(point) > -trail.half_width * 0.6:
			_undo_bridges(made)
			return
	_data.trails.append(trail)


func _undo_bridges(made: Array) -> void:
	for entry: Array in made:
		var crevasse: NelvarIceData.Crevasse = entry[0]
		crevasse.bridges.erase(entry[1])


func _random_valley_point(rng: RandomNumberGenerator, reach: float) -> Vector2:
	var angle := rng.randf() * TAU
	return _data.valley.point_at(angle, 0.0).lerp(_data.valley.center, 1.0 - sqrt(rng.randf()) * reach)


# --- Frozen creatures -------------------------------------------------------------------

## Creatures frozen into the lakes, wholly under the ice; a share of them watch.
func _frozen(rng: RandomNumberGenerator) -> void:
	for l in _data.lakes.size():
		var lake := _data.lakes[l]
		var wanted := rng.randi_range(_config.frozen_per_lake.x, _config.frozen_per_lake.y)
		var placed := 0
		for attempt in 50:
			if placed >= wanted:
				break
			var radius := minf(rng.randf_range(36.0, 80.0), lake.shape.axes.y * 0.45)
			var point := lake.shape.center + Vector2.from_angle(rng.randf() * TAU) \
				* lake.shape.axes * sqrt(rng.randf()) * 0.7
			if lake.shape.signed_distance(point) < radius + 24.0:
				continue
			var apart := true
			for other in _data.frozen:
				if other.position.distance_to(point) < other.radius + radius + 30.0:
					apart = false
			if not apart:
				continue
			var creature := NelvarIceData.Frozen.new()
			creature.lake = l
			creature.position = point
			creature.radius = radius
			creature.variant = rng.randi_range(0, NelvarIceData.Creature.size() - 1)
			creature.appearance_seed = rng.randi()
			creature.eye = rng.randf() < _config.watching_share
			creature.facing_left = rng.randf() < 0.5
			_data.frozen.append(creature)
			placed += 1
	# The ice is alive: at least one of them watches.
	var watching := false
	for creature in _data.frozen:
		watching = watching or creature.eye
	if not watching and not _data.frozen.is_empty():
		_data.frozen[0].eye = true


# --- Placement rules ------------------------------------------------------------

func _add(thing: NelvarIceData.Thing) -> void:
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


## Shared rules for anything placed in the valley. `trail_gap` is the free ground kept
## beside trails, `lake_gap` the snow kept from the ice (negative: may stand on the
## ice, never on thin ice), `crevasse_gap` the snow kept from a crack (bridges count
## as cracks here: nothing stands on them).
func _fits(point: Vector2, radius: float, solid: bool, trail_gap: float, lake_gap: float,
		crevasse_gap: float, plant_spacing: float = 0.7) -> bool:
	if _data.valley.signed_distance(point) < radius + (60.0 if solid else 24.0):
		return false
	if lake_gap >= 0.0 and _data.lake_depth(point) > -(radius + lake_gap):
		return false
	if _data.thin_depth(point) > -(radius + 30.0):
		return false
	if _data.crevasse_sample(point).x > -(radius + crevasse_gap):
		return false
	var spawn_gap := _config.spawn_clearance if solid else 60.0
	if point.distance_to(_data.spawn_position) < spawn_gap + radius:
		return false
	if solid:
		for clearing in _data.clearings:
			if point.distance_to(clearing.center) < clearing.radius + radius:
				return false
	if trail_gap >= 0.0 and _data.trail_clearance(point) < radius + trail_gap:
		return false
	for other: NelvarIceData.Thing in _nearby(point, 280.0):
		var distance := point.distance_to(other.position)
		if other.solid and solid:
			var gap := _config.passage_width
			if other.is_tree() and radius > 0.0:
				gap = maxf(gap, _config.tree_spacing - other.radius - radius)
			if distance < radius + other.spread() + gap:
				return false
		elif other.solid or solid:
			if distance < (radius + other.spread()) * 0.85:
				return false
		elif distance < (radius + other.radius) * plant_spacing:
			return false
		# Nothing hides behind a crown.
		if other.crown_hides(point, radius * 0.3):
			return false
	return true


func _crown_is_clear(tree: NelvarIceData.Thing) -> bool:
	if tree.kind != Kind.PINE:
		return true
	for other: NelvarIceData.Thing in _nearby(tree.crown_center(), tree.size.x + 120.0):
		if other.kind == Kind.STATUE and other.position.distance_to(tree.crown_center()) \
				< tree.size.x + other.radius * 2.2:
			return false
		if other.kind != Kind.PINE and tree.crown_hides(other.position):
			return false
	return true


# --- Statues, trees, stone, ice, drifts ---------------------------------------------

## Petrified creatures: big, solid, far apart, often at the edge of a clearing.
func _statues(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.statues.x, _config.statues.y)
	var placed: Array[Vector2] = []
	for attempt in 300:
		if placed.size() >= wanted:
			break
		var radius := rng.randf_range(44.0, 58.0)
		var point := _random_valley_point(rng, 0.78)
		if attempt < 120 and not _data.clearings.is_empty():
			var clearing := _data.clearings[rng.randi_range(0, _data.clearings.size() - 1)]
			point = clearing.center + Vector2.from_angle(rng.randf() * TAU) \
				* (clearing.radius + radius * 1.5 + rng.randf_range(10.0, 60.0))
		if _data.valley.signed_distance(point) < radius + 180.0:
			continue
		if point.distance_to(_data.spawn_position) < _config.spawn_clearance + radius + 140.0:
			continue
		var far := true
		for other in placed:
			if point.distance_to(other) < 650.0:
				far = false
		if not far or not _fits(point, radius * 1.45, true, _config.path_clearance + 30.0, 70.0,
				_config.crevasse_clearance + 30.0):
			continue
		var statue := NelvarIceData.Thing.new()
		statue.kind = Kind.STATUE
		statue.position = point
		statue.radius = radius
		statue.solid = true
		statue.accent = rng.randf() < 0.5
		statue.appearance_seed = rng.randi()
		_add(statue)
		placed.append(point)


func _trees(rng: RandomNumberGenerator) -> void:
	# Groves of pines under snow, a dead tree or two at their edge.
	var wanted := rng.randi_range(_config.pine_groves.x, _config.pine_groves.y)
	for attempt in 300:
		if _groves.size() >= wanted:
			break
		var center := _random_valley_point(rng, 0.92)
		if not _grove_ground(center):
			continue
		_groves.append(center)
		var radius := rng.randf_range(_config.grove_radius.x, _config.grove_radius.y)
		var count := rng.randi_range(_config.grove_trees.x, _config.grove_trees.y)
		var deep := rng.randf() < 0.5
		var grown := 0
		for t in count * 8:
			if grown >= count:
				break
			var point := center + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf())
			var pine := _try_tree(rng, Kind.PINE, point)
			if pine != null:
				pine.accent = deep if rng.randf() < 0.8 else not deep
				grown += 1
	# Lone pines in the open.
	var lone := rng.randi_range(_config.lone_pines.x, _config.lone_pines.y)
	var grown_lone := 0
	for attempt in lone * 10:
		if grown_lone >= lone:
			break
		var pine := _try_tree(rng, Kind.PINE, _random_valley_point(rng, 0.95))
		if pine != null:
			pine.accent = rng.randf() < 0.4
			grown_lone += 1
	# Stands of pines along the mountain foot, deep in snow.
	var foot := rng.randi_range(10, 16)
	var grown_foot := 0
	for attempt in 160:
		if grown_foot >= foot:
			break
		var stand := _data.valley.point_at(rng.randf() * TAU, rng.randf_range(90.0, 260.0))
		for k in rng.randi_range(2, 4):
			var point := stand + Vector2(rng.randf_range(-130.0, 130.0), rng.randf_range(-80.0, 80.0))
			var pine := _try_tree(rng, Kind.PINE, point)
			if pine != null:
				pine.accent = rng.randf() < 0.75
				grown_foot += 1
	# Dead trees: at the edge of a grove or alone.
	var dead := rng.randi_range(_config.dead_trees.x, _config.dead_trees.y)
	var grown_dead := 0
	for attempt in dead * 12:
		if grown_dead >= dead:
			break
		var point := _random_valley_point(rng, 0.94)
		if rng.randf() < 0.55 and not _groves.is_empty():
			var grove := _groves[rng.randi_range(0, _groves.size() - 1)]
			point = grove + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(160.0, 340.0)
		if _try_tree(rng, Kind.DEAD_TREE, point) != null:
			grown_dead += 1


func _grove_ground(center: Vector2) -> bool:
	if _data.valley.signed_distance(center) < 160.0 or _data.lake_depth(center) > -120.0:
		return false
	if _data.crevasse_sample(center).x > -120.0:
		return false
	if center.distance_to(_data.spawn_position) < _config.spawn_clearance + 220.0:
		return false
	for other in _groves:
		if center.distance_to(other) < 420.0:
			return false
	for clearing in _data.clearings:
		if center.distance_to(clearing.center) < clearing.radius + 140.0:
			return false
	return true


func _try_tree(rng: RandomNumberGenerator, kind: int, point: Vector2) -> NelvarIceData.Thing:
	var tree := NelvarIceData.Thing.new()
	tree.kind = kind
	tree.solid = true
	var scale := rng.randf()
	var pine := kind == Kind.PINE
	var trunk := PINE_TRUNK if pine else DEAD_TRUNK
	var crown := PINE_CROWN if pine else DEAD_CROWN
	var height := PINE_HEIGHT if pine else DEAD_HEIGHT
	tree.radius = lerpf(trunk.x, trunk.y, scale)
	tree.size = Vector2(lerpf(crown.x, crown.y, scale * 0.7 + rng.randf() * 0.3),
		lerpf(height.x, height.y, scale * 0.6 + rng.randf() * 0.4))
	tree.position = point
	tree.variant = rng.randi_range(0, 2)
	tree.appearance_seed = rng.randi()
	if not _fits(point, tree.radius, true, _config.path_clearance, 50.0, _config.crevasse_clearance):
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
		if _try_rock(rng, _random_valley_point(rng, 0.94), radius, rng.randf() < 0.45):
			placed += 1
	# Scree at the mountain foot, in loose heaps.
	var scree := rng.randi_range(_config.scree_rocks.x, _config.scree_rocks.y)
	var heaped := 0
	for attempt in 260:
		if heaped >= scree:
			break
		var heap := _data.valley.point_at(rng.randf() * TAU, rng.randf_range(80.0, 170.0))
		for k in rng.randi_range(2, 4):
			var radius := rng.randf_range(12.0, 34.0)
			var point := heap + Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-50.0, 50.0))
			if _data.valley.signed_distance(point) < radius + 60.0:
				continue
			if _try_rock(rng, point, radius, rng.randf() < 0.6):
				heaped += 1


func _try_rock(rng: RandomNumberGenerator, point: Vector2, radius: float, big_cap: bool) -> bool:
	if not _fits(point, radius, true, _config.path_clearance, 30.0, _config.crevasse_clearance):
		return false
	var rock := NelvarIceData.Thing.new()
	rock.kind = Kind.ROCK
	rock.position = point
	rock.radius = radius
	rock.solid = true
	rock.accent = big_cap
	rock.appearance_seed = rng.randi()
	_add(rock)
	return true


## Blocks and pressure ridges of ice: on the lake shores and at the foot, and a few out
## on the ice itself, where they are the only cover.
func _ice_blocks(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.ice_blocks.x, _config.ice_blocks.y)
	var placed := 0
	for attempt in wanted * 16:
		if placed >= wanted:
			break
		var ridge := rng.randf() < 0.35
		var radius := rng.randf_range(34.0, 56.0) if ridge else rng.randf_range(18.0, 40.0)
		var point := _data.valley.point_at(rng.randf() * TAU, rng.randf_range(90.0, 220.0))
		if rng.randf() < 0.65 and not _data.lakes.is_empty():
			var lake := _data.lakes[rng.randi_range(0, _data.lakes.size() - 1)]
			point = lake.shape.point_at(rng.randf() * TAU, -(radius * 0.6 + rng.randf_range(30.0, 80.0)))
		if _try_block(rng, point, radius, ridge, false):
			placed += 1
	for lake in _data.lakes:
		var count := rng.randi_range(_config.lake_blocks.x, _config.lake_blocks.y)
		var out := 0
		for attempt in count * 16:
			if out >= count:
				break
			var ridge := rng.randf() < 0.4
			var radius := rng.randf_range(30.0, 48.0) if ridge else rng.randf_range(18.0, 34.0)
			var point := lake.shape.center + Vector2.from_angle(rng.randf() * TAU) \
				* lake.shape.axes * sqrt(rng.randf()) * 0.8
			if lake.shape.signed_distance(point) < radius + 40.0:
				continue
			var hides := false
			for creature in _data.frozen:
				if creature.position.distance_to(point) < creature.radius + radius + 20.0:
					hides = true
			if not hides and _try_block(rng, point, radius, ridge, true):
				out += 1


func _try_block(rng: RandomNumberGenerator, point: Vector2, radius: float, ridge: bool, on_ice: bool) -> bool:
	var block := NelvarIceData.Thing.new()
	block.kind = Kind.ICE_BLOCK
	block.variant = NelvarIceData.Block.RIDGE if ridge else NelvarIceData.Block.CHUNK
	block.position = point
	block.radius = radius
	block.solid = true
	block.accent = on_ice
	if not _fits(point, block.spread(), true, _config.path_clearance, -1.0 if on_ice else 24.0,
			_config.crevasse_clearance):
		return false
	block.appearance_seed = rng.randi()
	_add(block)
	return true


## Snowdrifts: in the lee (east) of rocks and trees, along the foot and in the open.
func _drifts(rng: RandomNumberGenerator) -> void:
	var hosts: Array[NelvarIceData.Thing] = []
	for thing in _data.things:
		if thing.kind in [Kind.ROCK, Kind.PINE, Kind.STATUE]:
			hosts.append(thing)
	var wanted := rng.randi_range(_config.drifts.x, _config.drifts.y)
	var placed := 0
	for attempt in wanted * 16:
		if placed >= wanted:
			break
		var radius := rng.randf_range(30.0, 60.0)
		var point := _random_valley_point(rng, 0.92)
		var roll := rng.randf()
		if roll < 0.45 and not hosts.is_empty():
			var host := hosts[rng.randi_range(0, hosts.size() - 1)]
			point = host.position + Vector2(host.spread() + radius + _config.passage_width + rng.randf_range(4.0, 30.0),
				rng.randf_range(-16.0, 16.0))
		elif roll < 0.7:
			point = _data.valley.point_at(rng.randf() * TAU, rng.randf_range(90.0, 200.0))
		var drift := NelvarIceData.Thing.new()
		drift.kind = Kind.DRIFT
		drift.position = point
		drift.radius = radius
		drift.solid = true
		drift.variant = rng.randi_range(0, 2)
		drift.accent = rng.randf() < 0.5
		if _fits(point, drift.spread(), true, _config.path_clearance, 40.0, _config.crevasse_clearance):
			drift.appearance_seed = rng.randi()
			_add(drift)
			placed += 1


# --- Plants -------------------------------------------------------------------------

## Dry grass pokes out of the snow in the open and round rocks and drifts; bare shrubs
## stand at the foot of trees and rocks.
func _plants(rng: RandomNumberGenerator) -> void:
	var hosts: Array[NelvarIceData.Thing] = []
	for thing in _data.things:
		if thing.kind in [Kind.PINE, Kind.DEAD_TREE, Kind.ROCK, Kind.DRIFT]:
			hosts.append(thing)
	var meadows: Array[Vector2] = []
	for attempt in 200:
		if meadows.size() >= 14:
			break
		var point := _random_valley_point(rng, 0.9)
		if _data.lake_depth(point) < -80.0:
			meadows.append(point)
	if meadows.is_empty():
		meadows.append(_data.spawn_position + Vector2(300.0, 0.0))
	var in_open := func() -> Vector2:
		if rng.randf() < 0.35 and not hosts.is_empty():
			var host: NelvarIceData.Thing = hosts[rng.randi_range(0, hosts.size() - 1)]
			return host.position + Vector2.from_angle(rng.randf_range(-0.3, PI + 0.3)) \
				* (host.spread() + rng.randf_range(12.0, 50.0))
		return meadows[rng.randi_range(0, meadows.size() - 1)] \
			+ Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.7, 0.7)) * 240.0
	var by_host := func() -> Vector2:
		if hosts.is_empty():
			return _random_valley_point(rng, 0.9)
		var host: NelvarIceData.Thing = hosts[rng.randi_range(0, hosts.size() - 1)]
		return host.position + Vector2.from_angle(rng.randf_range(-0.2, PI + 0.2)) \
			* (host.spread() + rng.randf_range(20.0, 60.0))
	_scatter(rng, Kind.DRY_GRASS, rng.randi_range(_config.dry_grass.x, _config.dry_grass.y),
		Vector2(10.0, 18.0), 3, in_open, 2.0)
	_scatter(rng, Kind.SHRUB, rng.randi_range(_config.shrubs.x, _config.shrubs.y),
		Vector2(16.0, 26.0), 2, by_host, 4.0)


func _scatter(rng: RandomNumberGenerator, kind: Kind, count: int, radius_range: Vector2,
		variants: int, pick: Callable, trail_gap: float) -> void:
	var placed := 0
	for attempt in count * 12:
		if placed >= count:
			break
		var point: Vector2 = pick.call()
		var radius := rng.randf_range(radius_range.x, radius_range.y)
		if not _fits(point, radius, false, trail_gap, 14.0, 20.0):
			continue
		var plant := NelvarIceData.Thing.new()
		plant.kind = kind
		plant.position = point
		plant.radius = radius
		plant.variant = rng.randi_range(0, variants - 1)
		plant.accent = rng.randf() < (0.3 if kind == Kind.SHRUB else 0.5)
		plant.appearance_seed = rng.randi()
		_add(plant)
		placed += 1


## Fields of wind-blown snow for the floor: off the ice and the spawn.
func _snow_banks(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.snow_banks.x, _config.snow_banks.y)
	for attempt in 80:
		if _data.snow_banks.size() >= wanted:
			break
		var radius := rng.randf_range(140.0, 260.0)
		var center := _random_valley_point(rng, 0.9)
		if _data.lake_depth(center) > -radius * 0.6 or center.distance_to(_data.spawn_position) < radius:
			continue
		var apart := true
		for other in _data.snow_banks:
			if center.distance_to(Vector2(other.x, other.y)) < radius + other.z + 120.0:
				apart = false
		if apart:
			_data.snow_banks.append(Vector3(center.x, center.y, radius))


# --- Mountains ------------------------------------------------------------------

## Rows of peaks along the mountain foot, then crags and boulders on the plateau beyond
## them. Peaks on the south side are lower: they stand between the camera and the valley.
func _peaks(rng: RandomNumberGenerator) -> void:
	var valley := _data.valley
	var rows := _config.peak_rows
	for row in rows:
		var angle := rng.randf() * TAU
		var travelled := 0.0
		var widths := ROW_WIDTH[row]
		var last := Peak.SUMMIT
		while travelled < TAU:
			var shape := _peak_shape(rng, row, last)
			last = shape
			var look: Vector2 = PEAK_LOOK[shape]
			var width := rng.randf_range(widths.x, widths.y) * look.x
			var outward := Vector2.from_angle(angle)
			var south := maxf(0.0, outward.y)
			var offset := ROW_OFFSET[row] + width * 0.36 * absf(outward.x) * (1.0 if row == 0 else 0.5)
			var peak := NelvarEarthData.Thing.new()
			peak.kind = NelvarEarthData.Kind.PEAK
			peak.variant = shape
			peak.row = row
			peak.position = valley.point_at(angle, -offset)
			peak.radius = width * 0.5
			var height := width * rng.randf_range(0.92, 1.25) * look.y * lerpf(1.0, 0.58, south)
			peak.size = Vector2(width, height)
			peak.appearance_seed = rng.randi()
			_data.peaks.append(peak)
			var spacing := width * (rng.randf_range(0.36, 0.5) if row == 0 else rng.randf_range(0.42, 0.58))
			# The outermost row breaks up: the plateau shows between its peaks.
			if row == rows - 1 and row > 0 and rng.randf() < 0.3:
				spacing += width * rng.randf_range(0.4, 0.9)
			var step := spacing / maxf(valley.radius_at(angle) + offset, 1.0)
			angle = wrapf(angle + step, -PI, PI)
			travelled += step
	_plateau(rng, rows)


## Look of the next peak in a row: mostly summits, the others never twice in a row;
## giants only behind the nearest row.
func _peak_shape(rng: RandomNumberGenerator, row: int, last: int) -> int:
	for attempt in 4:
		var roll := rng.randf()
		var shape := Peak.SUMMIT
		if roll < 0.18:
			shape = Peak.MASSIF
		elif roll < 0.34:
			shape = Peak.NEEDLES
		elif roll < 0.44:
			shape = Peak.MESA
		elif roll < 0.6 and row > 0:
			shape = Peak.GIANT
		if shape == Peak.SUMMIT or shape != last:
			return shape
	return Peak.SUMMIT


## The plateau beyond the range: rocky crags with boulders round them, and boulders
## strewn on their own, all deep in snow.
func _plateau(rng: RandomNumberGenerator, rows: int) -> void:
	var valley := _data.valley
	var near := ROW_OFFSET[rows - 1] + ROW_WIDTH[rows - 1].y * 0.6
	var placed: Array[NelvarEarthData.Thing] = []
	var crags := rng.randi_range(_config.plateau_crags.x, _config.plateau_crags.y)
	var boulders := rng.randi_range(_config.plateau_boulders.x, _config.plateau_boulders.y)
	for attempt in crags * 20:
		if crags <= 0:
			break
		var width := rng.randf_range(240.0, 560.0)
		var point := valley.point_at(rng.randf() * TAU, -rng.randf_range(near, near + PLATEAU_DEPTH))
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
		var point := valley.point_at(rng.randf() * TAU, -rng.randf_range(near - 150.0, near + PLATEAU_DEPTH))
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
	thing.accent = rng.randf() < 0.5
	thing.appearance_seed = rng.randi()
	_data.peaks.append(thing)
	return thing
