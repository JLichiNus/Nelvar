extends Area2D


@export var travel_distance: float = 360.0
@export var duration: float = 0.55
@export var fade_duration: float = 0.20
@export var start_size := Vector2(70.0, 24.0)
@export var end_size := Vector2(180.0, 72.0)
@export var damage: float = 8.0
@export var knockback_force: float = 550.0

var direction := Vector2.RIGHT
var _hit_targets: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func launch(
	origin: Vector2,
	launch_direction: Vector2,
	collision_enabled: bool = true
) -> void:
	global_position = origin
	if launch_direction.length_squared() > 0.0001:
		direction = launch_direction.normalized()
	rotation = direction.angle()
	monitoring = collision_enabled
	monitorable = collision_enabled

	var tween := create_tween().set_parallel(true)
	tween.tween_property(
		self,
		"global_position",
		origin + direction * travel_distance,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", end_size / start_size, duration)
	tween.tween_property(
		self,
		"modulate:a",
		0.0,
		minf(fade_duration, duration)
	).set_delay(maxf(duration - fade_duration, 0.0))
	tween.chain().tween_callback(queue_free)


func _on_body_entered(body: Node) -> void:
	_hit(body)


func _on_area_entered(area: Area2D) -> void:
	_hit(area)


func _hit(target: Node) -> void:
	var collision_object := target as CollisionObject2D
	if collision_object == null or collision_object.collision_layer & 8 == 0:
		return
	var target_id := target.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	if target.has_method("take_damage"):
		target.call("take_damage", damage)
	if target.has_method("apply_knockback"):
		target.call("apply_knockback", direction * knockback_force)
