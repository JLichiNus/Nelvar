class_name NelvarFireData
extends RefCounted
## The fire forge: a basin of ash and basalt ringed by black ridges and volcanoes. Lava
## lakes lie in it, some with islands of black plates; lava streams run from the
## volcanoes into the lakes and are crossed where their crust has set; roads of cooled
## lava join the clearings; magma shows through fissures, and some of them erupt;
## vents smoke over yellow sulfur; burnt trees, boulders, crystals and the few plants
## that live in the heat stand between them. NelvarFireGenerator builds it; the ground
## shader, NelvarFirePainter and NelvarVolcanoPainter draw it.
##
## Lava stops whoever walks (physics layer 7, «Lava»); the flying player passes over it,
## and whoever comes down in it burns.

## World units per art pixel, as on the other maps.
const PIXEL := NelvarEarthData.PIXEL
## Physics layer 7 ("Lava"): stops the walking player; the flight passes over it.
const LAVA_LAYER := 64
const LAVA_LAYER_NUMBER := 7

enum Kind { TREE, SNAG, LOG, ROCK, CRYSTALS, VENT, EMBER_GRASS, ASH_FLOWER, SHRUB }
## Burnt trees and the one that lives in the heat.
enum Species { CHARRED, SMOULDERING, ASHEN, EMBERLEAF }
## Look of a rock (Thing.variant of Kind.ROCK): bare basalt, a cap of ash, glowing cracks.
enum Stone { PLAIN, ASHEN, EMBER }

const SPECIES_NAMES: Array[String] = ["обугленное", "тлеющее", "пепельное", "огнелист"]


## Where a lava stream's crust has set hard enough to walk over: a gap in its lava,
## `half_length` either way along the stream from `along` (its running length).
class Crossing:
	var center := Vector2.ZERO
	## The stream's direction there.
	var direction := Vector2.RIGHT
	var along := 0.0
	var half_length := 48.0


## A river of lava: a bending centre line with a half width. It runs from under a
## volcano into a lake, or from one lake into another.
class Stream:
	var points := PackedVector2Array()
	var half_width := 28.0
	var crossings: Array[Crossing] = []
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

	func point_at(along: float) -> Vector2:
		var i := _segment_at(along)
		var span := maxf(0.0001, lengths[i + 1] - lengths[i])
		return points[i].lerp(points[i + 1], clampf((along - lengths[i]) / span, 0.0, 1.0))

	func direction_at(along: float) -> Vector2:
		var i := _segment_at(along)
		return points[i].direction_to(points[i + 1])

	func _segment_at(along: float) -> int:
		for i in range(1, lengths.size()):
			if lengths[i] >= along:
				return i - 1
		return lengths.size() - 2

	## Lava depth from the centre line `distance` away whose closest point lies
	## `along` the stream: positive in the lava, negative on the ground (and on a
	## crossing, by how far it is to its end).
	func depth_at(distance: float, along: float) -> float:
		var depth := half_width - distance
		for crossing in crossings:
			var off := absf(along - crossing.along)
			if off < crossing.half_length + half_width + 8.0:
				depth = minf(depth, off - crossing.half_length)
		return depth


## A raft of black plates in a lava lake; only the flight reaches it.
class Island:
	var shape := NelvarEarthData.Radial.new()
	var lake := 0


## A crack where magma shows through the ground. An active one erupts now and then:
## it glows brighter for a moment (the warning), then throws up fire.
class Fissure:
	var points := PackedVector2Array()
	var active := false
	## Seconds between eruptions, and where in that cycle it starts.
	var period := 7.0
	var phase := 0.0
	var center := Vector2.ZERO
	var reach := 0.0


## Anything standing in the basin. The position is the ground origin: it drives
## Y-sorting and the collider's centre.
class Thing:
	var id := 0
	var kind := Kind.ROCK
	## Species for trees, look variant for other kinds.
	var variant := 0
	var position := Vector2.ZERO
	## Trees: trunk radius. Others: half-width of the footprint.
	var radius := 16.0
	## Trees: reach of the branches and total height. Logs: length.
	var size := Vector2.ZERO
	var solid := false
	var appearance_seed := 0
	## Trees: still smouldering (smoke from the top). Vents: a big one.
	var accent := false

	## Collision ellipse half-axes of solid things (trees and snags use a circle).
	func footprint() -> Vector2:
		match kind:
			Kind.ROCK:
				return Vector2(radius, radius * 0.56)
			Kind.CRYSTALS:
				return Vector2(radius, radius * 0.6)
			Kind.LOG:
				return Vector2(size.x * 0.5, radius * 0.7)
			Kind.VENT:
				return Vector2(radius, radius * 0.5)
		return Vector2(radius, radius)

	## Distance used to keep things apart: the larger half-axis of the footprint.
	func spread() -> float:
		var axes := footprint()
		return maxf(axes.x, axes.y)

	func crown_center() -> Vector2:
		return position + Vector2(0.0, -size.y * 0.66)

	func crown_axes() -> Vector2:
		return Vector2(size.x, size.y * 0.36)

	## True when the point lies under this tree's branches and behind the tree (so they
	## would hide whatever stands there).
	func crown_hides(point: Vector2, margin: float = 0.0) -> bool:
		if kind != Kind.TREE or point.y >= position.y:
			return false
		return ((point - crown_center()) / (crown_axes() + Vector2.ONE * margin)).length_squared() < 1.0

	func is_plant() -> bool:
		return kind in [Kind.EMBER_GRASS, Kind.ASH_FLOWER, Kind.SHRUB]


var world_seed := 0
## The walkable basin: the foot of the ridges is its outline.
var basin := NelvarEarthData.Radial.new()
var boundary := PackedVector2Array()
var lakes: Array[NelvarEarthData.Radial] = []
var lake_polygons: Array[PackedVector2Array] = []
var islands: Array[Island] = []
var island_polygons: Array[PackedVector2Array] = []
var streams: Array[Stream] = []
## Roads of cooled lava (the trails of the forge).
var flows: Array[NelvarEarthData.Trail] = []
var clearings: Array[NelvarEarthData.Clearing] = []
var fissures: Array[Fissure] = []
## Ground where magma glows through the joints of the basalt: centre and radius (z).
var magma_fields: Array[Vector3] = []
## Fumarole fields: smoke banks gather over them; centre and radius (z).
var smoke_banks: Array[Vector3] = []
var things: Array[Thing] = []
## The ridges, volcanoes and the plateau's crags, cones and boulders round the basin
## (NelvarEarthData.Thing, kind PEAK: NelvarVolcanoPainter paints them).
var peaks: Array[NelvarEarthData.Thing] = []
## Directions (from the basin's centre) of the great volcanoes; a stream starts under each.
var volcano_angles: Array[float] = []
var spawn_position := Vector2.ZERO

const _GRID := 192.0
const _CELL := 128.0
## Stream segments are listed this far round their lava, so lava_depth() is exact there.
const _STREAM_REACH := 180.0
var _solid_grid := {}
## Cell -> flow segments [a, b, half width] passing near it.
var _flow_grid := {}
## Cell -> stream segments [stream index, segment index].
var _stream_grid := {}


func count(kind: Kind) -> int:
	var total := 0
	for thing in things:
		if thing.kind == kind:
			total += 1
	return total


func count_species(species: Species) -> int:
	var total := 0
	for thing in things:
		if thing.kind == Kind.TREE and thing.variant == species:
			total += 1
	return total


## How deep the point lies in lava, world units: positive in a lake or a stream,
## negative on the ground (how far to the nearest lava within a couple of hundred
## units; -1000 further away). Islands and crossings are ground.
func lava_depth(point: Vector2) -> float:
	var best := -1000.0
	for lake in lakes:
		if point.distance_squared_to(lake.center) > pow(lake.reach() + 400.0, 2.0):
			continue
		best = maxf(best, lake.signed_distance(point))
	if best > -400.0:
		for island in islands:
			if point.distance_squared_to(island.shape.center) < pow(island.shape.reach() + 400.0, 2.0):
				best = minf(best, -island.shape.signed_distance(point))
	# Each stream by its nearest segment: its crossings cut its lava along its length.
	var nearest := {}
	for entry: Vector2i in _stream_grid.get(_cell(point), []):
		var stream := streams[entry.x]
		var a := stream.points[entry.y]
		var b := stream.points[entry.y + 1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := point.distance_to(closest)
		var known: Variant = nearest.get(entry.x)
		if known == null or (known as Vector2).x > distance:
			nearest[entry.x] = Vector2(distance, stream.lengths[entry.y] + a.distance_to(closest))
	for s: int in nearest:
		var found: Vector2 = nearest[s]
		best = maxf(best, streams[s].depth_at(found.x, found.y))
	return best


## True on an island of plates in a lava lake.
func on_island(point: Vector2, margin: float = 0.0) -> bool:
	for island in islands:
		if island.shape.signed_distance(point) > -margin:
			return true
	return false


## Ground nobody can stand on: the ridges, lava or an island (with `margin` to spare).
func is_open_ground(point: Vector2, margin: float = 0.0) -> bool:
	if basin.signed_distance(point) < margin:
		return false
	if lava_depth(point) > -margin:
		return false
	return not on_island(point, margin)


## Where a hopper may come down (NelvarHopper asks before it jumps).
func is_safe_landing(point: Vector2) -> bool:
	return is_open_ground(point, 22.0)


## Distance to the nearest fissure's crack (INF without any).
func fissure_distance(point: Vector2) -> float:
	var best := INF
	for fissure in fissures:
		if point.distance_to(fissure.center) > fissure.reach + best:
			continue
		best = minf(best, polyline_distance(fissure.points, point))
	return best


static func polyline_distance(points: PackedVector2Array, point: Vector2) -> float:
	var best := INF
	for i in points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1])
		best = minf(best, point.distance_to(closest))
	return best


func distance_to_flows(point: Vector2) -> float:
	var best := INF
	for flow in flows:
		best = minf(best, NelvarEarthData.trail_distance(flow, point))
	return best


## Like distance_to_flows, but only sees flows within about a hundred units (INF
## further away); fast, for placement checks.
func flow_clearance(point: Vector2) -> float:
	var best := INF
	for segment: Array in _flow_grid.get(_cell(point), []):
		var closest := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
		best = minf(best, point.distance_to(closest) - segment[2])
	return best


## Free ground for a body of `radius`: in the basin, out of the lava, off the islands
## and clear of trunks, rocks and other solid things. The enemy spawner uses it too.
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


func _cell(point: Vector2) -> Vector2i:
	return Vector2i((point / _CELL).floor())


func index_flows() -> void:
	_flow_grid.clear()
	for flow in flows:
		for i in flow.points.size() - 1:
			var a := flow.points[i]
			var b := flow.points[i + 1]
			var from := _cell(a.min(b)) - Vector2i.ONE
			var to := _cell(a.max(b)) + Vector2i.ONE
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var key := Vector2i(x, y)
					if not _flow_grid.has(key):
						_flow_grid[key] = []
					_flow_grid[key].append([a, b, flow.half_width])


## Lists every stream segment in the cells round its lava (streams measured first).
func index_streams() -> void:
	_stream_grid.clear()
	for s in streams.size():
		var stream := streams[s]
		var reach := Vector2.ONE * (stream.half_width + _STREAM_REACH)
		for i in stream.points.size() - 1:
			var a := stream.points[i]
			var b := stream.points[i + 1]
			var from := _cell(a.min(b) - reach)
			var to := _cell(a.max(b) + reach)
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var key := Vector2i(x, y)
					if not _stream_grid.has(key):
						_stream_grid[key] = []
					_stream_grid[key].append(Vector2i(s, i))


## The lava of a stream between its crossings: closed outlines, each a wall round one
## stretch (the crossings stay open). World units.
func stream_outlines(stream: Stream) -> Array[PackedVector2Array]:
	var cuts: Array[Vector2] = []
	var start := 0.0
	var ordered := stream.crossings.duplicate()
	ordered.sort_custom(func(a: Crossing, b: Crossing) -> bool: return a.along < b.along)
	for crossing: Crossing in ordered:
		cuts.append(Vector2(start, crossing.along - crossing.half_length))
		start = crossing.along + crossing.half_length
	cuts.append(Vector2(start, stream.length()))
	var outlines: Array[PackedVector2Array] = []
	for cut in cuts:
		if cut.y - cut.x < 2.0:
			continue
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var stations := PackedFloat32Array([cut.x])
		for i in stream.lengths.size():
			if stream.lengths[i] > cut.x + 1.0 and stream.lengths[i] < cut.y - 1.0:
				stations.append(stream.lengths[i])
		stations.append(cut.y)
		for along in stations:
			var point := stream.point_at(along)
			var side := _smooth_direction(stream, along).orthogonal() * stream.half_width
			left.append(point + side)
			right.append(point - side)
		# The stream's own ends are round, as its lava (lava_depth) is.
		if cut.y >= stream.length() - 1.0:
			left.append_array(_cap(stream, stream.length(), 1.0))
		right.reverse()
		left.append_array(right)
		if cut.x <= 1.0:
			left.append_array(_cap(stream, 0.0, -1.0))
		outlines.append(left)
	return outlines


## Half a circle round an end of the stream, from its left side to its right one
## (`facing` 1 at the far end, -1 at the start).
static func _cap(stream: Stream, along: float, facing: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var center := stream.point_at(along)
	var forward := _smooth_direction(stream, along) * facing
	var side := _smooth_direction(stream, along).orthogonal() * facing
	for k in range(1, 8):
		var t := PI * k / 8.0
		points.append(center + (side * cos(t) + forward * sin(t)) * stream.half_width)
	return points


## The stream's direction averaged over a short stretch (no kinks in its outline).
static func _smooth_direction(stream: Stream, along: float) -> Vector2:
	var span := 14.0
	var a := stream.point_at(maxf(0.0, along - span))
	var b := stream.point_at(minf(stream.length(), along + span))
	return a.direction_to(b) if a.distance_squared_to(b) > 0.01 else stream.direction_at(along)


## Called once the things are final: numbers them and indexes the solid ones.
func finish() -> void:
	index_flows()
	index_streams()
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
