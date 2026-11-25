extends SceneTree
## The Runner: it chases the player, winds up and dashes when the way is clear,
## hurts more in a dash, skids and recovers after a miss, is stunned by a trunk
## or by a wave that catches it winding up, loses its dash to compression, gets
## round a wall when chasing and dies.
## Run: godot --headless --path . --script tests/test_runner.gd

const PLAYER_SCENE := preload("res://player/player.tscn")
const RUNNER_SCENE := preload("res://enemies/runner/runner.tscn")

var _failures: Array[String] = []
var _checks := 0
var _world: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_art()
	await _check_chase()
	await _check_dash()
	await _check_no_dash_through_wall()
	await _check_bonk()
	await _check_wave_knocks_down()
	await _check_hold()
	await _check_death()
	if is_instance_valid(_world):
		_world.free()
	if _failures.is_empty():
		print("PASS: %d runner checks; art, chase, dash, skid, wall, bonk, wave, hold, death." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _fresh_world() -> void:
	if is_instance_valid(_world):
		_world.free()
	_world = Node2D.new()
	root.add_child(_world)


func _add_player(at: Vector2) -> NelvarPlayer:
	var player := PLAYER_SCENE.instantiate() as NelvarPlayer
	player.position = at
	_world.add_child(player)
	# Standing still: the test moves no keys.
	return player


func _add_runner(at: Vector2, first_delay: float = 0.05) -> NelvarRunner:
	var runner := RUNNER_SCENE.instantiate() as NelvarRunner
	runner.first_delay = Vector2(first_delay, first_delay)
	runner.position = at
	_world.add_child(runner)
	return runner


func _add_wall(at: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	wall.position = at
	_world.add_child(wall)


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _check_art() -> void:
	_fresh_world()
	var runner := _add_runner(Vector2.ZERO)
	for pose in NelvarRunner.Pose.values():
		_check(not runner._paint_legs(pose).is_invisible(), "Legs of pose %d are empty" % pose)
	var seen := {}
	for variant in 4:
		for eye in NelvarRunner.Eye.values():
			var image := runner._paint_body(variant, eye)
			_check(not image.is_invisible(), "Body %d/%d is empty" % [variant, eye])
			seen[image.get_data()] = true
	_check(seen.size() == 16, "Body variants repeat: %d unique" % seen.size())


func _check_chase() -> void:
	_fresh_world()
	var player := _add_player(Vector2(900, 0))
	var runner := _add_runner(Vector2.ZERO, 30.0)
	await _frames(2)
	var start := runner._ground().distance_to(player.global_position)
	await _frames(90)
	var now := runner._ground().distance_to(player.global_position)
	_check(now < start - 250.0, "Runner did not close in: %d -> %d" % [start, now])
	_check(runner._state == NelvarRunner.State.CHASE, "Runner left the chase without a dash")


func _check_dash() -> void:
	_fresh_world()
	var player := _add_player(Vector2(300, 0))
	var runner := _add_runner(Vector2(0, -runner_feet()))
	await _frames(12)
	_check(runner._state == NelvarRunner.State.WINDUP, "No windup at dash range (state %d)" % runner._state)
	var dir := runner._dash_dir
	_check(dir.dot((player.global_position - runner._ground()).normalized()) > 0.95, "Windup not aimed at the player")
	await _frames(int(runner.windup_duration * 60.0) + 2)
	_check(runner._state == NelvarRunner.State.DASH, "No dash after the windup")
	_check(runner.contact_damage == runner.dash_contact_damage, "A dash does not hurt more")
	var from := runner.global_position
	await _frames(int(runner.dash_duration * 60.0) + 2)
	var travelled := runner.global_position.distance_to(from)
	_check(travelled > runner.dash_speed * runner.dash_duration * 0.8, "Dash covered only %d" % travelled)
	_check(runner._state == NelvarRunner.State.SKID, "No skid after a dash")
	await _frames(int((runner.skid_duration + runner.recover_duration) * 60.0) + 4)
	_check(runner._state == NelvarRunner.State.CHASE, "Did not recover into the chase")
	_check(runner.contact_damage == runner.walk_contact_damage, "Contact damage stayed high")


func runner_feet() -> float:
	return (NelvarRunner.GROUND_ROW + 0.5 - NelvarRunner.ORIGIN.y) * 3.0


func _check_no_dash_through_wall() -> void:
	_fresh_world()
	_add_player(Vector2(300, 0))
	_add_wall(Vector2(150, 0), Vector2(20, 400))
	var runner := _add_runner(Vector2(0, -runner_feet()))
	await _frames(20)
	_check(runner._state != NelvarRunner.State.WINDUP and runner._state != NelvarRunner.State.DASH,
		"Wound up to dash through a wall")


func _check_bonk() -> void:
	_fresh_world()
	_add_wall(Vector2(120, 0), Vector2(20, 200))
	var runner := _add_runner(Vector2.ZERO, 30.0)
	await _frames(2)
	runner._dash_dir = Vector2.RIGHT
	runner._start_dash()
	await _frames(20)
	_check(runner.is_stunned(), "Running into a wall did not stun")
	_check(runner.contact_damage == 0.0, "A stunned Runner still hurts")
	_check(runner.global_position.x < 120.0, "Ran through the wall")


func _check_wave_knocks_down() -> void:
	_fresh_world()
	_add_player(Vector2(300, 0))
	var runner := _add_runner(Vector2(0, -runner_feet()))
	await _frames(12)
	_check(runner._state == NelvarRunner.State.WINDUP, "Not winding up for the wave check")
	runner.apply_knockback(Vector2.LEFT * 550.0)
	_check(runner.is_stunned(), "A wave did not knock the Runner down")
	await _frames(int(runner.windup_duration * 60.0) + 4)
	_check(runner._state != NelvarRunner.State.DASH, "Dashed after being knocked down")


func _check_hold() -> void:
	_fresh_world()
	_add_player(Vector2(300, 0))
	var runner := _add_runner(Vector2(0, -runner_feet()))
	await _frames(12)
	runner.apply_hold(1.0)
	var at := runner.global_position
	await _frames(40)
	_check(runner.global_position.distance_to(at) < 1.0, "A held Runner moved")
	_check(runner._state != NelvarRunner.State.DASH, "A held Runner dashed")


func _check_death() -> void:
	_fresh_world()
	var runner := _add_runner(Vector2.ZERO, 30.0)
	await _frames(2)
	runner.take_damage(runner.max_health)
	_check(not runner.is_in_group(&"enemies"), "A dead Runner stays an enemy")
	await _frames(int(runner.death_duration * 60.0) + 10)
	_check(not is_instance_valid(runner), "A dead Runner was not freed")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
