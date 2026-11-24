class_name NelvarEarthMain
extends Node2D
## The earth valley (developer setting "Запускать игру на Земле"): a plain of grass
## and groves with ponds and trails, ringed by snowy mountains, in the style of the
## "Земля" menu background.
##
## Loading paints everything — the valley and the peaks round it — on all cores at
## once, then works out the ground under the range (its rocky foot and the shadows the
## peaks cast) from the painted peaks: the map opens complete. The floor (ground
## shader) and the cloud shadows are drawn on the GPU.

const STEP := NelvarEarthData.PIXEL
const WATERFALL_SHADER := preload("res://scripts/earth/waterfall.gdshader")

@export var config: NelvarEarthConfig = preload("res://resources/earth_valley_config.tres")

var data: NelvarEarthData
var thing_nodes: Array[NelvarEarthThing] = []
var peak_nodes: Array[NelvarEarthThing] = []

var _time := 0.0
var _swaying: Array[NelvarEarthThing] = []
var _painter := NelvarEarthPainter.new()
## Threads painting the art. Past about half the cores (a dozen at most) script
## threads mostly wait for each other, and painting gets slower, not faster.
var _painters := clampi(OS.get_processor_count() >> 1, 2, 12)
## Everything to paint, the peaks first (largest first), and its art.
var _painting: Array[NelvarEarthData.Thing] = []
var _arts: Array = []
var _field: NelvarEarthField
var _mountain_field: NelvarMountainField
var _peaks: Array[NelvarEarthData.Thing] = []
var _waterfall_material: ShaderMaterial
var _show_debug := false
## F3: the mountain foot and the pond shores as the physics sees them.
var _outlines: Node2D

@onready var ground: NelvarCloudSea = $Ground
@onready var cloud_shadows: NelvarCloudSea = $CloudShadows
@onready var pollen: NelvarWindParticles = $Pollen
@onready var world_layer: Node2D = $World
@onready var actors: Node2D = $Actors
@onready var player: NelvarPlayer = $Actors/Player
@onready var enemy_spawner: Node2D = $Actors/EnemySpawner
@onready var butterflies: NelvarButterflies = $Butterflies
@onready var info_panel: Control = $HUD/Margin/Stack/Panel
@onready var seed_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Seed
@onready var status_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Status


func _ready() -> void:
	info_panel.visible = GameSettings.show_info_panel
	GameSettings.info_panel_changed.connect(info_panel.set_visible)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var world_seed := int(rng.randi())
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			var value := argument.trim_prefix("--seed=")
			if value.is_valid_int():
				world_seed = value.to_int()
	if has_meta("seed_override"):
		world_seed = get_meta("seed_override")
	var started := Time.get_ticks_msec()
	data = NelvarEarthGenerator.new().generate(config, world_seed)
	if data == null:
		seed_label.text = "Долина не сложилась · сид %d" % world_seed
		status_label.text = "Ошибка генерации. Подробности в Output."
		info_panel.show()
		player.set_physics_process(false)
		player.set_process(false)
		return
	_build_walls()
	_paint_world()
	_setup_ground()
	_setup_sky()
	player.position = data.spawn_position
	player.camera.reset_smoothing()
	butterflies.setup(data, player)
	enemy_spawner.call("start_on", data)
	seed_label.text = "ЗЕМЛЯ · ДОЛИНА · СИД %d" % data.world_seed
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


## Everything in the valley, the peaks and the ground maps, painted on all cores at
## once. The peaks take longest, the biggest most: they start first, and the small
## things of the valley fill the cores up behind them.
func _paint_world() -> void:
	var valley_things: Array[NelvarEarthData.Thing] = []
	for thing in data.things:
		if thing.kind == NelvarEarthData.Kind.PEAK:
			_peaks.append(thing)
		else:
			valley_things.append(thing)
	_peaks.sort_custom(func(a: NelvarEarthData.Thing, b: NelvarEarthData.Thing) -> bool:
		return a.size.x * a.size.y > b.size.x * b.size.y)
	_painting.append_array(_peaks)
	_painting.append_array(valley_things)
	_arts.resize(_painting.size())
	var field_task := WorkerThreadPool.add_task(_build_field, true, "Earth ground map")
	var group := WorkerThreadPool.add_group_task(_paint_thing, _painting.size(), _painters, true,
		"Earth art")
	WorkerThreadPool.wait_for_group_task_completion(group)
	# The range's foot and the peaks' shadows follow the painted peaks.
	_mountain_field = NelvarMountainField.build(_peaks, _arts.slice(0, _peaks.size()))
	WorkerThreadPool.wait_for_task_completion(field_task)
	for i in _painting.size():
		var thing := _painting[i]
		var art: NelvarEarthArt = _arts[i]
		art.bake()
		var node := NelvarEarthThing.new()
		node.setup(thing, art)
		if thing.kind == NelvarEarthData.Kind.STATUE:
			node.watcher = player
		if art.waterfall:
			if _waterfall_material == null:
				_waterfall_material = ShaderMaterial.new()
				_waterfall_material.shader = WATERFALL_SHADER
			node.material = _waterfall_material
		actors.add_child(node)
		if thing.kind == NelvarEarthData.Kind.PEAK:
			peak_nodes.append(node)
		else:
			thing_nodes.append(node)
		if art.sway > 0:
			_swaying.append(node)
	_arts.clear()
	_painting.clear()


func _paint_thing(index: int) -> void:
	_arts[index] = _painter.paint(_painting[index])


func _build_field() -> void:
	_field = NelvarEarthField.build(data)


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
	material.set_shader_parameter("mountain_tex", _mountain_field.texture())
	material.set_shader_parameter("mountain_origin", Vector2(_mountain_field.origin))
	material.set_shader_parameter("mountain_size", Vector2(_mountain_field.size))
	material.set_shader_parameter("mountain_scale", float(NelvarMountainField.SCALE))
	ground.texel_size = STEP
	_field = null
	_mountain_field = null


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


## True once every peak stands (they are all painted while the map loads).
func peaks_finished() -> bool:
	return peak_nodes.size() == _peaks.size()


# --- Every frame --------------------------------------------------------------------

## The wind over the valley: gusts run across it from the left. The ground shader's
## tufts use the same function (earth_ground.gdshader, gust).
func gust(world: Vector2) -> float:
	return 0.65 * sin(world.x * 0.0045 + world.y * 0.0012 - _time * 1.5) \
		+ 0.35 * sin(world.x * 0.011 - world.y * 0.006 - _time * 2.4)


func _process(delta: float) -> void:
	if data == null:
		return
	_time += delta
	ground.backdrop_material().set_shader_parameter("wind_time", _time)
	# Only plants near the view sway; the rest keep their last pose.
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(200.0)
	for node in _swaying:
		if view.has_point(node.position):
			node.set_gust(gust(node.position))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_show_debug = not _show_debug
		_outlines.visible = _show_debug
		for node in thing_nodes + peak_nodes:
			if node.thing.solid:
				node.show_collision = _show_debug
				node.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.adjust_zoom(1.15)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.adjust_zoom(1.0 / 1.15)
			get_viewport().set_input_as_handled()
