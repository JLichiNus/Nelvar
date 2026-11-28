class_name NelvarAnts
extends Node2D
## Columns of ants along the ant trails of the giant forest: 8–20 ants each, almost as big
## as the player, many carrying a scrap of leaf. The columns do not give way: an ant the
## player walks over (not flies over) is squashed flat and leaves a smear that fades, the
## column walking on with a gap. A few columns keep near the player: one left far behind
## starts again, whole, on a trail out of sight ahead. Drawn on the floor in whole art
## pixels, legs moving.

const STEP := NelvarEarthData.PIXEL
const COLUMNS := 3
const ANTS := Vector2i(8, 20)
const SPACING := Vector2(34.0, 46.0)
const SPEED := Vector2(38.0, 58.0)
## How close the player's middle comes to an ant to squash it (world units).
const SQUASH := 16.0
## How long a smear lies on the floor, fading over its last third (seconds).
const SPLAT_LIFE := 14.0
const SPLATS := 48
const SMEAR := Color8(58, 30, 22)
const FAR := 1500.0
const BODY := Color8(40, 22, 18)
const SHINE := Color8(96, 58, 42)
const LEG := Color8(30, 18, 16)
const LOADS: Array[Color] = [Color8(92, 150, 64), Color8(198, 170, 64), Color8(170, 104, 48)]


class Column:
	var trail := 0
	## How far the head is along the trail, and which way it goes (+1 / -1).
	var head := 0.0
	var direction := 1.0
	var count := 12
	var spacing := 40.0
	var speed := 48.0
	var loads := PackedInt32Array()
	## 1 while the ant is alive, 0 once squashed.
	var alive := PackedByteArray()


class Splat:
	var position := Vector2.ZERO
	var along := Vector2.RIGHT
	var load := -1
	var age := 0.0


var data: NelvarThicketData
var player: Node2D
var columns: Array[Column] = []
var splats: Array[Splat] = []
## Cumulative lengths of each trail's polyline.
var _lengths: Array[PackedFloat32Array] = []
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func setup(thicket: NelvarThicketData, watched: Node2D) -> void:
	data = thicket
	player = watched
	_rng.seed = ("%d:ants" % thicket.world_seed).hash()
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for trail in data.trails:
		var lengths := PackedFloat32Array([0.0])
		for i in trail.points.size() - 1:
			lengths.append(lengths[i] + trail.points[i].distance_to(trail.points[i + 1]))
		_lengths.append(lengths)
	if data.trails.is_empty():
		return
	for i in COLUMNS:
		var column := Column.new()
		_restart(column, 0.0, 900.0)
		columns.append(column)


## Puts the column on the trail nearest the player, between `near` and `far` from them.
func _restart(column: Column, near: float, far: float) -> void:
	var center := player.global_position if is_instance_valid(player) else data.spawn_position
	var best := -1
	var best_at := 0.0
	var best_score := INF
	for attempt in 24:
		var t := _rng.randi_range(0, data.trails.size() - 1)
		var lengths := _lengths[t]
		var at := _rng.randf() * lengths[lengths.size() - 1]
		var distance := _point(t, at).distance_to(center)
		var score := absf(distance - (near + far) * 0.5)
		if distance >= near and distance <= far and score < best_score:
			best_score = score
			best = t
			best_at = at
	if best < 0:
		best = _rng.randi_range(0, data.trails.size() - 1)
		best_at = _rng.randf() * _lengths[best][_lengths[best].size() - 1]
	column.trail = best
	column.head = best_at
	column.direction = 1.0 if _rng.randf() < 0.5 else -1.0
	column.count = _rng.randi_range(ANTS.x, ANTS.y)
	column.spacing = _rng.randf_range(SPACING.x, SPACING.y)
	column.speed = _rng.randf_range(SPEED.x, SPEED.y)
	column.loads.resize(column.count)
	for i in column.count:
		column.loads[i] = _rng.randi_range(0, LOADS.size()) - 1
	_revive(column)


func _revive(column: Column) -> void:
	column.alive.resize(column.count)
	column.alive.fill(1)


## The point `at` along trail `t` (clamped to its ends).
func _point(t: int, at: float) -> Vector2:
	var points := data.trails[t].points
	var lengths := _lengths[t]
	at = clampf(at, 0.0, lengths[lengths.size() - 1])
	var lo := 0
	var hi := lengths.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if lengths[mid] <= at:
			lo = mid
		else:
			hi = mid
	var span := maxf(lengths[hi] - lengths[lo], 0.001)
	return points[lo].lerp(points[hi], (at - lengths[lo]) / span)


## Where along its trail ant `i` of a column is.
func _along(column: Column, i: int) -> float:
	return column.head - column.direction * i * column.spacing


## Whether ant `i` is on the trail now (and not squashed).
func is_walking(column: Column, i: int) -> bool:
	var at := _along(column, i)
	return column.alive[i] == 1 and at >= 0.0 and at <= _lengths[column.trail][_lengths[column.trail].size() - 1]


## Where ant `i` of a column is now (world), wobbling a little off the trail.
func ant_position(column: Column, i: int) -> Vector2:
	var at := _along(column, i)
	var p := _point(column.trail, at)
	var ahead := _point(column.trail, at + column.direction * 6.0)
	var side := p.direction_to(ahead).orthogonal()
	return p + side * sin(_time * 3.0 + i * 1.7) * 3.0


## Positions of a column's walking ants now (world).
func ant_positions(column: Column) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in column.count:
		if is_walking(column, i):
			result.append(ant_position(column, i))
	return result


## The way ant `i` faces, snapped to one of the four art directions.
func _facing(column: Column, i: int, spot: Vector2) -> Vector2:
	var ahead := _point(column.trail, _along(column, i) + column.direction * 8.0)
	var direction := spot.direction_to(ahead)
	if direction == Vector2.ZERO:
		return Vector2.RIGHT
	return Vector2(signf(direction.x), 0.0) if absf(direction.x) > absf(direction.y) else Vector2(0.0, signf(direction.y))


func _process(delta: float) -> void:
	if not is_instance_valid(player) or data == null or data.trails.is_empty():
		return
	_time += delta
	var center := player.global_position
	var grounded: bool = not (player.has_method(&"is_airborne") and player.is_airborne())
	for column in columns:
		var total := _lengths[column.trail][_lengths[column.trail].size() - 1]
		column.head += column.direction * column.speed * delta
		var tail := column.head - column.direction * column.count * column.spacing
		if (column.direction > 0.0 and tail > total) or (column.direction < 0.0 and tail < 0.0):
			# Gone off the trail's end: turn round with a fresh line.
			column.direction = -column.direction
			column.head = clampf(column.head, 0.0, total)
			_revive(column)
		if grounded:
			for i in column.count:
				if is_walking(column, i):
					var p := ant_position(column, i)
					if p.distance_to(center) < SQUASH:
						_squash(column, i, p)
		if _point(column.trail, column.head).distance_to(center) > FAR:
			_restart(column, 500.0, 900.0)
	for splat in splats:
		splat.age += delta
	while not splats.is_empty() and splats[0].age > SPLAT_LIFE:
		splats.pop_front()
	queue_redraw()


func _squash(column: Column, i: int, spot: Vector2) -> void:
	column.alive[i] = 0
	var splat := Splat.new()
	splat.position = spot
	splat.along = _facing(column, i, spot)
	splat.load = column.loads[i]
	splats.append(splat)
	if splats.size() > SPLATS:
		splats.pop_front()


func _draw() -> void:
	var cell := Vector2.ONE * STEP
	for splat in splats:
		_draw_splat(splat, cell)
	for column in columns:
		for i in column.count:
			if not is_walking(column, i):
				continue
			var spot := ant_position(column, i)
			var at := (spot / STEP).floor()
			var step := int(_time * 10.0 + i) % 2
			# Three body segments along the way it walks (drawn sideways or upright).
			var along := _facing(column, i, spot)
			var across := Vector2(-along.y, along.x)
			for k in [-2, -1, 0, 1, 2]:
				draw_rect(Rect2((at + along * k) * STEP, cell), BODY if k != 1 else SHINE)
			for k in [-1, 0, 1]:
				var swing := (1 if (k + step) % 2 == 0 else 0)
				draw_rect(Rect2((at + along * k + across * 2.0 + along * swing) * STEP, cell), LEG)
				draw_rect(Rect2((at + along * k - across * 2.0 - along * swing) * STEP, cell), LEG)
			if column.loads[i] >= 0:
				var load := LOADS[column.loads[i]]
				draw_rect(Rect2((at + along * 2.0 + Vector2(0, -2)) * STEP, cell * 2.0), load)
				draw_rect(Rect2((at + along * 2.0 + Vector2(0, -2)) * STEP, cell), load.lightened(0.3))


## A squashed ant: the body pressed into a flat round blot, legs splayed out, a few drops
## spattered round it and its scrap of leaf dropped beside, all fading out over the last
## third of its life.
func _draw_splat(splat: Splat, cell: Vector2) -> void:
	var fade := clampf((SPLAT_LIFE - splat.age) / (SPLAT_LIFE / 3.0), 0.0, 1.0)
	var at := (splat.position / STEP).floor()
	var along := splat.along
	var across := Vector2(-along.y, along.x)
	var body := Color(BODY, fade)
	var smear := Color(SMEAR, 0.7 * fade)
	var leg := Color(LEG, fade)
	for a in [-1, 0, 1]:
		for b in [-1, 0, 1]:
			draw_rect(Rect2((at + along * a + across * b) * STEP, cell), body if (a == 0 or b == 0) else smear)
	draw_rect(Rect2((at + along * 2.0) * STEP, cell), body)
	draw_rect(Rect2((at - along * 2.0) * STEP, cell), Color(SHINE, fade))
	for s in [-1.0, 1.0]:
		draw_rect(Rect2((at + along * 2.0 + across * 2.0 * s) * STEP, cell), leg)
		draw_rect(Rect2((at + across * 3.0 * s) * STEP, cell), leg)
		draw_rect(Rect2((at - along * 2.0 + across * 2.0 * s) * STEP, cell), leg)
	# Drops, placed by the spot (the same each frame).
	var h := hash(at)
	for k in 3:
		var drop := Vector2(((h >> (k * 6)) & 7) - 3.5, ((h >> (k * 6 + 3)) & 7) - 3.5).round()
		if absf(drop.x) + absf(drop.y) >= 3.0:
			draw_rect(Rect2((at + drop) * STEP, cell), smear)
	if splat.load >= 0:
		var load := Color(LOADS[splat.load], fade)
		draw_rect(Rect2((at + along * 3.0 + across * 2.0) * STEP, cell * 2.0), load)
