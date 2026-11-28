class_name NelvarThicketMain
extends NelvarLocation
## The giant forest, Земля 2 (developer setting "Запускать игру на Земле"): the floor of a
## forest of giants, the player the size of a beetle. Trunks wider than the screen go up
## into the dark of the crowns; grass blades are taller than the player, an acorn is a
## boulder, a mushroom's cap a roof. The sun comes through the crowns in flecks and in rays
## over the clearings. The plants are alive and dangerous: flytraps snap, puffballs burst
## into clouds of spores, acorns and branches fall from the oaks, resin pools at the pines'
## feet, loose earth over the hollows under the roots gives way. The player's wind turns it
## all against the enemies. The valley (Земля 1) stays as it is; both maps live side by side.
##
## The ring of giants closes the floor in (a low bank of roots on the south side). Roots are
## walls near their trunk (layer 1), low further out (layer 6: the flight passes over), lift
## into arches here and there, dip under the trails. The water is a fall, not a wall: lily
## pads hold, the leaves drifting round a pond carry whoever stands on them, the small ones
## sink under a standing player. Loose earth holds a moving player, not a standing one: a
## stander cracks it in STAND_TIME, then it gives (BREAK_TIME) into a pit that stays. Resin
## halves the speed and grips. A trunk, the fallen giant and a mushroom's cap thin out while
## the player is behind or under them.
##
## Loading paints everything on several cores (as on the valley); the floor, the crowns'
## shade and the light are drawn on the GPU. The game starts once the floor's maps, the
## traps' looks and the art near the start are painted; the trunks and the things stand and
## collide from the start, the rest of the art comes in nearest first while the game runs.

const STEP := NelvarEarthData.PIXEL
const Kind = NelvarEarthData.Kind
const Part = NelvarThicketData.Part
## The water: the player holds for a moment, then goes in.
const WATER_TIME := NelvarThicketData.COYOTE_TIME
const WATER_DAMAGE := 10.0
const WATER_TINT := Color(0.12, 0.34, 0.24, 0.0)
## Loose earth: standing this long within STILL_REACH cracks it, BREAK_TIME more opens a pit.
const STAND_TIME := 0.6
const BREAK_TIME := 0.5
const STILL_REACH := 30.0
const PIT_TIME := 0.09
const PIT_DAMAGE := 12.0
const EARTH_TINT := Color(0.32, 0.22, 0.14, 0.0)
const FALL_TIME := 0.6
## Resin: speed and grip; a hopper landing in it sticks for HOLD seconds.
const RESIN_SPEED := 0.5
const RESIN_GRIP := 2.0
const HOLD := 1.5
const HINT_LOOSE := "Рыхлая земля не держит, если стоять. Двигайся"
const HINT_WATER := "Вода не держит. Иди по кувшинкам и листьям, разбегись (Ctrl) или взлети (Shift)"
const HINT_SINK := "Маленький лист тонет под весом. Не стой на нём"
const MAX_GLOWS := 16
## Bands of rows the floor's maps are built in, at once.
const FIELD_BANDS := 32
## The first frame waits for the art this near the start (world units); the rest is painted
## while the game runs and fades in over APPEAR seconds.
const READY_REACH := 700.0
const APPEAR := 0.35
const GLOW := Color(0.18, 0.42, 0.44)
const DEW_SPLASH := Color(0.74, 0.9, 0.96)
const CRUMBLE := preload("res://assets/audio/sfx/earth_crumble.tres")
## Behind a trunk, the fallen giant or a mushroom (a little past their edge).
const BEHIND_MARGIN := 12.0

@export var config: NelvarThicketConfig = preload("res://resources/earth_thicket_config.tres")

var data: NelvarThicketData
var thing_nodes: Array[NelvarThicketThing] = []
var trunk_nodes: Array[NelvarGiantTrunk] = []
var root_pieces: Array[NelvarGiantTrunk.Piece] = []
var fallen_pieces: Array[NelvarGiantTrunk.Piece] = []
var plate_node: NelvarGiantTrunk.Piece
var root_bodies: Array[StaticBody2D] = []
var fallen_body: StaticBody2D
## Falls so far: into the water, into the loose earth.
var plunges := 0
var pit_falls := 0
## The shared clock: the rafts follow it; the tests may set it.
var clock := 0.0
## How far the fallen giant has thinned out (0..1).
var fallen_fade := 0.0

var _time := 0.0
var _painter := NelvarThicketPainter.new()
var _giant_painter := NelvarGiantPainter.new()
var _queue: NelvarPaintQueue
## Each big picture's plan -> [its bands (by slot), bands still out, its node or null].
var _plans := {}
var _trap_arts: Array = []
var _puff_arts: Array = []
var _raft_arts: Array = []
var _field: NelvarThicketField
var _swaying: Array[NelvarThicketThing] = []
var _mushrooms: Array[NelvarThicketThing] = []
var _dews: Array[NelvarThicketThing] = []
var _glows: Array[Vector2] = []
var _fallen_material: ShaderMaterial
var _safe_position := Vector2.ZERO
var _over_time := 0.0
var _falling := false
var _riding: NelvarThicketData.Raft
var _stand_anchor := Vector2.INF
var _stand_time := 0.0
## The crack spreading under a standing player: stage 0..1 (0: none).
var crack_stage := 0.0
var _held := {}
var _hinted := {}
var _pollen: Array[CPUParticles2D] = []
var _outlines: Node2D

@onready var ground: NelvarCloudSea = $Ground
@onready var world_layer: Node2D = $World
@onready var rafts: NelvarLeafRafts = $World/Rafts
@onready var actors: Node2D = $Actors
@onready var flytraps: NelvarFlytraps = $Flytraps
@onready var puffballs: NelvarPuffballs = $Puffballs
@onready var falling: NelvarFalling = $Falling
@onready var spores: NelvarSmoke = $Spores
@onready var leaves: NelvarLeaves = $Leaves
@onready var ants: NelvarAnts = $Ants
@onready var pollen_layer: Node2D = $Pollen
@onready var shade: NelvarCloudSea = $Shade
@onready var shine: NelvarCloudSea = $Shine


func _build() -> void:
	var started := Time.get_ticks_msec()
	data = NelvarThicketGenerator.new().generate(config, world_seed)
	if data == null:
		fail("Лес не сложился")
		return
	_build_walls()
	_build_debug()
	_paint_world()
	_setup_ground()
	_setup_light()
	_setup_pollen()
	player.position = data.spawn_position
	player.camera.reset_smoothing()
	_safe_position = data.spawn_position
	falling.setup(data, player, actors, puffballs)
	leaves.setup(data.world_seed, player)
	ants.setup(data, player)
	flytraps.snapped.connect(_on_snap)
	puffballs.burst.connect(_update_status.unbind(1))
	enemy_spawner.start_on(data)
	show_seed()
	_update_status()
	print("Nelvar giant forest seed: %d | giants: %d inside, %d in the ring | roots: %d (%d arches) | clearings: %d | trails: %d | ponds: %d (%d lily pads, %d rafts) | fallen giant: %s | flytraps: %d | puffballs: %d | loose: %d | resin: %d | things: %d | %d ms" % [
		data.world_seed, data.inner_giants().size(), data.giants.size() - data.inner_giants().size(), data.roots.size(),
		data.arch_count(), data.clearings.size(), data.trails.size(), data.ponds.size(), data.lilies.size(),
		data.rafts.size(), "yes" if data.fallen != null else "no", data.flytraps.size(), data.puffballs.size(),
		data.loose.size(), data.resin.size(), data.things.size(), Time.get_ticks_msec() - started])


func _update_status() -> void:
	status_label.text = "%d исполинов · %d полян · %d мухоловок · %d дождевиков · %d прудов · жёлудей: %d · падений: %d" % [
		data.inner_giants().size(), data.clearings.size(), data.flytraps.size(), data.puffballs.size(), data.ponds.size(),
		falling.acorns, plunges + pit_falls]


# --- Building -------------------------------------------------------------------

## The ring's edge, the roots' walls (high on World, low on layer 6) and the fallen giant's
## shell and root plate.
func _build_walls() -> void:
	var ring := StaticBody2D.new()
	ring.name = "GiantRing"
	ring.collision_layer = NelvarProp.WORLD_LAYER
	ring.collision_mask = 0
	var segments := PackedVector2Array()
	for i in data.boundary.size():
		segments.append(data.boundary[i])
		segments.append(data.boundary[(i + 1) % data.boundary.size()])
	var outline := ConcavePolygonShape2D.new()
	outline.segments = segments
	var collider := CollisionShape2D.new()
	collider.shape = outline
	ring.add_child(collider)
	world_layer.add_child(ring)
	for root in data.roots:
		for layer in [NelvarProp.WORLD_LAYER, NelvarProp.LOW_OBSTACLE_LAYER]:
			var body := _root_body(root, layer)
			if body != null:
				world_layer.add_child(body)
				root_bodies.append(body)
	if data.fallen != null:
		fallen_body = _fallen_body(data.fallen)
		world_layer.add_child(fallen_body)


func _root_body(root: NelvarThicketData.Root, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Root_%d_%s" % [root.id, "high" if layer == NelvarProp.WORLD_LAYER else "low"]
	body.collision_layer = layer
	body.collision_mask = 0
	for i in root.points.size() - 1:
		if NelvarThicketData.segment_layer(root, i) != layer:
			continue
		# A box along the segment (flat ends: an arch or a trail starts right there), a
		# disc at each joint with the next box of the same wall.
		var a := root.points[i]
		var b := root.points[i + 1]
		var side := a.direction_to(b).orthogonal()
		var box := ConvexPolygonShape2D.new()
		box.points = PackedVector2Array([a + side * root.widths[i] * 0.5, b + side * root.widths[i + 1] * 0.5,
			b - side * root.widths[i + 1] * 0.5, a - side * root.widths[i] * 0.5])
		var shape := CollisionShape2D.new()
		shape.shape = box
		body.add_child(shape)
		if i + 2 < root.points.size() and NelvarThicketData.segment_layer(root, i + 1) == layer:
			var joint := CircleShape2D.new()
			joint.radius = root.widths[i + 1] * 0.5
			var disc := CollisionShape2D.new()
			disc.shape = joint
			disc.position = b
			body.add_child(disc)
	if body.get_child_count() == 0:
		body.free()
		return null
	return body


## The fallen giant's walls: the north and south shell (breaches in the south one), the
## closed end at the root plate, and the plate itself.
func _fallen_body(fallen: NelvarThicketData.Fallen) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "FallenGiant"
	body.collision_layer = NelvarProp.WORLD_LAYER
	body.collision_mask = 0
	var axis := fallen.axis()
	var normal := fallen.normal()
	var length := fallen.length()
	var box := func(from: float, to: float, near: float, far: float) -> void:
		var shape := ConvexPolygonShape2D.new()
		shape.points = PackedVector2Array([fallen.start + axis * from + normal * near, fallen.start + axis * to + normal * near,
			fallen.start + axis * to + normal * far, fallen.start + axis * from + normal * far])
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
	box.call(0.0, length, -fallen.radius, -fallen.tunnel)
	var cuts: Array[Vector2] = []
	for breach in fallen.breaches:
		cuts.append(Vector2(breach.x - breach.y * 0.5, breach.x + breach.y * 0.5))
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var from := 0.0
	for cut in cuts:
		box.call(from, cut.x, fallen.tunnel, fallen.radius)
		from = cut.y
	box.call(from, length, fallen.tunnel, fallen.radius)
	box.call(0.0, fallen.plate_depth, -fallen.tunnel, fallen.tunnel)
	var plate := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		plate.append(fallen.plate_center + axis * cos(angle) * fallen.plate_depth + normal * sin(angle) * fallen.plate_half)
	var shape := ConvexPolygonShape2D.new()
	shape.points = plate
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	return body


func _build_debug() -> void:
	_outlines = Node2D.new()
	_outlines.name = "Outlines"
	_outlines.visible = false
	_outlines.z_index = 30
	_outlines.draw.connect(_draw_outlines)
	add_child(_outlines)


## F3: the ring's edge and the trunks' circles, the roots coloured by part (wall, low, arch,
## under a trail), the clearings and the trails, the oaks' reach, resin, loose earth and the
## pits, the traps (their own), the spore clouds, the rafts now, the tunnel's walls.
func _draw_outlines() -> void:
	var closed := func(polygon: PackedVector2Array) -> PackedVector2Array:
		var line := polygon.duplicate()
		line.append(polygon[0])
		return line
	_outlines.draw_polyline(closed.call(data.boundary), NelvarEarthThing.DEBUG_COLOR, 3.0)
	for giant in data.giants:
		_outlines.draw_arc(giant.center, giant.radius, 0.0, TAU, 64, NelvarEarthThing.DEBUG_COLOR, 3.0)
		if giant.species == NelvarThicketData.Wood.OAK and not giant.ring:
			_outlines.draw_arc(giant.center, giant.crown, 0.0, TAU, 96, Color(0.8, 0.6, 0.2, 0.6), 2.0)
	var part_colors: Array[Color] = [Color.RED, Color.ORANGE, Color.CYAN, Color.YELLOW]
	for root in data.roots:
		for i in root.points.size() - 1:
			_outlines.draw_line(root.points[i], root.points[i + 1], part_colors[root.parts[i]], 4.0)
	for clearing in data.clearings:
		_outlines.draw_arc(clearing.center, clearing.radius, 0.0, TAU, 64, Color.GOLD, 2.0)
	for trail in data.trails:
		_outlines.draw_polyline(trail.points, Color(1.0, 0.9, 0.6, 0.6), trail.half_width * 2.0)
	for pool in data.resin:
		_outlines.draw_arc(pool.center, pool.radius, 0.0, TAU, 32, Color.ORANGE, 2.0)
	for patch in data.loose:
		_outlines.draw_polyline(closed.call(patch.polygon(48)), Color.SADDLE_BROWN, 3.0)
	for pit in data.pits:
		_outlines.draw_arc(pit.center, pit.radius, 0.0, TAU, 24, Color.BLACK, 3.0)
	for cloud in puffballs.clouds:
		_outlines.draw_arc(cloud.center, cloud.size(), 0.0, TAU, 32, Color.YELLOW_GREEN, 2.0)
	for p in data.pond_polygons:
		_outlines.draw_polyline(closed.call(p), Color.DODGER_BLUE, 2.0)
	for lily in data.lilies:
		_outlines.draw_arc(lily.center, lily.radius, 0.0, TAU, 32, Color.GREEN, 2.0)
	if fallen_body != null:
		for child in fallen_body.get_children():
			var shape := (child as CollisionShape2D).shape as ConvexPolygonShape2D
			_outlines.draw_polyline(closed.call(shape.points), Color.MAGENTA, 2.0)


## Everything on the floor, the trunks, the roots, the fallen giant and the traps' and
## puffballs' looks, painted on several cores (NelvarPaintQueue); the trunks, the fallen giant
## and the floor's maps in bands of rows, the root plate in bands of columns, then each laid
## together. The trunks and the things stand (and collide) at once and get their art when it
## is painted. Waits for the floor's maps, the traps', puffballs' and rafts' looks and
## everything within READY_REACH of the start; the rest is painted while the game runs.
func _paint_world() -> void:
	_queue = NelvarPaintQueue.new(_paint_job, _lay, "Thicket art")
	_field = NelvarThicketField.start(data, FIELD_BANDS)
	_fallen_material = ShaderMaterial.new()
	_fallen_material.shader = NelvarGiantTrunk.SHADER
	for band in _field.band_count():
		_queue.add(["field", band], 0.0, true)
	for i in data.flytraps.size():
		_queue.add(["trap", data.flytraps[i], i], 0.0, true)
	for i in data.puffballs.size():
		_queue.add(["puff", data.puffballs[i], i], 0.0, true)
	for i in data.rafts.size():
		_queue.add(["raft", data.rafts[i], i], 0.0, true)
	_trap_arts.resize(data.flytraps.size())
	_puff_arts.resize(data.puffballs.size())
	_raft_arts.resize(data.rafts.size())
	var big := func(plan: NelvarGiantPainter.Plan, kind: String, parts: Array[Vector2i], node: Node2D) -> void:
		var near := _distance(Rect2(Vector2(plan.from) * STEP, Vector2(plan.to - plan.from + Vector2i.ONE) * STEP))
		var bands := []
		bands.resize(parts.size())
		_plans[plan] = [bands, parts.size(), node]
		for slot in parts.size():
			_queue.add([kind, plan, parts[slot], slot], near)
	for giant in data.giants:
		var node := NelvarGiantTrunk.new()
		node.setup(giant)
		actors.add_child(node)
		trunk_nodes.append(node)
		var plan := _giant_painter.plan_trunk(giant)
		big.call(plan, "trunk", plan.bands(), node)
	if data.fallen != null:
		var plan := _giant_painter.plan_fallen(data.fallen)
		big.call(plan, "fallen", plan.bands(), null)
		var plate := _giant_painter.plan_plate(data.fallen)
		big.call(plate, "plate", plate.columns(), null)
	for root in data.roots:
		var reach := Rect2(root.points[0], Vector2.ZERO)
		for point in root.points:
			reach = reach.expand(point)
		_queue.add(["root", root], _distance(reach.grow(160.0)))
	for thing in data.things:
		var node := NelvarThicketThing.new()
		node.setup(thing, null)
		if thing.kind == Kind.STATUE or thing.kind == Kind.AMBER:
			node.watcher = player
		actors.add_child(node)
		thing_nodes.append(node)
		if thing.kind == Kind.GIANT_MUSHROOM:
			if thing.variant == 2:
				_glows.append(thing.position + Vector2(0.0, -thing.size.y))
			else:
				_mushrooms.append(node)
		if thing.kind == Kind.DEW:
			_dews.append(node)
		var size := maxf(thing.radius, maxf(thing.size.x, thing.size.y))
		_queue.add(["thing", thing, node], thing.position.distance_to(data.spawn_position) - size)
	_queue.start(READY_REACH)
	_queue.wait()
	_field.finish()
	flytraps.setup(data, _trap_arts, player, actors)
	puffballs.setup(data, _puff_arts, player, actors, spores)
	spores.palette = NelvarPuffballs.SPORES
	spores.plume_palette = NelvarPuffballs.JET
	spores.setup(data, PackedVector2Array(), PackedVector2Array())
	rafts.setup(data, _raft_arts)
	_trap_arts = []
	_puff_arts = []
	_raft_arts = []


## How far a rect is from the start (0 inside it).
func _distance(rect: Rect2) -> float:
	var point := data.spawn_position
	return Vector2(maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0),
		maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)).length()


## Waits until all the art is painted and laid in (the tests).
func finish_painting() -> void:
	if _queue != null:
		_queue.finish()


func is_painting() -> bool:
	return _queue != null and _queue.busy()


## Runs on the painters.
func _paint_job(job: Array) -> Variant:
	match job[0]:
		"trunk":
			return _giant_painter.paint_trunk_rows(job[1], job[2])
		"fallen":
			return _giant_painter.paint_fallen_rows(job[1], job[2])
		"plate":
			return _giant_painter.paint_plate_columns(job[1], job[2])
		"finish":
			var plan: NelvarGiantPainter.Plan = job[1]
			if plan is NelvarGiantPainter.TrunkPlan:
				return _giant_painter.finish_trunk(plan, job[2])
			if plan is NelvarGiantPainter.FallenPlan:
				return _giant_painter.finish_fallen(plan, job[2])
			return _giant_painter.finish_plate(plan, job[2])
		"root":
			var root: NelvarThicketData.Root = job[1]
			return _giant_painter.paint_root(root, data.giants[root.giant].species)
		"field":
			_field.build_band(data, job[1])
		"thing":
			return _painter.paint(job[1])
		"trap":
			var arts: Array[NelvarEarthArt] = []
			for state in 4:
				arts.append(_painter.paint_flytrap(job[1], state))
			return arts
		"puff":
			return [_painter.paint_puffball(job[1], false), _painter.paint_puffball(job[1], true)]
		"raft":
			return _painter.paint_raft(job[1])
	return null


## On the main thread: art onto its node; new nodes for the roots, the fallen giant and the
## root plate; a big picture's finishing queued when its last band is in.
func _lay(job: Array, result: Variant, late: bool) -> void:
	match job[0]:
		"trunk", "fallen", "plate":
			var entry: Array = _plans[job[1]]
			entry[0][job[3]] = result
			entry[1] -= 1
			if entry[1] == 0:
				_queue.then(["finish", job[1], entry[0]])
		"finish":
			var plan: NelvarGiantPainter.Plan = job[1]
			if plan is NelvarGiantPainter.TrunkPlan:
				var art: NelvarEarthArt = result
				art.bake()
				var node: NelvarGiantTrunk = _plans[plan][2]
				node.set_art(art)
				_appear(node, late)
			elif plan is NelvarGiantPainter.FallenPlan:
				for piece: NelvarGiantPainter.Piece in result:
					piece.art.bake()
					var node := NelvarGiantTrunk.Piece.new()
					node.setup(piece, _fallen_material)
					node.name = "Fallen_%d" % fallen_pieces.size()
					actors.add_child(node)
					fallen_pieces.append(node)
					_appear(node, late)
			elif result != null:
				var piece: NelvarGiantPainter.Piece = result
				piece.art.bake()
				plate_node = NelvarGiantTrunk.Piece.new()
				plate_node.setup(piece)
				plate_node.name = "RootPlate"
				actors.add_child(plate_node)
				_appear(plate_node, late)
			_plans.erase(plan)
		"root":
			for piece: NelvarGiantPainter.Piece in result:
				piece.art.bake()
				var node := NelvarGiantTrunk.Piece.new()
				node.setup(piece)
				node.name = "Root_%d_%d" % [job[1].id, root_pieces.size()]
				actors.add_child(node)
				root_pieces.append(node)
				NelvarOcclusionOutline.add_occluder(node, piece.art.texture,
					Rect2(piece.origin + piece.art.local_rect.position, piece.art.local_rect.size))
				node.tree_exiting.connect(NelvarOcclusionOutline.remove_occluder.bind(node))
				_appear(node, late)
		"thing":
			var node: NelvarThicketThing = job[2]
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				return
			var art: NelvarEarthArt = result
			if art == null:
				thing_nodes.erase(node)
				_mushrooms.erase(node)
				_dews.erase(node)
				node.queue_free()
				return
			art.bake()
			node.set_art(art)
			if art.sway > 0:
				_swaying.append(node)
			_appear(node, late)
		"trap":
			_trap_arts[job[2]] = result
		"puff":
			_puff_arts[job[2]] = result
		"raft":
			_raft_arts[job[2]] = result


## Art laid in after the first frame fades in.
func _appear(node: CanvasItem, late: bool) -> void:
	if not late:
		return
	node.modulate.a = 0.0
	node.create_tween().tween_property(node, "modulate:a", 1.0, APPEAR)


## Leaving while still painting: the painters drop what is left, then the scene can go.
func _exit_tree() -> void:
	if _queue != null:
		_queue.stop()


func _setup_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:thicket:floor" % data.world_seed).hash()
	var noise_offset := Vector2(rng.randi_range(-4096, 4096), rng.randi_range(-4096, 4096))
	var material := ground.backdrop_material()
	material.set_shader_parameter("texel_size", float(STEP))
	material.set_shader_parameter("noise_offset", noise_offset)
	material.set_shader_parameter("field_tex", _field.texture())
	material.set_shader_parameter("field_origin", Vector2(_field.origin))
	material.set_shader_parameter("field_size", Vector2(_field.size))
	material.set_shader_parameter("valley_center", data.valley.center)
	material.set_shader_parameter("valley_axes", data.valley.axes)
	material.set_shader_parameter("valley_amp", data.valley.amplitudes)
	material.set_shader_parameter("valley_phase", data.valley.phases)
	var giants: Array[Vector4] = []
	var heights := PackedFloat32Array()
	for giant in data.giants.slice(0, 24):
		giants.append(Vector4(giant.center.x, giant.center.y, giant.radius, giant.species))
		heights.append(giant.height)
	material.set_shader_parameter("giant_count", giants.size())
	while giants.size() < 24:
		giants.append(Vector4.ZERO)
		heights.append(0.0)
	material.set_shader_parameter("giants", giants)
	material.set_shader_parameter("giant_height", heights)
	if data.fallen != null:
		var fallen := data.fallen
		material.set_shader_parameter("fallen_start", fallen.start)
		material.set_shader_parameter("fallen_axis", fallen.axis())
		material.set_shader_parameter("fallen_size", Vector3(fallen.length(), fallen.radius, fallen.tunnel))
		material.set_shader_parameter("plate_pit", Vector3(fallen.plate_center.x, fallen.plate_center.y, 0.0)
			+ Vector3(-fallen.axis().x, -fallen.axis().y, 0.0) * (fallen.plate_depth + 110.0) + Vector3(0.0, 0.0, 150.0))
	var light := _field.light_texture()
	for target in [material, shade.backdrop_material(), shine.backdrop_material()]:
		target.set_shader_parameter("light_tex", light)
		target.set_shader_parameter("light_origin", Vector2(_field.light_origin * NelvarThicketField.LIGHT_SCALE))
		target.set_shader_parameter("light_size", Vector2(_field.light_size))
		target.set_shader_parameter("light_scale", float(NelvarThicketField.LIGHT_SCALE))
		target.set_shader_parameter("noise_offset", noise_offset)
		target.set_shader_parameter("texel_size", float(STEP))
	ground.texel_size = STEP
	_field = null


## The crowns' shade multiplied over everything, then the light added on top.
func _setup_light() -> void:
	shade.texel_size = STEP
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	shade.use_as_overlay(1, multiply)
	if data.fallen != null:
		var dusk := shade.backdrop_material()
		dusk.set_shader_parameter("tunnel_start", data.fallen.start)
		dusk.set_shader_parameter("tunnel_axis", data.fallen.axis())
		dusk.set_shader_parameter("tunnel_size", Vector2(data.fallen.length(), data.fallen.tunnel))
	shine.texel_size = STEP
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	shine.use_as_overlay(1, add)


## Pollen drifting in the light over each clearing (only near the screen).
func _setup_pollen() -> void:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	for clearing in data.clearings:
		var motes := CPUParticles2D.new()
		motes.name = "Pollen_%d" % _pollen.size()
		motes.position = clearing.center + Vector2(0.0, -60.0)
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		motes.emission_sphere_radius = clearing.radius
		motes.amount = clampi(int(clearing.radius * clearing.radius / 2600.0), 16, 70)
		motes.lifetime = 5.0
		motes.preprocess = 5.0
		motes.direction = Vector2(0.6, -1.0)
		motes.spread = 40.0
		motes.gravity = Vector2(4.0, -3.0)
		motes.initial_velocity_min = 6.0
		motes.initial_velocity_max = 16.0
		motes.scale_amount_min = STEP
		motes.scale_amount_max = STEP
		motes.color = Color(1.0, 0.94, 0.62, 0.85)
		motes.color_ramp = fade
		motes.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pollen_layer.add_child(motes)
		_pollen.append(motes)


# --- Every frame --------------------------------------------------------------------

## The wind high up in the crowns; the grass and the flecks of sun move with it.
func gust(world: Vector2) -> float:
	return 0.65 * sin(world.x * 0.0045 + world.y * 0.0012 - _time * 1.5) \
		+ 0.35 * sin(world.x * 0.011 - world.y * 0.006 - _time * 2.4)


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
	for i in _pollen.size():
		_pollen[i].emitting = view.grow(data.clearings[i].radius).has_point(data.clearings[i].center)
	rafts.sync(clock)
	_fade(delta)
	var gusts := NelvarEmbers.gusts_in(self)
	puffballs.gusts = gusts
	spores.gusts = gusts
	_pop_dew(gusts)
	var material := ground.backdrop_material()
	material.set_shader_parameter("time", _time)
	var pits: Array[Vector4] = []
	for pit in data.pits:
		pits.append(Vector4(pit.center.x, pit.center.y, pit.radius, pit.age))
	material.set_shader_parameter("pit_count", pits.size())
	while pits.size() < NelvarThicketData.MAX_PITS:
		pits.append(Vector4.ZERO)
	material.set_shader_parameter("pits", pits)
	if crack_stage > 0.0:
		material.set_shader_parameter("crack", Vector4(_stand_anchor.x, _stand_anchor.y, crack_stage, 60.0))
	else:
		material.set_shader_parameter("crack", Vector4.ZERO)
	shade.backdrop_material().set_shader_parameter("time", _time)
	var glow := shine.backdrop_material()
	glow.set_shader_parameter("time", _time)
	var near := _glows.filter(func(p: Vector2) -> bool: return p.distance_to(player.global_position) < 1000.0)
	var glows: Array[Vector4] = []
	var tints := PackedVector3Array()
	for p: Vector2 in near.slice(0, MAX_GLOWS):
		glows.append(Vector4(p.x / STEP, p.y / STEP, 16.0, 0.9))
		tints.append(Vector3(GLOW.r, GLOW.g, GLOW.b))
	glow.set_shader_parameter("glow_count", glows.size())
	while glows.size() < MAX_GLOWS:
		glows.append(Vector4.ZERO)
		tints.append(Vector3.ZERO)
	glow.set_shader_parameter("glows", glows)
	glow.set_shader_parameter("glow_tint", tints)
	if show_debug:
		_outlines.queue_redraw()


## Trunks, mushrooms' caps and the fallen giant thin out while the player is behind them.
func _fade(delta: float) -> void:
	var point := player.global_position
	for node in trunk_nodes:
		if node.giant.center.distance_to(point) < node.reach() + node.giant.radius + 400.0 or node.fade > 0.0:
			node.update_fade(node.hides(point, BEHIND_MARGIN), delta)
			node.crawl(delta)
	for node in _mushrooms:
		if node.position.distance_to(point) < 500.0 or node.fade > 0.0:
			node.update_fade(node.hides(point), delta)
	if data.fallen != null:
		var behind := fallen_hides(point)
		var target := 1.0 if behind else 0.0
		if not is_equal_approx(fallen_fade, target):
			fallen_fade = move_toward(fallen_fade, target, delta / (NelvarGiantTrunk.FADE_IN if behind else NelvarGiantTrunk.FADE_OUT))
			_fallen_material.set_shader_parameter("fade", fallen_fade)


## True when the point is in the fallen giant's tunnel, or behind it on screen.
func fallen_hides(point: Vector2) -> bool:
	var fallen := data.fallen
	if fallen == null:
		return false
	var local := fallen.local(point)
	if local.x < -BEHIND_MARGIN or local.x > fallen.length() + BEHIND_MARGIN:
		return false
	var top := fallen.radius * 1.45
	return local.y < fallen.radius and local.y > -fallen.radius - top


func _physics_process(delta: float) -> void:
	if data == null:
		return
	var next := clock + delta
	_carry(next)
	clock = next
	rafts.step(delta, _riding)
	flytraps.step(delta)
	puffballs.step(delta)
	falling.step(clock, delta)
	_enemies()
	for pit in data.pits:
		pit.age += delta
	if _falling or player.is_falling() or player.health <= 0.0:
		return
	if player.is_airborne():
		# The flight passes over the water, the resin and the loose earth.
		player.move_scale = 1.0
		player.traction = 1.0
		_over_time = 0.0
		_stand_anchor = Vector2.INF
		crack_stage = 0.0
		return
	var point := player.global_position
	var in_resin := data.resin_at(point)
	player.move_scale = RESIN_SPEED if in_resin else 1.0
	player.traction = RESIN_GRIP if in_resin else 1.0
	if data.water_at(point, clock):
		_over_time += delta
		if _over_time > WATER_TIME:
			_over_time = 0.0
			_plunge()
		return
	if data.pit_at(point) != null:
		_over_time += delta
		if _over_time > PIT_TIME:
			_over_time = 0.0
			_fall_in_pit()
		return
	_over_time = 0.0
	_loose(point, delta)
	if _riding == null and data.is_safe_spot(point):
		_safe_position = point


## Rafts carry whoever stands on them from `clock` to `next`.
func _carry(next: float) -> void:
	_riding = null
	if not player.is_falling() and not player.is_airborne() and not _falling:
		_riding = data.carrier_at(player.global_position, clock)
		if _riding != null:
			player.global_position += _riding.position_at(next) - _riding.position_at(clock)
			if _riding.small() and not _hinted.has(HINT_SINK) and _riding.sink > 0.2:
				_hinted[HINT_SINK] = true
				say(HINT_SINK)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
			continue
		var carrier := data.carrier_at(body.global_position, clock, 0.0)
		if carrier != null:
			body.global_position += carrier.position_at(next) - carrier.position_at(clock)


## Loose earth: a stander cracks it, then it gives into a pit under them.
func _loose(point: Vector2, delta: float) -> void:
	if not data.is_loose(point):
		_stand_anchor = Vector2.INF
		crack_stage = 0.0
		return
	if not _stand_anchor.is_finite() or point.distance_to(_stand_anchor) > STILL_REACH:
		_stand_anchor = point
		_stand_time = 0.0
		crack_stage = 0.0
		return
	_stand_time += delta
	if _stand_time < STAND_TIME:
		return
	if crack_stage == 0.0:
		NelvarOneShotSound.play(self, CRUMBLE, _stand_anchor, -2.0)
	crack_stage = clampf((_stand_time - STAND_TIME) / BREAK_TIME, 0.01, 1.0)
	if Engine.get_physics_frames() % 4 == 0:
		_puff(_stand_anchor + Vector2(randf_range(-20.0, 20.0), randf_range(-8.0, 8.0)), Color(0.36, 0.26, 0.18), 2)
	if _stand_time >= STAND_TIME + BREAK_TIME:
		open_pit(point)
		crack_stage = 0.0
		_stand_anchor = Vector2.INF
		_fall_in_pit()


## A pit opens at the point (it stays till the end of the run).
func open_pit(point: Vector2) -> NelvarThicketData.Pit:
	if data.pits.size() >= NelvarThicketData.MAX_PITS:
		data.pits.remove_at(0)
	var pit := NelvarThicketData.Pit.new()
	pit.center = point
	data.pits.append(pit)
	_puff(point, Color(0.3, 0.22, 0.14), 16)
	return pit


func _fall_in_pit() -> void:
	pit_falls += 1
	_fall(EARTH_TINT, PIT_DAMAGE, HINT_LOOSE)


func _plunge() -> void:
	plunges += 1
	_puff(player.global_position, Color(0.6, 0.8, 0.74), 16)
	_fall(WATER_TINT, WATER_DAMAGE, HINT_WATER)


## The player goes down and comes back where they last stood safely, hurt; the first fall
## of a kind says what to do.
func _fall(tint: Color, damage: float, hint: String) -> void:
	_falling = true
	_update_status()
	player.fall_into_abyss(FALL_TIME, tint)
	await get_tree().create_timer(FALL_TIME + 0.3, false).timeout
	_falling = false
	if not is_instance_valid(player):
		return
	player.recover_at(_safe_position)
	player.take_damage(damage)
	_stand_anchor = Vector2.INF
	if not _hinted.has(hint):
		_hinted[hint] = true
		say(hint)


## Hoppers blown into the water or a pit die; one in resin sticks for a moment.
func _enemies() -> void:
	var seen := {}
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
			continue
		var point := body.global_position
		if data.water_at(point, clock, 6.0):
			_puff(point, Color(0.6, 0.8, 0.74), 12)
			enemy.call("take_damage", 10000.0)
		elif data.pit_at(point, -6.0) != null:
			_puff(point, Color(0.3, 0.22, 0.14), 10)
			enemy.call("take_damage", 10000.0)
		elif data.resin_at(point):
			var id := body.get_instance_id()
			seen[id] = true
			if not _held.has(id) and enemy.has_method("apply_hold"):
				enemy.call("apply_hold", HOLD)
	_held = seen


## A drop of dew bursts at the player's touch, their shot or wave.
func _pop_dew(gusts: Array) -> void:
	var point := player.global_position
	for node: NelvarThicketThing in _dews.duplicate():
		var spot := node.position + Vector2(0.0, -node.thing.radius)
		var burst := not player.is_airborne() and point.distance_to(node.position) < node.thing.radius + NelvarPlayer.BODY_RADIUS
		for gust: Array in gusts:
			if (gust[0] as Vector2).distance_to(spot) < float(gust[2]) * 0.6 + node.thing.radius:
				burst = true
		if burst:
			_dews.erase(node)
			thing_nodes.erase(node)
			_puff(spot, DEW_SPLASH, 8)
			node.queue_free()


func _on_snap(_trap: NelvarThicketData.Flytrap, _eaten: int, _hurt: bool) -> void:
	_update_status()


## Bits thrown up (earth, water, spores).
func _puff(point: Vector2, color: Color, count: int) -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = count
	particles.lifetime = 0.6
	particles.direction = Vector2.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 50.0
	particles.initial_velocity_max = 140.0
	particles.gravity = Vector2(0.0, 320.0)
	particles.scale_amount_min = STEP
	particles.scale_amount_max = STEP
	particles.color = color
	particles.position = point
	particles.z_index = 20
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.finished.connect(particles.queue_free)
	add_child(particles)
	particles.emitting = true


## F3: the colliders and the outlines.
func _set_debug(shown: bool) -> bool:
	_outlines.visible = shown
	_outlines.queue_redraw()
	for node in thing_nodes:
		if node.thing.solid:
			node.show_collision = shown
			node.queue_redraw()
	for node in trunk_nodes:
		node.show_collision = shown
		node.queue_redraw()
	flytraps.set_debug(shown)
	puffballs.set_debug(shown)
	rafts.set_debug(shown)
	return true
