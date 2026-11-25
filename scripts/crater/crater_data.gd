class_name NelvarCraterData
extends NelvarFireData
## The volcano (Огонь 2): the top of one huge mountain. A broad rim of rock runs round
## the crater; the crater is a lake of lava filled almost to the brim, with the vent in
## its middle. Beyond the rim's outer edge is a sheer drop into clouds of ash far below;
## the camera, looking down from the south, sees the mountain's front slope under the
## southern edge.
##
## Floes of magma crust of every size and shape cover much of the lake, a step apart
## from the shore to the vent's moat; they sway together on one slow swell, hold whoever
## walks on them and carry them along. Some of them sink now and then (they warn first)
## and come up again red-hot; their place and their sinking depend on the time only, so
## every layout is reproducible.
##
## Nothing here is a wall. The lava and the edge are falls: a step over either holds for
## a moment (COYOTE_TIME), then the player goes down.
##
## NelvarCraterGenerator builds it; crater_ground.gdshader draws the same geometry: the
## lake and the capes are computed the same way there (lava_depth), the summit's edge is
## read from the same table of radii.

## A step over the lava or the edge holds this long (seconds) before it is a fall.
const COYOTE_TIME := 0.12
## Ground reaches this far past a floe's drawn edge (the body overhangs a little).
const EDGE_TOLERANCE := 6.0
## How round the capes meet the shore (world units).
const CAPE_BLEND := 48.0
## A gap this wide is crossed at a run (the run covers about 54 in COYOTE_TIME).
const RUN_GAP := 44.0
## Floes never come closer than this to each other.
const MIN_GAP := 8.0
## Floes: samples of an outline for floe_gap, the cells they are filed by, and how far
## past a floe's reach a query still finds it.
const FLOE_GAP_SAMPLES := 48
const FLOE_CELL := 256.0
const FLOE_QUERY_MARGIN := 80.0
## Sinking: the floe comes up red-hot (RISE), cools (COOL); warns (WARN) and goes down
## (DESCENT) before its time under.
const RISE := 1.2
const COOL := 2.0
const WARN := 3.0
const DESCENT := 1.2


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


## A tongue of rock from the shore into the lake, narrowing to a round tip.
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


## A floe of magma crust swaying round its own place. Its shape lies round that place.
class Isle:
	var id := 0
	var shape := NelvarEarthData.Radial.new()
	var center := Vector2.ZERO
	## Its sway round `center`: reach on x and y, radians per second on each, phases.
	var drift := Vector4.ZERO
	var drift_phase := Vector2.ZERO
	var outline := PackedVector2Array()
	var radii := PackedFloat32Array()
	## Sinking by itself: seconds per cycle (0: never), where it starts, time under.
	var sink_period := 0.0
	var sink_phase := 0.0
	var sink_under := 6.0
	var appearance_seed := 0
	## Smallest and largest radius of the shape.
	var inner := 0.0
	var outer := 0.0

	func position_at(time: float) -> Vector2:
		return center + Vector2(drift.x * sin(drift.z * time + drift_phase.x),
			drift.y * sin(drift.w * time + drift_phase.y))

	func sinks() -> bool:
		return sink_period > 0.0

	## Furthest a floe strays from its place.
	func drift_reach() -> float:
		return Vector2(drift.x, drift.y).length()

	## The outline sampled once (FLOE_GAP_SAMPLES round its place), for floe_gap.
	func tabulate() -> void:
		outline.resize(FLOE_GAP_SAMPLES)
		radii.resize(FLOE_GAP_SAMPLES)
		for i in FLOE_GAP_SAMPLES:
			var angle := TAU * i / FLOE_GAP_SAMPLES
			radii[i] = shape.radius_at(angle)
			outline[i] = Vector2.from_angle(angle) * radii[i]

	## The shape's radius read from the table.
	func table_radius(angle: float) -> float:
		var t := fposmod(angle, TAU) / TAU * FLOE_GAP_SAMPLES
		var i := int(t) % FLOE_GAP_SAMPLES
		return lerpf(radii[i], radii[(i + 1) % FLOE_GAP_SAMPLES], t - floorf(t))

	## How far under it is, 0..1: the lava eats it from the edge inwards.
	func sink_at(time: float) -> float:
		return _cycle(time).x

	## 0..1 in the seconds before it goes down by itself.
	func warn_at(time: float) -> float:
		return _cycle(time).y

	## 1 as it comes up red-hot, 0 once cooled.
	func hot_at(time: float) -> float:
		return _cycle(time).z

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
var geysers: Array[Geyser] = []
## Patches of boiling lava: centre and radius (z).
var boils: Array[Vector3] = []
## Floes of magma crust.
var floes: Array[Isle] = []
## Floes by cell (index_floes).
var _floe_cells := {}
## Broad places of the rim: direction and angular half-width.
var terraces: Array[Vector2] = []
## Fresh lava on the rim (NelvarCraterMain keeps it current): centre and radius (z).
var fresh_lava: Array[Vector3] = []
## The shared clock (NelvarCraterMain sets it each physics frame): hoppers ask where to
## land without a time.
var now := 0.0


## Positive on the summit, negative past its edge, world units.
func rim_depth(point: Vector2) -> float:
	return summit.signed_distance(point)


## How wide the rim is in a direction (from the lake's shore to the edge).
func rim_width_at(angle: float) -> float:
	return summit.radius_at(angle) - lake.radius_at(angle)


## How deep the point lies in the lake's lava, world units: positive in it, negative on
## the rim and the capes. Floes are not counted (lava_depth_at).
func lava_depth(point: Vector2) -> float:
	var ground := -lake.signed_distance(point)
	if ground > 600.0:
		return -ground
	for cape in capes:
		ground = smooth_max(ground, cape.signed_distance(point), CAPE_BLEND)
	return -ground


## The same with the floes as they are at `time` (sunk ones count less).
func lava_depth_at(point: Vector2, time: float) -> float:
	var depth := lava_depth(point)
	if depth <= 0.0:
		return depth
	for floe: Isle in _floes_near(point):
		depth = minf(depth, -floe.depth_at(point, time))
	return depth


## The floe under the point at `time` (it carries whoever stands on it), or null. Ground
## past its edge by `margin` counts.
func carrier_at(point: Vector2, time: float, margin: float = EDGE_TOLERANCE) -> Isle:
	for floe: Isle in _floes_near(point):
		if floe.depth_at(point, time) > -margin:
			return floe
	return null


## Files the floes by the cells their sway can reach, with room for the margins asked of
## carrier_at and lava_depth_at.
func index_floes() -> void:
	_floe_cells.clear()
	for floe in floes:
		var reach := floe.outer + floe.drift_reach() + FLOE_QUERY_MARGIN
		var lo := ((floe.center - Vector2.ONE * reach) / FLOE_CELL).floor()
		var hi := ((floe.center + Vector2.ONE * reach) / FLOE_CELL).floor()
		for y in range(int(lo.y), int(hi.y) + 1):
			for x in range(int(lo.x), int(hi.x) + 1):
				var key := Vector2i(x, y)
				if not _floe_cells.has(key):
					_floe_cells[key] = []
				_floe_cells[key].append(floe)


func _floes_near(point: Vector2) -> Array:
	return _floe_cells.get(Vector2i((point / FLOE_CELL).floor()), [])


## The geyser whose mouth is under the point (`margin` beyond it), or null.
func geyser_at(point: Vector2, margin: float = 0.0) -> Geyser:
	for geyser in geysers:
		if point.distance_to(geyser.position) < geyser.radius + margin:
			return geyser
	return null


## Standing ground: on the summit, off the lava (capes count), out of the
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


## Narrowest lava between two floes at `time` (tabulated), measured from each one's
## outline along rays from the other's place: never less than the true gap, exact in
## sign (negative once they overlap). Fit for long and lobed shapes.
static func floe_gap(a: Isle, b: Isle, time: float) -> float:
	var offset := b.position_at(time) - a.position_at(time)
	var best := INF
	for i in FLOE_GAP_SAMPLES:
		var p := a.outline[i] - offset
		best = minf(best, p.length() - b.table_radius(p.angle()))
		var q := b.outline[i] + offset
		best = minf(best, q.length() - a.table_radius(q.angle()))
	return best


## Most two floes on the same swell move apart or together.
static func sway_between(a: Isle, b: Isle) -> float:
	var d := (a.drift_phase - b.drift_phase) * 0.5
	return Vector2(2.0 * a.drift.x * absf(sin(d.x)), 2.0 * a.drift.y * absf(sin(d.y))).length()
