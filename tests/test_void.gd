extends SceneTree
## Run: godot --headless --path . --script tests/test_void.gd -- --seeds=50 --walks=6

var _failures: Array[String] = []
var last_cross_fell := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 50
	var walks := 6
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
		elif argument.begins_with("--walks="):
			walks = maxi(0, argument.trim_prefix("--walks=").to_int())
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
	await _check_gameplay(walks)
	if _failures.is_empty():
		print("PASS: %d checks; a bot walked %d Voids to the arena; hazards and the Only One behave" % [_checks, walks])
		quit(0)
	else:
		for failure in _failures.slice(0, 30):
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


## Walking must not clear a LEAP, running must; flight covers every FLIGHT gap.
func _check_reach_constants() -> void:
	# A fall is noticed on the first physics step past the coyote time.
	var tolerance := NelvarVoidData.EDGE_TOLERANCE * 2.0
	var air := NelvarVoidData.COYOTE_TIME + 1.0 / 60.0
	var walk := NelvarVoidData.WALK_SPEED * air + tolerance
	var run := NelvarVoidData.RUN_SPEED * air + tolerance
	_check(NelvarVoidData.STEP_GAP.y < walk - 15.0, "A step is not comfortably walkable")
	_check(NelvarVoidData.LEAP_GAP.x > walk + 5.0, "A leap can be walked over")
	_check(NelvarVoidData.LEAP_GAP.y < run - 5.0, "A leap is out of running reach")
	_check(NelvarVoidData.FLIGHT_GAP.x > run + 50.0, "A flight gap can be run over")
	_check(NelvarVoidData.SLACK_LIMITS[NelvarVoidData.Gap.STEP] < walk - 15.0,
		"A step taken off-centre is out of walking reach")
	_check(NelvarVoidData.SLACK_LIMITS[NelvarVoidData.Gap.LEAP] < run - 5.0,
		"A leap taken off-centre is out of running reach")
	_check(NelvarVoidData.FLIGHT_GAP.y < NelvarVoidData.RUN_SPEED * 2.0 * 0.4,
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
	# Consecutive route pieces: walking straight from the middle of one towards the
	# middle of the next crosses exactly the gap that crossing is meant to take.
	# Measured here by sampling the line, independently of the generator's maths.
	for i in data.route.size():
		var piece := data.debris[data.route[i]]
		var time := piece.period * 0.5 if piece.motion == NelvarVoidData.Motion.FERRY else 0.0
		var from := piece.position + piece.offset_at(time)
		var here := piece.world_polygon(time)
		var there := data.monolith.world_polygon()
		var to := data.monolith.position
		if i + 1 < data.route.size():
			var next := data.debris[data.route[i + 1]]
			there = next.world_polygon(0.0)
			to = next.position
		var gap := _sampled_gap(from, here, to, there)
		var limits := NelvarVoidData.STEP_GAP
		if piece.gap == NelvarVoidData.Gap.LEAP:
			limits = NelvarVoidData.LEAP_GAP
		elif piece.gap == NelvarVoidData.Gap.FLIGHT:
			limits = NelvarVoidData.FLIGHT_GAP
		_check(gap >= limits.x - 1.5 and gap <= limits.y + 1.5,
			context + "route crossing %d is %.1f wide, expected %s" % [i, gap, limits])
		_check(NelvarVoidData.polygon_distance(here, there) >= NelvarVoidData.MIN_EDGE_GAP - 0.5,
			context + "route pieces %d and %d nearly touch" % [i, i + 1])
		var side := from.direction_to(to).orthogonal() * NelvarVoidData.CROSSING_SLACK
		var slack := maxf(_sampled_gap(from + side, here, to + side, there),
			_sampled_gap(from - side, here, to - side, there))
		_check(slack <= NelvarVoidData.SLACK_LIMITS[piece.gap] + 1.5,
			context + "route crossing %d is %.1f wide off-centre" % [i, slack])
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


## Drives the real player through the Void scene. Walking straight over a leap is
## a fall that hurts and brings the player back; then a bot plays whole Voids from
## the spawn to the arena the way a player would (see _walk_route), and the arena
## seals the monolith.
func _check_gameplay(walk_seeds: int) -> void:
	var generator := NelvarVoidGenerator.new()
	var leap_seed := -1
	for candidate in 400:
		var data := generator.generate(candidate)
		if data != null and _crossing(data, NelvarVoidData.Gap.LEAP) >= 0:
			leap_seed = candidate
			break
	_check(leap_seed >= 0, "No seed with a leap between still pieces")
	# Game time runs four times faster; every physics step is still 1/60 s.
	var ticks := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	if leap_seed >= 0:
		var game = await _spawn(leap_seed)
		var data: NelvarVoidData = game.data
		var player: NelvarPlayer = game.player
		var index := _crossing(data, NelvarVoidData.Gap.LEAP)
		var here := data.debris[data.route[index]]
		var there := data.debris[data.route[index + 1]]
		player.global_position = here.position
		await _wait_frames(2)
		_check(not await _cross(game, here, there, NelvarVoidData.Gap.STEP),
			"Walking straight over a leap did not fail")
		_check(player.health < player.max_health, "A fall did not hurt")
		_check(not player.is_falling() and data.support_at(player.global_position, game._time) != null,
			"The player did not come back onto debris after a fall")
		game.queue_free()
		await process_frame
	for i in walk_seeds:
		var world_seed := 20261124 + i * 104729
		var game = await _spawn(world_seed)
		var failure: String = await _walk_route(game)
		_check(failure.is_empty(), "Seed %d: the bot could not reach the arena: %s" % [world_seed, failure])
		if failure.is_empty():
			await _check_seal(game)
		game.queue_free()
		await process_frame
	await _check_hazards()
	await _check_boss()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = ticks
	await process_frame
	# The baked monolith is cached for the whole run; drop it before exit.
	NelvarDebrisPainter.clear_cache()


## Each boss hazard hurts a player standing in it and spares one outside it.
func _check_hazards() -> void:
	var layer := Node2D.new()
	root.add_child(layer)
	var cases := {
		"rift on the line": [func() -> Node2D:
			var rift := NelvarVoidHazards.Rift.new()
			rift.length = 400.0
			rift.telegraph = 0.3
			rift.position = Vector2(-200.0, 0.0)
			return rift, Vector2.ZERO, true],
		"rift beside the line": [func() -> Node2D:
			var rift := NelvarVoidHazards.Rift.new()
			rift.length = 400.0
			rift.telegraph = 0.3
			rift.position = Vector2(-200.0, 90.0)
			return rift, Vector2.ZERO, false],
		"pull burst": [func() -> Node2D:
			var pull := NelvarVoidHazards.Pull.new()
			pull.duration = 0.6
			return pull, Vector2(0.0, 120.0), true],
		"collapse sector": [func() -> Node2D:
			var sectors := NelvarVoidHazards.Sectors.new()
			sectors.start = 0.0
			sectors.telegraph = 0.3
			sectors.cycles = 1
			return sectors, Vector2(300.0, 0.0), true],
		"between sectors": [func() -> Node2D:
			var sectors := NelvarVoidHazards.Sectors.new()
			sectors.start = 0.0
			sectors.count = 6
			sectors.telegraph = 0.3
			sectors.cycles = 1
			return sectors, Vector2.from_angle(PI / 6.0) * 300.0, false],
		"squeeze ring": [func() -> Node2D:
			var squeeze := NelvarVoidHazards.Squeeze.new()
			squeeze.start_radius = 500.0
			squeeze.duration = 2.0
			squeeze.gap = PI
			return squeeze, Vector2(300.0, 0.0), true],
		"squeeze gap": [func() -> Node2D:
			var squeeze := NelvarVoidHazards.Squeeze.new()
			squeeze.start_radius = 500.0
			squeeze.duration = 1.9
			squeeze.gap = 0.0
			squeeze.collapse_radius = 100.0
			return squeeze, Vector2(300.0, 0.0), false],
		"shard": [func() -> Node2D:
			var shard := NelvarVoidHazards.Shard.new()
			shard.boss = layer
			shard.position = Vector2(-200.0, -14.0)
			return shard, Vector2.ZERO, true],
		"dash trail": [func() -> Node2D:
			var trail := NelvarVoidHazards.Trail.new()
			trail.from = Vector2(-100.0, 0.0)
			trail.to = Vector2(100.0, 0.0)
			return trail, Vector2.ZERO, true],
	}
	for label: String in cases:
		var spec: Array = cases[label]
		var player: NelvarPlayer = (load("res://player/player.tscn") as PackedScene).instantiate()
		layer.add_child(player)
		player.global_position = spec[1]
		var hazard: NelvarVoidHazards.Hazard = spec[0].call()
		hazard.player = player
		hazard.damage = 20.0
		layer.add_child(hazard)
		await _wait_frames(60 * 3)
		var hurt := player.health < player.max_health
		_check(hurt == spec[2], "Hazard '%s': %s" % [label, "hurt" if hurt else "did not hurt"])
		if label == "pull burst":
			_check(player.global_position.length() < 100.0, "The pull did not drag the player in")
		player.queue_free()
		if is_instance_valid(hazard):
			hazard.queue_free()
		await process_frame
	layer.queue_free()
	await process_frame


## The Only One: forms invulnerable, goes through the phases at their thresholds
## (invulnerable while it changes), dies and lifts the seal. Losing the fight
## brings the next Void back with the same seed at the arena's door.
func _check_boss() -> void:
	var game = await _spawn(777)
	var data: NelvarVoidData = game.data
	var player: NelvarPlayer = game.player
	player.max_health = 1.0e6
	player.health = 1.0e6
	player.global_position = data.arena_center + Vector2(0.0, NelvarVoidData.ARENA_TRIGGER_RADIUS - 30.0)
	await _wait_frames(3)
	var boss: NelvarTheOne = game.arena.boss
	_check(boss != null, "Entering the arena did not bring the Only One")
	if boss == null:
		game.queue_free()
		return
	_check(boss.is_in_group("enemies"), "The boss is not an enemy for the player's attacks")
	_check((boss.get_node("Hurtbox") as Area2D).collision_layer & 8 != 0,
		"The boss's body cannot be hit")
	boss.take_damage(100.0)
	_check(boss.health == boss.max_health, "The boss took damage while forming")
	await _wait_frames(roundi(NelvarTheOne.INTRO_TIME * 60.0) + 30)
	_check(boss.active, "The boss never started fighting")
	var phases: Array[int] = []
	boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	for i in NelvarTheOne.PHASE_AT.size():
		boss.take_damage(boss.health - boss.max_health * NelvarTheOne.PHASE_AT[i] + 1.0)
		var during := boss.health
		boss.take_damage(50.0)
		_check(boss.health == during, "The boss took damage while changing phase")
		# The change runs partly in slow motion: wait until it fights again.
		for frame in 60 * 10:
			await physics_frame
			if boss.active:
				break
		_check(boss.active, "The boss did not come back after phase %d" % (i + 2))
	_check(phases == [1, 2, 3], "Phases went %s instead of I -> IV" % [phases])
	_check(boss.body.phase == 3, "The body did not follow the phases")
	await _wait_frames(60 * 4)
	boss.take_damage(1.0e6)
	# Its death runs in slow motion; wait it out, then for the last sparks to go.
	for frame in 60 * 12:
		if game.arena.boss_defeated:
			break
		await physics_frame
	await _wait_frames(150)
	_check(game.arena.boss_defeated, "The boss did not die")
	_check(get_nodes_in_group("void_hazards").is_empty(), "Hazards outlived the boss")
	_check(game.arena.get_node("Seal").collision_layer == 0, "The seal stayed after the fight")
	game.queue_free()
	await process_frame
	# Lose a fight: the next Void starts at the arena.
	game = await _spawn(777)
	player = game.player
	player.global_position = game.data.arena_center + Vector2(0.0, NelvarVoidData.ARENA_TRIGGER_RADIUS - 30.0)
	await _wait_frames(3)
	player.health = 0.0
	game.queue_free()
	await process_frame
	var retry = (load("res://scenes/void.tscn") as PackedScene).instantiate()
	root.add_child(retry)
	await _wait_frames(2)
	var last: NelvarVoidData.Debris = retry.data.debris[retry.data.route[retry.data.route.size() - 1]]
	_check(retry.data.world_seed == 777, "A lost fight did not bring the same Void back")
	_check(retry.data.support_at(retry.player.global_position, 0.0) == last,
		"After a lost fight the player did not start at the arena's door")
	retry.queue_free()
	await process_frame


## Untyped: the scene script uses autoloads, which tests cannot name at compile time.
func _spawn(world_seed: int):
	var game = (load("res://scenes/void.tscn") as PackedScene).instantiate()
	game.set_meta("seed_override", world_seed)
	root.add_child(game)
	await _wait_frames(2)
	_check(game.data != null and game.data.world_seed == world_seed,
		"Void scene did not build seed %d" % world_seed)
	return game


## Plays the route like a player: walk to the middle of the piece, wait for the
## right moment (a drifting piece at the near or far end, a flickering one solid
## for a while, the flight recharged), then go straight for the middle of the next
## piece — walking, with a run-up or flying, as the crossing needs. Returns "" when
## the arena fight starts, otherwise what went wrong.
func _walk_route(game) -> String:
	var data: NelvarVoidData = game.data
	var player: NelvarPlayer = game.player
	for i in data.route.size():
		var here := data.debris[data.route[i]]
		var there: NelvarVoidData.Debris = data.monolith
		if i + 1 < data.route.size():
			there = data.debris[data.route[i + 1]]
		var what := "crossing %d/%d (%s, %s -> %s)" % [i, data.route.size(),
			NelvarVoidData.Gap.keys()[here.gap], NelvarVoidData.Kind.keys()[here.kind],
			NelvarVoidData.Kind.keys()[there.kind]]
		if not await _go_to_middle(game, here):
			return "fell walking to the middle before " + what
		var waited := 0
		while not _good_moment(game, here, there):
			await physics_frame
			waited += 1
			if waited > 60 * 25:
				return "waited too long before " + what
		if not await _cross(game, here, there, here.gap):
			return ("fell on " if last_cross_fell else "never got a footing after ") + what
	# Onto the monolith and into the arena.
	_press_direction(player.global_position.direction_to(data.arena_center))
	for frame in 60 * 12:
		await physics_frame
		if game.arena.started:
			break
	_release_controls()
	if not game.arena.started:
		return "never reached the arena"
	if game._falls > 0:
		return "%d falls on the way" % game._falls
	return ""


func _go_to_middle(game, piece: NelvarVoidData.Debris) -> bool:
	var player: NelvarPlayer = game.player
	var falls: int = game._falls
	for frame in 60 * 4:
		var middle := piece.position + piece.offset_at(game._time)
		if player.global_position.distance_to(middle) < 10.0:
			break
		_press_direction(player.global_position.direction_to(middle))
		await physics_frame
		if game._falls != falls:
			_release_controls()
			return false
	_release_controls()
	await _wait_frames(4)
	return game._falls == falls


func _good_moment(game, here: NelvarVoidData.Debris, there: NelvarVoidData.Debris) -> bool:
	var time: float = game._time
	if here.motion == NelvarVoidData.Motion.FERRY \
			and here.offset_at(time).distance_to(here.travel) > 4.0:
		return false
	if there.motion == NelvarVoidData.Motion.FERRY and there.offset_at(time).length() > 4.0:
		return false
	if there.motion == NelvarVoidData.Motion.FLICKER:
		var solid_left := NelvarVoidData.FLICKER_SOLID_SHARE * there.period - there.cycle_at(time) * there.period
		if not there.is_solid_at(time) or solid_left < 2.0:
			return false
	if here.gap == NelvarVoidData.Gap.FLIGHT:
		# Flight must be ready (NelvarPlayer.SpeedBoostState.READY).
		return game.player.get("_speed_boost_state") == 0
	return true


## Index of the first route crossing of `gap` between two still pieces, or -1.
func _crossing(data: NelvarVoidData, gap: NelvarVoidData.Gap) -> int:
	for i in range(1, data.route.size() - 1):
		var here := data.debris[data.route[i]]
		var there := data.debris[data.route[i + 1]]
		if here.gap == gap and here.motion == NelvarVoidData.Motion.STILL \
				and there.motion == NelvarVoidData.Motion.STILL:
			return i
	return -1


## Goes straight from where the player stands towards the middle of `there`:
## walking for a STEP, with a run-up for a LEAP, flying for a FLIGHT. True when the
## player stands firmly on `there` without having fallen (`last_cross_fell` says
## which way it failed).
func _cross(game, here: NelvarVoidData.Debris, there: NelvarVoidData.Debris,
		gap: NelvarVoidData.Gap) -> bool:
	var player: NelvarPlayer = game.player
	var falls: int = game._falls
	var target := there.position + there.offset_at(game._time)
	_press_direction(player.global_position.direction_to(target))
	if gap == NelvarVoidData.Gap.LEAP:
		await physics_frame
		await _tap("toggle_run")
	elif gap == NelvarVoidData.Gap.FLIGHT:
		await _tap("speed_boost")
	var arrived := false
	for frame in 60 * 5:
		await physics_frame
		if game._falls != falls:
			break
		var middle := there.position + there.offset_at(game._time)
		_press_direction(player.global_position.direction_to(middle), false)
		var local := player.global_position - middle
		# Firm footing: the whole body is over the piece (logs are barely wider).
		if there.supports(player.global_position, game._time, 0.0) \
				and NelvarVoidData.distance_to_outline(local, there.polygon) > NelvarPlayer.BODY_RADIUS:
			arrived = true
			break
	_release_controls()
	last_cross_fell = game._falls != falls or player.is_falling()
	if last_cross_fell:
		# Let the fall finish so the next check starts clean.
		await _wait_frames(90)
		return false
	return arrived


## Holds an action across a whole idle frame, so `is_action_just_pressed` sees it.
func _tap(action: String) -> void:
	Input.action_press(action)
	await process_frame
	await process_frame
	Input.action_release(action)


## Inside the arena, walking at the sealed edge stops the player instead of a fall.
func _check_seal(game) -> void:
	var data: NelvarVoidData = game.data
	var player: NelvarPlayer = game.player
	var edge := data.monolith.world_polygon()
	var target := (edge[11] + edge[12]) * 0.5
	_press_direction(player.global_position.direction_to(target))
	await _wait_frames(roundi(player.global_position.distance_to(target) / player.speed * 60.0) + 40)
	_release_controls()
	_check(not player.is_falling() and data.monolith.supports(player.global_position, 0.0, 2.0),
		"The sealed arena let the player fall")


func _wait_frames(count: int) -> void:
	for i in count:
		await physics_frame


func _press_direction(direction: Vector2, reset := true) -> void:
	if reset:
		_release_controls()
	var normal := direction.normalized()
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	if normal.x > 0.0:
		Input.action_press("move_right", normal.x)
	elif normal.x < 0.0:
		Input.action_press("move_left", -normal.x)
	if normal.y > 0.0:
		Input.action_press("move_down", normal.y)
	elif normal.y < 0.0:
		Input.action_press("move_up", -normal.y)


func _release_controls() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "toggle_run", "speed_boost"]:
		Input.action_release(action)


## Length of the line from `from` to `to` that lies over the abyss, 1-unit samples.
func _sampled_gap(from: Vector2, a: PackedVector2Array, to: Vector2, b: PackedVector2Array) -> float:
	var length := from.distance_to(to)
	var outside := 0
	var steps := ceili(length)
	for i in steps:
		var point := from.lerp(to, (i + 0.5) / steps)
		if not Geometry2D.is_point_in_polygon(point, a) and not Geometry2D.is_point_in_polygon(point, b):
			outside += 1
	return length * outside / steps


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
