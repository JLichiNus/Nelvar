class_name NelvarCaveGenerator
extends RefCounted
## Lays out the ice cave from a seed: the halls (cold arenas, sunny halls, dark halls,
## grottos), the passages between them — a spanning tree of the Delaunay triangulation
## of the halls plus a share of its other edges, so there are loops and many ways to a
## place — winding, with niches and slits, a grotto at the end of each dead end; the ice
## pillars; the walls' distance field with the thin walls cut away; the sunny spots and
## their snow, the icy passages and the start; chasms with ice arches, crevasses with
## snow bridges, geysers, the lakes (frozen, melting, open water), the creatures frozen
## into the lakes and the walls and floating on the water, and everything standing on
## the floor.
##
## Every stage draws from its own seeded generator. After each chasm, crevasse and
## melting or open lake the floor is searched from the start: what would cut a hall off
## (or most of the floor) is not kept, so melting ice and open water never lie on the
## only way anywhere, and every chasm on a needed way has an arch.

const Kind = NelvarIceData.Kind
const Zone = NelvarCaveData.Zone
const Pool = NelvarCaveData.Pool
const Crystal = NelvarCaveData.Crystal
const CELL := NelvarCaveData.CELL
const PIXEL := NelvarIceData.PIXEL
const BODY := NelvarPlayer.BODY_RADIUS
## The floor's depth is taken exactly within this band of the outline, the distance
## transform further in.
const BAND := 24.0
## Rows of samples per bucket of shapes while carving.
const ROWS := 16
## The search grid of the reachability checks.
const REACH_CELL := 20.0
## How far placed things look for neighbours.
const GRID := 160.0
const PINE_TRUNK := Vector2(11.0, 16.0)
const PINE_CROWN := Vector2(40.0, 58.0)
const PINE_HEIGHT := Vector2(170.0, 240.0)
const DEAD_TRUNK := Vector2(9.0, 13.0)
const DEAD_CROWN := Vector2(28.0, 44.0)
const DEAD_HEIGHT := Vector2(120.0, 180.0)
const BIG := 1.0e12

var _config: NelvarCaveConfig
var _data: NelvarCaveData
var _grid := {}
## Carving: the samples' floor depth (exact near the outline), the floor mask.
var _floor := PackedFloat32Array()
var _mask := PackedByteArray()
var _size := Vector2i.ZERO
var _buckets: Array = []
var _edt := PackedFloat32Array()
var _edt_want := 0
## The reachability grid: open floor, and what the hazards kept so far block.
var _reach_size := Vector2i.ZERO
var _open := PackedByteArray()
var _blocked := PackedByteArray()
var _open_total := 0


func generate(config: NelvarCaveConfig, world_seed: int) -> NelvarCaveData:
	var error := config.validation_error()
	if not error.is_empty():
		push_error("Cave config: " + error)
		return null
	_config = config
	_data = NelvarCaveData.new()
	_data.world_seed = world_seed
	_data.bounds = Rect2(-config.size * 0.5, config.size)
	_grid.clear()
	_halls(_rng("halls"))
	_graph(_rng("graph"))
	_grottos(_rng("grottos"))
	_niches(_rng("niches"))
	_columns(_rng("columns"))
	_carve()
	_data.index_halls()
	_data.index_passages()
	_zones(_rng("zones"))
	_reach_base()
	_chasms(_rng("chasms"))
	_data.index_chasms()
	_crevasses(_rng("crevasses"))
	_data.index_crevasses()
	_geysers(_rng("geysers"))
	_lakes(_rng("lakes"))
	_thin_ice(_rng("thin"))
	_creatures(_rng("creatures"))
	_floaters(_rng("floaters"))
	_things(_rng("things"))
	_embedded(_rng("embedded"))
	_data.finish()
	var result := _data
	_data = null
	_grid.clear()
	_floor = PackedFloat32Array()
	_mask = PackedByteArray()
	_edt = PackedFloat32Array()
	_buckets.clear()
	return result


func _rng(stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:cave:%s" % [_data.world_seed, stage]).hash()
	return rng


## Slow bends: harmonic k gets a share of `depth` falling with k; the sum stays below
## `limit`, so the shape never pinches.
static func bend(shape: NelvarEarthData.Radial, rng: RandomNumberGenerator, depth: float, limit: float) -> void:
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


static func radial(center: Vector2, axes: Vector2, rng: RandomNumberGenerator, depth: float,
		limit: float) -> NelvarEarthData.Radial:
	var shape := NelvarEarthData.Radial.new()
	shape.center = center
	shape.axes = axes
	bend(shape, rng, depth, limit)
	return shape


# --- Halls ---------------------------------------------------------------------------

## The cold arenas first (the biggest), then the sunny halls, then the dark ones; each at
## the best of a dozen tries: the one whose room to its neighbours comes nearest a
## passage's length, so the halls fill the cave evenly.
func _halls(rng: RandomNumberGenerator) -> void:
	var plan: Array[Array] = []
	for i in rng.randi_range(_config.cold_halls.x, _config.cold_halls.y):
		plan.append([Zone.COLD, _config.cold_radius, i < _config.cold_halls.x])
	for i in rng.randi_range(_config.sunny_halls.x, _config.sunny_halls.y):
		plan.append([Zone.SUNNY, _config.sunny_radius, i < _config.sunny_halls.x])
	for i in rng.randi_range(_config.plain_halls.x, _config.plain_halls.y):
		plan.append([Zone.DARK, _config.plain_radius, i < _config.plain_halls.x])
	for entry in plan:
		_place_hall(rng, entry[0], entry[1], entry[2], _config.hall_gap)


func _place_hall(rng: RandomNumberGenerator, zone: Zone, radii: Vector2, needed: bool, gap: float) -> bool:
	var inner := _data.bounds.grow(-_config.margin)
	for round_index in (6 if needed else 2):
		var shrink := 1.0 - 0.16 * round_index
		var best: NelvarEarthData.Radial = null
		var best_room := -INF
		for attempt in 14:
			var radius := lerpf(radii.x, radii.y, rng.randf() * maxf(shrink, 0.0))
			var axes := Vector2(radius, radius * rng.randf_range(0.74, 0.94))
			if rng.randf() < 0.4:
				axes = Vector2(axes.y, axes.x)
			var shape := radial(Vector2.ZERO, axes, rng, _config.hall_wobble, 0.2)
			var reach := shape.reach()
			var box := inner.grow(-reach)
			if box.size.x <= 0.0 or box.size.y <= 0.0:
				continue
			shape.center = box.position + Vector2(rng.randf(), rng.randf()) * box.size
			var room := INF
			for hall in _data.halls:
				room = minf(room, _between(shape, hall.shape))
			if room < gap:
				continue
			var score := -absf(room - gap - 160.0) if room < INF else rng.randf()
			if score > best_room:
				best_room = score
				best = shape
		if best != null:
			var hall := NelvarCaveData.Hall.new()
			hall.shape = best
			hall.zone = zone
			_data.halls.append(hall)
			return true
	return false


# --- The graph of passages ---------------------------------------------------------

## A spanning tree of the Delaunay triangulation of the main halls plus a share of its
## other edges; edges that would graze a third hall are left out; every main hall gets at
## least two ways out.
func _graph(rng: RandomNumberGenerator) -> void:
	var centers := PackedVector2Array()
	for hall in _data.halls:
		centers.append(hall.shape.center)
	var edges := {}
	if centers.size() >= 3:
		var triangles := Geometry2D.triangulate_delaunay(centers)
		for t in range(0, triangles.size(), 3):
			for k in 3:
				var a := triangles[t + k]
				var b := triangles[t + (k + 1) % 3]
				edges[Vector2i(mini(a, b), maxi(a, b))] = true
	else:
		for a in centers.size():
			for b in range(a + 1, centers.size()):
				edges[Vector2i(a, b)] = true
	var valid: Array[Vector2i] = []
	var grazing: Array[Vector2i] = []
	for edge: Vector2i in edges:
		if _edge_clear(edge.x, edge.y):
			valid.append(edge)
		else:
			grazing.append(edge)
	var by_length := func(p: Vector2i, q: Vector2i) -> bool:
		return _edge_length(p) < _edge_length(q)
	valid.sort_custom(by_length)
	grazing.sort_custom(by_length)
	# Kruskal's spanning tree, over the grazing edges only where the clear ones fail.
	var parent: Array[int] = []
	for i in centers.size():
		parent.append(i)
	var chosen: Array[Vector2i] = []
	for edge in valid + grazing:
		var ra := _root(parent, edge.x)
		var rb := _root(parent, edge.y)
		if ra != rb:
			parent[ra] = rb
			chosen.append(edge)
	var rest: Array[Vector2i] = []
	for edge in valid:
		if not chosen.has(edge):
			rest.append(edge)
	# Loops: a share of the rest, the shorter ones likelier.
	var share := rng.randf_range(_config.extra_passages.x, _config.extra_passages.y)
	var wanted := roundi(rest.size() * share)
	var weighted: Array[Array] = []
	for edge in rest:
		weighted.append([_edge_length(edge) * rng.randf_range(0.7, 1.4), edge])
	weighted.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for i in mini(wanted, weighted.size()):
		chosen.append(weighted[i][1])
		rest.erase(weighted[i][1])
	# Two ways out of every hall.
	for h in centers.size():
		if _degree(chosen, h) >= 2:
			continue
		for edge in rest:
			if edge.x == h or edge.y == h:
				chosen.append(edge)
				rest.erase(edge)
				break
	for edge in chosen:
		_add_passage(rng, edge.x, edge.y)


func _root(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _degree(edges: Array[Vector2i], h: int) -> int:
	var total := 0
	for edge in edges:
		if edge.x == h or edge.y == h:
			total += 1
	return total


## Ice between the two halls' edges along the straight line.
func _edge_length(edge: Vector2i) -> float:
	return _between(_data.halls[edge.x].shape, _data.halls[edge.y].shape)


## Ice between two outlines along the line joining their centres (a little less to the
## sides: their bends).
static func _between(a: NelvarEarthData.Radial, b: NelvarEarthData.Radial) -> float:
	var angle := a.center.angle_to_point(b.center)
	var straight := a.center.distance_to(b.center) - a.radius_at(angle) - b.radius_at(angle + PI)
	var side := a.center.distance_to(b.center) - maxf(a.radius_at(angle + 0.3), a.radius_at(angle - 0.3)) \
		- maxf(b.radius_at(angle + PI + 0.3), b.radius_at(angle + PI - 0.3))
	return minf(straight, side + 40.0)


## The straight way between two halls keeps clear of every other hall.
func _edge_clear(a: int, b: int) -> bool:
	var from := _data.halls[a].shape.center
	var to := _data.halls[b].shape.center
	for h in _data.halls.size():
		if h == a or h == b:
			continue
		var shape := _data.halls[h].shape
		var closest := Geometry2D.get_closest_point_to_segment(shape.center, from, to)
		if shape.signed_distance(closest) > -(_config.passage_half_width.y + 70.0):
			return false
	return true


## A winding passage from hall a to hall b: it starts and ends well inside them, bends,
## keeps off the other halls, and its width wanders, now and then narrowing to a slit.
func _add_passage(rng: RandomNumberGenerator, a: int, b: int, slit_ok: bool = true) -> NelvarCaveData.Passage:
	var from_shape := _data.halls[a].shape
	var to_shape := _data.halls[b].shape
	var direction := from_shape.center.direction_to(to_shape.center)
	var start := from_shape.center + direction * from_shape.radius_at(direction.angle()) * 0.55
	var end := to_shape.center - direction * to_shape.radius_at((-direction).angle()) * 0.55
	var passage := NelvarCaveData.Passage.new()
	passage.from = a
	passage.to = b
	passage.points = _wind(rng, start, end, [a, b])
	passage.measure()
	var total := passage.length()
	var base := rng.randf_range(_config.passage_half_width.x, _config.passage_half_width.y)
	var salt := rng.randi() & 0xffff
	var slit := Vector2(-1.0, 0.0)
	if slit_ok and total > 420.0 and rng.randf() < _config.slit_chance:
		slit = Vector2(total * rng.randf_range(0.35, 0.65), rng.randf_range(40.0, 80.0))
	passage.half_widths.resize(passage.points.size())
	for i in passage.points.size():
		var along := passage.lengths[i]
		var wander := NelvarPixelArt.value_noise(along * 0.005, 0.5, salt)
		var half := clampf(base * (0.72 + 0.56 * wander), _config.passage_half_width.x, _config.passage_half_width.y)
		if slit.x >= 0.0:
			var off := absf(along - slit.x)
			half = lerpf(_config.slit_half_width, half, smoothstep(slit.y, slit.y + 70.0, off))
		passage.half_widths[i] = half
	_data.passages.append(passage)
	_data.halls[a].exits.append(_data.passages.size() - 1)
	_data.halls[b].exits.append(_data.passages.size() - 1)
	return passage


## A bending line from a to b that keeps off the halls but `own`.
func _wind(rng: RandomNumberGenerator, a: Vector2, b: Vector2, own: Array) -> PackedVector2Array:
	var length := a.distance_to(b)
	var count := maxi(4, int(length / 55.0))
	var normal := a.direction_to(b).orthogonal()
	var amplitude := minf(length * 0.16, 150.0) * rng.randf_range(0.35, 1.0)
	var waves := rng.randf_range(0.8, 2.3)
	var phase := rng.randf() * TAU
	var jitter := rng.randf_range(10.0, 26.0)
	var salt := rng.randi() & 0xffff
	var points: Array[Vector2] = []
	for i in count + 1:
		var t := float(i) / count
		var wave := sin(PI * t) * (sin(phase + t * PI * waves) * amplitude
			+ (NelvarPixelArt.value_noise(t * 6.0, 1.5, salt) - 0.5) * 2.0 * jitter)
		points.append(a.lerp(b, t) + normal * wave)
	var keep := _config.passage_half_width.y + 60.0
	for iteration in 6:
		for i in range(1, points.size() - 1):
			var p := points[i]
			for h in _data.halls.size():
				if own.has(h):
					continue
				var shape := _data.halls[h].shape
				var depth := shape.signed_distance(p)
				if depth > -keep:
					p += shape.center.direction_to(p) * (depth + keep)
			var inner := _data.bounds.grow(-_config.margin - keep)
			points[i] = p.clamp(inner.position, inner.end)
		var smooth: Array[Vector2] = points.duplicate()
		for i in range(1, points.size() - 1):
			smooth[i] = points[i - 1] * 0.25 + points[i] * 0.5 + points[i + 1] * 0.25
		points = smooth
	for pass_index in 2:
		var cut: Array[Vector2] = [points[0]]
		for i in points.size() - 1:
			cut.append(points[i].lerp(points[i + 1], 0.25))
			cut.append(points[i].lerp(points[i + 1], 0.75))
		cut.append(points[points.size() - 1])
		points = cut
	return PackedVector2Array(points)


## Grottos at the ends of dead ends: small halls hung on one passage from the nearest
## main hall, clear of the other halls and passages.
func _grottos(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.grottos.x, _config.grottos.y)
	var placed := 0
	var inner := _data.bounds.grow(-_config.margin)
	for attempt in 700:
		if placed >= wanted:
			break
		var radius := rng.randf_range(_config.grotto_radius.x, _config.grotto_radius.y)
		var shape := radial(Vector2.ZERO, Vector2(radius, radius * rng.randf_range(0.78, 0.95)), rng, 0.12, 0.2)
		var box := inner.grow(-shape.reach())
		shape.center = box.position + Vector2(rng.randf(), rng.randf()) * box.size
		var nearest := -1
		var nearest_gap := INF
		var fits := true
		for h in _data.halls.size():
			var other := _data.halls[h].shape
			var gap := _between(shape, other)
			if gap < 140.0:
				fits = false
				break
			if _data.halls[h].is_main() and gap < nearest_gap:
				nearest_gap = gap
				nearest = h
		if not fits or nearest < 0 or nearest_gap > 680.0:
			continue
		var host := _data.halls[nearest].shape
		var straight := [host.center, shape.center]
		var clear := true
		for h in _data.halls.size():
			if h == nearest:
				continue
			var other := _data.halls[h].shape
			var closest := Geometry2D.get_closest_point_to_segment(other.center, straight[0], straight[1])
			if other.signed_distance(closest) > -(_config.passage_half_width.y + 90.0):
				clear = false
		if not clear:
			continue
		for passage in _data.passages:
			if _polyline_gap(passage, host.center.lerp(shape.center, 0.35), shape.center) \
					< passage.widest() + _config.passage_half_width.y + 70.0:
				clear = false
				break
		if not clear:
			continue
		var grotto := NelvarCaveData.Hall.new()
		grotto.shape = shape
		grotto.zone = Zone.GROTTO
		_data.halls.append(grotto)
		var passage := _add_passage(rng, nearest, _data.halls.size() - 1, false)
		# The way in stays narrow-ish and never touches another passage.
		var touching := false
		for other in _data.passages:
			if other == passage:
				continue
			for i in range(passage.points.size() / 3, passage.points.size()):
				if NelvarFireData.polyline_distance(other.points, passage.points[i]) \
						< other.widest() + passage.widest() + 60.0:
					touching = true
					break
			if touching:
				break
		if touching:
			_data.passages.pop_back()
			_data.halls[nearest].exits.pop_back()
			_data.halls.pop_back()
			continue
		placed += 1


## Shortest distance between a passage's centre line and the segment a-b.
func _polyline_gap(passage: NelvarCaveData.Passage, a: Vector2, b: Vector2) -> float:
	var best := INF
	for i in passage.points.size() - 1:
		var p := Geometry2D.get_closest_points_between_segments(a, b, passage.points[i], passage.points[i + 1])
		best = minf(best, p[0].distance_to(p[1]))
	return best


## Niches and pockets beside the passages (things stand in them, the way stays free).
func _niches(rng: RandomNumberGenerator) -> void:
	for passage in _data.passages:
		var total := passage.length()
		for i in rng.randi_range(_config.niches.x, _config.niches.y):
			var along := total * rng.randf_range(0.25, 0.75)
			var point := passage.point_at(along)
			if _data.halls[passage.from].shape.signed_distance(point) > -60.0 \
					or _data.halls[passage.to].shape.signed_distance(point) > -60.0:
				continue
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var radius := rng.randf_range(40.0, 72.0)
			var normal := passage.direction_at(along).orthogonal() * side
			var center := point + normal * (passage.half_width_at(along) + radius * 0.35)
			passage.niches.append(radial(center, Vector2(radius, radius * rng.randf_range(0.7, 0.95)), rng, 0.14, 0.22))


## Ice pillars in the big halls: off the middle, the ways in and each other.
func _columns(rng: RandomNumberGenerator) -> void:
	for hall in _data.halls:
		var small := minf(hall.shape.axes.x, hall.shape.axes.y)
		var wanted := 0
		if hall.zone == Zone.COLD:
			wanted = rng.randi_range(_config.columns.x, _config.columns.y)
		elif hall.zone == Zone.DARK and small > 260.0:
			wanted = rng.randi_range(0, 2)
		for attempt in wanted * 20:
			if hall.columns.size() >= wanted:
				break
			var radius := rng.randf_range(_config.column_radius.x, _config.column_radius.y) * clampf(small / 450.0, 0.6, 1.0)
			var angle := rng.randf() * TAU
			var center := hall.shape.point_at(angle, 0.0).lerp(hall.shape.center, 1.0 - rng.randf_range(0.42, 0.76))
			if hall.shape.signed_distance(center) < radius + 110.0:
				continue
			var free := true
			for exit in hall.exits:
				var passage := _data.passages[exit]
				if NelvarFireData.polyline_distance(passage.points, center) < passage.widest() + radius + 80.0:
					free = false
			for other in hall.columns:
				if center.distance_to(other.center) < radius + other.reach() + 140.0:
					free = false
			if free:
				hall.columns.append(radial(center, Vector2(radius, radius * rng.randf_range(0.72, 0.95)), rng, 0.14, 0.22))


# --- The walls' distance field -------------------------------------------------------

## The floor (halls, niches, passages, less the pillars) as an exact depth near its
## outline; thin walls cut away (a wall must stand FACE + FACE_SPARE art pixels over each
## south face), crumbs of ice and pockets of floor cut off from the rest removed; then
## the signed distance everywhere.
func _carve() -> void:
	_size = Vector2i((_data.bounds.size / CELL).floor()) + Vector2i.ONE
	_data.sdf_origin = _data.bounds.position
	_data.sdf_size = _size
	_floor.resize(_size.x * _size.y)
	_floor.fill(-BAND - 1.0)
	_mask.resize(_size.x * _size.y)
	_buckets.clear()
	_buckets.resize(_size.y / ROWS + 1)
	for i in _buckets.size():
		_buckets[i] = []
	var shapes: Array = []
	for hall in _data.halls:
		shapes.append([0, hall.shape])
		for column in hall.columns:
			shapes.append([2, column])
	for passage in _data.passages:
		for niche in passage.niches:
			shapes.append([0, niche])
		for i in passage.points.size() - 1:
			shapes.append([1, passage.points[i], passage.points[i + 1], passage.half_widths[i], passage.half_widths[i + 1]])
	for shape: Array in shapes:
		var box := _shape_box(shape)
		var first := clampi(int((box.position.y - _data.sdf_origin.y) / CELL) / ROWS, 0, _buckets.size() - 1)
		var last := clampi(int((box.end.y - _data.sdf_origin.y) / CELL) / ROWS, 0, _buckets.size() - 1)
		for b in range(first, last + 1):
			_buckets[b].append(shape)
	var group := WorkerThreadPool.add_group_task(_carve_row, _size.y, -1, true, "Cave walls")
	WorkerThreadPool.wait_for_group_task_completion(group)
	for i in _floor.size():
		_mask[i] = 1 if _floor[i] > 0.0 else 0
	# A sample of slack: the outline lies between the samples.
	var least := (NelvarCaveData.FACE + NelvarCaveData.FACE_SPARE) * PIXEL + CELL * 1.5
	for round_index in 2:
		_cut_thin(true, least)
		_cut_thin(false, 2.5 * CELL)
	_cut_thin(true, least)
	_clean_islands()
	_signed_distance()


func _shape_box(shape: Array) -> Rect2:
	match shape[0]:
		1:
			var a: Vector2 = shape[1]
			var b: Vector2 = shape[2]
			var reach := maxf(shape[3], shape[4]) + BAND + CELL
			return Rect2(a.min(b) - Vector2.ONE * reach, (a.max(b) - a.min(b)) + Vector2.ONE * reach * 2.0)
	var radial_shape: NelvarEarthData.Radial = shape[1]
	var r := radial_shape.reach() + BAND + CELL
	return Rect2(radial_shape.center - Vector2.ONE * r, Vector2.ONE * r * 2.0)


## One row of samples: the deepest floor shape over it, less the pillars and the edge.
func _carve_row(y: int) -> void:
	var py := _data.sdf_origin.y + y * CELL
	var row := y * _size.x
	var shapes: Array = _buckets[y / ROWS]
	var columns: Array = []
	for shape: Array in shapes:
		var box := _shape_box(shape)
		if py < box.position.y or py > box.end.y:
			continue
		var x0 := clampi(int((box.position.x - _data.sdf_origin.x) / CELL), 0, _size.x - 1)
		var x1 := clampi(int((box.end.x - _data.sdf_origin.x) / CELL) + 1, 0, _size.x - 1)
		match shape[0]:
			0:
				var hall: NelvarEarthData.Radial = shape[1]
				for x in range(x0, x1 + 1):
					var d := hall.signed_distance(Vector2(_data.sdf_origin.x + x * CELL, py))
					if d > _floor[row + x]:
						_floor[row + x] = d
			1:
				var a: Vector2 = shape[1]
				var b: Vector2 = shape[2]
				var ha: float = shape[3]
				var hb: float = shape[4]
				var span := b - a
				var length_squared := maxf(span.length_squared(), 0.0001)
				for x in range(x0, x1 + 1):
					var p := Vector2(_data.sdf_origin.x + x * CELL, py)
					var t := clampf((p - a).dot(span) / length_squared, 0.0, 1.0)
					var d := lerpf(ha, hb, t) - p.distance_to(a + span * t)
					if d > _floor[row + x]:
						_floor[row + x] = d
			2:
				columns.append(shape)
	for shape: Array in columns:
		var column: NelvarEarthData.Radial = shape[1]
		var box := _shape_box(shape)
		var x0 := clampi(int((box.position.x - _data.sdf_origin.x) / CELL), 0, _size.x - 1)
		var x1 := clampi(int((box.end.x - _data.sdf_origin.x) / CELL) + 1, 0, _size.x - 1)
		for x in range(x0, x1 + 1):
			var d := -column.signed_distance(Vector2(_data.sdf_origin.x + x * CELL, py))
			if d < _floor[row + x]:
				_floor[row + x] = d
	var inner := _data.bounds.grow(-_config.margin * 0.5)
	for x in _size.x:
		var px := _data.sdf_origin.x + x * CELL
		var edge := minf(minf(px - inner.position.x, inner.end.x - px), minf(py - inner.position.y, inner.end.y - py))
		if edge < _floor[row + x]:
			_floor[row + x] = edge


## Runs of wall thinner than `least` between floor on both sides (down the columns, or
## along the rows) become floor.
func _cut_thin(vertical: bool, least: float) -> void:
	var lines := _size.x if vertical else _size.y
	var length := _size.y if vertical else _size.x
	for line in lines:
		var run_start := -1
		for k in length:
			var index := k * _size.x + line if vertical else line * _size.x + k
			if _mask[index] == 0:
				if run_start < 0:
					run_start = k
				continue
			if run_start > 0 and (k - run_start) * CELL < least:
				for j in range(run_start, k):
					_mask[j * _size.x + line if vertical else line * _size.x + j] = 1
			run_start = -1


## Crumbs of ice (small wall islands) melt into the floor; floor cut off from the main
## floor freezes into the wall.
func _clean_islands() -> void:
	var labels := PackedInt32Array()
	labels.resize(_mask.size())
	labels.fill(-1)
	var sizes: Array[int] = []
	var borders: Array[bool] = []
	var kinds: Array[int] = []
	for start in _mask.size():
		if labels[start] >= 0:
			continue
		var kind := _mask[start]
		var label := sizes.size()
		var queue := PackedInt32Array([start])
		labels[start] = label
		var count := 0
		var border := false
		while count < queue.size():
			var index := queue[count]
			count += 1
			var x := index % _size.x
			var y := index / _size.x
			if x == 0 or y == 0 or x == _size.x - 1 or y == _size.y - 1:
				border = true
			for next: int in [index - 1, index + 1, index - _size.x, index + _size.x]:
				if next < 0 or next >= _mask.size():
					continue
				if (next == index - 1 and x == 0) or (next == index + 1 and x == _size.x - 1):
					continue
				if labels[next] < 0 and _mask[next] == kind:
					labels[next] = label
					queue.append(next)
		sizes.append(count)
		borders.append(border)
		kinds.append(kind)
	var main_floor := -1
	for label in sizes.size():
		if kinds[label] == 1 and (main_floor < 0 or sizes[label] > sizes[main_floor]):
			main_floor = label
	for index in _mask.size():
		var label := labels[index]
		if kinds[label] == 0 and not borders[label] and sizes[label] < 70:
			_mask[index] = 1
		elif kinds[label] == 1 and label != main_floor:
			_mask[index] = 0


## Signed distance from the mask: the distance transform everywhere, the exact depth near
## an outline the cleaning left alone.
func _signed_distance() -> void:
	var to_wall := _transform(0)
	var to_floor := _transform(1)
	var changed := PackedByteArray()
	changed.resize(_mask.size())
	for index in _mask.size():
		if (_mask[index] == 1) != (_floor[index] > 0.0):
			changed[index] = 1
	var near := changed.duplicate()
	for y in _size.y:
		for x in _size.x:
			if changed[y * _size.x + x] == 0:
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < _size.x and ny < _size.y:
						near[ny * _size.x + nx] = 1
	var sdf := PackedFloat32Array()
	sdf.resize(_mask.size())
	for index in _mask.size():
		var value: float
		if _mask[index] == 1:
			value = -(sqrt(to_wall[index]) * CELL - CELL * 0.5)
		else:
			value = sqrt(to_floor[index]) * CELL - CELL * 0.5
		var exact := _floor[index]
		if near[index] == 0 and absf(exact) < BAND:
			value = lerpf(-exact, value, smoothstep(BAND * 0.6, BAND, absf(exact)))
		sdf[index] = value
	_data.sdf = sdf


## Squared distance (in samples) to the nearest sample whose mask is `want`
## (Felzenszwalb and Huttenlocher), rows then columns on several cores.
func _transform(want: int) -> PackedFloat32Array:
	_edt = PackedFloat32Array()
	_edt.resize(_mask.size())
	_edt_want = want
	var rows := WorkerThreadPool.add_group_task(_transform_row, _size.y, -1, true, "Cave distance rows")
	WorkerThreadPool.wait_for_group_task_completion(rows)
	var columns := WorkerThreadPool.add_group_task(_transform_column, _size.x, -1, true, "Cave distance columns")
	WorkerThreadPool.wait_for_group_task_completion(columns)
	return _edt


func _transform_row(y: int) -> void:
	var f := PackedFloat32Array()
	f.resize(_size.x)
	for x in _size.x:
		f[x] = 0.0 if _mask[y * _size.x + x] == _edt_want else BIG
	var d := _line_transform(f, _size.x)
	for x in _size.x:
		_edt[y * _size.x + x] = d[x]


func _transform_column(x: int) -> void:
	var f := PackedFloat32Array()
	f.resize(_size.y)
	for y in _size.y:
		f[y] = _edt[y * _size.x + x]
	var d := _line_transform(f, _size.y)
	for y in _size.y:
		_edt[y * _size.x + x] = d[y]


static func _line_transform(f: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(n)
	var v := PackedInt32Array()
	v.resize(n)
	var z := PackedFloat32Array()
	z.resize(n + 1)
	var k := 0
	v[0] = 0
	z[0] = -BIG
	z[1] = BIG
	for q in range(1, n):
		var fq := f[q] + q * q
		var vk := v[k]
		var s := (fq - (f[vk] + vk * vk)) / (2.0 * (q - vk))
		while s <= z[k]:
			k -= 1
			vk = v[k]
			s = (fq - (f[vk] + vk * vk)) / (2.0 * (q - vk))
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = BIG
	k = 0
	for q in n:
		while z[k + 1] < q:
			k += 1
		var r := q - v[k]
		d[q] = minf(r * r + f[v[k]], BIG)
	return d


# --- Zones and the start ---------------------------------------------------------------

## The sunny spots (snow round them and into the passages), the icy passages, and the
## start: a sunny hall with a way out to the north, on its snow.
func _zones(rng: RandomNumberGenerator) -> void:
	for h in _data.halls.size():
		var hall := _data.halls[h]
		if hall.zone != Zone.SUNNY:
			continue
		var small := minf(hall.shape.axes.x, hall.shape.axes.y)
		var skylight := NelvarCaveData.Skylight.new()
		skylight.hall = h
		var radius := minf(rng.randf_range(_config.skylight_radius.x, _config.skylight_radius.y), small * 0.78)
		var center := hall.shape.center + Vector2.from_angle(rng.randf() * TAU) * small * rng.randf_range(0.0, 0.18)
		skylight.spot = radial(center, Vector2(radius, radius * rng.randf_range(0.74, 0.94)), rng, 0.12, 0.2)
		skylight.reach = rng.randf_range(_config.snow_reach.x, _config.snow_reach.y)
		_data.skylights.append(skylight)
		for exit in hall.exits:
			_tongue(rng, _data.passages[exit], h)
	# Icy passages: between dark or cold halls.
	var candidates: Array[int] = []
	for p in _data.passages.size():
		var passage := _data.passages[p]
		var ends := [_data.halls[passage.from].zone, _data.halls[passage.to].zone]
		if not ends.has(Zone.SUNNY) and not ends.has(Zone.GROTTO) and passage.length() > 300.0:
			candidates.append(p)
	for i in candidates.size():
		var j := rng.randi_range(i, candidates.size() - 1)
		var swap := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	for i in mini(rng.randi_range(_config.icy_passages.x, _config.icy_passages.y), candidates.size()):
		_data.passages[candidates[i]].icy = true
	_start(rng)


## Snow running from a sunny hall into one of its passages, tapering.
func _tongue(rng: RandomNumberGenerator, passage: NelvarCaveData.Passage, hall: int) -> void:
	var total := passage.length()
	var shape := _data.halls[hall].shape
	var forward := passage.from == hall
	var edge := -1.0
	var along := 0.0
	while along <= total:
		var at := along if forward else total - along
		if shape.signed_distance(passage.point_at(at)) < 0.0:
			edge = along
			break
		along += 10.0
	if edge < 0.0:
		return
	var reach := rng.randf_range(_config.snow_tongue.x, _config.snow_tongue.y)
	var tongue := NelvarCaveData.Tongue.new()
	var from := maxf(0.0, edge - 60.0)
	var to := minf(total, edge + reach)
	var step := 0.0
	while true:
		var t := minf(from + step, to)
		var at := t if forward else total - t
		tongue.points.append(passage.point_at(at))
		var fade := 1.0 - smoothstep(edge, to, t)
		tongue.half_widths.append(passage.half_width_at(at) * (0.25 + 0.7 * fade))
		if t >= to:
			break
		step += 20.0
	if tongue.points.size() >= 2:
		tongue.measure()
		_data.tongues.append(tongue)


func _start(rng: RandomNumberGenerator) -> void:
	var best := -1
	var best_north := INF
	for s in _data.skylights.size():
		var hall := _data.halls[_data.skylights[s].hall]
		var north := INF
		for exit in hall.exits:
			var passage := _data.passages[exit]
			var mouth := passage.point_at(passage.length() * (0.22 if passage.from == _data.skylights[s].hall else 0.78))
			var heading := hall.shape.center.direction_to(mouth)
			north = minf(north, heading.y)
		if north < best_north:
			best_north = north
			best = s
	var skylight := _data.skylights[maxi(best, 0)]
	_data.start_hall = skylight.hall
	var hall := _data.halls[skylight.hall]
	var spot := skylight.spot
	var options: Array[Vector2] = [spot.center + Vector2(0.0, spot.axes.y * 0.25), spot.center,
		hall.shape.center + Vector2(0.0, hall.shape.axes.y * 0.2), hall.shape.center]
	for option in options:
		if _data.wall_depth(option) < -90.0:
			_data.spawn_position = option
			return
	_data.spawn_position = hall.shape.center


# --- Reachability ------------------------------------------------------------------------

## The open floor on the reachability grid (where the player fits).
func _reach_base() -> void:
	_reach_size = Vector2i((_data.bounds.size / REACH_CELL).ceil())
	_open.resize(_reach_size.x * _reach_size.y)
	_blocked.resize(_open.size())
	_blocked.fill(0)
	_open_total = 0
	for y in _reach_size.y:
		for x in _reach_size.x:
			var center := _reach_center(x, y)
			var open := _data.wall_depth(center) < -BODY
			_open[y * _reach_size.x + x] = 1 if open else 0
			if open:
				_open_total += 1


func _reach_center(x: int, y: int) -> Vector2:
	return _data.bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * REACH_CELL


## Blocks the cells where `depth` (a Callable of a point) is above -4, within `box`; the
## result is a copy of the blocked cells with them added.
func _with_blocked(box: Rect2, depth: Callable) -> PackedByteArray:
	var blocked := _blocked.duplicate()
	var from := Vector2i(((box.position - _data.bounds.position) / REACH_CELL).floor()).max(Vector2i.ZERO)
	var to := Vector2i(((box.end - _data.bounds.position) / REACH_CELL).floor()).min(_reach_size - Vector2i.ONE)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			if float(depth.call(_reach_center(x, y))) > -4.0:
				blocked[y * _reach_size.x + x] = 1
	return blocked


## True when, with `blocked`, nearly all the open floor and every hall can be walked to
## from the start.
func _reachable(blocked: PackedByteArray) -> bool:
	var start := Vector2i(((_data.spawn_position - _data.bounds.position) / REACH_CELL).floor())
	var first := start.y * _reach_size.x + start.x
	if _open[first] == 0 or blocked[first] == 1:
		return false
	var seen := PackedByteArray()
	seen.resize(_open.size())
	seen[first] = 1
	var queue := PackedInt32Array([first])
	var total := 0
	var w := _reach_size.x
	while total < queue.size():
		var index := queue[total]
		total += 1
		var x := index % w
		var y := index / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= _reach_size.y:
					continue
				var next := ny * w + nx
				if seen[next] == 1 or _open[next] == 0 or blocked[next] == 1:
					continue
				if dx != 0 and dy != 0 and (_open[y * w + nx] == 0 or _open[ny * w + x] == 0):
					continue
				seen[next] = 1
				queue.append(next)
	var free := 0
	for index in _open.size():
		if _open[index] == 1 and blocked[index] == 0:
			free += 1
	if total < free * 0.97:
		return false
	for hall in _data.halls:
		var cell := Vector2i(((hall.shape.center - _data.bounds.position) / REACH_CELL).floor())
		var found := false
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				var c := cell + Vector2i(dx, dy)
				if c.x >= 0 and c.y >= 0 and c.x < w and c.y < _reach_size.y and seen[c.y * w + c.x] == 1:
					found = true
		if not found:
			return false
	return true


# --- Chasms and crevasses -----------------------------------------------------------------

## Chasms through dark or cold halls and across passages; each keeps the cave whole (an
## arch where it must), or is dropped.
func _chasms(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.chasms.x, _config.chasms.y)
	var options: Array = []
	for h in _data.halls.size():
		var hall := _data.halls[h]
		if (hall.zone == Zone.DARK or hall.zone == Zone.COLD) and h != _data.start_hall \
				and minf(hall.shape.axes.x, hall.shape.axes.y) > 250.0:
			options.append([0, h])
	for p in _data.passages.size():
		var passage := _data.passages[p]
		if passage.length() > 420.0 and not passage.icy and _data.halls[passage.to].is_main() \
				and passage.from != _data.start_hall and passage.to != _data.start_hall:
			options.append([1, p])
	for i in options.size():
		var j := rng.randi_range(i, options.size() - 1)
		var swap: Array = options[i]
		options[i] = options[j]
		options[j] = swap
	# A hall split by a chasm first (its tip on the floor is the narrow place), then any.
	var halls_first: Array = options.filter(func(option: Array) -> bool: return option[0] == 0)
	halls_first.append_array(options.filter(func(option: Array) -> bool: return option[0] != 0))
	options = halls_first
	var split := false
	for option: Array in options:
		if split and option[0] == 0 and _data.chasms.size() >= 1 and rng.randf() < 0.5:
			continue
		if _data.chasms.size() >= wanted:
			break
		var chasm := _hall_chasm(rng, option[1]) if option[0] == 0 else _passage_chasm(rng, option[1])
		if chasm == null:
			continue
		var box := _line_box(chasm)
		var depth := func(point: Vector2) -> float: return _chasm_depth_of(chasm, point, true)
		var blocked := _with_blocked(box, depth)
		if not _reachable(blocked):
			continue
		_blocked = blocked
		_data.chasms.append(chasm)
		_leaps(chasm)
		split = split or option[0] == 0


## The narrow places of a chasm on open floor: the middle of the longest stretch narrow
## enough to run over, and of one to fly over.
func _leaps(chasm: NelvarCaveData.Chasm) -> void:
	for limits: Vector2 in [Vector2(14.0, NelvarCaveData.LEAP_RUN), Vector2(44.0, NelvarCaveData.LEAP_FLY)]:
		var best := Vector2(-1.0, 0.0)
		var run_start := -1.0
		var along := 0.0
		while along <= chasm.length() + 6.0:
			var width := chasm.half_width_at(minf(along, chasm.length())) * 2.0
			var point := chasm.point_at(minf(along, chasm.length()))
			var normal := chasm.direction_at(minf(along, chasm.length())).orthogonal()
			var fits := width >= limits.x and width <= limits.y and along <= chasm.length() \
				and _data.wall_depth(point) < -90.0 and _data.wall_depth(point + normal * (width * 0.5 + 100.0)) < -40.0 \
				and _data.wall_depth(point - normal * (width * 0.5 + 100.0)) < -40.0
			for arch in chasm.arches:
				fits = fits and arch.distance(point) > arch.half_width + 90.0
			if fits and run_start < 0.0:
				run_start = along
			elif not fits and run_start >= 0.0:
				if along - run_start > best.y - best.x:
					best = Vector2(run_start, along)
				run_start = -1.0
			along += 6.0
		if best.x >= 0.0 and best.y - best.x >= 12.0:
			var middle := (best.x + best.y) * 0.5
			var at := chasm.point_at(middle)
			chasm.leaps.append(Vector3(at.x, at.y, chasm.half_width_at(middle) * 2.0))


## A broad chasm across a hall: one end runs into the ice, the other tapers out on the
## floor (narrow enough there to run or fly over); one or two arches over it.
func _hall_chasm(rng: RandomNumberGenerator, h: int) -> NelvarCaveData.Chasm:
	var shape := _data.halls[h].shape
	var direction := Vector2.from_angle(rng.randf() * TAU)
	var center := shape.center + Vector2.from_angle(rng.randf() * TAU) * minf(shape.axes.x, shape.axes.y) * rng.randf_range(0.0, 0.15)
	var half := shape.reach() * rng.randf_range(0.95, 1.15)
	var short := minf(shape.axes.x, shape.axes.y) * rng.randf_range(0.45, 0.62)
	var chasm := _chasm_line(rng, center, direction, half, rng.randf_range(58.0, 125.0), 0.16, short)
	if not _chasm_fits(chasm):
		return null
	var total := chasm.length()
	var spots: Array[float] = [0.5, 0.36, 0.64, 0.44, 0.56, 0.3, 0.7]
	for spot in spots:
		if chasm.arches.size() >= (2 if total > 900.0 and rng.randf() < 0.6 else 1):
			break
		var along := total * spot
		var clash := false
		for arch in chasm.arches:
			if absf(chasm.lengths[0] + along - _arch_along(chasm, arch)) < 260.0:
				clash = true
		if not clash:
			_try_arch(rng, chasm, along)
	return chasm if not chasm.arches.is_empty() else null


## A chasm across a passage; an arch carries the way over it, or (where the cave has
## another way round) the gap is narrow enough to run or fly over.
func _passage_chasm(rng: RandomNumberGenerator, p: int) -> NelvarCaveData.Chasm:
	var passage := _data.passages[p]
	var total := passage.length()
	var along := total * rng.randf_range(0.36, 0.64)
	var center := passage.point_at(along)
	if _data.halls[passage.from].shape.signed_distance(center) > -120.0 \
			or _data.halls[passage.to].shape.signed_distance(center) > -120.0:
		return null
	var forward := passage.direction_at(along)
	var across := forward.orthogonal()
	var half := passage.half_width_at(along) + rng.randf_range(110.0, 170.0)
	var bridged := rng.randf() < 0.65
	var width := rng.randf_range(50.0, 100.0) if bridged else rng.randf_range(18.0, 46.0)
	var chasm := _chasm_line(rng, center, across, half, width, 0.0)
	if not _chasm_fits(chasm):
		return null
	if bridged:
		var reach := chasm.half_width_at(chasm.length() * 0.5) * 1.08 + 30.0
		var arch := NelvarCaveData.Arch.new()
		arch.a = center - forward * reach
		arch.b = center + forward * reach
		arch.half_width = minf(rng.randf_range(_config.arch_half_width.x, _config.arch_half_width.y),
			passage.half_width_at(along) - 6.0)
		if arch.half_width < _config.arch_half_width.x * 0.9 or arch.length() > 300.0:
			return null
		chasm.arches.append(arch)
	return chasm


## A chasm's centre line through `center` along `direction`, `half` back and `ahead`
## forward (`half` when negative), its half width `width` in the middle, wandering,
## tapering to a point at both ends.
func _chasm_line(rng: RandomNumberGenerator, center: Vector2, direction: Vector2, half: float, width: float,
		bend_share: float, ahead: float = -1.0) -> NelvarCaveData.Chasm:
	if ahead < 0.0:
		ahead = half
	var chasm := NelvarCaveData.Chasm.new()
	var normal := direction.orthogonal()
	var count := maxi(8, int((half + ahead) / 24.0))
	var waves := rng.randf_range(0.6, 1.6)
	var phase := rng.randf() * TAU
	var salt := rng.randi() & 0xffff
	for i in count + 1:
		var t := float(i) / count
		var offset := sin(phase + t * PI * waves) * half * bend_share \
			+ (NelvarPixelArt.value_noise(t * 9.0, 2.5, salt) - 0.5) * width * 0.35 * sin(PI * t)
		chasm.points.append(center + direction * lerpf(-half, ahead, t) + normal * offset)
	chasm.measure()
	var total := chasm.length()
	chasm.half_widths.resize(chasm.points.size())
	for i in chasm.points.size():
		var t := chasm.lengths[i] / total
		# Broken edges: slow swells and short bites out of the rim.
		var wander := NelvarPixelArt.value_noise(chasm.lengths[i] * 0.008, 0.5, salt) * 0.7 \
			+ NelvarPixelArt.value_noise(chasm.lengths[i] * 0.04, 4.5, salt) * 0.3
		var taper := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.62, 1.0, t))
		chasm.half_widths[i] = maxf(4.0, width * (0.66 + 0.68 * wander) * lerpf(0.04, 1.0, taper))
	return chasm


## A chasm keeps off the other chasms and the start.
func _chasm_fits(chasm: NelvarCaveData.Chasm) -> bool:
	for i in chasm.points.size():
		var point := chasm.points[i]
		var half := chasm.half_widths[i]
		if point.distance_to(_data.spawn_position) < half + 320.0:
			return false
		for other in _data.chasms:
			if NelvarFireData.polyline_distance(other.points, point) < half + other.widest() + 120.0:
				return false
	return true


## An arch across the chasm at `along`, if both its ends land on the floor.
func _try_arch(rng: RandomNumberGenerator, chasm: NelvarCaveData.Chasm, along: float) -> bool:
	var center := chasm.point_at(along)
	var across := chasm.direction_at(along).orthogonal()
	var reach := chasm.half_width_at(along) * 1.12 + 34.0
	var arch := NelvarCaveData.Arch.new()
	arch.a = center - across * reach
	arch.b = center + across * reach
	arch.half_width = rng.randf_range(_config.arch_half_width.x, _config.arch_half_width.y)
	if arch.length() > 300.0 or _data.wall_depth(center) > -arch.half_width:
		return false
	for end in [arch.a, arch.b]:
		if _data.wall_depth(end) > -(arch.half_width + 14.0):
			return false
		if _chasm_depth_of(chasm, end + (end - center).normalized() * 10.0, false) > -8.0:
			return false
	chasm.arches.append(arch)
	return true


func _arch_along(chasm: NelvarCaveData.Chasm, arch: NelvarCaveData.Arch) -> float:
	var middle := (arch.a + arch.b) * 0.5
	var best := INF
	var along := 0.0
	for i in chasm.points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(middle, chasm.points[i], chasm.points[i + 1])
		if closest.distance_to(middle) < best:
			best = closest.distance_to(middle)
			along = chasm.lengths[i] + chasm.points[i].distance_to(closest)
	return along


## Depth into this one chasm (with its arches unless `raw`).
func _chasm_depth_of(chasm: NelvarCaveData.Chasm, point: Vector2, with_arches: bool) -> float:
	var near := _nearest_on(chasm, point)
	var depth := chasm.raw_depth(near.x, near.y)
	if with_arches:
		for arch in chasm.arches:
			depth = minf(depth, arch.distance(point) - arch.half_width)
	return depth


## Distance to a centre line and the running length at its closest point.
func _nearest_on(line: NelvarIceData.Crevasse, point: Vector2) -> Vector2:
	var best := Vector2(INF, 0.0)
	for i in line.points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(point, line.points[i], line.points[i + 1])
		var distance := point.distance_to(closest)
		if distance < best.x:
			best = Vector2(distance, line.lengths[i] + line.points[i].distance_to(closest))
	return best


func _line_box(line: NelvarIceData.Crevasse) -> Rect2:
	var low := line.points[0]
	var high := line.points[0]
	for point in line.points:
		low = low.min(point)
		high = high.max(point)
	var reach := line.widest() + REACH_CELL * 2.0 + 40.0
	if line is NelvarCaveData.Chasm:
		for arch in (line as NelvarCaveData.Chasm).arches:
			low = low.min(arch.a.min(arch.b))
			high = high.max(arch.a.max(arch.b))
	return Rect2(low - Vector2.ONE * reach, high - low + Vector2.ONE * reach * 2.0)


## Short crevasses in the floor of the halls, a snow bridge over each.
func _crevasses(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.crevasses.x, _config.crevasses.y)
	for attempt in 80:
		if _data.crevasses.size() >= wanted:
			break
		var h := rng.randi_range(0, _data.halls.size() - 1)
		var hall := _data.halls[h]
		if not hall.is_main() or h == _data.start_hall:
			continue
		var center := hall.shape.point_at(rng.randf() * TAU, 0.0).lerp(hall.shape.center, 1.0 - rng.randf_range(0.1, 0.7))
		if _data.wall_depth(center) > -80.0:
			continue
		var direction := Vector2.from_angle(rng.randf() * TAU)
		var half := rng.randf_range(110.0, 240.0)
		var crevasse := NelvarIceData.Crevasse.new()
		var normal := direction.orthogonal()
		var phase := rng.randf() * TAU
		var count := maxi(5, int(half * 2.0 / 30.0))
		for i in count + 1:
			var t := float(i) / count
			crevasse.points.append(center + direction * lerpf(-half, half, t) + normal * sin(phase + t * 4.0) * half * 0.08)
		crevasse.measure()
		var total := crevasse.length()
		var base := rng.randf_range(_config.crevasse_half_width.x, _config.crevasse_half_width.y)
		var salt := rng.randi() & 0xffff
		crevasse.half_widths.resize(crevasse.points.size())
		for i in crevasse.points.size():
			var t := crevasse.lengths[i] / total
			var wander := NelvarPixelArt.value_noise(crevasse.lengths[i] * 0.01, 0.5, salt)
			var taper := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, t))
			crevasse.half_widths[i] = clampf(base * (0.7 + 0.6 * wander), _config.crevasse_half_width.x,
				_config.crevasse_half_width.y) * lerpf(0.3, 1.0, taper)
		var clear := true
		for i in crevasse.points.size():
			var point := crevasse.points[i]
			if point.distance_to(_data.spawn_position) < 300.0:
				clear = false
			for chasm in _data.chasms:
				if _chasm_depth_of(chasm, point, false) > -(crevasse.half_widths[i] + 90.0):
					clear = false
			for other in _data.crevasses:
				if NelvarFireData.polyline_distance(other.points, point) < other.widest() + 150.0:
					clear = false
		if not clear:
			continue
		var bridge := NelvarIceData.Bridge.new()
		bridge.along = total * rng.randf_range(0.4, 0.6)
		bridge.center = crevasse.point_at(bridge.along)
		bridge.direction = crevasse.direction_at(bridge.along)
		bridge.half_length = _config.bridge_half_length
		if _data.wall_depth(bridge.center) > -60.0:
			continue
		crevasse.bridges.append(bridge)
		var depth := func(point: Vector2) -> float:
			var near := _nearest_on(crevasse, point)
			return crevasse.depth_at(near.x, near.y)
		var blocked := _with_blocked(_line_box(crevasse), depth)
		if not _reachable(blocked):
			continue
		_blocked = blocked
		_data.crevasses.append(crevasse)


# --- Geysers and lakes -------------------------------------------------------------------

## Geysers in the cold halls: apart, away from the ways in, the chasms and the cracks.
func _geysers(rng: RandomNumberGenerator) -> void:
	for h in _data.halls.size():
		var hall := _data.halls[h]
		if hall.zone != Zone.COLD:
			continue
		var wanted := rng.randi_range(_config.geysers_per_hall.x, _config.geysers_per_hall.y)
		var placed := 0
		for attempt in 60:
			if placed >= wanted:
				break
			var point := hall.shape.point_at(rng.randf() * TAU, 0.0).lerp(hall.shape.center, 1.0 - rng.randf_range(0.0, 0.7))
			if _data.wall_depth(point) > -120.0:
				continue
			if not _clear_of_hazards(point, 120.0):
				continue
			var free := true
			for mouth in _mouths(h):
				if point.distance_to(mouth) < 240.0:
					free = false
			for other in _data.geysers:
				if other.position.distance_to(point) < _config.geyser_spacing:
					free = false
			if not free or point.distance_to(_data.spawn_position) < 400.0:
				continue
			var geyser := NelvarCaveData.Geyser.new()
			geyser.position = point
			geyser.hall = h
			geyser.radius = rng.randf_range(_config.geyser_warmth.x, _config.geyser_warmth.y)
			geyser.mouth = rng.randf_range(22.0, 30.0)
			geyser.period = rng.randf_range(_config.geyser_period.x, _config.geyser_period.y)
			geyser.offset = rng.randf() * geyser.period
			_data.geysers.append(geyser)
			placed += 1


## Where the passages leave hall `h`: the points of their centre lines on its outline.
func _mouths(h: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var shape := _data.halls[h].shape
	for exit in _data.halls[h].exits:
		var passage := _data.passages[exit]
		var total := passage.length()
		var along := 0.0
		while along <= total:
			var at := along if passage.from == h else total - along
			var point := passage.point_at(at)
			if shape.signed_distance(point) < 0.0:
				result.append(point)
				break
			along += 10.0
	return result


## Clear of the chasms and the crevasses by `gap`.
func _clear_of_hazards(point: Vector2, gap: float) -> bool:
	for chasm in _data.chasms:
		if _chasm_depth_of(chasm, point, false) > -gap:
			return false
	for crevasse in _data.crevasses:
		var near := _nearest_on(crevasse, point)
		if crevasse.raw_depth(near.x, near.y) > -gap:
			return false
	return true


## Open water by the geysers and in the grottos, melting lakes by the geysers and under
## the sun, frozen lakes (most in the cold halls). Melting ice and open water never cut
## anything off.
func _lakes(rng: RandomNumberGenerator) -> void:
	var opens := rng.randi_range(_config.open_lakes.x, _config.open_lakes.y)
	var melts := rng.randi_range(_config.melt_lakes.x, _config.melt_lakes.y)
	var frozen := rng.randi_range(_config.frozen_lakes.x, _config.frozen_lakes.y)
	var placed := 0
	for attempt in 120:
		if placed >= opens:
			break
		var radius := rng.randf_range(_config.open_radius.x, _config.open_radius.y)
		var center := Vector2.INF
		if attempt % 2 == 0 and not _data.geysers.is_empty():
			var geyser := _data.geysers[rng.randi_range(0, _data.geysers.size() - 1)]
			center = geyser.position + Vector2.from_angle(rng.randf() * TAU) * (geyser.mouth + radius + rng.randf_range(50.0, 110.0))
		else:
			var grottos: Array[NelvarCaveData.Hall] = []
			for hall in _data.halls:
				if hall.zone == Zone.GROTTO:
					grottos.append(hall)
			if grottos.is_empty():
				continue
			var grotto := grottos[rng.randi_range(0, grottos.size() - 1)]
			radius = minf(radius, minf(grotto.shape.axes.x, grotto.shape.axes.y) * 0.55)
			center = grotto.shape.center + Vector2.from_angle(rng.randf() * TAU) * radius * 0.2
		if _try_lake(rng, Pool.OPEN, center, radius):
			placed += 1
	placed = 0
	for attempt in 120:
		if placed >= melts:
			break
		var radius := rng.randf_range(_config.melt_radius.x, _config.melt_radius.y)
		var center := Vector2.INF
		var round_shape := true
		if attempt % 2 == 0 and not _data.geysers.is_empty():
			var geyser := _data.geysers[rng.randi_range(0, _data.geysers.size() - 1)]
			center = geyser.position + Vector2.from_angle(rng.randf() * TAU) * (geyser.mouth + radius + rng.randf_range(60.0, 140.0))
		else:
			var skylight := _data.skylights[rng.randi_range(0, _data.skylights.size() - 1)]
			if skylight.hall == _data.start_hall:
				continue
			center = skylight.spot.center + Vector2.from_angle(rng.randf() * TAU) * skylight.spot.axes.y * rng.randf_range(0.0, 0.5)
		if _try_lake(rng, Pool.MELT, center, radius, round_shape):
			placed += 1
	placed = 0
	for attempt in 200:
		if placed >= frozen:
			break
		var h := rng.randi_range(0, _data.halls.size() - 1)
		var hall := _data.halls[h]
		if hall.zone == Zone.GROTTO or h == _data.start_hall or (hall.zone != Zone.COLD and rng.randf() < 0.45):
			continue
		var shrink := 1.0 - 0.5 * float(attempt) / 200.0
		var radius := lerpf(_config.frozen_radius.x, _config.frozen_radius.y, rng.randf() * shrink)
		radius = minf(radius, minf(hall.shape.axes.x, hall.shape.axes.y) * 0.62)
		var center := hall.shape.center + Vector2.from_angle(rng.randf() * TAU) \
			* (minf(hall.shape.axes.x, hall.shape.axes.y) - radius) * rng.randf_range(0.0, 0.6)
		if _try_lake(rng, Pool.FROZEN, center, radius):
			placed += 1


## `round_shape`: nearly as wide every way (melting lakes: too wide to walk across
## anywhere, narrow enough to run).
func _try_lake(rng: RandomNumberGenerator, kind: Pool, center: Vector2, radius: float, round_shape: bool = false) -> bool:
	if not center.is_finite() or radius < 70.0:
		return false
	var lake := NelvarIceData.Lake.new()
	var squash := rng.randf_range(0.88, 0.96) if round_shape else rng.randf_range(0.66, 0.85)
	lake.shape = radial(center, Vector2(radius, radius * squash), rng, 0.05 if round_shape else 0.1, 0.08 if round_shape else 0.17)
	var polygon := lake.shape.polygon(48)
	for point in polygon:
		if _data.wall_depth(point) > -(36.0 if kind != Pool.FROZEN else 46.0):
			return false
		if not _clear_of_hazards(point, 70.0):
			return false
		if point.distance_to(_data.spawn_position) < 160.0:
			return false
	if lake.shape.signed_distance(_data.spawn_position) > -200.0:
		return false
	for other in _data.lakes:
		if center.distance_to(other.shape.center) < lake.shape.reach() + other.shape.reach() + 90.0:
			return false
	for geyser in _data.geysers:
		var gap := center.distance_to(geyser.position) - lake.shape.reach()
		if gap < geyser.mouth + 40.0:
			return false
		# Frozen lakes stay out of the warmth.
		if kind == Pool.FROZEN and gap < geyser.radius * 0.8:
			return false
	if kind != Pool.FROZEN:
		var reach := lake.shape.reach() + 30.0
		var depth := func(point: Vector2) -> float: return lake.shape.signed_distance(point)
		var blocked := _with_blocked(Rect2(center - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), depth)
		if not _reachable(blocked):
			return false
		_blocked = blocked
	_data.lakes.append(lake)
	_data.lake_polygons.append(lake.shape.polygon(72))
	_data.pools.append(kind)
	_data.rims.append(rng.randf_range(_config.open_rim.x, _config.open_rim.y) if kind == Pool.OPEN else 0.0)
	return true


## Patches of thin ice inside the frozen lakes, never touching the shore.
func _thin_ice(rng: RandomNumberGenerator) -> void:
	for l in _data.lakes.size():
		if _data.pools[l] != Pool.FROZEN:
			continue
		var lake := _data.lakes[l]
		var wanted := rng.randi_range(_config.thin_patches.x, _config.thin_patches.y)
		for attempt in 60:
			if lake.thin.size() >= wanted:
				break
			var radius := minf(rng.randf_range(_config.thin_radius.x, _config.thin_radius.y), lake.shape.axes.y * 0.5)
			var patch := radial(lake.shape.center + Vector2.from_angle(rng.randf() * TAU) * lake.shape.axes
				* sqrt(rng.randf()) * 0.62, Vector2(radius, radius * rng.randf_range(0.6, 0.85)), rng, 0.16, 0.26)
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


# --- Creatures ------------------------------------------------------------------------------

## Frozen hard under the frozen lakes (some watch), drifting slowly under the melting
## ones; in the walls, seen through the ice from the passages (some watch as the player
## goes by), and a giant or two running through the ice from one passage to another.
func _creatures(rng: RandomNumberGenerator) -> void:
	for l in _data.lakes.size():
		if _data.pools[l] == Pool.OPEN:
			continue
		var lake := _data.lakes[l]
		var melting := _data.pools[l] == Pool.MELT
		var wanted := rng.randi_range(_config.frozen_per_lake.x, _config.frozen_per_lake.y)
		var placed := 0
		for attempt in 50:
			if placed >= wanted:
				break
			var radius := minf(rng.randf_range(32.0, 76.0), lake.shape.axes.y * 0.42)
			var point := lake.shape.center + Vector2.from_angle(rng.randf() * TAU) * lake.shape.axes * sqrt(rng.randf()) * 0.6
			var loop := rng.randf_range(16.0, 34.0) if melting else 0.0
			if lake.shape.signed_distance(point) < radius + loop + 20.0:
				continue
			var apart := true
			for other in _data.frozen:
				if other.lake == l and other.position.distance_to(point) < other.radius + radius + loop + other.drift.x + 30.0:
					apart = false
			if not apart:
				continue
			var creature := _creature(rng, l, point, radius)
			creature.eye = not melting and rng.randf() < _config.watching_share
			if melting:
				creature.drift = Vector3(loop, rng.randf_range(40.0, 70.0), rng.randf() * TAU)
			placed += 1
	var watching := false
	for creature in _data.frozen:
		watching = watching or creature.eye
	if not watching and not _data.frozen.is_empty():
		for creature in _data.frozen:
			if creature.drift.x <= 0.0:
				creature.eye = true
				break
	_wall_creatures(rng)


func _creature(rng: RandomNumberGenerator, anchor: int, point: Vector2, radius: float) -> NelvarIceData.Frozen:
	var creature := NelvarIceData.Frozen.new()
	creature.lake = anchor
	creature.position = point
	creature.radius = radius
	creature.variant = rng.randi_range(0, NelvarIceData.Creature.size() - 1)
	creature.appearance_seed = rng.randi()
	creature.facing_left = rng.randf() < 0.5
	_data.frozen.append(creature)
	return creature


func _wall_creatures(rng: RandomNumberGenerator) -> void:
	var anchor_base := _data.lakes.size()
	var wanted := rng.randi_range(_config.wall_creatures.x, _config.wall_creatures.y)
	var placed: Array[NelvarIceData.Frozen] = []
	for attempt in wanted * 30:
		if placed.size() >= wanted:
			break
		var radius := rng.randf_range(34.0, 78.0)
		var point := _beside_floor(rng, rng.randf_range(maxf(40.0, radius * 0.55), 210.0))
		if not point.is_finite():
			continue
		var depth := _data.wall_depth(point)
		if depth < maxf(36.0, radius * 0.5) or depth > 230.0:
			continue
		var apart := true
		for other in placed:
			if other.position.distance_to(point) < other.radius + radius + 50.0:
				apart = false
		if not apart:
			continue
		var creature := _creature(rng, anchor_base + _data.wall_anchors.size(), point, radius)
		_data.wall_anchors.append(point)
		creature.eye = rng.randf() < _config.wall_watching_share
		creature.reach = maxf(0.0, depth - radius) + 30.0
		placed.append(creature)
	# Giants: long serpents through the ice between two passages, seen in parts.
	var giants := rng.randi_range(_config.giants.x, _config.giants.y)
	var made := 0
	for attempt in 300:
		if made >= giants:
			break
		var radius := rng.randf_range(100.0, 160.0)
		var point := _beside_floor(rng, rng.randf_range(50.0, 130.0))
		if not point.is_finite():
			continue
		var depth := _data.wall_depth(point)
		if depth < 45.0 or depth > 150.0:
			continue
		var through := false
		for k in 8:
			var direction := Vector2.from_angle(TAU * k / 8.0)
			if _data.wall_depth(point + direction * radius * 0.95) < -10.0 \
					and _data.wall_depth(point - direction * radius * 0.95) < -10.0:
				through = true
				break
		if not through:
			continue
		var apart := true
		for other in placed:
			if other.position.distance_to(point) < other.radius + radius + 30.0:
				apart = false
		if not apart:
			continue
		var giant := _creature(rng, anchor_base + _data.wall_anchors.size(), point, radius)
		_data.wall_anchors.append(point)
		giant.variant = NelvarIceData.Creature.SERPENT
		giant.eye = true
		giant.reach = 40.0
		placed.append(giant)
		made += 1


## A point `depth` into the ice beside a passage or a hall (INF if it missed).
func _beside_floor(rng: RandomNumberGenerator, depth: float) -> Vector2:
	if rng.randf() < 0.65 and not _data.passages.is_empty():
		var passage := _data.passages[rng.randi_range(0, _data.passages.size() - 1)]
		var along := passage.length() * rng.randf_range(0.1, 0.9)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var normal := passage.direction_at(along).orthogonal() * side
		return passage.point_at(along) + normal * (passage.half_width_at(along) + depth)
	var hall := _data.halls[rng.randi_range(0, _data.halls.size() - 1)]
	return hall.shape.point_at(rng.randf() * TAU, -depth)


## Bodies floating on the open water, drifting round small loops.
func _floaters(rng: RandomNumberGenerator) -> void:
	for l in _data.lakes.size():
		if _data.pools[l] != Pool.OPEN:
			continue
		var shape := _data.lakes[l].shape
		var water := minf(shape.axes.x, shape.axes.y) - _data.rims[l]
		var wanted := rng.randi_range(_config.floaters.x, _config.floaters.y)
		var made := 0
		for attempt in 40:
			if made >= wanted:
				break
			var radius := minf(rng.randf_range(26.0, 44.0), water * 0.5)
			var loop := rng.randf_range(8.0, 26.0)
			var point := shape.center + Vector2.from_angle(rng.randf() * TAU) * water * sqrt(rng.randf()) * 0.6
			if shape.signed_distance(point) < _data.rims[l] + radius + loop + 8.0:
				continue
			var apart := true
			for other in _data.floaters:
				if other.position.distance_to(point) < other.radius + radius + other.drift.x + loop + 10.0:
					apart = false
			if not apart:
				continue
			var floater := NelvarCaveData.Floater.new()
			floater.lake = l
			# On the art pixels: its sprite turns round its origin.
			floater.position = (point / PIXEL).round() * PIXEL
			floater.radius = radius
			floater.variant = rng.randi_range(0, NelvarIceData.Creature.size() - 1)
			floater.appearance_seed = rng.randi()
			floater.facing_left = rng.randf() < 0.5
			floater.sunk = rng.randf() < 0.5
			floater.drift = Vector3(loop, rng.randf_range(50.0, 110.0), rng.randf() * TAU)
			_data.floaters.append(floater)
			made += 1


# --- Placement rules -------------------------------------------------------------------------

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


## Shared rules for anything standing in the cave: on the floor (`wall_gap` from the ice),
## off the drops, the water and (unless `on_ice`) the lakes; solid things keep off the
## passages' ways, the halls' middles, the start and the geysers' mouths, and keep a
## passage between each other.
func _fits(point: Vector2, radius: float, solid: bool, wall_gap: float = 4.0, on_ice: bool = false) -> bool:
	if _data.wall_depth(point) > -(radius * (0.6 if solid else 0.8) + wall_gap):
		return false
	if not _clear_of_hazards(point, radius + 24.0):
		return false
	if on_ice:
		if _data.lake_depth(point) < radius + 30.0 or _data.thin_depth(point) > -(radius + 30.0):
			return false
		var lake := _data.lake_at(point)
		if lake < 0 or _data.pools[lake] != Pool.FROZEN:
			return false
	elif _data.lake_depth(point) > -(radius + 14.0):
		return false
	for geyser in _data.geysers:
		if point.distance_to(geyser.position) < geyser.mouth + radius + (40.0 if solid else 10.0):
			return false
	var near := _data.passage_near(point)
	if solid:
		if point.distance_to(_data.spawn_position) < 180.0 + radius:
			return false
		if near.x >= 0 and near.y < _data.passages[int(near.x)].half_width_at(near.z) + radius + 4.0:
			return false
		for hall in _data.halls:
			if hall.is_main() and point.distance_to(hall.shape.center) < hall.arena() + radius:
				return false
		for chasm in _data.chasms:
			for arch in chasm.arches:
				if minf(point.distance_to(arch.a), point.distance_to(arch.b)) < radius + arch.half_width + 50.0:
					return false
			for leap in chasm.leaps:
				if point.distance_to(Vector2(leap.x, leap.y)) < radius + 130.0:
					return false
		for crevasse in _data.crevasses:
			for bridge in crevasse.bridges:
				if point.distance_to(bridge.center) < radius + bridge.half_length + 50.0:
					return false
	elif point.distance_to(_data.spawn_position) < 50.0 + radius:
		return false
	for other: NelvarIceData.Thing in _nearby(point, 260.0):
		var distance := point.distance_to(other.position)
		if other.solid and solid:
			var gap := _config.passage_width
			if other.is_tree() and radius > 0.0:
				gap = maxf(gap, 92.0 - other.radius - radius)
			if distance < radius + other.spread() + gap:
				return false
		elif other.solid or solid:
			if distance < (radius + other.spread()) * 0.85:
				return false
		elif distance < (radius + other.radius) * 0.8:
			return false
		if other.crown_hides(point, radius * 0.3):
			return false
	return true


## A random point of the floor: in a hall (at `edge` 0..1 of the way out from its middle,
## or anywhere when negative) or along a passage (next to a wall when `edge` > 0.6).
func _floor_point(rng: RandomNumberGenerator, edge: float, halls_only: bool = false) -> Vector2:
	if halls_only or rng.randf() < 0.68:
		var hall := _data.halls[rng.randi_range(0, _data.halls.size() - 1)]
		var reach := sqrt(rng.randf()) if edge < 0.0 else clampf(edge + rng.randf_range(-0.12, 0.12), 0.0, 1.05)
		return hall.shape.point_at(rng.randf() * TAU, 0.0).lerp(hall.shape.center, 1.0 - reach)
	var passage := _data.passages[rng.randi_range(0, _data.passages.size() - 1)]
	var along := passage.length() * rng.randf()
	var across := rng.randf_range(-1.0, 1.0) if edge < 0.6 else (rng.randf_range(0.7, 1.1) * (-1.0 if rng.randf() < 0.5 else 1.0))
	if not passage.niches.is_empty() and rng.randf() < 0.4:
		var niche := passage.niches[rng.randi_range(0, passage.niches.size() - 1)]
		return niche.center + Vector2.from_angle(rng.randf() * TAU) * niche.axes.y * rng.randf_range(0.0, 0.6)
	return passage.point_at(along) + passage.direction_at(along).orthogonal() * passage.half_width_at(along) * across


func _thing(kind: Kind, point: Vector2, radius: float, solid: bool, rng: RandomNumberGenerator) -> NelvarIceData.Thing:
	var thing := NelvarIceData.Thing.new()
	thing.kind = kind
	thing.position = point
	thing.radius = radius
	thing.solid = solid
	thing.appearance_seed = rng.randi()
	return thing


# --- Things -----------------------------------------------------------------------------------

func _things(rng: RandomNumberGenerator) -> void:
	for geyser in _data.geysers:
		var vent := _thing(Kind.VENT, geyser.position, geyser.mouth, true, rng)
		_add(vent)
	_statues(rng)
	_sunny_things(rng)
	_crystals(rng)
	_stones(rng)
	_stalagmites(rng)
	_ice_blocks(rng)
	_bones(rng)


## Petrified creatures in the grottos.
func _statues(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.statues.x, _config.statues.y)
	var placed := 0
	for hall in _data.halls:
		if placed >= wanted or hall.zone != Zone.GROTTO:
			continue
		for attempt in 20:
			var radius := rng.randf_range(28.0, 36.0)
			var point := hall.shape.center + Vector2.from_angle(rng.randf() * TAU) * minf(hall.shape.axes.x, hall.shape.axes.y) * rng.randf_range(0.2, 0.5)
			var statue := _thing(Kind.STATUE, point, radius, true, rng)
			statue.accent = rng.randf() < 0.5
			if _fits(point, statue.spread(), true, 10.0):
				_add(statue)
				placed += 1
				break


## Pines on the snow of the sunny halls (off the middle), a dead tree now and then, drifts
## along the walls and in the ways out, dry grass and a few bare shrubs.
func _sunny_things(rng: RandomNumberGenerator) -> void:
	for skylight in _data.skylights:
		var hall := _data.halls[skylight.hall]
		var wanted := rng.randi_range(_config.pines_per_hall.x, _config.pines_per_hall.y)
		var grown := 0
		for attempt in 80:
			if grown >= wanted:
				break
			var point := hall.shape.point_at(rng.randf() * TAU, 0.0).lerp(hall.shape.center, 1.0 - rng.randf_range(0.45, 0.85))
			if _data.snow_depth(point) < 30.0:
				continue
			var pine := _tree(rng, Kind.PINE, point)
			if pine != null:
				pine.accent = rng.randf() < 0.5
				grown += 1
		if rng.randf() < 0.55:
			for attempt in 30:
				var point := hall.shape.point_at(rng.randf() * TAU, 0.0).lerp(hall.shape.center, 1.0 - rng.randf_range(0.4, 0.85))
				if _data.snow_depth(point) > 20.0 and _tree(rng, Kind.DEAD_TREE, point) != null:
					break
		for i in rng.randi_range(2, 4):
			for attempt in 20:
				var radius := rng.randf_range(30.0, 54.0)
				var point := hall.shape.point_at(rng.randf() * TAU, radius * 0.6 + 6.0)
				if _data.snow_depth(point) < 10.0:
					continue
				var drift := _thing(Kind.DRIFT, point, radius, true, rng)
				drift.variant = rng.randi_range(0, 2)
				drift.accent = rng.randf() < 0.5
				if _fits(point, drift.spread(), true, 0.0):
					_add(drift)
					break
		_scatter_on_snow(rng, hall, Kind.DRY_GRASS, rng.randi_range(3, 6), Vector2(10.0, 18.0), 3)
		_scatter_on_snow(rng, hall, Kind.SHRUB, rng.randi_range(1, 3), Vector2(16.0, 24.0), 2)


func _tree(rng: RandomNumberGenerator, kind: Kind, point: Vector2) -> NelvarIceData.Thing:
	var pine := kind == Kind.PINE
	var trunk := PINE_TRUNK if pine else DEAD_TRUNK
	var crown := PINE_CROWN if pine else DEAD_CROWN
	var height := PINE_HEIGHT if pine else DEAD_HEIGHT
	var scale := rng.randf()
	var tree := _thing(kind, point, lerpf(trunk.x, trunk.y, scale), true, rng)
	tree.size = Vector2(lerpf(crown.x, crown.y, scale * 0.7 + rng.randf() * 0.3),
		lerpf(height.x, height.y, scale * 0.6 + rng.randf() * 0.4))
	tree.variant = rng.randi_range(0, 2)
	if not _fits(point, tree.radius, true, tree.size.x * 0.4):
		return null
	# A crown never reaches into the wall above.
	if _data.wall_depth(tree.crown_center()) > -tree.size.x * 0.5:
		return null
	for other: NelvarIceData.Thing in _nearby(point, 300.0):
		if other.kind != Kind.PINE and tree.crown_hides(other.position):
			return null
	_add(tree)
	return tree


func _scatter_on_snow(rng: RandomNumberGenerator, hall: NelvarCaveData.Hall, kind: Kind, count: int,
		radii: Vector2, variants: int) -> void:
	var placed := 0
	for attempt in count * 12:
		if placed >= count:
			break
		var point := hall.shape.point_at(rng.randf() * TAU, 0.0).lerp(hall.shape.center, 1.0 - sqrt(rng.randf()))
		var radius := rng.randf_range(radii.x, radii.y)
		if _data.snow_depth(point) < radius or not _fits(point, radius, false):
			continue
		var plant := _thing(kind, point, radius, false, rng)
		plant.variant = rng.randi_range(0, variants - 1)
		plant.accent = rng.randf() < (0.3 if kind == Kind.SHRUB else 0.5)
		_add(plant)
		placed += 1


## Crystals of every size and look, thickest along the walls and in the grottos; some
## glow and light the dark.
func _crystals(rng: RandomNumberGenerator) -> void:
	var sizes: Array[Array] = [
		[rng.randi_range(_config.large_crystals.x, _config.large_crystals.y), Vector2(28.0, 40.0),
			[Crystal.COLUMN, Crystal.CLUSTER, Crystal.FAN]],
		[rng.randi_range(_config.medium_crystals.x, _config.medium_crystals.y), Vector2(14.0, 24.0),
			[Crystal.CLUSTER, Crystal.COLUMN, Crystal.FAN, Crystal.SLAB, Crystal.SHARD]],
		[rng.randi_range(_config.small_crystals.x, _config.small_crystals.y), Vector2(6.0, 12.0),
			[Crystal.SHARD, Crystal.CLUSTER, Crystal.SLAB, Crystal.SHARD]],
	]
	# The grottos first: druses.
	for hall in _data.halls:
		if hall.zone != Zone.GROTTO:
			continue
		for k in rng.randi_range(5, 9):
			var size_index := 2 if k > 2 else (1 if k > 0 else rng.randi_range(0, 1))
			var spec: Array = sizes[size_index]
			var point := hall.shape.point_at(rng.randf() * TAU, 0.0).lerp(hall.shape.center, 1.0 - rng.randf_range(0.6, 0.95))
			if _crystal(rng, point, spec[1], spec[2], 1.6):
				spec[0] = maxi(0, int(spec[0]) - 1)
	for spec: Array in sizes:
		var placed := 0
		for attempt in int(spec[0]) * 16:
			if placed >= int(spec[0]):
				break
			var near_wall := rng.randf() < 0.75
			var point := _floor_point(rng, 0.92 if near_wall else -1.0)
			if near_wall and _data.wall_depth(point) < -70.0:
				continue
			if _crystal(rng, point, spec[1], spec[2], 1.0):
				placed += 1


func _crystal(rng: RandomNumberGenerator, point: Vector2, radii: Vector2, looks: Array, glow_boost: float) -> bool:
	var radius := rng.randf_range(radii.x, radii.y)
	var solid := radius >= 14.0
	if not _fits(point, radius, solid, 0.0):
		return false
	var crystal := _thing(Kind.CRYSTAL, point, radius, solid, rng)
	crystal.variant = looks[rng.randi_range(0, looks.size() - 1)]
	var roll := rng.randf()
	crystal.size = Vector2(NelvarCaveData.Tint.VIOLET if roll < 0.08 else (NelvarCaveData.Tint.DEEP if roll < 0.4
		else NelvarCaveData.Tint.CLEAR), 1.0 if rng.randf() < _config.glowing_share * glow_boost else 0.0)
	_add(crystal)
	return true


## Boulders and small stones (snow caps on the snow, frost caps in the dark), smooth
## stones of ice.
func _stones(rng: RandomNumberGenerator) -> void:
	var boulders := rng.randi_range(_config.boulders.x, _config.boulders.y)
	var stones := rng.randi_range(_config.stones.x, _config.stones.y)
	for spec: Array in [[boulders, Vector2(30.0, 46.0)], [stones, Vector2(10.0, 24.0)]]:
		var placed := 0
		for attempt in int(spec[0]) * 14:
			if placed >= int(spec[0]):
				break
			var radius := rng.randf_range((spec[1] as Vector2).x, (spec[1] as Vector2).y)
			var point := _floor_point(rng, 0.9 if rng.randf() < 0.7 else -1.0)
			if not _fits(point, radius, true, 0.0):
				continue
			var rock := _thing(Kind.ROCK, point, radius, true, rng)
			rock.variant = 0 if _data.snow_depth(point) > 0.0 else 1
			rock.accent = rng.randf() < 0.45
			_add(rock)
			placed += 1
	var ice_stones := rng.randi_range(_config.ice_stones.x, _config.ice_stones.y)
	var placed := 0
	for attempt in ice_stones * 14:
		if placed >= ice_stones:
			break
		var size := rng.randi_range(0, 2)
		var radius: float = [rng.randf_range(12.0, 18.0), rng.randf_range(20.0, 28.0), rng.randf_range(32.0, 46.0)][size]
		var point := _floor_point(rng, 0.8 if rng.randf() < 0.6 else -1.0)
		if not _fits(point, radius, true, 0.0):
			continue
		var stone := _thing(Kind.ICE_STONE, point, radius, true, rng)
		stone.variant = size
		stone.accent = rng.randf() < 0.5
		_add(stone)
		placed += 1


## Stalagmites under the drips: round the geysers' warmth and under the sun.
func _stalagmites(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.stalagmites.x, _config.stalagmites.y)
	var placed := 0
	for attempt in wanted * 20:
		if placed >= wanted:
			break
		var point := Vector2.INF
		var mineral := false
		if rng.randf() < 0.6 and not _data.geysers.is_empty():
			var geyser := _data.geysers[rng.randi_range(0, _data.geysers.size() - 1)]
			point = geyser.position + Vector2.from_angle(rng.randf() * TAU) * geyser.radius * rng.randf_range(0.35, 1.1)
			mineral = rng.randf() < 0.6
		elif not _data.skylights.is_empty():
			var skylight := _data.skylights[rng.randi_range(0, _data.skylights.size() - 1)]
			point = skylight.spot.point_at(rng.randf() * TAU, -rng.randf_range(0.0, 120.0))
		else:
			continue
		var radius := rng.randf_range(8.0, 20.0)
		var solid := radius >= 12.0
		if not _fits(point, radius, solid, 0.0):
			continue
		var stalagmite := _thing(Kind.STALAGMITE, point, radius, solid, rng)
		stalagmite.variant = 1 if mineral else 0
		stalagmite.size = Vector2(radius, radius * rng.randf_range(2.0, 4.6))
		_add(stalagmite)
		placed += 1


## Blocks of ice out on the frozen lakes (cover on the slippery ground) and pressure
## ridges along the walls of the cold halls.
func _ice_blocks(rng: RandomNumberGenerator) -> void:
	for l in _data.lakes.size():
		if _data.pools[l] != Pool.FROZEN:
			continue
		var lake := _data.lakes[l]
		var count := rng.randi_range(1, 2)
		var out := 0
		for attempt in count * 16:
			if out >= count:
				break
			var ridge := rng.randf() < 0.4
			var radius := rng.randf_range(30.0, 46.0) if ridge else rng.randf_range(18.0, 32.0)
			var point := lake.shape.center + Vector2.from_angle(rng.randf() * TAU) * lake.shape.axes * sqrt(rng.randf()) * 0.75
			var hides := false
			for creature in _data.frozen:
				if creature.lake == l and creature.position.distance_to(point) < creature.radius + radius + 20.0:
					hides = true
			var block := _thing(Kind.ICE_BLOCK, point, radius, true, rng)
			block.variant = NelvarIceData.Block.RIDGE if ridge else NelvarIceData.Block.CHUNK
			block.accent = true
			if not hides and _fits(point, block.spread(), true, 20.0, true):
				_add(block)
				out += 1
	for hall in _data.halls:
		if hall.zone != Zone.COLD:
			continue
		var count := rng.randi_range(2, 4)
		var placed := 0
		for attempt in count * 16:
			if placed >= count:
				break
			var ridge := rng.randf() < 0.5
			var radius := rng.randf_range(34.0, 52.0) if ridge else rng.randf_range(18.0, 36.0)
			var point := hall.shape.point_at(rng.randf() * TAU, radius * 0.7 + 10.0)
			var block := _thing(Kind.ICE_BLOCK, point, radius, true, rng)
			block.variant = NelvarIceData.Block.RIDGE if ridge else NelvarIceData.Block.CHUNK
			if _fits(point, block.spread(), true, 0.0):
				_add(block)
				placed += 1


## Bones half frozen into the floor: ribs, skulls, horns.
func _bones(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.bones.x, _config.bones.y)
	var placed := 0
	for attempt in wanted * 16:
		if placed >= wanted:
			break
		var radius := rng.randf_range(16.0, 30.0)
		var point := _floor_point(rng, -1.0)
		if _data.snow_depth(point) > -20.0 or not _fits(point, radius, false, 6.0):
			continue
		var bones := _thing(Kind.BONES, point, radius, false, rng)
		bones.variant = rng.randi_range(0, 2)
		bones.accent = rng.randf() < 0.5
		_add(bones)
		placed += 1


## Creatures caught in ice flows at the foot of the south faces: a head with open jaws, a
## paw, a tail, a wing; some heads watch.
func _embedded(rng: RandomNumberGenerator) -> void:
	var wanted := rng.randi_range(_config.embedded.x, _config.embedded.y)
	var placed: Array[Vector2] = []
	for attempt in wanted * 60:
		if placed.size() >= wanted:
			break
		var start := _floor_point(rng, -1.0)
		if _data.wall_depth(start) > -10.0:
			continue
		# Up to the face above.
		var base := Vector2.INF
		var point := start
		for step in 60:
			var next := point + Vector2(0.0, -4.0)
			if _data.wall_depth(next) > 0.0:
				base = point
				break
			point = next
		if not base.is_finite():
			continue
		var tall := true
		for k in range(2, 16):
			if _data.wall_depth(base + Vector2(0.0, -4.0 * k)) <= 0.0:
				tall = false
		var radius := rng.randf_range(18.0, 26.0)
		for side: float in [-1.0, 1.0]:
			if _data.wall_depth(base + Vector2(side * (radius + 10.0), -10.0)) <= 0.0:
				tall = false
		if not tall or _data.wall_depth(base + Vector2(0.0, 30.0)) > -24.0:
			continue
		# The flow bulges a few art pixels out onto the floor: the origin is its front.
		var at := base + Vector2(0.0, 18.0)
		var apart := true
		for other in placed:
			if other.distance_to(at) < 220.0:
				apart = false
		if not apart or _data.snow_depth(at) > 0.0 or not _clear_of_hazards(at, 40.0) or _data.lake_depth(at) > -30.0:
			continue
		var crowded := false
		for other: NelvarIceData.Thing in _nearby(at, 120.0):
			if other.position.distance_to(at) < other.spread() + radius + 16.0:
				crowded = true
		if crowded or at.distance_to(_data.spawn_position) < 200.0:
			continue
		var thing := _thing(Kind.EMBEDDED, at, radius, true, rng)
		thing.variant = rng.randi_range(0, NelvarCaveData.Part.size() - 1)
		thing.accent = thing.variant == NelvarCaveData.Part.HEAD and rng.randf() < 0.6
		thing.size = Vector2(radius, 0.0)
		_add(thing)
		placed.append(at)
