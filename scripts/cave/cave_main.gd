class_name NelvarCaveMain
extends Node2D
## The ice cave, Лёд 2 (developer setting "Запускать игру на Льду"): a maze of halls and
## winding passages cut into blue ice with dead creatures frozen into it. Mostly dusk (an
## overlay multiplies it in; the player carries their own soft light); under holes in the
## roof the sun shines in slanting shafts, snow falls and lies, pines grow. The big halls
## are cold — frost, mist, ice pillars, geysers. The valley (Лёд 1) stays as it is; both
## maps live side by side.
##
## The walls are solid: the cave's distance field gives the collision, the logic and the
## floor one boundary; the flight does not pass over them (it passes over the chasms, the
## water and the low things). The valley's hazards hold here (NelvarIceHazards): a step
## over a crevasse, a chasm or open water holds for a moment, then the player falls and
## comes back where they last stood safely, hurt; thin ice of the frozen lakes cracks under
## a standing player. Melting ice gives even under a walker: the strain grows while they
## are on it (faster standing), cracks run at half, the water seeps up at 0.8, and at 1 it
## breaks into a hole under them; a run gets across, a walk does not. Lake ice and the icy
## passages are slippery. Geysers erupt every 14–22 s: the warmth widens for a while and
## the blast throws hoppers back from the mouth; the player is never hurt or thrown, so a
## geyser is a good place to fight. Hoppers blown into a drop or the water die, never jump
## into them, and the spawner only puts them where the way on foot is short; the wind
## wave does not reach through the walls.
##
## Loading builds the floor's maps first, then paints what stands near the start on several
## cores (NelvarPaintQueue, as on the valley); the rest is painted while the game runs. The
## floor, the depths, the abyss and the light are drawn on the GPU.

const STEP := NelvarIceData.PIXEL
## The first frame waits for the art this near the start (world units); the rest fades in
## over APPEAR seconds as it is painted.
const READY_REACH := 700.0
const APPEAR := 0.35
const Surface = NelvarIceData.Surface
const Fall = NelvarIceData.Fall
## Falls, thin ice and holes are NelvarIceHazards'; the tests read these here.
const FALL_TIME := NelvarIceHazards.FALL_TIME
const FREEZE_TIME := NelvarIceHazards.FREEZE_TIME
const MAX_CRACKS := NelvarIceHazards.MAX_CRACKS
const MAX_HOLES := NelvarIceHazards.MAX_HOLES
## Snow-clock seconds a mark in the snow lasts (no blizzards here: the clock runs at 1).
const MARK_LIFE := 90.0
## Melting ice: the strain reaches 1 in this long on the move, STAND_RATE times faster
## standing still; off the ice it eases twice as fast as it grew.
const STRAIN_TIME := 1.0
const STAND_RATE := 2.5
const STILL_SPEED := 60.0
const HINT_MELT := "Подтаявший лёд: не задерживайся на нём даже на ходу"
const HINT_CHASM := "Пропасть. Ищи ледяную арку, разбегись (Ctrl) или взлети (Shift)"
const HINT_OPEN := "Открытая вода не держит. Обойди или перелети (Shift)"
## An eruption throws hoppers this far from the mouth, this hard.
const BLAST_REACH := 110.0
const BLAST_PUSH := 620.0
## The player's own light: radius (world units), strength.
const LIGHT_RADIUS := 190.0
const LIGHT_STRENGTH := 0.85
const DARK := Vector3(0.46, 0.52, 0.66)
const MAX_RIPPLES := 12
const MAX_FLARES := 8
const MAX_HEAT := 8
const MESSAGE_FADE := 0.6
const MESSAGE_HOLD := 2.8
const STEAM: Array[Color] = [Color8(150, 168, 184), Color8(186, 202, 214), Color8(216, 226, 234),
	Color8(240, 245, 250)]
const STEAM_PLUME: Array[Color] = [Color8(164, 180, 194), Color8(196, 210, 220), Color8(222, 232, 240),
	Color8(246, 250, 252)]

@export var config: NelvarCaveConfig = preload("res://resources/ice_cave_config.tres")

var data: NelvarCaveData
## The falls, the thin ice and the holes (shared with the valley).
var hazards: NelvarIceHazards
var thing_nodes: Array[NelvarIceThing] = []
var wall_bodies: Array[StaticBody2D] = []
## Falls (crevasses and chasms), plunges (water), cracks and holes so far (HUD and tests).
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
## Melting ice given way under the player, and how far it has given now (0..1).
var breaks := 0
var strain := 0.0
var eruptions := 0
## The shared clock: the geysers' cycles follow it; the tests may set it.
var clock := 0.0
var snow_clock := 0.0

var _time := 0.0
var _swaying: Array[NelvarIceThing] = []
var _painter := NelvarCavePainter.new()
var _queue: NelvarPaintQueue
var _field: NelvarCaveField
var _frozen_arts: Array = []
var _floater_arts: Array = []
var _geyser_stage := PackedInt32Array()
var _blasted := {}
var _snowfalls: Array[CPUParticles2D] = []
var _hinted := {}
var _message_tween: Tween
var _show_debug := false
var _outlines: Node2D
var _wall_lines := {}

@onready var abyss: NelvarCloudSea = $Abyss
@onready var depths: NelvarIceDepths = $Depths
@onready var ground: NelvarCloudSea = $Ground
@onready var world_layer: Node2D = $World
@onready var floaters: NelvarCaveFloaters = $World/Floaters
@onready var actors: Node2D = $Actors
@onready var player: NelvarPlayer = $Actors/Player
@onready var enemy_spawner: Node2D = $Actors/EnemySpawner
@onready var snow_marks: NelvarSnowMarks = $SnowMarks
@onready var skylights: Node2D = $Skylights
@onready var geysers: NelvarCaveGeysers = $Geysers
@onready var steam: NelvarSmoke = $Steam
@onready var shade: NelvarCloudSea = $Shade
@onready var shine: NelvarCloudSea = $Shine
@onready var info_panel: Control = $HUD/Margin/Stack/Panel
@onready var seed_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Seed
@onready var status_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Status
@onready var message: Label = $HUD/Message


func _ready() -> void:
	info_panel.visible = GameSettings.show_info_panel
	GameSettings.info_panel_changed.connect(info_panel.set_visible)
	message.modulate.a = 0.0
	# NelvarCloudSea puts every layer at -1; the abyss lies under the depths.
	abyss.layer = -3
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
	data = NelvarCaveGenerator.new().generate(config, world_seed)
	if data == null:
		seed_label.text = "Пещера не сложилась · сид %d" % world_seed
		status_label.text = "Ошибка генерации. Подробности в Output."
		info_panel.show()
		player.set_physics_process(false)
		player.set_process(false)
		return
	_wall_lines = NelvarCaveWalls.segments(data)
	wall_bodies = NelvarCaveWalls.build(_wall_lines, world_layer)
	_build_debug()
	_paint_world()
	_setup_ground()
	_setup_light()
	_setup_skylights()
	_setup_steam()
	player.position = data.spawn_position
	player.camera.reset_smoothing()
	data.path_origin = data.spawn_position
	# The spawner's path grid, built now rather than on the first spawn.
	data.path_distance(data.spawn_position)
	NelvarPlayer.sight_mask = NelvarCaveData.WALL_SIGHT_LAYER
	hazards = NelvarIceHazards.new(data, player, self, snow_marks)
	hazards.hints[Fall.CHASM] = HINT_CHASM
	hazards.fell.connect(_update_status.unbind(1))
	_geyser_stage.resize(data.geysers.size())
	geysers.setup(data)
	enemy_spawner.call("start_on", data)
	seed_label.text = "ЛЁД 2 · ПЕЩЕРА · СИД %d" % data.world_seed
	_update_status()
	var zones := NelvarCaveData.Zone
	var pools := NelvarCaveData.Pool
	print("Nelvar ice cave seed: %d | halls: %d (cold %d, sunny %d, dark %d, grottos %d) | passages: %d | geysers: %d | lakes: %d frozen, %d melting, %d open | chasms: %d (%d arches) | crevasses: %d | creatures: %d | floaters: %d | things: %d | %d ms" % [
		data.world_seed, data.halls.size(), data.zone_count(zones.COLD), data.zone_count(zones.SUNNY),
		data.zone_count(zones.DARK), data.zone_count(zones.GROTTO), data.passages.size(), data.geysers.size(),
		data.pool_count(pools.FROZEN), data.pool_count(pools.MELT), data.pool_count(pools.OPEN), data.chasms.size(),
		data.arch_count(), data.crevasses.size(), data.frozen.size(), data.floaters.size(), data.things.size(),
		Time.get_ticks_msec() - started])


func _exit_tree() -> void:
	NelvarPlayer.sight_mask = 0
	if _queue != null:
		_queue.stop()


func _update_status() -> void:
	status_label.text = "%d залов · %d ходов · %d гейзеров · %d озёр · %d пропастей · падений: %d" % [
		data.halls.size(), data.passages.size(), data.geysers.size(), data.lakes.size(), data.chasms.size(),
		falls + plunges]


# --- Building -------------------------------------------------------------------

func _build_debug() -> void:
	_outlines = Node2D.new()
	_outlines.name = "Outlines"
	_outlines.visible = false
	_outlines.z_index = 30
	_outlines.draw.connect(_draw_outlines)
	add_child(_outlines)


## F3: the walls' outline (the collision), the halls in the colour of their kind and the
## graph of the passages, the chasms with their arches and the crevasses with their
## bridges, the lakes by kind with their thin ice, the geysers' warmth, the edges of the
## cold, the sunny spots, the holes, and the spawner's path grid round the player.
func _draw_outlines() -> void:
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(100.0)
	var closed := func(polygon: PackedVector2Array) -> PackedVector2Array:
		var line := polygon.duplicate()
		line.append(polygon[0])
		return line
	for key: Vector2i in _wall_lines:
		if view.intersects(Rect2(Vector2(key) * NelvarCaveWalls.CHUNK, Vector2.ONE * NelvarCaveWalls.CHUNK)):
			_outlines.draw_multiline(_wall_lines[key], NelvarEarthThing.DEBUG_COLOR, 2.0)
	var colors: Array[Color] = [Color.SLATE_GRAY, Color.GOLD, Color.DEEP_SKY_BLUE, Color.MEDIUM_PURPLE]
	for hall in data.halls:
		_outlines.draw_polyline(closed.call(hall.shape.polygon(64)), colors[hall.zone], 2.0)
		if hall.zone == NelvarCaveData.Zone.COLD:
			var edge := PackedVector2Array()
			for i in 65:
				edge.append(hall.shape.point_at(TAU * i / 64.0, -NelvarCaveData.COLD_EDGE))
			_outlines.draw_polyline(edge, Color(0.6, 0.8, 1.0, 0.5), 1.0)
	for passage in data.passages:
		_outlines.draw_polyline(passage.points, Color.AQUAMARINE if passage.icy else Color(1, 1, 1, 0.5), 2.0)
	for chasm in data.chasms:
		for edge in NelvarIceData.crevasse_edges(chasm):
			_outlines.draw_polyline(edge, Color.BLACK, 3.0)
		for arch in chasm.arches:
			_outlines.draw_line(arch.a, arch.b, Color.LIGHT_CYAN, arch.half_width * 2.0)
	for crevasse in data.crevasses:
		for edge in NelvarIceData.crevasse_edges(crevasse):
			_outlines.draw_polyline(edge, NelvarEarthThing.DEBUG_COLOR, 2.0)
		for bridge in crevasse.bridges:
			var side := bridge.direction.orthogonal() * (crevasse.half_width_at(bridge.along) + 8.0)
			for end in [-1.0, 1.0]:
				var at: Vector2 = bridge.center + bridge.direction * bridge.half_length * end
				_outlines.draw_line(at - side, at + side, Color.GREEN, 3.0)
	var pool_colors: Array[Color] = [Color.CYAN, Color.LIGHT_SLATE_GRAY, Color.NAVY_BLUE]
	for l in data.lakes.size():
		_outlines.draw_polyline(closed.call(data.lake_polygons[l]), pool_colors[data.pools[l]], 2.0)
		for patch in data.lakes[l].thin:
			_outlines.draw_polyline(closed.call(patch.polygon(32)), Color.DODGER_BLUE, 2.0)
		if data.pools[l] == NelvarCaveData.Pool.OPEN:
			var water := PackedVector2Array()
			for i in 49:
				water.append(data.lakes[l].shape.point_at(TAU * i / 48.0, data.rims[l]))
			_outlines.draw_polyline(water, Color.BLUE, 2.0)
	for geyser in data.geysers:
		_outlines.draw_arc(geyser.position, geyser.radius * geyser.heat_scale(clock), 0.0, TAU, 40, Color.ORANGE, 2.0)
		_outlines.draw_arc(geyser.position, BLAST_REACH, 0.0, TAU, 24,
			Color.RED if geyser.stage_at(clock) == 2 else Color.KHAKI, 1.0)
	for skylight in data.skylights:
		_outlines.draw_polyline(closed.call(skylight.spot.polygon(48)), Color.YELLOW, 2.0)
	for hole in data.holes:
		_outlines.draw_arc(hole.center, hole.radius, 0.0, TAU, 32, Color.AQUA, 2.0)
	# The spawner's way on foot from the player: reachable cells, warmer further.
	var cell := NelvarCaveData.PATH_CELL
	var from := ((view.position - data.bounds.position) / cell).floor()
	var to := ((view.end - data.bounds.position) / cell).ceil()
	for y in range(int(from.y), int(to.y)):
		for x in range(int(from.x), int(to.x)):
			var center := data.bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			var distance := data.path_distance(center)
			if distance < INF:
				_outlines.draw_rect(Rect2(center - Vector2.ONE * 2.0, Vector2.ONE * 4.0),
					Color.from_hsv(clampf(distance / 2400.0, 0.0, 1.0) * 0.6, 0.8, 1.0, 0.8))


## The floor's maps, the creatures in the lakes and the walls and the bodies on the water
## (their nodes take them all at once) and what stands within READY_REACH of the start, on
## several cores before the first frame (NelvarPaintQueue); the rest after. Each thing
## stands at once and gets its art when painted.
func _paint_world() -> void:
	_queue = NelvarPaintQueue.new(_paint_job, _lay, "Cave art")
	_queue.add(["field"], 0.0, true)
	for i in data.frozen.size():
		_queue.add(["frozen", data.frozen[i], i], 0.0, true)
	for i in data.floaters.size():
		_queue.add(["floater", data.floaters[i], i], 0.0, true)
	_frozen_arts.resize(data.frozen.size())
	_floater_arts.resize(data.floaters.size())
	for thing in data.things:
		var node := NelvarIceThing.new()
		node.setup(thing)
		if thing.kind == NelvarIceData.Kind.STATUE or (thing.kind == NelvarIceData.Kind.EMBEDDED and thing.accent):
			node.watcher = player
		actors.add_child(node)
		thing_nodes.append(node)
		var size := maxf(thing.radius, maxf(thing.size.x, thing.size.y))
		_queue.add(["thing", thing, node], thing.position.distance_to(data.spawn_position) - size)
	_queue.start(READY_REACH)
	_queue.wait()
	depths.setup(data, _frozen_arts, player)
	floaters.setup(data, _floater_arts)
	_frozen_arts = []
	_floater_arts = []


## Runs on the painters.
func _paint_job(job: Array) -> Variant:
	match job[0]:
		"field":
			return NelvarCaveField.build(data)
		"frozen":
			return _painter.paint_frozen(job[1])
		"floater":
			return _painter.paint_floater(job[1])
	return _painter.paint(job[1])


## On the main thread: the art onto its thing.
func _lay(job: Array, result: Variant, late: bool) -> void:
	match job[0]:
		"field":
			_field = result
		"frozen":
			_frozen_arts[job[2]] = result
		"floater":
			_floater_arts[job[2]] = result
		"thing":
			var node: NelvarIceThing = job[2]
			var art: NelvarIceArt = result
			if art == null:
				thing_nodes.erase(node)
				node.queue_free()
				return
			art.bake()
			node.set_art(art)
			if art.sway > 0:
				_swaying.append(node)
			if late:
				node.modulate.a = 0.0
				node.create_tween().tween_property(node, "modulate:a", 1.0, APPEAR)


## Waits until all the art is painted and laid in (the tests).
func finish_painting() -> void:
	if _queue != null:
		_queue.finish()


func is_painting() -> bool:
	return _queue != null and _queue.busy()


func _setup_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:cave:floor" % data.world_seed).hash()
	var noise_offset := Vector2(rng.randi_range(-4096, 4096), rng.randi_range(-4096, 4096))
	snow_marks.setup(data, _field.origin, _field.size)
	var sdf := NelvarCaveField.sdf_texture(data)
	var zone := _field.zone_texture()
	var light := _field.light_texture()
	var material := ground.backdrop_material()
	material.set_shader_parameter("texel_size", float(STEP))
	material.set_shader_parameter("noise_offset", noise_offset)
	material.set_shader_parameter("sdf_tex", sdf)
	material.set_shader_parameter("sdf_origin", data.sdf_origin)
	material.set_shader_parameter("sdf_size", Vector2(data.sdf_size))
	material.set_shader_parameter("sdf_cell", NelvarCaveData.CELL)
	material.set_shader_parameter("field_tex", _field.texture())
	material.set_shader_parameter("zone_tex", zone)
	material.set_shader_parameter("field_origin", Vector2(_field.origin))
	material.set_shader_parameter("field_size", Vector2(_field.size))
	material.set_shader_parameter("marks_tex", snow_marks.texture())
	material.set_shader_parameter("marks_origin", Vector2(_field.origin))
	material.set_shader_parameter("marks_size", Vector2(_field.size))
	material.set_shader_parameter("mark_life", MARK_LIFE)
	for target in [material, shade.backdrop_material(), shine.backdrop_material()]:
		target.set_shader_parameter("light_tex", light)
		target.set_shader_parameter("light_origin", Vector2(_field.light_origin))
		target.set_shader_parameter("light_size", Vector2(_field.light_size))
		target.set_shader_parameter("light_scale", float(NelvarCaveField.LIGHT_SCALE))
	depths.set_mask(sdf, data.sdf_origin, Vector2(data.sdf_size), NelvarCaveData.CELL, zone, Vector2(_field.origin),
		Vector2(_field.size))
	ground.texel_size = STEP
	abyss.texel_size = STEP
	abyss.set_world_seed(data.world_seed)
	_field = null


## The dusk multiplied over everything, then the light added on top.
func _setup_light() -> void:
	var dusk := shade.backdrop_material()
	dusk.set_shader_parameter("texel_size", float(STEP))
	dusk.set_shader_parameter("dark", DARK)
	shade.texel_size = STEP
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	shade.use_as_overlay(1, multiply)
	var glow := shine.backdrop_material()
	glow.set_shader_parameter("texel_size", float(STEP))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:cave:shine" % data.world_seed).hash()
	glow.set_shader_parameter("noise_offset", Vector2(rng.randi_range(-4096, 4096), rng.randi_range(-4096, 4096)))
	shine.texel_size = STEP
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	shine.use_as_overlay(1, add)


## Snow falling through each hole in the roof, slow and nearly straight down; it only
## falls while the spot is near the screen.
func _setup_skylights() -> void:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
	for skylight in data.skylights:
		var snow := CPUParticles2D.new()
		snow.name = "Snowfall_%d" % _snowfalls.size()
		var spot := skylight.spot
		snow.position = spot.center + Vector2(0.0, -70.0)
		snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		snow.emission_rect_extents = spot.axes * Vector2(0.9, 0.75)
		snow.amount = clampi(int(spot.axes.x * spot.axes.y / 900.0), 24, 140)
		snow.lifetime = 4.5
		snow.preprocess = 4.5
		snow.direction = Vector2(0.18, 1.0)
		snow.spread = 10.0
		snow.gravity = Vector2(2.0, 8.0)
		snow.initial_velocity_min = 22.0
		snow.initial_velocity_max = 42.0
		snow.scale_amount_min = STEP
		snow.scale_amount_max = STEP
		snow.color_ramp = fade
		snow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		skylights.add_child(snow)
		_snowfalls.append(snow)


## Steam over the geysers: wisps from the mouths and the warm water, a cloud over each
## mouth seen from far off; the player's wind blows it away.
func _setup_steam() -> void:
	steam.palette = STEAM
	steam.plume_palette = STEAM_PLUME
	var wisps := PackedVector2Array()
	var plumes := PackedVector2Array()
	for geyser in data.geysers:
		plumes.append(geyser.position + Vector2(0.0, -16.0))
		for k in 3:
			wisps.append(geyser.position + Vector2.from_angle(TAU * k / 3.0) * geyser.mouth * 0.5)
	for l in data.lakes.size():
		if data.pools[l] != NelvarCaveData.Pool.OPEN:
			continue
		var shape := data.lakes[l].shape
		var warm := data.warmth_at(shape.center) > 0.0
		for geyser in data.geysers:
			warm = warm or shape.center.distance_to(geyser.position) < geyser.radius + shape.reach()
		if warm:
			for k in 4:
				wisps.append(shape.point_at(TAU * (k + 0.5) / 4.0, data.rims[l] + 12.0))
	steam.setup(data, wisps, plumes)


# --- Every frame --------------------------------------------------------------------

## A faint draught along the passages; the plants under the sun lean with it.
func gust(world: Vector2) -> float:
	return 0.5 * sin(world.x * 0.004 + world.y * 0.0015 - _time * 1.1) \
		+ 0.3 * sin(world.x * 0.01 - world.y * 0.005 - _time * 1.9)


func _process(delta: float) -> void:
	if data == null:
		return
	if _queue.busy():
		_queue.lay_in()
	_time += delta
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(200.0)
	for node in _swaying:
		if view.has_point(node.position):
			node.set_gust(gust(node.position))
	for i in _snowfalls.size():
		var spot := data.skylights[i].spot
		_snowfalls[i].emitting = view.grow(spot.reach() + 200.0).has_point(spot.center)
	geysers.clock = clock
	steam.gusts = NelvarEmbers.gusts_in(self)
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
	var ripples := floaters.ripples().slice(0, MAX_RIPPLES)
	var ripple_count := ripples.size()
	while ripples.size() < MAX_RIPPLES:
		ripples.append(Vector4.ZERO)
	material.set_shader_parameter("ripples", ripples)
	material.set_shader_parameter("ripple_count", ripple_count)
	var at := player.global_position / STEP
	material.set_shader_parameter("strain", Vector3(at.x, at.y, strain))
	# The light: the player's own, the geysers' warmth, the eruptions' flashes.
	var flares: Array[Vector4] = []
	var heat: Array[Vector4] = []
	var center := player.global_position
	var near_geysers := data.geysers.duplicate()
	near_geysers.sort_custom(func(a: NelvarCaveData.Geyser, b: NelvarCaveData.Geyser) -> bool:
		return a.position.distance_squared_to(center) < b.position.distance_squared_to(center))
	for geyser: NelvarCaveData.Geyser in near_geysers.slice(0, MAX_HEAT):
		var stage := geyser.stage_at(clock)
		var progress := geyser.progress_at(clock)
		var g := geyser.position / STEP
		heat.append(Vector4(g.x, g.y, geyser.radius / STEP, geyser.heat_scale(clock)))
		if stage == 2:
			flares.append(Vector4(g.x, g.y - 4.0, 46.0, 1.1 * (1.0 - progress)))
		elif stage == 1:
			flares.append(Vector4(g.x, g.y - 2.0, 20.0, progress * 0.45))
	var flare_count := mini(flares.size(), MAX_FLARES)
	flares = flares.slice(0, flare_count)
	while flares.size() < MAX_FLARES:
		flares.append(Vector4.ZERO)
	var heat_count := heat.size()
	while heat.size() < MAX_HEAT:
		heat.append(Vector4.ZERO)
	var dusk := shade.backdrop_material()
	dusk.set_shader_parameter("time", _time)
	dusk.set_shader_parameter("player", Vector4(at.x, at.y - 4.0, LIGHT_RADIUS / STEP, LIGHT_STRENGTH))
	dusk.set_shader_parameter("flares", flares)
	dusk.set_shader_parameter("flare_count", flare_count)
	dusk.set_shader_parameter("heat", heat)
	dusk.set_shader_parameter("heat_count", heat_count)
	var glow := shine.backdrop_material()
	glow.set_shader_parameter("time", _time)
	glow.set_shader_parameter("flares", flares)
	glow.set_shader_parameter("flare_count", flare_count)
	glow.set_shader_parameter("heat", heat)
	glow.set_shader_parameter("heat_count", heat_count)
	if _show_debug:
		_outlines.queue_redraw()


func _physics_process(delta: float) -> void:
	if data == null:
		return
	clock += delta
	snow_clock += delta
	data.path_origin = player.global_position
	hazards.update_holes(delta)
	hazards.update_cracks(delta)
	hazards.enemies()
	_geysers()
	snow_marks.set_clock(snow_clock)
	snow_marks.track_player(player.global_position, player.is_airborne() or player.is_falling() or hazards.falling)
	_melting(delta)
	if not hazards.falling and not player.is_airborne() and not _hinted.has(HINT_OPEN) \
			and data.water_depth(player.global_position) > 0.0:
		_hinted[HINT_OPEN] = true
		hazards.next_hint = HINT_OPEN
	hazards.step(delta)


## Holes freeze over (the tests hurry them on).
func _update_holes(delta: float) -> void:
	hazards.update_holes(delta)


## Melting ice gives under the player: the strain grows while they are on it (faster
## standing still) and eases off it; at 1 a hole opens under them.
func _melting(delta: float) -> void:
	if hazards.falling or player.is_falling() or player.health <= 0.0:
		strain = 0.0
		return
	var point := player.global_position
	if player.is_airborne() or data.ice_at(point) != Surface.MELT:
		strain = maxf(0.0, strain - delta / STRAIN_TIME * 2.0)
		return
	var still := player.velocity.length() < STILL_SPEED
	strain += delta / STRAIN_TIME * (STAND_RATE if still else 1.0)
	if strain >= 1.0:
		strain = 0.0
		breaks += 1
		if not _hinted.has(HINT_MELT):
			_hinted[HINT_MELT] = true
			hazards.next_hint = HINT_MELT
		hazards.break_at(point)


## Geysers: the eruption (drawn by NelvarCaveGeysers, steam thrown up) throws the hoppers
## near the mouth back; the player is left alone.
func _geysers() -> void:
	for i in data.geysers.size():
		var geyser := data.geysers[i]
		var stage := geyser.stage_at(clock)
		if stage == 2 and _geyser_stage[i] != 2:
			eruptions += 1
			_blasted.clear()
			geysers.erupt(i)
			steam.puff(geyser.position + Vector2(0.0, -30.0), 8)
		if stage == 2:
			for enemy in get_tree().get_nodes_in_group("enemies"):
				var body := enemy as Node2D
				if body == null or _blasted.has(body) or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
					continue
				var offset := body.global_position - geyser.position
				if offset.length() < BLAST_REACH:
					_blasted[body] = true
					if enemy.has_method("apply_knockback"):
						var away := offset.normalized() if offset.length() > 0.1 else Vector2.from_angle(randf() * TAU)
						enemy.call("apply_knockback", away * BLAST_PUSH)
		_geyser_stage[i] = stage


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
