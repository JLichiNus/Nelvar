class_name NelvarIceMain
extends Node2D
## The ice valley (developer setting "Запускать игру на Льду"): a snowy plain ringed by
## snowy mountains, with frozen lakes, crevasses, pines under snow, drifts and
## petrified creatures, in the style of the "Лёд" menu background.
##
## The ice is slippery: on it the player speeds up and slows down slowly (traction),
## and the wind blows hoppers far over it. Under its translucent ice lies dark water
## with creatures frozen into it (NelvarIceDepths); some follow the player with an eye.
## There are no walls but the mountain foot. A step into a crevasse holds for a moment
## (narrow ones are crossed at a run, wide ones by flight, and snow bridges cross them
## all), then it is a fall: the player comes back where they last stood safely, hurt.
## Thin ice can be run over but not stood on: it cracks, then breaks into a hole of
## open water that freezes over again. Blizzards cross the valley: inside one the
## player moves and attacks slower and marks in the snow drift over faster.
##
## Loading paints everything on several cores at once (as on the earth map); the floor,
## the depths and the blizzard are drawn on the GPU.

const STEP := NelvarIceData.PIXEL
## Falls, thin ice and holes are NelvarIceHazards'; the tests read these here.
const FALL_TIME := NelvarIceHazards.FALL_TIME
const FREEZE_TIME := NelvarIceHazards.FREEZE_TIME
const MAX_CRACKS := NelvarIceHazards.MAX_CRACKS
const MAX_HOLES := NelvarIceHazards.MAX_HOLES
## Blizzards: how long they take to cross, the lulls between them, how they slow the
## player at full strength, how far ahead they are announced.
const STORM_TIME := Vector2(40.0, 60.0)
const LULL_TIME := Vector2(40.0, 70.0)
const FIRST_LULL := Vector2(20.0, 35.0)
const STORM_RADIUS := Vector2(500.0, 800.0)
const STORM_MOVE := 0.7
const STORM_ATTACK := 0.65
const WARN_TIME := 4.0
## The snow clock: 1 per second in the calm, this much in a full blizzard.
const STORM_CLOCK := 6.0
## Snow-clock seconds a mark in the snow lasts.
const MARK_LIFE := 90.0
const HINT_STORM := "Надвигается метель"
const MESSAGE_FADE := 0.6
const MESSAGE_HOLD := 2.6


## A blizzard's way across the valley.
class Storm:
	var start := 0.0
	var duration := 50.0
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var radius := 600.0
	var strength := 1.0
	var warned := false

	func progress(clock: float) -> float:
		return (clock - start) / duration

	func center_at(clock: float) -> Vector2:
		return from.lerp(to, clampf(progress(clock), 0.0, 1.0))

	## Strength now: it builds up and dies down at the ends of its way.
	func strength_at(clock: float) -> float:
		var p := progress(clock)
		if p <= 0.0 or p >= 1.0:
			return 0.0
		return strength * smoothstep(0.0, 0.08, p) * (1.0 - smoothstep(0.92, 1.0, p))


@export var config: NelvarIceConfig = preload("res://resources/ice_valley_config.tres")

var data: NelvarIceData
var thing_nodes: Array[NelvarIceThing] = []
var peak_nodes: Array[NelvarIceThing] = []
## The falls, the thin ice and the holes (shared with the cave).
var hazards: NelvarIceHazards
## Falls into crevasses, plunges into holes, cracks and holes so far (HUD and tests).
var falls: int:
	get:
		return hazards.falls if hazards != null else 0
var plunges: int:
	get:
		return hazards.plunges if hazards != null else 0
var cracks_made: int:
	get:
		return hazards.cracks_made if hazards != null else 0
var holes_broken: int:
	get:
		return hazards.holes_broken if hazards != null else 0
## Blizzard strength where the player stands, 0..1.
var storm_level := 0.0
var snow_clock := 0.0
## The blizzards' plan for the whole visit (seeded); the tests may set `clock`.
var storms: Array[Storm] = []
var clock := 0.0

var _time := 0.0
var _swaying: Array[NelvarIceThing] = []
var _painter := NelvarIcePainter.new()
var _frost_painter := NelvarFrostPainter.new()
var _painters := clampi(OS.get_processor_count() >> 1, 2, 12)
var _painting: Array = []
var _arts: Array = []
var _field: NelvarIceField
var _mountain_field: NelvarMountainField
## The cracks on thin ice now (NelvarIceHazards keeps them).
var _cracks: Array:
	get:
		return hazards.cracks if hazards != null else []
var _message_tween: Tween
var _show_debug := false
var _outlines: Node2D

@onready var depths: NelvarIceDepths = $Depths
@onready var ground: NelvarCloudSea = $Ground
@onready var world_layer: Node2D = $World
@onready var actors: Node2D = $Actors
@onready var player: NelvarPlayer = $Actors/Player
@onready var enemy_spawner: Node2D = $Actors/EnemySpawner
@onready var snowfall: NelvarWindParticles = $Snowfall
@onready var snow_marks: NelvarSnowMarks = $SnowMarks
@onready var blizzard: NelvarBlizzard = $Blizzard
@onready var info_panel: Control = $HUD/Margin/Stack/Panel
@onready var seed_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Seed
@onready var status_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Status
@onready var message: Label = $HUD/Message


func _ready() -> void:
	info_panel.visible = GameSettings.show_info_panel
	GameSettings.info_panel_changed.connect(info_panel.set_visible)
	message.modulate.a = 0.0
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
	data = NelvarIceGenerator.new().generate(config, world_seed)
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
	_plan_storms()
	player.position = data.spawn_position
	player.camera.reset_smoothing()
	hazards = NelvarIceHazards.new(data, player, self, snow_marks)
	hazards.fell.connect(_update_status.unbind(1))
	enemy_spawner.call("start_on", data)
	seed_label.text = "ЛЁД · ДОЛИНА · СИД %d" % data.world_seed
	_update_status()
	var kinds := NelvarIceData.Kind
	print("Nelvar ice seed: %d | lakes: %d | thin: %d | frozen: %d | crevasses: %d | bridges: %d | trails: %d | pines: %d | dead: %d | rocks: %d | peaks: %d | %d ms" % [
		data.world_seed, data.lakes.size(), _thin_count(), data.frozen.size(), data.crevasses.size(),
		data.bridge_count(), data.trails.size(), data.count(kinds.PINE), data.count(kinds.DEAD_TREE),
		data.count(kinds.ROCK), data.peaks.size(), Time.get_ticks_msec() - started])


func _thin_count() -> int:
	var total := 0
	for lake in data.lakes:
		total += lake.thin.size()
	return total


func _update_status() -> void:
	var trees := data.count(NelvarIceData.Kind.PINE) + data.count(NelvarIceData.Kind.DEAD_TREE)
	status_label.text = "%d озёр · %d расщелин · %d мостов · %d деревьев · падений: %d" % [
		data.lakes.size(), data.crevasses.size(), data.bridge_count(), trees, falls + plunges]


# --- Building -------------------------------------------------------------------

## The mountain foot stops everyone; crevasses and holes have no walls: they are falls.
func _build_walls() -> void:
	var foot := StaticBody2D.new()
	foot.name = "MountainFoot"
	foot.collision_layer = 1
	foot.collision_mask = 2
	var segments := PackedVector2Array()
	for i in data.boundary.size():
		segments.append(data.boundary[i])
		segments.append(data.boundary[(i + 1) % data.boundary.size()])
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segments
	var collider := CollisionShape2D.new()
	collider.shape = shape
	foot.add_child(collider)
	world_layer.add_child(foot)
	_outlines = Node2D.new()
	_outlines.name = "Outlines"
	_outlines.visible = false
	_outlines.z_index = 30
	_outlines.draw.connect(_draw_outlines)
	add_child(_outlines)


## F3: the mountain foot, the lakes and their thin ice, the crevasses' edges with their
## bridges, and the holes.
func _draw_outlines() -> void:
	var closed := func(polygon: PackedVector2Array) -> PackedVector2Array:
		var line := polygon.duplicate()
		line.append(polygon[0])
		return line
	_outlines.draw_polyline(closed.call(data.boundary), NelvarEarthThing.DEBUG_COLOR, 3.0)
	for lake in data.lakes:
		_outlines.draw_polyline(closed.call(lake.shape.polygon(72)), Color.CYAN, 2.0)
		for patch in lake.thin:
			_outlines.draw_polyline(closed.call(patch.polygon(32)), Color.DODGER_BLUE, 2.0)
	for crevasse in data.crevasses:
		for edge in NelvarIceData.crevasse_edges(crevasse):
			_outlines.draw_polyline(edge, NelvarEarthThing.DEBUG_COLOR, 2.0)
		for bridge in crevasse.bridges:
			var side := bridge.direction.orthogonal() * (crevasse.half_width_at(bridge.along) + 8.0)
			for end in [-1.0, 1.0]:
				var at: Vector2 = bridge.center + bridge.direction * bridge.half_length * end
				_outlines.draw_line(at - side, at + side, Color.GREEN, 3.0)
	for hole in data.holes:
		_outlines.draw_arc(hole.center, hole.radius, 0.0, TAU, 32, Color.AQUA, 2.0)


## Everything in the valley, the peaks round it and the creatures under the ice,
## painted on several cores; the biggest peaks start first. The floor map is built
## alongside.
func _paint_world() -> void:
	var peaks := data.peaks.duplicate()
	peaks.sort_custom(func(a: NelvarEarthData.Thing, b: NelvarEarthData.Thing) -> bool:
		return a.size.x * a.size.y > b.size.x * b.size.y)
	_painting.append_array(peaks)
	_painting.append_array(data.things)
	_painting.append_array(data.frozen)
	_arts.resize(_painting.size())
	var field_task := WorkerThreadPool.add_task(_build_field, true, "Ice floor map")
	var group := WorkerThreadPool.add_group_task(_paint_thing, _painting.size(), _painters, true, "Ice art")
	WorkerThreadPool.wait_for_group_task_completion(group)
	var ridges: Array[NelvarEarthData.Thing] = []
	var ridge_arts := []
	for i in peaks.size():
		ridges.append(peaks[i])
		ridge_arts.append(_arts[i])
	_mountain_field = NelvarMountainField.build(ridges, ridge_arts)
	WorkerThreadPool.wait_for_task_completion(field_task)
	var frozen_arts := []
	for i in _painting.size():
		var art: NelvarIceArt = _arts[i]
		var item: Variant = _painting[i]
		if item is NelvarIceData.Frozen:
			frozen_arts.append(art)
			continue
		if art == null:
			continue
		art.bake()
		if item is NelvarEarthData.Thing:
			var peak: NelvarEarthData.Thing = item
			var spec := NelvarIceData.Thing.new()
			spec.kind = NelvarIceData.Kind.ROCK
			spec.position = peak.position
			spec.radius = peak.radius
			spec.appearance_seed = peak.appearance_seed
			spec.id = i
			var node := NelvarIceThing.new()
			node.setup(spec, art)
			node.name = "Peak_%d" % i
			actors.add_child(node)
			peak_nodes.append(node)
			continue
		var thing: NelvarIceData.Thing = item
		var node := NelvarIceThing.new()
		node.setup(thing, art)
		if thing.kind == NelvarIceData.Kind.STATUE:
			node.watcher = player
		actors.add_child(node)
		thing_nodes.append(node)
		if art.sway > 0:
			_swaying.append(node)
	depths.setup(data, frozen_arts, player)
	_arts.clear()
	_painting.clear()


func _paint_thing(index: int) -> void:
	var item: Variant = _painting[index]
	if item is NelvarEarthData.Thing:
		var peak: NelvarEarthData.Thing = item
		if peak.variant == NelvarEarthData.Peak.BOULDER:
			_arts[index] = _painter.paint_boulder(peak)
		else:
			_arts[index] = _frost_painter.paint(peak)
	elif item is NelvarIceData.Frozen:
		_arts[index] = _painter.paint_frozen(item)
	else:
		_arts[index] = _painter.paint(item)


func _build_field() -> void:
	_field = NelvarIceField.build(data)


func _setup_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:ice:floor" % data.world_seed).hash()
	snow_marks.setup(data, _field.origin, _field.size)
	var material := ground.backdrop_material()
	material.set_shader_parameter("texel_size", float(STEP))
	material.set_shader_parameter("field_tex", _field.texture())
	material.set_shader_parameter("field_origin", Vector2(_field.origin))
	material.set_shader_parameter("field_size", Vector2(_field.size))
	material.set_shader_parameter("valley_center", data.valley.center)
	material.set_shader_parameter("valley_axes", data.valley.axes)
	material.set_shader_parameter("valley_amp", data.valley.amplitudes)
	material.set_shader_parameter("valley_phase", data.valley.phases)
	material.set_shader_parameter("noise_offset", Vector2(rng.randi_range(-4096, 4096), rng.randi_range(-4096, 4096)))
	material.set_shader_parameter("mountain_tex", _mountain_field.texture())
	material.set_shader_parameter("mountain_origin", Vector2(_mountain_field.origin))
	material.set_shader_parameter("mountain_size", Vector2(_mountain_field.size))
	material.set_shader_parameter("mountain_scale", float(NelvarMountainField.SCALE))
	material.set_shader_parameter("marks_tex", snow_marks.texture())
	material.set_shader_parameter("marks_origin", Vector2(_field.origin))
	material.set_shader_parameter("marks_size", Vector2(_field.size))
	material.set_shader_parameter("mark_life", MARK_LIFE)
	ground.texel_size = STEP
	_field = null
	_mountain_field = null


## Snow falling over everything.
func _setup_sky() -> void:
	snowfall.texel_size = STEP
	snowfall.color = Color(1.0, 1.0, 1.0, 0.85)
	snowfall.lifetime = 3.0
	snowfall.preprocess = 3.0


## Blizzards for the whole visit, from the seed: each crosses the valley with the wind
## (from its west side, mostly), a lull between them; now and then a second one crosses
## while the first is still out.
func _plan_storms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:ice:storms" % data.world_seed).hash()
	var at := rng.randf_range(FIRST_LULL.x, FIRST_LULL.y)
	for i in 60:
		var end := _add_storm(rng, at)
		if rng.randf() < 0.2:
			end = maxf(end, _add_storm(rng, at + (end - at) * rng.randf_range(0.35, 0.6)))
		at = end + rng.randf_range(LULL_TIME.x, LULL_TIME.y)


func _add_storm(rng: RandomNumberGenerator, at: float) -> float:
	var storm := Storm.new()
	storm.start = at
	storm.duration = rng.randf_range(STORM_TIME.x, STORM_TIME.y)
	storm.radius = rng.randf_range(STORM_RADIUS.x, STORM_RADIUS.y)
	storm.strength = rng.randf_range(0.85, 1.0)
	var heading := Vector2.from_angle(rng.randf_range(-0.5, 0.5) + 0.08)
	var reach := data.valley.radius_at(heading.angle()) + storm.radius
	var across := heading.orthogonal() * rng.randf_range(-0.6, 0.6) * data.valley.axes.y
	storm.from = data.valley.center - heading * reach + across
	storm.to = data.valley.center + heading * reach + across
	storms.append(storm)
	return at + storm.duration


# --- Every frame --------------------------------------------------------------------

## The wind over the valley: gusts run across it from the left; plants lean with them
## (the floor's dry stems use the same function).
func gust(world: Vector2) -> float:
	return 0.65 * sin(world.x * 0.0045 + world.y * 0.0012 - _time * 1.7) \
		+ 0.35 * sin(world.x * 0.011 - world.y * 0.006 - _time * 2.6)


func _process(delta: float) -> void:
	if data == null:
		return
	_time += delta
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(200.0)
	for node in _swaying:
		if view.has_point(node.position):
			node.set_gust(gust(node.position) + storm_level)
	var material := ground.backdrop_material()
	material.set_shader_parameter("time", _time)
	material.set_shader_parameter("snow_clock", snow_clock)
	var cracks: Array[Vector4] = []
	for crack in hazards.cracks:
		var stage := 1.0 + crack.held_time / NelvarIceHazards.CRACK_LINGER if crack.held \
			else crack.age / NelvarIceHazards.CRACK_TIME
		cracks.append(Vector4(crack.center.x / STEP, crack.center.y / STEP,
			(NelvarIceHazards.CRACK_REACH + 6.0) / STEP, stage))
	var crack_count := cracks.size()
	while cracks.size() < MAX_CRACKS:
		cracks.append(Vector4.ZERO)
	material.set_shader_parameter("cracks", cracks)
	material.set_shader_parameter("crack_count", crack_count)
	var holes: Array[Vector4] = []
	for hole in data.holes:
		holes.append(Vector4(hole.center.x / STEP, hole.center.y / STEP, hole.radius / STEP, hole.freeze))
	var hole_count := holes.size()
	while holes.size() < MAX_HOLES:
		holes.append(Vector4.ZERO)
	material.set_shader_parameter("holes", holes)
	material.set_shader_parameter("hole_count", hole_count)
	blizzard.strength = storm_level
	snowfall.speed_scale = 1.0 + storm_level * 2.5
	if _show_debug:
		_outlines.queue_redraw()


func _physics_process(delta: float) -> void:
	if data == null:
		return
	clock += delta
	_update_storms(delta)
	hazards.update_holes(delta)
	hazards.update_cracks(delta)
	hazards.enemies()
	snow_marks.set_clock(snow_clock)
	snow_marks.track_player(player.global_position, player.is_airborne() or player.is_falling() or hazards.falling)
	hazards.step(delta)


## Holes freeze over (the tests hurry them on).
func _update_holes(delta: float) -> void:
	hazards.update_holes(delta)


## Blizzards move on; the one over the player slows them and drifts the snow faster;
## one drawing near is announced.
func _update_storms(delta: float) -> void:
	data.storms.clear()
	var warning := 0.0
	var side := Vector2.RIGHT
	var point := player.global_position
	for storm in storms:
		var strength := storm.strength_at(clock)
		var p := storm.progress(clock)
		if p > 1.0 or storm.start - clock > WARN_TIME * 2.0 + storm.duration * 0.5:
			continue
		var center := storm.center_at(clock)
		if strength > 0.0:
			data.storms.append(Vector4(center.x, center.y, storm.radius, strength))
		# Ahead of its edge, closing in: how soon it arrives.
		var speed := storm.from.distance_to(storm.to) / storm.duration
		var edge := center.distance_to(point) - storm.radius * 0.9
		var closing := (storm.to - storm.from).normalized().dot(center.direction_to(point)) * speed
		if edge > 0.0 and closing > 1.0 and p < 0.9:
			var eta := edge / closing
			if eta < WARN_TIME:
				var near := 1.0 - eta / WARN_TIME
				if near > warning:
					warning = near
					side = point.direction_to(center)
				if not storm.warned:
					storm.warned = true
					say(HINT_STORM)
	var target := data.storm_at(point)
	storm_level = move_toward(storm_level, target, delta * 1.5)
	player.move_scale = lerpf(1.0, STORM_MOVE, storm_level)
	player.attack_rate = lerpf(1.0, STORM_ATTACK, storm_level)
	snow_clock += delta * lerpf(1.0, STORM_CLOCK, storm_level)
	blizzard.warning = warning if storm_level < 0.2 else 0.0
	blizzard.warning_side = side


## A line in the middle of the screen, faded in and out.
func say(text: String) -> void:
	if _message_tween != null:
		_message_tween.kill()
	message.text = text
	_message_tween = create_tween()
	_message_tween.tween_property(message, "modulate:a", 1.0, MESSAGE_FADE)
	_message_tween.tween_interval(MESSAGE_HOLD)
	_message_tween.tween_property(message, "modulate:a", 0.0, MESSAGE_FADE)


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
