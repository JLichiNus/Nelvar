extends SceneTree
## Run: godot --headless --path . --script tests/test_world.gd

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 100
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	var config := NelvarWorldConfig.new()
	var generator := NelvarWorldGenerator.new()
	var started := Time.get_ticks_msec()
	for index in count:
		# Include zero, negative and wide integer seeds, plus a reproducible spread.
		var world_seed := index * 7919 - 20261120
		if index == 0:
			world_seed = 0
		elif index == 1:
			world_seed = 9223372036854775807
		var data := generator.generate(config, world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		_check_world(data, config)
		if index < 5:
			var repeat := generator.generate(config, world_seed)
			_check(repeat != null and _fingerprint(data) == _fingerprint(repeat),
				"Seed %d: generation is not deterministic" % world_seed)
	print("Generation: %d seeds in %.2f s" % [
		count, float(Time.get_ticks_msec() - started) / 1000.0])
	await _check_gameplay()
	if _failures.is_empty():
		print("PASS: %d checks, including movement, coasts, bridge landings and camera." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


func _check_world(data: NelvarWorldData, config: NelvarWorldConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	var large := 0
	for island in data.islands:
		if island.large:
			large += 1
	var small := data.islands.size() - large
	_check(large >= 2 and large <= 3 and small >= 6 and small <= 7,
		context + "incorrect island counts")
	var reached := {0: true}
	for iteration in data.islands.size():
		for bridge in data.bridges:
			if reached.has(bridge.island_a) or reached.has(bridge.island_b):
				reached[bridge.island_a] = true
				reached[bridge.island_b] = true
	_check(reached.size() == data.islands.size(), context + "disconnected islands")
	_check(data.has_clearance(data.spawn_position, NelvarPlayer.BODY_RADIUS + 1.0),
		context + "unsafe spawn")
	var assigned := 0
	for chunk in data.leaves:
		assigned += chunk.borders.size()
		for polygon in chunk.ground_polygons + chunk.bridge_polygons:
			for point in polygon:
				_check(chunk.rect.grow(0.02).has_point(point), context + "geometry outside its chunk")
	_check(assigned == data.borders.size(), context + "missing or duplicated chunk colliders")
	for bridge in data.bridges:
		_check(is_equal_approx(bridge.width, config.bridge_width()), context + "incorrect bridge width")
		var direction := bridge.start.direction_to(bridge.finish)
		var side := direction.orthogonal()
		for step in 13:
			var point := bridge.start.lerp(bridge.finish, float(step) / 12.0)
			_check(data.has_clearance(point, NelvarPlayer.BODY_RADIUS + 1.0),
				context + "blocked bridge or landing")
			for offset: float in [-1.0, 1.0]:
				_check(data.is_walkable(point + side * offset * bridge.width * 0.42),
					context + "gap along bridge edge")
	for border in data.borders:
		var middle := (border.start + border.finish) * 0.5
		var normal := border.start.direction_to(border.finish).orthogonal() * 0.15
		_check(data.is_walkable(middle + normal) != data.is_walkable(middle - normal),
			context + "internal or invalid collision edge")
	# Chunk queries must agree with the original, uncut global surface geometry.
	var rng := RandomNumberGenerator.new()
	rng.seed = data.world_seed
	for sample in 180:
		var point := Vector2(rng.randf_range(data.bounds.position.x, data.bounds.end.x),
			rng.randf_range(data.bounds.position.y, data.bounds.end.y))
		var expected := false
		for island in data.islands:
			expected = expected or Geometry2D.is_point_in_polygon(point, island.polygon)
		for bridge in data.bridges:
			expected = expected or Geometry2D.is_point_in_polygon(point, bridge.polygon)
		_check(data.is_walkable(point) == expected, context + "chunk seam or missing surface")


func _check_gameplay() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game := packed.instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var player: NelvarPlayer = game.player
	var data: NelvarWorldData = game.world_data
	_check(data != null, "Main scene failed to generate its map")
	if data == null:
		game.queue_free()
		return
	_check(player.camera.enabled, "Player camera is disabled")
	_check(player.camera.get_parent() == player, "Camera does not follow the player")
	var initial := player.position
	_press_direction(Vector2.RIGHT)
	for frame in 16:
		await physics_frame
	_release_controls()
	_check(player.position.x > initial.x + 40.0, "Walking input does not move the player")
	_check(data.has_clearance(player.position, NelvarPlayer.BODY_RADIUS - 0.2),
		"Walking left the surface")
	# Walk the real CharacterBody2D off a shoreline away from bridge mouths.
	var tested_shore := false
	for border in data.borders:
		if not border.shore or border.start.distance_to(border.finish) < 20.0:
			continue
		var middle := (border.start + border.finish) * 0.5
		var normal := border.start.direction_to(border.finish).orthogonal()
		if data.is_walkable(middle + normal):
			normal = -normal
		var inside := middle - normal * (NelvarPlayer.BODY_RADIUS + 24.0)
		# Firm footing (main.gd SAFE_CLEARANCE), so the fall comes back right here.
		if not data.is_firm(inside, NelvarPlayer.BODY_RADIUS + 11.0):
			continue
		# The walk to the coast must not run into a rock instead.
		if not game.prop_data.has_clearance(inside, NelvarPlayer.BODY_RADIUS + 40.0):
			continue
		player.position = inside
		player.velocity = Vector2.ZERO
		await physics_frame
		var falls: int = game.falls
		var health := player.health
		_press_direction(normal)
		for frame in 30:
			await physics_frame
		_release_controls()
		_check(game.falls == falls + 1, "Walking off a coast did not fall")
		_check(await _wait_recovered(player), "The fall from a coast never ended")
		_check(data.is_firm(player.position, NelvarPlayer.BODY_RADIUS),
			"The fall from a coast did not bring the player back on firm ground")
		_check(player.position.distance_to(inside) < 70.0,
			"The fall from a coast brought the player back far away")
		_check(player.health < health, "The fall from a coast did no damage")
		tested_shore = true
		break
	_check(tested_shore, "No suitable coast for the physics test")
	# Enemies still stop at the edges.
	var hopper: PackedScene = load("res://enemies/hopper/hopper.tscn")
	var enemy := hopper.instantiate() as CollisionObject2D
	_check(enemy.collision_mask & NelvarWorldData.EDGE_LAYER != 0, "Enemies walk off the edges")
	enemy.free()
	_check(player.collision_mask & NelvarWorldData.EDGE_LAYER == 0, "The edges stop the player")
	# Walk across each complete bridge, through both landing seams.
	for bridge in data.bridges:
		var direction := bridge.start.direction_to(bridge.finish)
		player.position = bridge.start - direction * 20.0
		player.velocity = Vector2.ZERO
		_press_direction(direction)
		var frames := ceili((bridge.start.distance_to(bridge.finish) + 55.0)
			/ player.speed * Engine.physics_ticks_per_second)
		for frame in frames:
			await physics_frame
		_release_controls()
		_check((player.position - bridge.finish).dot(direction) >= 0.0,
			"Character was blocked at a bridge landing")
		_check(data.has_clearance(player.position, NelvarPlayer.BODY_RADIUS - 0.3),
			"Character left the bridge surface")
	# Step sideways off a bridge: a fall, and back on the bridge.
	var bridge := data.bridges[0]
	var middle := (bridge.start + bridge.finish) * 0.5
	var side := bridge.start.direction_to(bridge.finish).orthogonal()
	player.position = middle
	player.velocity = Vector2.ZERO
	await physics_frame
	var falls_before: int = game.falls
	_press_direction(side)
	for frame in 30:
		await physics_frame
	_release_controls()
	_check(game.falls == falls_before + 1, "Stepping off a bridge did not fall")
	_check(await _wait_recovered(player), "The fall from a bridge never ended")
	_check(player.position.distance_to(middle) < bridge.width * 0.5,
		"The fall from a bridge did not bring the player back onto it")
	# The flight carries the player over the sky without a fall.
	var sky := middle + side * (bridge.width * 0.5 + 60.0)
	if not data.is_walkable(sky):
		player.call("_try_speed_boost")
		player.position = sky
		player.velocity = Vector2.ZERO
		var falls_flying: int = game.falls
		for frame in 20:
			await physics_frame
		_check(player.is_airborne() and game.falls == falls_flying, "The flight fell into the sky")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(game.world_view.details.show_chunks, "F3 does not show the chunks")
	game.queue_free()
	await process_frame


## Waits out a fall; false if the player is still falling after a few seconds.
func _wait_recovered(player: NelvarPlayer) -> bool:
	for frame in 240:
		if not player.is_falling():
			return true
		await physics_frame
	return not player.is_falling()


func _press_direction(direction: Vector2) -> void:
	_release_controls()
	if direction.x > 0.0:
		Input.action_press("move_right", direction.x)
	elif direction.x < 0.0:
		Input.action_press("move_left", -direction.x)
	if direction.y > 0.0:
		Input.action_press("move_down", direction.y)
	elif direction.y < 0.0:
		Input.action_press("move_up", -direction.y)


func _release_controls() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)


func _fingerprint(data: NelvarWorldData) -> int:
	var parts: Array = []
	for island in data.islands:
		parts.append(island.polygon)
	for bridge in data.bridges:
		parts.append(bridge.polygon)
	for chunk in data.leaves:
		parts.append(chunk.rect)
	return hash(parts)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 40:
		_failures.append(message)
