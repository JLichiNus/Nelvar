extends SceneTree
## The earth valley: layout rules, reachability, artwork, the ground map, and the
## real scene (walls, water, plants, statues, peaks, enemy spawns, the start setting).
## Run: godot --headless --path . --script tests/test_earth.gd -- --seeds=30

const Kind = NelvarEarthData.Kind

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 30
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	var config := NelvarEarthConfig.new()
	var generator := NelvarEarthGenerator.new()
	var started := Time.get_ticks_msec()
	var reached := 0.0
	for index in count:
		var world_seed := 20261123 + index * 7919
		var data := generator.generate(config, world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		_check_layout(data, config)
		if index < 4:
			_check(_fingerprint(generator.generate(config, world_seed)) == _fingerprint(data),
				"Seed %d: layout is not reproducible" % world_seed)
		if index < 8:
			reached += _check_reachability(data)
		if index == 0:
			_check_art(data)
			_check_field(data)
	print("Earth: %d seeds in %.2f s · %.1f%% of open ground reachable" % [count,
		float(Time.get_ticks_msec() - started) / 1000.0, reached / mini(count, 8) * 100.0])
	_check_settings()
	await _check_scene()
	if _failures.is_empty():
		print("PASS: %d checks; valley layout, reachability, art, walls, water and the scene behave" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


# --- Layout --------------------------------------------------------------------

func _check_layout(data: NelvarEarthData, config: NelvarEarthConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	_check(data.boundary.size() == config.boundary_vertices, context + "the mountain foot is not closed")
	_check(data.has_clearance(data.spawn_position, NelvarPlayer.BODY_RADIUS + 20.0),
		context + "the spawn is blocked")
	_check(data.ponds.size() >= config.pond_count.x and data.ponds.size() <= config.pond_count.y,
		context + "%d ponds" % data.ponds.size())
	for i in data.ponds.size():
		for point in data.pond_polygons[i]:
			_check(data.valley.signed_distance(point) > config.pond_margin * 0.5,
				context + "pond %d touches the mountain foot" % i)
			for j in data.ponds.size():
				if j != i:
					_check(data.ponds[j].signed_distance(point) < -config.pond_gap * 0.5,
						context + "ponds %d and %d nearly touch" % [i, j])
	_check(data.trails.size() >= data.clearings.size(), context + "too few trails")
	for trail in data.trails:
		for point in trail.points:
			_check(data.pond_depth(point) < -trail.half_width, context + "a trail runs into a pond")
	for clearing in data.clearings:
		_check(data.has_clearance(clearing.center, NelvarPlayer.BODY_RADIUS), context + "a clearing is blocked")
	var species := {}
	var solids: Array[NelvarEarthData.Thing] = []
	for thing in data.things:
		if thing.kind == Kind.PEAK:
			_check(data.valley.signed_distance(thing.position) < 0.0, context + "a peak stands in the valley")
			continue
		if thing.kind == Kind.TREE:
			species[thing.variant] = true
		if thing.kind == Kind.LILY:
			_check(data.pond_depth(thing.position) > thing.radius, context + "a lily lies on dry land")
			continue
		if thing.kind == Kind.REEDS:
			_check(data.pond_depth(thing.position) > 0.0, context + "reeds stand on dry land")
			continue
		_check(data.valley.signed_distance(thing.position) > thing.spread(),
			context + "%s %d stands in the mountains" % [Kind.keys()[thing.kind], thing.id])
		_check(data.pond_depth(thing.position) < -thing.spread() * 0.5,
			context + "%s %d stands in a pond" % [Kind.keys()[thing.kind], thing.id])
		if thing.solid:
			solids.append(thing)
			_check(data.distance_to_trails(thing.position) >= thing.spread() - 0.5,
				context + "%s %d blocks a trail" % [Kind.keys()[thing.kind], thing.id])
			_check(thing.position.distance_to(data.spawn_position) >= config.spawn_clearance,
				context + "something solid stands at the spawn")
	_check(species.size() >= 4, context + "only %d tree species" % species.size())
	_check(data.count(Kind.STATUE) >= config.statues.x, context + "no petrified creatures")
	_check(data.count(Kind.TREE) >= 80, context + "only %d trees" % data.count(Kind.TREE))
	var plants := 0
	for thing in data.things:
		if thing.is_plant():
			plants += 1
	_check(plants >= 200, context + "only %d plants" % plants)
	# Solid things leave a passage wider than the player between them.
	for a in solids.size():
		for b in range(a + 1, solids.size()):
			var first := solids[a]
			var second := solids[b]
			var distance := first.position.distance_to(second.position)
			if distance > 400.0:
				continue
			_check(distance >= first.spread() + second.spread() + NelvarPlayer.BODY_RADIUS * 2.0,
				context + "no passage between %s %d and %s %d" % [Kind.keys()[first.kind], first.id,
					Kind.keys()[second.kind], second.id])
	# The nearest row of peaks rings the valley without gaps.
	var angles: Array[float] = []
	for thing in data.things:
		if thing.kind == Kind.PEAK and thing.row == 0:
			angles.append((thing.position - data.valley.center).angle())
	angles.sort()
	var widest := TAU - (angles[angles.size() - 1] - angles[0])
	for i in angles.size() - 1:
		widest = maxf(widest, angles[i + 1] - angles[i])
	_check(widest < 0.25, context + "a gap of %.2f rad in the mountains" % widest)


## Share of open ground (where the player fits) reachable from the spawn.
func _check_reachability(data: NelvarEarthData) -> float:
	const CELL := 24.0
	var bounds := Rect2(data.boundary[0], Vector2.ZERO)
	for point in data.boundary:
		bounds = bounds.expand(point)
	var origin := bounds.position
	var size := Vector2i((bounds.size / CELL).ceil()) + Vector2i.ONE
	var open := PackedByteArray()
	open.resize(size.x * size.y)
	var total := 0
	for y in size.y:
		for x in size.x:
			if data.has_clearance(origin + Vector2(x + 0.5, y + 0.5) * CELL, NelvarPlayer.BODY_RADIUS):
				open[y * size.x + x] = 1
				total += 1
	var start := Vector2i(((data.spawn_position - origin) / CELL).floor())
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y or seen.has(next):
				continue
			if open[next.y * size.x + next.x] == 1:
				seen[next] = true
				queue.append(next)
	var share := float(queue.size()) / maxf(1.0, total)
	_check(share > 0.97, "Seed %d: only %.1f%% of open ground is reachable" % [data.world_seed, share * 100.0])
	return share


func _fingerprint(data: NelvarEarthData) -> int:
	var parts: Array = [data.spawn_position, data.boundary, data.trails.size()]
	for thing in data.things:
		parts.append([thing.kind, thing.variant, thing.position, thing.radius, thing.size,
			thing.accent, thing.appearance_seed])
	return hash(parts)


# --- Art and the ground map ---------------------------------------------------------

func _check_art(data: NelvarEarthData) -> void:
	var painter := NelvarEarthPainter.new()
	var seen := {}
	var images := {}
	for thing in data.things:
		var key := "%d:%d" % [thing.kind, thing.variant if thing.kind != Kind.PEAK else thing.row]
		if seen.get(key, 0) >= 2:
			continue
		seen[key] = seen.get(key, 0) + 1
		var art := painter.paint(thing)
		var name: String = Kind.keys()[thing.kind]
		_check(art != null and art.image != null and not art.image.is_invisible(), name + " has no art")
		if art == null:
			continue
		_check(art.image.get_data() == painter.paint(thing).image.get_data(), name + " art is not reproducible")
		var grid: Vector2 = (thing.position + art.local_rect.position) / NelvarEarthData.PIXEL
		_check(grid.is_equal_approx(grid.round()), name + " art is off the world grid")
		images[hash(art.image.get_data())] = true
		if thing.kind == Kind.STATUE:
			_check(art.eye.is_finite() and art.local_rect.has_point(art.eye * NelvarEarthData.PIXEL),
				"The statue's eye is off its art")
	_check(images.size() == _sum(seen), "Two things share identical art")
	for species in NelvarEarthData.Species.size():
		var tree := NelvarEarthData.Thing.new()
		tree.kind = Kind.TREE
		tree.variant = species
		tree.radius = 16.0
		tree.size = Vector2(60.0, 180.0)
		tree.appearance_seed = 99 + species
		_check(not painter.paint(tree).image.is_invisible(), "Species %d has no art" % species)


func _sum(counts: Dictionary) -> int:
	var total := 0
	for value: int in counts.values():
		total += value
	return total


func _check_field(data: NelvarEarthData) -> void:
	var field := NelvarEarthField.build(data)
	var at := func(point: Vector2, channel: int) -> int:
		var p := Vector2i((point / NelvarEarthData.PIXEL).floor()) - field.origin
		return field.data[(p.y * field.size.x + p.x) * 4 + channel]
	for pond in data.ponds:
		_check(at.call(pond.center, 0) > 140, "The ground map has no water in a pond")
		_check(at.call(pond.point_at(0.0, -60.0), 0) < 128, "The ground map floods a pond's shore")
	for trail in data.trails:
		var middle := trail.points[trail.points.size() / 2]
		_check(at.call(middle, 1) < 20, "The ground map misses a trail")
	_check(at.call(data.spawn_position + Vector2(0.0, 200.0), 1) > 0, "The ground map is all trail")


# --- The start setting -------------------------------------------------------------

## The two start options exclude each other. The player's saved settings are put
## back exactly as they were.
func _check_settings() -> void:
	var settings: Node = root.get_node("GameSettings")
	var path: String = settings.PATH
	var saved := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var was_void: bool = settings.start_in_void
	var was_earth: bool = settings.start_on_earth
	settings.set_start_in_void(true)
	settings.set_start_on_earth(true)
	_check(settings.start_on_earth and not settings.start_in_void, "Earth did not replace the Void at start")
	settings.set_start_in_void(true)
	_check(settings.start_in_void and not settings.start_on_earth, "The Void did not replace the earth at start")
	settings.start_in_void = was_void
	settings.start_on_earth = was_earth
	if saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()


# --- The scene ---------------------------------------------------------------------

func _check_scene() -> void:
	var game = load("res://scenes/earth.tscn").instantiate()
	game.set_meta("seed_override", 20261123)
	root.add_child(game)
	await physics_frame
	await physics_frame
	for enemy in get_nodes_in_group("enemies"):
		_check(game.data.has_clearance(enemy.global_position, 20.0), "An enemy appeared in a wall or the water")
		enemy.queue_free()
	game.enemy_spawner.set_process(false)
	var data: NelvarEarthData = game.data
	var player: NelvarPlayer = game.player
	_check(player.collision_mask & NelvarEarthData.WATER_LAYER != 0, "The player does not collide with water")
	for i in 40:
		var point: Variant = game.enemy_spawner.call("_pick_spawn_point")
		if point != null:
			_check(data.has_clearance(point, 20.0), "The spawner picked blocked ground")
	# The mountain foot stops the player.
	var angle := -PI * 0.5
	var start := data.valley.point_at(angle, 90.0)
	if data.has_clearance(start, NelvarPlayer.BODY_RADIUS + 4.0):
		player.position = start
		player.velocity = Vector2.ZERO
		await _hold(Vector2.UP, 60)
		_check(data.valley.signed_distance(player.position) > NelvarPlayer.BODY_RADIUS - 3.0,
			"The player walked into the mountains")
	# A pond stops the player but not a wind projectile.
	var pond := data.ponds[0]
	var shore := pond.point_at(PI * 0.5, -40.0)
	player.position = shore
	player.velocity = Vector2.ZERO
	await _hold(Vector2.UP, 50)
	_check(data.pond_depth(player.position) < -NelvarPlayer.BODY_RADIUS + 3.0, "The player waded into a pond")
	var shot: Node2D = player.projectile_scene.instantiate()
	game.add_child(shot)
	shot.call("launch", shore, Vector2.UP)
	for i in 30:
		await physics_frame
	_check(is_instance_valid(shot) and shot.global_position.y < pond.center.y - pond.axes.y * 0.5,
		"A projectile stopped at the water's edge")
	# Trunks stop the player; tall grass does not.
	var tree := _open_thing(game, Kind.TREE)
	_check(tree != null, "No tree with open ground beside it")
	if tree != null:
		player.position = tree.position - Vector2(tree.thing.radius + 50.0, 0.0)
		player.velocity = Vector2.ZERO
		await _hold(Vector2.RIGHT, 50)
		_check(player.position.x < tree.position.x - tree.thing.radius, "The player walked through a trunk")
	var grass := _open_thing(game, Kind.TALL_GRASS)
	_check(grass != null, "No tall grass with open ground beside it")
	if grass != null:
		player.position = grass.position - Vector2(grass.thing.radius + 40.0, 0.0)
		player.velocity = Vector2.ZERO
		await _hold(Vector2.RIGHT, 40)
		_check(player.position.x > grass.position.x + grass.thing.radius, "Tall grass stopped the player")
	# A petrified creature opens its eye while the player is near, and closes it after.
	var statue: NelvarEarthThing = null
	for node in game.thing_nodes:
		if node.thing.kind == Kind.STATUE:
			statue = node
	_check(statue != null, "No statue in the scene")
	if statue != null:
		player.position = statue.position + Vector2(0.0, 160.0)
		await create_timer(0.6).timeout
		_check(statue.is_eye_open(), "The statue did not open its eye")
		player.position = statue.position + Vector2(0.0, 900.0)
		await create_timer(0.6).timeout
		_check(not statue.is_eye_open(), "The statue did not close its eye")
	# Plants sway with the wind; the peaks all rise.
	var leaned := false
	var waited := Time.get_ticks_msec()
	while Time.get_ticks_msec() - waited < 20000:
		await process_frame
		for node in game.thing_nodes:
			if node.lean != 0:
				leaned = true
		if leaned and game.peaks_finished():
			break
	_check(game.peaks_finished(), "The peaks were not painted")
	_check(game.peak_nodes.size() == data.count(Kind.PEAK), "Some peaks are missing")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(tree == null or tree.show_collision, "F3 does not show colliders")
	game.queue_free()
	await process_frame


## A node of this kind with free ground on both sides of it horizontally.
func _open_thing(game, kind: Kind) -> NelvarEarthThing:
	for node: NelvarEarthThing in game.thing_nodes:
		if node.thing.kind != kind:
			continue
		var clear := true
		var reach := node.thing.radius + 60.0
		for offset in range(-int(reach), int(reach) + 1, 6):
			var sample := node.position + Vector2(offset, 0.0)
			if absf(offset) > node.thing.spread() + NelvarPlayer.BODY_RADIUS + 2.0 \
					and not game.data.has_clearance(sample, NelvarPlayer.BODY_RADIUS + 2.0):
				clear = false
				break
		if clear:
			return node
	return null


func _hold(direction: Vector2, frames: int) -> void:
	var action := "move_right"
	if direction == Vector2.LEFT:
		action = "move_left"
	elif direction == Vector2.UP:
		action = "move_up"
	elif direction == Vector2.DOWN:
		action = "move_down"
	Input.action_press(action)
	for frame in frames:
		await physics_frame
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 30:
		_failures.append(message)
