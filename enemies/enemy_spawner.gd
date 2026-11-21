extends Node2D


@export var enemy_scene: PackedScene
@export var player: Node2D
@export var initial_count: int = 5
@export var max_alive: int = 10
@export var spawn_interval: float = 2.5
@export var min_distance_from_player: float = 450.0
@export var spawn_area := Rect2(80, 80, 3296, 1784)
@export var spawn_attempts: int = 10
@export var appear_duration: float = 0.3

var _spawn_time_left := 0.0


func _ready() -> void:
	if enemy_scene == null:
		push_warning("Не назначена сцена врага для спавнера.")
		set_process(false)
		return
	for _i in initial_count:
		_try_spawn()
	_spawn_time_left = spawn_interval


func _process(delta: float) -> void:
	_spawn_time_left -= delta
	if _spawn_time_left > 0.0:
		return
	_spawn_time_left = spawn_interval
	_try_spawn()


func _try_spawn() -> void:
	if _alive_count() >= max_alive:
		return
	var point: Variant = _pick_spawn_point()
	if point == null:
		return
	var enemy := enemy_scene.instantiate() as Node2D
	if enemy == null:
		push_warning("Сцена врага должна начинаться с Node2D.")
		return
	enemy.position = to_local(point)
	add_child(enemy)
	if enemy.has_method("play_spawn_animation"):
		enemy.call("play_spawn_animation", appear_duration)


func _alive_count() -> int:
	# Мёртвый враг сразу выходит из группы, поэтому его место освобождается.
	return get_tree().get_nodes_in_group("enemies").size()


func _pick_spawn_point() -> Variant:
	for _attempt in maxi(spawn_attempts, 1):
		var point := Vector2(
			randf_range(spawn_area.position.x, spawn_area.end.x),
			randf_range(spawn_area.position.y, spawn_area.end.y)
		)
		if (
			not is_instance_valid(player)
			or point.distance_to(player.global_position) >= min_distance_from_player
		):
			return point
	return null
