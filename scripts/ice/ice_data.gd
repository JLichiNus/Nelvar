class_name NelvarIceData
extends RefCounted
## The ice valley: a snowy plain ringed by snowy mountains. Frozen lakes lie in it with
## patches of thin ice and creatures frozen under them; crevasses cut the snow from the
## mountain foot, crossed by snow bridges; trodden trails join the clearings; pines under
## snow, dead trees, rocks with snow caps, drifts, blocks of ice and petrified creatures
## stand between them. NelvarIceGenerator builds it; the ground shader, NelvarIcePainter
## and NelvarFrostPainter draw it.
##
## There are no walls but the mountain foot: the lakes are walked on (and slid on), a
## step into a crevasse or an open hole is a fall. Holes are broken during play
## (NelvarIceMain keeps `holes`); the queries below see them, so hoppers keep out of them
## too.

## World units per art pixel, as on the other maps.
const PIXEL := NelvarEarthData.PIXEL
## Grip of the ice: how fast the player speeds up and slows down there (snow is 1).
const ICE_GRIP := 0.15
## A hole is open water, then slush, until this share of its freezing; then thin ice.
const SLUSH_END := 0.8
## Safe ground (where a fall brings the player back) keeps this much from any danger.
const SAFE_MARGIN := 18.0

## The last six are the ice cave's (NelvarCaveData): the valley never makes them.
enum Kind { PINE, DEAD_TREE, ROCK, STATUE, DRIFT, ICE_BLOCK, DRY_GRASS, SHRUB,
	ICE_STONE, CRYSTAL, STALAGMITE, BONES, EMBEDDED, VENT }
## What lies under a point (ice_at). The cave adds bare stone, melting ice and open water.
enum Surface { SNOW, ICE, THIN, STONE, MELT, WATER }
## Looks of a creature frozen into a lake. The cave adds the winged and the crawler.
enum Creature { BEAST, FISH, SERPENT, WINGED, CRAWLER }
## What a step leads into (fall_kind): nothing, a crack, the water, a chasm (the cave).
enum Fall { NONE, CREVASSE, WATER, CHASM }
## Looks of a block of ice (Thing.variant of Kind.ICE_BLOCK): one block, a pressure ridge.
enum Block { CHUNK, RIDGE }


## A frozen lake and the patches of thin ice in it.
class Lake:
	var shape := NelvarEarthData.Radial.new()
	var thin: Array[NelvarEarthData.Radial] = []


## Where snow has drifted over a crevasse thick enough to walk across: `half_length`
## either way along the crevasse from `along` (its running length).
class Bridge:
	var center := Vector2.ZERO
	## The crevasse's direction there.
	var direction := Vector2.RIGHT
	var along := 0.0
	var half_length := 46.0


## A crack in the snow: a bending centre line whose half width changes along it. It runs
## from under the mountains into the valley, or branches off another crevasse.
class Crevasse:
	var points := PackedVector2Array()
	## Half width at each point.
	var half_widths := PackedFloat32Array()
	var bridges: Array[Bridge] = []
	## The crevasse this one branches off (-1: it starts at the mountain foot).
	var parent := -1
	## Running length at each point.
	var lengths := PackedFloat32Array()

	func measure() -> void:
		lengths.resize(points.size())
		var total := 0.0
		for i in points.size():
			if i > 0:
				total += points[i - 1].distance_to(points[i])
			lengths[i] = total

	func length() -> float:
		return lengths[lengths.size() - 1] if not lengths.is_empty() else 0.0

	func widest() -> float:
		var best := 0.0
		for value in half_widths:
			best = maxf(best, value)
		return best

	func point_at(along: float) -> Vector2:
		var i := _segment_at(along)
		var span := maxf(0.0001, lengths[i + 1] - lengths[i])
		return points[i].lerp(points[i + 1], clampf((along - lengths[i]) / span, 0.0, 1.0))

	func direction_at(along: float) -> Vector2:
		var i := _segment_at(along)
		return points[i].direction_to(points[i + 1])

	func half_width_at(along: float) -> float:
		var i := _segment_at(along)
		var span := maxf(0.0001, lengths[i + 1] - lengths[i])
		return lerpf(half_widths[i], half_widths[i + 1], clampf((along - lengths[i]) / span, 0.0, 1.0))

	func _segment_at(along: float) -> int:
		for i in range(1, lengths.size()):
			if lengths[i] >= along:
				return i - 1
		return lengths.size() - 2

	## Depth into the crevasse from the centre line `distance` away whose closest point
	## lies `along` it, without the bridges: positive in the crack.
	func raw_depth(distance: float, along: float) -> float:
		return half_width_at(along) - distance

	## The same with the bridges: on a bridge it is ground (negative, by how far it is
	## to the bridge's end).
	func depth_at(distance: float, along: float) -> float:
		var depth := raw_depth(distance, along)
		for bridge in bridges:
			var off := absf(along - bridge.along)
			if off < bridge.half_length + 48.0:
				depth = minf(depth, off - bridge.half_length)
		return depth


## A creature frozen into a lake, seen through the ice. Some follow the player with an
## eye while they stand over them.
class Frozen:
	var id := 0
	var lake := 0
	var position := Vector2.ZERO
	## Half the length of the body.
	var radius := 40.0
	var variant := Creature.BEAST
	var appearance_seed := 0
	var eye := false
	var facing_left := false
	## The eye opens this much further off (the cave's creatures deep in a wall).
	var reach := 0.0
	## Drifting under melting ice: a loop of radius x, one round in y seconds, starting
	## at phase z. Zero: frozen in place.
	var drift := Vector3.ZERO

	## Where it is after `time` seconds (it only moves while drifting).
	func position_at(time: float) -> Vector2:
		if drift.x <= 0.0:
			return position
		var angle := drift.z + TAU * time / maxf(drift.y, 1.0)
		return position + Vector2(cos(angle), sin(angle) * 0.6) * drift.x


## A hole broken in thin ice during play: open water, then slush, then thin ice again.
class Hole:
	var center := Vector2.ZERO
	var radius := 40.0
	## 0 just broken, 1 frozen over again.
	var freeze := 0.0

	func is_open() -> bool:
		return freeze < SLUSH_END


## Anything standing in the valley. The position is the ground origin: it drives
## Y-sorting and the collider's centre.
class Thing:
	var id := 0
	var kind := Kind.ROCK
	## Look variant.
	var variant := 0
	var position := Vector2.ZERO
	## Trees: trunk radius. Others: half-width of the footprint.
	var radius := 16.0
	## Trees: reach of the branches and total height.
	var size := Vector2.ZERO
	var solid := false
	var appearance_seed := 0
	## Pines: deep snow on the branches. Rocks: a big cap. Statues: facing left.
	## Shrubs: berries. Ice blocks: out on a lake.
	var accent := false

	## Collision ellipse half-axes of solid things (trees use a circle).
	func footprint() -> Vector2:
		match kind:
			Kind.ROCK:
				return Vector2(radius, radius * 0.56)
			Kind.STATUE:
				return Vector2(radius * 1.45, radius * 0.62)
			Kind.DRIFT:
				return Vector2(radius, radius * 0.42)
			Kind.ICE_BLOCK, Kind.ICE_STONE, Kind.VENT, Kind.STALAGMITE:
				return Vector2(radius, radius * 0.6)
			Kind.CRYSTAL:
				return Vector2(radius, radius * 0.55)
			Kind.EMBEDDED:
				return Vector2(radius, radius * 0.45)
		return Vector2(radius, radius)

	## Distance used to keep things apart: the larger half-axis of the footprint.
	func spread() -> float:
		var axes := footprint()
		return maxf(axes.x, axes.y)

	func crown_center() -> Vector2:
		return position + Vector2(0.0, -size.y * 0.56)

	func crown_axes() -> Vector2:
		return Vector2(size.x, size.y * 0.42)

	## True when the point lies under this pine's branches and behind it (so they would
	## hide whatever stands there).
	func crown_hides(point: Vector2, margin: float = 0.0) -> bool:
		if kind != Kind.PINE or point.y >= position.y:
			return false
		return ((point - crown_center()) / (crown_axes() + Vector2.ONE * margin)).length_squared() < 1.0

	func is_tree() -> bool:
		return kind == Kind.PINE or kind == Kind.DEAD_TREE

	func is_plant() -> bool:
		return kind == Kind.DRY_GRASS or kind == Kind.SHRUB


var world_seed := 0
## The walkable valley: the mountain foot is its outline.
var valley := NelvarEarthData.Radial.new()
var boundary := PackedVector2Array()
var lakes: Array[Lake] = []
var lake_polygons: Array[PackedVector2Array] = []
var crevasses: Array[Crevasse] = []
var trails: Array[NelvarEarthData.Trail] = []
var clearings: Array[NelvarEarthData.Clearing] = []
var things: Array[Thing] = []
var frozen: Array[Frozen] = []
## Fields of wind-blown snow: centre and radius (z). The floor shows them.
var snow_banks: Array[Vector3] = []
## The rows of peaks and the plateau's crags and boulders round the valley
## (NelvarEarthData.Thing, kind PEAK: NelvarFrostPainter paints them).
var peaks: Array[NelvarEarthData.Thing] = []
var spawn_position := Vector2.ZERO
## Holes broken in the thin ice so far (NelvarIceMain keeps them).
var holes: Array[Hole] = []
## Blizzards over the valley now: centre (x, y), radius (z), strength (w). NelvarIceMain
## keeps them; hoppers jump a little shorter inside.
var storms: Array[Vector4] = []

const _GRID := 192.0
const _CELL := 128.0
## Crevasse segments are listed this far round their crack, so crevasse_depth() is
## exact there.
const _CREVASSE_REACH := 180.0
const _FAR := -1000.0
var _solid_grid := {}
## Cell -> trail segments [a, b, half width] passing near it.
var _trail_grid := {}
## Cell -> crevasse segments [crevasse index, segment index].
var _crevasse_grid := {}


func count(kind: Kind) -> int:
	var total := 0
	for thing in things:
		if thing.kind == kind:
			total += 1
	return total


func bridge_count() -> int:
	var total := 0
	for crevasse in crevasses:
		total += crevasse.bridges.size()
	return total


# --- What lies under a point ------------------------------------------------------

## Signed distance into the nearest lake: positive on its ice, -1000 far from any.
func lake_depth(point: Vector2) -> float:
	var best := _FAR
	for lake in lakes:
		if point.distance_squared_to(lake.shape.center) > pow(lake.shape.reach() + 400.0, 2.0):
			continue
		best = maxf(best, lake.shape.signed_distance(point))
	return best


## Index of the lake whose ice the point is on, -1 on snow.
func lake_at(point: Vector2) -> int:
	for i in lakes.size():
		if lakes[i].shape.signed_distance(point) > 0.0:
			return i
	return -1


## Signed distance into the nearest patch of thin ice: positive on it, -1000 far away.
func thin_depth(point: Vector2) -> float:
	var best := _FAR
	for lake in lakes:
		if point.distance_squared_to(lake.shape.center) > pow(lake.shape.reach() + 200.0, 2.0):
			continue
		for patch in lake.thin:
			best = maxf(best, patch.signed_distance(point))
	return best


## Snow, ice or thin ice (Surface). A hole, open or frozen over again, is thin ice.
func ice_at(point: Vector2) -> int:
	if lake_depth(point) <= 0.0:
		return Surface.SNOW
	if thin_depth(point) > 0.0:
		return Surface.THIN
	for hole in holes:
		if point.distance_squared_to(hole.center) < hole.radius * hole.radius:
			return Surface.THIN
	return Surface.ICE


## How well the ground holds: 1 on snow, ICE_GRIP on ice.
func grip_at(point: Vector2) -> float:
	return 1.0 if lake_depth(point) <= 0.0 else ICE_GRIP


## Depth into a crevasse without the bridges (x) and with them (y): positive in the
## crack, negative on the snow (how far to the crack within a couple of hundred units,
## -1000 further away). A bridge is snow in y only.
func crevasse_sample(point: Vector2) -> Vector2:
	var raw := _FAR
	var bridged := _FAR
	# Each crevasse by its nearest segment: its bridges cut it along its length.
	var nearest := {}
	for entry: Vector2i in _crevasse_grid.get(_cell(point), []):
		var crevasse := crevasses[entry.x]
		var a := crevasse.points[entry.y]
		var b := crevasse.points[entry.y + 1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := point.distance_to(closest)
		var known: Variant = nearest.get(entry.x)
		if known == null or (known as Vector2).x > distance:
			nearest[entry.x] = Vector2(distance, crevasse.lengths[entry.y] + a.distance_to(closest))
	for c: int in nearest:
		var found: Vector2 = nearest[c]
		raw = maxf(raw, crevasses[c].raw_depth(found.x, found.y))
		bridged = maxf(bridged, crevasses[c].depth_at(found.x, found.y))
	return Vector2(raw, bridged)


## Depth into a crevasse: positive in the crack, negative on the snow and on a bridge.
func crevasse_depth(point: Vector2) -> float:
	return crevasse_sample(point).y


## Depth into an open hole (water or slush): positive in it, -1000 far from any.
func hole_depth(point: Vector2) -> float:
	var best := _FAR
	for hole in holes:
		if hole.is_open():
			best = maxf(best, hole.radius - point.distance_to(hole.center))
	return best


## Ground nobody can stand on: the mountains, a crevasse or an open hole (with `margin`
## to spare). The ice of the lakes is ground.
func is_open_ground(point: Vector2, margin: float = 0.0) -> bool:
	if valley.signed_distance(point) < margin:
		return false
	if crevasse_depth(point) > -margin:
		return false
	return hole_depth(point) < -margin


## Where a hopper may come down (NelvarHopper asks before it jumps): not in a crevasse
## or a hole, and not on thin ice.
func is_safe_landing(point: Vector2) -> bool:
	return is_open_ground(point, 22.0) and thin_depth(point) < -16.0 and hole_depth(point) < -30.0


## Snow lies here (marks show only on it): off the ice and out of the crevasses.
func is_snow(point: Vector2) -> bool:
	return lake_depth(point) < -4.0 and crevasse_sample(point).x < -6.0 and valley.signed_distance(point) > 0.0


## What a step onto the point leads into (Fall): a crevasse, an open hole, nothing.
## `margin`: how far in it must be (hoppers die 6 in).
func fall_kind(point: Vector2, margin: float = 0.0) -> int:
	if crevasse_depth(point) > margin:
		return Fall.CREVASSE
	if hole_depth(point) > margin:
		return Fall.WATER
	return Fall.NONE


## Ground a fall brings the player back to: snow away from the ice, the crevasses and
## the mountains.
func is_safe_spot(point: Vector2) -> bool:
	return lake_depth(point) < -SAFE_MARGIN \
		and crevasse_depth(point) < -(NelvarPlayer.BODY_RADIUS + SAFE_MARGIN) \
		and valley.signed_distance(point) > NelvarPlayer.BODY_RADIUS + 4.0


## Points the creatures under the ice move round with the parallax (NelvarIceDepths):
## Frozen.lake indexes them. Here the lakes' centres.
func depth_anchors() -> PackedVector2Array:
	var anchors := PackedVector2Array()
	for lake in lakes:
		anchors.append(lake.shape.center)
	return anchors


## How hard a blizzard blows here, 0..1.
func storm_at(point: Vector2) -> float:
	var best := 0.0
	for storm in storms:
		var distance := point.distance_to(Vector2(storm.x, storm.y)) / maxf(storm.z, 1.0)
		best = maxf(best, storm.w * (1.0 - smoothstep(0.55, 1.0, distance)))
	return best


## Hoppers jump a little shorter in a blizzard (NelvarHopper asks).
func jump_scale_at(point: Vector2) -> float:
	return 1.0 - 0.15 * storm_at(point)


## Free ground for a body of `radius`: in the valley, out of crevasses and holes, clear
## of trunks, rocks and other solid things. The enemy spawner uses it too.
func has_clearance(point: Vector2, radius: float) -> bool:
	if not is_open_ground(point, radius):
		return false
	var cell := Vector2i((point / _GRID).floor())
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			for thing: Thing in _solid_grid.get(Vector2i(x, y), []):
				if ((point - thing.position) / (thing.footprint() + Vector2.ONE * radius)).length_squared() < 1.0:
					return false
	return true


# --- Trails --------------------------------------------------------------------------

func distance_to_trails(point: Vector2) -> float:
	var best := INF
	for trail in trails:
		best = minf(best, NelvarEarthData.trail_distance(trail, point))
	return best


## Like distance_to_trails, but only sees trails within about a hundred units (INF
## further away); fast, for placement checks.
func trail_clearance(point: Vector2) -> float:
	var best := INF
	for segment: Array in _trail_grid.get(_cell(point), []):
		var closest := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
		best = minf(best, point.distance_to(closest) - segment[2])
	return best


# --- Indexes ---------------------------------------------------------------------------

func _cell(point: Vector2) -> Vector2i:
	return Vector2i((point / _CELL).floor())


func index_trails() -> void:
	_trail_grid.clear()
	for trail in trails:
		for i in trail.points.size() - 1:
			var a := trail.points[i]
			var b := trail.points[i + 1]
			var from := _cell(a.min(b)) - Vector2i.ONE
			var to := _cell(a.max(b)) + Vector2i.ONE
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var key := Vector2i(x, y)
					if not _trail_grid.has(key):
						_trail_grid[key] = []
					_trail_grid[key].append([a, b, trail.half_width])


## Lists every crevasse segment in the cells round its crack (crevasses measured first).
func index_crevasses() -> void:
	_crevasse_grid.clear()
	for c in crevasses.size():
		var crevasse := crevasses[c]
		var reach := Vector2.ONE * (crevasse.widest() + _CREVASSE_REACH)
		for i in crevasse.points.size() - 1:
			var a := crevasse.points[i]
			var b := crevasse.points[i + 1]
			var from := _cell(a.min(b) - reach)
			var to := _cell(a.max(b) + reach)
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var key := Vector2i(x, y)
					if not _crevasse_grid.has(key):
						_crevasse_grid[key] = []
					_crevasse_grid[key].append(Vector2i(c, i))


## The two edges of a crevasse as lines (F3 and the tests). World units.
static func crevasse_edges(crevasse: Crevasse) -> Array[PackedVector2Array]:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var along := 0.0
	var total := crevasse.length()
	while true:
		var point := crevasse.point_at(along)
		var a := crevasse.point_at(maxf(0.0, along - 14.0))
		var b := crevasse.point_at(minf(total, along + 14.0))
		var side := a.direction_to(b).orthogonal() * crevasse.half_width_at(along)
		left.append(point + side)
		right.append(point - side)
		if along >= total:
			break
		along = minf(total, along + 16.0)
	return [left, right]


## Called once the things are final: numbers them and indexes the solid ones.
func finish() -> void:
	index_trails()
	index_crevasses()
	for i in frozen.size():
		frozen[i].id = i
	_solid_grid.clear()
	for i in things.size():
		var thing := things[i]
		thing.id = i
		if not thing.solid:
			continue
		var reach := thing.spread()
		var from := Vector2i(((thing.position - Vector2.ONE * reach) / _GRID).floor())
		var to := Vector2i(((thing.position + Vector2.ONE * reach) / _GRID).floor())
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var key := Vector2i(x, y)
				if not _solid_grid.has(key):
					_solid_grid[key] = []
				_solid_grid[key].append(thing)
