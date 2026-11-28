class_name NelvarThicketData
extends NelvarEarthData
## The giant forest, Земля 2: the floor of a forest of giants with the player the size of
## a beetle. A ring of trunks wider than the screen closes the floor in (on the south side
## a low bank of roots instead, so nothing stands between the camera and the floor);
## inside stand a few more giants with skirts of roots round them. Clearings in the
## crowns are the arenas, ant trails join them; ponds with lily pads and leaves drifting
## round them as rafts; one fallen giant with a tunnel through it.
##
## Built on the valley's data (NelvarEarthData): the floor's outline is its Radial
## `valley`, the trails, clearings and ponds are its own, the things are its Things (the
## kinds of this map are at the end of Kind), so NelvarEarthThing, the spawner
## and the valley's painter work with it unchanged.
##
## NelvarThicketGenerator builds it; the floor shader, NelvarGiantPainter and
## NelvarThicketPainter draw it. Everything here is static except the few runtime states
## the map keeps on it (the traps, the rafts sinking, the pits).

## A step into the water holds this long (seconds) before it is a fall.
const COYOTE_TIME := 0.12
## Ground reaches this far past a pad's or a raft's drawn edge.
const EDGE_TOLERANCE := 6.0
## A gap this wide is crossed at a run (a run covers about 54 in COYOTE_TIME).
const RUN_GAP := 44.0
## Safe ground keeps this much from water, loose earth, pits, resin and traps.
const SAFE_MARGIN := 18.0
## Roots are sampled this often along their line; their sprites are cut this long.
const ROOT_STEP := 16.0
const PIECE := 64.0
## How far the sun of a clearing spills under the crowns.
const SUN_EDGE := 120.0
## Smallest raft that holds a standing player; smaller ones sink under them.
const SMALL_RAFT := 140.0
## A pit opening under the player on loose earth.
const PIT_RADIUS := 46.0
const MAX_PITS := 24
## Damp ground round the pond shores, the trunks' feet and the puffballs.
const DAMP_POND := 220.0
const DAMP_TRUNK := 170.0
const DAMP_SPOT := 160.0
## Light map channels encode signed distances this many units per level step.
const SDF_SCALE := 64.0

enum Wood { OAK, PINE, BIRCH, DEAD }
## Parts of a root along it: a wall higher than the player, a low one, lifted into an
## arch (free ground under it), dipped under a trail (no collision).
enum Part { HIGH, LOW, ARCH, PASS }
enum TrapState { OPEN, TRIGGERED, CLOSED, OPENING }

const TREE_NAMES: Array[String] = ["дуб", "сосна", "берёза", "сухостой"]


## A trunk wider than the screen: its collision is the circle of its base.
class Giant:
	var id := 0
	var center := Vector2.ZERO
	var radius := 300.0
	var species := Wood.OAK
	## Seen height of the trunk (world units) before it melts into the dark of the crown.
	var height := 900.0
	## Stands in the ring round the floor (outside the boundary).
	var ring := false
	## Oaks: acorns fall within this distance of the centre (not on clearings).
	var crown := 850.0
	var appearance_seed := 0
	var roots: Array[int] = []

	func edge_distance(point: Vector2) -> float:
		return point.distance_to(center) - radius


## A root: a line of samples from under its trunk outwards.
class Root:
	var id := 0
	var giant := 0
	## A branch: the root it grows from (-1 for a main root), and the sample it forks at.
	var parent := -1
	var fork := 0
	var points := PackedVector2Array()
	## Full width of the root at each sample (world units).
	var widths := PackedFloat32Array()
	## Height of its top above the ground at each sample, art pixels.
	var heights := PackedFloat32Array()
	## Free ground under it at each sample (an arch), art pixels.
	var lifts := PackedFloat32Array()
	var parts := PackedInt32Array()
	var appearance_seed := 0

	func length() -> float:
		return ROOT_STEP * maxf(0.0, points.size() - 1)

	func count(part: int) -> int:
		var total := 0
		for p in parts:
			if p == part:
				total += 1
		return total


## A lily pad: never sinks, holds the player.
class Lily:
	var id := 0
	var pond := 0
	var center := Vector2.ZERO
	var radius := 100.0
	var appearance_seed := 0


## A fallen leaf drifting round its pond on a slow loop; where it is depends on the time
## only. It never turns.
class Raft:
	var id := 0
	var pond := 0
	var length := 160.0
	var width := 72.0
	var angle := 0.0
	var period := 90.0
	var phase := 0.0
	var appearance_seed := 0
	## Runtime: how far under it is now, 0..1 (small ones sink under a standing player).
	var sink := 0.0
	var _loop: PondLoop

	func small() -> bool:
		return length < SMALL_RAFT

	func position_at(time: float) -> Vector2:
		return _loop.point_at(phase + TAU * time / period)

	## Positive inside the leaf: how far the point is from its edge along the ray from the
	## leaf's middle (never less than the true distance outside it).
	func depth_at(point: Vector2, time: float) -> float:
		var local := (point - position_at(time)).rotated(-angle)
		var axes := Vector2(length, width) * 0.5
		var q := (local / axes).length()
		if q < 0.0001:
			return minf(axes.x, axes.y)
		return local.length() * (1.0 / q - 1.0)

	func holds(point: Vector2, time: float, tolerance: float) -> bool:
		return sink < 0.5 and depth_at(point, time) > -tolerance

	## Furthest the leaf reaches from its middle along `direction`.
	func support(direction: Vector2) -> float:
		var t := Vector2.from_angle(angle)
		var n := t.orthogonal()
		return Vector2(length * 0.5 * direction.dot(t), width * 0.5 * direction.dot(n)).length()


## The loop the rafts of a pond follow: a radius per direction round the pond's middle.
class PondLoop:
	var center := Vector2.ZERO
	var radii := PackedFloat32Array()

	func radius_at(angle: float) -> float:
		var count := radii.size()
		var t := fposmod(angle, TAU) / TAU * count
		var i := int(t)
		return lerpf(radii[i % count], radii[(i + 1) % count], t - float(i))

	func point_at(angle: float) -> Vector2:
		return center + Vector2.from_angle(angle) * radius_at(angle)


## The fallen giant: a hollow trunk lying almost across the screen with its torn-out
## roots standing on edge at one end. Inside runs a tunnel, open at the broken end and
## through breaches in the south side.
class Fallen:
	## The axis: from the root plate to the broken end.
	var start := Vector2.ZERO
	var end := Vector2.ZERO
	## Outer half thickness and the tunnel's half width.
	var radius := 160.0
	var tunnel := 80.0
	## Along the axis from `start`: where each breach in the south side is, and its width.
	var breaches := PackedVector2Array()
	## The root plate: its middle, half width across the axis, half thickness along it.
	var plate_center := Vector2.ZERO
	var plate_half := 300.0
	var plate_depth := 70.0
	var appearance_seed := 0

	func axis() -> Vector2:
		return start.direction_to(end)

	## Across the axis, towards the screen's bottom.
	func normal() -> Vector2:
		var n := axis().orthogonal()
		return n if n.y >= 0.0 else -n

	func length() -> float:
		return start.distance_to(end)

	## (along from start, across towards the south side).
	func local(point: Vector2) -> Vector2:
		var offset := point - start
		return Vector2(offset.dot(axis()), offset.dot(normal()))

	## True within the trunk's footprint (shell or tunnel), `margin` beyond it.
	func covers(point: Vector2, margin: float = 0.0) -> bool:
		var l := local(point)
		return l.x > -margin and l.x < length() + margin and absf(l.y) < radius + margin

	## True in the tunnel (inside the hollow, off its walls by `margin`).
	func in_tunnel(point: Vector2, margin: float = 0.0) -> bool:
		var l := local(point)
		return l.x > margin and l.x < length() + margin and absf(l.y) < tunnel - margin

	## True in a breach's gap through the south wall.
	func in_breach(along: float) -> bool:
		for breach in breaches:
			if absf(along - breach.x) < breach.y * 0.5:
				return true
		return false

	## True on the shell (a wall), the closed end or the root plate, `margin` beyond.
	func blocks(point: Vector2, margin: float = 0.0) -> bool:
		if plate_blocks(point, margin):
			return true
		var l := local(point)
		if l.x < -margin or l.x > length() + margin or absf(l.y) > radius + margin:
			return false
		if absf(l.y) < tunnel - margin:
			# The tunnel: the plate end is closed.
			return l.x < plate_depth + margin
		if l.y > 0.0 and in_breach(l.x) and l.x > plate_depth:
			return false
		return true

	func plate_blocks(point: Vector2, margin: float = 0.0) -> bool:
		var offset := point - plate_center
		var q := Vector2(offset.dot(axis()) / (plate_depth + margin), offset.dot(normal()) / (plate_half + margin))
		return q.length_squared() < 1.0


## A Venus flytrap lying open on the ground; its state is the map's at runtime.
class Flytrap:
	var id := 0
	var center := Vector2.ZERO
	var radius := 70.0
	## In the garden: planted in rows.
	var garden := false
	var appearance_seed := 0
	var state := TrapState.OPEN
	var timer := 0.0
	var fed := false

	func is_open() -> bool:
		return state == TrapState.OPEN or state == TrapState.TRIGGERED


## A puffball: bursts into a cloud of spores, grows back.
class Puffball:
	var id := 0
	var center := Vector2.ZERO
	var radius := 36.0
	var appearance_seed := 0
	## Runtime: seconds until it stands whole again (0: whole).
	var regrow := 0.0

	func solid() -> bool:
		return radius >= 40.0

	func whole() -> bool:
		return regrow <= 0.0


## A pool of resin at a pine's foot: one round lobe.
class Resin:
	var center := Vector2.ZERO
	var radius := 100.0
	var giant := 0


## A pit opened in loose earth (runtime; it stays till the end of the run).
class Pit:
	var center := Vector2.ZERO
	var radius := PIT_RADIUS
	var age := 0.0


## Extra things this map knows about beside the valley's: a flag for low obstacles and
## the footprints of the long ones.
class Item extends NelvarEarthData.Thing:
	## Stands on layer 6 (low obstacles): the flight and the dash pass over it.
	var low := false

	func footprint() -> Vector2:
		match kind:
			Kind.TWIG:
				return Vector2(size.x * 0.5, radius * 0.7)
			Kind.SHELL, Kind.AMBER:
				return Vector2(radius, radius * 0.75)
			Kind.ACORN:
				return Vector2(radius, radius * 0.7)
			Kind.STATUE:
				return Vector2(radius * 1.45, radius * 0.62)
			Kind.ROCK:
				return Vector2(radius, radius * 0.56)
		return Vector2(radius, radius)


var giants: Array[Giant] = []
var roots: Array[Root] = []
var lilies: Array[Lily] = []
var rafts: Array[Raft] = []
var loops: Array[PondLoop] = []
var fallen: Fallen
var flytraps: Array[Flytrap] = []
var puffballs: Array[Puffball] = []
var resin: Array[Resin] = []
var loose: Array[NelvarEarthData.Radial] = []
## Small openings in the crowns beside the clearings: (x, y, radius).
var windows: Array[Vector3] = []
var pits: Array[Pit] = []
## The clearing with the start, and the garden of flytraps (-1: none).
var start_clearing := 0
var garden := -1
## The world's bounds (the floor and the ring round it).
var bounds := Rect2()

const _ROOT_CELL := 128.0
## Cell -> [root id, sample index] of root segments passing near it.
var _root_grid := {}
const _HAZARD_CELL := 256.0
var _hazard_grid := {}


# --- Counting -----------------------------------------------------------------------

func inner_giants() -> Array[Giant]:
	var result: Array[Giant] = []
	for giant in giants:
		if not giant.ring:
			result.append(giant)
	return result


func count_trees(species: int, ring: bool = false) -> int:
	var total := 0
	for giant in giants:
		if giant.species == species and giant.ring == ring:
			total += 1
	return total


func arch_count() -> int:
	var total := 0
	for root in roots:
		var inside := false
		for part in root.parts:
			if part == Part.ARCH and not inside:
				total += 1
			inside = part == Part.ARCH
	return total


# --- The floor ----------------------------------------------------------------------------

## How much sun reaches the floor, 0 under the crowns, 1 on a clearing.
func sun_at(point: Vector2) -> float:
	var best := 0.0
	for clearing in clearings:
		var d := clearing.radius - point.distance_to(clearing.center)
		if d > -SUN_EDGE:
			best = maxf(best, smoothstep(-SUN_EDGE, SUN_EDGE * 0.5, d))
	for window in windows:
		var d := window.z - point.distance_to(Vector2(window.x, window.y))
		if d > -SUN_EDGE * 0.5:
			best = maxf(best, smoothstep(-SUN_EDGE * 0.5, SUN_EDGE * 0.25, d) * 0.8)
	return best


## Damp ground, 0..1: by the ponds, at the trunks' feet, round the puffballs and the
## fallen giant.
func damp_at(point: Vector2) -> float:
	var best := 0.0
	for pond in ponds:
		var d := -pond.signed_distance(point)
		if d < DAMP_POND:
			best = maxf(best, 1.0 - smoothstep(0.0, DAMP_POND, d))
	for giant in giants:
		var d := giant.edge_distance(point)
		if d < DAMP_TRUNK:
			best = maxf(best, (1.0 - smoothstep(0.0, DAMP_TRUNK, d)) * 0.85)
	for puffball in puffballs:
		var d := point.distance_to(puffball.center) - puffball.radius
		if d < DAMP_SPOT:
			best = maxf(best, (1.0 - smoothstep(0.0, DAMP_SPOT, d)) * 0.8)
	if fallen != null:
		var l := fallen.local(point)
		var along := maxf(0.0, maxf(-l.x, l.x - fallen.length()))
		var d := Vector2(along, maxf(0.0, absf(l.y) - fallen.radius)).length()
		if d < DAMP_SPOT:
			best = maxf(best, (1.0 - smoothstep(0.0, DAMP_SPOT, d)) * 0.9)
		var plate := point.distance_to(fallen.plate_center - fallen.axis() * (fallen.plate_depth + 90.0)) - 150.0
		if plate < DAMP_SPOT:
			best = maxf(best, 1.0 - smoothstep(0.0, DAMP_SPOT, plate))
	return best


## Signed distance into the nearest patch of loose earth (positive on it).
func loose_depth(point: Vector2) -> float:
	var best := -INF
	for patch in loose:
		if point.distance_squared_to(patch.center) > pow(patch.reach() + 200.0, 2.0):
			continue
		best = maxf(best, patch.signed_distance(point))
	return best


func is_loose(point: Vector2) -> bool:
	return loose_depth(point) > 0.0


## Signed distance into the nearest pool of resin (positive in it).
func resin_depth(point: Vector2) -> float:
	var best := -INF
	for pool in resin:
		best = maxf(best, pool.radius - point.distance_to(pool.center))
	return best


func resin_at(point: Vector2) -> bool:
	return resin_depth(point) > 0.0


## The pit under the point, if any (`margin` beyond its edge).
func pit_at(point: Vector2, margin: float = 0.0) -> Pit:
	for pit in pits:
		if point.distance_to(pit.center) < pit.radius + margin:
			return pit
	return null


## The flytrap whose mouth covers the point (`margin` beyond it).
func flytrap_at(point: Vector2, margin: float = 0.0) -> Flytrap:
	for trap: Flytrap in _hazards_near(point, "trap"):
		if point.distance_to(trap.center) < trap.radius + margin:
			return trap
	return null


func puffball_at(point: Vector2, margin: float = 0.0) -> Puffball:
	for puffball: Puffball in _hazards_near(point, "puff"):
		if point.distance_to(puffball.center) < puffball.radius + margin:
			return puffball
	return null


## The oak whose crown hangs over the point (acorns fall here), or null; never over a
## clearing.
func oak_over(point: Vector2) -> Giant:
	if sun_at(point) > 0.5:
		return null
	for giant in giants:
		if giant.species == Wood.OAK and not giant.ring and point.distance_to(giant.center) < giant.crown:
			return giant
	return null


# --- Water ----------------------------------------------------------------------------

func lily_at(point: Vector2, tolerance: float = EDGE_TOLERANCE) -> Lily:
	for lily in lilies:
		if point.distance_to(lily.center) < lily.radius + tolerance:
			return lily
	return null


## The raft holding the point at `time`, if any.
func carrier_at(point: Vector2, time: float, tolerance: float = EDGE_TOLERANCE) -> Raft:
	for raft in rafts:
		if raft.holds(point, time, tolerance):
			return raft
	return null


## True over open water at `time`: in a pond, off the pads and the rafts.
func water_at(point: Vector2, time: float, margin: float = 0.0) -> bool:
	if pond_depth(point) <= margin:
		return false
	return lily_at(point, EDGE_TOLERANCE - margin) == null and carrier_at(point, time, EDGE_TOLERANCE - margin) == null


## True when the pond can be crossed from its south shore to its north shore over the pads
## and the rafts, with no step longer than RUN_GAP, waiting on the pads (or riding a raft
## that holds) as long as it takes. Small rafts only count for the moment they pass.
static func crossable(pond: NelvarEarthData.Radial, lilies: Array[Lily], rafts: Array[Raft]) -> bool:
	if lilies.is_empty() and rafts.is_empty():
		return false
	var period := rafts[0].period if not rafts.is_empty() else 1.0
	var on_lily := PackedByteArray()
	on_lily.resize(lilies.size())
	var on_raft := PackedByteArray()
	on_raft.resize(rafts.size())
	var samples := 120
	for round_index in 3:
		for s in samples:
			var time := period * s / samples
			var now := on_raft.duplicate()
			var changed := true
			while changed:
				changed = false
				for r in rafts.size():
					if now[r] == 1:
						continue
					var reach := _shore_gap(pond, rafts[r].position_at(time), rafts[r], null) <= RUN_GAP \
						and _shore_side(pond, rafts[r].position_at(time)) > 0
					for l in lilies.size():
						if on_lily[l] == 1 and -rafts[r].depth_at(lilies[l].center, time) - lilies[l].radius <= RUN_GAP:
							reach = true
					if reach:
						now[r] = 1
						if not rafts[r].small():
							on_raft[r] = 1
						changed = true
				for l in lilies.size():
					if on_lily[l] == 1:
						continue
					var lily := lilies[l]
					var reach := _shore_gap(pond, lily.center, null, lily) <= RUN_GAP and _shore_side(pond, lily.center) > 0
					for other in lilies.size():
						if on_lily[other] == 1 and lily.center.distance_to(lilies[other].center) \
								- lily.radius - lilies[other].radius <= RUN_GAP:
							reach = true
					for r in rafts.size():
						if now[r] == 1 and -rafts[r].depth_at(lily.center, time) - lily.radius <= RUN_GAP:
							reach = true
					if reach:
						on_lily[l] = 1
						changed = true
			for l in lilies.size():
				if on_lily[l] == 1 and _shore_side(pond, lilies[l].center) < 0 \
						and _shore_gap(pond, lilies[l].center, null, lilies[l]) <= RUN_GAP:
					return true
			for r in rafts.size():
				var at := rafts[r].position_at(time)
				if now[r] == 1 and _shore_side(pond, at) < 0 and _shore_gap(pond, at, rafts[r], null) <= RUN_GAP:
					return true
	return false


## The gap between a pad or a raft (at `point`) and the shore beyond it, along the ray
## from the pond's middle.
static func _shore_gap(pond: NelvarEarthData.Radial, point: Vector2, raft: Raft, lily: Lily) -> float:
	var offset := point - pond.center
	var direction := offset.normalized() if offset.length() > 0.001 else Vector2.DOWN
	var extent := lily.radius if lily != null else raft.support(direction)
	return pond.radius_at(direction.angle()) - offset.length() - extent


## 1 on the south side of the pond, -1 on the north, 0 at the sides.
static func _shore_side(pond: NelvarEarthData.Radial, point: Vector2) -> int:
	var offset := point - pond.center
	if offset.length() < 0.001:
		return 0
	var y := offset.normalized().y
	return 1 if y > 0.5 else (-1 if y < -0.5 else 0)


# --- Giants and roots -------------------------------------------------------------------

## The giant whose trunk covers the point (`margin` beyond its bark).
func giant_at(point: Vector2, margin: float = 0.0) -> Giant:
	for giant in giants:
		if giant.edge_distance(point) < margin:
			return giant
	return null


## Distance from the point to the nearest root's flank (negative on a root), counting the
## parts in `parts` only; INF with no root within a couple of cells.
func root_clearance(point: Vector2, parts: Array = [Part.HIGH, Part.LOW, Part.ARCH]) -> float:
	var best := INF
	var cell := Vector2i((point / _ROOT_CELL).floor())
	for entry: Vector2i in _root_grid.get(cell, []):
		var root := roots[entry.x]
		var i := entry.y
		if not parts.has(root.parts[i]) and not parts.has(root.parts[i + 1]):
			continue
		var a := root.points[i]
		var b := root.points[i + 1]
		var along := b - a
		var t := clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
		var width := lerpf(root.widths[i], root.widths[i + 1], t)
		best = minf(best, point.distance_to(a + along * t) - width * 0.5)
	return best


## The part of the root under the point (-1: no root), the highest where two meet.
func root_part_at(point: Vector2, margin: float = 0.0) -> int:
	var found := -1
	var cell := Vector2i((point / _ROOT_CELL).floor())
	for entry: Vector2i in _root_grid.get(cell, []):
		var root := roots[entry.x]
		var i := entry.y
		var a := root.points[i]
		var b := root.points[i + 1]
		var along := b - a
		var t := clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
		var width := lerpf(root.widths[i], root.widths[i + 1], t)
		if point.distance_to(a + along * t) < width * 0.5 + margin:
			var part := root.parts[i] if t < 0.5 else root.parts[i + 1]
			if found < 0 or part < found:
				found = part
	return found


## The layer a root's segment stands on (NelvarProp layers): a wall where either end is
## high, low where both are low, none over an arch or under a trail.
static func segment_layer(root: Root, i: int) -> int:
	var a := root.parts[i]
	var b := root.parts[i + 1]
	if a == Part.ARCH or b == Part.ARCH or a == Part.PASS or b == Part.PASS:
		return 0
	if a == Part.HIGH or b == Part.HIGH:
		return NelvarProp.WORLD_LAYER
	return NelvarProp.LOW_OBSTACLE_LAYER


## Files the roots' segments by cell (each within a cell of its bounds).
func index_roots() -> void:
	_root_grid.clear()
	for root in roots:
		for i in root.points.size() - 1:
			var reach := maxf(root.widths[i], root.widths[i + 1]) * 0.5 + 8.0
			var a := root.points[i]
			var b := root.points[i + 1]
			var from := Vector2i(((a.min(b) - Vector2.ONE * reach) / _ROOT_CELL).floor()) - Vector2i.ONE
			var to := Vector2i(((a.max(b) + Vector2.ONE * reach) / _ROOT_CELL).floor()) + Vector2i.ONE
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var key := Vector2i(x, y)
					if not _root_grid.has(key):
						_root_grid[key] = []
					_root_grid[key].append(Vector2i(root.id, i))


func index_hazards() -> void:
	_hazard_grid.clear()
	for trap in flytraps:
		_file_hazard(trap.center, trap.radius, ["trap", trap])
	for puffball in puffballs:
		_file_hazard(puffball.center, puffball.radius, ["puff", puffball])


func _file_hazard(center: Vector2, radius: float, entry: Array) -> void:
	var reach := radius + 120.0
	var from := Vector2i(((center - Vector2.ONE * reach) / _HAZARD_CELL).floor())
	var to := Vector2i(((center + Vector2.ONE * reach) / _HAZARD_CELL).floor())
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var key := Vector2i(x, y)
			if not _hazard_grid.has(key):
				_hazard_grid[key] = []
			_hazard_grid[key].append(entry)


func _hazards_near(point: Vector2, kind: String) -> Array:
	var result := []
	for entry: Array in _hazard_grid.get(Vector2i((point / _HAZARD_CELL).floor()), []):
		if entry[0] == kind:
			result.append(entry[1])
	return result


# --- Standing, landing, spawning --------------------------------------------------------

## Solid under the point for a body of `radius`: the ring, a trunk, a wall of a root
## (high or low), the fallen giant's shell or a solid thing.
func is_blocked(point: Vector2, radius: float) -> bool:
	if valley.signed_distance(point) < radius:
		return true
	if giant_at(point, radius) != null:
		return true
	if root_clearance(point, [Part.HIGH, Part.LOW]) < radius:
		return true
	if fallen != null and fallen.blocks(point, radius):
		return true
	var cell := Vector2i((point / _GRID).floor())
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			for thing: Thing in _solid_grid.get(Vector2i(x, y), []):
				if ((point - thing.position) / (thing.footprint() + Vector2.ONE * radius)).length_squared() < 1.0:
					return true
	return false


## Free ground for a body of `radius` (the enemy spawner's question): on the floor, out of
## the water, clear of trunks, roots, the fallen giant (and its tunnel), solid things and
## every hazard.
func has_clearance(point: Vector2, radius: float) -> bool:
	if not super.has_clearance(point, radius):
		return false
	if giant_at(point, radius) != null or root_clearance(point) < radius:
		return false
	if fallen != null and fallen.covers(point, radius):
		return false
	return not _in_hazard(point, radius)


func _in_hazard(point: Vector2, margin: float) -> bool:
	if loose_depth(point) > -margin or resin_depth(point) > -margin or pit_at(point, margin) != null:
		return true
	return flytrap_at(point, margin) != null or puffball_at(point, margin) != null


## Where a fall brings the player back: firm ground well away from the water, loose
## earth, pits, resin and traps (a lily pad counts; a raft does not).
func is_safe_spot(point: Vector2) -> bool:
	var spare := NelvarPlayer.BODY_RADIUS + SAFE_MARGIN
	if valley.signed_distance(point) < spare:
		return false
	if pond_depth(point) > -spare:
		var lily := lily_at(point, 0.0)
		if lily == null or point.distance_to(lily.center) > lily.radius - spare:
			return false
	if loose_depth(point) > -SAFE_MARGIN or resin_depth(point) > -SAFE_MARGIN or pit_at(point, SAFE_MARGIN) != null:
		return false
	var trap := flytrap_at(point, SAFE_MARGIN + NelvarPlayer.BODY_RADIUS)
	return trap == null


## A hopper never jumps into the water or onto a raft, into an open trap, resin, loose
## earth or a pit, nor over a trunk, a high root or the fallen giant's shell (the middle
## of its jump is asked too).
func is_safe_landing(point: Vector2) -> bool:
	if valley.signed_distance(point) < 30.0 or pond_depth(point) > -12.0:
		return false
	if giant_at(point, 24.0) != null or root_clearance(point, [Part.HIGH]) < 22.0:
		return false
	if fallen != null and fallen.blocks(point, 22.0):
		return false
	if loose_depth(point) > -12.0 or resin_depth(point) > -12.0 or pit_at(point, 16.0) != null:
		return false
	var trap := flytrap_at(point, 16.0)
	return trap == null or not trap.is_open()


## Called once the things and hazards are final.
func finish() -> void:
	super.finish()
	index_roots()
	index_hazards()
