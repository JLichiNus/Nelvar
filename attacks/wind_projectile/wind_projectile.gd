extends Area2D

# Спрайтшит генерирует tools/gen_attack_sprites.py: колонки — кадры завитка
# внутри шарика, строки — направления 0..90°, прочие квадранты получаются
# отражением. Visual не вращается вместе с узлом — пиксели остаются
# ровными и одного размера с пикселями игрока.
const SHEET_TEXEL := 3.0
const TRAIL_SCRIPT := preload("res://attacks/wind_projectile/wind_projectile_trail.gd")
## Частицы, разлетающиеся при попадании и при исчезновении в конце полёта.
const HIT_BURST := 7
const FADE_BURST := 4


@export var speed: float = 900.0
## Set by the player at launch from its base damage (primary_damage_percent).
@export var damage: float = 5.0
@export var lifetime: float = 2.5
@export var frame_duration: float = 0.07

## Enemies the projectile flies through before it stops (mutations).
@export var pierce: int = 0

var direction := Vector2.RIGHT
var _hit_targets: Dictionary = {}
var _sheet_row := 0
var _anim_time := 0.0
var _visual: Sprite2D
var _trail: WindProjectileTrail
var _finished := false

@onready var lifetime_timer: Timer = $Lifetime


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	lifetime_timer.timeout.connect(_finish.bind(FADE_BURST))
	lifetime_timer.start(lifetime)


func launch(origin: Vector2, launch_direction: Vector2) -> void:
	global_position = origin
	if launch_direction.length_squared() > 0.0001:
		direction = launch_direction.normalized()
	rotation = direction.angle()
	_setup_visual()
	_setup_trail()


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_anim_time += delta
	_update_visual()
	if _trail != null:
		_trail.follow(global_position, direction)


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


# Шлейф — сосед снаряда, а не ребёнок: после попадания он дотаивает сам.
# Добавлен перед снарядом, поэтому рисуется под шариком.
func _setup_trail() -> void:
	var parent := get_parent()
	if parent == null or _trail != null:
		return
	_trail = TRAIL_SCRIPT.new()
	parent.add_child(_trail)
	parent.move_child(_trail, get_index())
	_trail.follow(global_position, direction)


func _finish(burst: int) -> void:
	if _finished:
		return
	_finished = true
	if _trail != null and is_instance_valid(_trail):
		_trail.release(global_position, direction, burst)
	queue_free()


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
	var is_enemy := (
		collision_object != null
		and collision_object.collision_layer & 8 != 0
		and target.has_method("take_damage")
	)
	if not is_enemy:
		_finish(HIT_BURST)
		return
	var target_id := target.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	target.call("take_damage", damage)
	if pierce <= 0:
		_finish(HIT_BURST)
		return
	pierce -= 1
