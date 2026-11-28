class_name NelvarEarthMain
extends NelvarLocation
## The earth valley (developer setting "Запускать игру на Земле"): a plain of grass
## and groves with ponds and trails, ringed by snowy mountains, in the style of the
## "Земля" menu background.
##
## Loading builds the floor's map and paints what lies near the start on several cores
## (NelvarPaintQueue); the map opens then. The rest of the valley and the peaks round it are
## painted while the game runs (nearest first, fading in), then the ground under the range
## (its rocky foot and the shadows the peaks cast) is worked out from the painted peaks.
## Everything stands and collides from the start. The floor (ground shader) and the cloud
## shadows are drawn on the GPU.

const STEP := NelvarEarthData.PIXEL
const WATERFALL_SHADER := preload("res://scripts/earth/waterfall.gdshader")
## The first frame waits for the art this near the start (world units); the rest fades in
## over APPEAR seconds as it is painted.
const READY_REACH := 700.0
const APPEAR := 0.35

@export var config: NelvarEarthConfig = preload("res://resources/earth_valley_config.tres")

var data: NelvarEarthData
var thing_nodes: Array[NelvarEarthThing] = []
var peak_nodes: Array[NelvarEarthThing] = []

var _time := 0.0
var _swaying: Array[NelvarEarthThing] = []
var _painter := NelvarEarthPainter.new()
var _queue: NelvarPaintQueue
var _field: NelvarEarthField
## The peaks, their art as it comes in, how many still to come.
var _peaks: Array[NelvarEarthData.Thing] = []
var _peak_arts: Array = []
var _peaks_left := 0
var _waterfall_material: ShaderMaterial
## F3: the mountain foot and the pond shores as the physics sees them.
var _outlines: Node2D

@onready var ground: NelvarCloudSea = $Ground
@onready var cloud_shadows: NelvarCloudSea = $CloudShadows
@onready var pollen: NelvarWindParticles = $Pollen
@onready var world_layer: Node2D = $World
@onready var actors: Node2D = $Actors
@onready var butterflies: NelvarButterflies = $Butterflies


func _build() -> void:
	var started := Time.get_ticks_msec()
	data = NelvarEarthGenerator.new().generate(config, world_seed)
	if data == null:
		fail("Долина не сложилась")
		return
	_build_walls()
	_paint_world()
	_setup_ground()
	_setup_sky()
	player.position = data.spawn_position
	player.camera.reset_smoothing()
	butterflies.setup(data, player)
	enemy_spawner.start_on(data)
	show_seed()
	var kinds := NelvarEarthData.Kind
	status_label.text = "%d деревьев · %d прудов · %d троп · %d камней · %d окаменевших · %d растений" % [
		data.count(kinds.TREE), data.ponds.size(), data.trails.size(), data.count(kinds.ROCK),
		data.count(kinds.STATUE), _plant_count()]
	print("Nelvar earth seed: %d | trees: %d | ponds: %d | trails: %d | rocks: %d | statues: %d | plants: %d | peaks: %d | %d ms" % [
		data.world_seed, data.count(kinds.TREE), data.ponds.size(), data.trails.size(),
		data.count(kinds.ROCK), data.count(kinds.STATUE), _plant_count(), _peaks.size(),
		Time.get_ticks_msec() - started])


func _plant_count() -> int:
	var total := 0
	for thing in data.things:
		if thing.is_plant() or thing.kind in [NelvarEarthData.Kind.MUSHROOMS, NelvarEarthData.Kind.LILY]:
			total += 1
	return total


# --- Building -------------------------------------------------------------------

## The mountain foot stops everyone; ponds stop walkers but not projectiles.
func _build_walls() -> void:
	var foot := StaticBody2D.new()
	foot.name = "MountainFoot"
	foot.collision_layer = 1
	foot.collision_mask = 2
	foot.add_child(_outline_shape(data.boundary))
	world_layer.add_child(foot)
	for i in data.pond_polygons.size():
		var pond := StaticBody2D.new()
		pond.name = "Pond_%d" % i
		pond.collision_layer = NelvarEarthData.WATER_LAYER
		pond.collision_mask = 0
		pond.add_child(_outline_shape(data.pond_polygons[i]))
		world_layer.add_child(pond)
	_outlines = Node2D.new()
	_outlines.name = "Outlines"
	_outlines.visible = false
	_outlines.z_index = 30
	_outlines.draw.connect(_draw_outlines)
	add_child(_outlines)


func _draw_outlines() -> void:
	for polygon: PackedVector2Array in [data.boundary] + data.pond_polygons:
		var closed := polygon.duplicate()
		closed.append(polygon[0])
		_outlines.draw_polyline(closed, NelvarEarthThing.DEBUG_COLOR, 3.0)


func _outline_shape(polygon: PackedVector2Array) -> CollisionShape2D:
	var segments := PackedVector2Array()
	for i in polygon.size():
		segments.append(polygon[i])
		segments.append(polygon[(i + 1) % polygon.size()])
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segments
	var collider := CollisionShape2D.new()
	collider.shape = shape
	return collider


## The floor's map and everything in the valley and round it, on several cores: the map and
## what is within READY_REACH of the start before the first frame, the rest after (see the
## class comment). Each thing stands (and collides) at once and gets its art when painted.
func _paint_world() -> void:
	_queue = NelvarPaintQueue.new(_paint_job, _lay, "Earth art")
	_queue.add(["field"], 0.0, true)
	for thing in data.things:
		var node := NelvarEarthThing.new()
		node.setup(thing, null)
		if thing.kind == NelvarEarthData.Kind.STATUE:
			node.watcher = player
		actors.add_child(node)
		var job := ["thing", thing, node]
		if thing.kind == NelvarEarthData.Kind.PEAK:
			peak_nodes.append(node)
			job = ["peak", thing, node, _peaks.size()]
			_peaks.append(thing)
		else:
			thing_nodes.append(node)
		var size := maxf(thing.radius, maxf(thing.size.x, thing.size.y))
		_queue.add(job, thing.position.distance_to(data.spawn_position) - size)
	_peak_arts.resize(_peaks.size())
	_peaks_left = _peaks.size()
	_queue.start(READY_REACH)
	_queue.wait()


## Runs on the painters.
func _paint_job(job: Array) -> Variant:
	match job[0]:
		"field":
			return NelvarEarthField.build(data)
		"mountains":
			return NelvarMountainField.build(_peaks, _peak_arts)
	return _painter.paint(job[1])


## On the main thread: the art onto its thing; once every peak is in, the ground under them.
func _lay(job: Array, result: Variant, late: bool) -> void:
	match job[0]:
		"field":
			_field = result
		"mountains":
			_set_mountains(result)
		_:
			var node: NelvarEarthThing = job[2]
			var art: NelvarEarthArt = result
			art.bake()
			if art.waterfall:
				if _waterfall_material == null:
					_waterfall_material = ShaderMaterial.new()
					_waterfall_material.shader = WATERFALL_SHADER
				node.material = _waterfall_material
			node.set_art(art)
			if art.sway > 0:
				_swaying.append(node)
			if late:
				node.modulate.a = 0.0
				node.create_tween().tween_property(node, "modulate:a", 1.0, APPEAR)
			if job[0] == "peak":
				_peak_arts[job[3]] = art
				_peaks_left -= 1
				if _peaks_left == 0:
					_queue.then(["mountains"])


func _setup_ground() -> void:
	var material := ground.backdrop_material()
	material.set_shader_parameter("texel_size", float(STEP))
	material.set_shader_parameter("field_tex", _field.texture())
	material.set_shader_parameter("field_origin", Vector2(_field.origin))
	material.set_shader_parameter("field_size", Vector2(_field.size))
	material.set_shader_parameter("valley_center", data.valley.center)
	material.set_shader_parameter("valley_axes", data.valley.axes)
	material.set_shader_parameter("valley_amp", data.valley.amplitudes)
	material.set_shader_parameter("valley_phase", data.valley.phases)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:earth:floor" % data.world_seed).hash()
	material.set_shader_parameter("noise_offset", Vector2(rng.randi_range(-4096, 4096), rng.randi_range(-4096, 4096)))
	ground.texel_size = STEP
	_field = null


## The range's foot and the peaks' shadows on the floor (none until every peak is painted).
func _set_mountains(mountains: NelvarMountainField) -> void:
	var material := ground.backdrop_material()
	material.set_shader_parameter("mountain_tex", mountains.texture())
	material.set_shader_parameter("mountain_origin", Vector2(mountains.origin))
	material.set_shader_parameter("mountain_scale", float(NelvarMountainField.SCALE))
	material.set_shader_parameter("mountain_size", Vector2(mountains.size))
	_peak_arts = []


## Cloud shadows over everything, pollen drifting in the warm air.
func _setup_sky() -> void:
	cloud_shadows.texel_size = STEP
	cloud_shadows.set_world_seed(data.world_seed)
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	cloud_shadows.use_as_overlay(1, multiply)
	pollen.texel_size = STEP
	pollen.color = Color(0.98, 0.93, 0.64, 0.7)
	pollen.lifetime = 4.0
	pollen.preprocess = 4.0


## True once every peak is painted (they come in while the game runs).
func peaks_finished() -> bool:
	return _peaks_left == 0


## Waits until all the art is painted and laid in (the tests).
func finish_painting() -> void:
	if _queue != null:
		_queue.finish()


func is_painting() -> bool:
	return _queue != null and _queue.busy()


func _exit_tree() -> void:
	if _queue != null:
		_queue.stop()


# --- Every frame --------------------------------------------------------------------

## The wind over the valley: gusts run across it from the left. The ground shader's
## tufts use the same function (earth_ground.gdshader, gust).
func gust(world: Vector2) -> float:
	return 0.65 * sin(world.x * 0.0045 + world.y * 0.0012 - _time * 1.5) \
		+ 0.35 * sin(world.x * 0.011 - world.y * 0.006 - _time * 2.4)


func _process(delta: float) -> void:
	if data == null:
		return
	if _queue.busy():
		_queue.lay_in()
	_time += delta
	ground.backdrop_material().set_shader_parameter("wind_time", _time)
	# Only plants near the view sway; the rest keep their last pose.
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(200.0)
	for node in _swaying:
		if view.has_point(node.position):
			node.set_gust(gust(node.position))


## F3: the colliders and the outlines.
func _set_debug(shown: bool) -> bool:
	_outlines.visible = shown
	for node in thing_nodes + peak_nodes:
		if node.thing.solid:
			node.show_collision = shown
			node.queue_redraw()
	return true
