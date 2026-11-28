class_name NelvarLavaSplashes
extends Node2D
## Lava slopping over the volcano's shores. Every SPLASH_INTERVAL seconds (a sequence
## drawn from the map's seed) a spot on the rim's shore or on a broad floe's edge,
## between 250 and 800 from the player (so they see it), bulges and bubbles (WARN_TIME),
## then a tongue of lava sloshes over it: whoever is in it is hurt and thrown back from
## the lake (NelvarCraterMain). The fresh lava burns and slows for FRESH_TIME, sets into
## a crust with glowing seams that is safe (COOL_TIME), and fades away (FADE_TIME).
##
## Each splash is a decal drawn by lava_splashes.gdshader; on a floe it is the floe's
## child and floats with it.

signal struck(splash: Splash)

const SHADER := preload("res://scripts/crater/lava_splashes.gdshader")
const STEP := NelvarFireData.PIXEL
const INTERVAL := Vector2(7.0, 12.0)
const RANGE := Vector2(250.0, 800.0)
const WARN_TIME := 1.3
const FRESH_TIME := 3.0
const COOL_TIME := 8.0
const FADE_TIME := 20.0
const MAX_SPLASHES := 16
const WIDTH := Vector2(80.0, 160.0)
const REACH := Vector2(50.0, 110.0)
## Splashes come over floes at least this broad (their smallest radius).
const MIN_FLOE := 90.0

enum Stage { WARN, FRESH, COOLING, FADING, GONE }


class Splash:
	## The floe it came over, or null on the rim.
	var isle: NelvarCraterData.Isle
	## Where the lava comes over: world on the rim, from the floe's centre on a floe.
	var origin := Vector2.ZERO
	## Inland, away from the lava.
	var direction := Vector2.DOWN
	var width := 120.0
	var reach := 80.0
	var start := 0.0
	var node: Node2D
	var material: ShaderMaterial
	var struck := false

	func age(time: float) -> float:
		return time - start

	func stage_at(time: float) -> Stage:
		var t := age(time)
		if t < WARN_TIME:
			return Stage.WARN
		t -= WARN_TIME
		if t < FRESH_TIME:
			return Stage.FRESH
		t -= FRESH_TIME
		if t < COOL_TIME:
			return Stage.COOLING
		t -= COOL_TIME
		if t < FADE_TIME:
			return Stage.FADING
		return Stage.GONE

	func world_origin(time: float) -> Vector2:
		return origin + (isle.position_at(time) if isle != null else Vector2.ZERO)

	## True when `point` lies in its tongue of lava (`margin` beyond it).
	func covers(point: Vector2, time: float, margin: float = 0.0) -> bool:
		var local := point - world_origin(time)
		var u := local.dot(direction)
		var v := local.dot(direction.orthogonal())
		if u < -12.0 - margin:
			return false
		var along := maxf(u, 0.0) / (reach + margin)
		var across := v / (width * 0.5 + margin)
		return along * along + across * across < 1.0


var data: NelvarCraterData
var splashes: Array[Splash] = []
## Splashes so far (HUD and tests).
var count := 0
## The floes' nodes, by id (a splash on a floe is drawn as their child).
var isle_nodes := {}

var _rng := RandomNumberGenerator.new()
var _next := 0.0


func setup(crater: NelvarCraterData) -> void:
	data = crater
	_rng.seed = ("%d:splashes" % crater.world_seed).hash()
	_next = _rng.randf_range(INTERVAL.x * 0.5, INTERVAL.y * 0.6)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Advances to `time`: a new splash when it is due, stages of the others.
func step(time: float, around: Vector2) -> void:
	if time >= _next:
		_next = time + _rng.randf_range(INTERVAL.x, INTERVAL.y)
		if splashes.size() < MAX_SPLASHES:
			var splash := _place(time, around)
			if splash != null:
				add(splash)
	for splash: Splash in splashes.duplicate():
		var stage := splash.stage_at(time)
		if stage == Stage.GONE or (splash.isle != null and splash.isle.sink_at(time) > 0.9):
			_remove(splash)
			continue
		splash.material.set_shader_parameter("age", splash.age(time))
		splash.material.set_shader_parameter("time", time)
		if stage != Stage.WARN and not splash.struck:
			splash.struck = true
			struck.emit(splash)


## Fresh lava (still burning) under the point at `time`.
func fresh_at(point: Vector2, time: float) -> Splash:
	for splash in splashes:
		if splash.stage_at(time) == Stage.FRESH and splash.covers(point, time):
			return splash
	return null


## Any splash not yet cooled near the point (warning or fresh).
func active_near(point: Vector2, time: float, margin: float) -> bool:
	for splash in splashes:
		var stage := splash.stage_at(time)
		if (stage == Stage.WARN or stage == Stage.FRESH) and splash.covers(point, time, margin):
			return true
	return false


## Fresh lava on the rim: centre and radius, for the hoppers (NelvarCraterData.fresh_lava).
func rim_hazards(time: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for splash in splashes:
		var stage := splash.stage_at(time)
		if splash.isle == null and (stage == Stage.WARN or stage == Stage.FRESH):
			var center := splash.origin + splash.direction * splash.reach * 0.5
			result.append(Vector3(center.x, center.y, maxf(splash.reach, splash.width) * 0.6))
	return result


## A spot on the rim's shore, or on the edge of a broad floe in range.
func _place(time: float, around: Vector2) -> Splash:
	for attempt in 40:
		var splash := _on_floe(time, around) if _rng.randf() < 0.3 else _on_rim(around)
		if splash != null:
			splash.start = time
			return splash
	return null


func _on_rim(around: Vector2) -> Splash:
	var toward := (around - data.vent).angle() + _rng.randf_range(-0.55, 0.55)
	var spot := data.vent + Vector2.from_angle(toward) * (data.lake.radius_at(toward) - 30.0)
	# Out along the ray to where the rock begins (a cape may stand in the way).
	for i in 80:
		if data.lava_depth(spot) < 0.0:
			break
		spot += Vector2.from_angle(toward) * 6.0
	if data.lava_depth(spot) >= 0.0:
		return null
	var distance := spot.distance_to(around)
	if distance < RANGE.x or distance > RANGE.y:
		return null
	var e := 4.0
	var gradient := Vector2(data.lava_depth(spot + Vector2(e, 0)) - data.lava_depth(spot - Vector2(e, 0)),
		data.lava_depth(spot + Vector2(0, e)) - data.lava_depth(spot - Vector2(0, e)))
	if gradient.length_squared() < 0.0001:
		return null
	var splash := Splash.new()
	splash.direction = -gradient.normalized()
	splash.width = _rng.randf_range(WIDTH.x, WIDTH.y)
	splash.reach = _rng.randf_range(REACH.x, REACH.y)
	splash.origin = spot
	var tip := spot + splash.direction * splash.reach
	if data.rim_depth(tip) < 30.0 or data.geyser_at(tip, 40.0) != null or data.geyser_at(spot, 40.0) != null:
		return null
	for other in splashes:
		if other.isle == null and other.origin.distance_to(spot) < 200.0:
			return null
	return splash


func _on_floe(time: float, around: Vector2) -> Splash:
	var floes: Array[NelvarCraterData.Isle] = []
	for isle in data.floes:
		if isle.inner < MIN_FLOE or not isle_nodes.has(isle.id):
			continue
		var distance := isle.position_at(time).distance_to(around)
		if distance > RANGE.x and distance < RANGE.y and isle.sink_at(time) < 0.01 \
				and isle.sink_at(time + WARN_TIME + FRESH_TIME) < 0.01:
			floes.append(isle)
	if floes.is_empty():
		return null
	var isle := floes[_rng.randi_range(0, floes.size() - 1)]
	for other in splashes:
		if other.isle == isle:
			return null
	var angle := _rng.randf() * TAU
	var splash := Splash.new()
	splash.isle = isle
	splash.origin = Vector2.from_angle(angle) * (isle.radius_at(angle) - 2.0)
	splash.direction = -Vector2.from_angle(angle)
	splash.width = minf(_rng.randf_range(WIDTH.x, WIDTH.y), isle.inner * 1.1)
	splash.reach = minf(_rng.randf_range(REACH.x, REACH.y), isle.inner * 0.7)
	return splash


## Puts a splash in play (its decal, on the floe's node when it is on a floe).
func add(splash: Splash) -> void:
	count += 1
	var size := ceili(maxf(splash.reach, splash.width * 0.5) / STEP) + 8
	var decal := SplashDecal.new()
	decal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	decal.half = size
	splash.material = ShaderMaterial.new()
	splash.material.shader = SHADER
	splash.material.set_shader_parameter("direction", splash.direction)
	splash.material.set_shader_parameter("reach_px", splash.reach / STEP)
	splash.material.set_shader_parameter("width_px", splash.width / STEP)
	splash.material.set_shader_parameter("size_px", float(size * 2 + 1))
	splash.material.set_shader_parameter("seed_offset", Vector2(_rng.randi_range(-4096, 4096), _rng.randi_range(-4096, 4096)))
	decal.material = splash.material
	decal.position = (splash.origin / STEP).round() * STEP
	splash.node = decal
	if splash.isle != null:
		(isle_nodes[splash.isle.id] as Node2D).add_child(decal)
	else:
		add_child(decal)
	splashes.append(splash)


func _remove(splash: Splash) -> void:
	splashes.erase(splash)
	if is_instance_valid(splash.node):
		splash.node.queue_free()


## A square of art pixels round the splash's origin; the shader draws the splash in it.
class SplashDecal extends Node2D:
	var half := 16
	static var _white: ImageTexture

	func _draw() -> void:
		if _white == null:
			var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			_white = ImageTexture.create_from_image(image)
		var side := (half * 2 + 1) * STEP
		draw_texture_rect(_white, Rect2(Vector2.ONE * -half * STEP, Vector2.ONE * side), false)
