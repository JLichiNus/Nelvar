class_name NelvarVoidData
extends RefCounted
## Geometry of the Void: debris of the four realities hanging over nothing, the
## route across them and the fixed monolith with the arena at its end.
##
## Nothing here has walls. Ground is wherever a piece of debris is; the player
## crosses the gaps between pieces on momentum, by running or by flight
## (see NelvarVoidMain for the rules and the reach constants below).

enum Kind { EARTH, ROCK, LOG, ICE, FIRE, AIR, RUIN, SHARD, MONOLITH }
## STILL hangs in place; FERRY drifts back and forth between two neighbours of the
## route; FLICKER fades out of existence for a while and comes back.
enum Motion { STILL, FERRY, FLICKER }
## What it takes to cross from a route piece to the next one.
enum Gap { STEP, LEAP, FLIGHT }

## Off the ground the player still stands for this long (seconds), so walking
## over a narrow gap is safe; longer is a fall.
const COYOTE_TIME := 0.2
## Ground reaches this far past the drawn edge (the body overhangs a little).
const EDGE_TOLERANCE := 6.0
## Gap widths, world units, measured the way a player crosses: straight from the
## middle of one piece towards the middle of the next (see crossing_gap). With the
## player's speeds (300 walking, 450 running, flight for 2 s) a STEP is crossed
## walking, a LEAP needs a run-up and a FLIGHT gap needs the flight. Tests keep
## these consistent and walk the whole route with the real player.
const STEP_GAP := Vector2(14.0, 36.0)
const LEAP_GAP := Vector2(84.0, 94.0)
const FLIGHT_GAP := Vector2(180.0, 280.0)
## Nobody walks exactly through the middles: lines this far to either side of the
## straight crossing must still stay within reach (see SLACK_LIMITS).
const CROSSING_SLACK := 16.0
## Widest abyss allowed on those side lines, per Gap: well inside walking,
## running and flying reach.
const SLACK_LIMITS: Array[float] = [50.0, 102.0, 330.0]
## Neighbouring pieces never come closer than this anywhere (no touching corners).
const MIN_EDGE_GAP := 6.0
const WALK_SPEED := 300.0
const RUN_SPEED := 450.0

## FLICKER cycle: solid for this share of the period, the last WARN_TIME of it flickering.
const FLICKER_SOLID_SHARE := 0.68
const FLICKER_WARN_TIME := 0.9

## The monolith is the same in every Void: its outline around MONOLITH_CENTER,
## scaled by MONOLITH_SCALE (it holds the arena of the Only One).
const MONOLITH_CENTER := Vector2(0.0, -4900.0)
const MONOLITH_SCALE := 1.6
const MONOLITH_OUTLINE: Array[Vector2] = [
	Vector2(-560, -360), Vector2(-380, -520), Vector2(-120, -480), Vector2(40, -600),
	Vector2(300, -540), Vector2(470, -380), Vector2(620, -300), Vector2(560, -60),
	Vector2(660, 120), Vector2(520, 330), Vector2(300, 380), Vector2(180, 520),
	Vector2(-60, 470), Vector2(-240, 540), Vector2(-420, 380), Vector2(-600, 300),
	Vector2(-540, 60), Vector2(-660, -120),
]
## Entering this radius around the arena centre starts the fight.
const ARENA_TRIGGER_RADIUS := 480.0
## Attacks that fill the arena reach this far from its centre (past every edge).
const ARENA_REACH := 1100.0
## Broken obelisks ring the arena: angle (radians) and how much of each is left.
const OBELISK_RING := 640.0
const OBELISKS: Array[Vector2] = [
	Vector2(-1.85, 1.0), Vector2(-0.82, 0.55), Vector2(0.18, 1.0),
	Vector2(1.05, 0.35), Vector2(2.2, 0.8), Vector2(3.05, 1.0),
]
const OBELISK_RADIUS := 26.0


class Debris:
	var id: int
	var kind: Kind
	var motion := Motion.STILL
	## Walkable outline around the origin.
	var polygon: PackedVector2Array
	## Farthest polygon point from the origin.
	var radius: float
	## Long pieces (logs, slabs, causeways) lie along this angle; their art follows it.
	var angle := 0.0
	## Rest position. A FERRY travels from here to position + travel and back.
	var position: Vector2
	var travel := Vector2.ZERO
	var period := 1.0
	var phase := 0.0
	var on_route := false
	## Dead end of a side branch: something forgotten lies there.
	var relic := false
	## Gap to the next route piece (route pieces only).
	var gap := Gap.STEP
	var appearance_seed: int

	## FERRY: offset from the rest position at `time`, 0..travel and back.
	func offset_at(time: float) -> Vector2:
		if motion != Motion.FERRY:
			return Vector2.ZERO
		return travel * (0.5 - 0.5 * cos(TAU * time / period + phase))

	## 0..1 position in the FLICKER cycle.
	func cycle_at(time: float) -> float:
		return fposmod(time / period + phase, 1.0)

	func is_solid_at(time: float) -> bool:
		return motion != Motion.FLICKER or cycle_at(time) < FLICKER_SOLID_SHARE

	func world_polygon(time: float = 0.0) -> PackedVector2Array:
		var shift := position + offset_at(time)
		var result := PackedVector2Array()
		for point in polygon:
			result.append(point + shift)
		return result

	## Supports a point `margin` beyond its edge too.
	func supports(point: Vector2, time: float, margin: float) -> bool:
		if not is_solid_at(time):
			return false
		var local := point - position - offset_at(time)
		if local.length_squared() > (radius + margin) * (radius + margin):
			return false
		if Geometry2D.is_point_in_polygon(local, polygon):
			return true
		return NelvarVoidData.distance_to_outline(local, polygon) <= margin


var world_seed: int
var debris: Array[Debris] = []
## Route piece ids from the spawn to the last piece before the monolith.
var route: Array[int] = []
var monolith: Debris
var spawn_position: Vector2
var arena_center := MONOLITH_CENTER


## The piece under `point` at `time`; the monolith counts as one. Null over the abyss.
func support_at(point: Vector2, time: float, margin: float = EDGE_TOLERANCE) -> Debris:
	if monolith != null and monolith.supports(point, time, margin):
		return monolith
	for piece in debris:
		if piece.supports(point, time, margin):
			return piece
	return null


func route_pieces() -> Array[Debris]:
	var result: Array[Debris] = []
	for id in route:
		result.append(debris[id])
	return result


func count_gaps(gap: Gap) -> int:
	var count := 0
	for id in route:
		if debris[id].gap == gap:
			count += 1
	return count


func count_motion(motion: Motion) -> int:
	var count := 0
	for piece in debris:
		if piece.motion == motion:
			count += 1
	return count


static func monolith_polygon() -> PackedVector2Array:
	var outline := PackedVector2Array()
	for point in MONOLITH_OUTLINE:
		outline.append(point * MONOLITH_SCALE)
	return outline


static func obelisk_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for spec in OBELISKS:
		result.append(MONOLITH_CENTER + Vector2.from_angle(spec.x) * OBELISK_RING)
	return result


## The gap a player walks over going straight from `from` (inside outline `a`)
## towards `to` (inside outline `b`): from where that line last leaves `a` to where
## it first enters `b`. All pieces are star-shaped around their origin, so a line
## from the middle leaves a piece once. Negative when they overlap on that line.
static func crossing_gap(from: Vector2, a: PackedVector2Array, to: Vector2,
		b: PackedVector2Array) -> float:
	var leave := 0.0
	for i in a.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, a[i], a[(i + 1) % a.size()])
		if hit is Vector2:
			leave = maxf(leave, from.distance_to(hit))
	var enter := from.distance_to(to)
	for i in b.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, b[i], b[(i + 1) % b.size()])
		if hit is Vector2:
			enter = minf(enter, from.distance_to(hit))
	return enter - leave


## Total length of the line from `from` to `to` that is over the abyss, i.e. not
## inside any of `outlines`.
static func abyss_along(from: Vector2, to: Vector2, outlines: Array[PackedVector2Array]) -> float:
	var length := from.distance_to(to)
	if length <= 0.0:
		return 0.0
	var cuts: Array[float] = [0.0, 1.0]
	for outline in outlines:
		for i in outline.size():
			var hit: Variant = Geometry2D.segment_intersects_segment(from, to, outline[i],
				outline[(i + 1) % outline.size()])
			if hit is Vector2:
				cuts.append(from.distance_to(hit) / length)
	cuts.sort()
	var abyss := 0.0
	for i in range(1, cuts.size()):
		var middle := from.lerp(to, (cuts[i] + cuts[i - 1]) * 0.5)
		var solid := false
		for outline in outlines:
			if Geometry2D.is_point_in_polygon(middle, outline):
				solid = true
				break
		if not solid:
			abyss += (cuts[i] - cuts[i - 1]) * length
	return abyss


## The crossing from `from` to `to`, shifted CROSSING_SLACK to each side: the widest
## abyss on those two lines.
static func slack_gap(from: Vector2, a: PackedVector2Array, to: Vector2,
		b: PackedVector2Array) -> float:
	var side := from.direction_to(to).orthogonal() * CROSSING_SLACK
	var outlines: Array[PackedVector2Array] = [a, b]
	return maxf(abyss_along(from + side, to + side, outlines),
		abyss_along(from - side, to - side, outlines))


## Where the straight crossing from `from` to `to` leaves `a` and enters `b`.
static func crossing_points(from: Vector2, a: PackedVector2Array, to: Vector2,
		b: PackedVector2Array) -> Array[Vector2]:
	var direction := from.direction_to(to)
	var length := from.distance_to(to)
	var gap := crossing_gap(from, a, to, b)
	var enter := length
	for i in b.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, b[i], b[(i + 1) % b.size()])
		if hit is Vector2:
			enter = minf(enter, from.distance_to(hit))
	return [from + direction * (enter - gap), from + direction * enter]


static func distance_to_outline(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for i in polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, polygon[i],
			polygon[(i + 1) % polygon.size()])
		best = minf(best, point.distance_to(closest))
	return best


## Edge-to-edge distance between two outlines; -1 when they touch or overlap.
static func polygon_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if not Geometry2D.intersect_polygons(a, b).is_empty():
		return -1.0
	var best := INF
	for point in a:
		best = minf(best, distance_to_outline(point, b))
	for point in b:
		best = minf(best, distance_to_outline(point, a))
	return best
