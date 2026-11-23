class_name NelvarEarthData
extends RefCounted
## The earth valley: a plain ringed by snowy mountains, with ponds, trails, groves,
## rocks and petrified creatures. NelvarEarthGenerator builds it; the ground shader,
## NelvarEarthPainter and NelvarMountainPainter draw it.

## World units per art pixel, as on the air map.
const PIXEL := 4
## Physics layer 5 ("Water"): stops the player and enemies, not projectiles.
const WATER_LAYER := 16
## Harmonics bending the valley and the ponds: k = 2 .. HARMONICS + 1.
const HARMONICS := 6

enum Kind { TREE, ROCK, STATUE, STUMP, LOG, BUSH, TALL_GRASS, FERN, FLOWERS, MUSHROOMS,
	REEDS, LILY, PEAK }
enum Species { OAK, BIRCH, PINE, BLOSSOM, APPLE, WILLOW, MAPLE }
## Look of a peak (Thing.variant of Kind.PEAK). The ring round the valley mixes the
## first five; crags and boulders lie on the plateau beyond it.
enum Peak { SUMMIT, MASSIF, NEEDLES, MESA, GIANT, CRAG, BOULDER }

const SPECIES_NAMES: Array[String] = ["дуб", "берёза", "ель", "цветущая вишня", "яблоня",
	"ива", "золотой клён"]


## A closed shape given by its radius around a centre: an ellipse bent by a few slow
## harmonics. The valley floor and every pond are such shapes; the ground shader
## evaluates the same function for the valley.
class Radial:
	var center := Vector2.ZERO
	var axes := Vector2.ONE
	var amplitudes := PackedFloat32Array()
	var phases := PackedFloat32Array()

	func radius_at(angle: float) -> float:
		var c := cos(angle)
		var s := sin(angle)
		var radius := axes.x * axes.y / sqrt(axes.y * axes.y * c * c + axes.x * axes.x * s * s)
		var bend := 1.0
		for i in amplitudes.size():
			bend += amplitudes[i] * cos(float(i + 2) * angle + phases[i])
		return radius * bend

	## Positive inside, in world units: exact on the outline, close to it nearby.
	func signed_distance(point: Vector2) -> float:
		var offset := point - center
		if offset.length_squared() < 0.0001:
			return radius_at(0.0)
		return radius_at(offset.angle()) - offset.length()

	func point_at(angle: float, inset: float = 0.0) -> Vector2:
		return center + Vector2.from_angle(angle) * (radius_at(angle) - inset)

	func polygon(vertices: int) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in vertices:
			points.append(point_at(TAU * float(i) / vertices))
		return points

	## Largest radius: a bound for the shape.
	func reach() -> float:
		var total := 1.0
		for amplitude in amplitudes:
			total += absf(amplitude)
		return maxf(axes.x, axes.y) * total


class Trail:
	var points := PackedVector2Array()
	var half_width := 16.0
	## Runs off into the mountains instead of ending on the plain.
	var into_mountains := false


class Clearing:
	var center: Vector2
	var radius: float


## Anything placed in the valley or on the mountains. The position is the ground
## origin: it drives Y-sorting and the collider's centre.
class Thing:
	var id := 0
	var kind := Kind.ROCK
	## Species for trees, look variant for other kinds.
	var variant := 0
	var position := Vector2.ZERO
	## Trees: trunk radius. Peaks: half the base. Others: half-width of the footprint.
	var radius := 16.0
	## Trees: crown radius and total height. Peaks: base width and height. Logs: length.
	var size := Vector2.ZERO
	var solid := false
	var appearance_seed := 0
	## Moss on rocks and stumps, snow on pines, a statue facing left, a flower on a lily.
	var accent := false
	## Peaks: 0 at the mountain foot, higher rows further out; the plateau's crags and
	## boulders have the row past the last.
	var row := 0

	## Collision ellipse half-axes of solid things (trees and stumps use a circle).
	func footprint() -> Vector2:
		match kind:
			Kind.ROCK:
				return Vector2(radius, radius * 0.56)
			Kind.STATUE:
				return Vector2(radius * 1.45, radius * 0.62)
			Kind.LOG:
				return Vector2(size.x * 0.5, radius * 0.7)
		return Vector2(radius, radius)

	## Distance used to keep things apart: the larger half-axis of the footprint.
	func spread() -> float:
		var axes := footprint()
		return maxf(axes.x, axes.y)

	func crown_center() -> Vector2:
		return position + Vector2(0.0, -size.y + size.x * 0.92)

	func crown_axes() -> Vector2:
		return Vector2(size.x, size.x * 0.9)

	## True when the point lies in this tree's crown and behind the tree (so the crown
	## would hide whatever stands there).
	func crown_hides(point: Vector2, margin: float = 0.0) -> bool:
		if kind != Kind.TREE or point.y >= position.y:
			return false
		return ((point - crown_center()) / (crown_axes() + Vector2.ONE * margin)).length_squared() < 1.0

	func is_plant() -> bool:
		return kind in [Kind.BUSH, Kind.TALL_GRASS, Kind.FERN, Kind.FLOWERS, Kind.REEDS]


var world_seed := 0
var valley := Radial.new()
var boundary := PackedVector2Array()
var ponds: Array[Radial] = []
var pond_polygons: Array[PackedVector2Array] = []
var trails: Array[Trail] = []
var clearings: Array[Clearing] = []
var things: Array[Thing] = []
var spawn_position := Vector2.ZERO

const _GRID := 192.0
const _TRAIL_CELL := 128.0
var _solid_grid := {}
## Cell -> trail segments [a, b, half width] passing near it.
var _trail_grid := {}


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


## Ground nobody can stand on: the mountains or a pond (with `margin` to spare).
func is_open_ground(point: Vector2, margin: float = 0.0) -> bool:
	if valley.signed_distance(point) < margin:
		return false
	return pond_depth(point) < -margin


## Signed distance into the nearest pond: positive in the water.
func pond_depth(point: Vector2) -> float:
	var best := -INF
	for pond in ponds:
		if point.distance_squared_to(pond.center) > pow(pond.reach() + 400.0, 2.0):
			continue
		best = maxf(best, pond.signed_distance(point))
	return best


func distance_to_trails(point: Vector2) -> float:
	var best := INF
	for trail in trails:
		best = minf(best, trail_distance(trail, point))
	return best


## Distance from the point to the trail's edge (negative on the trail).
static func trail_distance(trail: Trail, point: Vector2) -> float:
	var best := INF
	for i in trail.points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(point, trail.points[i], trail.points[i + 1])
		best = minf(best, point.distance_to(closest))
	return best - trail.half_width


## Like distance_to_trails, but only sees trails within about a hundred units (INF
## further away); fast, for placement checks.
func trail_clearance(point: Vector2) -> float:
	var best := INF
	for segment: Array in _trail_grid.get(Vector2i((point / _TRAIL_CELL).floor()), []):
		var closest := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
		best = minf(best, point.distance_to(closest) - segment[2])
	return best


func index_trails() -> void:
	_trail_grid.clear()
	for trail in trails:
		for i in trail.points.size() - 1:
			var a := trail.points[i]
			var b := trail.points[i + 1]
			# Each segment is listed in every cell within a cell of its bounds.
			var from := Vector2i((a.min(b) / _TRAIL_CELL).floor()) - Vector2i.ONE
			var to := Vector2i((a.max(b) / _TRAIL_CELL).floor()) + Vector2i.ONE
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var key := Vector2i(x, y)
					if not _trail_grid.has(key):
						_trail_grid[key] = []
					_trail_grid[key].append([a, b, trail.half_width])


## Free ground for a body of `radius`: inside the valley, out of the water and clear
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


## Called once the things are final: numbers them and indexes the solid ones.
func finish() -> void:
	index_trails()
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
