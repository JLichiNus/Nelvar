extends Node2D


@export var wave_scene: PackedScene
@export var side_offset: float = 180.0
@export var duration: float = 0.65
@export var fade_duration: float = 0.20


func start_at(effect_point: Vector2, facing_direction: Vector2) -> void:
	global_position = effect_point
	if wave_scene == null:
		push_warning("Не назначена сцена волны для R-сжатия.")
		queue_free()
		return

	var facing := facing_direction.normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.RIGHT
	var perpendicular := facing.orthogonal()
	for side: float in [-1.0, 1.0]:
		var wave = wave_scene.instantiate()
		get_parent().add_child(wave)
		wave.set("travel_distance", side_offset)
		wave.set("duration", duration)
		wave.set("fade_duration", fade_duration)
		var origin := effect_point + perpendicular * side_offset * side
		wave.call("launch", origin, -perpendicular * side, false)

	get_tree().create_timer(duration + 0.05).timeout.connect(queue_free)


func start_compression(target: Node2D) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	start_at(target.global_position, Vector2.RIGHT)
