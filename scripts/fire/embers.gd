class_name NelvarEmbers
extends Node2D
## Ash and sparks over the fire forge. Grey flakes of ash drift down across the view
## with the wind; sparks rise from the lava's edge, from glowing cracks in stone and
## bark and from the volcanoes' craters, flicker and die; eruptions and things falling
## into the lava throw up bursts of them. The player's wind (projectiles and waves,
## found by NelvarEmbers.gusts) blows both away, and fans the sparks brighter.
## On the volcano (flame_rate, flame_spots, flame()) little tongues of flame lick up
## from the lava by its shores, over the boiling patches and wherever lava splashes.
## Drawn in whole art pixels of the world grid.

const STEP := NelvarFireData.PIXEL
const ASH_COLORS: Array[Color] = [Color8(150, 142, 136), Color8(112, 104, 100), Color8(186, 178, 168)]
const SPARK_COLORS: Array[Color] = [Color8(255, 236, 160), Color8(255, 196, 96), Color8(246, 130, 52),
	Color8(212, 76, 34), Color8(120, 36, 24)]
## A tongue of flame, its root to its tip.
const FLAME_COLORS: Array[Color] = [Color8(255, 236, 160), Color8(255, 196, 96), Color8(246, 130, 52),
	Color8(212, 76, 34)]
## The drift of the air: the same as the smoke's.
const WIND := Vector2(16.0, 5.0)

enum Kind { ASH, SPARK, FLAME }


class Mote:
	var kind := Kind.ASH
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var age := 0.0
	var life := 1.0
	var phase := 0.0
	## Sparks: fanned by the wind, they burn brighter for a moment.
	var fanned := 0.0


## Flakes of ash alive per million square world units of view.
@export var ash_density := 26.0
## Sparks rising from the lava's edge per second over the view.
@export var spark_rate := 26.0
## Tongues of flame licking up from the lava near its shores, per second over the view
## (none in the forge).
@export var flame_rate := 0.0

var data: NelvarFireData
## Glowing cracks, craters and smouldering tops that throw sparks now and then.
var sources := PackedVector2Array()
## Wind attacks this frame: [position, velocity, radius].
var gusts: Array = []
## Patches flames keep rising from: centre and radius (boiling lava, a vent).
var flame_spots: Array[Vector3] = []

var _motes: Array[Mote] = []
var _rng := RandomNumberGenerator.new()
var _spark_debt := 0.0
var _flame_debt := 0.0


func setup(fire: NelvarFireData, spark_sources: PackedVector2Array) -> void:
	data = fire
	sources = spark_sources
	_rng.seed = ("%d:embers" % fire.world_seed).hash()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## The player's wind attacks now flying in `scene`: [position, velocity, radius].
static func gusts_in(scene: Node) -> Array:
	var result := []
	if scene == null:
		return result
	for child in scene.get_children():
		if not child is Area2D or not "direction" in child:
			continue
		var area := child as Area2D
		var direction: Vector2 = child.get("direction")
		if "speed" in child:
			result.append([area.global_position, direction * float(child.get("speed")), 34.0])
		elif "travel_distance" in child:
			var reach := 40.0 * area.scale.x
			result.append([area.global_position,
				direction * float(child.get("travel_distance")) / maxf(0.1, float(child.get("duration"))), reach])
	return result


## A burst of sparks thrown up at `at` (an eruption, something falling into the lava).
func burst(at: Vector2, count: int, power: float = 1.0) -> void:
	for i in count:
		var mote := Mote.new()
		mote.kind = Kind.SPARK
		mote.position = at + Vector2(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-6.0, 6.0))
		mote.velocity = Vector2(_rng.randf_range(-70.0, 70.0), _rng.randf_range(-190.0, -70.0)) * power
		mote.life = _rng.randf_range(0.6, 1.5)
		mote.phase = _rng.randf() * TAU
		mote.fanned = 0.6
		_motes.append(mote)


## Tongues of flame licking up round `at` (fresh lava, a geyser's mouth, a sinking edge).
func flame(at: Vector2, count: int = 1, spread: float = 10.0) -> void:
	for i in count:
		var mote := Mote.new()
		mote.kind = Kind.FLAME
		mote.position = at + Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread) * 0.6)
		mote.velocity = Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-16.0, -8.0))
		mote.life = _rng.randf_range(0.6, 1.2)
		mote.phase = _rng.randf() * TAU
		_motes.append(mote)


func _process(delta: float) -> void:
	if data == null:
		return
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size))
	_spawn(view, delta)
	var keep: Array[Mote] = []
	var area := view.grow(160.0)
	for mote in _motes:
		mote.age += delta
		if mote.age >= mote.life or not area.has_point(mote.position):
			continue
		_move(mote, delta)
		keep.append(mote)
	_motes = keep
	queue_redraw()


func _spawn(view: Rect2, delta: float) -> void:
	var ash_wanted := clampi(roundi(view.get_area() / 1.0e6 * ash_density), 10, 260)
	var ash := 0
	for mote in _motes:
		if mote.kind == Kind.ASH:
			ash += 1
	for i in mini(ash_wanted - ash, 8):
		var mote := Mote.new()
		mote.kind = Kind.ASH
		mote.position = view.position + Vector2(_rng.randf() * view.size.x, _rng.randf() * view.size.y)
		mote.velocity = WIND + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(6.0, 16.0))
		mote.life = _rng.randf_range(5.0, 9.0)
		mote.phase = _rng.randf() * TAU
		_motes.append(mote)
	# Sparks from the lava's edge: random points of the view, kept where lava is near.
	_spark_debt += spark_rate * delta * clampf(view.get_area() / 1.6e6, 0.4, 3.0)
	var tries := 0
	while _spark_debt >= 1.0 and tries < 24:
		tries += 1
		var point := view.position + Vector2(_rng.randf() * view.size.x, _rng.randf() * view.size.y)
		var depth := data.lava_depth(point)
		if depth < -24.0 or depth > 30.0:
			continue
		_spark_debt -= 1.0
		_spark(point, 1.0)
	_spark_debt = minf(_spark_debt, 4.0)
	# Glowing cracks and craters in view throw a spark now and then.
	for point in sources:
		if view.grow(40.0).has_point(point) and _rng.randf() < delta * 0.35:
			_spark(point, 0.7)
	if flame_rate > 0.0:
		_spawn_flames(view, delta)


## Flames over the lava just off its shores, and over the flame spots in view.
func _spawn_flames(view: Rect2, delta: float) -> void:
	_flame_debt += flame_rate * delta * clampf(view.get_area() / 1.6e6, 0.4, 3.0)
	var tries := 0
	while _flame_debt >= 1.0 and tries < 24:
		tries += 1
		var point := view.position + Vector2(_rng.randf() * view.size.x, _rng.randf() * view.size.y)
		var depth := data.lava_depth(point)
		if depth < 2.0 or depth > 26.0:
			continue
		_flame_debt -= 1.0
		flame(point, 1, 2.0)
	_flame_debt = minf(_flame_debt, 4.0)
	for spot in flame_spots:
		var center := Vector2(spot.x, spot.y)
		if view.grow(spot.z).has_point(center) and _rng.randf() < delta * spot.z * 0.08:
			flame(center + Vector2.from_angle(_rng.randf() * TAU) * spot.z * 0.8 * sqrt(_rng.randf()), 1, 2.0)


func _spark(at: Vector2, power: float) -> void:
	var mote := Mote.new()
	mote.kind = Kind.SPARK
	mote.position = at
	mote.velocity = Vector2(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-70.0, -30.0) * power)
	mote.life = _rng.randf_range(0.9, 2.2)
	mote.phase = _rng.randf() * TAU
	_motes.append(mote)


func _move(mote: Mote, delta: float) -> void:
	for gust: Array in gusts:
		var offset: Vector2 = mote.position - gust[0]
		var reach: float = gust[2] + 26.0
		if offset.length_squared() < reach * reach:
			# The wind carries the mote along and a little outwards.
			var push: Vector2 = gust[1] * 0.75 + offset.normalized() * 120.0
			mote.velocity = mote.velocity.lerp(push, minf(1.0, delta * 9.0))
			if mote.kind == Kind.SPARK:
				mote.fanned = 1.0
				mote.life = maxf(mote.life, mote.age + 0.6)
			else:
				mote.life = maxf(mote.life, mote.age + 1.0)
	match mote.kind:
		Kind.ASH:
			mote.phase += delta * 1.7
			var target := WIND + Vector2(sin(mote.phase) * 10.0, 10.0 + cos(mote.phase * 0.7) * 4.0)
			mote.velocity = mote.velocity.lerp(target, minf(1.0, delta * 0.8))
		Kind.FLAME:
			mote.phase += delta * 14.0
			mote.velocity = mote.velocity.lerp(Vector2(WIND.x * 0.3, -12.0), minf(1.0, delta * 2.0))
		Kind.SPARK:
			mote.phase += delta * 6.0
			var target := Vector2(WIND.x * 0.6 + sin(mote.phase) * 14.0, -46.0)
			mote.velocity = mote.velocity.lerp(target, minf(1.0, delta * 1.3))
			mote.fanned = maxf(0.0, mote.fanned - delta * 1.5)
	mote.position += mote.velocity * delta


func _draw() -> void:
	var cell := Vector2.ONE * STEP
	for mote in _motes:
		var at := (mote.position / STEP).floor() * STEP
		var fade := 1.0 - mote.age / mote.life
		if mote.kind == Kind.ASH:
			var color := ASH_COLORS[int(mote.phase * 3.0) % 3 if fmod(mote.phase, 2.0) < 0.2 else 0]
			color.a = minf(1.0, mote.age * 2.0) * minf(1.0, fade * 3.0) * 0.8
			draw_rect(Rect2(at, cell), color)
		elif mote.kind == Kind.FLAME:
			# 2 to 4 pixels tall, flickering, shrinking as it dies; the root hottest.
			var height := clampi(roundi((2.0 + 2.0 * fade) * (0.75 + 0.25 * sin(mote.phase))), 1, 4)
			var cool := 1 if fade < 0.35 else 0
			for k in height:
				var index := mini(k + cool + (1 if sin(mote.phase * 1.7 + k) > 0.8 else 0), FLAME_COLORS.size() - 1)
				var sway: float = STEP if k == height - 1 and sin(mote.phase * 0.6) > 0.5 else 0.0
				draw_rect(Rect2(at + Vector2(sway, -k * STEP), cell), FLAME_COLORS[index])
		else:
			var heat := clampf(1.0 - mote.age / mote.life + mote.fanned * 0.5, 0.0, 1.0)
			var index := clampi(int((1.0 - heat) * SPARK_COLORS.size()), 0, SPARK_COLORS.size() - 1)
			if sin(mote.phase * 3.0) > 0.85 and index > 0:
				index -= 1
			draw_rect(Rect2(at, cell), SPARK_COLORS[index])
			if mote.fanned > 0.5:
				draw_rect(Rect2(at + Vector2(0, STEP), cell), SPARK_COLORS[mini(index + 2, 4)])
