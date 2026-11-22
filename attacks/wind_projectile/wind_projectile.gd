extends Area2D

# Спрайтшит генерирует tools/gen_attack_sprites.py: колонки — кадры мерцания
# хвоста, строки — направления 0..90°, прочие квадранты получаются
# отражением. Visual не вращается вместе с узлом — пиксели остаются
# ровными и одного размера с пикселями игрока.
const SHEET_TEXEL := 1.5


@export var speed: float = 900.0
@export var damage: float = 5.0
@export var lifetime: float = 2.5
@export var frame_duration: float = 0.07

var direction := Vector2.RIGHT
var _sheet_row := 0
var _anim_time := 0.0
var _visual: Sprite2D

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
	_setup_visual()


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_anim_time += delta
	_update_visual()


func _setup_visual() -> void:
	# launch() может прийти раньше _ready, поэтому без @onready.
	_visual = $Visual
	var row_count := _visual.vframes
	var base_angle := atan2(absf(direction.y), absf(direction.x))
	_sheet_row = clampi(
		roundi(base_angle / (PI * 0.5) * (row_count - 1)), 0, row_count - 1
	)
	_visual.flip_h = direction.x < 0.0
	_visual.flip_v = direction.y < 0.0
	_update_visual()


func _update_visual() -> void:
	if _visual == null:
		return
	var column := int(_anim_time / maxf(frame_duration, 0.01)) % _visual.hframes
	_visual.frame_coords = Vector2i(column, _sheet_row)
	_visual.global_rotation = 0.0
	_visual.global_scale = Vector2(SHEET_TEXEL, SHEET_TEXEL)


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
