class_name NelvarVoidHazards
extends RefCounted
## What the Only One leaves on the arena. Every hazard shows itself before it hurts
## (a crack before the rift opens, a ring before the pull bursts, faint sectors
## before the collapse), checks the player itself and frees itself when done.
## Damage goes through NelvarPlayer.take_damage, so flight and the short
## invulnerability after a hit protect as usual. All hazards are in the group
## "void_hazards" and are cleared when the boss dies.

const VOID := Color(0.02, 0.0, 0.05)
const VIOLET := Color(0.62, 0.4, 1.0)
const PALE := Color(0.88, 0.82, 1.0)
const GRID := 3.0


class Hazard:
	extends Node2D
	var player: NelvarPlayer
	var damage := 20.0
	var age := 0.0

	func _init() -> void:
		add_to_group("void_hazards")
		z_index = 3
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _physics_process(delta: float) -> void:
		age += delta
		_step(delta)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _step(_delta: float) -> void:
		pass

	func hurt() -> void:
		if is_instance_valid(player) and not player.is_falling():
			player.take_damage(damage)

	func player_point() -> Vector2:
		return player.global_position if is_instance_valid(player) else Vector2.INF

	func dot(point: Vector2, size: float, color: Color) -> void:
		var at := (point / GRID).floor() * GRID
		draw_rect(Rect2(at - Vector2.ONE * floorf(size / GRID * 0.5) * GRID, Vector2.ONE * size), color)


## A short-lived flash: an expanding ring. Purely visual.
class Burst:
	extends Hazard
	var radius := 100.0
	var life := 0.45
	var color := PALE

	func _step(_delta: float) -> void:
		if age >= life:
			queue_free()

	func _draw() -> void:
		var k := clampf(age / life, 0.0, 1.0)
		var fill := VIOLET
		fill.a = 0.35 * (1.0 - k)
		draw_circle(Vector2.ZERO, radius * (0.4 + 0.6 * k), fill)
		var ring := color
		ring.a = 1.0 - k
		draw_arc(Vector2.ZERO, radius * (0.5 + 0.5 * k), 0.0, TAU, 64, ring, maxf(1.0, 9.0 * (1.0 - k)))


## The Void left behind a dash, hurting whoever steps in it until it fades.
class Trail:
	extends Hazard
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var width := 30.0
	var life := 0.7

	func _step(_delta: float) -> void:
		if age >= life:
			queue_free()
			return
		var closest := Geometry2D.get_closest_point_to_segment(player_point(), from, to)
		if age > 0.05 and player_point().distance_to(closest) < width * 0.5 + 8.0:
			hurt()

	func _draw() -> void:
		var fade := 1.0 - clampf(age / life, 0.0, 1.0)
		var core := VOID
		core.a = 0.85 * fade
		draw_line(from, to, core, width)
		var edge := VIOLET
		edge.a = fade
		var length := from.distance_to(to)
		var direction := from.direction_to(to)
		var side := direction.orthogonal()
		var along := 0.0
		while along < length:
			var wobble := sin(along * 0.31 + age * 9.0) * 3.0
			dot(from + direction * along + side * (width * 0.5 + wobble), 3.0, edge)
			dot(from + direction * along - side * (width * 0.5 - wobble), 3.0, edge)
			along += 6.0


## A circle that drags the player to its centre, then bursts inside.
class Pull:
	extends Hazard
	var radius := 240.0
	var duration := 2.0
	var strength := 150.0
	## The pull reaches past the circle (by this factor), so it catches.
	var reach := 1.6
	var _burst := false

	func _step(delta: float) -> void:
		var point := player_point()
		var offset := global_position - point
		if age < duration:
			if is_instance_valid(player) and not player.is_airborne() and not player.is_falling():
				var distance := offset.length()
				if distance < radius * reach and distance > 4.0:
					var pull := strength * (0.6 + 0.4 * (1.0 - distance / (radius * reach)))
					player.move_and_collide(offset / distance * minf(pull * delta, distance))
			return
		if not _burst:
			_burst = true
			if offset.length() < radius + 6.0:
				hurt()
			var burst := Burst.new()
			burst.radius = radius
			burst.position = position
			get_parent().add_child(burst)
			queue_free()

	func _draw() -> void:
		var k := clampf(age / duration, 0.0, 1.0)
		var fill := VOID
		fill.a = 0.15 + 0.4 * k
		draw_circle(Vector2.ZERO, radius, fill)
		var ring := VIOLET
		for i in 48:
			var angle := TAU * i / 48.0 + age * 0.6
			ring.a = 0.45 + 0.45 * k if (i + int(age * 20.0)) % 3 != 0 else 0.25
			dot(Vector2.from_angle(angle) * radius, 6.0, ring)
		# Motes falling inwards; the outer ring shows how far the pull reaches.
		var mote := PALE
		for i in 30:
			var phase := fmod(age * 0.7 + float(i) / 30.0, 1.0)
			var angle := TAU * float(i * 7) / 30.0 + phase * 1.5
			mote.a = 0.8 * phase
			dot(Vector2.from_angle(angle) * radius * reach * (1.0 - phase), 3.0, mote)
		var outer := VIOLET
		outer.a = 0.25
		draw_arc(Vector2.ZERO, radius * reach, 0.0, TAU, 72, outer, 2.0)


## A crack across the floor that opens after a delay.
class Rift:
	extends Hazard
	var direction := Vector2.RIGHT
	var length := 900.0
	var width := 44.0
	var telegraph := 0.8
	var open_time := 0.35
	var close_time := 0.3
	var _edge: PackedVector2Array

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(global_position) ^ hash(direction)
		var side := direction.orthogonal()
		var along := 0.0
		while along <= length:
			_edge.append(direction * along + side * rng.randf_range(-7.0, 7.0))
			along += 24.0

	func _step(_delta: float) -> void:
		if age >= telegraph + open_time + close_time:
			queue_free()
			return
		if age >= telegraph and age < telegraph + open_time:
			var local := player_point() - global_position
			var closest := Geometry2D.get_closest_point_to_segment(local, Vector2.ZERO, direction * length)
			if local.distance_to(closest) < width * 0.5 + 6.0:
				hurt()

	func _draw() -> void:
		if age < telegraph:
			# The crack runs out over the floor, brightening as it is about to open.
			var grown := clampf(age / 0.25, 0.0, 1.0)
			var count := maxi(2, int(_edge.size() * grown))
			var crack := VIOLET
			crack.a = 0.45 + 0.4 * (age / telegraph) + (0.15 if int(age * 18.0) % 2 == 0 else 0.0)
			draw_polyline(_edge.slice(0, count), crack, 3.0)
			return
		var open := age - telegraph
		var spread := 1.0 if open < open_time else 1.0 - (open - open_time) / close_time
		var half := width * 0.5 * spread
		if half < 1.0:
			return
		var side := direction.orthogonal()
		var core := VOID
		core.a = 0.95 * spread
		# Segment by segment: each quad is convex, so it always triangulates.
		for i in range(1, _edge.size()):
			draw_colored_polygon(PackedVector2Array([
				_edge[i - 1] + side * half, _edge[i] + side * half,
				_edge[i] - side * half * 0.8, _edge[i - 1] - side * half * 0.8]), core)
		var rim := PALE if open < open_time else VIOLET
		rim.a = spread
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		for point in _edge:
			top.append(point + side * half)
			bottom.append(point - side * half * 0.8)
		draw_polyline(top, rim, 3.0)
		draw_polyline(bottom, rim, 3.0)


## Collapse: sectors of the arena around the boss tear open, turn, tear again.
class Sectors:
	extends Hazard
	var count := 6
	var arc := 0.5
	var start := 0.0
	var turn := 0.35
	var cycles := 4
	var telegraph := 0.85
	var fire_time := 0.3
	var inner := 70.0
	var outer := 1100.0

	func _step(_delta: float) -> void:
		var cycle := int(age / (telegraph + fire_time))
		if cycle >= cycles:
			queue_free()
			return
		var local := age - cycle * (telegraph + fire_time)
		if local < telegraph:
			return
		var offset := player_point() - global_position
		var distance := offset.length()
		if distance < inner or distance > outer:
			return
		for i in count:
			var center := start + cycle * turn + TAU * i / count
			if absf(angle_difference(offset.angle(), center)) < arc * 0.5:
				hurt()
				return

	func _draw() -> void:
		var cycle := mini(int(age / (telegraph + fire_time)), cycles - 1)
		var local := age - cycle * (telegraph + fire_time)
		var firing := local >= telegraph
		for i in count:
			var center := start + cycle * turn + TAU * i / count
			var shape := PackedVector2Array()
			for j in 13:
				shape.append(Vector2.from_angle(center - arc * 0.5 + arc * j / 12.0) * outer)
			for j in range(12, -1, -1):
				shape.append(Vector2.from_angle(center - arc * 0.5 + arc * j / 12.0) * inner)
			# Warning: a faint flicker that thickens; the tear itself burns bright.
			var fill := VIOLET
			fill.a = 0.55 if firing else 0.05 + 0.1 * (local / telegraph) + (0.05 if int(age * 16.0) % 2 == 0 else 0.0)
			draw_colored_polygon(shape, fill)
			var edge := PALE if firing else VIOLET
			edge.a = 0.9 if firing else 0.35 + 0.4 * (local / telegraph)
			shape.append(shape[0])
			draw_polyline(shape, edge, 3.0 if firing else 2.0)


## A shard of the Void: flies out, stops, then comes back to the boss.
class Shard:
	extends Hazard
	var direction := Vector2.RIGHT
	var out_speed := 420.0
	var out_time := 0.75
	var hold := 0.45
	var back_speed := 560.0
	var boss: Node2D

	func _init() -> void:
		super()
		z_as_relative = false
		z_index = 6

	func _step(delta: float) -> void:
		if age < out_time:
			position += direction * out_speed * delta
		elif age >= out_time + hold:
			if not is_instance_valid(boss) or age > 9.0:
				queue_free()
				return
			var home := boss.global_position + Vector2(0.0, -14.0)
			var to_home := home - global_position
			if to_home.length() < 24.0:
				queue_free()
				return
			position += to_home.normalized() * minf(back_speed * delta, to_home.length())
		if player_point().distance_to(global_position + Vector2(0.0, 14.0)) < 22.0:
			hurt()
			queue_free()

	func _draw() -> void:
		var resting := age >= out_time and age < out_time + hold
		var core := PALE if not resting or int(age * 14.0) % 2 == 0 else VIOLET
		dot(Vector2.ZERO, 6.0, core)
		for offset: Vector2 in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
			dot(offset, 3.0, VIOLET)
		var shadow := VOID
		shadow.a = 0.5
		dot(Vector2(0.0, 14.0), 6.0, shadow)


## Squeeze: a ring of the Void closes in on the boss; one gap lets the player out.
class Squeeze:
	extends Hazard
	var start_radius := 1050.0
	var band := 140.0
	var gap := 0.0
	## Width of the gap along the ring, world units.
	var gap_width := 180.0
	var duration := 6.0
	var warn := 0.8
	var collapse_radius := 170.0
	var collapse_damage := 30.0

	func radius_at(time: float) -> float:
		var k := clampf((time - warn) / (duration - warn), 0.0, 1.0)
		return start_radius * (1.0 - k)

	func _half_gap(radius: float) -> float:
		return clampf(gap_width * 0.5 / maxf(radius + band * 0.5, 1.0), 0.06, PI)

	func _step(_delta: float) -> void:
		var offset := player_point() - global_position
		var distance := offset.length()
		if age >= duration:
			if distance < collapse_radius:
				damage = collapse_damage
				hurt()
			var burst := Burst.new()
			burst.radius = collapse_radius
			burst.position = position
			get_parent().add_child(burst)
			queue_free()
			return
		if age < warn:
			return
		var r := radius_at(age)
		if distance >= r and distance <= r + band \
				and absf(angle_difference(offset.angle(), gap)) > _half_gap(r):
			hurt()

	func _draw() -> void:
		var r := radius_at(age)
		var half := _half_gap(r)
		var shown := clampf(age / warn, 0.0, 1.0)
		var fill := VOID
		fill.a = 0.75 * shown
		draw_arc(Vector2.ZERO, r + band * 0.5, gap + half, gap + TAU - half, 96, fill, band)
		var rim := VIOLET
		rim.a = shown
		draw_arc(Vector2.ZERO, maxf(r, 1.0), gap + half, gap + TAU - half, 96, rim, 3.0)
		draw_arc(Vector2.ZERO, r + band, gap + half, gap + TAU - half, 96, rim, 3.0)
		var light := PALE
		light.a = shown
		for edge in [gap + half, gap - half]:
			draw_line(Vector2.from_angle(edge) * r, Vector2.from_angle(edge) * (r + band), light, 4.0)
