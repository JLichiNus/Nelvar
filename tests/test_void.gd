extends SceneTree
## Run: godot --headless --path . --script tests/test_void.gd -- --seeds=50

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 50
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	_check_reach_constants()
	var generator := NelvarVoidGenerator.new()
	var started := Time.get_ticks_msec()
	var stats := Vector4i.ZERO
	var monolith_fingerprint := ""
	for index in count:
		var world_seed := index * 7919 - 20261123
		if index == 0:
			world_seed = 0
		var data := generator.generate(world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		_check_void(data)
		var fingerprint := str(data.monolith.world_polygon())
		if monolith_fingerprint.is_empty():
			monolith_fingerprint = fingerprint
		_check(fingerprint == monolith_fingerprint, "Seed %d: the monolith changed" % world_seed)
		if index < 5:
			var repeat := generator.generate(world_seed)
			_check(repeat != null and _fingerprint(repeat) == _fingerprint(data),
				"Seed %d: generation is not deterministic" % world_seed)
		stats += Vector4i(data.route.size(), data.debris.size(),
			data.count_gaps(NelvarVoidData.Gap.FLIGHT), data.count_motion(NelvarVoidData.Motion.FERRY))
	print("Void: %d seeds in %.2f s · route %.1f · pieces %.1f · flights %.2f · ferries %.2f" % [
		count, float(Time.get_ticks_msec() - started) / 1000.0, float(stats.x) / count,
		float(stats.y) / count, float(stats.z) / count, float(stats.w) / count])
	await _check_gameplay()
	if _failures.is_empty():
		print("PASS: %d checks, including walking, falling, leaping and the arena" % _checks)
		quit(0)
	else:
		for failure in _failures.slice(0, 30):
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


## Walking must not clear a LEAP, running must; flight covers every FLIGHT gap.
func _check_reach_constants() -> void:
	var tolerance := NelvarVoidData.EDGE_TOLERANCE * 2.0
	var walk := NelvarVoidData.WALK_SPEED * NelvarVoidData.COYOTE_TIME + tolerance
	var run := NelvarVoidData.RUN_SPEED * NelvarVoidData.COYOTE_TIME + tolerance
	_check(NelvarVoidData.STEP_GAP.y < walk - 15.0, "A step is not comfortably walkable")
	_check(NelvarVoidData.LEAP_GAP.x > walk + 5.0, "A leap can be walked over")
	_check(NelvarVoidData.LEAP_GAP.y < run - 5.0, "A leap is out of running reach")
	_check(NelvarVoidData.FLIGHT_GAP.x > run + 50.0, "A flight gap can be run over")
	_check(NelvarVoidData.FLIGHT_GAP.y < NelvarVoidData.RUN_SPEED * 2.0 * 0.6,
		"A flight gap is too wide for one flight")


func _check_void(data: NelvarVoidData) -> void:
	var context := "Seed %d: " % data.world_seed
	_check(data.route.size() >= 8, context + "route is too short (%d)" % data.route.size())
	var spawn := data.support_at(data.spawn_position, 0.0, 0.0)
	_check(spawn != null and spawn.id == data.route[0], context + "spawn is not on the first piece")
	_check(Geometry2D.is_point_in_polygon(data.arena_center, data.monolith.world_polygon()),
		context + "arena centre is off the monolith")
	for obelisk in NelvarVoidData.obelisk_positions():
		_check(NelvarVoidData.distance_to_outline(obelisk, data.monolith.world_polygon())
			> NelvarVoidData.OBELISK_RADIUS + 40.0, context + "an obelisk hangs over the edge")
	# Consecutive route pieces: the gap matches what the crossing is supposed to take.
	for i in data.route.size():
		var piece := data.debris[data.route[i]]
		var here := piece.world_polygon(piece.period * 0.5 if piece.motion
			== NelvarVoidData.Motion.FERRY else 0.0)
		var there := data.monolith.world_polygon()
		if i + 1 < data.route.size():
			there = data.debris[data.route[i + 1]].world_polygon(0.0)
		var gap := NelvarVoidData.polygon_distance(here, there)
		var limits := NelvarVoidData.STEP_GAP
		if piece.gap == NelvarVoidData.Gap.LEAP:
			limits = NelvarVoidData.LEAP_GAP
		elif piece.gap == NelvarVoidData.Gap.FLIGHT:
			limits = NelvarVoidData.FLIGHT_GAP
		_check(gap >= limits.x - 1.0 and gap <= limits.y + 1.0,
			context + "route gap %d is %.1f, expected %s" % [i, gap, limits])
	# No piece touches another or the monolith; non-neighbours stay out of running reach.
	var monolith := data.monolith.world_polygon()
	for a in data.debris.size():
		var piece_a := data.debris[a]
		var polygon_a := piece_a.world_polygon()
		_check(NelvarVoidData.polygon_distance(polygon_a, monolith) > 0.0,
			context + "piece %d touches the monolith" % a)
		for b in range(a + 1, data.debris.size()):
			var polygon_b := data.debris[b].world_polygon()
			var gap := NelvarVoidData.polygon_distance(polygon_a, polygon_b)
			_check(gap > 0.0, context + "pieces %d and %d overlap" % [a, b])


## Drives the real player through the Void scene: a step is walked over, a leap is
## a fall when walked and a success with a run-up, the arena seals the monolith.
func _check_gameplay() -> void:
	var generator := NelvarVoidGenerator.new()
	var world_seed := -1
	for candidate in 400:
		var data := generator.generate(candidate)
		if data != null and _crossing(data, NelvarVoidData.Gap.STEP) >= 0 \
				and _crossing(data, NelvarVoidData.Gap.LEAP) >= 0:
			world_seed = candidate
			break
	_check(world_seed >= 0, "No seed with both a still step and a still leap")
	if world_seed < 0:
		return
	# Untyped: the scene script uses autoloads, which tests cannot name at compile time.
	var game = (load("res://scenes/void.tscn") as PackedScene).instantiate()
	# The scene reads its seed from the command line; set it before _ready.
	game.set_meta("seed_override", world_seed)
	root.add_child(game)
	await physics_frame
	await physics_frame
	var data: NelvarVoidData = game.data
	var player: NelvarPlayer = game.player
	_check(data != null and data.world_seed == world_seed, "Void scene did not build seed %d" % world_seed)
	if data == null:
		game.queue_free()
		return
	_check(data.support_at(player.global_position, 0.0) != null, "Player does not start on debris")
	var step := _crossing(data, NelvarVoidData.Gap.STEP)
	_check(await _cross(game, step, false), "Walking did not cross a step")
	var leap := _crossing(data, NelvarVoidData.Gap.LEAP)
	_check(not await _cross(game, leap, false), "Walking crossed a leap")
	_check(game.player.health < player.max_health, "A fall did not hurt")
	await _wait_frames(70)
	_check(not player.is_falling() and data.support_at(player.global_position, 0.0) != null,
		"The player did not come back onto debris after a fall")
	_check(await _cross(game, leap, true), "Running did not clear a leap")
	# The arena: stepping in seals the monolith; walking at its edge then stops.
	player.global_position = data.arena_center + Vector2(0.0, NelvarVoidData.ARENA_TRIGGER_RADIUS - 40.0)
	await _wait_frames(3)
	_check(game.arena.started, "Entering the arena did not start the fight")
	var edge := data.monolith.world_polygon()
	var target := (edge[11] + edge[12]) * 0.5
	var direction := player.global_position.direction_to(target)
	_press_direction(direction)
	await _wait_frames(roundi(player.global_position.distance_to(target) / player.speed * 60.0) + 40)
	_release_controls()
	_check(not player.is_falling() and data.monolith.supports(player.global_position, 0.0, 2.0),
		"The sealed arena let the player fall")
	game.queue_free()
	await process_frame
	await process_frame
	# The baked monolith is cached for the whole run; drop it before exit.
	NelvarDebrisPainter.clear_cache()


## Index of the first route crossing of `gap` between two still pieces, or -1.
func _crossing(data: NelvarVoidData, gap: NelvarVoidData.Gap) -> int:
	for i in range(1, data.route.size() - 1):
		var here := data.debris[data.route[i]]
		var there := data.debris[data.route[i + 1]]
		if here.gap == gap and here.motion == NelvarVoidData.Motion.STILL \
				and there.motion == NelvarVoidData.Motion.STILL:
			return i
	return -1


## Walks (or runs) from route piece `index` to the next; true when the player ends
## up on the next piece without falling.
func _cross(game, index: int, run: bool) -> bool:
	var data: NelvarVoidData = game.data
	var player: NelvarPlayer = game.player
	var here := data.debris[data.route[index]]
	var there := data.debris[data.route[index + 1]]
	var a := here.world_polygon()
	var b := there.world_polygon()
	var best := INF
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	for i in a.size():
		for point in b:
			var closest := Geometry2D.get_closest_point_to_segment(point, a[i], a[(i + 1) % a.size()])
			if closest.distance_to(point) < best:
				best = closest.distance_to(point)
				from = closest
				to = point
	for i in b.size():
		for point in a:
			var closest := Geometry2D.get_closest_point_to_segment(point, b[i], b[(i + 1) % b.size()])
			if closest.distance_to(point) < best:
				best = closest.distance_to(point)
				from = point
				to = closest
	var direction := from.direction_to(to)
	# A run-up needs room; walking starts close to the edge.
	var start := from - direction * (90.0 if run else 40.0)
	if data.support_at(start, 0.0, 0.0) != here:
		start = here.position
		direction = start.direction_to(to)
	player.global_position = start
	player.velocity = Vector2.ZERO
	game._air_time = 0.0
	await _wait_frames(2)
	var falls: int = game._falls
	_press_direction(direction)
	if run:
		await _wait_frames(2)
		Input.action_press("toggle_run")
		await _wait_frames(1)
		Input.action_release("toggle_run")
	var arrived := false
	for frame in 150:
		await physics_frame
		if game._falls != falls or player.is_falling():
			break
		var support := data.support_at(player.global_position, 0.0, 0.0)
		if support == there and NelvarVoidData.distance_to_outline(
				player.global_position - there.position, there.polygon) > 20.0:
			arrived = true
			break
	_release_controls()
	await _wait_frames(15)
	if game._falls != falls or player.is_falling():
		# Let the fall finish so the next check starts clean.
		await _wait_frames(80)
		return false
	return arrived


func _wait_frames(count: int) -> void:
	for i in count:
		await physics_frame


func _press_direction(direction: Vector2) -> void:
	_release_controls()
	var normal := direction.normalized()
	if normal.x > 0.0:
		Input.action_press("move_right", normal.x)
	elif normal.x < 0.0:
		Input.action_press("move_left", -normal.x)
	if normal.y > 0.0:
		Input.action_press("move_down", normal.y)
	elif normal.y < 0.0:
		Input.action_press("move_up", -normal.y)


func _release_controls() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "toggle_run"]:
		Input.action_release(action)


func _fingerprint(data: NelvarVoidData) -> String:
	var parts: Array[String] = []
	for piece in data.debris:
		parts.append("%d:%d:%s:%s" % [piece.kind, piece.motion, piece.position.snapped(Vector2.ONE * 0.01),
			piece.travel.snapped(Vector2.ONE * 0.01)])
	return ",".join(parts)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
