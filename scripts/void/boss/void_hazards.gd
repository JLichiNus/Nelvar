class_name NelvarVoidHazards
extends RefCounted
## What the Only One leaves on the arena. Every hazard shows itself before it hurts
## (a crack before the rift opens, a vortex before the pull bursts, faint sectors
## before the collapse), checks the player itself and frees itself when done.
## Damage goes through NelvarPlayer.take_damage, so flight and the short
## invulnerability after a hit protect as usual. All hazards are in the group
## "void_hazards" and are cleared when the boss dies.
##
## Each hazard draws twice: the Void itself (dark, normal blending) and its light
## (`_draw_glow`, added on top), and casts violet light on the arena, throws pixel
## sparks and shakes the screen when it strikes (NelvarVoidFx).

const VOID := Color(0.02, 0.0, 0.05)
const VIOLET := NelvarVoidFx.VIOLET
const PALE := NelvarVoidFx.PALE
const DEEP := NelvarVoidFx.DEEP
const GRID := 3.0


class Hazard:
	extends Node2D
	var player: NelvarPlayer
	var damage := 20.0
	var age := 0.0
	var _glow: Node2D

	func _init() -> void:
		add_to_group("void_hazards")
		z_index = 3
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _ready() -> void:
		_glow = Node2D.new()
		_glow.name = "Glow"
		_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = add
		_glow.draw.connect(_draw_glow)
		add_child(_glow)
		_setup()

	func _physics_process(delta: float) -> void:
		age += delta
		_step(delta)

	func _process(_delta: float) -> void:
		queue_redraw()
		_glow.queue_redraw()

	func _setup() -> void:
		pass

	func _step(_delta: float) -> void:
		pass

	func _draw_glow() -> void:
		pass

	func hurt() -> void:
		if is_instance_valid(player) and not player.is_falling():
			player.take_damage(damage)

	func player_point() -> Vector2:
		return player.global_position if is_instance_valid(player) else Vector2.INF

	## Stops a continuous emitter after `delay` (its last sparks still finish).
	func _stop_later(particles: CPUParticles2D, delay: float) -> void:
		await get_tree().create_timer(delay, false).timeout
		if is_instance_valid(particles):
			particles.emitting = false

	## A square on the art grid, on this node (dark) or on its light layer.
	func dot(point: Vector2, size: float, color: Color, glow := false) -> void:
		var at := (point / GRID).floor() * GRID - Vector2.ONE * floorf(size / GRID * 0.5) * GRID
		(_glow if glow else self).draw_rect(Rect2(at, Vector2.ONE * size), color)

	## Pixel sparks along the line from `a` to `b` (local), thrown up off the floor.
	func sparks_along(a: Vector2, b: Vector2, amount: int, color: Color, speed: float,
			lifetime: float, one_shot := true) -> CPUParticles2D:
		var particles := NelvarVoidFx.spark_emitter(color)
		particles.position = (a + b) * 0.5
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		particles.emission_rect_extents = Vector2(a.distance_to(b) * 0.5, 4.0)
		particles.rotation = a.angle_to_point(b)
		particles.amount = maxi(1, amount)
		particles.lifetime = lifetime
		particles.one_shot = one_shot
		particles.explosiveness = 0.85 if one_shot else 0.0
		# Up the screen = up off the floor; local coordinates are rotated, so aim globally.
		particles.local_coords = false
		particles.direction = Vector2(0.0, -1.0).rotated(-particles.rotation)
		particles.spread = 35.0
		# Gravity is global for particles in world coordinates.
		particles.gravity = Vector2(0.0, speed * 1.4)
		particles.initial_velocity_min = speed * 0.4
		particles.initial_velocity_max = speed
		add_child(particles)
		particles.emitting = true
		return particles


## A flash where something burst: light, sparks, a ring tearing outward, a shockwave.
class Burst:
	extends Hazard
	var radius := 100.0
	var life := 0.5
	var color := PALE
	## How hard it shakes the screen (0 = not at all).
	var power := 0.6
	var _rays: Array[PackedVector2Array] = []

	func _setup() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(global_position) ^ int(radius)
		for i in 9:
			var ray := PackedVector2Array([Vector2.ZERO])
			var angle := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
			var point := Vector2.ZERO
			for step in 5:
				point += Vector2.from_angle(angle + rng.randf_range(-0.45, 0.45)) * radius * 0.22
				ray.append(point)
			_rays.append(ray)
		NelvarVoidFx.flash_light(self, Vector2.ZERO, VIOLET, 1.8, radius * 1.8, life * 1.4)
		NelvarVoidFx.burst(self, Vector2.ZERO, clampi(int(radius / 5.0), 12, 60), color, radius * 2.2, 0.7)
		NelvarVoidFx.burst(self, Vector2.ZERO, clampi(int(radius / 9.0), 6, 30), Color(0.05, 0.02, 0.1),
			radius * 1.5, 0.9, 0.0, false)
		if power > 0.0:
			NelvarVoidFx.shock(self, global_position, power)

	func _step(_delta: float) -> void:
		if age >= life + 0.9:
			queue_free()

	func _draw() -> void:
		var k := clampf(age / life, 0.0, 1.0)
		if k >= 1.0:
			return
		var fill := VOID
		fill.a = 0.6 * (1.0 - k)
		draw_circle(Vector2.ZERO, radius * (0.3 + 0.7 * k), fill)

	func _draw_glow() -> void:
		var k := clampf(age / life, 0.0, 1.0)
		if k >= 1.0:
			return
		var ring := color
		ring.a = 1.0 - k
		_glow.draw_arc(Vector2.ZERO, radius * (0.45 + 0.55 * k), 0.0, TAU, 72, ring, maxf(1.0, 10.0 * (1.0 - k)))
		var inner := VIOLET
		inner.a = 0.5 * (1.0 - k)
		_glow.draw_arc(Vector2.ZERO, radius * (0.2 + 0.4 * k), 0.0, TAU, 48, inner, 4.0)
		var crack := PALE
		crack.a = 0.9 * (1.0 - k)
		for ray in _rays:
			var shown := ray.slice(0, 1 + int(clampf(k * 3.0, 0.0, 1.0) * (ray.size() - 1)))
			if shown.size() >= 2:
				_glow.draw_polyline(shown, crack, 3.0)


## The Void left behind a dash, hurting whoever steps in it until it fades.
class Trail:
	extends Hazard
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var width := 30.0
	var life := 0.7

	func _setup() -> void:
		var sparks := sparks_along(from, to, int(from.distance_to(to) / 8.0), VIOLET, 60.0,
			minf(life, 1.2), false)
		_stop_later(sparks, maxf(life - 0.3, 0.1))

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
		core.a = 0.9 * fade
		draw_line(from, to, core, width)

	func _draw_glow() -> void:
		var fade := 1.0 - clampf(age / life, 0.0, 1.0)
		var length := from.distance_to(to)
		var direction := from.direction_to(to)
		var side := direction.orthogonal()
		var edge := VIOLET
		var along := 0.0
		while along < length:
			var wobble := sin(along * 0.31 + age * 9.0) * 3.0
			edge.a = fade * (0.6 + 0.4 * sin(along * 0.2 - age * 14.0))
			dot(from + direction * along + side * (width * 0.5 + wobble), 3.0, edge, true)
			dot(from + direction * along - side * (width * 0.5 - wobble), 3.0, edge, true)
			along += 6.0
		var core := DEEP
		core.a = 0.5 * fade
		_glow.draw_line(from, to, core, 4.0)


## A vortex that drags the player to its centre, then bursts inside.
class Pull:
	extends Hazard
	var radius := 240.0
	var duration := 2.0
	var strength := 150.0
	## The pull reaches past the circle (by this factor), so it catches.
	var reach := 1.6
	var _burst := false
	var _light: PointLight2D

	func _setup() -> void:
		_light = NelvarVoidFx.make_light(VIOLET, 0.1, radius * 1.5)
		add_child(_light)
		# Motes spiralling in from the edge of its reach.
		var motes := NelvarVoidFx.spark_emitter(PALE)
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
		motes.emission_sphere_radius = radius * reach
		motes.amount = 70
		motes.lifetime = 0.9
		motes.gravity = Vector2.ZERO
		motes.radial_accel_min = -radius * 2.4
		motes.radial_accel_max = -radius * 1.8
		motes.tangential_accel_min = radius * 0.8
		motes.tangential_accel_max = radius * 1.2
		add_child(motes)
		motes.emitting = true

	func _step(delta: float) -> void:
		var point := player_point()
		var offset := global_position - point
		if age < duration:
			_light.energy = 0.2 + 1.3 * (age / duration) * (0.85 + 0.15 * sin(age * 18.0))
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
			burst.power = 0.9
			burst.position = position
			get_parent().add_child(burst)
			queue_free()

	func _draw() -> void:
		var k := clampf(age / duration, 0.0, 1.0)
		var fill := VOID
		fill.a = 0.2 + 0.45 * k
		draw_circle(Vector2.ZERO, radius, fill)

	func _draw_glow() -> void:
		var k := clampf(age / duration, 0.0, 1.0)
		# Three spiral arms turning inwards, faster as it charges.
		for arm in 3:
			for step in 28:
				var t := float(step) / 28.0
				var angle := TAU * arm / 3.0 + t * 4.2 - age * (2.0 + 4.0 * k)
				var color := VIOLET.lerp(PALE, t)
				color.a = (0.25 + 0.6 * k) * (1.0 - t * 0.4)
				dot(Vector2.from_angle(angle) * radius * (1.0 - t), 3.0 + floorf(t * 2.0) * 3.0, color, true)
		var ring := VIOLET
		for i in 48:
			var angle := TAU * i / 48.0 + age * 0.6
			ring.a = 0.45 + 0.5 * k if (i + int(age * 20.0)) % 3 != 0 else 0.2
			dot(Vector2.from_angle(angle) * radius, 6.0, ring, true)
		var outer := VIOLET
		outer.a = 0.22
		_glow.draw_arc(Vector2.ZERO, radius * reach, 0.0, TAU, 72, outer, 2.0)
		# The heart of it swells until it bursts.
		var core := PALE
		core.a = 0.35 + 0.5 * k
		_glow.draw_circle(Vector2.ZERO, 6.0 + 22.0 * k * (0.9 + 0.1 * sin(age * 30.0)), core)


## A crack across the floor that opens after a delay, erupting with the Void.
class Rift:
	extends Hazard
	var direction := Vector2.RIGHT
	var length := 900.0
	var width := 44.0
	var telegraph := 0.8
	var open_time := 0.35
	var close_time := 0.3
	var _edge: PackedVector2Array
	var _opened := false
	var _seed := 0

	func _setup() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(global_position) ^ hash(direction)
		_seed = rng.randi()
		var side := direction.orthogonal()
		var along := 0.0
		while along <= length:
			_edge.append(direction * along + side * rng.randf_range(-7.0, 7.0))
			along += 24.0
		# Dust trickling up out of the crack while it waits.
		var dust := sparks_along(Vector2.ZERO, direction * length, int(length / 40.0), VIOLET, 30.0, 0.8, false)
		_stop_later(dust, telegraph)

	func _step(_delta: float) -> void:
		if age >= telegraph + open_time + close_time + 0.9:
			queue_free()
			return
		if age >= telegraph and not _opened:
			_opened = true
			_erupt()
		if age >= telegraph and age < telegraph + open_time:
			var local := player_point() - global_position
			var closest := Geometry2D.get_closest_point_to_segment(local, Vector2.ZERO, direction * length)
			if local.distance_to(closest) < width * 0.5 + 6.0:
				hurt()

	## Opening: the Void bursts out along the whole crack.
	func _erupt() -> void:
		sparks_along(Vector2.ZERO, direction * length, int(length / 7.0), PALE, 260.0, 0.6)
		sparks_along(Vector2.ZERO, direction * length, int(length / 14.0), DEEP, 180.0, 0.8)
		for i in 3:
			NelvarVoidFx.flash_light(self, direction * length * (0.2 + 0.3 * i), VIOLET, 1.4,
				minf(length * 0.35, 300.0), 0.6)
		NelvarVoidFx.shock(self, global_position + direction * length * 0.3, 0.35)

	func _draw() -> void:
		if age < telegraph:
			return
		var spread := _spread()
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

	func _spread() -> float:
		var open := age - telegraph
		if open < 0.0:
			return 0.0
		if open < 0.08:
			return open / 0.08
		if open < open_time:
			return 1.0
		return maxf(0.0, 1.0 - (open - open_time) / close_time)

	func _draw_glow() -> void:
		if age < telegraph:
			# The crack runs out over the floor, brightening as it is about to open;
			# sparks crawl along it.
			var grown := clampf(age / 0.25, 0.0, 1.0)
			var count := maxi(2, int(_edge.size() * grown))
			var crack := VIOLET
			crack.a = 0.45 + 0.45 * (age / telegraph) + (0.15 if int(age * 18.0) % 2 == 0 else 0.0)
			_glow.draw_polyline(_edge.slice(0, count), crack, 3.0)
			var crawl := PALE
			for i in 4:
				var along := fmod(age * 700.0 + i * length / 4.0, length * grown)
				crawl.a = crack.a
				dot(direction * along, 6.0, crawl, true)
			return
		var spread := _spread()
		var half := width * 0.5 * spread
		if half < 1.0:
			return
		var side := direction.orthogonal()
		var rim := PALE if age < telegraph + open_time else VIOLET
		rim.a = spread
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		for point in _edge:
			top.append(point + side * half)
			bottom.append(point - side * half * 0.8)
		_glow.draw_polyline(top, rim, 3.0)
		_glow.draw_polyline(bottom, rim, 3.0)
		# Energy boiling inside the open rift.
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed + int(age * 20.0)
		var boil := VIOLET
		for i in int(length / 10.0):
			boil.a = rng.randf_range(0.3, 0.9) * spread
			dot(direction * rng.randf() * length + side * rng.randf_range(-half * 0.7, half * 0.6),
				3.0 if rng.randf() < 0.7 else 6.0, boil, true)


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
	var _fired := -1

	func _cycle() -> int:
		return int(age / (telegraph + fire_time))

	func _center(cycle: int, i: int) -> float:
		return start + cycle * turn + TAU * i / count

	func _step(_delta: float) -> void:
		var cycle := _cycle()
		if cycle >= cycles:
			queue_free()
			return
		var local := age - cycle * (telegraph + fire_time)
		if local < telegraph:
			return
		if _fired != cycle:
			_fired = cycle
			_tear(cycle)
		var offset := player_point() - global_position
		var distance := offset.length()
		if distance < inner or distance > outer:
			return
		for i in count:
			if absf(angle_difference(offset.angle(), _center(cycle, i))) < arc * 0.5:
				hurt()
				return

	func _tear(cycle: int) -> void:
		for i in count:
			var axis := Vector2.from_angle(_center(cycle, i))
			sparks_along(axis * inner, axis * minf(outer, 900.0), 40, PALE, 220.0, 0.55)
		NelvarVoidFx.flash_light(self, Vector2.ZERO, VIOLET, 1.6, 900.0, 0.5)
		NelvarVoidFx.shock(self, global_position, 0.55)

	func _shape(center: float) -> PackedVector2Array:
		var shape := PackedVector2Array()
		for j in 13:
			shape.append(Vector2.from_angle(center - arc * 0.5 + arc * j / 12.0) * outer)
		for j in range(12, -1, -1):
			shape.append(Vector2.from_angle(center - arc * 0.5 + arc * j / 12.0) * inner)
		return shape

	func _draw() -> void:
		var cycle := mini(_cycle(), cycles - 1)
		var local := age - cycle * (telegraph + fire_time)
		if local < telegraph:
			return
		for i in count:
			var fill := VOID
			fill.a = 0.6
			draw_colored_polygon(_shape(_center(cycle, i)), fill)

	func _draw_glow() -> void:
		var cycle := mini(_cycle(), cycles - 1)
		var local := age - cycle * (telegraph + fire_time)
		var firing := local >= telegraph
		for i in count:
			var center := _center(cycle, i)
			var shape := _shape(center)
			var fill := VIOLET
			fill.a = 0.45 * (1.0 - (local - telegraph) / fire_time) if firing \
				else 0.04 + 0.1 * (local / telegraph) + (0.04 if int(age * 16.0) % 2 == 0 else 0.0)
			_glow.draw_colored_polygon(shape, fill)
			var edge := PALE if firing else VIOLET
			edge.a = 0.9 if firing else 0.3 + 0.45 * (local / telegraph)
			shape.append(shape[0])
			_glow.draw_polyline(shape, edge, 3.0 if firing else 2.0)
			if not firing:
				# Sparks running out along both edges, faster as it is about to tear.
				for side in [-0.5, 0.5]:
					var axis := Vector2.from_angle(center + arc * side)
					var along := inner + fmod(local * 900.0 + i * 97.0, outer - inner)
					dot(axis * along, 6.0, PALE, true)


## A shard of the Void: flies out, stops, then comes back to the boss.
class Shard:
	extends Hazard
	var direction := Vector2.RIGHT
	var out_speed := 420.0
	var out_time := 0.75
	var hold := 0.45
	var back_speed := 560.0
	var boss: Node2D
	var _trail: Array[Vector2] = []

	func _init() -> void:
		super()
		z_as_relative = false
		z_index = 6

	func _step(delta: float) -> void:
		_trail.push_front(global_position)
		if _trail.size() > 9:
			_trail.pop_back()
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
			NelvarVoidFx.burst(get_parent(), global_position, 10, PALE, 160.0, 0.35)
			queue_free()

	func _draw() -> void:
		var shadow := VOID
		shadow.a = 0.5
		dot(Vector2(0.0, 14.0), 6.0, shadow)
		dot(Vector2.ZERO, 6.0, Color(0.05, 0.02, 0.1))

	func _draw_glow() -> void:
		for i in range(1, _trail.size()):
			var color := VIOLET
			color.a = 0.5 * (1.0 - float(i) / _trail.size())
			dot(_trail[i] - global_position, 3.0, color, true)
		var resting := age >= out_time and age < out_time + hold
		var halo := VIOLET
		halo.a = 0.3
		_glow.draw_circle(Vector2.ZERO, 11.0, halo)
		var core := PALE if not resting or int(age * 14.0) % 2 == 0 else VIOLET
		var spin := age * 9.0
		for k in 4:
			dot(Vector2.from_angle(spin + k * PI / 2.0) * 6.0, 3.0, VIOLET, true)
		dot(Vector2.ZERO, 3.0, core, true)


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
	var _gap_light: PointLight2D

	func _setup() -> void:
		# A pillar of light marks the way out.
		_gap_light = NelvarVoidFx.make_light(PALE, 1.2, 220.0)
		add_child(_gap_light)

	func radius_at(time: float) -> float:
		var k := clampf((time - warn) / (duration - warn), 0.0, 1.0)
		return start_radius * (1.0 - k)

	func _half_gap(radius: float) -> float:
		return clampf(gap_width * 0.5 / maxf(radius + band * 0.5, 1.0), 0.06, PI)

	func _step(_delta: float) -> void:
		var offset := player_point() - global_position
		var distance := offset.length()
		var r := radius_at(age)
		_gap_light.position = Vector2.from_angle(gap) * (r + band * 0.5)
		_gap_light.energy = (0.8 + 0.4 * sin(age * 6.0)) * clampf(age / warn, 0.0, 1.0)
		if age >= duration:
			if distance < collapse_radius:
				damage = collapse_damage
				hurt()
			var burst := Burst.new()
			burst.radius = collapse_radius * 1.6
			burst.power = 1.0
			burst.position = position
			get_parent().add_child(burst)
			NelvarVoidFx.flash(self, PALE, 0.25, 0.4)
			queue_free()
			return
		if age < warn:
			return
		if distance >= r and distance <= r + band \
				and absf(angle_difference(offset.angle(), gap)) > _half_gap(r):
			hurt()

	func _draw() -> void:
		var r := radius_at(age)
		var half := _half_gap(r)
		var shown := clampf(age / warn, 0.0, 1.0)
		var fill := VOID
		fill.a = 0.78 * shown
		draw_arc(Vector2.ZERO, r + band * 0.5, gap + half, gap + TAU - half, 96, fill, band)

	func _draw_glow() -> void:
		var r := radius_at(age)
		var half := _half_gap(r)
		var shown := clampf(age / warn, 0.0, 1.0)
		var rim := VIOLET
		rim.a = shown
		_glow.draw_arc(Vector2.ZERO, maxf(r, 1.0), gap + half, gap + TAU - half, 96, rim, 4.0)
		_glow.draw_arc(Vector2.ZERO, r + band, gap + half, gap + TAU - half, 96, rim, 3.0)
		# The Void churning inside the band.
		var churn := VIOLET
		for i in 90:
			var angle := gap + half + (TAU - half * 2.0) * fmod(float(i) / 90.0 + age * 0.05, 1.0)
			var depth := fmod(i * 0.37 + age * 0.6, 1.0)
			churn.a = 0.25 * shown * (1.0 - absf(depth - 0.5) * 1.6)
			dot(Vector2.from_angle(angle) * (r + band * depth), 3.0, churn, true)
		# Bright pillars at both sides of the way out.
		var light := PALE
		light.a = shown
		for edge in [gap + half, gap - half]:
			_glow.draw_line(Vector2.from_angle(edge) * r, Vector2.from_angle(edge) * (r + band), light, 5.0)


## Where a dash is about to go: a line of light from the boss to its target that
## tightens and brightens as the wind-up ends. Does no harm by itself.
class Aim:
	extends Hazard
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	## 0..1, how close the dash is.
	var charge := 0.0

	func _draw_glow() -> void:
		var length := from.distance_to(to)
		if length < 1.0:
			return
		var direction := from.direction_to(to)
		var side := direction.orthogonal()
		var spread := (1.0 - charge) * 26.0
		var color := VIOLET.lerp(PALE, charge)
		var along := 0.0
		while along < length:
			var pulse := 0.5 + 0.5 * sin(along * 0.05 - age * 22.0)
			color.a = (0.2 + 0.6 * charge) * (0.5 + 0.5 * pulse)
			dot(from + direction * along + side * spread, 3.0, color, true)
			dot(from + direction * along - side * spread, 3.0, color, true)
			along += 9.0
		var tip := PALE
		tip.a = 0.4 + 0.6 * charge
		_glow.draw_arc(to, 14.0 + 10.0 * (1.0 - charge), 0.0, TAU, 24, tip, 3.0)


## The Only One forming: a pillar of cold light from the sigil, the Void streaming
## into it from all around. Purely visual.
class Pillar:
	extends Hazard
	var life := 2.6
	var height := 900.0
	var _light: PointLight2D

	func _setup() -> void:
		_light = NelvarVoidFx.make_light(VIOLET, 0.0, 520.0)
		add_child(_light)
		var inflow := NelvarVoidFx.spark_emitter(PALE)
		inflow.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
		inflow.emission_sphere_radius = 560.0
		inflow.amount = 120
		inflow.lifetime = 1.1
		inflow.gravity = Vector2.ZERO
		inflow.radial_accel_min = -1100.0
		inflow.radial_accel_max = -900.0
		inflow.tangential_accel_min = 150.0
		inflow.tangential_accel_max = 260.0
		add_child(inflow)
		inflow.emitting = true
		_stop_later(inflow, life - 0.9)
		var rising := NelvarVoidFx.spark_emitter(VIOLET)
		rising.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		rising.emission_rect_extents = Vector2(40.0, 6.0)
		rising.amount = 50
		rising.lifetime = 1.2
		rising.direction = Vector2(0.0, -1.0)
		rising.spread = 6.0
		rising.gravity = Vector2.ZERO
		rising.initial_velocity_min = 300.0
		rising.initial_velocity_max = 700.0
		add_child(rising)
		rising.emitting = true
		_stop_later(rising, life - 0.4)

	func _step(_delta: float) -> void:
		var k := age / life
		_light.energy = 2.2 * sin(clampf(k, 0.0, 1.0) * PI)
		if age >= life + 1.2:
			queue_free()

	func _draw_glow() -> void:
		var k := clampf(age / life, 0.0, 1.0)
		var strength := sin(k * PI)
		if strength <= 0.01:
			return
		# Layers of the beam, widest and faintest outside.
		for layer in 3:
			var width := (70.0 - layer * 22.0) * (0.6 + 0.4 * strength) * (1.0 + 0.08 * sin(age * 20.0 + layer))
			var color := VIOLET.lerp(PALE, layer / 2.0)
			color.a = strength * (0.18 + layer * 0.22)
			_glow.draw_rect(Rect2(-width * 0.5, -height, width, height), color)
		var base := PALE
		base.a = strength * 0.6
		_glow.draw_circle(Vector2.ZERO, 30.0 + 30.0 * strength, base)
