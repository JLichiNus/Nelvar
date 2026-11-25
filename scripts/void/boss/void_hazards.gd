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
			player.take_damage(damage, global_position)

	func player_point() -> Vector2:
		return player.global_position if is_instance_valid(player) else Vector2.INF

	## Stops a continuous emitter after `delay` (its last sparks still finish).
	func _stop_later(particles: CPUParticles2D, delay: float) -> void:
		await get_tree().create_timer(delay, false).timeout
		if is_instance_valid(particles):
			particles.emitting = false

	## A filled quad as two triangles: never fails to triangulate, even squashed flat.
	static func quad(on: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
		on.draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([color, color, color, color]),
			PackedVector2Array())

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


## A tear in space left behind a dash. It hurts at once; after `charge` seconds it
## widens and throws a wave of the Void out to both sides (as far as `wave_reach`),
## then stays open until `life` runs out. The reach of the wave is drawn faintly
## while it charges, brighter the closer it is.
class Trail:
	extends Hazard
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var width := 30.0
	## Total life; at least `charge` plus the wave's flight.
	var life := 2.0
	## Seconds until it bursts sideways.
	var charge := 1.0
	var wave_reach := 150.0
	var wave_speed := 480.0
	## The tear is this much wider once it has burst.
	var widen := 1.45
	var _erupted := false
	var _wave_hit := false
	var _jag := PackedFloat32Array()
	var _lights: Array[PointLight2D] = []
	var _seed := 0

	func _setup() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(from) ^ hash(to)
		_seed = rng.randi()
		var length := from.distance_to(to)
		for i in int(length / 12.0) + 2:
			_jag.append(rng.randf_range(-1.0, 1.0))
		var sparks := sparks_along(from, to, int(length / 8.0), VIOLET, 60.0, 0.9, false)
		_stop_later(sparks, maxf(life - 0.4, 0.1))
		for i in 2:
			var light := NelvarVoidFx.make_light(VIOLET, 0.0, minf(length * 0.45, 260.0) + 60.0)
			light.position = from.lerp(to, 0.25 + 0.5 * i)
			add_child(light)
			_lights.append(light)

	func _fade() -> float:
		return clampf((life - age) / 0.35, 0.0, 1.0)

	func _charge_k() -> float:
		return clampf(age / charge, 0.0, 1.0)

	func _half() -> float:
		var opened := clampf((age - charge) / 0.12, 0.0, 1.0) if _erupted else 0.0
		return width * 0.5 * lerpf(1.0, widen, opened) * (0.4 + 0.6 * _fade())

	## How far the side wave has gone from the axis (or -1 before / after it).
	func _front() -> float:
		if not _erupted:
			return -1.0
		var front := width * 0.5 * widen + (age - charge) * wave_speed
		return front if front <= width * 0.5 * widen + wave_reach else -1.0

	## The two ragged edges of the tear, tapering to its ends.
	func _lips() -> Array[PackedVector2Array]:
		var direction := from.direction_to(to)
		var side := direction.orthogonal()
		var length := from.distance_to(to)
		var half := _half()
		var speed := 11.0 + 20.0 * _charge_k()
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		var count := _jag.size()
		for i in count:
			var t := float(i) / float(count - 1)
			var taper := sqrt(sin(t * PI))
			var wobble := sin(t * 31.0 + age * speed) * 2.0
			var point := from + direction * length * t
			top.append(point + side * maxf(half * taper + _jag[i] * 3.0 + wobble, 1.5))
			bottom.append(point - side * maxf(half * taper + _jag[(i + 3) % count] * 3.0 - wobble, 1.5))
		return [top, bottom]

	func _step(_delta: float) -> void:
		if age >= life:
			queue_free()
			return
		var k := _charge_k()
		for light in _lights:
			light.energy = (0.25 + 0.9 * k * k) * _fade() if not _erupted \
				else maxf(0.35, 2.2 - (age - charge) * 4.0) * _fade()
		if not _erupted and age >= charge:
			_erupted = true
			_erupt()
		var point := player_point()
		if point == Vector2.INF:
			return
		var closest := Geometry2D.get_closest_point_to_segment(point, from, to)
		var distance := point.distance_to(closest)
		if age > 0.05 and _fade() > 0.3 and distance < _half() + 8.0:
			hurt()
			return
		# The wave only runs out from the sides, not past the ends of the tear.
		var front := _front()
		var length := from.distance_to(to)
		var along := (point - from).dot(from.direction_to(to))
		if front > 0.0 and not _wave_hit and along > -10.0 and along < length + 10.0 \
				and absf(distance - front) < 16.0:
			_wave_hit = true
			hurt()

	func _erupt() -> void:
		var side := from.direction_to(to).orthogonal()
		var length := from.distance_to(to)
		for flank in [-1.0, 1.0]:
			var a: Vector2 = from + side * flank * width * 0.6
			var b: Vector2 = to + side * flank * width * 0.6
			var sparks := sparks_along(a, b, int(length / 6.0), PALE, 300.0, 0.55)
			sparks.direction = (side * flank).rotated(-sparks.rotation)
			sparks.gravity = Vector2.ZERO
			sparks.spread = 12.0
			sparks.damping_min = 300.0
			sparks.damping_max = 500.0
		sparks_along(from, to, int(length / 10.0), DEEP, 200.0, 0.8)
		NelvarVoidFx.shock(self, global_position + from.lerp(to, 0.5), 0.45)

	func _draw() -> void:
		var fade := _fade()
		var direction := from.direction_to(to)
		var side := direction.orthogonal()
		var half := _half()
		# The tear itself: a ragged black slit, its edges trembling.
		var core := VOID
		core.a = 0.92 * fade
		var lips := _lips()
		var top: PackedVector2Array = lips[0]
		var bottom: PackedVector2Array = lips[1]
		for i in range(1, top.size()):
			quad(self, top[i - 1], top[i], bottom[i], bottom[i - 1], core)
		# The wave: the Void dragged behind each front.
		var front := _front()
		if front > 0.0:
			var gone := (front - width * 0.5 * widen) / wave_reach
			var wake := VOID
			wake.a = 0.35 * (1.0 - gone) * fade
			for flank in [-1.0, 1.0]:
				var inner: Vector2 = side * flank * half
				var outer: Vector2 = side * flank * front
				quad(self, from + inner, to + inner, to + outer, from + outer, wake)

	func _draw_glow() -> void:
		var fade := _fade()
		var direction := from.direction_to(to)
		var side := direction.orthogonal()
		var length := from.distance_to(to)
		var half := _half()
		var k := _charge_k()
		# Glowing ragged lips of the tear, trembling faster as the charge nears.
		var lips := _lips()
		var haze := VIOLET
		haze.a = (0.22 + 0.25 * k) * fade
		var edge := VIOLET.lerp(PALE, k * k if not _erupted else 0.5)
		edge.a = (0.75 + 0.25 * sin(age * (10.0 + 30.0 * k))) * fade
		for lip in lips:
			_glow.draw_polyline(lip, haze, 10.0)
			_glow.draw_polyline(lip, edge, 3.0)
		# Sparks crawling along the lips.
		var crawl := PALE
		crawl.a = fade
		for i in 6:
			var t := fmod(age * (0.6 + 0.9 * k) + i / 6.0, 1.0)
			var lip: PackedVector2Array = lips[i % 2]
			dot(lip[int(t * (lip.size() - 1))], 6.0, crawl, true)
		var heart := DEEP.lerp(PALE, k * 0.5) if not _erupted else DEEP
		heart.a = (0.35 + 0.3 * k) * fade
		_glow.draw_line(from, to, heart, 2.0 + 2.0 * k)
		if not _erupted:
			# Where the wave will reach: dashed lines on both sides, and threads of light
			# reaching out from the tear towards them, growing with the charge.
			var mark := VIOLET.lerp(PALE, k * k * 0.6)
			mark.a = (0.2 + 0.6 * k * k) * (1.0 if int(age * (6.0 + 12.0 * k)) % 2 == 0 else 0.7)
			var reach := width * 0.5 * widen + wave_reach
			var step := fmod(age * 40.0, 24.0)
			while step < length - 12.0:
				for flank in [-1.0, 1.0]:
					var at: Vector2 = from + direction * step + side * flank * reach
					_glow.draw_line(at, at + direction * 12.0, mark, 3.0)
				step += 24.0
			for end in [from, to]:
				var bracket := mark
				bracket.a *= 0.6
				_glow.draw_line(end - side * reach, end + side * reach, bracket, 2.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = _seed
			var thread := PALE
			thread.a = 0.35 + 0.5 * k
			for i in int(length / 40.0):
				var at := from + direction * rng.randf() * length
				var flank := 1.0 if rng.randf() < 0.5 else -1.0
				var grown := reach * k * rng.randf_range(0.5, 1.0)
				var steps := int(grown / 9.0)
				for j in steps:
					dot(at + side * flank * (half + j * 9.0) + direction * sin(j * 1.3 + i) * 4.0, 3.0, thread, true)
			return
		# The fronts: ragged bright lines running out to both sides.
		var front := _front()
		if front <= 0.0:
			return
		var gone := (front - width * 0.5 * widen) / wave_reach
		var line := PALE.lerp(VIOLET, gone)
		line.a = (1.0 - gone * 0.7) * fade
		var glow := VIOLET
		glow.a = 0.3 * (1.0 - gone) * fade
		for flank in [-1.0, 1.0]:
			var points := PackedVector2Array()
			var along := 0.0
			while along <= length:
				var jitter := sin(along * 0.17 + age * 40.0) * 4.0 + _jag[int(along / 12.0) % _jag.size()] * 3.0
				points.append(from + direction * along + side * flank * (front + jitter))
				along += 12.0
			_glow.draw_polyline(points, glow, 12.0)
			_glow.draw_polyline(points, line, 3.0)


## A gravity well: drags the player towards its heart, harder as it charges, while
## the circle it will burst over grows from `start_radius` to `radius`. It may
## creep after the player (`follow`) or circle a point with a twin (`orbit_*`),
## and stops `lock_time` before it bursts, its rim turning pale. With
## `pulse_period` its pull swells and ebbs; a twin ebbs as this one swells.
class Pull:
	extends Hazard
	var radius := 240.0
	var start_radius := 120.0
	var duration := 2.2
	## Pull at its heart at the end of the charge, and at its start.
	var strength := 170.0
	var start_strength := 55.0
	## The pull reaches past the final circle (by this factor), so it catches.
	var reach := 1.6
	var follow: Node2D
	var follow_speed := 0.0
	var orbit_center := Vector2.INF
	var orbit_radius := 0.0
	var orbit_angle := 0.0
	var orbit_speed := 0.0
	var lock_time := 0.0
	var pulse_period := 0.0
	var pulse_offset := 0.0
	## A twin circling the same point: this one draws the orbit and the bond.
	var twin: Node2D
	var _burst := false
	var _light: PointLight2D
	var _motes: CPUParticles2D

	func _setup() -> void:
		_light = NelvarVoidFx.make_light(VIOLET, 0.1, radius * 1.6)
		add_child(_light)
		# Motes spiralling in from the edge of its reach.
		_motes = NelvarVoidFx.spark_emitter(PALE)
		_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
		_motes.emission_sphere_radius = radius * reach
		_motes.amount = 70
		_motes.lifetime = 0.9
		_motes.gravity = Vector2.ZERO
		_motes.radial_accel_min = -radius * 2.4
		_motes.radial_accel_max = -radius * 1.8
		_motes.tangential_accel_min = radius * 0.8
		_motes.tangential_accel_max = radius * 1.2
		_motes.local_coords = true
		add_child(_motes)
		_motes.emitting = true
		if orbit_center != Vector2.INF:
			position = orbit_center + Vector2.from_angle(orbit_angle) * orbit_radius

	func charge() -> float:
		return clampf(age / duration, 0.0, 1.0)

	func locked() -> bool:
		return lock_time > 0.0 and age >= duration - lock_time

	## 0.25..1: how strong it is right now against its peak (always 1 without a pulse).
	func weight() -> float:
		if pulse_period <= 0.0:
			return 1.0
		return 0.25 + 0.75 * (0.5 + 0.5 * sin(TAU * age / pulse_period + pulse_offset))

	func current_radius() -> float:
		return lerpf(start_radius, radius, ease(charge(), 0.6))

	func current_strength() -> float:
		var k := charge()
		return lerpf(start_strength, strength, k * k) * weight()

	func _step(delta: float) -> void:
		var k := charge()
		if age < duration and not locked():
			if orbit_center != Vector2.INF:
				orbit_angle += orbit_speed * delta
				position = orbit_center + Vector2.from_angle(orbit_angle) * orbit_radius
			elif is_instance_valid(follow) and follow_speed > 0.0:
				var to_target := follow.global_position - global_position
				position += to_target.limit_length(follow_speed * delta)
		var point := player_point()
		var offset := global_position - point
		if age < duration:
			_light.energy = (0.2 + 1.4 * k) * (0.55 + 0.45 * weight()) * (0.85 + 0.15 * sin(age * 18.0))
			_motes.speed_scale = 0.6 + 1.2 * weight() * (0.4 + k)
			if is_instance_valid(player) and not player.is_airborne() and not player.is_falling():
				var distance := offset.length()
				if distance < radius * reach and distance > 4.0:
					var pull := current_strength() * (0.6 + 0.4 * (1.0 - distance / (radius * reach)))
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
			NelvarVoidFx.burst(get_parent(), position, 46, VIOLET, radius * 2.6, 0.6, radius * 0.25)
			queue_free()

	func _draw() -> void:
		var k := charge()
		var fill := VOID
		fill.a = 0.18 + 0.4 * k
		draw_circle(Vector2.ZERO, current_radius(), fill)
		var heart := VOID
		heart.a = 0.5 + 0.4 * k
		draw_circle(Vector2.ZERO, current_radius() * 0.35, heart)

	func _draw_glow() -> void:
		var k := charge()
		var w := weight()
		var r := current_radius()
		var lock := locked()
		var blink := lock and int(age * 16.0) % 2 == 0
		# Three spiral arms turning inwards, faster as it charges and as it swells.
		for arm in 3:
			for step in 28:
				var t := float(step) / 28.0
				var angle := TAU * arm / 3.0 + t * 4.2 - age * (2.0 + 5.0 * k) * (0.5 + w)
				var color := VIOLET.lerp(PALE, t)
				color.a = (0.2 + 0.65 * k) * (1.0 - t * 0.4) * (0.45 + 0.55 * w)
				dot(Vector2.from_angle(angle) * r * (1.0 - t), 3.0 + floorf(t * 2.0) * 3.0, color, true)
		# The rim it will burst over: a ring of beads chasing round, pale once it stops.
		var ring := PALE if lock else VIOLET
		var beads := 56
		for i in beads:
			var angle := TAU * i / beads + age * (0.6 + 1.4 * k)
			var lit := (i + int(age * 20.0)) % 3 != 0
			ring.a = (0.5 + 0.5 * k if lit else 0.2) * (1.0 if not blink else 0.55)
			dot(Vector2.from_angle(angle) * r, 6.0 if lit else 3.0, ring, true)
		var halo := VIOLET.lerp(PALE, 0.5 if lock else 0.0)
		halo.a = 0.18 + 0.3 * k
		_glow.draw_arc(Vector2.ZERO, r, 0.0, TAU, 72, halo, 7.0)
		if lock:
			# Spikes stabbing inwards from the rim: it is about to go.
			var spike := PALE
			spike.a = 0.9 if blink else 0.5
			for i in 12:
				var axis := Vector2.from_angle(TAU * i / 12.0 + PI / 12.0)
				_glow.draw_line(axis * r, axis * (r - 18.0 - 10.0 * k), spike, 3.0)
		# How far it pulls: a faint dotted circle, flickering with its strength.
		var outer := VIOLET
		outer.a = 0.12 + 0.25 * w * (0.4 + k)
		for i in 60:
			if i % 2 == 0:
				var angle := TAU * i / 60.0 - age * 0.4
				_glow.draw_arc(Vector2.ZERO, radius * reach, angle, angle + TAU / 60.0, 3, outer, 2.0)
		if orbit_center != Vector2.INF and is_instance_valid(twin):
			_draw_orbit()
		# The heart of it swells until it bursts.
		var core := PALE
		core.a = 0.35 + 0.5 * k
		_glow.draw_circle(Vector2.ZERO, (6.0 + 22.0 * k) * (0.75 + 0.25 * w) * (0.9 + 0.1 * sin(age * 30.0)), core)
		var aura := VIOLET
		aura.a = 0.25 * w
		_glow.draw_circle(Vector2.ZERO, 14.0 + 34.0 * k * w, aura)

	## The circle both twins run along, and the bond between them, brighter
	## towards whichever pulls harder now.
	func _draw_orbit() -> void:
		var pivot := orbit_center - position
		var track := VIOLET
		track.a = 0.22
		for i in 48:
			if i % 3 != 2:
				var angle := TAU * i / 48.0 + age * orbit_speed * 0.5
				dot(pivot + Vector2.from_angle(angle) * orbit_radius, 3.0, track, true)
		var other: Vector2 = twin.position - position
		var mine := weight()
		var theirs: float = twin.call(&"weight")
		var length := other.length()
		var along := 0.0
		while along < length:
			var t := along / length
			var bond := VIOLET.lerp(PALE, absf(mine - theirs))
			bond.a = 0.15 + 0.55 * lerpf(mine, theirs, t) * (0.6 + 0.4 * sin(along * 0.08 - age * 16.0))
			dot(other * t + other.orthogonal().normalized() * sin(t * PI * 3.0 + age * 5.0) * 6.0, 3.0, bond, true)
			along += 8.0
		var center := PALE
		center.a = 0.5 + 0.3 * sin(age * 8.0)
		for i in 4:
			dot(pivot + Vector2.from_angle(TAU * i / 4.0 + age * 2.0) * 9.0, 3.0, center, true)


## A crack across the floor. After `telegraph` the Void tears it open as a wave
## running from its start to its end (`wave_speed`); each stretch stays open and
## hurts for `hold` seconds, then closes in the same order.
class Rift:
	extends Hazard
	var direction := Vector2.RIGHT
	var length := 900.0
	var width := 44.0
	var telegraph := 0.8
	var wave_speed := 1300.0
	var hold := 2.4
	var close_time := 0.3
	var _edge: PackedVector2Array
	var _along: PackedFloat32Array
	var _opened := false
	var _seed := 0
	var _head: PointLight2D
	var _head_sparks: CPUParticles2D

	func _setup() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(global_position) ^ hash(direction)
		_seed = rng.randi()
		var side := direction.orthogonal()
		var along := 0.0
		while along <= length:
			_edge.append(direction * along + side * rng.randf_range(-7.0, 7.0))
			_along.append(along)
			along += 24.0
		# Dust trickling up out of the crack while it waits.
		var dust := sparks_along(Vector2.ZERO, direction * length, int(length / 40.0), VIOLET, 30.0, 0.8, false)
		_stop_later(dust, telegraph)

	## How far the opening has run, and how far the closing.
	func _front() -> float:
		return (age - telegraph) * wave_speed

	func _tail() -> float:
		return (age - telegraph - hold) * wave_speed

	## 0..1, how open the crack is at `along` from its start.
	func open_at(along: float) -> float:
		var since := (_front() - along) / wave_speed
		if since < 0.0:
			return 0.0
		var opening := clampf(since / 0.08, 0.0, 1.0)
		var closing := 1.0 - clampf((_tail() - along) / wave_speed / close_time, 0.0, 1.0)
		return minf(opening, closing)

	func _step(_delta: float) -> void:
		if age >= telegraph + hold + length / wave_speed + close_time + 0.9:
			queue_free()
			return
		if age >= telegraph and not _opened:
			_opened = true
			_erupt()
		if _opened:
			_move_head()
		var local := player_point() - global_position
		var along := clampf(local.dot(direction), 0.0, length)
		if local.distance_to(direction * along) < width * 0.5 + 6.0 and open_at(along) > 0.5:
			hurt()

	## Opening: a head of light and sparks tears along the crack.
	func _erupt() -> void:
		_head = NelvarVoidFx.make_light(PALE, 2.0, 230.0)
		add_child(_head)
		_head_sparks = NelvarVoidFx.spark_emitter(PALE)
		_head_sparks.amount = 60
		_head_sparks.lifetime = 0.6
		_head_sparks.direction = Vector2(0.0, -1.0)
		_head_sparks.spread = 70.0
		_head_sparks.gravity = Vector2(0.0, 420.0)
		_head_sparks.initial_velocity_min = 90.0
		_head_sparks.initial_velocity_max = 300.0
		_head_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_head_sparks.emission_sphere_radius = width * 0.5
		add_child(_head_sparks)
		_head_sparks.emitting = true
		sparks_along(Vector2.ZERO, direction * length, int(length / 14.0), DEEP, 180.0, 0.8)
		NelvarVoidFx.shock(self, global_position, 0.35)

	func _move_head() -> void:
		var front := _front()
		if front <= length:
			_head.position = direction * front
			_head_sparks.position = direction * front
			_head.energy = 2.0
			return
		# The wave reached the end: its light dies away.
		_head_sparks.emitting = false
		_head.energy = maxf(0.0, _head.energy - get_physics_process_delta_time() * 4.0)

	func _draw() -> void:
		if age < telegraph:
			return
		var side := direction.orthogonal()
		# Segment by segment: each quad is convex, so it always triangulates.
		for i in range(1, _edge.size()):
			var a := open_at(_along[i - 1])
			var b := open_at(_along[i])
			if a <= 0.01 and b <= 0.01:
				continue
			var core := VOID
			core.a = 0.95 * maxf(a, b)
			quad(self, _edge[i - 1] + side * width * 0.5 * a, _edge[i] + side * width * 0.5 * b,
				_edge[i] - side * width * 0.4 * b, _edge[i - 1] - side * width * 0.4 * a, core)

	func _draw_glow() -> void:
		var front := _front()
		if age < telegraph:
			# The crack runs out over the floor, brightening as it is about to open;
			# sparks crawl along it from the end it opens from.
			var grown := clampf(age / 0.25, 0.0, 1.0)
			var count := maxi(2, int(_edge.size() * grown))
			var k := age / telegraph
			var crack := VIOLET.lerp(PALE, k * k * 0.5)
			crack.a = 0.45 + 0.45 * k + (0.15 if int(age * 18.0) % 2 == 0 else 0.0)
			_glow.draw_polyline(_edge.slice(0, count), crack, 3.0)
			var crawl := PALE
			crawl.a = crack.a
			for i in 4:
				var along := fmod(age * 700.0 + i * length / 4.0, length * grown)
				dot(direction * along, 6.0, crawl, true)
			# The start glows hotter: that is where it tears from.
			var start := PALE
			start.a = 0.3 + 0.6 * k
			_glow.draw_circle(Vector2.ZERO, 6.0 + 10.0 * k, start)
			return
		var side := direction.orthogonal()
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed + int(age * 20.0)
		for i in range(1, _edge.size()):
			var a := open_at(_along[i - 1])
			var b := open_at(_along[i])
			if a <= 0.01 and b <= 0.01:
				continue
			# Fresh stretches burn pale, older ones settle to violet.
			var fresh := clampf(1.0 - (front - _along[i]) / (wave_speed * 0.6), 0.0, 1.0)
			var rim := VIOLET.lerp(PALE, fresh)
			rim.a = maxf(a, b)
			_glow.draw_line(_edge[i - 1] + side * width * 0.5 * a, _edge[i] + side * width * 0.5 * b, rim, 3.0)
			_glow.draw_line(_edge[i - 1] - side * width * 0.4 * a, _edge[i] - side * width * 0.4 * b, rim, 3.0)
			# Energy boiling inside the open stretch.
			var boil := VIOLET.lerp(PALE, fresh * 0.6)
			for j in 3:
				var t := rng.randf()
				var open := lerpf(a, b, t)
				boil.a = rng.randf_range(0.3, 0.9) * open
				dot(_edge[i - 1].lerp(_edge[i], t) + side * rng.randf_range(-width * 0.35, width * 0.45) * open,
					3.0 if rng.randf() < 0.7 else 6.0, boil, true)
		# The head of the wave: a white-hot point with a flare across the crack.
		if front <= length:
			var head := direction * front
			var flare := PALE
			_glow.draw_circle(head, 10.0 + 3.0 * sin(age * 50.0), flare)
			flare.a = 0.45
			_glow.draw_circle(head, 24.0, flare)
			_glow.draw_line(head - side * width * 0.9, head + side * width * 0.9, PALE, 3.0)
			var tail := VIOLET
			tail.a = 0.35
			_glow.draw_line(head, head - direction * minf(front, 140.0), tail, width * 0.5)


## Collapse: six turning wedges with a warned reversal on the third wave.
class Sectors:
	extends Hazard
	const REVERSE_LEAD := 0.65
	const REVERSE_BLEND := 0.3

	var count := 6
	var arc := deg_to_rad(42.0)
	var start := 0.0
	var turn := 0.26
	var cycles := 4
	var telegraph := 1.15
	var fire_time := 0.3
	## Actual clearance between the wedges where the angular gaps narrow.
	var min_gap := 36.0
	var core_radius := 38.0
	var outer := NelvarVoidData.ARENA_REACH
	var _fired := -1

	func duration() -> float:
		return cycles * (telegraph + fire_time)

	func rotation_at(time: float) -> float:
		# Integrate the speed through the reversal so the wedges never jump.
		var elapsed := time - 2.0 * (telegraph + fire_time) - REVERSE_LEAD
		var blend := clampf(elapsed / REVERSE_BLEND, 0.0, 1.0)
		var reversed := 0.5 * REVERSE_BLEND * blend * blend + maxf(elapsed - REVERSE_BLEND, 0.0)
		return start + turn * (time - 2.0 * reversed)

	func _half_arc(radius: float) -> float:
		var half_step := PI / count
		return clampf(half_step - asin(minf(min_gap * 0.5 / maxf(radius, 1.0), 1.0)), 0.0, arc * 0.5)

	func _step(_delta: float) -> void:
		if age >= duration():
			queue_free()
			return
		var period := telegraph + fire_time
		if fmod(age, period) < telegraph:
			return
		var cycle := int(age / period)
		var rotation := rotation_at(age)
		if _fired != cycle:
			_fired = cycle
			_tear(rotation)
		var offset := player_point() - global_position
		var distance := offset.length()
		if distance > outer:
			return
		var step := TAU / count
		var angle := wrapf(offset.angle() - rotation, -step * 0.5, step * 0.5)
		if distance <= core_radius or absf(angle) < _half_arc(distance):
			hurt()

	func _tear(rotation: float) -> void:
		var knee := minf(outer, min_gap * 0.5 / sin(PI / count - arc * 0.5))
		for i in count:
			var center := rotation + TAU * i / count
			for side: float in [-1.0, 1.0]:
				var axis := Vector2.from_angle(center + arc * 0.5 * side)
				var sparks := sparks_along(axis * knee, axis * minf(outer, 900.0), 14, PALE, 180.0, 0.42)
				sparks.finished.connect(sparks.queue_free)
		NelvarVoidFx.flash_light(self, Vector2.ZERO, VIOLET, 1.4, 760.0, 0.45)
		NelvarVoidFx.shock(self, global_position, 0.42)

	func _shape(center: float) -> PackedVector2Array:
		var shape := PackedVector2Array()
		var half := _half_arc(outer)
		for i in 17:
			shape.append(Vector2.from_angle(center + half * (i / 8.0 - 1.0)) * outer)
		# The straight inner edges leave parallel-sided corridors next to the boss.
		var knee := min_gap * 0.5 / sin(PI / count - arc * 0.5)
		if knee < outer:
			shape.append(Vector2.from_angle(center + arc * 0.5) * knee)
		shape.append(Vector2.from_angle(center) * (min_gap * 0.5 / sin(PI / count)))
		if knee < outer:
			shape.append(Vector2.from_angle(center - arc * 0.5) * knee)
		return shape

	func _draw() -> void:
		var firing := fmod(age, telegraph + fire_time) >= telegraph
		var local := fmod(age, telegraph + fire_time)
		var fill := Color(VOID, 0.7 if firing else 0.14 + 0.24 * local / telegraph)
		var rotation := rotation_at(age)
		for i in count:
			draw_colored_polygon(_shape(rotation + TAU * i / count), fill)
		draw_circle(Vector2.ZERO, core_radius, fill)

	func _draw_glow() -> void:
		var period := telegraph + fire_time
		var local := fmod(age, period)
		var firing := local >= telegraph
		var charge := local / telegraph if not firing else 1.0 - (local - telegraph) / fire_time
		var reversing := age >= 2.0 * period and age < 2.0 * period + REVERSE_LEAD + REVERSE_BLEND
		var direction := signf(turn) if age < 2.0 * period else -signf(turn)
		var rotation := rotation_at(age)
		var edge := Color(PALE if firing else VIOLET, 0.4 + 0.6 * charge)
		var fill := Color(DEEP, 0.13 + 0.15 * charge if firing else 0.04 + 0.08 * charge)
		_glow.draw_circle(Vector2.ZERO, core_radius, fill)
		_glow.draw_arc(Vector2.ZERO, core_radius, 0.0, TAU, 32, edge, 3.0)
		for i in count:
			var center := rotation + TAU * i / count
			var shape := _shape(center)
			_glow.draw_colored_polygon(shape, fill)
			shape.append(shape[0])
			_glow.draw_polyline(shape, edge, 3.0)
			for side: float in [-1.0, 1.0]:
				for j in 5:
					var along := core_radius + fposmod(age * (330.0 + 260.0 * charge)
						+ i * 97.0 + j * 211.0, outer - core_radius)
					var axis := Vector2.from_angle(center + side * _half_arc(along))
					dot(axis * along, 6.0 if j == 0 else 3.0, Color(PALE, 0.3 + 0.55 * charge), true)
			_draw_lane(center + PI / count, direction, reversing)

	func _draw_lane(center: float, direction: float, reversing: bool) -> void:
		var axis := Vector2.from_angle(center)
		# The way through: a soft pale band down the middle of the lane.
		_glow.draw_line(axis * (core_radius + 12.0), axis * outer, Color(VIOLET, 0.1), 15.0)
		_glow.draw_line(axis * (core_radius + 12.0), axis * outer, Color(PALE, 0.28), 3.0)
		for distance: float in [84.0, 160.0, 290.0, 455.0, 685.0, 925.0]:
			if distance >= outer:
				break
			var along := direction * (fposmod(age * 2.4 + distance * 0.005, 1.0) - 0.5)
			var angle := center + along * minf(PI / count - _half_arc(distance), 0.48)
			var normal := Vector2.from_angle(angle)
			var point := normal * distance
			var tangent := normal.orthogonal() * direction
			var color := Color(PALE, 1.0 if reversing else 0.7)
			if reversing:
				dot(point - tangent * 13.0, 12.0, Color(VIOLET, 0.8), true)
			_glow.draw_polyline(PackedVector2Array([point - tangent * 8.0 - normal * 9.0,
				point + tangent * 4.0, point - tangent * 8.0 + normal * 9.0]), color, 3.0)


## A shard follows two logarithmic spirals, with a bright pause at its turning point.
class Shard:
	extends Hazard
	const COUNT := 18
	const INNER := 110.0
	const OUTER := 990.0
	const HIT_RADIUS := 18.0
	const WARNING := 0.85
	const LAUNCH_SPACING := 1.55
	## Alternating spokes launch a little later to leave room at the inner edge.
	const SPOKE_STAGGER := 0.18
	const OUT_TIME := 2.0
	const HOLD := 0.65
	const BACK_TIME := 2.1
	const FLIGHT_TIME := OUT_TIME + HOLD + BACK_TIME
	const OUT_CURL := 230.0 * OUT_TIME / (OUTER - INNER)
	const BACK_CURL := 120.0 * BACK_TIME / (OUTER - INNER)
	const LIFT := Vector2(0.0, -14.0)

	var heading := 0.0
	var telegraph := WARNING
	var _origin := Vector2.ZERO

	## At equal radii, the following launch meets the first ring on its return.
	static func crossing_offset(launch_spacing: float) -> float:
		var progress := (FLIGHT_TIME - launch_spacing) / (OUT_TIME + BACK_TIME)
		var radius := lerpf(INNER, OUTER, progress)
		return _return_angle(radius) - _out_angle(radius)

	static func _out_angle(radius: float) -> float:
		return OUT_CURL * log(radius / INNER)

	static func _return_angle(radius: float) -> float:
		return _out_angle(OUTER) + BACK_CURL * log(radius / OUTER)

	func _init() -> void:
		super()
		z_as_relative = false
		z_index = 6

	func _setup() -> void:
		_origin = position
		position = _origin + _point_at(0.0)

	## Ground position relative to the launch centre at a time after the warning.
	func _point_at(flight: float) -> Vector2:
		if flight < OUT_TIME + HOLD:
			var radius := lerpf(INNER, OUTER, clampf(flight / OUT_TIME, 0.0, 1.0))
			return Vector2.from_angle(heading + _out_angle(radius)) * radius
		var radius := lerpf(OUTER, INNER, clampf((flight - OUT_TIME - HOLD) / BACK_TIME, 0.0, 1.0))
		return Vector2.from_angle(heading + _return_angle(radius)) * radius

	func _step(_delta: float) -> void:
		var flight := age - telegraph
		if flight < 0.0:
			return
		if flight >= FLIGHT_TIME:
			queue_free()
			return
		position = _origin + _point_at(flight)
		if player_point().distance_squared_to(global_position) < HIT_RADIUS * HIT_RADIUS:
			hurt()
			NelvarVoidFx.burst(get_parent(), global_position + LIFT, 8, PALE, 145.0, 0.32)
			queue_free()

	func _draw() -> void:
		var shown := clampf(age / telegraph, 0.0, 1.0)
		dot(Vector2.ZERO, 12.0, Color(VOID, shown * 0.8))
		dot(LIFT, 15.0, Color(VOID, shown * 0.95))

	func _draw_glow() -> void:
		var flight := age - telegraph
		var waiting := flight < 0.0
		var turning := flight >= OUT_TIME and flight < OUT_TIME + HOLD
		var here := _point_at(flight)
		if flight > 0.0:
			# A long curved tail: it shows which way the spiral bends.
			var trail := PackedVector2Array()
			var tint := PALE if flight >= OUT_TIME + HOLD else VIOLET
			var colors := PackedColorArray()
			var samples := 22
			for i in range(samples, -1, -1):
				var point := _point_at(maxf(flight - i * 0.03, 0.0)) - here
				trail.append(point + LIFT)
				colors.append(Color(VIOLET, 0.42 * (1.0 - float(i) / samples)))
				if i > 0 and i % 2 == 0 and point.length_squared() > 9.0:
					dot(point + LIFT, 6.0 if i < 6 else 3.0, Color(tint, 0.7 * (1.0 - float(i) / samples)), true)
			_glow.draw_polyline_colors(trail, colors, 7.0)
			var bright := colors.duplicate()
			for i in bright.size():
				bright[i] = Color(PALE, bright[i].a * 0.9)
			_glow.draw_polyline_colors(trail, bright, 2.0)
		if waiting or turning:
			# A dotted piece of the next curve points away from the charged shard.
			var charge := age / telegraph if waiting else (flight - OUT_TIME) / HOLD
			var next_leg := 0.0 if waiting else OUT_TIME + HOLD
			var tint := VIOLET.lerp(PALE, charge)
			for i in range(1, 9):
				var point := _point_at(next_leg + i * 0.025) - here
				var pulse := 0.5 + 0.5 * sin(age * 26.0 - i * 0.8)
				dot(point + LIFT, 6.0 if i % 4 == 0 else 3.0, Color(tint, 0.3 + 0.58 * pulse), true)
			_glow.draw_arc(LIFT, 19.0 - 8.0 * charge, 0.0, TAU, 14, Color(tint, 0.45 + 0.4 * charge), 3.0)
		var halo := Color(VIOLET, 0.2 if waiting else 0.44)
		_glow.draw_circle(LIFT, 12.0, halo)
		var spin := age * 10.0
		for i in 4:
			dot(LIFT + Vector2.from_angle(spin + i * PI * 0.5) * 7.0, 3.0, VIOLET, true)
		dot(LIFT, 6.0, VIOLET if waiting else PALE, true)
		dot(LIFT + Vector2(-3.0, -3.0), 3.0, PALE, true)


## Squeeze: an accelerating wall of the Void with a slowly sweeping way out.
class Squeeze:
	extends Hazard
	const GAP_DRIFT := 0.14

	var start_radius := NelvarVoidData.ARENA_REACH
	var band := 120.0
	var gap := 0.0
	## Width in world units at the outer lip of the ring.
	var gap_width := 224.0
	var duration := 6.8
	var warn := 1.0
	var collapse_radius := 165.0
	var collapse_damage := 30.0
	var _gap_light: PointLight2D
	var _heart_light: PointLight2D

	func _setup() -> void:
		_gap_light = NelvarVoidFx.make_light(PALE, 0.0, 185.0)
		add_child(_gap_light)
		_heart_light = NelvarVoidFx.make_light(VIOLET, 0.0, collapse_radius * 1.7)
		add_child(_heart_light)

	func _closing(time: float) -> float:
		return clampf((time - warn) / (duration - warn), 0.0, 1.0)

	func radius_at(time: float) -> float:
		var k := _closing(time)
		return start_radius * (1.0 - k * (0.42 + 0.58 * k))

	func gap_at(time: float) -> float:
		# Most of the extra turn comes late, when the lip is small enough to follow.
		var k := _closing(time)
		return gap + GAP_DRIFT * time + 0.12 * (duration - warn) * pow(k, 5.0)

	func _half_gap(radius: float) -> float:
		return minf(gap_width * 0.5 / (radius + band), PI)

	func _heart_charge() -> float:
		return clampf(1.0 - (duration - age) / 1.1, 0.0, 1.0)

	func _step(delta: float) -> void:
		var offset := player_point() - global_position
		var distance := offset.length()
		var r := radius_at(age)
		var center := gap_at(age)
		_gap_light.position = Vector2.from_angle(center) * (r + band * 0.5)
		_gap_light.energy = (1.0 + 0.25 * sin(age * 8.0)) * clampf(age / warn, 0.0, 1.0)
		_heart_light.energy = _heart_charge() * 1.6
		if age >= duration:
			if distance < collapse_radius:
				damage = collapse_damage
				hurt()
			var burst := Burst.new()
			burst.radius = collapse_radius
			burst.power = 0.85
			burst.position = position
			get_parent().add_child(burst)
			NelvarVoidFx.flash(self, PALE, 0.25, 0.4)
			queue_free()
			return
		if age - delta < warn and age >= warn:
			NelvarVoidFx.shock(self, global_position, 0.32)
		if age >= warn and distance >= r and distance <= r + band \
				and absf(angle_difference(offset.angle(), center)) > _half_gap(r):
			hurt()

	func _draw() -> void:
		var r := radius_at(age)
		var center := gap_at(age)
		var half := _half_gap(r)
		var shown := clampf(age / warn, 0.0, 1.0)
		draw_arc(Vector2.ZERO, r + band * 0.5, center + half, center + TAU - half, 128,
			Color(VOID, 0.85 * shown), band)
		var charge := _heart_charge()
		if charge > 0.0:
			draw_circle(Vector2.ZERO, collapse_radius, Color(VOID, charge * 0.55))

	func _draw_glow() -> void:
		var r := radius_at(age)
		var center := gap_at(age)
		var half := _half_gap(r)
		var shown := clampf(age / warn, 0.0, 1.0)
		var closing := _closing(age)
		var begin := center + half
		var span := TAU - 2.0 * half
		var rim := Color(PALE, shown * (0.65 + 0.35 * closing))
		_glow.draw_arc(Vector2.ZERO, r + band, begin, begin + span, 128, Color(VIOLET, shown), 3.0)
		_glow.draw_arc(Vector2.ZERO, maxf(r, 1.0), begin, begin + span, 128, rim, 4.0)
		for layer in 3:
			var filament := PackedVector2Array()
			for i in 81:
				var angle := begin + span * i / 80.0
				var ripple := sin(angle * 17.0 + age * (6.0 + layer * 3.0))
				ripple *= cos(angle * 11.0 - age * 7.0 + layer * 2.0)
				var depth := 0.18 + 0.29 * layer + 0.15 * ripple
				filament.append(Vector2.from_angle(angle) * (r + band * depth))
			_glow.draw_polyline(filament, Color(VIOLET if layer == 0 else DEEP, shown * 0.55), 6.0)
		# The sparks fall inward faster with the wall, leaving short pale streaks.
		var flow := age * 0.55 + 2.8 * (duration - warn) * closing * closing
		for i in 144:
			var turn := fposmod(i * 0.618034 + age * 0.028, 1.0)
			var axis := Vector2.from_angle(begin + span * turn)
			var depth := 1.0 - fposmod(i * 0.37 + flow * (0.6 + 0.1 * (i % 5)), 1.0)
			var spark := Color(PALE if i % 4 == 0 else VIOLET, shown * sin(depth * PI))
			var point := axis * (r + band * depth)
			dot(point, 6.0 if i % 4 == 0 else 3.0, spark, true)
			if i % 4 == 0:
				dot(point + axis * (6.0 + 9.0 * closing), 3.0, Color(spark, spark.a * 0.4), true)
		_draw_gap(center, half, r, shown)
		_draw_heart(_heart_charge())

	func _draw_gap(center: float, half: float, r: float, shown: float) -> void:
		var outer := r + band
		var floor_light := Color(PALE, shown * 0.17)
		_glow.draw_arc(Vector2.ZERO, r + band * 0.5, center - half, center + half, 24, floor_light, band)
		for side: float in [-1.0, 1.0]:
			var edge := Vector2.from_angle(center + side * half)
			_glow.draw_line(edge * r, edge * outer, Color(VIOLET, 0.55 * shown), 15.0)
			_glow.draw_line(edge * r, edge * outer, Color(PALE, shown), 4.0)
			for i in 5:
				var along := fposmod(age * 1.2 + i * 0.2, 1.0)
				dot(edge * (r + band * along), 6.0, Color(PALE, shown * along), true)
		for i in 4:
			var sweep := fposmod(age * 1.45 + i * 0.25, 1.0)
			var normal := Vector2.from_angle(center + half * (sweep - 0.5) * 1.4)
			var point := normal * (r + band * (0.33 + (i % 2) * 0.34))
			var side := normal.orthogonal()
			_glow.draw_polyline(PackedVector2Array([point - side * 10.0 - normal * 10.0,
				point + side * 5.0, point - side * 10.0 + normal * 10.0]),
				Color(PALE, shown * sin(sweep * PI)), 4.0)
		# The way out is readable from the centre before the rim comes into view.
		var axis := Vector2.from_angle(center)
		_glow.draw_line(axis * minf(75.0, r), axis * r, floor_light, 3.0)
		for i in 12:
			var along := 75.0 + fposmod(age * 210.0 + i * 97.0, maxf(r - 75.0, 1.0))
			if along < r:
				dot(axis * along, 6.0, Color(PALE, shown * 0.62), true)

	func _draw_heart(charge: float) -> void:
		if charge <= 0.0:
			return
		_glow.draw_arc(Vector2.ZERO, collapse_radius, 0.0, TAU, 72, Color(PALE, 0.45 + 0.5 * charge), 3.0)
		var radius := collapse_radius * (1.0 - 0.87 * charge)
		_glow.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(VIOLET, charge), 6.0)
		for i in 20:
			var angle := TAU * i / 20.0 + age * 2.5
			dot(Vector2.from_angle(angle) * radius, 6.0, Color(PALE, charge), true)


## Where a dash is about to go: a line of light from the boss to its target that
## tightens and brightens as the wind-up ends. While it still follows the player
## it is two loose dotted lines; once `locked` it snaps into one pale line with
## chevrons racing along it. Does no harm by itself.
class Aim:
	extends Hazard
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	## 0..1, how close the dash is.
	var charge := 0.0
	var locked := false
	var _locked_at := -1.0

	func _step(_delta: float) -> void:
		if locked and _locked_at < 0.0:
			_locked_at = age
			NelvarVoidFx.burst(get_parent(), to, 12, PALE, 160.0, 0.35)

	func _draw_glow() -> void:
		var length := from.distance_to(to)
		if length < 1.0:
			return
		var direction := from.direction_to(to)
		var side := direction.orthogonal()
		if not locked:
			var spread := (1.0 - charge) * 26.0 + 4.0
			var color := VIOLET.lerp(PALE, charge * 0.6)
			var along := 0.0
			while along < length:
				var pulse := 0.5 + 0.5 * sin(along * 0.05 - age * 22.0)
				color.a = (0.2 + 0.5 * charge) * (0.5 + 0.5 * pulse)
				dot(from + direction * along + side * spread, 3.0, color, true)
				dot(from + direction * along - side * spread, 3.0, color, true)
				along += 9.0
			var seek := VIOLET
			seek.a = 0.4 + 0.4 * charge
			_glow.draw_arc(to, 16.0 + 12.0 * (1.0 - charge), age * 3.0, age * 3.0 + TAU * 0.75, 18, seek, 3.0)
			return
		# Locked: no more turning. A snap of light, then chevrons racing to the target.
		var snap := clampf(1.0 - (age - _locked_at) / 0.15, 0.0, 1.0)
		var beam := PALE
		beam.a = 0.55 + 0.45 * snap
		_glow.draw_line(from, to, beam, 3.0 + 6.0 * snap)
		var haze := VIOLET
		haze.a = 0.22 + 0.2 * charge
		_glow.draw_line(from, to, haze, 16.0)
		var chevron := PALE
		var gap := 42.0
		var offset := fmod((age - _locked_at) * 900.0, gap)
		var along := offset
		while along < length:
			chevron.a = 0.5 + 0.5 * (along / length)
			var tip := from + direction * along
			_glow.draw_polyline(PackedVector2Array([tip - direction * 9.0 + side * 9.0, tip,
				tip - direction * 9.0 - side * 9.0]), chevron, 3.0)
			along += gap
		# The target: a cross that closes in.
		var size := 18.0 - 8.0 * charge
		for k in 4:
			var axis := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
			_glow.draw_line(to + axis * size, to + axis * (size + 10.0), PALE, 3.0)
		_glow.draw_arc(to, size, 0.0, TAU, 24, beam, 2.0)


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
