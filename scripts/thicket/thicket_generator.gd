class_name NelvarThicketGenerator
extends RefCounted
## Lays out the giant forest (Земля 2) from a seed: the floor and the ring of giants round
## it, the start on a southern clearing with a giant right north of it, the giants inside,
## the ponds, the fallen giant, the clearings, the ant trails between them (a spanning tree
## and a few loops, found round the trunks, the ponds and the fallen giant), the roots
## (walls near the trunk, low further out, now and then an arch; dipping under the
## trails), the lily pads and the rafts, the hazards and everything lying about.
##
## Every stage draws from its own seeded generator, so changing one stage leaves the others
## as they were. Solid things keep a passage wider than a hopper between them; trails, the
## clearings' middles and the start stay free.

const Kind = NelvarEarthData.Kind
const Wood = NelvarThicketData.Wood
const Part = NelvarThicketData.Part
const STEP := NelvarThicketData.ROOT_STEP
## Placement grid of things.
const GRID := 192.0
## The trails' search grid.
const ROUTE_CELL := 32.0
## The south side of the ring (no giants there): directions within this of straight down.
const SOUTH_GAP := 0.8
## Oaks' acorns fall this far from the trunk.
const OAK_CROWN := Vector2(700.0, 1000.0)
## Free ground under an arch, from wall to wall.
const ARCH_WIDTH := Vector2(60.0, 110.0)

var _config: NelvarThicketConfig
var _data: NelvarThicketData
var _grid := {}
## Root samples filed by cell: [point, width, root id, giant, along].
var _samples := {}
const SAMPLE_CELL := 160.0
var _route_origin := Vector2.ZERO
var _route_size := Vector2i.ZERO
var _route_blocked := PackedByteArray()
var _route_cost := PackedFloat32Array()


func generate(config: NelvarThicketConfig, world_seed: int) -> NelvarThicketData:
	var error := config.validation_error()
	if not error.is_empty():
		push_error("Thicket config: " + error)
		return null
	_config = config
	_data = NelvarThicketData.new()
	_data.world_seed = world_seed
	_grid.clear()
	_samples.clear()
	_floor(_rng("floor"))
	_fallen(_rng("fallen"))
	_ponds(_rng("ponds"))
	_inner_giants(_rng("giants"))
	_ring(_rng("ring"))
	_clearings(_rng("clearings"))
	_trails(_rng("trails"))
	_data.index_trails()
	_roots(_rng("roots"))
	_data.index_roots()
	_water(_rng("water"))
	_hazards(_rng("hazards"))
	_data.index_hazards()
	_things(_rng("things"))
	_data.finish()
	var result := _data
	_data = null
	_grid.clear()
	_samples.clear()
	return result


func _rng(stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:thicket:%s" % [_data.world_seed, stage]).hash()
	return rng


# --- The floor and the giants ---------------------------------------------------------

## The floor's outline, the start on a southern clearing and the giant north of it.
func _floor(rng: RandomNumberGenerator) -> void:
	var valley := _data.valley
	valley.center = Vector2.ZERO
	valley.axes = _config.floor_radius * Vector2(rng.randf_range(0.97, 1.03), rng.randf_range(0.97, 1.03))
	_bend(valley, rng, _config.floor_wobble, 0.16)
	_data.boundary = valley.polygon(_config.boundary_vertices)
	var reach := valley.reach()
	_data.bounds = Rect2(-Vector2.ONE * (reach + 900.0), Vector2.ONE * (reach + 900.0) * 2.0)
	# The start: well south of the middle, on its own clearing.
	var south := valley.point_at(PI * 0.5)
	_data.spawn_position = Vector2(rng.randf_range(-0.2, 0.2) * valley.axes.x, south.y * rng.randf_range(0.52, 0.6))
	var start := NelvarEarthData.Clearing.new()
	start.radius = rng.randf_range(_config.start_clearing_radius.x, _config.start_clearing_radius.y)
	start.center = _data.spawn_position + Vector2(rng.randf_range(-30.0, 30.0), start.radius * 0.45)
	_data.clearings.append(start)
	_data.start_clearing = 0
	# The giant right north of it: its base fills the top of the first view (the view
	# reaches about 350 up from the player).
	var giant := NelvarThicketData.Giant.new()
	var distance := rng.randf_range(_config.start_giant_distance.x, _config.start_giant_distance.y)
	giant.radius = clampf(distance - rng.randf_range(140.0, 190.0), _config.giant_radius.x, _config.giant_radius.y)
	distance = clampf(distance, giant.radius + 140.0, giant.radius + 200.0)
	giant.center = _data.spawn_position + Vector2(rng.randf_range(-0.2, 0.2) * giant.radius, -distance)
	giant.species = [Wood.OAK, Wood.OAK, Wood.PINE, Wood.BIRCH][rng.randi_range(0, 3)]
	_finish_giant(giant, rng)


func _finish_giant(giant: NelvarThicketData.Giant, rng: RandomNumberGenerator) -> void:
	var diameter := giant.radius * 2.0
	giant.height = minf(diameter * rng.randf_range(_config.trunk_height.x, _config.trunk_height.y),
		_config.trunk_height_cap)
	if giant.ring:
		giant.height = minf(giant.height, 760.0)
	giant.crown = rng.randf_range(OAK_CROWN.x, OAK_CROWN.y)
	giant.appearance_seed = rng.randi()
	giant.id = _data.giants.size()
	_data.giants.append(giant)


## Slow bends of a Radial (as on the valley).
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


## The giants inside: far apart, away from the edge and the start; oaks, pines, birches.
func _inner_giants(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.giants.x, _config.giants.y)
	var species: Array[int] = []
	for i in rng.randi_range(2, 3):
		species.append(Wood.OAK)
	for i in rng.randi_range(1, 2):
		species.append(Wood.PINE)
	for i in rng.randi_range(1, 2):
		species.append(Wood.BIRCH)
	# The giant by the start is one of them.
	species.erase(_data.giants[0].species)
	while species.size() < wanted - 1:
		species.append([Wood.OAK, Wood.PINE, Wood.BIRCH][rng.randi_range(0, 2)])
	_shuffle(species, rng)
	var start := _data.clearings[0]
	for attempt in 900:
		if _data.giants.size() >= wanted:
			break
		var shrink := 1.0 - float(attempt) / 1400.0
		var radius := rng.randf_range(_config.giant_radius.x, _config.giant_radius.y) * shrink
		radius = maxf(radius, _config.giant_radius.x * 0.9)
		var point := _random_floor_point(rng, 0.9)
		if _data.valley.signed_distance(point) < radius + 230.0:
			continue
		if point.distance_to(start.center) < radius + start.radius + 300.0:
			continue
		var apart := true
		for other in _data.giants:
			if other.edge_distance(point) - radius < _config.giant_gap:
				apart = false
				break
		var fallen := _data.fallen
		if fallen != null and (fallen.covers(point, radius + 200.0) or fallen.plate_blocks(point, radius + 200.0)):
			apart = false
		for pond in _data.ponds:
			if pond.signed_distance(point) > -(radius + 220.0):
				apart = false
		if not apart:
			continue
		var giant := NelvarThicketData.Giant.new()
		giant.center = point
		giant.radius = radius
		giant.species = species[(_data.giants.size() - 1) % species.size()]
		_finish_giant(giant, rng)


## Giants shoulder to shoulder round the floor, beyond its edge (none on the south side).
func _ring(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.ring_giants.x, _config.ring_giants.y)
	var from := PI * 0.5 + SOUTH_GAP
	var span := TAU - SOUTH_GAP * 2.0
	var kinds: Array[int] = [Wood.DEAD, Wood.DEAD]
	while kinds.size() < wanted:
		kinds.append([Wood.OAK, Wood.PINE, Wood.BIRCH][kinds.size() % 3])
	_shuffle(kinds, rng)
	for i in wanted:
		var angle := from + span * (float(i) + 0.5 + rng.randf_range(-0.18, 0.18)) / wanted
		var giant := NelvarThicketData.Giant.new()
		giant.ring = true
		giant.radius = rng.randf_range(300.0, 500.0)
		giant.center = _data.valley.point_at(angle) + Vector2.from_angle(angle) * (giant.radius + rng.randf_range(4.0, 40.0))
		giant.species = kinds[i]
		_finish_giant(giant, rng)


## Array.shuffle() draws from the global generator; this one from the stage's.
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


func _random_floor_point(rng: RandomNumberGenerator, reach: float) -> Vector2:
	var angle := rng.randf() * TAU
	return _data.valley.point_at(angle).lerp(_data.valley.center, 1.0 - sqrt(rng.randf()) * reach)


func _ponds(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.ponds.x, _config.ponds.y)
	for attempt in 600:
		if _data.ponds.size() >= wanted:
			break
		var radius := rng.randf_range(_config.pond_radius.x, _config.pond_radius.y) * (1.0 - float(attempt) / 1200.0)
		radius = maxf(radius, _config.pond_radius.x)
		var center := _random_floor_point(rng, 0.85)
		if _data.valley.signed_distance(center) < radius + 220.0:
			continue
		if center.distance_to(_data.spawn_position) < radius + 600.0:
			continue
		var apart := true
		for giant in _data.giants:
			if giant.edge_distance(center) < radius + 320.0:
				apart = false
		for other in _data.ponds:
			if center.distance_to(other.center) < radius + other.reach() + 450.0:
				apart = false
		var fallen := _data.fallen
		if fallen != null and (fallen.covers(center, radius + 220.0) or fallen.plate_blocks(center, radius + 220.0)):
			apart = false
		if not apart:
			continue
		var pond := NelvarEarthData.Radial.new()
		pond.center = center
		pond.axes = Vector2(radius, radius * rng.randf_range(0.82, 0.94))
		_bend(pond, rng, 0.04, 0.06)
		_data.ponds.append(pond)
		_data.pond_polygons.append(pond.polygon(72))


## One fallen giant lying almost across the screen, its root plate on one end; both ends
## leave room to walk round.
func _fallen(rng: RandomNumberGenerator) -> void:
	for attempt in 500:
		var shrink := 1.0 - float(attempt) / 700.0
		var length := maxf(rng.randf_range(_config.fallen_length.x, _config.fallen_length.y) * shrink, 1300.0)
		var radius := rng.randf_range(_config.fallen_thickness.x, _config.fallen_thickness.y) * 0.5
		var angle := rng.randf_range(-0.34, 0.34) + (PI if rng.randf() < 0.5 else 0.0)
		var axis := Vector2.from_angle(angle)
		var middle := _random_floor_point(rng, 0.75)
		var fallen := NelvarThicketData.Fallen.new()
		fallen.start = middle - axis * length * 0.5
		fallen.end = middle + axis * length * 0.5
		fallen.radius = radius
		fallen.tunnel = minf(rng.randf_range(_config.tunnel_width.x, _config.tunnel_width.y) * 0.5, radius - 44.0)
		fallen.plate_half = rng.randf_range(_config.root_plate_width.x, _config.root_plate_width.y) * 0.5
		fallen.plate_depth = rng.randf_range(56.0, 80.0)
		fallen.plate_center = fallen.start + axis * fallen.plate_depth * 0.4
		if not _fallen_fits(fallen):
			continue
		var wanted := rng.randi_range(_config.breaches.x, _config.breaches.y)
		for i in 40:
			if fallen.breaches.size() >= wanted:
				break
			var at := rng.randf_range(fallen.plate_depth + 220.0, length - 180.0)
			var width := rng.randf_range(90.0, 140.0)
			var apart := true
			for breach in fallen.breaches:
				if absf(breach.x - at) < (breach.y + width) * 0.5 + 200.0:
					apart = false
			if apart:
				fallen.breaches.append(Vector2(at, width))
		fallen.appearance_seed = rng.randi()
		_data.fallen = fallen
		return


func _fallen_fits(fallen: NelvarThicketData.Fallen) -> bool:
	var normal := fallen.normal()
	var axis := fallen.axis()
	var checks: Array[Vector2] = [fallen.end + axis * 40.0, fallen.end + normal * fallen.radius,
		fallen.end - normal * fallen.radius, fallen.plate_center + normal * fallen.plate_half,
		fallen.plate_center - normal * fallen.plate_half, fallen.start - axis * fallen.plate_depth]
	for point in checks:
		# Room to walk round both ends.
		if _data.valley.signed_distance(point) < 260.0:
			return false
	for i in 21:
		var point := fallen.start.lerp(fallen.end, i / 20.0)
		if _data.valley.signed_distance(point) < fallen.radius + 200.0:
			return false
		for giant in _data.giants:
			if giant.edge_distance(point) < fallen.radius + 260.0:
				return false
		for pond in _data.ponds:
			if pond.signed_distance(point) > -(fallen.radius + 200.0):
				return false
	for point in [fallen.plate_center + normal * fallen.plate_half, fallen.plate_center - normal * fallen.plate_half]:
		for giant in _data.giants:
			if giant.edge_distance(point) < 260.0:
				return false
	var start := _data.clearings[0]
	return not fallen.covers(start.center, start.radius + 300.0) \
		and not fallen.plate_blocks(start.center, start.radius + 300.0)


## Clearings in the crowns, as far apart as they can be; small sunny windows besides.
func _clearings(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.clearings.x, _config.clearings.y)
	var candidates: Array[Vector3] = []
	for i in 420:
		var point := _random_floor_point(rng, 0.9)
		var radius := rng.randf_range(_config.clearing_radius.x, _config.clearing_radius.y)
		# Where a big one does not fit, a smaller one may.
		while radius > _config.clearing_radius.x and not _clearing_fits(point, radius):
			radius -= 40.0
		radius = maxf(radius, _config.clearing_radius.x)
		if _clearing_fits(point, radius):
			candidates.append(Vector3(point.x, point.y, radius))
	for i in wanted:
		var best := -1
		var best_distance := 0.0
		for c in candidates.size():
			var candidate := candidates[c]
			var point := Vector2(candidate.x, candidate.y)
			var nearest := INF
			for clearing in _data.clearings:
				nearest = minf(nearest, point.distance_to(clearing.center) - clearing.radius - candidate.z)
			if nearest > best_distance:
				best_distance = nearest
				best = c
		if best < 0 or best_distance < 110.0:
			break
		var clearing := NelvarEarthData.Clearing.new()
		clearing.center = Vector2(candidates[best].x, candidates[best].y)
		clearing.radius = candidates[best].z
		_data.clearings.append(clearing)
		candidates.remove_at(best)
	for i in 80:
		if _data.windows.size() >= 8:
			break
		var point := _random_floor_point(rng, 0.88)
		var radius := rng.randf_range(50.0, 110.0)
		if _data.sun_at(point) > 0.0 or _data.giant_at(point, radius + 60.0) != null:
			continue
		if _data.valley.signed_distance(point) < 200.0:
			continue
		_data.windows.append(Vector3(point.x, point.y, radius))


func _clearing_fits(point: Vector2, radius: float) -> bool:
	if _data.valley.signed_distance(point) < radius + 130.0:
		return false
	for giant in _data.giants:
		if giant.edge_distance(point) < radius + 90.0:
			return false
	for pond in _data.ponds:
		if pond.signed_distance(point) > -(radius + 120.0):
			return false
	var fallen := _data.fallen
	return fallen == null or (not fallen.covers(point, radius + 90.0) and not fallen.plate_blocks(point, radius + 90.0))


# --- Ant trails ---------------------------------------------------------------------

## Trails join the clearings: a spanning tree and a few loops, each found on a grid round
## the trunks, the ponds and the fallen giant.
func _trails(rng: RandomNumberGenerator) -> void:
	_build_route_grid(rng)
	var nodes: Array[Vector2] = []
	for clearing in _data.clearings:
		nodes.append(clearing.center)
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
	var loops := rng.randi_range(_config.extra_trails.x, _config.extra_trails.y)
	var added := 0
	for edge in extra:
		if added >= loops:
			break
		if _clear_angle(edge, edges, nodes):
			edges.append(edge)
			added += 1
	for edge in edges:
		var points := _route(nodes[edge.x], nodes[edge.y])
		if points.size() < 2:
			push_warning("Thicket seed %d: no way for a trail between clearings %d and %d" % [
				_data.world_seed, edge.x, edge.y])
			continue
		var trail := NelvarEarthData.Trail.new()
		trail.half_width = rng.randf_range(_config.trail_half_width.x, _config.trail_half_width.y)
		trail.points = points
		_data.trails.append(trail)


func _clear_angle(edge: Vector2i, edges: Array[Vector2i], nodes: Array[Vector2]) -> bool:
	for end: int in [edge.x, edge.y]:
		var other: int = edge.y if end == edge.x else edge.x
		var direction := nodes[end].direction_to(nodes[other])
		for existing in edges:
			if existing.x != end and existing.y != end:
				continue
			var far: int = existing.y if existing.x == end else existing.x
			if absf(direction.angle_to(nodes[end].direction_to(nodes[far]))) < deg_to_rad(45.0):
				return false
	return true


## Cells a trail may not cross (with room for its width) and the cost of the others: dearer
## near the trunks, a little noise for the wander.
func _build_route_grid(rng: RandomNumberGenerator) -> void:
	var reach := _data.valley.reach()
	_route_origin = -Vector2.ONE * reach
	_route_size = Vector2i((Vector2.ONE * reach * 2.0 / ROUTE_CELL).ceil()) + Vector2i.ONE
	var count := _route_size.x * _route_size.y
	_route_blocked.resize(count)
	_route_cost.resize(count)
	var keep := _config.trail_half_width.y + 40.0
	var salt := rng.randi() & 0xffff
	for y in _route_size.y:
		for x in _route_size.x:
			var point := _route_origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * ROUTE_CELL
			var index := y * _route_size.x + x
			var blocked := _data.valley.signed_distance(point) < keep + 80.0
			var cost := 1.0 + NelvarPixelArt.value_noise(point.x / 260.0, point.y / 260.0, salt) * 0.8
			if not blocked:
				for giant in _data.giants:
					var edge := giant.edge_distance(point)
					if edge < keep + 40.0:
						blocked = true
						break
					cost += 2.5 * (1.0 - smoothstep(keep, keep + 260.0, edge))
			if not blocked and _data.pond_depth(point) > -(keep + 30.0):
				blocked = true
			var fallen := _data.fallen
			if not blocked and fallen != null and (fallen.covers(point, keep + 30.0) or fallen.plate_blocks(point, keep + 30.0)):
				blocked = true
			_route_blocked[index] = 1 if blocked else 0
			_route_cost[index] = cost


func _route_cell(point: Vector2) -> Vector2i:
	return Vector2i(((point - _route_origin) / ROUTE_CELL).floor()).clamp(Vector2i.ZERO, _route_size - Vector2i.ONE)


func _route_center(cell: Vector2i) -> Vector2:
	return _route_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * ROUTE_CELL


func _route_free(point: Vector2) -> bool:
	var cell := Vector2i(((point - _route_origin) / ROUTE_CELL).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= _route_size.x or cell.y >= _route_size.y:
		return false
	return _route_blocked[cell.y * _route_size.x + cell.x] == 0


## A* over the grid from a to b, then pulled straight where the grid allows and rounded.
func _route(a: Vector2, b: Vector2) -> PackedVector2Array:
	var start := _route_cell(a)
	var goal := _route_cell(b)
	var width := _route_size.x
	var count := _route_size.x * _route_size.y
	var cost := PackedFloat32Array()
	cost.resize(count)
	cost.fill(INF)
	var came := PackedInt32Array()
	came.resize(count)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	var heap_keys := PackedFloat32Array()
	var heap_nodes := PackedInt32Array()
	var start_index := start.y * width + start.x
	var goal_index := goal.y * width + goal.x
	cost[start_index] = 0.0
	_heap_push(heap_keys, heap_nodes, 0.0, start_index)
	var found := false
	var moves: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while heap_nodes.size() > 0:
		var current := _heap_pop(heap_keys, heap_nodes)
		if current == goal_index:
			found = true
			break
		if closed[current] == 1:
			continue
		closed[current] = 1
		var cx := current % width
		var cy := current / width
		for move in moves:
			var nx := cx + move.x
			var ny := cy + move.y
			if nx < 0 or ny < 0 or nx >= _route_size.x or ny >= _route_size.y:
				continue
			var next := ny * width + nx
			if _route_blocked[next] == 1 and next != goal_index:
				continue
			if move.x != 0 and move.y != 0 and (_route_blocked[cy * width + nx] == 1 or _route_blocked[ny * width + cx] == 1):
				continue
			var step := 1.4142 if move.x != 0 and move.y != 0 else 1.0
			var total := cost[current] + step * (_route_cost[next] + _route_cost[current]) * 0.5
			if total < cost[next]:
				cost[next] = total
				came[next] = current
				_heap_push(heap_keys, heap_nodes, total + Vector2(nx - goal.x, ny - goal.y).length(), next)
	if not found:
		return PackedVector2Array()
	var cells: Array[Vector2] = []
	var at := goal_index
	while at != -1:
		cells.append(_route_center(Vector2i(at % width, at / width)))
		at = came[at]
	cells.reverse()
	cells[0] = a
	cells[cells.size() - 1] = b
	# Pull the line straight where the grid sees through.
	var pulled: Array[Vector2] = [cells[0]]
	var anchor := 0
	while anchor < cells.size() - 1:
		var far := anchor + 1
		for j in range(cells.size() - 1, anchor + 1, -1):
			if j - anchor > 14:
				continue
			if _sight(cells[anchor], cells[j]):
				far = j
				break
		pulled.append(cells[far])
		anchor = far
	# Gentle bends in between, then rounded off.
	var points: Array[Vector2] = [pulled[0]]
	for i in pulled.size() - 1:
		var p := pulled[i]
		var q := pulled[i + 1]
		var pieces := maxi(1, int(p.distance_to(q) / 70.0))
		for k in range(1, pieces + 1):
			points.append(p.lerp(q, float(k) / pieces))
	for pass_index in 2:
		var cut: Array[Vector2] = [points[0]]
		for i in points.size() - 1:
			cut.append(points[i].lerp(points[i + 1], 0.25))
			cut.append(points[i].lerp(points[i + 1], 0.75))
		cut.append(points[points.size() - 1])
		points = cut
	for point in points:
		if not _route_free(point) and point.distance_to(a) > ROUTE_CELL and point.distance_to(b) > ROUTE_CELL:
			return PackedVector2Array(pulled)
	return PackedVector2Array(points)


func _sight(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, int(a.distance_to(b) / 10.0))
	for k in steps + 1:
		var point := a.lerp(b, float(k) / steps)
		if not _route_free(point) and point.distance_to(a) > ROUTE_CELL and point.distance_to(b) > ROUTE_CELL:
			return false
	return true


func _heap_push(keys: PackedFloat32Array, nodes: PackedInt32Array, key: float, node: int) -> void:
	keys.append(key)
	nodes.append(node)
	var i := keys.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if keys[parent] <= keys[i]:
			break
		var k := keys[parent]
		keys[parent] = keys[i]
		keys[i] = k
		var n := nodes[parent]
		nodes[parent] = nodes[i]
		nodes[i] = n
		i = parent


func _heap_pop(keys: PackedFloat32Array, nodes: PackedInt32Array) -> int:
	var top := nodes[0]
	var last := keys.size() - 1
	keys[0] = keys[last]
	nodes[0] = nodes[last]
	keys.resize(last)
	nodes.resize(last)
	var i := 0
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var smallest := i
		if left < last and keys[left] < keys[smallest]:
			smallest = left
		if right < last and keys[right] < keys[smallest]:
			smallest = right
		if smallest == i:
			break
		var k := keys[smallest]
		keys[smallest] = keys[i]
		keys[i] = k
		var n := nodes[smallest]
		nodes[smallest] = nodes[i]
		nodes[i] = n
		i = smallest
	return top


# --- Roots ------------------------------------------------------------------------------

## A skirt of roots round each giant inside: grown outwards side by side, bending gently,
## stopping short of the clearings, the water, the edge, other giants and other roots;
## some branch once. Then each is split into its parts: a wall near the trunk, low
## further out, an arch where it runs across the screen, a dip under every trail.
func _roots(rng: RandomNumberGenerator) -> void:
	var plans := []
	for giant in _data.inner_giants():
		var count := rng.randi_range(_config.roots_per_giant.x, _config.roots_per_giant.y)
		var offset := rng.randf() * TAU
		for i in count:
			var angle := offset + TAU * (float(i) + rng.randf_range(-0.22, 0.22)) / count
			plans.append([giant, angle, i])
	# Round robin: the first root of every giant, then the second...
	plans.sort_custom(func(p: Array, q: Array) -> bool: return p[2] < q[2] if p[2] != q[2] else p[0].id < q[0].id)
	var mains: Array[NelvarThicketData.Root] = []
	for plan: Array in plans:
		var giant: NelvarThicketData.Giant = plan[0]
		var size := clampf((giant.radius - 200.0) / 220.0, 0.0, 1.0)
		var length := rng.randf_range(_config.root_length.x, _config.root_length.y) * lerpf(0.75, 1.0, size)
		var width := lerpf(80.0, _config.root_width.y, size) * rng.randf_range(0.8, 1.0)
		var start := giant.center + Vector2.from_angle(plan[1]) * (giant.radius - 24.0)
		var root := _grow(giant, start, plan[1], length, width, -1, rng)
		if root != null:
			mains.append(root)
	for root in mains:
		if rng.randf() >= _config.branch_chance or root.points.size() < 16:
			continue
		var at := int(root.points.size() * rng.randf_range(0.38, 0.65))
		var heading := root.points[at - 1].direction_to(root.points[at + 1]).angle()
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var left := (root.points.size() - at) * STEP
		var branch := _grow(_data.giants[root.giant], root.points[at], heading + side * rng.randf_range(0.45, 0.7),
			left * rng.randf_range(0.4, 0.7), root.widths[at] * 0.72, root.id, rng)
		if branch != null:
			branch.fork = at
	for root in _data.roots:
		_shape_root(root, rng)


## Grows one root from `start` along `angle`; null when it stays too short.
func _grow(giant: NelvarThicketData.Giant, start: Vector2, angle: float, length: float, width: float,
		parent: int, rng: RandomNumberGenerator) -> NelvarThicketData.Root:
	var root := NelvarThicketData.Root.new()
	root.giant = giant.id
	root.parent = parent
	root.points.append(start)
	var bend := rng.randf_range(0.18, 0.42)
	var wave := rng.randf_range(1.0 / 380.0, 1.0 / 200.0)
	var phase := rng.randf() * TAU
	var drift := rng.randf_range(-0.12, 0.12)
	var heading := angle
	var steps := int(length / STEP)
	var tip := minf(width, _config.root_width.x)
	for k in range(1, steps + 1):
		var along := k * STEP
		var want := angle + sin(along * wave + phase) * bend + drift * along / 300.0
		var w := lerpf(width, tip, pow(float(k) / steps, 0.75))
		var next := Vector2.INF
		for attempt: float in [0.0, 0.3, -0.3, 0.6, -0.6]:
			var direction := lerp_angle(heading, want, 0.35) + attempt
			var candidate := root.points[k - 1] + Vector2.from_angle(direction) * STEP
			if _root_room(candidate, w, giant, root, along, parent):
				next = candidate
				heading = direction
				break
		if not next.is_finite():
			break
		root.points.append(next)
	if root.points.size() < 8:
		return null
	var count := root.points.size()
	for k in count:
		root.widths.append(lerpf(width, tip, pow(float(k) / maxf(1.0, count - 1), 0.75)))
	root.id = _data.roots.size()
	root.appearance_seed = rng.randi()
	_data.roots.append(root)
	giant.roots.append(root.id)
	for k in count:
		_file_sample(root.points[k], root.widths[k], root.id, giant.id, k * STEP)
	return root


## Room for a root sample: on the floor, off the clearings and the water, clear of other
## giants, the fallen giant and other roots (its own giant's next to the trunk, and the
## root it branches from at the fork, may come closer).
func _root_room(point: Vector2, width: float, giant: NelvarThicketData.Giant, root: NelvarThicketData.Root,
		along: float, parent: int) -> bool:
	var half := width * 0.5
	var passage := _config.passage_width
	if _data.valley.signed_distance(point) < half + 70.0:
		return false
	for clearing in _data.clearings:
		if point.distance_to(clearing.center) < clearing.radius + half + 30.0:
			return false
	if _data.pond_depth(point) > -(half + 16.0):
		return false
	for other in _data.giants:
		if other != giant and other.edge_distance(point) < half + passage + 20.0:
			return false
	if along > giant.radius * 0.6 and giant.edge_distance(point) < -giant.radius * 0.4:
		# Never curling back under its own trunk.
		return false
	var fallen := _data.fallen
	if fallen != null and (fallen.covers(point, half + passage) or fallen.plate_blocks(point, half + passage)):
		return false
	var cell := Vector2i((point / SAMPLE_CELL).floor())
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			for sample: Array in _samples.get(Vector2i(x, y), []):
				var other_root: int = sample[2]
				if other_root == root.id:
					continue
				var other_along: float = sample[4]
				if sample[3] == giant.id and along < 170.0 and other_along < 170.0 + giant.radius * 0.2:
					continue
				if other_root == parent and along < 110.0:
					continue
				var gap := point.distance_to(sample[0]) - half - float(sample[1]) * 0.5
				if gap < passage:
					return false
	return true


func _file_sample(point: Vector2, width: float, root: int, giant: int, along: float) -> void:
	var key := Vector2i((point / SAMPLE_CELL).floor())
	if not _samples.has(key):
		_samples[key] = []
	_samples[key].append([point, width, root, giant, along])


## Heights and parts along a root: a wall for the first 40–60%, low after that, an arch
## where it runs across the screen, dipped under every trail it crosses.
func _shape_root(root: NelvarThicketData.Root, rng: RandomNumberGenerator) -> void:
	var giant := _data.giants[root.giant]
	var count := root.points.size()
	var size := clampf((giant.radius - 200.0) / 220.0, 0.0, 1.0)
	var top := lerpf(18.0, 30.0, size) * rng.randf_range(0.85, 1.0)
	var share := rng.randf_range(_config.high_share.x, _config.high_share.y)
	if root.parent >= 0:
		# A branch starts as high as its root is at the fork.
		var parent := _data.roots[root.parent]
		top = maxf(parent.heights[mini(root.fork, parent.heights.size() - 1)] * 0.9, 6.0)
		share = 0.3 if top >= 14.0 else 0.0
	var high := int(count * share)
	if root.parent < 0:
		high = maxi(2, high)
	var low_top := 10.0 if high > 0 else minf(top, 10.0)
	root.heights.resize(count)
	root.lifts.resize(count)
	root.parts.resize(count)
	for k in count:
		if k < high:
			root.heights[k] = lerpf(top, 14.0, float(k) / high)
			root.parts[k] = Part.HIGH
		else:
			root.heights[k] = lerpf(low_top, 4.0, float(k - high) / maxf(1.0, count - high))
			root.parts[k] = Part.LOW
	# An arch where the root runs across the screen (never right at the trunk).
	if rng.randf() < _config.arch_chance:
		# The free ground under it runs from one wall sample to the next: (gap + 1) steps.
		var gap := maxi(3, roundi(rng.randf_range(ARCH_WIDTH.x, ARCH_WIDTH.y) / STEP) - 1)
		var options: Array[int] = []
		for k in range(maxi(int(count * 0.25), int(140.0 / STEP)), count - gap - 3):
			var flat := true
			for j in range(k - 1, k + gap + 1):
				var direction := root.points[j].direction_to(root.points[mini(j + 1, count - 1)])
				if absf(direction.y) > sin(deg_to_rad(35.0)) or _trail_near(root.points[j], 60.0):
					flat = false
					break
			if flat:
				options.append(k)
		if not options.is_empty():
			var from := options[rng.randi_range(0, options.size() - 1)]
			var lift := rng.randf_range(10.0, 16.0)
			for j in range(from, from + gap):
				root.parts[j] = Part.ARCH
				root.lifts[j] = lift
				root.heights[j] = lift + clampf(root.widths[j] / NelvarThicketData.PIXEL * 0.35, 5.0, 9.0)
			# The ends it stands on are walls.
			for j in [from - 2, from - 1, from + gap, from + gap + 1]:
				if j >= 0 and j < count:
					root.parts[j] = Part.HIGH
					root.heights[j] = maxf(root.heights[j], lift + 4.0)
	# Under the trails the root dips into the ground.
	for k in count:
		if _data.trail_clearance(root.points[k]) < 30.0 + root.widths[k] * 0.5:
			root.parts[k] = Part.PASS
			root.lifts[k] = 0.0
			root.heights[k] = 2.0


func _trail_near(point: Vector2, reach: float) -> bool:
	return _data.trail_clearance(point) < reach


# --- Water ------------------------------------------------------------------------------

## Each pond: rafts drifting on one loop round it, lily pads in a line across its middle;
## a raft passing the shore and the line makes a way over the water.
func _water(rng: RandomNumberGenerator) -> void:
	for p in _data.ponds.size():
		var pond := _data.ponds[p]
		var best_lilies: Array[NelvarThicketData.Lily] = []
		var best_rafts: Array[NelvarThicketData.Raft] = []
		var best_loop: NelvarThicketData.PondLoop
		for attempt in 30:
			var loop := NelvarThicketData.PondLoop.new()
			var rafts := _make_rafts(pond, p, loop, rng)
			var lilies := _make_lilies(pond, p, loop, rafts, rng)
			best_lilies = lilies
			best_rafts = rafts
			best_loop = loop
			if NelvarThicketData.crossable(pond, lilies, rafts):
				break
		_data.loops.append(best_loop)
		for raft in best_rafts:
			raft.id = _data.rafts.size()
			_data.rafts.append(raft)
		for lily in best_lilies:
			lily.id = _data.lilies.size()
			_data.lilies.append(lily)


func _make_rafts(pond: NelvarEarthData.Radial, index: int, loop: NelvarThicketData.PondLoop,
		rng: RandomNumberGenerator) -> Array[NelvarThicketData.Raft]:
	var rafts: Array[NelvarThicketData.Raft] = []
	var count := rng.randi_range(_config.rafts_per_pond.x, _config.rafts_per_pond.y)
	var period := rng.randf_range(_config.raft_period.x, _config.raft_period.y)
	var base := rng.randf() * TAU
	# Smaller ponds carry smaller leaves; the first always holds a standing player.
	var longest := clampf(minf(pond.axes.x, pond.axes.y) * 0.62, NelvarThicketData.SMALL_RAFT + 10.0, _config.raft_length.y)
	for i in count:
		var raft := NelvarThicketData.Raft.new()
		raft.pond = index
		raft.length = rng.randf_range(minf(_config.raft_length.x, longest * 0.7), longest)
		if i == 0:
			raft.length = rng.randf_range(maxf(NelvarThicketData.SMALL_RAFT + 6.0, longest * 0.82), longest)
		raft.width = raft.length * rng.randf_range(0.42, 0.5)
		raft.angle = rng.randf_range(-0.35, 0.35)
		raft.period = period
		raft.phase = base + TAU * (float(i) + rng.randf_range(-0.12, 0.12)) / count
		raft.appearance_seed = rng.randi()
		raft._loop = loop
		rafts.append(raft)
	# The loop keeps every raft off the shore by a little.
	loop.center = pond.center
	loop.radii.resize(64)
	for k in 64:
		var angle := TAU * k / 64.0
		var direction := Vector2.from_angle(angle)
		var widest := 0.0
		for raft in rafts:
			widest = maxf(widest, raft.support(direction))
		loop.radii[k] = pond.radius_at(angle) - widest - 12.0
	# Shrink it where a raft would still touch the shore (the shore bends).
	for round_index in 6:
		var touching := false
		for k in 64:
			var angle := TAU * k / 64.0
			for raft in rafts:
				var at := loop.point_at(angle)
				for j in 12:
					var local := Vector2.from_angle(TAU * j / 12.0) * Vector2(raft.length, raft.width) * 0.5
					if pond.signed_distance(at + local.rotated(raft.angle)) < 6.0:
						loop.radii[k] -= 8.0
						touching = true
						break
		if not touching:
			break
	# Rafts never bump into each other (they share the loop): drop the ones that would.
	var kept: Array[NelvarThicketData.Raft] = []
	for raft in rafts:
		var clear := true
		for other in kept:
			for s in 48:
				var time := period * s / 48.0
				if raft.position_at(time).distance_to(other.position_at(time)) < (raft.length + other.length) * 0.5 + 10.0:
					clear = false
					break
			if not clear:
				break
		if clear:
			kept.append(raft)
	return kept


func _make_lilies(pond: NelvarEarthData.Radial, index: int, loop: NelvarThicketData.PondLoop,
		rafts: Array[NelvarThicketData.Raft], rng: RandomNumberGenerator) -> Array[NelvarThicketData.Lily]:
	var lilies: Array[NelvarThicketData.Lily] = []
	if rafts.is_empty():
		return lilies
	# A line of pads across the middle from south to north, between the inner edges of the
	# biggest raft as it passes either side; each pad as big as the rafts going by allow.
	var big := rafts[0]
	var shift := rng.randf_range(-0.1, 0.1) * pond.axes.x
	var y := loop.radius_at(PI * 0.5) - big.support(Vector2.DOWN) - rng.randf_range(10.0, 24.0)
	var end := -(loop.radius_at(-PI * 0.5) - big.support(Vector2.UP)) + 20.0
	var guard := 0
	while y > end and guard < 14:
		guard += 1
		var want := rng.randf_range(_config.lily_radius.x, _config.lily_radius.y)
		var placed := false
		var radius := minf(want, (y - end) * 0.5 + 12.0)
		while radius >= 40.0:
			var center := pond.center + Vector2(shift, y - radius)
			if _lily_room(center, radius, pond, rafts) >= 0.0:
				var lily := NelvarThicketData.Lily.new()
				lily.pond = index
				lily.radius = radius
				lily.center = center
				lily.appearance_seed = rng.randi()
				lilies.append(lily)
				y -= radius * 2.0 + rng.randf_range(14.0, 28.0)
				placed = true
				break
			radius -= 8.0
		if not placed:
			break
	# A few more pads where there is room, off the rafts' way.
	var wanted := rng.randi_range(_config.lilies_per_pond.x, _config.lilies_per_pond.y)
	for attempt in 50:
		if lilies.size() >= wanted:
			break
		var radius := rng.randf_range(_config.lily_radius.x * 0.6, _config.lily_radius.y * 0.8)
		var angle := rng.randf() * TAU
		var point := pond.center + Vector2.from_angle(angle) * rng.randf() * loop.radius_at(angle) * 0.6
		var clear := true
		for other in lilies:
			if point.distance_to(other.center) < radius + other.radius + 24.0:
				clear = false
		if not clear or _lily_room(point, radius, pond, rafts) < 0.0:
			continue
		var lily := NelvarThicketData.Lily.new()
		lily.pond = index
		lily.radius = radius
		lily.center = point
		lily.appearance_seed = rng.randi()
		lilies.append(lily)
	return lilies


## Room left round a pad: negative where the shore or a passing raft would touch it.
func _lily_room(center: Vector2, radius: float, pond: NelvarEarthData.Radial,
		rafts: Array[NelvarThicketData.Raft]) -> float:
	var room := pond.signed_distance(center) - radius - 8.0
	for raft in rafts:
		for s in 96:
			room = minf(room, -raft.depth_at(center, raft.period * s / 96.0) - radius - 12.0)
			if room < 0.0:
				return room
	return room


# --- Hazards ----------------------------------------------------------------------------

func _hazards(rng: RandomNumberGenerator) -> void:
	_resin(rng)
	_loose(rng)
	_flytraps(rng)
	_puffballs(rng)


## Pools of resin round the feet of the pines inside.
func _resin(rng: RandomNumberGenerator) -> void:
	for giant in _data.inner_giants():
		if giant.species != Wood.PINE:
			continue
		var wanted := rng.randi_range(_config.resin_lobes.x, _config.resin_lobes.y)
		var placed := 0
		for attempt in 60:
			if placed >= wanted:
				break
			var radius := rng.randf_range(_config.resin_radius.x, _config.resin_radius.y)
			var angle := rng.randf() * TAU
			var point := giant.center + Vector2.from_angle(angle) * (giant.radius + radius * 0.45 + rng.randf_range(0.0, 40.0))
			if not _clear_of_trails(point, radius, 20.0) or _data.sun_at(point) > 0.4:
				continue
			if _data.valley.signed_distance(point) < radius + 40.0 or _data.pond_depth(point) > -radius:
				continue
			if point.distance_to(_data.spawn_position) < _config.start_clearance + radius:
				continue
			var pool := NelvarThicketData.Resin.new()
			pool.center = point
			pool.radius = radius
			pool.giant = giant.id
			_data.resin.append(pool)
			placed += 1


## Patches of loose earth, most by the roots, never on a trail.
func _loose(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.loose_patches.x, _config.loose_patches.y)
	for attempt in 400:
		if _data.loose.size() >= wanted:
			break
		var radius := rng.randf_range(_config.loose_radius.x, _config.loose_radius.y)
		var point := _random_floor_point(rng, 0.9)
		if attempt % 3 != 0 and not _data.roots.is_empty():
			var root := _data.roots[rng.randi_range(0, _data.roots.size() - 1)]
			var k := rng.randi_range(0, root.points.size() - 1)
			var side := root.points[k].direction_to(root.points[mini(k + 1, root.points.size() - 1)]).orthogonal()
			if side == Vector2.ZERO:
				continue
			point = root.points[k] + side * (root.widths[k] * 0.5 + radius * 0.55) * (1.0 if rng.randf() < 0.5 else -1.0)
		if not _hazard_room(point, radius * 1.2, 30.0):
			continue
		var patch := NelvarEarthData.Radial.new()
		patch.center = point
		patch.axes = Vector2(radius, radius * rng.randf_range(0.78, 1.0))
		_bend(patch, rng, 0.12, 0.2)
		_data.loose.append(patch)


## True when a disc of `radius` keeps `gap` from every trail (the trails' index only sees
## about a cell round a point, so the disc's rim is asked too).
func _clear_of_trails(point: Vector2, radius: float, gap: float) -> bool:
	if _data.trail_clearance(point) < radius + gap:
		return false
	for k in 12:
		if _data.trail_clearance(point + Vector2.from_angle(TAU * k / 12.0) * radius) < gap:
			return false
	return true


## Room for a hazard of `radius`: on the floor, off the trails (`trail_gap` beyond), the
## start, the water, the trunks, the fallen giant and the other hazards.
func _hazard_room(point: Vector2, radius: float, trail_gap: float) -> bool:
	if _data.valley.signed_distance(point) < radius + 60.0:
		return false
	if not _clear_of_trails(point, radius, trail_gap):
		return false
	if point.distance_to(_data.spawn_position) < _config.start_clearance + radius:
		return false
	if _data.pond_depth(point) > -(radius + 20.0) or _data.giant_at(point, radius + 10.0) != null:
		return false
	var fallen := _data.fallen
	if fallen != null and (fallen.covers(point, radius + 30.0) or fallen.plate_blocks(point, radius + 30.0)):
		return false
	if _data.loose_depth(point) > -(radius + 30.0) or _data.resin_depth(point) > -(radius + 30.0):
		return false
	for trap in _data.flytraps:
		if point.distance_to(trap.center) < radius + trap.radius + 24.0:
			return false
	for puffball in _data.puffballs:
		if point.distance_to(puffball.center) < radius + puffball.radius + _config.passage_width:
			return false
	return true


## Flytraps: groups on the edges of sunny clearings and by the ponds, and the garden:
## one clearing planted in rows with a petrified creature in the middle.
func _flytraps(rng: RandomNumberGenerator) -> void:
	var options: Array[int] = []
	for i in range(1, _data.clearings.size()):
		options.append(i)
	if not options.is_empty():
		_data.garden = options[rng.randi_range(0, options.size() - 1)]
		_garden(rng, _data.clearings[_data.garden])
	var wanted := rng.randi_range(_config.flytrap_groups.x, _config.flytrap_groups.y)
	var groups := 0
	for attempt in 200:
		if groups >= wanted:
			break
		var center: Vector2
		if not _data.ponds.is_empty() and rng.randf() < 0.35:
			var pond := _data.ponds[rng.randi_range(0, _data.ponds.size() - 1)]
			center = pond.point_at(rng.randf() * TAU, -rng.randf_range(90.0, 160.0))
		else:
			var index := rng.randi_range(1, maxi(1, _data.clearings.size() - 1))
			if index == _data.garden or index >= _data.clearings.size():
				continue
			var clearing := _data.clearings[index]
			center = clearing.center + Vector2.from_angle(rng.randf() * TAU) * clearing.radius * rng.randf_range(0.8, 1.05)
		var count := rng.randi_range(_config.flytraps_per_group.x, _config.flytraps_per_group.y)
		var placed := 0
		for k in 40:
			if placed >= count:
				break
			var radius := rng.randf_range(_config.flytrap_radius.x, _config.flytrap_radius.y)
			var point := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 170.0)
			if not _trap_room(point, radius):
				continue
			_add_trap(point, radius, false, rng)
			placed += 1
		if placed > 0:
			groups += 1


func _trap_room(point: Vector2, radius: float) -> bool:
	if not _hazard_room(point, radius, 20.0):
		return false
	for clearing in _data.clearings:
		if point.distance_to(clearing.center) < clearing.radius * 0.55 + radius:
			return false
	return _data.root_clearance(point) > 8.0


func _add_trap(point: Vector2, radius: float, garden: bool, rng: RandomNumberGenerator) -> void:
	var trap := NelvarThicketData.Flytrap.new()
	trap.id = _data.flytraps.size()
	trap.center = point
	trap.radius = radius
	trap.garden = garden
	trap.appearance_seed = rng.randi()
	_data.flytraps.append(trap)


func _garden(rng: RandomNumberGenerator, clearing: NelvarEarthData.Clearing) -> void:
	# The creature in the middle, off the trails meeting there.
	var statue := clearing.center
	for attempt in 40:
		var candidate := clearing.center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, clearing.radius * 0.4)
		if _data.trail_clearance(candidate) > 110.0:
			statue = candidate
			break
	if _data.trail_clearance(statue) > 100.0:
		_add_item(Kind.STATUE, statue, 50.0, true, false, rng, 0, rng.randf() < 0.5)
	var spacing := 165.0
	var turn := rng.randf_range(-0.2, 0.2)
	var reach := int(clearing.radius / spacing) + 1
	for row in range(-reach, reach + 1):
		for column in range(-reach, reach + 1):
			var point := clearing.center + Vector2(column * spacing, row * spacing * 0.8).rotated(turn)
			if point.distance_to(clearing.center) > clearing.radius * 0.9 or point.distance_to(statue) < 140.0:
				continue
			var radius := rng.randf_range(_config.flytrap_radius.x, _config.flytrap_radius.y) * 0.9
			if _hazard_room(point, radius, 24.0) and _data.root_clearance(point) > 8.0:
				_add_trap(point, radius, true, rng)


## Puffballs in groups on the damp ground: by the fallen giant, the ponds, the trunks.
func _puffballs(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.puffball_groups.x, _config.puffball_groups.y)
	var groups := 0
	for attempt in 500:
		if groups >= wanted:
			break
		var center := _random_floor_point(rng, 0.92)
		if _data.damp_at(center) < 0.45 or _data.sun_at(center) > 0.3:
			continue
		var count := rng.randi_range(_config.puffballs_per_group.x, _config.puffballs_per_group.y)
		var placed := 0
		for k in 30:
			if placed >= count:
				break
			var radius := rng.randf_range(_config.puffball_radius.x, _config.puffball_radius.y)
			var point := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 130.0)
			if not _hazard_room(point, radius, 40.0) or _data.root_clearance(point) < radius + _config.passage_width:
				continue
			var puffball := NelvarThicketData.Puffball.new()
			puffball.id = _data.puffballs.size()
			puffball.center = point
			puffball.radius = radius
			puffball.appearance_seed = rng.randi()
			_data.puffballs.append(puffball)
			placed += 1
		if placed > 0:
			groups += 1


# --- Things -------------------------------------------------------------------------------

func _add_item(kind: int, point: Vector2, radius: float, solid: bool, low: bool, rng: RandomNumberGenerator,
		variant: int = 0, accent: bool = false, size: Vector2 = Vector2.ZERO) -> NelvarThicketData.Item:
	var item := NelvarThicketData.Item.new()
	item.kind = kind
	item.position = point
	item.radius = radius
	item.solid = solid
	item.low = low
	item.variant = variant
	item.accent = accent
	item.size = size
	item.appearance_seed = rng.randi()
	_data.things.append(item)
	var cell := Vector2i((point / GRID).floor())
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append(item)
	return item


func _nearby(point: Vector2, reach: float) -> Array:
	var result := []
	var from := Vector2i(((point - Vector2.ONE * reach) / GRID).floor())
	var to := Vector2i(((point + Vector2.ONE * reach) / GRID).floor())
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			result.append_array(_grid.get(Vector2i(x, y), []))
	return result


## Shared rules for anything lying or standing on the floor. `trail_gap` < 0 lets it lie
## on a trail; solid things keep a passage from every other solid thing and root.
func _fits(point: Vector2, radius: float, solid: bool, trail_gap: float, spacing: float = 0.7) -> bool:
	if _data.valley.signed_distance(point) < radius + (70.0 if solid else 24.0):
		return false
	if _data.pond_depth(point) > -(radius + 10.0):
		return false
	if point.distance_to(_data.spawn_position) < (160.0 if solid else 50.0) + radius:
		return false
	if solid:
		for clearing in _data.clearings:
			if point.distance_to(clearing.center) < clearing.radius * 0.55 + radius:
				return false
	if trail_gap >= 0.0 and _data.trail_clearance(point) < radius + trail_gap:
		return false
	var passage := _config.passage_width
	if _data.giant_at(point, radius + (passage if solid else 6.0)) != null:
		return false
	var roots := _data.root_clearance(point)
	if roots < (radius + passage if solid else radius * 0.4):
		return false
	var fallen := _data.fallen
	if fallen != null and (fallen.covers(point, radius + (passage if solid else 4.0))
			or fallen.plate_blocks(point, radius + (passage if solid else 4.0))):
		return false
	if _data.loose_depth(point) > -(radius + 8.0) or _data.resin_depth(point) > -(radius + 8.0):
		return false
	for trap in _data.flytraps:
		if point.distance_to(trap.center) < radius + trap.radius + 10.0:
			return false
	for puffball in _data.puffballs:
		if point.distance_to(puffball.center) < radius + puffball.radius + (passage if solid else 8.0):
			return false
	for other: NelvarEarthData.Thing in _nearby(point, 300.0):
		var distance := point.distance_to(other.position)
		if other.solid and solid:
			if distance < radius + other.spread() + passage:
				return false
		elif other.solid or solid:
			if distance < (radius + other.spread()) * 0.9:
				return false
		elif distance < (radius + other.radius) * spacing:
			return false
	return true


## A point on the floor; `corner`: by a root or a trunk, where things gather.
func _spot(rng: RandomNumberGenerator, corner: bool) -> Vector2:
	if corner and not _data.roots.is_empty() and rng.randf() < 0.75:
		var root := _data.roots[rng.randi_range(0, _data.roots.size() - 1)]
		var k := rng.randi_range(0, root.points.size() - 1)
		var side := root.points[k].direction_to(root.points[mini(k + 1, root.points.size() - 1)]).orthogonal()
		if side == Vector2.ZERO:
			side = Vector2.RIGHT
		return root.points[k] + side * (root.widths[k] * 0.5 + rng.randf_range(30.0, 140.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
	return _random_floor_point(rng, 0.95)


func _in_crowns(point: Vector2) -> bool:
	return _data.sun_at(point) < 0.3


## The giant nearest the point (inner ones only), for what lies under its crown.
func _nearest_tree(point: Vector2) -> NelvarThicketData.Giant:
	var best: NelvarThicketData.Giant
	var best_distance := INF
	for giant in _data.giants:
		var d := giant.edge_distance(point)
		if d < best_distance:
			best_distance = d
			best = giant
	return best


func _things(rng: RandomNumberGenerator) -> void:
	_ambers(rng)
	_statues(rng)
	_ribs(rng)
	_tunnel(rng)
	_mushrooms(rng)
	_place(rng, Kind.TWIG, _config.twigs, func() -> Array:
		return [_spot(rng, true), rng.randf_range(14.0, 22.0), true, false, 30.0,
			Vector2(rng.randf_range(200.0, 400.0), 0.0)])
	_place(rng, Kind.SHELL, _config.shells, func() -> Array:
		return [_spot(rng, true), rng.randf_range(45.0, 70.0), true, false, 30.0, Vector2.ZERO])
	_place(rng, Kind.ROCK, _config.rocks, func() -> Array:
		return [_spot(rng, true), rng.randf_range(40.0, 64.0), true, false, 30.0, Vector2.ZERO])
	_flowers(rng)
	_acorns(rng)
	# Flat and soft things last: they fill in between.
	_place(rng, Kind.GRASS_BLADES, _config.grass_clumps, func() -> Array:
		var point := _sunny_spot(rng) if rng.randf() < 0.6 else _spot(rng, true)
		return [point, rng.randf_range(18.0, 34.0), false, false, 4.0, Vector2(0.0, rng.randf_range(80.0, 160.0))])
	_place(rng, Kind.CLOVER, _config.clovers, func() -> Array:
		return [_sunny_spot(rng), rng.randf_range(34.0, 56.0), false, false, 4.0, Vector2.ZERO])
	_place(rng, Kind.LEAF, _config.leaves, func() -> Array:
		var point := _spot(rng, rng.randf() < 0.5)
		if not _in_crowns(point):
			return []
		var tree := _nearest_tree(point)
		var variant := 0
		if tree != null:
			variant = [0, 2, 1, 0][tree.species]
		return [point, rng.randf_range(60.0, 130.0), false, false, 4.0, Vector2.ZERO, variant])
	_place(rng, Kind.FEATHER, _config.feathers, func() -> Array:
		return [_spot(rng, false), rng.randf_range(80.0, 130.0), false, false, 10.0, Vector2.ZERO])
	_place(rng, Kind.BONES, _config.bones, func() -> Array:
		return [_spot(rng, true), rng.randf_range(40.0, 70.0), false, false, 10.0, Vector2.ZERO, rng.randi_range(0, 2)])
	_dew(rng)
	_water_things(rng)


## Places up to `count` things of `kind`; `make` returns [point, radius, solid, low,
## trail gap, size, variant] or [] to skip.
func _place(rng: RandomNumberGenerator, kind: int, count: Vector2i, make: Callable) -> int:
	var wanted := rng.randi_range(count.x, count.y)
	var placed := 0
	for attempt in wanted * 14:
		if placed >= wanted:
			break
		var spec: Array = make.call()
		if spec.is_empty():
			continue
		var point: Vector2 = spec[0]
		var radius: float = spec[1]
		var solid: bool = spec[2]
		var footprint := radius
		var size: Vector2 = spec[5]
		if kind == Kind.TWIG:
			footprint = size.x * 0.5
		if not _fits(point, footprint, solid, spec[4]):
			continue
		var variant: int = spec[6] if spec.size() > 6 else rng.randi_range(0, 2)
		_add_item(kind, point, radius, solid, spec[3], rng, variant, rng.randf() < 0.3, size)
		placed += 1
	return placed


func _sunny_spot(rng: RandomNumberGenerator) -> Vector2:
	var index := rng.randi_range(0, _data.clearings.size() - 1)
	if index == _data.garden:
		index = 0
	var clearing := _data.clearings[index]
	return clearing.center + Vector2.from_angle(rng.randf() * TAU) * clearing.radius * sqrt(rng.randf()) * 1.1


## Drops of amber by the pines and at the foot of the ring; some hold a creature that
## watches.
func _ambers(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.ambers.x, _config.ambers.y)
	var placed := 0
	var pines: Array[NelvarThicketData.Giant] = []
	for giant in _data.giants:
		if giant.species == Wood.PINE:
			pines.append(giant)
	for attempt in 300:
		if placed >= wanted:
			break
		var radius := rng.randf_range(20.0, 45.0)
		var point: Vector2
		if not pines.is_empty() and rng.randf() < 0.6:
			var pine := pines[rng.randi_range(0, pines.size() - 1)]
			point = pine.center + Vector2.from_angle(rng.randf() * TAU) * (pine.radius + rng.randf_range(80.0, 420.0))
		else:
			point = _data.valley.point_at(rng.randf() * TAU, rng.randf_range(90.0, 180.0))
		if not _fits(point, radius, true, 30.0):
			continue
		_add_item(Kind.AMBER, point, radius, true, false, rng, rng.randi_range(0, 2), rng.randf() < 0.45)
		placed += 1


## Petrified creatures half grown into the roots.
func _statues(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.statues.x, _config.statues.y)
	var placed := 0
	for attempt in 300:
		if placed >= wanted:
			break
		var radius := rng.randf_range(42.0, 54.0)
		var point := _spot(rng, true)
		if not _fits(point, radius * 1.45, true, 40.0):
			continue
		var far := true
		for thing in _data.things:
			if thing.kind == Kind.STATUE and thing.position.distance_to(point) < 700.0:
				far = false
		if far:
			_add_item(Kind.STATUE, point, radius, true, false, rng, 1, rng.randf() < 0.5)
			placed += 1


## Now and then the ribs of something enormous, roots grown through them: two rows of
## bone pillars over a spine.
func _ribs(rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.35:
		return
	for attempt in 120:
		var center := _spot(rng, true)
		if not _in_crowns(center):
			continue
		var pairs := rng.randi_range(3, 5)
		var spacing := 96.0
		var half := 76.0
		var spots: Array[Vector2] = []
		for i in pairs:
			var x := (i - (pairs - 1) * 0.5) * spacing
			spots.append(center + Vector2(x, -half))
			spots.append(center + Vector2(x, half))
		var fits := true
		for spot in spots:
			if not _fits(spot, 16.0, true, 40.0):
				fits = false
				break
		if not fits:
			continue
		for i in spots.size():
			var height := rng.randf_range(160.0, 240.0) * (1.0 - absf(float(i / 2) - (pairs - 1) * 0.5) / pairs * 0.5)
			_add_item(Kind.RIB, spots[i], 16.0, true, false, rng, i % 2, false, Vector2(0.0, height))
		_add_item(Kind.BONES, center, 60.0, false, false, rng, 3, false, Vector2(pairs * spacing, 0.0))
		return


## Inside the fallen giant: glowing mushrooms along the walls, bones, and a petrified
## wanderer grown into the wood at the closed end.
func _tunnel(rng: RandomNumberGenerator) -> void:
	var fallen := _data.fallen
	if fallen == null:
		return
	var axis := fallen.axis()
	var normal := fallen.normal()
	var length := fallen.length()
	_add_item(Kind.STATUE, fallen.start + axis * (fallen.plate_depth + 44.0), 26.0, true, false, rng, 2, false)
	for i in rng.randi_range(5, 8):
		var along := rng.randf_range(fallen.plate_depth + 120.0, length - 60.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var point := fallen.start + axis * along + normal * side * (fallen.tunnel - 18.0)
		_add_item(Kind.GIANT_MUSHROOM, point, 8.0, false, false, rng, 2, true, Vector2(rng.randf_range(18.0, 30.0), rng.randf_range(24.0, 40.0)))
	for i in rng.randi_range(2, 3):
		var point := fallen.start + axis * rng.randf_range(fallen.plate_depth + 140.0, length - 120.0) \
			+ normal * rng.randf_range(-0.4, 0.4) * fallen.tunnel
		_add_item(Kind.BONES, point, rng.randf_range(30.0, 50.0), false, false, rng, rng.randi_range(0, 2))


## Giant mushrooms in groups on the damp ground; one can walk under their caps.
func _mushrooms(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.mushroom_groups.x, _config.mushroom_groups.y)
	var groups := 0
	for attempt in 400:
		if groups >= wanted:
			break
		var center := _spot(rng, true)
		if _data.damp_at(center) < 0.3 or not _in_crowns(center):
			continue
		var count := rng.randi_range(1, 3)
		var placed := 0
		for k in 10:
			if placed >= count:
				break
			var cap := rng.randf_range(60.0, 160.0)
			var stem := clampf(cap * rng.randf_range(0.14, 0.2), 12.0, 30.0)
			var point := center + Vector2(rng.randf_range(-160.0, 160.0), rng.randf_range(-90.0, 90.0))
			if not _fits(point, stem, true, 30.0) or not _cap_clear(point, cap):
				continue
			var height := cap * rng.randf_range(1.1, 1.7) + 40.0
			_add_item(Kind.GIANT_MUSHROOM, point, stem, true, false, rng, rng.randi_range(0, 1), false, Vector2(cap, height))
			placed += 1
		if placed > 0:
			groups += 1


func _cap_clear(point: Vector2, cap: float) -> bool:
	for other: NelvarEarthData.Thing in _nearby(point, 400.0):
		if other.kind == Kind.GIANT_MUSHROOM and other.position.distance_to(point) < (cap + other.size.x) * 0.75:
			return false
	return true


## Giant flowers on the clearings (never in the garden): a dandelion, a bluebell, a daisy;
## their stems are low obstacles.
func _flowers(rng: RandomNumberGenerator) -> void:
	_place(rng, Kind.GIANT_FLOWER, _config.flowers, func() -> Array:
		var point := _sunny_spot(rng)
		return [point, rng.randf_range(10.0, 14.0), true, true, 20.0, Vector2(0.0, rng.randf_range(120.0, 260.0))])


## Acorns under the oaks: whole, cracked, sprouted, and caps lying apart.
func _acorns(rng: RandomNumberGenerator) -> void:
	var oaks: Array[NelvarThicketData.Giant] = []
	for giant in _data.inner_giants():
		if giant.species == Wood.OAK:
			oaks.append(giant)
	if oaks.is_empty():
		return
	_place(rng, Kind.ACORN, _config.acorns, func() -> Array:
		var oak := oaks[rng.randi_range(0, oaks.size() - 1)]
		var point := oak.center + Vector2.from_angle(rng.randf() * TAU) * (oak.radius + rng.randf_range(40.0, oak.crown - oak.radius))
		if _data.oak_over(point) == null:
			return []
		var variant := rng.randi_range(0, 3)
		var radius := rng.randf_range(28.0, 40.0)
		var cap := variant == 3
		return [point, radius * (0.7 if cap else 1.0), not cap, not cap, 26.0, Vector2.ZERO, variant])


## Dew drops on the fallen leaves and by the grass under the crowns.
func _dew(rng: RandomNumberGenerator) -> void:
	var hosts: Array[NelvarEarthData.Thing] = []
	for thing in _data.things:
		if thing.kind == Kind.LEAF or thing.kind == Kind.GRASS_BLADES or thing.kind == Kind.CLOVER:
			hosts.append(thing)
	if hosts.is_empty():
		return
	var wanted := rng.randi_range(_config.dew_drops.x, _config.dew_drops.y)
	var placed := 0
	for attempt in wanted * 10:
		if placed >= wanted:
			break
		var host := hosts[rng.randi_range(0, hosts.size() - 1)]
		var point := host.position + Vector2.from_angle(rng.randf() * TAU) * host.radius * rng.randf_range(0.2, 0.7)
		if host.kind != Kind.LEAF:
			point = host.position + Vector2(rng.randf_range(-1.0, 1.0) * host.radius * 1.3, rng.randf_range(4.0, 16.0))
		var radius := rng.randf_range(12.0, 20.0)
		if _data.valley.signed_distance(point) < 60.0 or _data.pond_depth(point) > -20.0 \
				or _data.trail_clearance(point) < radius or _data.root_clearance(point) < radius:
			continue
		var crowded := false
		for other: NelvarEarthData.Thing in _nearby(point, 120.0):
			if other.kind == Kind.DEW and other.position.distance_to(point) < 70.0:
				crowded = true
			elif other.solid and other.position.distance_to(point) < other.spread() + radius:
				crowded = true
		if crowded:
			continue
		_add_item(Kind.DEW, point, radius, false, false, rng, 0, host.kind == Kind.LEAF)
		placed += 1


## Lily pads, and reeds at the shores (the line of pads' ends left free).
func _water_things(rng: RandomNumberGenerator) -> void:
	for lily in _data.lilies:
		var item := _add_item(Kind.LILY, lily.center, lily.radius, false, false, rng, lily.id, rng.randf() < 0.3)
		item.appearance_seed = lily.appearance_seed
	for p in _data.ponds.size():
		var pond := _data.ponds[p]
		var wanted := rng.randi_range(_config.reeds_per_pond.x, _config.reeds_per_pond.y)
		var placed := 0
		for attempt in 80:
			if placed >= wanted:
				break
			var angle := rng.randf() * TAU
			if absf(angle_difference(angle, PI * 0.5)) < 0.45 or absf(angle_difference(angle, -PI * 0.5)) < 0.45:
				continue
			var point := pond.point_at(angle, rng.randf_range(10.0, 36.0))
			var crowded := false
			for other: NelvarEarthData.Thing in _nearby(point, 200.0):
				if other.position.distance_to(point) < other.radius + 50.0:
					crowded = true
			if crowded or _data.trail_clearance(point) < 60.0 or _data.root_clearance(point) < 40.0:
				continue
			_add_item(Kind.REEDS, point, rng.randf_range(26.0, 40.0), false, false, rng, rng.randi_range(0, 1), false,
				Vector2(0.0, rng.randf_range(160.0, 260.0)))
			placed += 1
