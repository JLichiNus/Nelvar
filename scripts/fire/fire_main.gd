class_name NelvarFireMain
extends Node2D
## The fire forge (developer setting "Запускать игру в Огне"): a basin of ash and basalt
## ringed by black ridges and volcanoes, with lava lakes and streams, roads of cooled
## lava, magma fissures, smoking vents and burnt trees, in the style of the "Огонь" menu
## background.
##
## Lava stops whoever walks; the flight (Shift) carries the player over it, and whoever
## comes down in it burns and is thrown back to where they last stood safely. Standing
## right at the lava's edge scorches a little. Hoppers do not jump into the lava, but
## the wind can blow them in. Active fissures glow brighter for a moment, then erupt.
##
## Loading paints everything on several cores at once (as on the earth map). The floor,
## the light of the lava, the smoke shadows and the heat haze are drawn on the GPU.

const STEP := NelvarFireData.PIXEL
const MOLTEN_SHADER := preload("res://scripts/fire/fire_molten.gdshader")
## Burning in the lava: damage, and how long the player sinks before coming back.
const LAVA_DAMAGE := 20.0
const SINK_TIME := 0.45
const LAVA_TINT := Color(1.0, 0.45, 0.12, 0.0)
## The scorching edge: closer than this to the lava (world units) hurts, after a moment.
const HEAT_REACH := 26.0
const HEAT_DAMAGE := 2.0
const HEAT_DELAY := 0.7
const HEAT_INTERVAL := 0.9
## Eruptions: the warning, the burst, how far from the crack it hurts, and how much.
const WARN_TIME := 1.3
const BURST_TIME := 0.5
const BURST_REACH := 34.0
const BURST_DAMAGE := 12.0
const BURST_ENEMY_DAMAGE := 20.0
## Safe ground: this far from lava and eruptions, the player's last such spot is kept.
const SAFE_MARGIN := 18.0

@export var config: NelvarFireConfig = preload("res://resources/fire_forge_config.tres")

var data: NelvarFireData
var thing_nodes: Array[NelvarFireThing] = []
var peak_nodes: Array[NelvarEarthThing] = []
## Burns (falls into the lava) and eruptions so far, for the HUD and the tests.
var burns := 0
var eruptions := 0

var _time := 0.0
var _swaying: Array[NelvarFireThing] = []
var _painter := NelvarFirePainter.new()
var _volcano_painter := NelvarVolcanoPainter.new()
var _painters := clampi(OS.get_processor_count() >> 1, 2, 12)
var _painting: Array = []
var _arts: Array = []
var _field: NelvarFireField
var _mountain_field: NelvarMountainField
var _molten_material: ShaderMaterial
var _safe_position := Vector2.ZERO
var _heat_time := 0.0
var _burning := false
## Per fissure: the eruption's state this frame (0 idle, 1 warning, 2 burst).
var _fissure_state := PackedInt32Array()
var _fissure_hit := PackedByteArray()
## Craters glowing over their rims: world art pixel, radius, heat.
var _craters: Array[Vector4] = []
var _show_debug := false
var _outlines: Node2D

@onready var ground: NelvarCloudSea = $Ground
@onready var smoke_shadows: NelvarCloudSea = $SmokeShadows
@onready var glow: NelvarCloudSea = $Glow
@onready var heat_haze: NelvarHeatHaze = $HeatHaze
@onready var world_layer: Node2D = $World
@onready var actors: Node2D = $Actors
@onready var player: NelvarPlayer = $Actors/Player
@onready var enemy_spawner: Node2D = $Actors/EnemySpawner
@onready var embers: NelvarEmbers = $Embers
@onready var smoke: NelvarSmoke = $Smoke
@onready var critters: NelvarFireCritters = $Critters
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
	data = NelvarFireGenerator.new().generate(config, world_seed)
	if data == null:
		seed_label.text = "Кузня не сложилась · сид %d" % world_seed
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
	_safe_position = data.spawn_position
	_fissure_state.resize(data.fissures.size())
	_fissure_hit.resize(data.fissures.size())
	enemy_spawner.call("start_on", data)
	var kinds := NelvarFireData.Kind
	var crossings := 0
	for stream in data.streams:
		crossings += stream.crossings.size()
	seed_label.text = "ОГОНЬ · КУЗНЯ · СИД %d" % data.world_seed
	status_label.text = "%d озёр лавы · %d ручьёв · %d переправ · %d трещин · %d деревьев · %d камней · %d растений" % [
		data.lakes.size(), data.streams.size(), crossings, data.fissures.size(), data.count(kinds.TREE),
		data.count(kinds.ROCK), _plant_count()]
	print("Nelvar fire seed: %d | lakes: %d | islands: %d | streams: %d | crossings: %d | roads: %d | fissures: %d | trees: %d | rocks: %d | peaks: %d | %d ms" % [
		data.world_seed, data.lakes.size(), data.islands.size(), data.streams.size(), crossings,
		data.flows.size(), data.fissures.size(), data.count(kinds.TREE), data.count(kinds.ROCK),
		data.peaks.size(), Time.get_ticks_msec() - started])


func _plant_count() -> int:
	var total := 0
	for thing in data.things:
		if thing.is_plant():
			total += 1
	return total


# --- Building -------------------------------------------------------------------

## The ridges' foot stops everyone; the lava (lakes, the stretches of streams between
## crossings, the islands' shores) stops the walking player on its own layer.
func _build_walls() -> void:
	var foot := StaticBody2D.new()
	foot.name = "RidgeFoot"
	foot.collision_layer = 1
	foot.collision_mask = 2
	foot.add_child(_outline_shape(data.boundary))
	world_layer.add_child(foot)
	var lava := StaticBody2D.new()
	lava.name = "Lava"
	lava.collision_layer = NelvarFireData.LAVA_LAYER
	lava.collision_mask = 0
	for polygon in _lava_outlines():
		lava.add_child(_outline_shape(polygon))
	world_layer.add_child(lava)
	player.set_collision_mask_value(NelvarFireData.LAVA_LAYER_NUMBER, true)
	_outlines = Node2D.new()
	_outlines.name = "Outlines"
	_outlines.visible = false
	_outlines.z_index = 30
	_outlines.draw.connect(_draw_outlines)
	add_child(_outlines)


func _lava_outlines() -> Array[PackedVector2Array]:
	var outlines: Array[PackedVector2Array] = []
	outlines.append_array(data.lake_polygons)
	outlines.append_array(data.island_polygons)
	for stream in data.streams:
		outlines.append_array(data.stream_outlines(stream))
	return outlines


func _draw_outlines() -> void:
	for polygon: PackedVector2Array in [data.boundary] + _lava_outlines():
		var closed := polygon.duplicate()
		closed.append(polygon[0])
		_outlines.draw_polyline(closed, NelvarEarthThing.DEBUG_COLOR, 3.0)
	for fissure in data.fissures:
		_outlines.draw_polyline(fissure.points, Color.YELLOW if fissure.active else Color.ORANGE, 2.0)


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


## Everything in the basin and the ridges round it, painted on several cores; the
## biggest ridges start first. The ground map is built alongside.
func _paint_world() -> void:
	var peaks := data.peaks.duplicate()
	peaks.sort_custom(func(a: NelvarEarthData.Thing, b: NelvarEarthData.Thing) -> bool:
		return a.size.x * a.size.y > b.size.x * b.size.y)
	_painting.append_array(peaks)
	_painting.append_array(data.things)
	_arts.resize(_painting.size())
	var field_task := WorkerThreadPool.add_task(_build_field, true, "Fire ground map")
	var group := WorkerThreadPool.add_group_task(_paint_thing, _painting.size(), _painters, true, "Fire art")
	WorkerThreadPool.wait_for_group_task_completion(group)
	var ridges: Array[NelvarEarthData.Thing] = []
	var ridge_arts := []
	for i in peaks.size():
		ridges.append(peaks[i])
		ridge_arts.append(_arts[i])
	_mountain_field = NelvarMountainField.build(ridges, ridge_arts)
	WorkerThreadPool.wait_for_task_completion(field_task)
	_molten_material = ShaderMaterial.new()
	_molten_material.shader = MOLTEN_SHADER
	var wisps := PackedVector2Array()
	var plumes := PackedVector2Array()
	var sparks := PackedVector2Array()
	for i in _painting.size():
		var art: NelvarFireArt = _arts[i]
		if art == null:
			continue
		art.bake()
		if _painting[i] is NelvarEarthData.Thing:
			var peak: NelvarEarthData.Thing = _painting[i]
			var node := NelvarEarthThing.new()
			node.setup(peak, art)
			node.material = _molten_material
			actors.add_child(node)
			peak_nodes.append(node)
			if art.vent.is_finite():
				var vent := peak.position + art.vent * STEP
				var molten := peak.accent and peak.variant == NelvarEarthData.Peak.GIANT
				if molten:
					plumes.append(vent)
					var radius := peak.size.x / STEP * 0.12
					_craters.append(Vector4(vent.x / STEP, vent.y / STEP, maxf(10.0, radius), 0.7))
				for point in art.sparks:
					sparks.append(peak.position + point * STEP)
			continue
		var thing: NelvarFireData.Thing = _painting[i]
		var node := NelvarFireThing.new()
		node.setup(thing, art)
		if art.molten:
			node.material = _molten_material
		actors.add_child(node)
		thing_nodes.append(node)
		if art.sway > 0:
			_swaying.append(node)
		if art.vent.is_finite():
			wisps.append(thing.position + art.vent * STEP)
		sparks.append_array(node.spark_points())
	_arts.clear()
	_painting.clear()
	embers.setup(data, sparks)
	smoke.setup(data, wisps, plumes)
	critters.setup(data, player, embers)


func _paint_thing(index: int) -> void:
	var item: Variant = _painting[index]
	if item is NelvarEarthData.Thing:
		var peak: NelvarEarthData.Thing = item
		if peak.variant == NelvarEarthData.Peak.BOULDER:
			_arts[index] = _painter.paint_boulder(peak)
		else:
			_arts[index] = _volcano_painter.paint(peak)
	else:
		_arts[index] = _painter.paint(item)


func _build_field() -> void:
	_field = NelvarFireField.build(data)


func _setup_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:fire:floor" % data.world_seed).hash()
	var noise_offset := Vector2(rng.randi_range(-4096, 4096), rng.randi_range(-4096, 4096))
	var glow_texture := _field.glow_texture()
	var material := ground.backdrop_material()
	material.set_shader_parameter("texel_size", float(STEP))
	material.set_shader_parameter("field_tex", _field.texture())
	material.set_shader_parameter("field_origin", Vector2(_field.origin))
	material.set_shader_parameter("field_size", Vector2(_field.size))
	material.set_shader_parameter("noise_offset", noise_offset)
	material.set_shader_parameter("mountain_tex", _mountain_field.texture())
	material.set_shader_parameter("mountain_origin", Vector2(_mountain_field.origin))
	material.set_shader_parameter("mountain_size", Vector2(_mountain_field.size))
	material.set_shader_parameter("mountain_scale", float(NelvarMountainField.SCALE))
	ground.texel_size = STEP
	var light := glow.backdrop_material()
	light.set_shader_parameter("texel_size", float(STEP))
	light.set_shader_parameter("noise_offset", noise_offset)
	light.set_shader_parameter("glow_tex", glow_texture)
	light.set_shader_parameter("glow_origin", Vector2(_field.glow_origin))
	light.set_shader_parameter("glow_size", Vector2(_field.glow_size))
	light.set_shader_parameter("glow_scale", float(NelvarFireField.GLOW_SCALE))
	for target: ShaderMaterial in [material, light]:
		target.set_shader_parameter("basin_center", data.basin.center)
		target.set_shader_parameter("basin_axes", data.basin.axes)
		target.set_shader_parameter("basin_amp", data.basin.amplitudes)
		target.set_shader_parameter("basin_phase", data.basin.phases)
	glow.texel_size = STEP
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.use_as_overlay(1, add)
	var haze := heat_haze.material()
	haze.set_shader_parameter("glow_tex", glow_texture)
	haze.set_shader_parameter("glow_origin", Vector2(_field.glow_origin))
	haze.set_shader_parameter("glow_size", Vector2(_field.glow_size))
	haze.set_shader_parameter("glow_scale", float(NelvarFireField.GLOW_SCALE))
	haze.set_shader_parameter("texel_size", float(STEP))
	_field = null
	_mountain_field = null


## Shadows of the smoke drifting over everything.
func _setup_sky() -> void:
	smoke_shadows.texel_size = STEP
	smoke_shadows.set_world_seed(data.world_seed)
	var shadow := smoke_shadows.backdrop_material()
	shadow.set_shader_parameter("shade", Vector3(0.78, 0.72, 0.76))
	shadow.set_shader_parameter("cover", 0.3)
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	smoke_shadows.use_as_overlay(1, multiply)


# --- Every frame --------------------------------------------------------------------

## Hot gusts rising over the basin; plants lean with them (as on the earth map).
func gust(world: Vector2) -> float:
	return 0.65 * sin(world.x * 0.004 + world.y * 0.0015 - _time * 1.2) \
		+ 0.35 * sin(world.x * 0.012 - world.y * 0.005 - _time * 2.1)


func _process(delta: float) -> void:
	if data == null:
		return
	_time += delta
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(200.0)
	for node in _swaying:
		if view.has_point(node.position):
			node.set_gust(gust(node.position))
	var gusts := NelvarEmbers.gusts_in(self)
	embers.gusts = gusts
	smoke.gusts = gusts
	var flares := _flares()
	var count := mini(flares.size(), 8)
	var near: Array[Vector4] = flares.slice(0, count)
	while near.size() < 8:
		near.append(Vector4.ZERO)
	ground.backdrop_material().set_shader_parameter("time", _time)
	ground.backdrop_material().set_shader_parameter("flares", near)
	ground.backdrop_material().set_shader_parameter("flare_count", count)
	heat_haze.material().set_shader_parameter("flares", near)
	heat_haze.material().set_shader_parameter("flare_count", count)
	var lit: Array[Vector4] = flares.duplicate()
	for crater in _craters:
		lit.append(Vector4(crater.x, crater.y, crater.z, crater.w * (0.8 + 0.2 * sin(_time * 1.1 + crater.x))))
	lit = lit.slice(0, 16)
	var lit_count := lit.size()
	while lit.size() < 16:
		lit.append(Vector4.ZERO)
	glow.backdrop_material().set_shader_parameter("time", _time)
	glow.backdrop_material().set_shader_parameter("flares", lit)
	glow.backdrop_material().set_shader_parameter("flare_count", lit_count)


## Fissures warning or bursting now: world art pixel, radius in art pixels, heat.
func _flares() -> Array[Vector4]:
	var result: Array[Vector4] = []
	for i in data.fissures.size():
		var fissure := data.fissures[i]
		if not fissure.active:
			continue
		var cycle := fposmod(_time + fissure.phase, fissure.period)
		var warn_start := fissure.period - WARN_TIME - BURST_TIME
		var heat := 0.0
		if cycle >= warn_start + WARN_TIME:
			heat = 2.0 - (cycle - warn_start - WARN_TIME) / BURST_TIME
		elif cycle >= warn_start:
			var t := (cycle - warn_start) / WARN_TIME
			heat = t * (0.6 + 0.4 * absf(sin(cycle * 14.0)))
		if heat > 0.0:
			result.append(Vector4(fissure.center.x / STEP, fissure.center.y / STEP,
				(fissure.reach + 40.0) / STEP, heat))
	return result


func _physics_process(delta: float) -> void:
	if data == null:
		return
	# Lava stops the walking player only: the flight passes over it.
	player.set_collision_mask_value(NelvarFireData.LAVA_LAYER_NUMBER, not player.is_airborne())
	_eruptions()
	_enemies_in_lava()
	if _burning or player.is_falling() or player.health <= 0.0:
		return
	if player.is_airborne():
		_heat_time = 0.0
		return
	var depth := data.lava_depth(player.global_position)
	if depth > 0.0:
		_burn()
		return
	if depth > -HEAT_REACH:
		_heat_time += delta
		if _heat_time > HEAT_DELAY:
			_heat_time -= HEAT_INTERVAL
			player.take_damage(HEAT_DAMAGE)
			embers.burst(player.global_position, 3, 0.4)
	else:
		_heat_time = 0.0
	if depth < -(NelvarPlayer.BODY_RADIUS + SAFE_MARGIN) and data.basin.signed_distance(player.global_position) > 0.0 \
			and data.fissure_distance(player.global_position) > BURST_REACH + 10.0:
		_safe_position = player.global_position


## The player came down in the lava: they sink in a flash of sparks and come back on the
## ground they last stood on safely, burnt.
func _burn() -> void:
	_burning = true
	burns += 1
	embers.burst(player.global_position, 24, 1.2)
	player.fall_into_abyss(SINK_TIME, LAVA_TINT)
	await get_tree().create_timer(SINK_TIME + 0.25, false).timeout
	_burning = false
	if not is_instance_valid(player):
		return
	player.recover_at(_safe_position)
	player.take_damage(LAVA_DAMAGE)


## Active fissures: the warning, then a burst that hurts whoever stands on the crack
## (the flight passes over it) and throws sparks.
func _eruptions() -> void:
	for i in data.fissures.size():
		var fissure := data.fissures[i]
		if not fissure.active:
			continue
		var cycle := fposmod(_time + fissure.phase, fissure.period)
		var burst_start := fissure.period - BURST_TIME
		var state := 0
		if cycle >= burst_start:
			state = 2
		elif cycle >= burst_start - WARN_TIME:
			state = 1
		if state == 1 and randf() < 0.3:
			var p := fissure.points[randi_range(0, fissure.points.size() - 1)]
			embers.burst(p, 1, 0.5)
		if state == 2 and _fissure_state[i] != 2:
			eruptions += 1
			_fissure_hit[i] = 0
			for p in fissure.points:
				embers.burst(p, 4, 1.4)
		if state == 2 and _fissure_hit[i] == 0:
			_fissure_hit[i] = 1
			if not player.is_airborne() and NelvarFireData.polyline_distance(fissure.points,
					player.global_position) < BURST_REACH:
				player.take_damage(BURST_DAMAGE)
			for enemy in get_tree().get_nodes_in_group("enemies"):
				var body := enemy as Node2D
				if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
					continue
				if NelvarFireData.polyline_distance(fissure.points, body.global_position) < BURST_REACH:
					enemy.call("take_damage", BURST_ENEMY_DAMAGE)
					if enemy.has_method("apply_knockback"):
						var away := fissure.center.direction_to(body.global_position)
						enemy.call("apply_knockback", away * 300.0)
		_fissure_state[i] = state


## Hoppers blown into the lava burn up in a splash of sparks.
func _enemies_in_lava() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
			continue
		if data.lava_depth(body.global_position) > 6.0:
			embers.burst(body.global_position, 18, 1.0)
			enemy.call("take_damage", 10000.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_show_debug = not _show_debug
		_outlines.visible = _show_debug
		_outlines.queue_redraw()
		for node in thing_nodes:
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
