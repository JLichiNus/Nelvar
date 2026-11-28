extends Area2D

# Спрайтшит генерирует tools/gen_attack_sprites.py: колонки — кадры расширения,
# строки — направления 0..90°, прочие квадранты получаются отражением.
# Кадры уже нарисованы нужного размера, поэтому Visual не масштабируется
# и не вращается вместе с узлом — пиксели остаются ровными и одного размера
# с пикселями игрока. При смене duration/start_size/end_size — перегенерировать.
const SHEET_TEXEL := 3.0
## Радиус дуги в локальных координатах узла (CollisionPolygon2D) и полуугол
## серпа — с его задней кромки срываются клочья воздуха.
const ARC_RADIUS := 35.0
const ARC_HALF_ANGLE := deg_to_rad(66.0)
## Клочьев в секунду и до какой доли полёта они срываются (потом серп тает).
const AIR_RATE := 190.0
const AIR_UNTIL := 0.8
const TRAIL_SCRIPT := preload("res://attacks/wind_projectile/wind_projectile_trail.gd")


@export var travel_distance: float = 360.0
@export var duration: float = 0.55
@export var fade_duration: float = 0.10  # текстура сама рассыпается, это лишь добивка
@export var start_size := Vector2(70.0, 70.0)
@export var end_size := Vector2(180.0, 180.0)
## Set by the player at launch from its base damage (wave_damage_percent).
@export var damage: float = 8.0
@export var knockback_force: float = 550.0
## Mutations grow or shrink the wave. The sprite stays on whole texels, so
## the size snaps to multiples of 1/SHEET_TEXEL (4/3, 5/3, 2/3...).
@export var size_multiplier: float = 1.0
## Where the player stood when they cast it: on a map with walls that block sight
## (NelvarPlayer.sight_mask) it only reaches enemies seen from there. INF: no check.
var sight_from := Vector2.INF

var direction := Vector2.RIGHT
var _hit_targets: Dictionary = {}
var _sheet_row := 0
var _visual: Sprite2D
## Клочья воздуха, сорванные волной; дотаивают и после неё.
var _air: WindProjectileTrail
var _air_carry := 0.0
var _last_progress := 0.0


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
	var size := _snapped_size()
	scale = Vector2.ONE * size
	modulate.a = 1.0
	_hit_targets.clear()
	_setup_visual()
	_setup_air()
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
		end_size / start_size * size,
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
	tween.chain().tween_callback(_finish)


# Воздух — сосед волны, а не ребёнок: волна исчезает, а сорванные клочья
# дотаивают сами. Добавлен перед волной, поэтому рисуется под ней.
func _setup_air() -> void:
	var parent := get_parent()
	if parent == null or _air != null:
		return
	_air = TRAIL_SCRIPT.new()
	_air.lifetime = Vector2(0.22, 0.45)
	_air.curl_radius = 3.2
	parent.add_child(_air)
	parent.move_child(_air, get_index())


# Клочья срываются с задней кромки серпа, чаще у кончиков, и уносятся
# назад и прочь от оси — за волной остаётся рваное облачко завитков.
func _emit_air(progress: float) -> void:
	var step := progress - _last_progress
	_last_progress = progress
	if _air == null or not is_instance_valid(_air) or progress > AIR_UNTIL:
		return
	_air_carry += step * duration * AIR_RATE
	while _air_carry >= 1.0:
		_air_carry -= 1.0
		var side := 1.0 if randf() < 0.5 else -1.0
		var angle := ARC_HALF_ANGLE * sqrt(randf()) * side
		var at := to_global(Vector2.from_angle(angle) * ARC_RADIUS * randf_range(0.8, 0.95))
		var away := direction.orthogonal() * -side
		var velocity := (
			-direction * randf_range(40.0, 120.0)
			+ away * randf_range(30.0, 110.0) * absf(angle) / ARC_HALF_ANGLE
		)
		_air.emit_puff(at, velocity, direction)


func _finish() -> void:
	if _air != null and is_instance_valid(_air):
		_air.release(global_position, direction, 0)
	queue_free()


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
	var texel := SHEET_TEXEL * _snapped_size()
	_visual.global_scale = Vector2(texel, texel)
	_emit_air(progress)


func _snapped_size() -> float:
	return maxf(roundf(SHEET_TEXEL * size_multiplier), 1.0) / SHEET_TEXEL


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
	# Behind a wall: out of reach.
	if sight_from.is_finite() and target is Node2D \
			and not NelvarPlayer.sight_clear(get_world_2d(), sight_from, (target as Node2D).global_position):
		return
	_hit_targets[target_id] = true
	# Enemy projectiles that can be turned back (a Whistler's bubble) are sent
	# the way the wave goes instead of being hit.
	if target.has_method("deflect"):
		target.call("deflect", direction)
		return
	if target.has_method("take_damage"):
		target.call("take_damage", damage)
	if target.has_method("apply_knockback"):
		target.call("apply_knockback", direction * knockback_force)
