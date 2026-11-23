class_name NelvarEarthMain
extends Node2D
## The earth valley (developer setting "Запускать игру на Земле"): a plain of grass
## and groves with ponds and trails, ringed by snowy mountains, in the style of the
## "Земля" menu background.
##
## Loading paints everything in the valley on all cores; the peaks round it are far
## out of view at first, so they are painted in the background and rise as they are
## ready. The floor (ground shader), the cloud shadows and the high clouds are drawn
## on the GPU.

const STEP := NelvarEarthData.PIXEL

@export var config: NelvarEarthConfig = preload("res://resources/earth_valley_config.tres")

var data: NelvarEarthData
var thing_nodes: Array[NelvarEarthThing] = []
var peak_nodes: Array[NelvarEarthThing] = []

var _time := 0.0
var _swaying: Array[NelvarEarthThing] = []
var _painter := NelvarEarthPainter.new()
var _arts: Array = []
var _field: NelvarEarthField
var _valley_things: Array[NelvarEarthData.Thing] = []
var _peaks: Array[NelvarEarthData.Thing] = []
var _peak_arts: Array = []
var _peak_task := -1
var _peak_mutex := Mutex.new()
var _peaks_ready := PackedInt32Array()
var _show_debug := false
## F3: the mountain foot and the pond shores as the physics sees them.
var _outlines: Node2D

@onready var ground: NelvarCloudSea = $Ground
@onready var cloud_shadows: NelvarCloudSea = $CloudShadows
@onready var high_clouds: NelvarCloudSea = $HighClouds
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
	_paint_valley()
	_setup_ground()
	_setup_sky()
	_start_peaks()
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


## Everything in the valley and the ground map, painted on all cores at once.
func _paint_valley() -> void:
	for thing in data.things:
		if thing.kind == NelvarEarthData.Kind.PEAK:
			_peaks.append(thing)
		else:
			_valley_things.append(thing)
	_arts.resize(_valley_things.size())
	var field_task := WorkerThreadPool.add_task(_build_field, true, "Earth ground map")
	var group := WorkerThreadPool.add_group_task(_paint_thing, _valley_things.size(), -1, true,
		"Earth valley art")
	WorkerThreadPool.wait_for_group_task_completion(group)
	WorkerThreadPool.wait_for_task_completion(field_task)
	for i in _valley_things.size():
		var art: NelvarEarthArt = _arts[i]
		art.bake()
		var node := NelvarEarthThing.new()
		node.setup(_valley_things[i], art)
		if _valley_things[i].kind == NelvarEarthData.Kind.STATUE:
			node.watcher = player
		actors.add_child(node)
		thing_nodes.append(node)
		if art.sway > 0:
			_swaying.append(node)
	_arts.clear()


func _paint_thing(index: int) -> void:
	_arts[index] = _painter.paint(_valley_things[index])


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
	ground.texel_size = STEP
	_field = null


## Cloud shadows over everything, rare clouds passing over the plateau, pollen
## drifting in the warm air.
func _setup_sky() -> void:
	cloud_shadows.texel_size = STEP
	cloud_shadows.set_world_seed(data.world_seed)
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	cloud_shadows.use_as_overlay(1, multiply)
	high_clouds.texel_size = STEP
	high_clouds.set_world_seed(data.world_seed + 1)
	high_clouds.use_as_overlay(2, null)
	var clouds := high_clouds.backdrop_material()
	clouds.set_shader_parameter("texel_size", float(STEP))
	clouds.set_shader_parameter("valley_center", data.valley.center)
	clouds.set_shader_parameter("valley_axes", data.valley.axes)
	clouds.set_shader_parameter("valley_amp", data.valley.amplitudes)
	clouds.set_shader_parameter("valley_phase", data.valley.phases)
	pollen.texel_size = STEP
	pollen.color = Color(0.98, 0.93, 0.64, 0.7)
	pollen.lifetime = 4.0
	pollen.preprocess = 4.0


# --- Peaks, painted in the background ---------------------------------------------

func _start_peaks() -> void:
	_peak_arts.resize(_peaks.size())
	_peak_task = WorkerThreadPool.add_group_task(_paint_peak, _peaks.size(), -1, false, "Earth peaks")


func _paint_peak(index: int) -> void:
	_peak_arts[index] = _painter.paint(_peaks[index])
	_peak_mutex.lock()
	_peaks_ready.append(index)
	_peak_mutex.unlock()


## True once every peak is painted and standing.
func peaks_finished() -> bool:
	return _peak_task < 0 and peak_nodes.size() == _peaks.size()


func _raise_ready_peaks() -> void:
	_peak_mutex.lock()
	var ready := _peaks_ready
	_peaks_ready = PackedInt32Array()
	_peak_mutex.unlock()
	for index in ready:
		var art: NelvarEarthArt = _peak_arts[index]
		art.bake()
		var node := NelvarEarthThing.new()
		node.setup(_peaks[index], art)
		node.show_collision = _show_debug
		actors.add_child(node)
		peak_nodes.append(node)
	if _peak_task >= 0 and WorkerThreadPool.is_group_task_completed(_peak_task):
		WorkerThreadPool.wait_for_group_task_completion(_peak_task)
		_peak_task = -1
		_raise_ready_peaks()


func _exit_tree() -> void:
	if _peak_task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_peak_task)
		_peak_task = -1


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
	if _peak_task >= 0 or not _peaks_ready.is_empty():
		_raise_ready_peaks()
	ground.backdrop_material().set_shader_parameter("wind_time", _time)
	high_clouds.backdrop_material().set_shader_parameter("drift_pixels", high_clouds.drift() / STEP)
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
