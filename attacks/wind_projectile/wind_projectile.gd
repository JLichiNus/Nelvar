extends Area2D


@export var speed: float = 900.0
@export var damage: float = 5.0
@export var lifetime: float = 2.5

var direction := Vector2.RIGHT

@onready var lifetime_timer: Timer = $Lifetime


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	lifetime_timer.timeout.connect(queue_free)
	lifetime_timer.start(lifetime)


func launch(origin: Vector2, launch_direction: Vector2) -> void:
	global_position = origin
	if launch_direction.length_squared() > 0.0001:
		direction = launch_direction.normalized()
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	_hit(body)


func _on_area_entered(area: Area2D) -> void:
	_hit(area)


func _hit(target: Node) -> void:
	var collision_object := target as CollisionObject2D
	if (
		collision_object != null
		and collision_object.collision_layer & 8 != 0
		and target.has_method("take_damage")
	):
		target.call("take_damage", damage)
	queue_free()
