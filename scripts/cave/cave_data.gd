class_name NelvarCaveData
extends NelvarIceData
## The ice cave, Лёд 2: halls joined by winding passages, with loops and dead ends, cut
## into a mass of blue ice with dead creatures frozen into it. Mostly dusk; under holes
## in the roof the sun shines, snow falls and lies, pines grow. The biggest halls are
## cold, with frost, mist, pillars and geysers. Lakes — frozen, melting, open water —
## chasms crossed by ice arches, crevasses with snow bridges, crystals, boulders.
## NelvarCaveGenerator builds it; the floor shader, NelvarCavePainter and the light
## overlays draw it.
##
## The one truth about the walls is a signed distance field on a grid of CELL (two art
## pixels): positive in the ice, negative on the floor. The collision (its zero line by
## marching squares), the queries (wall_depth, bilinear) and the floor shader (bilinear
## per art pixel) all read it, so they see one boundary.
##
## It is built on NelvarIceData: the lakes, the thin ice, the crevasses and their bridges,
## the holes, the things and the creatures under the ice are the valley's, so the
## valley's painter, depths, marks and hazards work on it as they are.

const CELL := 8.0
## Height of a south face (the wall turned to the camera), art pixels; every wall keeps
## FACE + FACE_SPARE above it.
const FACE := 12
const FACE_SPARE := 4
## Soft edges of the zones: the cold, the sun.
const COLD_EDGE := 120.0
const SUN_EDGE := 40.0
## The smooth ice of an icy passage reaches this far past its corridor.
const ICY_SPARE := 6.0
## The path grid of the enemy spawner (path_distance).
const PATH_CELL := 32.0
## Narrow places of a chasm: a run crosses this much (the step holds 0.09 s at 450 a
## second), the flight this much.
const LEAP_RUN := 34.0
const LEAP_FLY := 100.0
## Physics layer 9 ("Walls"): the cave's walls are on it besides World, so a sight line
## can tell them from the things (the player's sight_mask).
const WALL_SIGHT_LAYER := 256

## Hall kinds: a dark hall, a sunny one under a hole in the roof, a cold arena, a grotto
## at the end of a dead end.
enum Zone { DARK, SUNNY, COLD, GROTTO }
## Lake kinds: frozen hard, melting (gives under a walker), open water.
enum Pool { FROZEN, MELT, OPEN }
## Crystal looks (Thing.variant of Kind.CRYSTAL).
enum Crystal { SHARD, CLUSTER, COLUMN, SLAB, FAN }
## Crystal colours (Thing.size.x).
enum Tint { CLEAR, DEEP, VIOLET }
## What sticks out of a face (Thing.variant of Kind.EMBEDDED).
enum Part { HEAD, PAW, TAIL, WING }


## A hall: its outline, its kind, its exits and the ice pillars standing in it.
class Hall:
	var shape := NelvarEarthData.Radial.new()
	var zone := Zone.DARK
	## Passages leaving it (indices).
	var exits: Array[int] = []
	var columns: Array[NelvarEarthData.Radial] = []

	func is_main() -> bool:
		return zone != Zone.GROTTO

	## The free middle of the hall, where nothing solid stands.
	func arena() -> float:
		return minf(shape.axes.x, shape.axes.y) * 0.34


## A winding passage between two halls: a centre line whose half width changes along it,
## and the niches beside it.
class Passage extends NelvarIceData.Crevasse:
	var from := -1
	var to := -1
	var icy := false
	var niches: Array[NelvarEarthData.Radial] = []


## A hole in the roof over a sunny hall: the patch of sunlight.
class Skylight:
	var spot := NelvarEarthData.Radial.new()
	var hall := -1
	## Snow lies this much further round the spot.
	var reach := 90.0


## Snow running from a sunny hall into a passage: a centre line, tapering.
class Tongue:
	var points := PackedVector2Array()
	var half_widths := PackedFloat32Array()
	## Where it lies (with its widest half width round it).
	var box := Rect2()

	func measure() -> void:
		var widest := 0.0
		for half in half_widths:
			widest = maxf(widest, half)
		box = Rect2(points[0], Vector2.ZERO)
		for point in points:
			box = box.expand(point)
		box = box.grow(widest + 2.0)


## A geyser in a cold hall: its warm ground, its mouth and its cycle — calm, then
## BUBBLE seconds of bubbling, then ERUPT seconds of eruption.
class Geyser:
	const BUBBLE := 1.5
	const ERUPT := 1.2
	## An eruption widens the warmth for this long.
	const AFTER := 4.0
	var position := Vector2.ZERO
	var radius := 200.0
	var mouth := 26.0
	var period := 18.0
	var offset := 0.0
	var hall := -1

	func phase(clock: float) -> float:
		return fposmod(clock + offset, period)

	## 0 calm, 1 bubbling, 2 erupting.
	func stage_at(clock: float) -> int:
		var p := phase(clock)
		if p >= period - ERUPT:
			return 2
		if p >= period - ERUPT - BUBBLE:
			return 1
		return 0

	## How far into the stage, 0..1.
	func progress_at(clock: float) -> float:
		var p := phase(clock)
		match stage_at(clock):
			2:
				return (p - (period - ERUPT)) / ERUPT
			1:
				return (p - (period - ERUPT - BUBBLE)) / BUBBLE
		return p / maxf(period - ERUPT - BUBBLE, 0.01)

	## Seconds since the last eruption began.
	func since_eruption(clock: float) -> float:
		var p := phase(clock)
		var start := period - ERUPT
		return p - start if p >= start else p + ERUPT

	## How far the warmth reaches now, as a share of `radius`: 1.3 just after an
	## eruption, back to 1 within AFTER seconds.
	func heat_scale(clock: float) -> float:
		var since := since_eruption(clock)
		if since > AFTER:
			return 1.0
		return 1.0 + 0.3 * (1.0 - smoothstep(AFTER * 0.5, AFTER, since))


## An ice arch over a chasm: a straight deck from `a` to `b`.
class Arch:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var half_width := 32.0

	func distance(point: Vector2) -> float:
		return point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))

	func length() -> float:
		return a.distance_to(b)


## A chasm: a broad crack down into the dark, tapering at its ends; arches cross it.
class Chasm extends NelvarIceData.Crevasse:
	var arches: Array[Arch] = []
	## Narrow places on open floor: where it is crossed (x, y), how wide it is there (z).
	## Up to LEAP_RUN a run gets over, up to LEAP_FLY the flight.
	var leaps := PackedVector3Array()


## A body floating on open water, drifting slowly round a loop.
class Floater:
	var lake := 0
	var position := Vector2.ZERO
	var radius := 30.0
	var variant := Creature.BEAST
	var appearance_seed := 0
	var facing_left := false
	## Half under the water.
	var sunk := false
	## A loop of radius x, one round in y seconds, from phase z.
	var drift := Vector3(20.0, 90.0, 0.0)

	func position_at(time: float) -> Vector2:
		var angle := drift.z + TAU * time / maxf(drift.y, 1.0)
		return position + Vector2(cos(angle), sin(angle) * 0.7) * drift.x


## The cave's rectangle; solid ice all round.
var bounds := Rect2()
var halls: Array[Hall] = []
var passages: Array[Passage] = []
var skylights: Array[Skylight] = []
var tongues: Array[Tongue] = []
var geysers: Array[Geyser] = []
var chasms: Array[Chasm] = []
var floaters: Array[Floater] = []
## Per lake: its kind (Pool) and, for open water, the band of melting ice round it.
var pools := PackedInt32Array()
var rims := PackedFloat32Array()
## Creatures frozen into the walls move round these with the parallax (after the lakes).
var wall_anchors := PackedVector2Array()
## The hall the player starts in (a sunny one).
var start_hall := -1
## The walls: signed distance, world units, positive in the ice; sample (x, y) lies at
## sdf_origin + (x, y) * CELL.
var sdf := PackedFloat32Array()
var sdf_origin := Vector2.ZERO
var sdf_size := Vector2i.ZERO
## Where the player is (NelvarCaveMain sets it every frame): path_distance() measures
## from here.
var path_origin := Vector2.INF

const _HALL_CELL := 256.0
const _LINE_CELL := 128.0
const _LINE_REACH := 200.0
var _hall_grid := {}
## Cell -> [passage index, segment index] near it.
var _passage_grid := {}
## Cell -> Vector2i(chasm index, segment index) near it.
var _chasm_grid := {}
var _walkable := PackedByteArray()
var _path_size := Vector2i.ZERO
var _path_cell := Vector2i(-1073741824, 0)
var _path := PackedFloat32Array()


func main_halls() -> int:
	var total := 0
	for hall in halls:
		if hall.is_main():
			total += 1
	return total


func zone_count(zone: Zone) -> int:
	var total := 0
	for hall in halls:
		if hall.zone == zone:
			total += 1
	return total


func pool_count(kind: Pool) -> int:
	var total := 0
	for value in pools:
		if value == kind:
			total += 1
	return total


func arch_count() -> int:
	var total := 0
	for chasm in chasms:
		total += chasm.arches.size()
	return total


# --- The walls -------------------------------------------------------------------

## Signed distance to the floor's edge, world units: positive in the ice (how deep),
## negative on the floor (how far to the nearest wall). Bilinear between the samples.
func wall_depth(point: Vector2) -> float:
	var f := (point - sdf_origin) / CELL
	var x := floori(f.x)
	var y := floori(f.y)
	if x < 0 or y < 0 or x >= sdf_size.x - 1 or y >= sdf_size.y - 1:
		return 1000.0
	var tx := f.x - x
	var ty := f.y - y
	var i := y * sdf_size.x + x
	var top := lerpf(sdf[i], sdf[i + 1], tx)
	var bottom := lerpf(sdf[i + sdf_size.x], sdf[i + sdf_size.x + 1], tx)
	return lerpf(top, bottom, ty)


# --- Halls and passages ----------------------------------------------------------

## Index of the hall the point is in (the one it is deepest in), -1 in a passage.
func hall_at(point: Vector2) -> int:
	var best := -1
	var depth := 0.0
	for h: int in _hall_grid.get(_hall_cell(point), []):
		var d := halls[h].shape.signed_distance(point)
		if d > depth:
			depth = d
			best = h
	return best


## How deep in a hall's outline the point lies (most), -1000 far from any.
func hall_depth(point: Vector2) -> float:
	var best := -1000.0
	for h: int in _hall_grid.get(_hall_cell(point), []):
		best = maxf(best, halls[h].shape.signed_distance(point))
	return best


## The nearest passage: Vector3(index, distance from its centre line, running length
## there); index -1 with none within about two hundred units.
func passage_near(point: Vector2) -> Vector3:
	var best := Vector3(-1, INF, 0.0)
	for entry: Vector2i in _passage_grid.get(_line_cell(point), []):
		var passage := passages[entry.x]
		var a := passage.points[entry.y]
		var b := passage.points[entry.y + 1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := point.distance_to(closest)
		if distance < best.y:
			best = Vector3(entry.x, distance, passage.lengths[entry.y] + a.distance_to(closest))
	return best


## How far inside a passage's corridor the point is (its half width there minus the
## distance from the centre line): positive inside, -1000 far away.
func passage_depth(point: Vector2) -> float:
	var near := passage_near(point)
	if near.x < 0:
		return -1000.0
	return passages[int(near.x)].half_width_at(near.z) - near.y


## On the smooth ice of an icy passage: inside its corridor (and a little more), out of
## the halls.
func icy_at(point: Vector2) -> bool:
	var nearest := {}
	for entry: Vector2i in _passage_grid.get(_line_cell(point), []):
		var passage := passages[entry.x]
		if not passage.icy:
			continue
		var a := passage.points[entry.y]
		var b := passage.points[entry.y + 1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := point.distance_to(closest)
		var known: Variant = nearest.get(entry.x)
		if known == null or (known as Vector2).x > distance:
			nearest[entry.x] = Vector2(distance, passage.lengths[entry.y] + a.distance_to(closest))
	for p: int in nearest:
		var found: Vector2 = nearest[p]
		if found.x < passages[p].half_width_at(found.y) + ICY_SPARE and hall_depth(point) < -10.0:
			return true
	return false


# --- Light, snow, cold, warmth ----------------------------------------------------

## Sunlight through the roof, 0..1 (a soft edge of SUN_EDGE).
func sun_at(point: Vector2) -> float:
	var best := 0.0
	for skylight in skylights:
		best = maxf(best, smoothstep(-SUN_EDGE, SUN_EDGE, skylight.spot.signed_distance(point)))
	return best


## How far inside the snow the point is, world units (positive on snow): round each
## sunny spot and in tongues into the passages, the edge ragged.
func snow_depth(point: Vector2) -> float:
	var best := -1000.0
	for skylight in skylights:
		if point.distance_squared_to(skylight.spot.center) > pow(skylight.spot.reach() + skylight.reach + 300.0, 2.0):
			continue
		best = maxf(best, skylight.spot.signed_distance(point) + skylight.reach)
	for tongue in tongues:
		if not tongue.box.has_point(point):
			continue
		for i in tongue.points.size() - 1:
			var a := tongue.points[i]
			var b := tongue.points[i + 1]
			var span := b - a
			var t := clampf((point - a).dot(span) / maxf(span.length_squared(), 0.0001), 0.0, 1.0)
			var half := lerpf(tongue.half_widths[i], tongue.half_widths[i + 1], t)
			best = maxf(best, half - point.distance_to(a + span * t))
	if best < -300.0:
		return best
	return best + (NelvarPixelArt.value_noise(point.x / 52.0, point.y / 52.0, 77) - 0.5) * 44.0


## Snow lies here (marks show only on it): in the sunny places, off the ice, out of the
## cracks, the chasms and the warmth.
func is_snow(point: Vector2) -> bool:
	if snow_depth(point) <= 0.0 or wall_depth(point) > 0.0:
		return false
	return lake_depth(point) < -4.0 and crevasse_sample(point).x < -6.0 and chasm_sample(point).x < -6.0 \
		and warmth_at(point) < 0.2


## The cold of the big halls, 0..1 (frost and mist only: it does not hurt).
func cold_at(point: Vector2) -> float:
	var best := 0.0
	for h: int in _hall_grid.get(_hall_cell(point), []):
		var hall := halls[h]
		if hall.zone == Zone.COLD:
			best = maxf(best, smoothstep(-COLD_EDGE, COLD_EDGE, hall.shape.signed_distance(point)))
	return best


## The warmth round the geysers, 0..1 (as far as they reach when calm).
func warmth_at(point: Vector2) -> float:
	var best := 0.0
	for geyser in geysers:
		var d := point.distance_to(geyser.position)
		if d < geyser.radius:
			best = maxf(best, 1.0 - smoothstep(0.0, geyser.radius, d))
	return best


## The geyser whose mouth the point is in (with `margin`), null outside.
func geyser_at(point: Vector2, margin: float = 0.0) -> Geyser:
	for geyser in geysers:
		if point.distance_to(geyser.position) < geyser.mouth + margin:
			return geyser
	return null


# --- Lakes, chasms ----------------------------------------------------------------

## Depth into open water (inside the melting rim): positive in it, -1000 far away.
func water_depth(point: Vector2) -> float:
	var best := -1000.0
	for i in lakes.size():
		if pools[i] != Pool.OPEN:
			continue
		var shape := lakes[i].shape
		if point.distance_squared_to(shape.center) > pow(shape.reach() + 300.0, 2.0):
			continue
		best = maxf(best, shape.signed_distance(point) - rims[i])
	return best


## Depth into melting ice or open water (any lake that gives): positive in it.
func melt_depth(point: Vector2) -> float:
	var best := -1000.0
	for i in lakes.size():
		if pools[i] == Pool.FROZEN:
			continue
		var shape := lakes[i].shape
		if point.distance_squared_to(shape.center) > pow(shape.reach() + 300.0, 2.0):
			continue
		best = maxf(best, shape.signed_distance(point))
	return best


## Depth into a chasm without the arches (x) and with them (y): positive in it, negative
## on the floor and on an arch (how far, within a couple of hundred units; -1000 further).
func chasm_sample(point: Vector2) -> Vector2:
	var raw := -1000.0
	var nearest := {}
	for entry: Vector2i in _chasm_grid.get(_line_cell(point), []):
		var chasm := chasms[entry.x]
		var a := chasm.points[entry.y]
		var b := chasm.points[entry.y + 1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := point.distance_to(closest)
		var known: Variant = nearest.get(entry.x)
		if known == null or (known as Vector2).x > distance:
			nearest[entry.x] = Vector2(distance, chasm.lengths[entry.y] + a.distance_to(closest))
	var bridged := -1000.0
	for c: int in nearest:
		var found: Vector2 = nearest[c]
		var depth := chasms[c].raw_depth(found.x, found.y)
		raw = maxf(raw, depth)
		for arch in chasms[c].arches:
			depth = minf(depth, arch.distance(point) - arch.half_width)
		bridged = maxf(bridged, depth)
	return Vector2(raw, bridged)


## Depth into a chasm: positive over the drop, negative on the floor and on an arch.
func chasm_depth(point: Vector2) -> float:
	return chasm_sample(point).y


## The arch the point is on (null off the arches).
func arch_at(point: Vector2) -> Arch:
	for chasm in chasms:
		for arch in chasm.arches:
			if arch.distance(point) < arch.half_width:
				return arch
	return null


# --- What lies under a point -------------------------------------------------------

## Snow, bare stone, lake ice, thin ice, melting ice or open water (Surface).
func ice_at(point: Vector2) -> int:
	var lake := lake_at(point)
	if lake >= 0:
		match pools[lake]:
			Pool.OPEN:
				return Surface.WATER if lakes[lake].shape.signed_distance(point) > rims[lake] else Surface.MELT
			Pool.MELT:
				return Surface.MELT
		if thin_depth(point) > 0.0:
			return Surface.THIN
		for hole in holes:
			if point.distance_squared_to(hole.center) < hole.radius * hole.radius:
				return Surface.THIN
		return Surface.ICE
	if icy_at(point):
		return Surface.ICE
	if is_snow(point):
		return Surface.SNOW
	return Surface.STONE


## How well the ground holds: 1 on stone and snow, ICE_GRIP on any ice.
func grip_at(point: Vector2) -> float:
	var surface := ice_at(point)
	if surface == Surface.SNOW or surface == Surface.STONE:
		return 1.0
	return ICE_GRIP


## What a step onto the point leads into: a crevasse, a chasm, the water (an open hole or
## open water), nothing.
func fall_kind(point: Vector2, margin: float = 0.0) -> int:
	if crevasse_depth(point) > margin:
		return Fall.CREVASSE
	if chasm_depth(point) > margin:
		return Fall.CHASM
	if water_depth(point) > margin or hole_depth(point) > margin:
		return Fall.WATER
	return Fall.NONE


## Ground nobody can stand on: the ice of the walls, a crevasse, a chasm, the water
## (with `margin` to spare). Lake ice, arches and bridges are ground.
func is_open_ground(point: Vector2, margin: float = 0.0) -> bool:
	if wall_depth(point) > -margin:
		return false
	if crevasse_depth(point) > -margin or chasm_depth(point) > -margin:
		return false
	return water_depth(point) < -margin and hole_depth(point) < -margin


## Where a hopper may come down: clear of the walls (with room to spare), the falls,
## thin ice and melting ice.
func is_safe_landing(point: Vector2) -> bool:
	return is_open_ground(point, 22.0) and wall_depth(point) < -26.0 and thin_depth(point) < -16.0 \
		and hole_depth(point) < -30.0 and melt_depth(point) < -16.0


## Ground a fall brings the player back to: off the lakes and the arches and bridges,
## away from the walls and every drop.
func is_safe_spot(point: Vector2) -> bool:
	var spare := NelvarPlayer.BODY_RADIUS + SAFE_MARGIN
	if wall_depth(point) > -(NelvarPlayer.BODY_RADIUS + 4.0) or lake_depth(point) > -SAFE_MARGIN:
		return false
	if crevasse_sample(point).x > -spare or chasm_sample(point).x > -spare:
		return false
	return geyser_at(point, NelvarPlayer.BODY_RADIUS + 8.0) == null


## The lakes' centres, then the anchors of the creatures in the walls.
func depth_anchors() -> PackedVector2Array:
	var anchors := super()
	anchors.append_array(wall_anchors)
	return anchors


# --- Paths for the spawner -------------------------------------------------------------

## Length of the way on foot from the player (path_origin) to the point, over a grid of
## PATH_CELL; INF where it cannot be walked to (or is further than about 2600). The grid
## is searched again when the player moves to another cell.
func path_distance(point: Vector2) -> float:
	if not path_origin.is_finite():
		return 0.0
	_update_paths()
	var cell := _path_cell_of(point)
	var best := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= _path_size.x or c.y >= _path_size.y:
				continue
			var value := _path[c.y * _path_size.x + c.x]
			if value < INF:
				var center := bounds.position + (Vector2(c) + Vector2(0.5, 0.5)) * PATH_CELL
				best = minf(best, value + center.distance_to(point))
	return best


func _path_cell_of(point: Vector2) -> Vector2i:
	return Vector2i(((point - bounds.position) / PATH_CELL).floor())


## The walkable cells of the path grid (once).
func _build_walkable() -> void:
	_path_size = Vector2i((bounds.size / PATH_CELL).ceil())
	_walkable.resize(_path_size.x * _path_size.y)
	for y in _path_size.y:
		for x in _path_size.x:
			var center := bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * PATH_CELL
			var open := wall_depth(center) < -6.0 and chasm_depth(center) < 0.0 and water_depth(center) < 0.0
			_walkable[y * _path_size.x + x] = 1 if open else 0


## Dijkstra over the path grid from the player's cell (steps of 10 and 14 tenths of a
## cell in buckets), as far as about 2600.
func _update_paths() -> void:
	if _walkable.is_empty():
		_build_walkable()
	var start := _path_cell_of(path_origin)
	if start == _path_cell:
		return
	_path_cell = start
	_path.resize(_path_size.x * _path_size.y)
	_path.fill(INF)
	if start.x < 0 or start.y < 0 or start.x >= _path_size.x or start.y >= _path_size.y:
		return
	var limit := int(2600.0 / PATH_CELL * 10.0)
	var buckets: Array = []
	buckets.resize(limit + 15)
	for i in buckets.size():
		buckets[i] = []
	var costs := PackedInt32Array()
	costs.resize(_path_size.x * _path_size.y)
	costs.fill(1 << 30)
	var first := start.y * _path_size.x + start.x
	costs[first] = 0
	buckets[0].append(first)
	var steps: Array[Vector3i] = [Vector3i(1, 0, 10), Vector3i(-1, 0, 10), Vector3i(0, 1, 10), Vector3i(0, -1, 10),
		Vector3i(1, 1, 14), Vector3i(-1, 1, 14), Vector3i(1, -1, 14), Vector3i(-1, -1, 14)]
	for cost in limit:
		var bucket: Array = buckets[cost]
		var k := 0
		while k < bucket.size():
			var index: int = bucket[k]
			k += 1
			if costs[index] != cost:
				continue
			_path[index] = cost * PATH_CELL / 10.0
			var x := index % _path_size.x
			var y := index / _path_size.x
			for step in steps:
				var nx := x + step.x
				var ny := y + step.y
				if nx < 0 or ny < 0 or nx >= _path_size.x or ny >= _path_size.y:
					continue
				var next := ny * _path_size.x + nx
				if _walkable[next] == 0:
					continue
				if step.z == 14 and (_walkable[y * _path_size.x + nx] == 0 or _walkable[ny * _path_size.x + x] == 0):
					continue
				var value := cost + step.z
				if value < costs[next] and value < limit:
					costs[next] = value
					buckets[value].append(next)


# --- Indexes ---------------------------------------------------------------------------

func _hall_cell(point: Vector2) -> Vector2i:
	return Vector2i((point / _HALL_CELL).floor())


func _line_cell(point: Vector2) -> Vector2i:
	return Vector2i((point / _LINE_CELL).floor())


func index_halls() -> void:
	_hall_grid.clear()
	for h in halls.size():
		var shape := halls[h].shape
		var reach := Vector2.ONE * (shape.reach() + COLD_EDGE + 40.0)
		var from := _hall_cell(shape.center - reach)
		var to := _hall_cell(shape.center + reach)
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var key := Vector2i(x, y)
				if not _hall_grid.has(key):
					_hall_grid[key] = []
				_hall_grid[key].append(h)


## Lists each segment of `lines` (centre lines with half widths) in the cells round it.
func _index_lines(lines: Array, grid: Dictionary) -> void:
	grid.clear()
	for l in lines.size():
		var line: NelvarIceData.Crevasse = lines[l]
		var reach := Vector2.ONE * (line.widest() + _LINE_REACH)
		for i in line.points.size() - 1:
			var a := line.points[i]
			var b := line.points[i + 1]
			var from := _line_cell(a.min(b) - reach)
			var to := _line_cell(a.max(b) + reach)
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var key := Vector2i(x, y)
					if not grid.has(key):
						grid[key] = []
					grid[key].append(Vector2i(l, i))


func index_passages() -> void:
	_index_lines(passages, _passage_grid)


func index_chasms() -> void:
	_index_lines(chasms, _chasm_grid)


## Called once the things are final: numbers and indexes everything.
func finish() -> void:
	index_halls()
	index_passages()
	index_chasms()
	super()
