class_name NelvarCraterMain
extends Node2D
## The volcano, Огонь 2 (developer setting "Запускать игру в Огне 2"): the top of one
## huge mountain. The player runs round the crater's narrow rim; the crater is a lake of
## lava with islands afloat on it; below the summit's edge clouds of ash drift far down.
##
## Nothing here is a wall. A step into the lava or off the edge holds for a moment
## (NelvarCraterData.COYOTE_TIME, sparks hiss under the player over the lava), then the
## player falls: into the lava they burn, off the edge they drop into the clouds; either
## way they come back where they last stood safely (on the rim or an anchor), hurt.
## Floating islands carry whoever stands on them; plates sink now and then by themselves
## (they warn first) and under someone who stands still too long, rafts almost at once.
## Geysers erupt and throw whoever stands in them up and along their run-up. Lava
## splashes over the shores: the fresh lava burns and slows, then sets into a safe crust.
## Hoppers burn in the lava and die off the edge, the wind can blow them either way.
##
## Loading paints the things on several cores (as the forge does); the floor, the clouds
## below, the islands, the light and the heat haze are drawn on the GPU.

const STEP := NelvarFireData.PIXEL
const MOLTEN_SHADER := preload("res://scripts/fire/fire_molten.gdshader")
const IsleKind = NelvarCraterData.IsleKind
## Burning in the lava, and dropping off the edge.
const LAVA_DAMAGE := 20.0
const SINK_TIME := 0.45
const LAVA_TINT := Color(1.0, 0.45, 0.12, 0.0)
const CLIFF_DAMAGE := 15.0
const CLIFF_TIME := 0.8
const ASH_TINT := Color(0.2, 0.15, 0.17, 0.0)
## Safe ground keeps this much to spare from the lava, the edge and the geysers.
const SAFE_MARGIN := 18.0
## Geysers: damage (before the throw: in the air nothing hurts), the throw.
const GEYSER_DAMAGE := 6.0
const GEYSER_ENEMY_DAMAGE := 20.0
const LAUNCH_TIME := 1.1
const LAUNCH_HEIGHT := 64.0
const LAUNCH_BOOST := 1.25
## Splashes: the blow, the fresh lava's burn and how it slows.
const SPLASH_DAMAGE := 10.0
const SPLASH_PUSH := 520.0
const FRESH_DAMAGE := 4.0
const FRESH_INTERVAL := 0.5
const FRESH_SLOW := 0.6
const HINT_SINK := "Остров не выдержит, если стоять на месте. Двигайся"
const HINT_FAR := "Слишком далеко. Разбегись (Ctrl), взлети (Shift) или дождись, пока остров подплывёт"
const MESSAGE_FADE := 0.6
const MESSAGE_HOLD := 3.0
const MAX_GEYSERS := 10
const MAX_FLARES := 8

@export var config: NelvarCraterConfig = preload("res://resources/fire_crater_config.tres")

var data: NelvarCraterData
var thing_nodes: Array[NelvarFireThing] = []
var isle_nodes: Array[NelvarCraterIsland] = []
## Falls so far: into the lava and off the edge; islands sunk under weight; eruptions.
var burns := 0
var drops := 0
var sunk := 0
var eruptions := 0

## The shared clock: the islands' places and the geysers' cycles follow it.
var clock := 0.0
var _time := 0.0
var _swaying: Array[NelvarFireThing] = []
var _painter := NelvarFirePainter.new()
var _painters := clampi(OS.get_processor_count() >> 1, 2, 12)
var _painting: Array = []
var _arts: Array = []
var _masks: Array = []
var _field: NelvarCraterField
var _molten_material: ShaderMaterial
var _safe_position := Vector2.ZERO
var _over_time := 0.0
var _falling := false
## The floating island the player stands on (null on the rim), and the last one.
var _riding: NelvarCraterData.Isle
var _geyser_stage := PackedInt32Array()
var _geyser_thrown := {}
var _fresh_timer := 0.0
var _hinted_sink := false
var _hinted_far := false
var _message_tween: Tween
var _show_debug := false
var _outlines: Node2D

@onready var below: NelvarCloudSea = $Below
@onready var ground: NelvarCloudSea = $Ground
@onready var smoke_shadows: NelvarCloudSea = $SmokeShadows
@onready var glow: NelvarCloudSea = $Glow
@onready var heat_haze: NelvarHeatHaze = $HeatHaze
@onready var world_layer: Node2D = $World
@onready var splashes: NelvarLavaSplashes = $World/Splashes
@onready var actors: Node2D = $Actors
@onready var player: NelvarPlayer = $Actors/Player
@onready var enemy_spawner: Node2D = $Actors/EnemySpawner
@onready var geysers: NelvarGeysers = $Geysers
@onready var embers: NelvarEmbers = $Embers
@onready var smoke: NelvarSmoke = $Smoke
@onready var critters: NelvarFireCritters = $Critters
@onready var info_panel: Control = $HUD/Margin/Stack/Panel
@onready var seed_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Seed
@onready var status_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Status
@onready var message: Label = $HUD/Message


func _ready() -> void:
	info_panel.visible = GameSettings.show_info_panel
	GameSettings.info_panel_changed.connect(info_panel.set_visible)
	message.modulate.a = 0.0
	# NelvarCloudSea puts every layer at -1; the clouds lie under the floor.
	below.layer = -2
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
	data = NelvarCraterGenerator.new().generate(config, world_seed)
	if data == null:
		seed_label.text = "Вулкан не сложился · сид %d" % world_seed
		status_label.text = "Ошибка генерации. Подробности в Output."
		info_panel.show()
		player.set_physics_process(false)
		player.set_process(false)
		return
	_build_debug()
	_paint_world()
	_setup_ground()
	_setup_sky()
	player.set_collision_mask_value(NelvarFireData.LAVA_LAYER_NUMBER, false)
	player.position = data.spawn_position
	player.camera.reset_smoothing()
	_safe_position = data.spawn_position
	_geyser_stage.resize(data.geysers.size())
	splashes.setup(data)
	for node in isle_nodes:
		splashes.isle_nodes[node.isle.id] = node
	splashes.struck.connect(_on_splash)
	enemy_spawner.call("start_on", data)
	seed_label.text = "ОГОНЬ 2 · ВУЛКАН · СИД %d" % data.world_seed
	_update_status()
	print("Nelvar volcano seed: %d | anchors: %d | plates: %d | rafts: %d | capes: %d | geysers: %d | boils: %d | things: %d | %d ms" % [
		data.world_seed, data.count_isles(IsleKind.ANCHOR), data.count_isles(IsleKind.PLATE),
		data.count_isles(IsleKind.RAFT), data.capes.size(), data.geysers.size(), data.boils.size(),
		data.things.size(), Time.get_ticks_msec() - started])


func _update_status() -> void:
	status_label.text = "%d островов · %d гейзеров · выплесков: %d · падений: %d" % [
		data.isles.size(), data.geysers.size(), splashes.count, burns + drops]


# --- Building -------------------------------------------------------------------

func _build_debug() -> void:
	_outlines = Node2D.new()
	_outlines.name = "Outlines"
	_outlines.visible = false
	_outlines.z_index = 30
	_outlines.draw.connect(_draw_outlines)
	add_child(_outlines)


## F3: the summit's edge and the shore, the islands as they are now (sunk parts left
## out), the rings they ride, the geysers' mouths and the splashes' tongues.
func _draw_outlines() -> void:
	var closed := func(polygon: PackedVector2Array) -> PackedVector2Array:
		var line := polygon.duplicate()
		line.append(polygon[0])
		return line
	_outlines.draw_polyline(closed.call(data.boundary), NelvarEarthThing.DEBUG_COLOR, 3.0)
	_outlines.draw_polyline(closed.call(data.lake_polygons[0]), Color.ORANGE, 2.0)
	for cape in data.capes:
		var outline := PackedVector2Array()
		var axis := cape.tip - cape.base
		var side := axis.normalized().orthogonal()
		for i in 13:
			var t := i / 12.0
			outline.append(cape.base + axis * t + side * cape.width_at(t))
		for i in 9:
			outline.append(cape.tip + Vector2.from_angle(side.angle() - PI * i / 8.0) * cape.width_at(1.0))
		for i in 13:
			var t := 1.0 - i / 12.0
			outline.append(cape.base + axis * t - side * cape.width_at(t))
		_outlines.draw_polyline(outline, Color.ORANGE, 2.0)
	for ring in data.rings:
		_outlines.draw_arc(data.vent, ring.x, 0.0, TAU, 96, Color(1.0, 0.8, 0.3, 0.35), 1.0)
		_outlines.draw_arc(data.vent, ring.y, 0.0, TAU, 96, Color(1.0, 0.8, 0.3, 0.35), 1.0)
	for isle in data.isles:
		var at := isle.position_at(clock)
		var sink := isle.sink_at(clock) * isle.sink_depth()
		var outline := PackedVector2Array()
		for i in 41:
			var angle := TAU * i / 40.0
			outline.append(at + Vector2.from_angle(angle) * maxf(0.0, isle.shape.radius_at(angle) - sink))
		_outlines.draw_polyline(outline, Color.CYAN if isle.moving() else Color.GREEN, 2.0)
	for geyser in data.geysers:
		_outlines.draw_arc(geyser.position, geyser.radius + NelvarPlayer.BODY_RADIUS, 0.0, TAU, 24,
			Color.YELLOW if geyser.stage_at(clock) == 2 else Color.KHAKI, 2.0)
	for splash in splashes.splashes:
		var origin := splash.world_origin(clock)
		var outline := PackedVector2Array()
		for i in 17:
			var angle := -PI * 0.5 + PI * i / 16.0
			outline.append(origin + splash.direction * cos(angle) * splash.reach
				+ splash.direction.orthogonal() * sin(angle) * splash.width * 0.5)
		_outlines.draw_polyline(outline, Color.RED, 2.0)


## Things on the rim and the anchors, painted on several cores; the islands' masks and
## the ground map are made alongside.
func _paint_world() -> void:
	_painting.append_array(data.things)
	_arts.resize(_painting.size())
	var moving := data.moving_isles()
	_masks.resize(moving.size())
	var field_task := WorkerThreadPool.add_task(_build_field, true, "Volcano ground map")
	var group := WorkerThreadPool.add_group_task(_paint_thing, _painting.size(), _painters, true, "Volcano art")
	var mask_group := WorkerThreadPool.add_group_task(_bake_mask.bind(moving), moving.size(), _painters, true,
		"Volcano islands")
	WorkerThreadPool.wait_for_group_task_completion(group)
	WorkerThreadPool.wait_for_group_task_completion(mask_group)
	WorkerThreadPool.wait_for_task_completion(field_task)
	_molten_material = ShaderMaterial.new()
	_molten_material.shader = MOLTEN_SHADER
	var wisps := PackedVector2Array()
	var sparks := PackedVector2Array()
	for i in _painting.size():
		var art: NelvarFireArt = _arts[i]
		if art == null:
			continue
		art.bake()
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
	for i in moving.size():
		var node := NelvarCraterIsland.new()
		node.setup(moving[i], _masks[i])
		world_layer.add_child(node)
		world_layer.move_child(node, 0)
		isle_nodes.append(node)
	_arts.clear()
	_painting.clear()
	_masks.clear()
	for geyser in data.geysers:
		wisps.append(geyser.position + Vector2(0.0, -4.0))
	embers.setup(data, sparks)
	embers.flame_spots.append(Vector3(data.vent.x, data.vent.y, data.vent_radius + 30.0))
	embers.flame_spots.append_array(data.boils)
	smoke.setup(data, wisps, PackedVector2Array([data.vent]))
	critters.setup(data, player, embers)
	geysers.setup(data, embers)


func _paint_thing(index: int) -> void:
	_arts[index] = _painter.paint(_painting[index])


func _bake_mask(index: int, moving: Array[NelvarCraterData.Isle]) -> void:
	_masks[index] = NelvarCraterIsland.bake_mask(moving[index])


func _build_field() -> void:
	_field = NelvarCraterField.build_crater(data)


func _setup_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:crater:floor" % data.world_seed).hash()
	var noise_offset := Vector2(rng.randi_range(-4096, 4096), rng.randi_range(-4096, 4096))
	var glow_texture := _field.glow_texture()
	var material := ground.backdrop_material()
	material.set_shader_parameter("texel_size", float(STEP))
	material.set_shader_parameter("noise_offset", noise_offset)
	material.set_shader_parameter("field_tex", _field.texture())
	material.set_shader_parameter("field_origin", Vector2(_field.origin))
	material.set_shader_parameter("field_size", Vector2(_field.size))
	material.set_shader_parameter("lake_center", data.lake.center)
	material.set_shader_parameter("lake_axes", data.lake.axes)
	material.set_shader_parameter("lake_amp", data.lake.amplitudes)
	material.set_shader_parameter("lake_phase", data.lake.phases)
	material.set_shader_parameter("edge_tex", _field.edge_texture())
	material.set_shader_parameter("edge_count", _field.edge.size())
	var lines: Array[Vector4] = []
	var forms: Array[Vector4] = []
	for cape in data.capes:
		lines.append(Vector4(cape.base.x, cape.base.y, cape.tip.x, cape.tip.y))
		forms.append(Vector4(cape.half_width, cape.tip_width, cape.wobble, cape.wobble_phase))
	material.set_shader_parameter("cape_count", lines.size())
	while lines.size() < 6:
		lines.append(Vector4.ZERO)
		forms.append(Vector4.ZERO)
	material.set_shader_parameter("cape_line", lines)
	material.set_shader_parameter("cape_form", forms)
	material.set_shader_parameter("cape_blend", NelvarCraterData.CAPE_BLEND)
	var shapes: Array[Vector4] = []
	var amps := PackedFloat32Array()
	var phases := PackedFloat32Array()
	for anchor in data.anchors():
		shapes.append(Vector4(anchor.center.x, anchor.center.y, anchor.shape.axes.x, anchor.shape.axes.y))
		amps.append_array(anchor.shape.amplitudes)
		phases.append_array(anchor.shape.phases)
	material.set_shader_parameter("anchor_count", shapes.size())
	while shapes.size() < 4:
		shapes.append(Vector4.ZERO)
	amps.resize(24)
	phases.resize(24)
	material.set_shader_parameter("anchor_shape", shapes)
	material.set_shader_parameter("anchor_amp", amps)
	material.set_shader_parameter("anchor_phase", phases)
	material.set_shader_parameter("vent", Vector3(data.vent.x, data.vent.y, data.vent_radius))
	var boils: Array[Vector3] = data.boils.duplicate()
	material.set_shader_parameter("boil_count", boils.size())
	while boils.size() < 6:
		boils.append(Vector3(0.0, 0.0, 1.0))
	material.set_shader_parameter("boils", boils.slice(0, 6))
	var rings: Array[Vector3] = data.rings.duplicate()
	material.set_shader_parameter("ring_count", rings.size())
	while rings.size() < 3:
		rings.append(Vector3.ZERO)
	material.set_shader_parameter("rings", rings.slice(0, 3))
	material.set_shader_parameter("ring_gap", config.ring_gap)
	material.set_shader_parameter("geyser_count", mini(data.geysers.size(), MAX_GEYSERS))
	material.set_shader_parameter("slope_tex", _field.slope_texture())
	material.set_shader_parameter("slope_origin", float(_field.slope_origin))
	var first := 0
	while first < _field.slope.size() - 1 and _field.slope[first] < 0.0:
		first += 1
	var last := _field.slope.size() - 1
	while last > 0 and _field.slope[last] < 0.0:
		last -= 1
	material.set_shader_parameter("slope_ends", Vector4(_field.slope_origin + first, _field.slope_origin + last,
		_field.slope[first], _field.slope[last]))
	material.set_shader_parameter("summit_mid", data.lake.center.x / STEP)
	material.set_shader_parameter("summit_half", (last - first) * 0.5)
	ground.texel_size = STEP
	below.texel_size = STEP
	below.set_world_seed(data.world_seed)
	var light := glow.backdrop_material()
	light.set_shader_parameter("texel_size", float(STEP))
	light.set_shader_parameter("noise_offset", noise_offset)
	light.set_shader_parameter("glow_tex", glow_texture)
	light.set_shader_parameter("glow_origin", Vector2(_field.glow_origin))
	light.set_shader_parameter("glow_size", Vector2(_field.glow_size))
	light.set_shader_parameter("glow_scale", float(NelvarFireField.GLOW_SCALE))
	# No land beyond to light: the glow's rivers of the forge stay out.
	light.set_shader_parameter("basin_center", Vector2.ZERO)
	light.set_shader_parameter("basin_axes", Vector2(1.0e6, 1.0e6))
	light.set_shader_parameter("basin_amp", PackedFloat32Array([0, 0, 0, 0, 0, 0]))
	light.set_shader_parameter("basin_phase", PackedFloat32Array([0, 0, 0, 0, 0, 0]))
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
	haze.set_shader_parameter("use_haze_mask", true)
	_field = null


## Shadows of the smoke drifting over the top.
func _setup_sky() -> void:
	smoke_shadows.texel_size = STEP
	smoke_shadows.set_world_seed(data.world_seed)
	var shadow := smoke_shadows.backdrop_material()
	shadow.set_shader_parameter("shade", Vector3(0.8, 0.74, 0.78))
	shadow.set_shader_parameter("cover", 0.24)
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	smoke_shadows.use_as_overlay(1, multiply)


# --- Every frame --------------------------------------------------------------------

## Hot gusts over the top; plants lean with them.
func gust(world: Vector2) -> float:
	return 0.65 * sin(world.x * 0.004 + world.y * 0.0015 - _time * 1.4) \
		+ 0.35 * sin(world.x * 0.012 - world.y * 0.005 - _time * 2.3)


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
	for node in isle_nodes:
		node.sync(clock, _time)
	var gusts := NelvarEmbers.gusts_in(self)
	embers.gusts = gusts
	smoke.gusts = gusts
	geysers.clock = clock
	var states: Array[Vector4] = []
	var flares: Array[Vector4] = []
	for i in mini(data.geysers.size(), MAX_GEYSERS):
		var geyser := data.geysers[i]
		var stage := geyser.stage_at(clock)
		var progress := geyser.progress_at(clock)
		states.append(Vector4(geyser.position.x / STEP, geyser.position.y / STEP, geyser.radius / STEP,
			stage + progress))
		if stage == 2:
			flares.append(Vector4(geyser.position.x / STEP, geyser.position.y / STEP, 22.0, 1.6 * (1.0 - progress)))
		elif stage == 1:
			flares.append(Vector4(geyser.position.x / STEP, geyser.position.y / STEP, 12.0, progress * 0.6))
	for splash in splashes.splashes:
		var stage := splash.stage_at(clock)
		var at := splash.world_origin(clock) + splash.direction * splash.reach * 0.4
		if stage == NelvarLavaSplashes.Stage.WARN:
			flares.append(Vector4(at.x / STEP, at.y / STEP, splash.width / STEP * 0.5, splash.age(clock) / NelvarLavaSplashes.WARN_TIME * 0.7))
		elif stage == NelvarLavaSplashes.Stage.FRESH:
			flares.append(Vector4(at.x / STEP, at.y / STEP, splash.width / STEP * 0.6, 1.0))
	while states.size() < MAX_GEYSERS:
		states.append(Vector4.ZERO)
	var material := ground.backdrop_material()
	material.set_shader_parameter("time", _time)
	material.set_shader_parameter("geysers", states)
	# The nearest flares to the player light and shimmer.
	var center := player.global_position
	flares.sort_custom(func(a: Vector4, b: Vector4) -> bool:
		return Vector2(a.x, a.y).distance_squared_to(center / STEP) < Vector2(b.x, b.y).distance_squared_to(center / STEP))
	var count := mini(flares.size(), MAX_FLARES)
	var near: Array[Vector4] = flares.slice(0, count)
	while near.size() < MAX_FLARES:
		near.append(Vector4.ZERO)
	heat_haze.material().set_shader_parameter("flares", near)
	heat_haze.material().set_shader_parameter("flare_count", count)
	var lit: Array[Vector4] = near.slice(0, count)
	lit.append(Vector4(data.vent.x / STEP, data.vent.y / STEP, (data.vent_radius + 60.0) / STEP,
		0.7 + 0.2 * sin(_time * 1.3)))
	var lit_count := lit.size()
	while lit.size() < 16:
		lit.append(Vector4.ZERO)
	glow.backdrop_material().set_shader_parameter("time", _time)
	glow.backdrop_material().set_shader_parameter("flares", lit)
	glow.backdrop_material().set_shader_parameter("flare_count", lit_count)
	if _show_debug:
		_outlines.queue_redraw()


func _physics_process(delta: float) -> void:
	if data == null:
		return
	var next := clock + delta
	_carry(next)
	clock = next
	data.now = clock
	_weigh(delta)
	_geysers()
	splashes.step(clock, player.global_position)
	data.fresh_lava = splashes.rim_hazards(clock)
	_splash_warnings()
	_enemies(delta)
	_fresh_lava(delta)
	if _falling or player.is_falling() or player.health <= 0.0:
		return
	if player.is_airborne():
		_over_time = 0.0
		return
	var point := player.global_position
	var off_edge := data.rim_depth(point) < 0.0
	var in_lava := data.lava_depth_at(point, clock) > 0.0
	if off_edge or in_lava:
		_over_time += delta
		if in_lava and Engine.get_physics_frames() % 3 == 0:
			# Sparks hiss under the player: a step too far.
			embers.burst(point, 1, 0.35)
		if _over_time > NelvarCraterData.COYOTE_TIME:
			_over_time = 0.0
			if off_edge:
				_drop()
			else:
				_burn()
		return
	_over_time = 0.0
	if _is_safe(point):
		_safe_position = point


## Floating islands carry whoever stands on them from `clock` to `next`.
func _carry(next: float) -> void:
	_riding = null
	if not player.is_falling() and not player.is_airborne() and not _falling:
		_riding = data.carrier_at(player.global_position, clock)
		if _riding != null:
			player.global_position += _riding.position_at(next) - _riding.position_at(clock)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
			continue
		var carrier := data.carrier_at(body.global_position, clock, 0.0)
		if carrier != null:
			body.global_position += carrier.position_at(next) - carrier.position_at(clock)


## Firm ground: the rim or an anchor, away from the lava, the edge, the geysers and any
## splash.
func _is_safe(point: Vector2) -> bool:
	var spare := NelvarPlayer.BODY_RADIUS + SAFE_MARGIN
	if data.rim_depth(point) < spare or data.lava_depth(point) > -spare:
		return false
	if data.geyser_at(point, spare + 10.0) != null:
		return false
	return not splashes.active_near(point, clock, spare) and splashes.fresh_at(point, clock) == null


## Weight on the island under the player: it settles, then goes down; it recovers half as
## fast once they leave.
func _weigh(delta: float) -> void:
	var standing: NelvarCraterData.Isle = null
	if not player.is_airborne() and not player.is_falling() and not _falling:
		standing = data.carrier_at(player.global_position, clock, 0.0)
	for isle in data.isles:
		if not isle.moving() or not is_finite(isle.hold_time):
			continue
		if isle == standing and isle.sink_at(clock) < 0.5:
			isle.weight += delta / isle.hold_time
			if isle.weight >= 0.5 and randf() < delta * 3.0:
				embers.burst(player.global_position + Vector2(randf_range(-30, 30), randf_range(-16, 16)), 1, 0.4)
			if isle.weight >= 1.0:
				isle.weight = 0.0
				isle.sank_at = clock
				sunk += 1
		else:
			isle.weight = maxf(0.0, isle.weight - delta / (isle.hold_time * 2.0))
		# Lava licks at a sinking edge.
		var sink := isle.sink_at(clock)
		if (sink > 0.0 and sink < 1.0) or isle.warn_at(clock) > 0.3:
			if randf() < delta * 6.0:
				var angle := randf() * TAU
				var edge := isle.position_at(clock) + Vector2.from_angle(angle) \
					* maxf(0.0, isle.shape.radius_at(angle) - sink * isle.sink_depth())
				embers.flame(edge, 1, 4.0)


## Geysers: the warning, the eruption, and the throw of whoever stands in the mouth.
func _geysers() -> void:
	for i in data.geysers.size():
		var geyser := data.geysers[i]
		var stage := geyser.stage_at(clock)
		if stage == 1 and randf() < 0.3:
			embers.burst(geyser.position, 1, 0.5)
		if stage == 2 and _geyser_stage[i] != 2:
			eruptions += 1
			_geyser_thrown.clear()
			geysers.erupt(i)
			smoke.puff(geyser.position + Vector2(0.0, -40.0), 7)
			embers.burst(geyser.position, 14, 1.6)
			embers.flame(geyser.position, 6, geyser.radius * 0.6)
		if stage == 2:
			var reach := geyser.radius + NelvarPlayer.BODY_RADIUS
			if not player.is_airborne() and not player.is_falling() and not _falling \
					and player.global_position.distance_to(geyser.position) < reach:
				# The damage first: in the air nothing hurts.
				player.take_damage(GEYSER_DAMAGE, geyser.position)
				player.launch(player.velocity * LAUNCH_BOOST, LAUNCH_HEIGHT, LAUNCH_TIME)
			for enemy in get_tree().get_nodes_in_group("enemies"):
				var body := enemy as Node2D
				if body == null or _geyser_thrown.has(body) or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
					continue
				if body.global_position.distance_to(geyser.position) < geyser.radius + 22.0:
					_geyser_thrown[body] = true
					enemy.call("take_damage", GEYSER_ENEMY_DAMAGE)
					if enemy.has_method("apply_knockback"):
						var away := geyser.position.direction_to(body.global_position)
						if away == Vector2.ZERO:
							away = Vector2.from_angle(randf() * TAU)
						enemy.call("apply_knockback", away * 320.0)
		_geyser_stage[i] = stage


## A splash comes over: whoever is in its tongue is hurt and thrown back from the lake.
func _on_splash(splash: NelvarLavaSplashes.Splash) -> void:
	_update_status()
	var origin := splash.world_origin(clock)
	for i in 10:
		embers.burst(origin + splash.direction * splash.reach * randf() + splash.direction.orthogonal()
			* randf_range(-0.4, 0.4) * splash.width, 2, 1.1)
	embers.flame(origin + splash.direction * splash.reach * 0.4, 8, splash.width * 0.3)
	if not player.is_airborne() and not player.is_falling() and splash.covers(player.global_position, clock):
		player.take_damage(SPLASH_DAMAGE, origin)
		player.velocity += splash.direction * SPLASH_PUSH
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
			continue
		if splash.covers(body.global_position, clock, 10.0):
			enemy.call("take_damage", SPLASH_DAMAGE)
			if enemy.has_method("apply_knockback"):
				enemy.call("apply_knockback", splash.direction * SPLASH_PUSH * 0.6)


## Where lava is about to come over, sparks rise from the rock and the lava bubbles up.
func _splash_warnings() -> void:
	for splash in splashes.splashes:
		var stage := splash.stage_at(clock)
		if stage == NelvarLavaSplashes.Stage.WARN and randf() < 0.35:
			var across := splash.direction.orthogonal() * randf_range(-0.45, 0.45) * splash.width
			embers.burst(splash.world_origin(clock) + splash.direction * randf() * splash.reach + across, 1, 0.6)
		elif stage == NelvarLavaSplashes.Stage.FRESH and randf() < 0.2:
			var across := splash.direction.orthogonal() * randf_range(-0.35, 0.35) * splash.width
			embers.flame(splash.world_origin(clock) + splash.direction * randf() * splash.reach * 0.8 + across, 1, 4.0)


## Fresh lava burns now and then and slows whoever wades through it.
func _fresh_lava(delta: float) -> void:
	var fresh: NelvarLavaSplashes.Splash = null
	if not player.is_airborne() and not player.is_falling() and not _falling:
		fresh = splashes.fresh_at(player.global_position, clock)
	player.move_scale = FRESH_SLOW if fresh != null else 1.0
	if fresh == null:
		_fresh_timer = 0.0
		return
	_fresh_timer -= delta
	if _fresh_timer <= 0.0:
		_fresh_timer = FRESH_INTERVAL
		player.take_damage(FRESH_DAMAGE, fresh.world_origin(clock))
		embers.flame(player.global_position, 2, 8.0)


## Hoppers in the lava burn up; off the edge they are gone; in fresh lava they hurt.
func _enemies(_delta: float) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
			continue
		var point := body.global_position
		if data.rim_depth(point) < -6.0:
			smoke.puff(point, 3)
			enemy.call("take_damage", 10000.0)
		elif data.lava_depth_at(point, clock) > 6.0:
			embers.burst(point, 18, 1.0)
			embers.flame(point, 4, 10.0)
			enemy.call("take_damage", 10000.0)


## Into the lava: the player sinks in a flash of sparks and comes back on safe ground,
## burnt. The first time it says what went wrong.
func _burn() -> void:
	_falling = true
	burns += 1
	var hint := ""
	var last := _riding if _riding != null else data.carrier_at(player.global_position, clock, 60.0)
	if last != null and (last.sink_at(clock) > 0.0 or last.sank_at > clock - 3.0):
		if not _hinted_sink:
			_hinted_sink = true
			hint = HINT_SINK
	elif not _hinted_far:
		_hinted_far = true
		hint = HINT_FAR
	_update_status()
	embers.burst(player.global_position, 24, 1.2)
	embers.flame(player.global_position, 6, 12.0)
	player.fall_into_abyss(SINK_TIME, LAVA_TINT)
	await get_tree().create_timer(SINK_TIME + 0.25, false).timeout
	_falling = false
	if not is_instance_valid(player):
		return
	player.recover_at(_safe_position)
	player.take_damage(LAVA_DAMAGE)
	if not hint.is_empty():
		say(hint)


## Off the edge: the player drops into the clouds far below and comes back, hurt.
func _drop() -> void:
	_falling = true
	drops += 1
	_update_status()
	player.fall_into_abyss(CLIFF_TIME, ASH_TINT)
	await get_tree().create_timer(CLIFF_TIME + 0.3, false).timeout
	_falling = false
	if not is_instance_valid(player):
		return
	player.recover_at(_safe_position)
	player.take_damage(CLIFF_DAMAGE)


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
