extends SceneTree
## The ice cave, Лёд 2: the layout (halls and their ways out, loops, the start, geysers,
## snow and pines under the sun, things and creatures where they belong, melting ice and
## open water never on the only way), walking everywhere from the start and the passages
## wide enough, the wall over every south face, the walls' one boundary (collision,
## queries, shader field), the floor's maps against the queries, the art, the start
## setting, and the real scene: the walls hold even in flight, melting ice gives under a
## walker and not under a runner, a stander goes through at once; thin ice, open water and
## chasms drop the player and bring them back hurt; an icy passage slides; snow takes marks
## and stone does not; hoppers blown into a drop die; the wave stops at a wall; an eruption
## throws a hopper and leaves the player be; the spawner keeps to short ways on foot.
## Run: godot --headless --path . --script tests/test_cave.gd -- --seeds=6

const Kind = NelvarIceData.Kind
const Zone = NelvarCaveData.Zone
const Pool = NelvarCaveData.Pool
const BODY := NelvarPlayer.BODY_RADIUS
const PIXEL := NelvarIceData.PIXEL

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 6
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	var config := NelvarCaveConfig.new()
	var generator := NelvarCaveGenerator.new()
	var started := Time.get_ticks_msec()
	var halls := 0
	var loops := 0
	for index in count:
		var world_seed := 20261126 + index * 7919
		var data := generator.generate(config, world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		halls += data.halls.size()
		loops += data.passages.size() - data.halls.size() + 1
		_check_layout(data, config)
		if index < 2:
			_check(_fingerprint(generator.generate(config, world_seed)) == _fingerprint(data),
				"Seed %d: the layout is not reproducible" % world_seed)
		if index < 3:
			_check_reach(data)
			_check_faces(data)
		if index == 0:
			_check_walls(data)
			_check_field(data)
			_check_art(data)
	print("Cave: %d seeds in %.1f s · %.1f halls · %.1f loops each" % [count,
		float(Time.get_ticks_msec() - started) / 1000.0, float(halls) / count, float(loops) / count])
	_check_settings()
	await _check_scene()
	if _failures.is_empty():
		print("PASS: %d checks; the cave's layout, walls, floor, art, hazards and the scene behave" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


# --- Layout ----------------------------------------------------------------------------

func _check_layout(data: NelvarCaveData, config: NelvarCaveConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	_check(data.zone_count(Zone.COLD) >= config.cold_halls.x and data.zone_count(Zone.SUNNY) >= config.sunny_halls.x
		and data.zone_count(Zone.GROTTO) >= 2 and data.zone_count(Zone.DARK) >= 2,
		context + "halls: %d cold, %d sunny, %d dark, %d grottos" % [data.zone_count(Zone.COLD),
		data.zone_count(Zone.SUNNY), data.zone_count(Zone.DARK), data.zone_count(Zone.GROTTO)])
	var exits := 0
	for hall in data.halls:
		if (hall.is_main() and hall.exits.size() < 2) or (not hall.is_main() and hall.exits.size() != 1):
			exits += 1
	_check(exits == 0, context + "%d halls with too few ways out (or a grotto with more than one)" % exits)
	_check(data.passages.size() - data.halls.size() + 1 >= 3, context + "fewer than three loops")
	var start := data.hall_at(data.spawn_position)
	_check(start >= 0 and data.halls[start].zone == Zone.SUNNY and data.is_snow(data.spawn_position)
		and data.cold_at(data.spawn_position) == 0.0 and data.has_clearance(data.spawn_position, BODY + 20.0),
		context + "the start is not on clear snow in a sunny hall")
	var geysers := 0
	for geyser in data.geysers:
		var hall := data.halls[geyser.hall]
		if hall.zone != Zone.COLD or hall.shape.signed_distance(geyser.position) < geyser.mouth:
			geysers += 1
	_check(geysers == 0 and not data.geysers.is_empty(), context + "geysers outside the cold halls (or none)")
	var astray := 0
	for thing in data.things:
		var on_snow := data.is_snow(thing.position)
		if thing.kind in [Kind.PINE, Kind.DEAD_TREE, Kind.DRIFT, Kind.DRY_GRASS, Kind.SHRUB] and not on_snow:
			astray += 1
		if data.wall_depth(thing.position) > -2.0 or data.chasm_sample(thing.position).x > 0.0 \
				or data.water_depth(thing.position) > 0.0 or data.crevasse_sample(thing.position).x > 0.0:
			astray += 1
		if thing.kind != Kind.ICE_BLOCK and data.lake_depth(thing.position) > 0.0:
			astray += 1
		if thing.kind == Kind.ICE_BLOCK and data.lake_depth(thing.position) > 0.0 \
				and data.pools[data.lake_at(thing.position)] != Pool.FROZEN:
			astray += 1
	_check(astray == 0, context + "%d things out of place (snow things off the snow, or in the ice or a drop)" % astray)
	# Snow lies only round the sunny spots.
	var stray_snow := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = data.world_seed
	for i in 600:
		var point := data.bounds.position + Vector2(rng.randf(), rng.randf()) * data.bounds.size
		if not data.is_snow(point):
			continue
		var near := false
		for skylight in data.skylights:
			if skylight.spot.signed_distance(point) > -(skylight.reach + 260.0):
				near = true
		if not near:
			stray_snow += 1
	_check(stray_snow == 0, context + "snow away from the sun")
	var walled := 0
	for creature in data.frozen:
		if creature.lake >= data.lakes.size():
			var depth := data.wall_depth(creature.position)
			if depth < 30.0 or depth > 240.0:
				walled += 1
		elif data.lakes[creature.lake].shape.signed_distance(creature.position) < creature.radius:
			walled += 1
	_check(walled == 0, context + "%d creatures not where they can be seen (in a wall or under the ice)" % walled)
	var floating := 0
	for floater in data.floaters:
		if data.pools[floater.lake] != Pool.OPEN or data.water_depth(floater.position) < floater.radius:
			floating += 1
	_check(floating == 0, context + "%d bodies off the open water" % floating)
	_check(data.pool_count(Pool.FROZEN) >= 1 and data.pool_count(Pool.MELT) + data.pool_count(Pool.OPEN) >= 1,
		context + "lakes: %d frozen, %d melting, %d open" % [data.pool_count(Pool.FROZEN), data.pool_count(Pool.MELT),
		data.pool_count(Pool.OPEN)])
	_check(not data.chasms.is_empty() and data.arch_count() >= 1, context + "no chasm with an arch")


func _fingerprint(data: NelvarCaveData) -> int:
	var parts: Array = [data.spawn_position, hash(data.sdf), data.passages.size()]
	for hall in data.halls:
		parts.append([hall.shape.center, hall.shape.axes, hall.zone])
	for chasm in data.chasms:
		parts.append([chasm.points, chasm.arches.size()])
	for lake in data.lakes:
		parts.append([lake.shape.center, lake.shape.axes])
	for creature in data.frozen:
		parts.append([creature.position, creature.variant, creature.eye])
	for thing in data.things:
		parts.append([thing.kind, thing.variant, thing.position, thing.radius, thing.appearance_seed])
	return hash(parts)


## From the start every hall can be walked to over the floor (arches and bridges are
## floor; chasms, crevasses, water and melting ice are not), and the floor shrunk by a
## hopper's width (26) still holds together.
func _check_reach(data: NelvarCaveData) -> void:
	var context := "Seed %d: " % data.world_seed
	var walk := func(point: Vector2) -> bool:
		return data.has_clearance(point, BODY) and data.melt_depth(point) < 0.0
	var seen := _flood(data, 20.0, walk)
	var missing := 0
	for hall in data.halls:
		if not _hall_reached(data, hall, seen, 20.0):
			missing += 1
	_check(missing == 0, context + "%d halls cannot be walked to" % missing)
	var wide := func(point: Vector2) -> bool: return data.wall_depth(point) < -26.0
	var wide_seen := _flood(data, 16.0, wide)
	var narrow := 0
	for hall in data.halls:
		if not _hall_reached(data, hall, wide_seen, 16.0):
			narrow += 1
	_check(narrow == 0, context + "%d halls only through ways narrower than a hopper" % narrow)


func _flood(data: NelvarCaveData, cell: float, open: Callable) -> Dictionary:
	var start := Vector2i((data.spawn_position / cell).floor())
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		var at := queue[i]
		i += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := at + step
			if seen.has(next):
				continue
			var point := (Vector2(next) + Vector2(0.5, 0.5)) * cell
			if not data.bounds.has_point(point) or not open.call(point):
				continue
			seen[next] = true
			queue.append(next)
	return seen


func _hall_reached(data: NelvarCaveData, hall: NelvarCaveData.Hall, seen: Dictionary, cell: float) -> bool:
	var center := Vector2i((hall.shape.center / cell).floor())
	var reach := int(minf(hall.shape.axes.x, hall.shape.axes.y) * 0.8 / cell)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if seen.has(center + Vector2i(dx, dy)):
				return true
	return false


## Over every south face the wall stands at least FACE + FACE_SPARE art pixels.
func _check_faces(data: NelvarCaveData) -> void:
	var thin := 0
	var faces := 0
	var least := (NelvarCaveData.FACE + NelvarCaveData.FACE_SPARE) * PIXEL
	var rng := RandomNumberGenerator.new()
	rng.seed = data.world_seed + 3
	for i in 20000:
		var point := ((data.bounds.position + Vector2(rng.randf(), rng.randf()) * data.bounds.size) / PIXEL).floor() * PIXEL \
			+ Vector2.ONE * PIXEL * 0.5
		# The foot of a face: the ice plainly begins right above (not a corner of it).
		if data.wall_depth(point) > 0.0 or data.wall_depth(point - Vector2(0.0, PIXEL)) <= 0.0 \
				or data.wall_depth(point - Vector2(0.0, PIXEL * 2.0)) <= 4.0:
			continue
		faces += 1
		# One art pixel of slack: the bilinear edge.
		for k in range(2, int(least / PIXEL) + 1):
			if data.wall_depth(point - Vector2(0.0, k * PIXEL)) <= 0.0:
				thin += 1
				break
	_check(faces > 20 and thin == 0, "Seed %d: %d of %d south faces under too thin a wall" % [data.world_seed, thin, faces])


## The collision, the queries and the shader's field see one boundary.
func _check_walls(data: NelvarCaveData) -> void:
	var chunks := NelvarCaveWalls.segments(data)
	var worst := 0.0
	var count := 0
	for key: Vector2i in chunks:
		var list: PackedVector2Array = chunks[key]
		for i in range(0, list.size(), 2):
			var middle := (list[i] + list[i + 1]) * 0.5
			worst = maxf(worst, absf(data.wall_depth(middle)))
			worst = maxf(worst, absf(data.wall_depth(list[i])))
			count += 1
	_check(count > 1000 and worst <= PIXEL, "The collision strays %.1f from the walls' zero line (%d segments)" % [worst, count])
	var image := NelvarCaveField.sdf_texture(data).get_image()
	var differ := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2000:
		var x := rng.randi_range(0, data.sdf_size.x - 1)
		var y := rng.randi_range(0, data.sdf_size.y - 1)
		if not is_equal_approx(image.get_pixel(x, y).r, data.sdf[y * data.sdf_size.x + x]):
			differ += 1
	_check(differ == 0, "The shader's wall field differs from the walls at %d samples" % differ)


## The floor's maps say what the queries say (away from the edges by a pixel or two).
func _check_field(data: NelvarCaveData) -> void:
	var field := NelvarCaveField.build(data)
	var at := func(bytes: PackedByteArray, point: Vector2, channel: int) -> int:
		var p := Vector2i((point / PIXEL).floor()) - field.origin
		return bytes[(p.y * field.size.x + p.x) * 4 + channel]
	var wrong := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = data.world_seed + 11
	var tested := 0
	for i in 40000:
		var point := ((data.bounds.position + Vector2(rng.randf(), rng.randf()) * data.bounds.size * 0.98 + Vector2.ONE * 20.0)
			/ PIXEL).floor() * PIXEL + Vector2.ONE * PIXEL * 0.5
		if data.wall_depth(point) > -2.0:
			continue
		tested += 1
		var lake := data.lake_depth(point)
		if absf(lake) > 6.0 and (at.call(field.field, point, 0) > 128) != (lake > 0.0):
			wrong["lake"] = wrong.get("lake", 0) + 1
		var chasm := data.chasm_sample(point).x
		if absf(chasm) > 6.0 and (at.call(field.zone, point, 0) > 128) != (chasm > 0.0):
			wrong["chasm"] = wrong.get("chasm", 0) + 1
		var crack := data.crevasse_sample(point).x
		if absf(crack) > 6.0 and (at.call(field.field, point, 2) > 128) != (crack > 0.0):
			wrong["crevasse"] = wrong.get("crevasse", 0) + 1
		var snow := data.snow_depth(point)
		if absf(snow) > 3.0 and (at.call(field.field, point, 1) >> 3 > 0) != (snow > 0.0):
			wrong["snow"] = wrong.get("snow", 0) + 1
		if (at.call(field.field, point, 1) & 4 != 0) != data.icy_at(point):
			var near := data.passage_near(point)
			if near.x < 0 or absf(data.passages[int(near.x)].half_width_at(near.z) + NelvarCaveData.ICY_SPARE - near.y) > 6.0:
				wrong["icy"] = wrong.get("icy", 0) + 1
	var light := 0
	for i in 1500:
		var x := rng.randi_range(0, field.light_size.x - 1)
		var y := rng.randi_range(0, field.light_size.y - 1)
		var point := (Vector2(field.light_origin) + (Vector2(x, y) + Vector2(0.5, 0.5)) * NelvarCaveField.LIGHT_SCALE) * PIXEL
		var index := (y * field.light_size.x + x) * 4
		if absi(field.light[index] - roundi(data.sun_at(point) * 255.0)) > 1 \
				or absi(field.light[index + 2] - roundi(data.warmth_at(point) * 255.0)) > 1 \
				or absi(field.light[index + 3] - roundi(data.cold_at(point) * 255.0)) > 1:
			light += 1
	_check(tested > 5000 and wrong.is_empty(), "The floor map disagrees with the queries: %s" % wrong)
	_check(light == 0, "The light map disagrees with sun_at, warmth_at or cold_at at %d texels" % light)


# --- Art -----------------------------------------------------------------------------------

func _check_art(data: NelvarCaveData) -> void:
	var painter := NelvarCavePainter.new()
	var seen := {}
	var broken: Array[String] = []
	for thing in data.things:
		var key := "%d:%d" % [thing.kind, thing.variant]
		if seen.has(key):
			continue
		seen[key] = true
		var art := painter.paint(thing)
		var name: String = Kind.keys()[thing.kind]
		if art == null or art.image == null or art.image.is_invisible():
			broken.append(name)
			continue
		if art.image.get_data() != painter.paint(thing).image.get_data():
			broken.append(name + " (not reproducible)")
		var grid: Vector2 = (thing.position + art.local_rect.position) / PIXEL
		if not grid.is_equal_approx(grid.round()):
			broken.append(name + " (off the grid)")
		if thing.kind == Kind.EMBEDDED and thing.variant == NelvarCaveData.Part.HEAD and not art.eye.is_finite():
			broken.append("EMBEDDED head (no eye)")
	var kinds := {}
	for key: String in seen:
		kinds[int(key.split(":")[0])] = true
	for kind in [Kind.CRYSTAL, Kind.ICE_STONE, Kind.STALAGMITE, Kind.BONES, Kind.EMBEDDED, Kind.VENT, Kind.ROCK, Kind.PINE]:
		if not kinds.has(kind):
			broken.append("no %s at all" % Kind.keys()[kind])
	# Every creature, every crystal look, the bodies on the water.
	for variant in NelvarIceData.Creature.size():
		var creature := NelvarIceData.Frozen.new()
		creature.radius = 50.0
		creature.variant = variant
		creature.appearance_seed = 99 + variant
		var art := painter.paint_frozen(creature)
		if art == null or art.image.is_invisible() or not art.eye.is_finite():
			broken.append("creature %d" % variant)
	for variant in NelvarCaveData.Crystal.size():
		for tint in NelvarCaveData.Tint.size():
			var crystal := NelvarIceData.Thing.new()
			crystal.kind = Kind.CRYSTAL
			crystal.variant = variant
			crystal.radius = 20.0
			crystal.size = Vector2(tint, tint % 2)
			crystal.appearance_seed = variant * 7 + tint
			var art := painter.paint(crystal)
			if art == null or art.image.is_invisible():
				broken.append("crystal %d/%d" % [variant, tint])
	for floater in data.floaters.slice(0, 2):
		var art := painter.paint_floater(floater)
		if art == null or art.image.is_invisible():
			broken.append("floater")
	_check(broken.is_empty(), "Art: %s" % ", ".join(broken))


# --- The start setting -------------------------------------------------------------------

## The start options exclude each other; «Играть» opens the cave when its option is on.
func _check_settings() -> void:
	var settings: Node = root.get_node("GameSettings")
	var path: String = settings.PATH
	var saved := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var flags := ["start_in_void", "start_on_earth", "start_on_earth2", "start_in_fire", "start_on_ice", "start_in_fire2",
		"start_on_ice2"]
	var was := []
	for flag in flags:
		was.append(settings.get(flag))
	var clashes := 0
	for i in flags.size():
		settings.call("set_" + flags[i], true)
		for j in flags.size():
			if bool(settings.get(flags[j])) != (i == j):
				clashes += 1
	settings.set_start_on_ice2(false)
	for flag in flags:
		if settings.get(flag):
			clashes += 1
	_check(clashes == 0, "The start options do not exclude each other (%d clashes)" % clashes)
	for i in flags.size():
		settings.set(flags[i], was[i])
	if saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	var menu := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	_check(menu.contains("res://scenes/ice2.tscn") and menu.contains("GameSettings.start_on_ice2"),
		"«Играть» does not open the cave")
	var panel: Node = load("res://ui/main_menu/settings_panel.tscn").instantiate()
	var check: Node = panel.get_node_or_null("Rows/Body/PageColumn/Scroll/Pages/DevPage/StartOnIce2")
	var rows: Node = panel.get_node("Rows/Body/PageColumn/Scroll/Pages/DevPage")
	_check(check is CheckButton and (check as CheckButton).text == "Запускать игру на Льду"
		and check.get_index() == rows.get_node("StartInFire2").get_index() + 1,
		"The developer menu has no Лёд 2 start right under Огонь 2")
	panel.free()
	var hint := FileAccess.get_file_as_string("res://ui/main_menu/settings_panel.tscn")
	_check(hint.contains("«Играть» откроет ледяную пещеру (Лёд 2)"), "The developer menu does not say «Играть» opens the cave")


# --- The scene -----------------------------------------------------------------------------

func _check_scene() -> void:
	var game = load("res://scenes/ice2.tscn").instantiate()
	game.set_meta("seed_override", 20261126)
	root.add_child(game)
	game.finish_painting()
	# The player's attacks join the current scene.
	current_scene = game
	await physics_frame
	await physics_frame
	var data: NelvarCaveData = game.data
	var player: NelvarPlayer = game.player
	_check(data != null, "The cave scene did not generate")
	if data == null:
		return
	var misplaced := 0
	for enemy in get_nodes_in_group("enemies"):
		if not data.has_clearance(enemy.global_position, 20.0) or enemy.get("ground") != data:
			misplaced += 1
		enemy.queue_free()
	_check(misplaced == 0, "%d hoppers appeared in the ice or a drop, or do not know the cave" % misplaced)
	game.enemy_spawner.set_process(false)
	await physics_frame
	_check(game.thing_nodes.size() == data.things.size() and game.depths.frozen_nodes.size() == data.frozen.size(),
		"Some things or frozen creatures are missing")
	_check(game.ground.transparent and player.sight_mask == NelvarCaveData.WALL_SIGHT_LAYER,
		"The floor is not see-through or the walls do not block sight")
	await _check_walls_hold(game, data, player)
	await _check_melting(game, data, player)
	await _check_falls(game, data, player)
	await _check_sliding(game, data, player)
	await _check_marks(game, data, player)
	await _check_hoppers(game, data)
	await _check_wave(game, data, player)
	await _check_geyser(game, data, player)
	_check_spawner(game, data, player)
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(game.get("_outlines").visible, "F3 does not show the outlines")
	game.queue_free()
	await process_frame


## Walking into a wall, then flying into it: the player stays on the floor.
func _check_walls_hold(game: Node, data: NelvarCaveData, player: NelvarPlayer) -> void:
	var spot := _by_wall(data)
	_check(not spot.is_empty(), "No floor next to a wall to push against")
	if spot.is_empty():
		return
	var from: Vector2 = spot[0]
	var toward: Vector2 = spot[1]
	await _place(player, from)
	var deepest := -INF
	await _push(player, toward, 1.0, true, 50, func() -> bool:
		deepest = maxf(deepest, data.wall_depth(player.global_position))
		return false)
	await _place(player, from)
	player.call("_try_speed_boost")
	_check(player.is_airborne(), "The flight did not start")
	await _push(player, toward, 1.0, true, 50, func() -> bool:
		deepest = maxf(deepest, data.wall_depth(player.global_position))
		return false)
	_check(deepest < -BODY + 6.0, "The player got %.0f into a wall" % (deepest + BODY))
	await create_timer(3.5).timeout


## Floor 80 units from a wall straight ahead: [start, direction].
func _by_wall(data: NelvarCaveData) -> Array:
	for passage in data.passages:
		var along := passage.length() * 0.5
		var center := passage.point_at(along)
		var normal := passage.direction_at(along).orthogonal()
		var half := passage.half_width_at(along)
		if data.wall_depth(center) < -half + 10.0 and data.has_clearance(center, BODY + 4.0) \
				and data.fall_kind(center) == NelvarIceData.Fall.NONE and data.ice_at(center) == NelvarIceData.Surface.STONE:
			return [center, normal]
	return []


## Melting ice: a walk across breaks it and drops the player in; a run gets across whole;
## standing on it breaks it within half a second.
func _check_melting(game: Node, data: NelvarCaveData, player: NelvarPlayer) -> void:
	var lane := _melt_lane(data)
	_check(not lane.is_empty(), "No clear way across melting ice")
	if lane.is_empty():
		return
	var start: Vector2 = lane[0]
	var direction: Vector2 = lane[1]
	var end: Vector2 = lane[2]
	var center: Vector2 = lane[3]
	await _place(player, start)
	var breaks: int = game.breaks
	await _push(player, direction, 1.0, true, 150, func() -> bool:
		return (player.global_position - end).dot(direction) > 0.0 or player.is_falling())
	_check(game.breaks == breaks and not player.is_falling(), "Melting ice gave under a running player")
	await create_timer(1.6).timeout
	await _place(player, start)
	breaks = game.breaks
	var plunges: int = game.plunges
	await _push(player, direction, 1.0, false, 200, func() -> bool:
		return game.plunges > plunges or (player.global_position - end).dot(direction) > 0.0)
	_check(game.breaks > breaks and game.plunges > plunges, "A walker got across the melting ice")
	await create_timer(game.FALL_TIME + 0.6).timeout
	_check(not player.is_falling() and data.lake_depth(player.global_position) < 0.0,
		"The player did not come back off the melting ice")
	data.holes.clear()
	await _place(player, center)
	breaks = game.breaks
	var stood := 0.0
	while game.breaks == breaks and stood < 1.0:
		await physics_frame
		stood += 1.0 / Engine.physics_ticks_per_second
	_check(game.breaks > breaks and stood < 0.55, "Standing on melting ice took %.2f s to break it" % stood)
	await create_timer(game.FALL_TIME + 0.6).timeout
	data.holes.clear()


## A straight way over a melting lake short enough to run (over 0.95 s at a run, more
## than 1 s at a walk): [start, direction, end, a point on the ice].
func _melt_lane(data: NelvarCaveData) -> Array:
	for l in data.lakes.size():
		if data.pools[l] != Pool.MELT:
			continue
		var shape := data.lakes[l].shape
		for k in 16:
			var direction := Vector2.from_angle(TAU * k / 16.0)
			var entry := shape.center - direction * shape.radius_at((-direction).angle())
			var exit := shape.center + direction * shape.radius_at(direction.angle())
			var across := entry.distance_to(exit)
			if across < 330.0 or across > 400.0:
				continue
			var start := entry - direction * 110.0
			var end := exit + direction * 40.0
			var clear := true
			var step := 0.0
			while step < start.distance_to(end):
				var point := start + direction * step
				if not data.has_clearance(point, BODY + 6.0):
					clear = false
					break
				step += 10.0
			if clear:
				return [start, direction, end, shape.center]
	return []


## Open water and a chasm: a step in holds a moment, then the player drops, comes back on
## safe ground, hurt; thin ice of a frozen lake breaks under a standing player.
func _check_falls(game: Node, data: NelvarCaveData, player: NelvarPlayer) -> void:
	for kind in [NelvarIceData.Fall.WATER, NelvarIceData.Fall.CHASM]:
		var spot := _edge_of(data, kind)
		if spot.is_empty():
			_check(kind == NelvarIceData.Fall.WATER and data.pool_count(Pool.OPEN) == 0, "No edge of a drop to step off (%d)" % kind)
			continue
		var start: Vector2 = spot[0]
		var direction: Vector2 = spot[1]
		await _place(player, start)
		await _place(player, start)
		player.health = player.max_health
		player.set("_invulnerability_left", 0.0)
		var before: int = game.falls + game.plunges
		await _push(player, direction, 1.0, false, 120, func() -> bool: return player.is_falling())
		_check(player.is_falling(), "Stepping off into a drop (%d) did not drop the player" % kind)
		await create_timer(game.FALL_TIME + 0.6).timeout
		_check(game.falls + game.plunges == before + 1 and not player.is_falling() and player.health < player.max_health
			and data.is_safe_spot(player.global_position), "The player did not come back hurt on safe ground (%d)" % kind)
	# A narrow place of a chasm is crossed at a run.
	var narrow := _narrow_spot(data)
	_check(not narrow.is_empty(), "No narrow place of a chasm to run over")
	if not narrow.is_empty():
		var before: int = game.falls
		await _place(player, narrow[0])
		await _push(player, narrow[1], 1.0, true, 60, func() -> bool:
			return (player.global_position - (narrow[2] as Vector2)).dot(narrow[1]) > 0.0 or player.is_falling())
		_check(game.falls == before and not player.is_falling(), "A run did not get over a narrow place of a chasm")
		await create_timer(game.FALL_TIME + 0.6).timeout
	var patch: NelvarEarthData.Radial = null
	for l in data.lakes.size():
		for candidate in data.lakes[l].thin:
			if data.thin_depth(candidate.center) > 20.0 and data.has_clearance(candidate.center, BODY + 6.0):
				patch = candidate
	if patch != null:
		await _place(player, patch.center)
		var holes: int = game.holes_broken
		for i in 120:
			await physics_frame
			if game.holes_broken > holes:
				break
		_check(game.holes_broken > holes, "Thin ice held a standing player")
		await create_timer(game.FALL_TIME + 0.8).timeout
		data.holes.clear()


## Ground just before a drop of `kind` (open water, a chasm away from its arches):
## [start, direction] (empty if none).
func _edge_of(data: NelvarCaveData, kind: int) -> Array:
	var tries: Array[Array] = []
	if kind == NelvarIceData.Fall.WATER:
		for l in data.lakes.size():
			if data.pools[l] != Pool.OPEN:
				continue
			var shape := data.lakes[l].shape
			for k in 16:
				var out := Vector2.from_angle(TAU * k / 16.0)
				tries.append([shape.point_at(out.angle(), -60.0), -out])
	else:
		for chasm in data.chasms:
			for leap in chasm.leaps:
				var normal := _across(chasm, Vector2(leap.x, leap.y))
				for side: float in [-1.0, 1.0]:
					tries.append([Vector2(leap.x, leap.y) + normal * side * (leap.z * 0.5 + 70.0), -normal * side])
			for t in [0.3, 0.4, 0.5, 0.6, 0.7]:
				var along: float = chasm.length() * t
				var normal := chasm.direction_at(along).orthogonal()
				for side: float in [-1.0, 1.0]:
					tries.append([chasm.point_at(along) + normal * side * (chasm.half_width_at(along) + 60.0), -normal * side])
	for entry in tries:
		var start: Vector2 = entry[0]
		var direction: Vector2 = entry[1]
		if not data.is_safe_spot(start) or not data.has_clearance(start, BODY + 4.0) or data.wall_depth(start) > -40.0:
			continue
		var clear := true
		var reached := false
		for step in range(0, 200, 8):
			var at := start + direction * step
			if data.fall_kind(at, 8.0) == kind:
				reached = data.arch_at(at) == null
				break
			if data.wall_depth(at) > -(BODY + 2.0):
				clear = false
				break
		if clear and reached:
			return [start, direction]
	return []


## A narrow place of a chasm (NelvarCaveData.LEAP_RUN or less) on open floor:
## [start, direction, end].
func _narrow_spot(data: NelvarCaveData) -> Array:
	for chasm in data.chasms:
		for leap in chasm.leaps:
			if leap.z > NelvarCaveData.LEAP_RUN:
				continue
			var point := Vector2(leap.x, leap.y)
			var half := leap.z * 0.5
			var normal := _across(chasm, point)
			var start := point - normal * (half + 90.0)
			var end := point + normal * (half + 30.0)
			var clear := true
			var step := 0.0
			while step < start.distance_to(end):
				var at := start + normal * step
				step += 6.0
				if data.chasm_sample(at).x > 0.0 and absf((at - point).dot(normal)) > half * 1.6 + 4.0:
					clear = false
				if data.wall_depth(at) > -(BODY + 2.0):
					clear = false
				if data.arch_at(at) != null or data.ice_at(at) != NelvarIceData.Surface.STONE and data.ice_at(at) != NelvarIceData.Surface.SNOW:
					clear = false
			if clear and data.is_safe_spot(start):
				return [start, normal, end]
	return []


## The direction across a chasm at a point of it.
func _across(chasm: NelvarCaveData.Chasm, point: Vector2) -> Vector2:
	var near := Vector2(INF, 0.0)
	for i in chasm.points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(point, chasm.points[i], chasm.points[i + 1])
		if closest.distance_to(point) < near.x:
			near = Vector2(closest.distance_to(point), chasm.lengths[i] + chasm.points[i].distance_to(closest))
	return chasm.direction_at(near.y).orthogonal()


## On the smooth ice of an icy passage the player slides much further than on stone.
func _check_sliding(game: Node, data: NelvarCaveData, player: NelvarPlayer) -> void:
	var icy := Vector2.INF
	var direction := Vector2.RIGHT
	for passage in data.passages:
		if not passage.icy:
			continue
		for t in [0.5, 0.4, 0.6]:
			var along: float = passage.length() * t
			var point := passage.point_at(along)
			var forward := passage.direction_at(along)
			if data.icy_at(point) and data.icy_at(point + forward * 120.0) and data.has_clearance(point + forward * 120.0, BODY):
				icy = point
				direction = forward
				break
		if icy.is_finite():
			break
	_check(icy.is_finite(), "No icy passage to slide along")
	if not icy.is_finite():
		return
	var on_ice := await _coast(player, icy, direction)
	var stone: Array = _by_wall(data)
	var on_stone := await _coast(player, stone[0], (stone[1] as Vector2).orthogonal())
	_check(on_ice > on_stone * 3.0 and on_ice > 90.0, "The player slid %.0f on ice and %.0f on stone" % [on_ice, on_stone])


func _coast(player: NelvarPlayer, from: Vector2, direction: Vector2) -> float:
	await _place(player, from)
	player.velocity = direction * player.speed
	for i in 80:
		await physics_frame
	return player.global_position.distance_to(from)


## Walking over snow leaves marks; walking over stone does not.
func _check_marks(game: Node, data: NelvarCaveData, player: NelvarPlayer) -> void:
	var marks: NelvarSnowMarks = game.snow_marks
	await _place(player, data.spawn_position)
	var stamps := marks.stamps
	await _push(player, _free_direction(data, data.spawn_position, 120.0, true), 1.0, false, 30, func() -> bool: return false)
	_check(marks.stamps > stamps + 5 and marks.fresh_near(player.global_position, 60.0) > 0, "Walking over snow left no marks")
	var stone: Array = _by_wall(data)
	await _place(player, stone[0])
	stamps = marks.stamps
	await _push(player, (stone[1] as Vector2).orthogonal(), 1.0, false, 20, func() -> bool: return false)
	_check(marks.stamps == stamps, "Walking over stone left marks")


func _free_direction(data: NelvarCaveData, from: Vector2, length: float, snow: bool) -> Vector2:
	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		var free := true
		for step in int(length / 10.0) + 1:
			var point := from + direction * step * 10.0
			if not data.has_clearance(point, BODY + 6.0) or (snow and not data.is_snow(point)):
				free = false
				break
		if free:
			return direction
	return Vector2.RIGHT


## Hoppers blown into a chasm or open water die.
func _check_hoppers(game: Node, data: NelvarCaveData) -> void:
	for kind in [NelvarIceData.Fall.CHASM, NelvarIceData.Fall.WATER]:
		var spot := _edge_of(data, kind)
		if spot.is_empty():
			continue
		var hopper := await _hopper(game, spot[0])
		hopper.call("apply_knockback", (spot[1] as Vector2) * 900.0)
		await create_timer(0.8).timeout
		_check(not is_instance_valid(hopper) or hopper.call("is_dead"), "A hopper blown into a drop (%d) lived" % kind)


func _hopper(game: Node, point: Vector2) -> Node2D:
	var hopper: Node2D = game.enemy_spawner.enemy_scene.instantiate()
	hopper.position = point
	hopper.set("ground", game.data)
	hopper.set("idle_time_min", 30.0)
	hopper.set("idle_time_max", 30.0)
	game.enemy_spawner.add_child(hopper)
	await physics_frame
	return hopper


## The wind wave stops at a wall: a hopper on the far side of one is untouched; one in
## the open the same way off is hit.
func _check_wave(game: Node, data: NelvarCaveData, player: NelvarPlayer) -> void:
	var across := _wall_between(data)
	_check(not across.is_empty(), "No wall with floor on both sides to test the wave")
	if across.is_empty():
		return
	await _place(player, across[0])
	var hidden := await _hopper(game, across[1])
	var health: float = hidden.get("health")
	player.aim_direction = (across[0] as Vector2).direction_to(across[1])
	player.set("_wave_cooldown_left", 0.0)
	player.call("_try_wave_attack")
	await create_timer(0.8).timeout
	_check(is_instance_valid(hidden) and is_equal_approx(hidden.get("health"), health), "The wave reached a hopper behind a wall")
	if is_instance_valid(hidden):
		hidden.queue_free()
	var open := _free_direction(data, data.spawn_position, 170.0, false)
	await _place(player, data.spawn_position)
	var seen := await _hopper(game, data.spawn_position + open * 150.0)
	health = seen.get("health")
	player.aim_direction = open
	player.set("_wave_cooldown_left", 0.0)
	player.call("_try_wave_attack")
	await create_timer(0.8).timeout
	_check(not is_instance_valid(seen) or seen.get("health") < health, "The wave missed a hopper in the open")
	if is_instance_valid(seen):
		seen.queue_free()


## Two floor points 120–220 apart with ice between them: [player side, hopper side].
func _wall_between(data: NelvarCaveData) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for attempt in 6000:
		var point := data.bounds.position + Vector2(rng.randf(), rng.randf()) * data.bounds.size
		var depth := data.wall_depth(point)
		if depth < 20.0 or depth > 110.0:
			continue
		for k in 8:
			var direction := Vector2.from_angle(TAU * k / 8.0)
			for reach in [depth + 40.0, depth + 60.0]:
				var a: Vector2 = point - direction * reach
				var b: Vector2 = point + direction * reach
				if data.has_clearance(a, 26.0) and data.has_clearance(b, 26.0) and data.fall_kind(a) == 0 \
						and data.fall_kind(b) == 0 and a.distance_to(b) < 300.0 and data.melt_depth(a) < 0.0 \
						and data.melt_depth(b) < 0.0 and data.lake_depth(a) < 0.0 and data.lake_depth(b) < 0.0:
					return [a, b]
	return []


## An eruption throws a hopper away from the mouth; the player beside it is not hurt or
## moved.
func _check_geyser(game: Node, data: NelvarCaveData, player: NelvarPlayer) -> void:
	_check(not data.geysers.is_empty(), "No geyser")
	if data.geysers.is_empty():
		return
	var geyser := data.geysers[0]
	var side := Vector2.ZERO
	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		if data.has_clearance(geyser.position + direction * 70.0, BODY + 4.0) \
				and data.has_clearance(geyser.position - direction * 70.0, 26.0):
			side = direction
			break
	_check(side != Vector2.ZERO, "No room round a geyser")
	if side == Vector2.ZERO:
		return
	var stand := geyser.position + side * 70.0
	await _place(player, stand)
	player.health = player.max_health
	player.set("_invulnerability_left", 0.0)
	var hopper := await _hopper(game, geyser.position - side * 70.0)
	var from := hopper.global_position
	# Just before the eruption.
	game.clock = geyser.period - geyser.offset - geyser.ERUPT - 0.05
	for i in 30:
		player.global_position = stand
		player.velocity = Vector2.ZERO
		await physics_frame
	_check(game.eruptions > 0, "The geyser did not erupt")
	_check(not is_instance_valid(hopper) or hopper.global_position.distance_to(geyser.position)
		> from.distance_to(geyser.position) + 40.0, "The eruption did not throw the hopper back")
	_check(is_equal_approx(player.health, player.max_health) and player.global_position.distance_to(stand) < 2.0,
		"The eruption hurt or moved the player")
	if is_instance_valid(hopper):
		hopper.queue_free()


## The spawner only picks points close by on foot.
func _check_spawner(game: Node, data: NelvarCaveData, player: NelvarPlayer) -> void:
	player.global_position = data.spawn_position
	data.path_origin = data.spawn_position
	var picked := 0
	var far := 0
	for i in 60:
		var point: Variant = game.enemy_spawner.call("_pick_world_spawn_point")
		if point == null:
			continue
		picked += 1
		var walk := data.path_distance(point)
		if walk > (point as Vector2).distance_to(data.spawn_position) * 1.6 + 1.0:
			far += 1
	_check(picked > 10 and far == 0, "The spawner picked %d points behind walls (of %d)" % [far, picked])


func _place(player: NelvarPlayer, point: Vector2) -> void:
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)
	player.global_position = point
	player.velocity = Vector2.ZERO
	for i in 4:
		await physics_frame
		player.global_position = point
		player.velocity = Vector2.ZERO
	await physics_frame


func _push(player: NelvarPlayer, direction: Vector2, strength: float, run: bool, frames: int, done: Callable) -> void:
	var d := direction.normalized() * strength
	var amounts := {"move_right": d.x, "move_left": -d.x, "move_down": d.y, "move_up": -d.y}
	for name: String in amounts:
		var amount: float = amounts[name]
		if amount > 0.001:
			Input.action_press(name, amount)
		else:
			Input.action_release(name)
	for frame in frames:
		if run:
			player.set("_is_running", true)
		await physics_frame
		if done.call():
			break
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 30:
		_failures.append(message)
