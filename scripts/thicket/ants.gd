class_name NelvarAnts
extends Node2D
## Columns of ants along the ant trails of the giant forest: 8–20 ants each, almost as big
## as the player, many carrying a scrap of leaf. A column steps aside round the player and
## never touches anyone. A few columns keep near the player: one left far behind starts
## again on a trail out of sight ahead. Drawn on the floor in whole art pixels, legs moving.

const STEP := NelvarEarthData.PIXEL
const COLUMNS := 3
const ANTS := Vector2i(8, 20)
const SPACING := Vector2(34.0, 46.0)
const SPEED := Vector2(38.0, 58.0)
const AVOID := 70.0
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
	## Each ant's sideways step (world units), eased.
	var aside := PackedFloat32Array()


var data: NelvarThicketData
var player: Node2D
var columns: Array[Column] = []
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
	column.aside.resize(column.count)
	for i in column.count:
		column.loads[i] = _rng.randi_range(0, LOADS.size()) - 1
		column.aside[i] = 0.0


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


## Positions of a column's ants now (world).
func ant_positions(column: Column) -> PackedVector2Array:
	var result := PackedVector2Array()
	var total := _lengths[column.trail][_lengths[column.trail].size() - 1]
	for i in column.count:
		var at := column.head - column.direction * i * column.spacing
		if at < 0.0 or at > total:
			continue
		var p := _point(column.trail, at)
		var ahead := _point(column.trail, at + column.direction * 6.0)
		var side := p.direction_to(ahead).orthogonal()
		result.append(p + side * (column.aside[i] + sin(_time * 3.0 + i * 1.7) * 3.0))
	return result


func _process(delta: float) -> void:
	if not is_instance_valid(player) or data == null or data.trails.is_empty():
		return
	_time += delta
	var center := player.global_position
	for column in columns:
		var total := _lengths[column.trail][_lengths[column.trail].size() - 1]
		column.head += column.direction * column.speed * delta
		var tail := column.head - column.direction * column.count * column.spacing
		if (column.direction > 0.0 and tail > total) or (column.direction < 0.0 and tail < 0.0):
			# Gone off the trail's end: turn round with a fresh line.
			column.direction = -column.direction
			column.head = clampf(column.head, 0.0, total)
		# Step aside round the player.
		for i in column.count:
			var at := column.head - column.direction * i * column.spacing
			var p := _point(column.trail, at)
			var want := 0.0
			var offset := p - center
			if offset.length() < AVOID:
				var ahead := _point(column.trail, at + column.direction * 6.0)
				var side := p.direction_to(ahead).orthogonal()
				want = (AVOID - offset.length() + 20.0) * (1.0 if offset.dot(side) >= 0.0 else -1.0)
			column.aside[i] = move_toward(column.aside[i], want, delta * 160.0)
		if _point(column.trail, column.head).distance_to(center) > FAR:
			_restart(column, 500.0, 900.0)
	queue_redraw()


func _draw() -> void:
	var cell := Vector2.ONE * STEP
	for column in columns:
		var positions := ant_positions(column)
		for i in positions.size():
			var at := (positions[i] / STEP).floor()
			var step := int(_time * 10.0 + i) % 2
			# Three body segments along the way it walks (drawn sideways or upright).
			var ahead := _point(column.trail, column.head - column.direction * i * column.spacing + column.direction * 8.0)
			var direction := positions[i].direction_to(ahead)
			var along := Vector2(signf(direction.x), 0.0) if absf(direction.x) > absf(direction.y) else Vector2(0.0, signf(direction.y))
			if along == Vector2.ZERO:
				along = Vector2.RIGHT
			var across := Vector2(-along.y, along.x)
			for k in [-2, -1, 0, 1, 2]:
				draw_rect(Rect2((at + along * k) * STEP, cell), BODY if k != 1 else SHINE)
			for k in [-1, 0, 1]:
				var swing := (1 if (k + step) % 2 == 0 else 0)
				draw_rect(Rect2((at + along * (k + swing * 0.0) + across * 2.0 + along * swing) * STEP, cell), LEG)
				draw_rect(Rect2((at + along * k - across * 2.0 - along * swing) * STEP, cell), LEG)
			if column.loads[i] >= 0 and i < column.loads.size():
				var load := LOADS[column.loads[i]]
				draw_rect(Rect2((at + along * 2.0 + Vector2(0, -2)) * STEP, cell * 2.0), load)
				draw_rect(Rect2((at + along * 2.0 + Vector2(0, -2)) * STEP, cell), load.lightened(0.3))
