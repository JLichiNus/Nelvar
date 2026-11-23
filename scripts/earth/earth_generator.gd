class_name NelvarEarthGenerator
extends RefCounted
## Lays out the earth valley from a seed: the mountain foot, the spawn, ponds,
## clearings and the trails between them, petrified creatures, groves of different
## trees, rocks, plants, and the rows of peaks around it all.
##
## Every stage draws from its own seeded generator, so changing one stage leaves the
## others as they were. Solid things always keep a passage wider than the player
## between them; trails, clearings and the spawn stay free of anything solid.

const Kind = NelvarEarthData.Kind
const Species = NelvarEarthData.Species

## How far placed things look for neighbours (largest crown plus margins).
const GRID := 160.0
## Peaks: distance of each row from the mountain foot and its base width range.
const ROW_OFFSET: Array[float] = [12.0, 230.0, 480.0, 760.0]
const ROW_WIDTH: Array[Vector2] = [Vector2(260.0, 400.0), Vector2(380.0, 560.0),
	Vector2(500.0, 720.0), Vector2(620.0, 860.0)]

## Trunk radius, crown radius and height of each species (Species order).
const TRUNK: Array[Vector2] = [Vector2(17, 23), Vector2(11, 14), Vector2(13, 17),
	Vector2(13, 17), Vector2(14, 18), Vector2(17, 22), Vector2(15, 19)]
const CROWN: Array[Vector2] = [Vector2(66, 92), Vector2(40, 54), Vector2(40, 54),
	Vector2(56, 74), Vector2(56, 72), Vector2(70, 92), Vector2(60, 80)]
const HEIGHT: Array[Vector2] = [Vector2(170, 220), Vector2(170, 220), Vector2(190, 250),
	Vector2(140, 180), Vector2(140, 175), Vector2(160, 200), Vector2(160, 205)]

## Species of lone trees in the open, picked evenly (oaks twice as often).
const LONE_SPECIES: Array[int] = [Species.OAK, Species.OAK, Species.BIRCH, Species.APPLE,
	Species.BLOSSOM, Species.MAPLE]

var _config: NelvarEarthConfig
var _data: NelvarEarthData
var _grid := {}
var _groves: Array[Vector2] = []


func generate(config: NelvarEarthConfig, world_seed: int) -> NelvarEarthData:
	var error := config.validation_error()
	if not error.is_empty():
		push_error("Earth config: " + error)
		return null
	_config = config
	_data = NelvarEarthData.new()
	_data.world_seed = world_seed
	_grid.clear()
	_groves.clear()
	_valley(_rng("valley"))
	_ponds(_rng("ponds"))
	_clearings(_rng("clearings"))
	_trails(_rng("trails"))
	_data.index_trails()
	_statues(_rng("statues"))
	_trees(_rng("trees"))
	_rocks(_rng("rocks"))
	_deadwood(_rng("deadwood"))
	_plants(_rng("plants"))
	_water_plants(_rng("water"))
	_peaks(_rng("peaks"))
	_data.finish()
	var result := _data
	_data = null
	_grid.clear()
	return result


func _rng(stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:earth:%s" % [_data.world_seed, stage]).hash()
	return rng


# --- Valley, ponds, clearings, trails ------------------------------------------

func _valley(rng: RandomNumberGenerator) -> void:
	var valley := _data.valley
	valley.center = Vector2.ZERO
	valley.axes = _config.valley_radius * Vector2(rng.randf_range(0.96, 1.04), rng.randf_range(0.96, 1.04))
	_bend(valley, rng, _config.valley_wobble, 0.2)
	_data.boundary = valley.polygon(_config.boundary_vertices)
	var spawn_angle := rng.randf() * TAU
	_data.spawn_position = valley.center + Vector2.from_angle(spawn_angle) \
		* valley.axes * rng.randf_range(0.0, 0.1)


## Slow bends: harmonic k gets a share of `depth` falling with k; the sum stays
## below `limit`, so the shape never pinches.
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


func _ponds(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.pond_count.x, _config.pond_count.y)
	for attempt in 400:
		if _data.ponds.size() >= wanted:
			break
		var radius := rng.randf_range(_config.pond_radius.x, _config.pond_radius.y)
		var center := _random_valley_point(rng, 0.86)
		if _data.valley.signed_distance(center) < _config.pond_margin + radius:
			continue
		if center.distance_to(_data.spawn_position) < _config.spawn_clearance + radius + 160.0:
			continue
		var apart := true
		for other in _data.ponds:
			if center.distance_to(other.center) < radius + other.reach() + _config.pond_gap:
				apart = false
				break
		if not apart:
			continue
		var pond := NelvarEarthData.Radial.new()
		pond.center = center
		pond.axes = Vector2(radius, radius * rng.randf_range(0.66, 0.8))
		_bend(pond, rng, 0.1, 0.17)
		_data.ponds.append(pond)
		_data.pond_polygons.append(pond.polygon(_config.pond_vertices))


func _clearings(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.clearing_count.x, _config.clearing_count.y)
	var taken: Array[Vector2] = [_data.spawn_position]
	for pond in _data.ponds:
		taken.append(pond.center)
	var candidates: Array[Vector2] = []
	for i in 60:
		var point := _random_valley_point(rng, 0.85)
		if _data.valley.signed_distance(point) > 300.0 and _data.pond_depth(point) < -220.0:
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


## Trails join the spawn, the clearings and the pond shores (a spanning tree plus a
## few loops); some run off into the mountains. They bend gently and go round ponds.
func _trails(rng: RandomNumberGenerator) -> void:
	var nodes: Array[Vector2] = [_data.spawn_position]
	for clearing in _data.clearings:
		nodes.append(clearing.center)
	for pond in _data.ponds:
		var toward := (_data.spawn_position - pond.center).angle() + rng.randf_range(-0.6, 0.6)
		nodes.append(pond.center + Vector2.from_angle(toward) * (pond.radius_at(toward) + 34.0))
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
	# Loops: the shortest missing links that leave their ends at a clear angle.
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
		trail.points = _route(nodes[edge.x], nodes[edge.y], trail.half_width, rng, false)
		if _trail_is_dry(trail):
			_data.trails.append(trail)
	# Trails into the mountains, from the nearest node to the foot, mostly northwards.
	for i in _config.mountain_trails:
		var angle := -PI * 0.5 + rng.randf_range(-1.1, 1.1) if i % 2 == 0 \
			else rng.randf_range(-PI, PI)
		var foot := _data.valley.point_at(angle, -50.0)
		var nearest := 0
		for n in nodes.size():
			if nodes[n].distance_to(foot) < nodes[nearest].distance_to(foot):
				nearest = n
		var trail := NelvarEarthData.Trail.new()
		trail.half_width = rng.randf_range(_config.path_half_width.x, _config.path_half_width.y) * 0.8
		trail.into_mountains = true
		trail.points = _route(nodes[nearest], foot, trail.half_width, rng, true)
		if _trail_is_dry(trail):
			_data.trails.append(trail)


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


## A gently bending line from a to b that keeps clear of ponds and of the mountain foot.
func _route(a: Vector2, b: Vector2, half_width: float, rng: RandomNumberGenerator,
		into_mountains: bool) -> PackedVector2Array:
	var length := a.distance_to(b)
	var count := maxi(3, int(length / 60.0))
	var normal := a.direction_to(b).orthogonal()
	var amplitude := minf(length * 0.09, 110.0) * rng.randf_range(0.4, 1.0)
	var waves := rng.randf_range(0.7, 1.7)
	var phase := rng.randf() * TAU
	var points: Array[Vector2] = []
	for i in count + 1:
		var t := float(i) / count
		var bend := sin(PI * t) * sin(phase + t * PI * waves) * amplitude
		points.append(a.lerp(b, t) + normal * bend)
	var keep_out := half_width + 44.0
	for iteration in 8:
		for i in range(1, points.size() - 1):
			var p := points[i]
			for pond in _data.ponds:
				var depth := pond.signed_distance(p)
				if depth > -keep_out:
					p += pond.center.direction_to(p) * (depth + keep_out)
			# The last stretch of a mountain trail may reach the foot.
			if not (into_mountains and float(i) / points.size() > 0.8):
				var inside := _data.valley.signed_distance(p)
				var limit := half_width + 90.0
				if inside < limit:
					p += p.direction_to(_data.valley.center) * (limit - inside)
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


func _trail_is_dry(trail: NelvarEarthData.Trail) -> bool:
	for point in trail.points:
		if _data.pond_depth(point) > -trail.half_width - 4.0:
			return false
	return true


func _random_valley_point(rng: RandomNumberGenerator, reach: float) -> Vector2:
	var angle := rng.randf() * TAU
	return _data.valley.point_at(angle, 0.0).lerp(_data.valley.center, 1.0 - sqrt(rng.randf()) * reach)


# --- Placement rules ------------------------------------------------------------

func _add(thing: NelvarEarthData.Thing) -> void:
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


## Shared rules for anything placed on the plain. `trail_gap` is the free ground kept
## beside trails, `crown_margin` how far outside a tree crown it must stay (behind
## the tree), `water_gap` the ground kept from ponds (negative: may stand in water).
func _fits(point: Vector2, radius: float, solid: bool, trail_gap: float, water_gap: float,
		plant_spacing: float = 0.7) -> bool:
	if _data.valley.signed_distance(point) < radius + (60.0 if solid else 24.0):
		return false
	if _data.pond_depth(point) > -(radius + water_gap):
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
	for other: NelvarEarthData.Thing in _nearby(point, 280.0):
		if other.kind == Kind.PEAK:
			continue
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
		# Nothing hides behind a crown, and no crown hides a statue.
		if other.crown_hides(point, radius * 0.3):
			return false
	return true


func _crown_is_clear(tree: NelvarEarthData.Thing) -> bool:
	for other: NelvarEarthData.Thing in _nearby(tree.crown_center(), tree.size.x + 120.0):
		if other.kind == Kind.STATUE and other.position.distance_to(tree.crown_center()) \
				< tree.size.x + other.radius * 2.2:
			return false
		if other.kind != Kind.TREE and other.kind != Kind.PEAK and tree.crown_hides(other.position):
			return false
	return true


# --- Statues, trees, rocks, deadwood ----------------------------------------

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
		if not far or not _fits(point, radius * 1.45, true, _config.path_clearance + 30.0, 70.0):
			continue
		var statue := NelvarEarthData.Thing.new()
		statue.kind = Kind.STATUE
		statue.position = point
		statue.radius = radius
		statue.solid = true
		statue.accent = rng.randf() < 0.5
		statue.appearance_seed = rng.randi()
		_add(statue)
		placed.append(point)


func _trees(rng: RandomNumberGenerator) -> void:
	# Willows lean over the ponds.
	for pond in _data.ponds:
		var wanted := rng.randi_range(_config.willows_per_pond.x, _config.willows_per_pond.y)
		var placed := 0
		for attempt in 40:
			if placed >= wanted:
				break
			var angle := rng.randf() * TAU
			var point := pond.point_at(angle, -rng.randf_range(46.0, 90.0))
			if _try_tree(rng, Species.WILLOW, point, 20.0) != null:
				placed += 1
	# Groves: one main species each, a few trees of another mixed in.
	var wanted_groves := rng.randi_range(_config.grove_count.x, _config.grove_count.y)
	for attempt in 300:
		if _groves.size() >= wanted_groves:
			break
		var center := _random_valley_point(rng, 0.92)
		if _data.valley.signed_distance(center) < 160.0 or _data.pond_depth(center) > -120.0:
			continue
		if center.distance_to(_data.spawn_position) < _config.spawn_clearance + 220.0:
			continue
		var spaced := true
		for other in _groves:
			if center.distance_to(other) < 420.0:
				spaced = false
		for clearing in _data.clearings:
			if center.distance_to(clearing.center) < clearing.radius + 140.0:
				spaced = false
		if not spaced:
			continue
		_groves.append(center)
		var foot := _data.valley.signed_distance(center) < 520.0
		var main := _grove_species(rng, foot)
		var radius := rng.randf_range(_config.grove_radius.x, _config.grove_radius.y)
		var count := rng.randi_range(_config.grove_trees.x, _config.grove_trees.y)
		var grown := 0
		for t in count * 8:
			if grown >= count:
				break
			var species := main
			if rng.randf() < 0.22:
				species = Species.BIRCH if main == Species.OAK else Species.OAK
			var point := center + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf())
			if _try_tree(rng, species, point, 50.0) != null:
				grown += 1
	# Lone trees in the open.
	var lone := rng.randi_range(_config.lone_trees.x, _config.lone_trees.y)
	var grown_lone := 0
	for attempt in lone * 10:
		if grown_lone >= lone:
			break
		var species := LONE_SPECIES[rng.randi_range(0, LONE_SPECIES.size() - 1)]
		if _try_tree(rng, species, _random_valley_point(rng, 0.95), 50.0) != null:
			grown_lone += 1
	# Stands of pines along the mountain foot; the nearest to the snow are dusted with it.
	var pines := rng.randi_range(_config.foothill_pines.x, _config.foothill_pines.y)
	var grown_pines := 0
	for attempt in 200:
		if grown_pines >= pines:
			break
		var angle := rng.randf() * TAU
		var stand := _data.valley.point_at(angle, rng.randf_range(90.0, 260.0))
		for k in rng.randi_range(2, 5):
			var point := stand + Vector2(rng.randf_range(-130.0, 130.0), rng.randf_range(-80.0, 80.0))
			if _data.valley.signed_distance(point) < 70.0:
				continue
			var pine := _try_tree(rng, Species.PINE, point, 50.0)
			if pine != null:
				grown_pines += 1
				pine.accent = _data.valley.signed_distance(point) < 170.0 and rng.randf() < 0.7


func _grove_species(rng: RandomNumberGenerator, foot: bool) -> int:
	var weights := [34.0, 22.0, 14.0, 10.0, 10.0, 0.0, 6.0]
	if foot:
		weights[Species.PINE] = 60.0
	var total := 0.0
	for w: float in weights:
		total += w
	var pick := rng.randf() * total
	for i in weights.size():
		pick -= weights[i]
		if pick <= 0.0:
			return i
	return Species.OAK


func _try_tree(rng: RandomNumberGenerator, species: int, point: Vector2,
		water_gap: float) -> NelvarEarthData.Thing:
	var tree := NelvarEarthData.Thing.new()
	tree.kind = Kind.TREE
	tree.variant = species
	tree.solid = true
	var scale := rng.randf()
	tree.radius = lerpf(TRUNK[species].x, TRUNK[species].y, scale)
	tree.size = Vector2(lerpf(CROWN[species].x, CROWN[species].y, scale * 0.7 + rng.randf() * 0.3),
		lerpf(HEIGHT[species].x, HEIGHT[species].y, scale * 0.6 + rng.randf() * 0.4))
	tree.position = point
	tree.appearance_seed = rng.randi()
	if not _fits(point, tree.radius, true, _config.path_clearance, water_gap):
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
		var angle := rng.randf() * TAU
		var heap := _data.valley.point_at(angle, rng.randf_range(80.0, 170.0))
		for k in rng.randi_range(2, 4):
			var radius := rng.randf_range(12.0, 34.0)
			var point := heap + Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-50.0, 50.0))
			if _data.valley.signed_distance(point) < radius + 60.0:
				continue
			if _try_rock(rng, point, radius, rng.randf() < 0.3):
				heaped += 1


func _try_rock(rng: RandomNumberGenerator, point: Vector2, radius: float, moss: bool) -> bool:
	if not _fits(point, radius, true, _config.path_clearance, 30.0):
		return false
	var rock := NelvarEarthData.Thing.new()
	rock.kind = Kind.ROCK
	rock.position = point
	rock.radius = radius
	rock.solid = true
	rock.accent = moss
	rock.appearance_seed = rng.randi()
	_add(rock)
	return true


## Stumps and fallen logs near the groves.
func _deadwood(rng: RandomNumberGenerator) -> void:
	if _groves.is_empty():
		return
	var wanted := rng.randi_range(_config.stumps_and_logs.x, _config.stumps_and_logs.y)
	var placed := 0
	for attempt in wanted * 20:
		if placed >= wanted:
			break
		var grove := _groves[rng.randi_range(0, _groves.size() - 1)]
		var point := grove + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 340.0)
		var thing := NelvarEarthData.Thing.new()
		thing.solid = true
		thing.position = point
		thing.appearance_seed = rng.randi()
		thing.accent = rng.randf() < 0.5
		if rng.randf() < 0.5:
			thing.kind = Kind.STUMP
			thing.radius = rng.randf_range(15.0, 21.0)
		else:
			thing.kind = Kind.LOG
			thing.radius = rng.randf_range(12.0, 15.0)
			thing.size = Vector2(rng.randf_range(80.0, 124.0), 0.0)
		if _fits(point, thing.spread(), true, _config.path_clearance, 40.0):
			_add(thing)
			placed += 1


# --- Plants -------------------------------------------------------------------

func _plants(rng: RandomNumberGenerator) -> void:
	var trees: Array[NelvarEarthData.Thing] = []
	var deadwood: Array[NelvarEarthData.Thing] = []
	for thing in _data.things:
		if thing.kind == Kind.TREE:
			trees.append(thing)
		elif thing.kind == Kind.STUMP or thing.kind == Kind.LOG:
			deadwood.append(thing)
	var meadows := _meadow_centers(rng, 14)
	var hosts: Array[NelvarEarthData.Thing] = trees + deadwood
	# Bushes: most at the foot of a tree, the rest in the open.
	var near_tree := func() -> Vector2:
		if rng.randf() < 0.6 and not trees.is_empty():
			var tree := trees[rng.randi_range(0, trees.size() - 1)]
			return tree.position + Vector2.from_angle(rng.randf() * TAU) \
				* (tree.radius + rng.randf_range(40.0, 100.0))
		return _random_valley_point(rng, 0.95)
	# Tall grass and most flowers grow in meadow patches.
	var in_meadow := func() -> Vector2:
		var meadow := meadows[rng.randi_range(0, meadows.size() - 1)]
		return meadow + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.7, 0.7)) * 220.0
	# Ferns in the shade of the groves.
	var in_shade := func() -> Vector2:
		if trees.is_empty():
			return _random_valley_point(rng, 0.9)
		var tree := trees[rng.randi_range(0, trees.size() - 1)]
		return tree.position + Vector2.from_angle(rng.randf() * TAU) \
			* (tree.radius + rng.randf_range(24.0, 110.0))
	# The rest of the flowers line the trails.
	var flower_spot := func() -> Vector2:
		if rng.randf() < 0.35 and not _data.trails.is_empty():
			var trail := _data.trails[rng.randi_range(0, _data.trails.size() - 1)]
			var i := rng.randi_range(0, trail.points.size() - 2)
			var along := trail.points[i].lerp(trail.points[i + 1], rng.randf())
			var side := trail.points[i].direction_to(trail.points[i + 1]).orthogonal()
			var side_sign := 1.0 if rng.randf() < 0.5 else -1.0
			return along + side * side_sign * (trail.half_width + rng.randf_range(16.0, 40.0))
		return meadows[rng.randi_range(0, meadows.size() - 1)] \
			+ Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.7, 0.7)) * 260.0
	# Mushrooms in front of trunks, stumps and logs.
	var by_wood := func() -> Vector2:
		if hosts.is_empty():
			return _random_valley_point(rng, 0.9)
		var host: NelvarEarthData.Thing = hosts[rng.randi_range(0, hosts.size() - 1)]
		return host.position + Vector2.from_angle(rng.randf_range(-0.2, PI + 0.2)) \
			* (host.spread() + rng.randf_range(10.0, 30.0))
	_scatter(rng, Kind.BUSH, rng.randi_range(_config.bushes.x, _config.bushes.y),
		Vector2(26.0, 40.0), 3, near_tree, 4.0)
	_scatter(rng, Kind.TALL_GRASS, rng.randi_range(_config.tall_grass.x, _config.tall_grass.y),
		Vector2(14.0, 24.0), 3, in_meadow, 2.0)
	_scatter(rng, Kind.FERN, rng.randi_range(_config.ferns.x, _config.ferns.y),
		Vector2(14.0, 22.0), 2, in_shade, 2.0)
	_scatter(rng, Kind.FLOWERS, rng.randi_range(_config.flower_clumps.x, _config.flower_clumps.y),
		Vector2(10.0, 18.0), 4, flower_spot, 0.0)
	_scatter(rng, Kind.MUSHROOMS, rng.randi_range(_config.mushrooms.x, _config.mushrooms.y),
		Vector2(8.0, 12.0), 3, by_wood, 0.0)


## Places `count` plants of one kind at points from `pick`; `variants` look variants.
func _scatter(rng: RandomNumberGenerator, kind: Kind, count: int, radius_range: Vector2,
		variants: int, pick: Callable, trail_gap: float) -> void:
	var placed := 0
	for attempt in count * 10:
		if placed >= count:
			break
		var point: Vector2 = pick.call()
		var radius := rng.randf_range(radius_range.x, radius_range.y)
		if not _fits(point, radius, false, trail_gap, 12.0):
			continue
		var plant := NelvarEarthData.Thing.new()
		plant.kind = kind
		plant.position = point
		plant.radius = radius
		plant.variant = rng.randi_range(0, variants - 1)
		plant.accent = rng.randf() < 0.5
		plant.appearance_seed = rng.randi()
		_add(plant)
		placed += 1


## Open spots for meadows of tall grass and flowers.
func _meadow_centers(rng: RandomNumberGenerator, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for attempt in 200:
		if result.size() >= count:
			break
		var point := _random_valley_point(rng, 0.9)
		if _data.pond_depth(point) > -80.0:
			continue
		result.append(point)
	if result.is_empty():
		result.append(_data.spawn_position + Vector2(300.0, 0.0))
	return result


## Reeds stand in the shallows at the shore; lilies float further out.
func _water_plants(rng: RandomNumberGenerator) -> void:
	for pond in _data.ponds:
		var reeds := rng.randi_range(_config.reeds_per_pond.x, _config.reeds_per_pond.y)
		var start := rng.randf() * TAU
		for i in reeds:
			var angle := start + TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / reeds
			var reed := NelvarEarthData.Thing.new()
			reed.kind = Kind.REEDS
			reed.radius = rng.randf_range(12.0, 18.0)
			reed.position = pond.point_at(angle, rng.randf_range(4.0, 10.0))
			reed.variant = rng.randi_range(0, 1)
			reed.appearance_seed = rng.randi()
			_add(reed)
		var lilies := rng.randi_range(_config.lilies_per_pond.x, _config.lilies_per_pond.y)
		var floated := 0
		for attempt in lilies * 12:
			if floated >= lilies:
				break
			var radius := rng.randf_range(8.0, 14.0)
			var point := pond.center + Vector2.from_angle(rng.randf() * TAU) * pond.axes * sqrt(rng.randf()) * 0.85
			if pond.signed_distance(point) < radius + 14.0:
				continue
			var crowded := false
			for other: NelvarEarthData.Thing in _nearby(point, 60.0):
				if other.kind == Kind.LILY and point.distance_to(other.position) < radius + other.radius + 6.0:
					crowded = true
			if crowded:
				continue
			var lily := NelvarEarthData.Thing.new()
			lily.kind = Kind.LILY
			lily.radius = radius
			lily.position = point
			lily.accent = rng.randf() < 0.35
			lily.appearance_seed = rng.randi()
			_add(lily)
			floated += 1


# --- Mountains ------------------------------------------------------------------

## Rows of peaks along the mountain foot. Peaks on the south side are lower: they
## stand between the camera and the valley.
func _peaks(rng: RandomNumberGenerator) -> void:
	var valley := _data.valley
	for row in _config.peak_rows:
		var angle := rng.randf() * TAU
		var travelled := 0.0
		var widths := ROW_WIDTH[row]
		while travelled < TAU:
			var width := rng.randf_range(widths.x, widths.y)
			var outward := Vector2.from_angle(angle)
			var south := maxf(0.0, outward.y)
			var offset := ROW_OFFSET[row] + width * 0.36 * absf(outward.x) * (1.0 if row == 0 else 0.5)
			var peak := NelvarEarthData.Thing.new()
			peak.kind = Kind.PEAK
			peak.row = row
			peak.position = valley.point_at(angle, -offset)
			peak.radius = width * 0.5
			var height := width * rng.randf_range(0.92, 1.25) * lerpf(1.0, 0.58, south)
			peak.size = Vector2(width, height)
			peak.appearance_seed = rng.randi()
			_add(peak)
			var spacing := width * (rng.randf_range(0.36, 0.5) if row == 0 else rng.randf_range(0.42, 0.58))
			var step := spacing / maxf(valley.radius_at(angle) + offset, 1.0)
			angle = wrapf(angle + step, -PI, PI)
			travelled += step
