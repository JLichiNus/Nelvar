extends Area2D

# Спрайтшит генерирует tools/gen_attack_sprites.py: колонки — кадры расширения,
# строки — направления 0..90°, прочие квадранты получаются отражением.
# Кадры уже нарисованы нужного размера, поэтому Visual не масштабируется
# и не вращается вместе с узлом — пиксели остаются ровными и одного размера
# с пикселями игрока. При смене duration/start_size/end_size — перегенерировать.
const SHEET_TEXEL := 3.0


@export var travel_distance: float = 360.0
@export var duration: float = 0.55
@export var fade_duration: float = 0.10  # текстура сама рассыпается, это лишь добивка
@export var start_size := Vector2(70.0, 70.0)
@export var end_size := Vector2(180.0, 180.0)
## Set by the player at launch from its base damage (wave_damage_percent).
@export var damage: float = 8.0
@export var knockback_force: float = 550.0

var direction := Vector2.RIGHT
var _hit_targets: Dictionary = {}
var _sheet_row := 0
var _visual: Sprite2D


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
	scale = Vector2.ONE
	modulate.a = 1.0
	_hit_targets.clear()
	_setup_visual()
	monitoring = collision_enabled
	monitorable = collision_enabled

	var tween := create_tween().set_parallel(true)
	tween.tween_property(
		self,
		"global_position",
		origin + direction * travel_distance,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self,
		"scale",
		end_size / start_size,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self,
		"modulate:a",
		0.0,
		minf(fade_duration, duration)
	).set_delay(maxf(duration - fade_duration, 0.0))
	# Последним в том же tween — чтобы спрайт брал уже обновлённый масштаб узла.
	tween.tween_method(_update_visual, 0.0, 1.0, duration)
	tween.chain().tween_callback(queue_free)


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
	_update_visual(0.0)


func _update_visual(progress: float) -> void:
	var column := mini(int(progress * _visual.hframes), _visual.hframes - 1)
	_visual.frame_coords = Vector2i(column, _sheet_row)
	_visual.global_rotation = 0.0
	_visual.global_scale = Vector2(SHEET_TEXEL, SHEET_TEXEL)


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
