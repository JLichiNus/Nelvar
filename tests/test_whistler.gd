extends SceneTree
## The Whistler: it draws breath and blows a fan or a trill of bubbles at the
## player; a bubble hurts a walking player and not a flying one, the LMB shot
## bursts it, the RMB wave turns it back onto enemies, compression breaks off a
## breath, and the spawner keeps each kind under its own cap.
## Run: godot --headless --path . --script tests/test_whistler.gd

const PLAYER_SCENE := preload("res://player/player.tscn")
const WHISTLER_SCENE := preload("res://enemies/whistler/whistler.tscn")
const BUBBLE_SCENE := preload("res://enemies/whistler/whistler_bubble.tscn")
const HOPPER_SCENE := preload("res://enemies/hopper/hopper.tscn")
const WAVE_SCENE := preload("res://attacks/wind_wave/wind_wave.tscn")
const SPAWNER_SCRIPT := preload("res://enemies/enemy_spawner.gd")

var _failures: Array[String] = []
var _checks := 0
var _world: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_art()
	await _check_fan()
	await _check_trill()
	await _check_bubble_hits_player()
	await _check_bubble_spares_flyer()
	await _check_shot_bursts_bubble()
	await _check_wave_deflects()
	await _check_hold_breaks_breath()
	await _check_death()
	await _check_spawner_caps()
	_world.free()
	if _failures.is_empty():
		print("PASS: %d whistler checks; art, fan, trill, hits, flight, burst, deflect, hold, death, spawner." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _fresh_world() -> Node2D:
	if is_instance_valid(_world):
		_world.free()
	_world = Node2D.new()
	root.add_child(_world)
	return _world


func _add_player(at: Vector2) -> NelvarPlayer:
	var player := PLAYER_SCENE.instantiate() as NelvarPlayer
	player.position = at
	_world.add_child(player)
	return player


func _add_whistler(at: Vector2, trill_chance: float) -> NelvarWhistler:
	var whistler := WHISTLER_SCENE.instantiate() as NelvarWhistler
	whistler.first_delay = Vector2(0.05, 0.05)
	whistler.recover_time = Vector2(5.0, 5.0)
	whistler.trill_chance = trill_chance
	whistler.position = at
	_world.add_child(whistler)
	return whistler


func _bubbles() -> Array[NelvarWhistlerBubble]:
	var found: Array[NelvarWhistlerBubble] = []
	for child in _world.get_children():
		if child is NelvarWhistlerBubble:
			found.append(child)
	return found


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _check_art() -> void:
	_fresh_world()
	var whistler := _add_whistler(Vector2.ZERO, 0.0)
	await _frames(2)
	_check(whistler.body.texture != null, "Whistler body has no texture")
	for index in NelvarWhistler.DIRECTIONS:
		var image := whistler._paint_nozzle(index)
		_check(not image.is_invisible(), "Nozzle %d is empty" % index)
	var open := whistler._paint_body(NelvarWhistler.Eyes.CENTER)
	var closed := whistler._paint_body(NelvarWhistler.Eyes.CLOSED)
	_check(open.get_data() != closed.get_data(), "Blink does not change the eyes")


func _check_fan() -> void:
	_fresh_world()
	var player := _add_player(Vector2(300, 16))
	var whistler := _add_whistler(Vector2.ZERO, 0.0)
	await _frames(int((0.05 + whistler.inhale_duration) * 60.0) + 6)
	var bubbles := _bubbles()
	_check(bubbles.size() >= whistler.fan_count_min and bubbles.size() <= whistler.fan_count_max,
		"Fan blew %d bubbles" % bubbles.size())
	var toward := (player.global_position - whistler._feet()).normalized()
	var mean := Vector2.ZERO
	for bubble in bubbles:
		mean += bubble.direction
	_check(mean.normalized().dot(toward) > 0.95, "Fan is not aimed at the player")


func _check_trill() -> void:
	_fresh_world()
	_add_player(Vector2(300, 16))
	var whistler := _add_whistler(Vector2.ZERO, 1.0)
	await _frames(int((0.05 + whistler.inhale_duration) * 60.0) + 3)
	var first := _bubbles().size()
	await _frames(int(whistler.trill_interval * whistler.trill_count * 60.0) + 6)
	_check(first == 1, "Trill started with %d bubbles" % first)
	_check(_bubbles().size() == whistler.trill_count, "Trill blew %d bubbles" % _bubbles().size())


func _launch_bubble(at: Vector2, direction: Vector2) -> NelvarWhistlerBubble:
	var bubble := BUBBLE_SCENE.instantiate() as NelvarWhistlerBubble
	_world.add_child(bubble)
	bubble.launch(at, direction)
	return bubble


func _check_bubble_hits_player() -> void:
	_fresh_world()
	var player := _add_player(Vector2(120, 0))
	await _frames(2)
	var health := player.health
	var bubble := _launch_bubble(Vector2.ZERO, Vector2.RIGHT)
	await _frames(60)
	_check(not is_instance_valid(bubble), "Bubble did not burst on the player")
	_check(is_equal_approx(player.health, health - bubble_damage()), "Bubble hit for %s" % (health - player.health))


func bubble_damage() -> float:
	var bubble := BUBBLE_SCENE.instantiate() as NelvarWhistlerBubble
	var damage := bubble.damage
	bubble.free()
	return damage


func _check_bubble_spares_flyer() -> void:
	_fresh_world()
	var player := _add_player(Vector2(60, 0))
	await _frames(2)
	player._speed_boost_state = NelvarPlayer.SpeedBoostState.ACTIVE
	var health := player.health
	var bubble := _launch_bubble(Vector2.ZERO, Vector2.RIGHT)
	await _frames(20)
	_check(is_instance_valid(bubble), "Bubble burst on a flying player")
	_check(player.health == health, "A flying player was hurt by a bubble")


func _check_shot_bursts_bubble() -> void:
	_fresh_world()
	var bubble := _launch_bubble(Vector2.ZERO, Vector2.RIGHT)
	await _frames(2)
	bubble.take_damage(10.0)
	await _frames(1)
	_check(not is_instance_valid(bubble), "A shot did not burst the bubble")


func _check_wave_deflects() -> void:
	_fresh_world()
	var whistler := _add_whistler(Vector2(-300, -16), 0.0)
	whistler.first_delay = Vector2(30, 30)
	whistler._enter(NelvarWhistler.State.RECOVER, 30.0)
	var bubble := _launch_bubble(Vector2(0, 0), Vector2.RIGHT)
	await _frames(2)
	var wave := WAVE_SCENE.instantiate()
	_world.add_child(wave)
	wave.call("launch", Vector2(30, 0), Vector2.LEFT)
	await _frames(4)
	_check(is_instance_valid(bubble) and bubble.is_deflected(), "The wave did not deflect the bubble")
	if is_instance_valid(bubble):
		_check(bubble.collision_layer == NelvarWhistlerBubble.LAYER_PLAYER_ATTACKS,
			"A deflected bubble is still on the Enemies layer")
		_check(bubble.direction.dot(Vector2.LEFT) > 0.9, "Deflected the wrong way")
	var health := whistler.health
	await _frames(60)
	_check(whistler.health < health, "A deflected bubble did not hurt the Whistler")


func _check_hold_breaks_breath() -> void:
	_fresh_world()
	_add_player(Vector2(300, 16))
	var whistler := _add_whistler(Vector2.ZERO, 0.0)
	await _frames(int((0.05 + whistler.inhale_duration * 0.5) * 60.0))
	_check(whistler._state == NelvarWhistler.State.INHALE, "Not drawing breath yet")
	whistler.apply_hold(1.0)
	await _frames(int(whistler.inhale_duration * 60.0) + 6)
	_check(_bubbles().is_empty(), "Compression did not break off the breath")


func _check_death() -> void:
	_fresh_world()
	var whistler := _add_whistler(Vector2.ZERO, 0.0)
	await _frames(2)
	whistler.take_damage(whistler.max_health)
	_check(not whistler.is_in_group(&"enemies"), "A dead Whistler stays an enemy")
	await _frames(int(whistler.death_duration * 60.0) + 10)
	_check(not is_instance_valid(whistler), "A dead Whistler was not freed")


func _check_spawner_caps() -> void:
	_fresh_world()
	var whistler_kind := NelvarEnemyKind.new()
	whistler_kind.scene = WHISTLER_SCENE
	whistler_kind.weight = 10.0
	whistler_kind.max_alive = 2
	var hopper_kind := NelvarEnemyKind.new()
	hopper_kind.scene = HOPPER_SCENE
	hopper_kind.weight = 1.0
	var spawner := SPAWNER_SCRIPT.new() as Node2D
	spawner.set("auto_start", false)
	spawner.set("enemy_kinds", [whistler_kind, hopper_kind] as Array[NelvarEnemyKind])
	spawner.set("initial_count", 8)
	spawner.set("max_alive", 8)
	spawner.set("spawn_area", Rect2(0, 0, 2000, 2000))
	_world.add_child(spawner)
	spawner.call("start")
	await _frames(2)
	var whistlers := 0
	var hoppers := 0
	for enemy in spawner.get_children():
		if enemy is NelvarWhistler:
			whistlers += 1
		elif enemy.scene_file_path == HOPPER_SCENE.resource_path:
			hoppers += 1
	_check(whistlers == 2, "Spawner made %d Whistlers past their cap" % whistlers)
	_check(hoppers == 6, "Spawner made %d hoppers" % hoppers)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
