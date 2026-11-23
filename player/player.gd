class_name NelvarPlayer
extends CharacterBody2D
## Элементаль ветра «Вихрь»: торс с парящими кулаками, вместо ног — смерч.
## Начало координат — точка на земле под смерчем: по ней идут Y-сортировка
## с деревьями и коллизия с миром. Прицел и атаки считаются от уровня
## кулаков (AimPivot).


signal health_changed(current: float, maximum: float)
signal died

enum SpeedBoostState { READY, ACTIVE, COOLDOWN }

# Радиус круга-«следа» под ногами; на него опираются проверки мира и спавн.
const BODY_RADIUS := 14.0
const DEAD_COLOR := Color(0.45, 0.47, 0.5, 1.0)
# Анимация атаки с большим приоритетом не прерывается меньшей.
const ATTACK_PRIORITY := {
	&"attack_primary": 1,
	&"attack_wave": 2,
	&"attack_compression": 3,
}

@export_category("Movement")
@export var speed: float = 300.0
# Элементаль скользит: разгоняется и тормозит не мгновенно, но быстро.
@export var acceleration: float = 2400.0
@export var deceleration: float = 2000.0
@export var run_speed_multiplier: float = 1.5
@export var speed_boost_multiplier: float = 1.5
@export var speed_boost_duration: float = 2.0
@export var speed_boost_cooldown: float = 10.0
@export var flight_height: float = 14.0
@export var flight_lift_duration: float = 0.12
# Покачивание корпуса над смерчем: на сколько текселей и с каким периодом.
@export var hover_bob_texels: float = 1.0
@export var hover_bob_period: float = 1.3

@export_category("Attacks")
@export var projectile_scene: PackedScene
@export var wave_scene: PackedScene
@export var compression_scene: PackedScene
@export var primary_cooldown: float = 0.20
@export var wave_cooldown: float = 0.80
@export var compression_cooldown: float = 8.0
@export var wave_spawn_distance: float = 53.0
@export var compression_max_range: float = 650.0
@export var compression_target_radius: float = 140.0
# Сколько персонаж ещё смотрит на курсор после атаки — без этого при зажатой
# ЛКМ спиной вперёд он дёргался бы между выстрелами.
@export var attack_facing_hold: float = 0.25

@export_category("Health")
@export var max_health: float = 100.0
@export var invulnerability_duration: float = 1.0
@export var blink_frequency: float = 10.0
@export var blink_alpha: float = 0.35
@export var death_restart_delay: float = 1.5

@export_category("Camera")
@export var zoom_min: float = 0.18
@export var zoom_max: float = 1.6

var aim_direction := Vector2.RIGHT
var _primary_cooldown_left := 0.0
var _wave_cooldown_left := 0.0
var _compression_cooldown_left := 0.0
var _speed_boost_state := SpeedBoostState.READY
# Ctrl переключает бег/ходьбу; любая атака или остановка сбрасывает бег.
var _is_running := false
var health: float
var _invulnerability_left := 0.0
var _is_dead := false
var _flight_tween: Tween
# Масштаб спрайта при взгляде вправо; взгляд влево — отрицательный scale.x.
var _body_scale := Vector2.ONE
# Положение тела на земле; полёт поднимает его на flight_height выше.
var _body_rest_position := Vector2.ZERO
var _facing_left := false
# Текущая анимация атаки корпуса; пусто — корпус повторяет локомоцию ног.
var _attack_animation := &""
var _attack_facing_left := 0.0
var _hover_time := 0.0

@onready var aim_pivot: Node2D = $AimPivot
@onready var projectile_spawn: Marker2D = $AimPivot/ProjectileSpawn
@onready var boost_duration_timer: Timer = $BoostDuration
@onready var boost_cooldown_timer: Timer = $BoostCooldown
@onready var body_visual: Node2D = $Body
@onready var vortex_sprite: AnimatedSprite2D = $Body/Vortex
@onready var torso_sprite: AnimatedSprite2D = $Body/Torso
@onready var wind_trail: CPUParticles2D = $WindTrail
@onready var hurtbox: Area2D = $Hurtbox
@onready var camera: Camera2D = $Camera2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	health = max_health
	(collision_shape.shape as CircleShape2D).radius = BODY_RADIUS
	_body_scale = body_visual.scale.abs()
	_body_rest_position = body_visual.position
	torso_sprite.animation_finished.connect(_on_torso_animation_finished)
	boost_duration_timer.timeout.connect(_on_boost_duration_timeout)
	boost_cooldown_timer.timeout.connect(_on_boost_cooldown_timeout)


func _process(delta: float) -> void:
	if _is_dead:
		return
	_update_blink()
	_update_hover(delta)
	_update_aim()
	_primary_cooldown_left = maxf(_primary_cooldown_left - delta, 0.0)
	_wave_cooldown_left = maxf(_wave_cooldown_left - delta, 0.0)
	_compression_cooldown_left = maxf(_compression_cooldown_left - delta, 0.0)

	# Стоя на месте Ctrl ничего не делает.
	if Input.is_action_just_pressed("toggle_run") and _is_move_input_held():
		_is_running = not _is_running
	if Input.is_action_pressed("attack_primary"):
		_try_primary_attack()
	if Input.is_action_just_pressed("attack_wave"):
		_try_wave_attack()
	if Input.is_action_just_pressed("speed_boost"):
		_try_speed_boost()
	if Input.is_action_just_pressed("special_compression"):
		_try_compression()


func _is_move_input_held() -> bool:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO


# Корпус парит над смерчем, покачиваясь на целый тексель — пиксели
# остаются на сетке. Смерч не качается: его кончик касается земли.
func _update_hover(delta: float) -> void:
	_hover_time = fmod(_hover_time + delta, hover_bob_period)
	var up := sin(_hover_time / hover_bob_period * TAU) > 0.0
	torso_sprite.position.y = -hover_bob_texels if up else 0.0


func _update_aim() -> void:
	var mouse_offset := get_global_mouse_position() - get_aim_origin()
	if mouse_offset.length_squared() > 0.0001:
		aim_direction = mouse_offset.normalized()
		aim_pivot.rotation = aim_direction.angle()


# Центр тела, от которого целятся и вылетают атаки.
func get_aim_origin() -> Vector2:
	return aim_pivot.global_position


func adjust_zoom(multiplier: float) -> void:
	var value := clampf(camera.zoom.x * multiplier, zoom_min, zoom_max)
	camera.zoom = Vector2.ONE * value


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_invulnerability_left = maxf(_invulnerability_left - delta, 0.0)
	_attack_facing_left = maxf(_attack_facing_left - delta, 0.0)

	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	# Бег возможен только в движении: остановка его сбрасывает.
	if direction == Vector2.ZERO:
		_is_running = false

	# Ускорение задаёт фиксированную скорость независимо от бега/ходьбы.
	var speed_multiplier := 1.0
	if _speed_boost_state == SpeedBoostState.ACTIVE:
		speed_multiplier = speed_boost_multiplier
	elif _is_running:
		speed_multiplier = run_speed_multiplier
	var target_velocity := direction * speed * speed_multiplier
	var rate := acceleration if direction != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(target_velocity, rate * delta)
	move_and_slide()
	_update_animation(direction)
	# В полёте игрок проходит над врагами и не получает контактного урона.
	if not is_airborne():
		_check_enemy_contact()


# Спрайт из двух слоёв: смерч всегда играет локомоцию, корпус — локомоцию
# синхронно со смерчем или анимацию атаки поверх неё.
# Во время атаки персонаж смотрит на курсор, иначе — по ходу движения
# (а без горизонтального движения — тоже на курсор).
func _update_animation(direction: Vector2) -> void:
	var facing_aim := _attack_animation != &"" or _attack_facing_left > 0.0
	var facing_x := aim_direction.x if facing_aim else direction.x
	if absf(facing_x) < 0.01:
		facing_x = aim_direction.x
	if absf(facing_x) >= 0.01:
		_facing_left = facing_x < 0.0
	body_visual.scale = Vector2(
		-_body_scale.x if _facing_left else _body_scale.x,
		_body_scale.y
	)

	var locomotion := &"idle"
	if is_airborne():
		locomotion = &"fly"
	elif direction != Vector2.ZERO:
		locomotion = &"run" if _is_running else &"walk"
	# Хвост смерча тянется против хода: спиной вперёд (атака против хода)
	# смерч играет *_back с хвостом в другую сторону, а корпус не
	# наклоняется вперёд и играет idle.
	var moving_backwards := (
		locomotion != &"idle"
		and absf(direction.x) >= 0.01
		and (direction.x < 0.0) != _facing_left
	)
	var vortex_animation := locomotion
	var torso_locomotion := locomotion
	if moving_backwards:
		vortex_animation = StringName(String(locomotion) + "_back")
		torso_locomotion = &"idle"
	if vortex_sprite.animation != vortex_animation:
		# Кадров у всех анимаций смерча поровну — продолжаем с того же
		# кадра, чтобы вращение не дёргалось при смене анимации.
		var frame := vortex_sprite.frame
		var progress := vortex_sprite.frame_progress
		vortex_sprite.play(vortex_animation)
		vortex_sprite.set_frame_and_progress(frame, progress)
	wind_trail.emitting = (
		direction != Vector2.ZERO
		and (locomotion == &"run" or locomotion == &"fly")
	)

	if _attack_animation != &"":
		return
	if torso_sprite.animation != torso_locomotion:
		torso_sprite.play(torso_locomotion)
	torso_sprite.set_frame_and_progress(
		vortex_sprite.frame,
		vortex_sprite.frame_progress
	)


func _play_attack_animation(animation_name: StringName) -> void:
	_attack_facing_left = attack_facing_hold
	if _attack_animation != &"" \
			and ATTACK_PRIORITY[_attack_animation] > ATTACK_PRIORITY[animation_name]:
		return
	_attack_animation = animation_name
	torso_sprite.play(animation_name)
	# play() не перезапускает ту же анимацию, если она ещё не доиграла.
	torso_sprite.set_frame_and_progress(0, 0.0)


func _on_torso_animation_finished() -> void:
	if torso_sprite.animation == _attack_animation:
		_attack_animation = &""


func is_airborne() -> bool:
	return _speed_boost_state == SpeedBoostState.ACTIVE


func take_damage(amount: float) -> void:
	if _is_dead or is_airborne() or _invulnerability_left > 0.0 \
			or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()
		return
	_invulnerability_left = invulnerability_duration


func _check_enemy_contact() -> void:
	# Опрос каждый кадр: стоящий внутри врага игрок получает урон раз в
	# invulnerability_duration, а не только при входе.
	if _invulnerability_left > 0.0:
		return
	for body in hurtbox.get_overlapping_bodies():
		if body.is_in_group("enemies") and "contact_damage" in body:
			take_damage(body.get("contact_damage"))
			return


func _update_blink() -> void:
	if _invulnerability_left <= 0.0:
		body_visual.modulate.a = 1.0
		return
	var phase := int(_invulnerability_left * blink_frequency * 2.0)
	body_visual.modulate.a = 1.0 if phase % 2 == 0 else blink_alpha


func _die() -> void:
	_is_dead = true
	_invulnerability_left = 0.0
	velocity = Vector2.ZERO
	body_visual.modulate = DEAD_COLOR
	_attack_animation = &""
	for sprite: AnimatedSprite2D in [vortex_sprite, torso_sprite]:
		sprite.play(&"idle")
		sprite.stop()
	torso_sprite.position.y = 0.0
	wind_trail.emitting = false
	if _flight_tween != null:
		_flight_tween.kill()
	body_visual.position = _body_rest_position
	aim_pivot.visible = false
	hurtbox.set_deferred("monitoring", false)
	died.emit()
	get_tree().create_timer(death_restart_delay, false).timeout.connect(
		_restart_scene
	)


func _restart_scene() -> void:
	get_tree().reload_current_scene()


func _try_primary_attack() -> void:
	if _primary_cooldown_left > 0.0:
		return
	var projectile := _instantiate_attack(projectile_scene, "ЛКМ-снаряд")
	if projectile == null:
		return
	_primary_cooldown_left = primary_cooldown
	_is_running = false
	_play_attack_animation(&"attack_primary")
	projectile.call("launch", projectile_spawn.global_position, aim_direction)


func _try_wave_attack() -> void:
	if _wave_cooldown_left > 0.0:
		return
	var wave := _instantiate_attack(wave_scene, "ПКМ-волна")
	if wave == null:
		return
	_wave_cooldown_left = wave_cooldown
	_is_running = false
	_play_attack_animation(&"attack_wave")
	var wave_origin := get_aim_origin() + aim_direction * wave_spawn_distance
	wave.call("launch", wave_origin, aim_direction)


func _try_speed_boost() -> void:
	if _speed_boost_state != SpeedBoostState.READY:
		return
	_speed_boost_state = SpeedBoostState.ACTIVE
	boost_duration_timer.start(speed_boost_duration)
	_play_lift_off()


func _try_compression() -> void:
	if _compression_cooldown_left > 0.0:
		return
	# Без цели способность не срабатывает и кулдаун не тратится.
	var target := _find_compression_target()
	if target == null:
		return
	var compression := _instantiate_attack(compression_scene, "R-сжатие")
	if compression == null:
		return
	_compression_cooldown_left = compression_cooldown
	_is_running = false
	_play_attack_animation(&"attack_compression")
	compression.call("start_compression", target, get_aim_origin())


# Ближайший к курсору враг в пределах compression_target_radius от курсора
# и compression_max_range от игрока.
func _find_compression_target() -> Node2D:
	var cursor := get_global_mouse_position()
	var max_range_sq := compression_max_range * compression_max_range
	var best_distance_sq := compression_target_radius * compression_target_radius
	var best: Node2D = null
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null:
			continue
		var range_sq := get_aim_origin().distance_squared_to(enemy.global_position)
		if range_sq > max_range_sq:
			continue
		var distance_sq := cursor.distance_squared_to(enemy.global_position)
		if distance_sq <= best_distance_sq:
			best_distance_sq = distance_sq
			best = enemy
	return best


func _instantiate_attack(scene: PackedScene, attack_name: String) -> Node:
	if scene == null:
		push_warning("Не назначена сцена атаки: %s." % attack_name)
		return null
	var attack := scene.instantiate()
	var world := get_tree().current_scene
	if world == null:
		push_warning("Невозможно создать %s: текущая сцена отсутствует." % attack_name)
		attack.free()
		return null
	world.add_child(attack)
	return attack


func _play_lift_off() -> void:
	_restart_flight_tween().tween_property(
		body_visual,
		"position:y",
		_body_rest_position.y - flight_height,
		flight_lift_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_landing() -> void:
	_restart_flight_tween().tween_property(
		body_visual,
		"position:y",
		_body_rest_position.y,
		flight_lift_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _restart_flight_tween() -> Tween:
	if _flight_tween != null:
		_flight_tween.kill()
	_flight_tween = create_tween()
	return _flight_tween


func _on_boost_duration_timeout() -> void:
	_speed_boost_state = SpeedBoostState.COOLDOWN
	boost_cooldown_timer.start(speed_boost_cooldown)
	if not _is_dead:
		_play_landing()


func _on_boost_cooldown_timeout() -> void:
	_speed_boost_state = SpeedBoostState.READY
