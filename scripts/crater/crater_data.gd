class_name NelvarCraterData
extends NelvarFireData
## The volcano (Огонь 2): the top of one huge mountain. A narrow rim of rock runs round
## the crater; the crater is a lake of lava filled almost to the brim; islands float on
## it, carried round the vent in its middle by rings of current. Beyond the rim's outer
## edge is a sheer drop into clouds of ash far below; the camera, looking down from the
## south, sees the mountain's front slope under the southern edge.
##
## Nothing here is a wall. The lava and the edge are falls: a step over either holds for
## a moment (COYOTE_TIME), then the player goes down. Anchors stand round the vent and
## never sink; plates and rafts ride the rings (their place depends on the time only, so
## every layout is reproducible) and sink now and then, and under weight.
##
## NelvarCraterGenerator builds it; crater_ground.gdshader draws the same geometry: the
## lake, the capes and the anchors are computed the same way there (lava_depth), the
## summit's edge is read from the same table of radii.

enum IsleKind { ANCHOR, PLATE, RAFT }

## A step over the lava or the edge holds this long (seconds) before it is a fall.
const COYOTE_TIME := 0.12
## Ground reaches this far past an island's drawn edge (the body overhangs a little).
const EDGE_TOLERANCE := 6.0
## How round the capes meet the shore (world units).
const CAPE_BLEND := 48.0
## A gap this wide is crossed at a run (the run covers about 54 in COYOTE_TIME).
const RUN_GAP := 44.0
## Islands never come closer than this to each other, to a cape or to an anchor.
const MIN_GAP := 8.0
## Sinking: the plate comes up red-hot (RISE), cools (COOL); warns (WARN) and goes down
## (DESCENT) before its time under.
const RISE := 1.2
const COOL := 2.0
const WARN := 3.0
const DESCENT := 1.2
## Under weight: at this load the island settles (sinks a little), at 1 it goes down.
const SETTLE_LOAD := 0.75
const SETTLE_SINK := 0.12
## Rafts stay under this long after sinking under someone.
const RAFT_UNDER := 5.0


## The summit's edge: a radius per direction (a terrace pushes it out locally, which a
## few harmonics could not). Every Radial query works on it.
class Profile extends NelvarEarthData.Radial:
	## Radii at TAU * i / size directions; linear in between.
	var radii := PackedFloat32Array()

	func radius_at(angle: float) -> float:
		var count := radii.size()
		var t := fposmod(angle, TAU) / TAU * count
		var i := int(t)
		var f := t - float(i)
		i = i % count
		return lerpf(radii[i], radii[(i + 1) % count], f)

	func reach() -> float:
		var best := 0.0
		for radius in radii:
			best = maxf(best, radius)
		return best


## A tongue of rock from the shore into the lake, narrowing to a round tip. The islands
## of the outer ring pass close by its tip.
class Cape:
	var angle := 0.0
	## Its axis: from under the rim to the centre of the round tip.
	var base := Vector2.ZERO
	var tip := Vector2.ZERO
	var half_width := 70.0
	var tip_width := 52.0
	var wobble := 0.06
	var wobble_phase := 0.0

	## Positive on the cape, world units (close to exact near its outline).
	func signed_distance(point: Vector2) -> float:
		var axis := tip - base
		var t := clampf((point - base).dot(axis) / maxf(axis.length_squared(), 0.0001), 0.0, 1.0)
		return width_at(t) - point.distance_to(base + axis * t)

	func width_at(t: float) -> float:
		return lerpf(half_width, tip_width, t) * (1.0 + wobble * sin(t * 9.0 + wobble_phase))

	## The point of the tip, furthest into the lake.
	func apex() -> Vector2:
		return tip + base.direction_to(tip) * width_at(1.0)


## An island: an anchor standing round the vent, or a plate or raft riding a ring of
## current round it. Its shape lies round its own origin.
class Isle:
	var id := 0
	var kind := IsleKind.PLATE
	var shape := NelvarEarthData.Radial.new()
	## The vent for islands on a ring, the island's place for an anchor.
	var center := Vector2.ZERO
	## Ring index (-1 for anchors), distance of the centre from the vent, the angle at
	## time 0 and radians per second (the sign is the way round).
	var ring := -1
	var orbit := 0.0
	var phase := 0.0
	var speed := 0.0
	## Sinking by itself: seconds per cycle (0: never), where it starts, time under.
	var sink_period := 0.0
	var sink_phase := 0.0
	var sink_under := 8.0
	## Seconds of standing on it before it goes down (INF: never).
	var hold_time := INF
	var appearance_seed := 0
	## Smallest and largest radius of the shape.
	var inner := 0.0
	var outer := 0.0
	## Play state (NelvarCraterMain): weight on it, 0..1, and when it last went down
	## under it.
	var weight := 0.0
	var sank_at := -INF

	func moving() -> bool:
		return ring >= 0

	func position_at(time: float) -> Vector2:
		if ring < 0:
			return center
		return center + Vector2.from_angle(phase + speed * time) * orbit

	## How far under it is, 0..1: the lava eats it from the edge inwards.
	func sink_at(time: float) -> float:
		return clampf(maxf(maxf(_cycle(time).x, _under_weight(time).x), _settle()), 0.0, 1.0)

	## 0..1 in the seconds before it goes down by itself.
	func warn_at(time: float) -> float:
		return _cycle(time).y

	## 1 as it comes up red-hot, 0 once cooled.
	func hot_at(time: float) -> float:
		return maxf(_cycle(time).z, _under_weight(time).z)

	## How deep into it the lava eats when it is fully under: past its core, so nothing
	## of it is left.
	func sink_depth() -> float:
		return outer + 8.0

	## Positive on its solid part, world units.
	func depth_at(point: Vector2, time: float) -> float:
		var local := point - position_at(time)
		var far := local.length_squared()
		if far > (outer + 200.0) * (outer + 200.0):
			return outer - sqrt(far)
		return shape.signed_distance(local) - sink_at(time) * sink_depth()

	## (sink, warning, heat) of the cycle at `time`.
	func _cycle(time: float) -> Vector3:
		if sink_period <= 0.0:
			return Vector3.ZERO
		var c := fposmod(time + sink_phase, sink_period)
		var under_at := sink_period - sink_under
		var down_at := under_at - DESCENT
		var warn_at_time := down_at - WARN
		if c < RISE:
			return Vector3(1.0 - c / RISE, 0.0, 1.0)
		if c < RISE + COOL:
			return Vector3(0.0, 0.0, 1.0 - (c - RISE) / COOL)
		if c >= under_at:
			return Vector3(1.0, 1.0, 0.0)
		if c >= down_at:
			return Vector3((c - down_at) / DESCENT, 1.0, 0.0)
		if c >= warn_at_time:
			return Vector3(0.0, (c - warn_at_time) / WARN, 0.0)
		return Vector3.ZERO

	## The same after it went down under weight.
	func _under_weight(time: float) -> Vector3:
		var e := time - sank_at
		if e < 0.0 or not is_finite(e):
			return Vector3.ZERO
		var under := RAFT_UNDER if kind == IsleKind.RAFT else sink_under
		if e < DESCENT:
			# It had settled already: it goes on down from there.
			return Vector3(lerpf(SETTLE_SINK, 1.0, e / DESCENT), 1.0, 0.0)
		e -= DESCENT
		if e < under:
			return Vector3(1.0, 1.0, 0.0)
		e -= under
		if e < RISE:
			return Vector3(1.0 - e / RISE, 0.0, 1.0)
		e -= RISE
		if e < COOL:
			return Vector3(0.0, 0.0, 1.0 - e / COOL)
		return Vector3.ZERO

	func _settle() -> float:
		return smoothstep(SETTLE_LOAD, 1.0, weight) * SETTLE_SINK


## A geyser on the rim: rests, warns, then throws up a column of steam and fire.
class Geyser:
	const WARN_TIME := 1.5
	const BURST_TIME := 0.9
	var position := Vector2.ZERO
	## The mouth.
	var radius := 18.0
	var period := 12.0
	var phase := 0.0
	## Index of the cape it stands on, -1 on the rim.
	var cape := -1

	## 0 at rest, 1 warning, 2 erupting.
	func stage_at(time: float) -> int:
		var c := fposmod(time + phase, period)
		if c >= period - BURST_TIME:
			return 2
		if c >= period - BURST_TIME - WARN_TIME:
			return 1
		return 0

	## Progress through the current stage, 0..1.
	func progress_at(time: float) -> float:
		var c := fposmod(time + phase, period)
		match stage_at(time):
			2:
				return (c - (period - BURST_TIME)) / BURST_TIME
			1:
				return (c - (period - BURST_TIME - WARN_TIME)) / WARN_TIME
		return c / (period - BURST_TIME - WARN_TIME)


## The summit's outer edge (the same object as `basin`) and the crater lake (`lakes[0]`).
var summit: Profile
var lake: NelvarEarthData.Radial
var vent := Vector2.ZERO
var vent_radius := 72.0
var capes: Array[Cape] = []
## Anchors first, then the islands of the rings.
var isles: Array[Isle] = []
## Per ring: inner and outer edge (distance from the vent), radians per second.
var rings: Array[Vector3] = []
## Where the anchors' outer edges lie from the vent.
var anchor_reach := 0.0
var geysers: Array[Geyser] = []
## Patches of boiling lava: centre and radius (z).
var boils: Array[Vector3] = []
## Broad places of the rim: direction and angular half-width.
var terraces: Array[Vector2] = []
## Fresh lava on the rim (NelvarCraterMain keeps it current): centre and radius (z).
var fresh_lava: Array[Vector3] = []
## The shared clock (NelvarCraterMain sets it each physics frame): hoppers ask where to
## land without a time.
var now := 0.0


func count_isles(kind: IsleKind) -> int:
	var total := 0
	for isle in isles:
		if isle.kind == kind:
			total += 1
	return total


func anchors() -> Array[Isle]:
	var result: Array[Isle] = []
	for isle in isles:
		if not isle.moving():
			result.append(isle)
	return result


func moving_isles() -> Array[Isle]:
	var result: Array[Isle] = []
	for isle in isles:
		if isle.moving():
			result.append(isle)
	return result


## Positive on the summit, negative past its edge, world units.
func rim_depth(point: Vector2) -> float:
	return summit.signed_distance(point)


## How wide the rim is in a direction (from the lake's shore to the edge).
func rim_width_at(angle: float) -> float:
	return summit.radius_at(angle) - lake.radius_at(angle)


## How deep the point lies in the lake's lava, world units: positive in it, negative on
## the rim, the capes and the anchors. Floating islands are not counted (lava_depth_at).
func lava_depth(point: Vector2) -> float:
	var ground := -lake.signed_distance(point)
	if ground > 600.0:
		return -ground
	for cape in capes:
		ground = smooth_max(ground, cape.signed_distance(point), CAPE_BLEND)
	for isle in isles:
		if isle.moving():
			break
		ground = maxf(ground, isle.depth_at(point, 0.0))
	return -ground


## The same with the floating islands as they are at `time` (sunk ones count less).
func lava_depth_at(point: Vector2, time: float) -> float:
	var depth := lava_depth(point)
	if depth <= 0.0:
		return depth
	for isle in isles:
		if isle.moving():
			depth = minf(depth, -isle.depth_at(point, time))
	return depth


## The floating island under the point at `time` (it carries whoever stands on it), or
## null. Ground past its edge by `margin` counts.
func carrier_at(point: Vector2, time: float, margin: float = EDGE_TOLERANCE) -> Isle:
	for isle in isles:
		if isle.moving() and isle.depth_at(point, time) > -margin:
			return isle
	return null


## Any island under the point (anchors too), or null.
func isle_at(point: Vector2, time: float, margin: float = 0.0) -> Isle:
	for isle in isles:
		if isle.depth_at(point, time) > -margin:
			return isle
	return null


func on_island(point: Vector2, margin: float = 0.0) -> bool:
	return isle_at(point, now, margin) != null


## The geyser whose mouth is under the point (`margin` beyond it), or null.
func geyser_at(point: Vector2, margin: float = 0.0) -> Geyser:
	for geyser in geysers:
		if point.distance_to(geyser.position) < geyser.radius + margin:
			return geyser
	return null


## Standing ground: on the summit, off the lava (anchors and capes count), out of the
## geysers' mouths; `margin` to spare.
func is_open_ground(point: Vector2, margin: float = 0.0) -> bool:
	if rim_depth(point) < margin:
		return false
	if lava_depth(point) > -margin:
		return false
	return geyser_at(point, margin) == null


## Where a hopper may come down: firm ground, out of fresh lava.
func is_safe_landing(point: Vector2) -> bool:
	if not is_open_ground(point, 22.0):
		return false
	for area in fresh_lava:
		if point.distance_to(Vector2(area.x, area.y)) < area.z + 16.0:
			return false
	return true


## Smooth maximum: rounds the corner where two shapes meet over about `k`.
static func smooth_max(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return maxf(a, b) + h * h * k * 0.25


## Edge-to-edge gap between two islands at `time` (approximate for near-round shapes).
static func isle_gap(a: Isle, b: Isle, time: float) -> float:
	var pa := a.position_at(time)
	var pb := b.position_at(time)
	var offset := pb - pa
	var distance := offset.length()
	var angle := offset.angle()
	return distance - a.shape.radius_at(angle) - b.shape.radius_at(angle + PI)


## Gap between an island at `time` and a cape's tip (approximate).
static func cape_gap(isle: Isle, cape: Cape, time: float) -> float:
	var at := isle.position_at(time)
	var axis := cape.tip - cape.base
	var t := clampf((at - cape.base).dot(axis) / axis.length_squared(), 0.0, 1.0)
	var closest := cape.base + axis * t
	var toward := at.direction_to(closest)
	return at.distance_to(closest) - cape.width_at(t) - isle.shape.radius_at(toward.angle())
