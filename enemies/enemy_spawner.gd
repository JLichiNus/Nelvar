extends Node2D
## Без мира враги появляются в spawn_area (тестовая сцена). Со сгенерированным
## миром (start(world, forest, props)) — на суше в кольце вокруг игрока,
## не в небе, не в стволах деревьев и не в камнях. Другие карты (земляная
## долина) передают start_on(ground): у него есть spawn_position и
## has_clearance(point, radius).


## The only kind when enemy_kinds is empty.
@export var enemy_scene: PackedScene
## Several kinds: each spawn picks one by weight among those below their cap.
@export var enemy_kinds: Array[NelvarEnemyKind] = []
@export var player: Node2D
# false — ждать вызова start(), например пока генерируется мир.
@export var auto_start: bool = true
@export var initial_count: int = 25
@export var max_alive: int = 100
@export var spawn_interval: float = 2.5
@export var min_distance_from_player: float = 450.0
@export var spawn_area := Rect2(80, 80, 3296, 1784)
@export var spawn_attempts: int = 10

@export_category("Generated world")
@export var max_distance_from_player: float = 1100.0
@export var world_spawn_attempts: int = 30
# Свободное место вокруг точки появления (радиус тела врага + запас).
@export var spawn_clearance: float = 28.0
# Лабиринт (у карты есть path_distance(point)): путь пешком от игрока не длиннее
# прямой во столько раз и не длиннее max_path_distance — иначе прыгун окажется
# за стеной в соседнем ходе и не дойдёт.
@export var max_path_ratio: float = 1.6
@export var max_path_distance: float = 1700.0

@export_category("Visual")
@export var appear_duration: float = 0.3

var _spawn_time_left := 0.0
var _world: NelvarWorldData
var _forest: NelvarForestData
var _props: NelvarPropData
## Любая карта со spawn_position и has_clearance(point, radius).
var _ground: Object


func _ready() -> void:
	set_process(false)
	if auto_start:
		start()


func start(world: NelvarWorldData = null, forest: NelvarForestData = null,
		props: NelvarPropData = null) -> void:
	if enemy_scene == null and enemy_kinds.is_empty():
		push_warning("Не назначена сцена врага для спавнера.")
		return
	_world = world
	_forest = forest
	_props = props
	for _i in initial_count:
		_try_spawn()
	_spawn_time_left = spawn_interval
	set_process(true)


func start_on(ground: Object) -> void:
	_ground = ground
	start()


func _process(delta: float) -> void:
	_spawn_time_left -= delta
	if _spawn_time_left > 0.0:
		return
	_spawn_time_left = spawn_interval
	_try_spawn()


func _try_spawn() -> void:
	if _alive_count() >= max_alive:
		return
	var scene := _pick_scene()
	if scene == null:
		return
	var point: Variant = _pick_spawn_point()
	if point == null:
		return
	var enemy := scene.instantiate() as Node2D
	if enemy == null:
		push_warning("Сцена врага должна начинаться с Node2D.")
		return
	enemy.position = to_local(point)
	# Карта с опасной землёй (кузня) подсказывает врагу, куда не прыгать.
	if _ground != null and _ground.has_method("is_safe_landing") and "ground" in enemy:
		enemy.set("ground", _ground)
	add_child(enemy)
	if enemy.has_method("play_spawn_animation"):
		enemy.call("play_spawn_animation", appear_duration)


func _pick_scene() -> PackedScene:
	if enemy_kinds.is_empty():
		return enemy_scene
	var alive := {}
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var path: String = enemy.scene_file_path
		alive[path] = int(alive.get(path, 0)) + 1
	var open: Array[NelvarEnemyKind] = []
	var total := 0.0
	for kind in enemy_kinds:
		if kind == null or kind.scene == null or kind.weight <= 0.0:
			continue
		if kind.max_alive > 0 and int(alive.get(kind.scene.resource_path, 0)) >= kind.max_alive:
			continue
		open.append(kind)
		total += kind.weight
	var roll := randf() * total
	for kind in open:
		roll -= kind.weight
		if roll <= 0.0:
			return kind.scene
	return open.back().scene if not open.is_empty() else null


func _alive_count() -> int:
	# Мёртвый враг сразу выходит из группы, поэтому его место освобождается.
	return get_tree().get_nodes_in_group("enemies").size()


func _pick_spawn_point() -> Variant:
	if _world != null or _ground != null:
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
	var center: Vector2 = _world.spawn_position if _world != null else _ground.get("spawn_position")
	if is_instance_valid(player):
		center = player.global_position
	var max_distance := maxf(max_distance_from_player, min_distance_from_player)
	for _attempt in maxi(world_spawn_attempts, 1):
		var point := center + Vector2.from_angle(randf() * TAU) \
			* randf_range(min_distance_from_player, max_distance)
		if _world != null and not _world.has_clearance(point, spawn_clearance):
			continue
		if _ground != null and not _ground.call("has_clearance", point, spawn_clearance):
			continue
		if _ground != null and _ground.has_method("path_distance") and is_instance_valid(player):
			var walk: float = _ground.call("path_distance", point)
			if walk > max_path_distance or walk > point.distance_to(player.global_position) * max_path_ratio:
				continue
		if _forest != null and not _forest.has_clearance(point, spawn_clearance):
			continue
		if _props != null and not _props.has_clearance(point, spawn_clearance):
			continue
		return point
	return null
