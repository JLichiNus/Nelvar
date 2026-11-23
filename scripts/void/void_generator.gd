class_name NelvarVoidGenerator
extends RefCounted
## Deterministic layout of the Void: a winding route of debris from the spawn to the
## monolith, dead-end side branches and scattered unreachable pieces.
##
## Route pieces are placed one after another at an exact edge-to-edge gap from the
## previous one (see NelvarVoidData.Gap); every other pair of pieces is kept farther
## apart than a run-up reaches, so the route cannot be cut short on foot.

const LAYOUT_ATTEMPTS := 24
const PLACEMENT_TRIES := 40
## Closest any two pieces that are not neighbours may come (beyond running reach).
const MIN_SEPARATION := 120.0
const MONOLITH_SEPARATION := 230.0
## The route ends once a piece is this close to the monolith.
const FINISH_DISTANCE := 560.0
const MAX_ROUTE := 34
const MAX_FERRIES := 2
const MAX_FLICKERS := 2
const MAX_FLIGHTS := 2
const BRANCHES := Vector2i(3, 5)
const STRAYS := Vector2i(16, 24)
const CAUSEWAY_WIDTH := 72.0

var _rng: RandomNumberGenerator
var _data: NelvarVoidData
var _monolith_polygon: PackedVector2Array


func generate(world_seed: int) -> NelvarVoidData:
	_monolith_polygon = PackedVector2Array()
	for point in NelvarVoidData.monolith_polygon():
		_monolith_polygon.append(point + NelvarVoidData.MONOLITH_CENTER)
	for attempt in LAYOUT_ATTEMPTS:
		_rng = RandomNumberGenerator.new()
		_rng.seed = ("%d:void:%d" % [world_seed, attempt]).hash()
		_data = NelvarVoidData.new()
		_data.world_seed = world_seed
		_data.monolith = _make_monolith()
		if not _build_route():
			continue
		_build_branches()
		_build_strays()
		_data.spawn_position = _data.debris[0].position
		return _data
	push_error("Unable to build the Void for seed %d." % world_seed)
	return null


func _make_monolith() -> NelvarVoidData.Debris:
	var piece := NelvarVoidData.Debris.new()
	piece.id = -1
	piece.kind = NelvarVoidData.Kind.MONOLITH
	piece.polygon = NelvarVoidData.monolith_polygon()
	piece.radius = _radius(piece.polygon)
	piece.position = NelvarVoidData.MONOLITH_CENTER
	# The same everywhere: its look does not depend on the world seed.
	piece.appearance_seed = 0x5EA1ED
	return piece


# --- Route -------------------------------------------------------------------

func _build_route() -> bool:
	var start := _new_piece(NelvarVoidData.Kind.EARTH, 0.0)
	start.position = Vector2.ZERO
	start.on_route = true
	_add(start)
	var ferries := 0
	var flickers := 0
	var flights := 0
	var last_flight := -10
	var current := start
	while _data.route.size() < MAX_ROUTE:
		var anchor := current.position + current.travel
		var to_goal := NelvarVoidData.MONOLITH_CENTER - anchor
		var index := _data.route.size()
		var distance := NelvarVoidData.crossing_gap(anchor, current.world_polygon(_far_time(current)),
			NelvarVoidData.MONOLITH_CENTER, _monolith_polygon)
		if distance <= FINISH_DISTANCE:
			return _finish_route(current)
		# Choose what the next crossing takes and how the next piece behaves.
		var motion := NelvarVoidData.Motion.STILL
		if index >= 2 and current.motion == NelvarVoidData.Motion.STILL:
			var roll := _rng.randf()
			if roll < 0.2 and ferries < MAX_FERRIES:
				motion = NelvarVoidData.Motion.FERRY
			elif roll < 0.36 and flickers < MAX_FLICKERS:
				motion = NelvarVoidData.Motion.FLICKER
		var gap := NelvarVoidData.Gap.STEP
		var near_goal := distance < FINISH_DISTANCE + 700.0
		if motion == NelvarVoidData.Motion.STILL and current.motion == NelvarVoidData.Motion.STILL \
				and index >= 1 and not near_goal:
			var roll := _rng.randf()
			if roll < 0.2 and flights < MAX_FLIGHTS and index - last_flight >= 5:
				gap = NelvarVoidData.Gap.FLIGHT
			elif roll < 0.42:
				gap = NelvarVoidData.Gap.LEAP
		var placed: NelvarVoidData.Debris = null
		for attempt in PLACEMENT_TRIES:
			var spread := lerpf(1.0, 0.35, clampf(1.0 - distance / 2600.0, 0.0, 1.0))
			var direction := to_goal.normalized().rotated(_rng.randf_range(-spread, spread))
			var kind := _route_kind(motion)
			var piece := _new_piece(kind, direction.angle())
			piece.motion = motion
			piece.on_route = true
			if not _place_at_gap(piece, current, current.travel, direction, _gap_width(gap), gap):
				continue
			if motion == NelvarVoidData.Motion.FERRY:
				var drift := to_goal.normalized().rotated(_rng.randf_range(-0.5, 0.5))
				piece.travel = drift * _rng.randf_range(240.0, 360.0)
				piece.period = _rng.randf_range(5.5, 7.5)
				# Starts at the near end, waiting for the player.
				piece.phase = 0.0
			elif motion == NelvarVoidData.Motion.FLICKER:
				piece.period = _rng.randf_range(5.0, 7.0)
				piece.phase = _rng.randf()
			if not _fits(piece, [current]):
				continue
			placed = piece
			break
		if placed == null:
			return false
		current.gap = gap
		if gap == NelvarVoidData.Gap.FLIGHT:
			flights += 1
			last_flight = index
		if motion == NelvarVoidData.Motion.FERRY:
			ferries += 1
		elif motion == NelvarVoidData.Motion.FLICKER:
			flickers += 1
		_add(placed)
		current = placed
	return false


## A broken causeway from the last piece straight towards the monolith's centre,
## a step from each end along that line.
func _finish_route(current: NelvarVoidData.Debris) -> bool:
	var polygon := current.world_polygon(_far_time(current))
	var from := current.position + current.travel
	var points := NelvarVoidData.crossing_points(from, polygon, NelvarVoidData.MONOLITH_CENTER,
		_monolith_polygon)
	var direction := from.direction_to(NelvarVoidData.MONOLITH_CENTER)
	var near_gap := _rng.randf_range(NelvarVoidData.STEP_GAP.x + 4.0, NelvarVoidData.STEP_GAP.y - 6.0)
	var far_gap := _rng.randf_range(NelvarVoidData.STEP_GAP.x + 4.0, NelvarVoidData.STEP_GAP.y - 6.0)
	var length := points[0].distance_to(points[1]) - near_gap - far_gap
	if length < 140.0:
		return false
	var piece := NelvarVoidData.Debris.new()
	piece.kind = NelvarVoidData.Kind.RUIN
	piece.appearance_seed = _rng.randi()
	piece.on_route = true
	piece.angle = direction.angle()
	piece.polygon = _causeway_polygon(length, CAUSEWAY_WIDTH, piece.angle)
	piece.radius = _radius(piece.polygon)
	piece.position = points[0] + direction * (near_gap + length * 0.5)
	var world := piece.world_polygon()
	# Its ends are square to the line, so both crossings are exactly the chosen steps;
	# check anyway, and that no corner grazes either neighbour.
	if not _is_step(NelvarVoidData.crossing_gap(from, polygon, piece.position, world)) \
			or not _is_step(NelvarVoidData.crossing_gap(piece.position, world,
				NelvarVoidData.MONOLITH_CENTER, _monolith_polygon)):
		return false
	if NelvarVoidData.polygon_distance(world, polygon) < NelvarVoidData.MIN_EDGE_GAP \
			or NelvarVoidData.polygon_distance(world, _monolith_polygon) < NelvarVoidData.MIN_EDGE_GAP:
		return false
	var step_slack := NelvarVoidData.SLACK_LIMITS[NelvarVoidData.Gap.STEP]
	if NelvarVoidData.slack_gap(from, polygon, piece.position, world) > step_slack \
			or NelvarVoidData.slack_gap(piece.position, world, NelvarVoidData.MONOLITH_CENTER,
				_monolith_polygon) > step_slack:
		return false
	if not _fits(piece, [current], true):
		return false
	current.gap = NelvarVoidData.Gap.STEP
	piece.gap = NelvarVoidData.Gap.STEP
	_add(piece)
	return true


func _is_step(gap: float) -> bool:
	return gap >= NelvarVoidData.STEP_GAP.x and gap <= NelvarVoidData.STEP_GAP.y


## FERRY pieces are crossed to from their far end; everything else is still.
func _far_time(piece: NelvarVoidData.Debris) -> float:
	return piece.period * 0.5 if piece.motion == NelvarVoidData.Motion.FERRY else 0.0


func _route_kind(motion: NelvarVoidData.Motion) -> NelvarVoidData.Kind:
	if motion == NelvarVoidData.Motion.FLICKER:
		return NelvarVoidData.Kind.SHARD
	if motion == NelvarVoidData.Motion.FERRY:
		var movers := [NelvarVoidData.Kind.ROCK, NelvarVoidData.Kind.ICE, NelvarVoidData.Kind.AIR]
		return movers[_rng.randi_range(0, movers.size() - 1)]
	var kinds := [NelvarVoidData.Kind.EARTH, NelvarVoidData.Kind.ROCK, NelvarVoidData.Kind.LOG,
		NelvarVoidData.Kind.ICE, NelvarVoidData.Kind.FIRE, NelvarVoidData.Kind.AIR,
		NelvarVoidData.Kind.RUIN, NelvarVoidData.Kind.LOG]
	return kinds[_rng.randi_range(0, kinds.size() - 1)]


func _gap_width(gap: NelvarVoidData.Gap) -> float:
	match gap:
		NelvarVoidData.Gap.LEAP:
			return _rng.randf_range(NelvarVoidData.LEAP_GAP.x + 2.0, NelvarVoidData.LEAP_GAP.y - 2.0)
		NelvarVoidData.Gap.FLIGHT:
			return _rng.randf_range(NelvarVoidData.FLIGHT_GAP.x + 5.0, NelvarVoidData.FLIGHT_GAP.y - 5.0)
	return _rng.randf_range(NelvarVoidData.STEP_GAP.x + 3.0, NelvarVoidData.STEP_GAP.y - 3.0)


## Moves `piece` along `direction` from `previous` (shifted by `previous_offset`)
## until the crossing between their middles is exactly `gap` wide (that is the way
## a player goes). Lines a little to the side must stay within reach of `kind` of
## crossing too, and no other part of the two may come closer than MIN_EDGE_GAP.
func _place_at_gap(piece: NelvarVoidData.Debris, previous: NelvarVoidData.Debris,
		previous_offset: Vector2, direction: Vector2, gap: float,
		kind: NelvarVoidData.Gap = NelvarVoidData.Gap.STEP) -> bool:
	var other := PackedVector2Array()
	for point in previous.polygon:
		other.append(point + previous.position + previous_offset)
	var origin := previous.position + previous_offset
	var distance := previous.radius + piece.radius + gap
	for i in 24:
		piece.position = origin + direction * distance
		var world := piece.world_polygon()
		var actual := NelvarVoidData.crossing_gap(origin, other, piece.position, world)
		if absf(actual - gap) < 0.5:
			return NelvarVoidData.polygon_distance(world, other) >= NelvarVoidData.MIN_EDGE_GAP \
				and NelvarVoidData.slack_gap(origin, other, piece.position, world) \
					<= NelvarVoidData.SLACK_LIMITS[kind]
		distance += gap - actual
	return false


## No overlap with the monolith, nothing but `neighbours` within MIN_SEPARATION.
## FERRY pieces are checked along their whole path.
func _fits(piece: NelvarVoidData.Debris, neighbours: Array, near_monolith := false) -> bool:
	var samples := [0.0]
	if piece.motion == NelvarVoidData.Motion.FERRY:
		samples = [0.0, piece.period * 0.125, piece.period * 0.25, piece.period * 0.375,
			piece.period * 0.5]
	for time: float in samples:
		var polygon := piece.world_polygon(time)
		var to_monolith := NelvarVoidData.polygon_distance(polygon, _monolith_polygon)
		if to_monolith < 0.0 or (not near_monolith and to_monolith < MONOLITH_SEPARATION):
			return false
		for other in _data.debris:
			var other_polygon := other.world_polygon(_far_time(other) if other.motion \
				== NelvarVoidData.Motion.FERRY and time > 0.0 else 0.0)
			var gap := NelvarVoidData.polygon_distance(polygon, other_polygon)
			if neighbours.has(other):
				if gap < NelvarVoidData.MIN_EDGE_GAP - 0.5:
					return false
				continue
			if gap < MIN_SEPARATION:
				return false
			# Every position of a moving neighbour counts too.
			if other.motion == NelvarVoidData.Motion.FERRY:
				for t in [other.period * 0.25, other.period * 0.5]:
					if NelvarVoidData.polygon_distance(polygon, other.world_polygon(t)) < MIN_SEPARATION:
						return false
	return true


# --- Side branches and strays --------------------------------------------------

## Dead ends off the route, one to three pieces long; the last one keeps a relic.
func _build_branches() -> void:
	var count := _rng.randi_range(BRANCHES.x, BRANCHES.y)
	for branch in count:
		var root_index := _rng.randi_range(1, maxi(1, _data.route.size() - 3))
		var current := _data.debris[_data.route[root_index]]
		if current.motion != NelvarVoidData.Motion.STILL:
			continue
		var heading := Vector2.from_angle(_rng.randf() * TAU)
		var length := _rng.randi_range(1, 3)
		var last: NelvarVoidData.Debris = null
		for step in length:
			var placed: NelvarVoidData.Debris = null
			for attempt in PLACEMENT_TRIES / 2:
				var direction := heading.rotated(_rng.randf_range(-0.6, 0.6))
				var piece := _new_piece(_route_kind(NelvarVoidData.Motion.STILL), direction.angle())
				var gap := NelvarVoidData.Gap.LEAP if _rng.randf() < 0.35 else NelvarVoidData.Gap.STEP
				if not _place_at_gap(piece, current, Vector2.ZERO, direction, _gap_width(gap), gap):
					continue
				if _fits(piece, [current]):
					placed = piece
					break
			if placed == null:
				break
			_add(placed)
			current = placed
			last = placed
		if last != null:
			last.relic = true


## Pieces hanging alone, far from everything: only flight reaches them.
func _build_strays() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	for piece in _data.debris:
		bounds = bounds.expand(piece.position)
	bounds = bounds.grow(700.0)
	var count := _rng.randi_range(STRAYS.x, STRAYS.y)
	for i in count:
		for attempt in PLACEMENT_TRIES:
			var piece := _new_piece(_route_kind(NelvarVoidData.Motion.STILL), _rng.randf() * TAU)
			if _rng.randf() < 0.15:
				piece = _new_piece(NelvarVoidData.Kind.SHARD, _rng.randf() * TAU)
				piece.motion = NelvarVoidData.Motion.FLICKER
				piece.period = _rng.randf_range(4.0, 9.0)
				piece.phase = _rng.randf()
			piece.position = Vector2(_rng.randf_range(bounds.position.x, bounds.end.x),
				_rng.randf_range(bounds.position.y, bounds.end.y))
			if _fits(piece, []):
				# Strays stand apart: farther than a run-up from everything.
				_add(piece)
				break


# --- Pieces ------------------------------------------------------------------

func _add(piece: NelvarVoidData.Debris) -> void:
	piece.id = _data.debris.size()
	_data.debris.append(piece)
	if piece.on_route:
		_data.route.append(piece.id)


## A new piece of `kind`; long pieces lie along `angle`.
func _new_piece(kind: NelvarVoidData.Kind, angle: float) -> NelvarVoidData.Debris:
	var piece := NelvarVoidData.Debris.new()
	piece.kind = kind
	piece.appearance_seed = _rng.randi()
	match kind:
		NelvarVoidData.Kind.EARTH:
			piece.polygon = _blob(_rng.randf_range(110.0, 175.0), 22, 0.16, true)
		NelvarVoidData.Kind.ROCK:
			piece.polygon = _shard_shape(_rng.randf_range(64.0, 100.0), _rng.randi_range(8, 11), 0.22)
		NelvarVoidData.Kind.LOG:
			piece.angle = angle + _rng.randf_range(-0.3, 0.3)
			piece.polygon = _log_polygon(_rng.randf_range(220.0, 320.0), _rng.randf_range(46.0, 56.0),
				piece.angle)
		NelvarVoidData.Kind.ICE:
			piece.polygon = _shard_shape(_rng.randf_range(80.0, 130.0), _rng.randi_range(6, 8), 0.3,
				Vector2(1.0, _rng.randf_range(0.6, 0.85)), _rng.randf() * TAU)
		NelvarVoidData.Kind.FIRE:
			piece.polygon = _shard_shape(_rng.randf_range(80.0, 125.0), _rng.randi_range(7, 10), 0.14)
		NelvarVoidData.Kind.AIR:
			piece.polygon = _blob(_rng.randf_range(72.0, 115.0), 16, 0.1, false)
		NelvarVoidData.Kind.RUIN:
			piece.angle = _rng.randf() * TAU
			piece.polygon = _slab(_rng.randf_range(150.0, 220.0), _rng.randf_range(100.0, 130.0),
				piece.angle)
		NelvarVoidData.Kind.SHARD:
			piece.polygon = _shard_shape(_rng.randf_range(72.0, 96.0), _rng.randi_range(5, 6), 0.18,
				Vector2(1.0, 0.7), _rng.randf() * TAU)
	piece.radius = _radius(piece.polygon)
	return piece


## A torn chunk of an island: lobed, with one side bitten off.
func _blob(radius: float, vertices: int, roughness: float, torn: bool) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var phases := Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	var tear := _rng.randf() * TAU
	for i in vertices:
		var angle := TAU * float(i) / vertices
		var factor := 1.0 + roughness * sin(angle * 3.0 + phases.x)
		factor += roughness * 0.5 * sin(angle * 7.0 + phases.y)
		if torn and absf(angle_difference(angle, tear)) < 0.7:
			# The broken side: jagged and pulled in.
			factor *= _rng.randf_range(0.62, 0.86)
		polygon.append(Vector2.from_angle(angle) * radius * factor)
	return polygon


## Angular fragment: few vertices, uneven radii, optionally stretched and turned.
func _shard_shape(radius: float, vertices: int, jitter: float,
		stretch := Vector2.ONE, turn := 0.0) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var start := _rng.randf() * TAU
	for i in vertices:
		var angle := start + TAU * (float(i) + _rng.randf_range(-0.25, 0.25)) / vertices
		var point := Vector2.from_angle(angle) * radius * _rng.randf_range(1.0 - jitter, 1.0 + jitter * 0.4)
		polygon.append((point * stretch).rotated(turn))
	return polygon


## A fallen trunk lying along `angle`, both ends broken off.
func _log_polygon(length: float, width: float, angle: float) -> PackedVector2Array:
	var half := Vector2(length, width) * 0.5
	var points: Array[Vector2] = [
		Vector2(-half.x, -half.y), Vector2(half.x * 0.96, -half.y),
		Vector2(half.x + _rng.randf_range(4.0, 14.0), -half.y * 0.3),
		Vector2(half.x - _rng.randf_range(0.0, 10.0), half.y * 0.2),
		Vector2(half.x, half.y), Vector2(-half.x * 0.97, half.y),
		Vector2(-half.x - _rng.randf_range(4.0, 14.0), half.y * 0.25),
		Vector2(-half.x + _rng.randf_range(0.0, 10.0), -half.y * 0.25),
	]
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(point.rotated(angle))
	return polygon


## A paved slab with chipped corners.
func _slab(width: float, height: float, angle: float) -> PackedVector2Array:
	var half := Vector2(width, height) * 0.5
	var chip := _rng.randf_range(14.0, 34.0)
	var points: Array[Vector2] = [
		Vector2(-half.x + chip, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y - chip * 0.7), Vector2(half.x - chip * 1.2, half.y),
		Vector2(-half.x, half.y), Vector2(-half.x, -half.y + chip),
	]
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(point.rotated(angle))
	return polygon


## A long broken causeway along `angle`, its sides gently chipped.
func _causeway_polygon(length: float, width: float, angle: float) -> PackedVector2Array:
	var half := Vector2(length, width) * 0.5
	var points: Array[Vector2] = [
		Vector2(-half.x, -half.y), Vector2(-half.x * 0.3, -half.y),
		Vector2(-half.x * 0.1, -half.y * 0.82), Vector2(half.x * 0.4, -half.y * 0.9),
		Vector2(half.x, -half.y), Vector2(half.x, half.y),
		Vector2(half.x * 0.2, half.y), Vector2(0.0, half.y * 0.84),
		Vector2(-half.x * 0.5, half.y * 0.9), Vector2(-half.x, half.y),
	]
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(point.rotated(angle))
	return polygon


func _radius(polygon: PackedVector2Array) -> float:
	var radius := 0.0
	for point in polygon:
		radius = maxf(radius, point.length())
	return radius
