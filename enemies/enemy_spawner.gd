extends Node2D
## Без мира враги появляются в spawn_area (тестовая сцена). Со сгенерированным
## миром (start(world, forest)) — на суше в кольце вокруг игрока,
## не в воде и не в стволах деревьев.


@export var enemy_scene: PackedScene
@export var player: Node2D
# false — ждать вызова start(), например пока генерируется мир.
@export var auto_start: bool = true
@export var initial_count: int = 5
@export var max_alive: int = 10
@export var spawn_interval: float = 2.5
@export var min_distance_from_player: float = 450.0
@export var spawn_area := Rect2(80, 80, 3296, 1784)
@export var spawn_attempts: int = 10

@export_category("Generated world")
@export var max_distance_from_player: float = 1100.0
@export var world_spawn_attempts: int = 30
# Свободное место вокруг точки появления (радиус тела врага + запас).
@export var spawn_clearance: float = 28.0

@export_category("Visual")
@export var appear_duration: float = 0.3

var _spawn_time_left := 0.0
var _world: NelvarWorldData
var _forest: NelvarForestData


func _ready() -> void:
	set_process(false)
	if auto_start:
		start()


func start(world: NelvarWorldData = null, forest: NelvarForestData = null) -> void:
	if enemy_scene == null:
		push_warning("Не назначена сцена врага для спавнера.")
		return
	_world = world
	_forest = forest
	for _i in initial_count:
		_try_spawn()
	_spawn_time_left = spawn_interval
	set_process(true)


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
	if _world != null:
		return _pick_world_spawn_point()
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


func _pick_world_spawn_point() -> Variant:
	var center := _world.spawn_position
	if is_instance_valid(player):
		center = player.global_position
	var max_distance := maxf(max_distance_from_player, min_distance_from_player)
	for _attempt in maxi(world_spawn_attempts, 1):
		var point := center + Vector2.from_angle(randf() * TAU) \
			* randf_range(min_distance_from_player, max_distance)
		if not _world.has_clearance(point, spawn_clearance):
			continue
		if _forest != null and not _forest.has_clearance(point, spawn_clearance):
			continue
		return point
	return null
