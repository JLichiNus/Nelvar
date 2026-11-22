extends CharacterBody2D


signal health_changed(current: float, maximum: float)
signal died

enum SpeedBoostState { READY, ACTIVE, COOLDOWN }

const DEAD_COLOR := Color(0.45, 0.47, 0.5, 1.0)

@export_category("Movement")
@export var base_speed: float = 300.0
@export var run_speed_multiplier: float = 1.5
@export var speed_boost_multiplier: float = 1.5
@export var speed_boost_duration: float = 2.0
@export var speed_boost_cooldown: float = 10.0
@export var flight_height: float = 14.0
@export var flight_lift_duration: float = 0.12
@export var flight_shadow_scale: float = 0.7

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

@export_category("Health")
@export var max_health: float = 100.0
@export var invulnerability_duration: float = 1.0
@export var blink_frequency: float = 10.0
@export var blink_alpha: float = 0.35
@export var death_restart_delay: float = 1.5

var aim_direction := Vector2.RIGHT
var _primary_cooldown_left := 0.0
var _wave_cooldown_left := 0.0
var _compression_cooldown_left := 0.0
var _speed_boost_state := SpeedBoostState.READY
# Ctrl переключает бег/ходьбу; любая атака сбрасывает бег.
var _is_running := false
var health: float
var _invulnerability_left := 0.0
var _is_dead := false
var _flight_tween: Tween

@onready var aim_pivot: Node2D = $AimPivot
@onready var projectile_spawn: Marker2D = $AimPivot/ProjectileSpawn
@onready var boost_duration_timer: Timer = $BoostDuration
@onready var boost_cooldown_timer: Timer = $BoostCooldown
@onready var body_visual: Polygon2D = $Body
@onready var shadow: Polygon2D = $Shadow
@onready var hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	health = max_health
	boost_duration_timer.timeout.connect(_on_boost_duration_timeout)
	boost_cooldown_timer.timeout.connect(_on_boost_cooldown_timeout)


func _process(delta: float) -> void:
	if _is_dead:
		return
	_update_blink()
	_update_aim()
	_primary_cooldown_left = maxf(_primary_cooldown_left - delta, 0.0)
	_wave_cooldown_left = maxf(_wave_cooldown_left - delta, 0.0)
	_compression_cooldown_left = maxf(_compression_cooldown_left - delta, 0.0)

	if Input.is_action_just_pressed("toggle_run"):
		_is_running = not _is_running
	if Input.is_action_pressed("attack_primary"):
		_try_primary_attack()
	if Input.is_action_just_pressed("attack_wave"):
		_try_wave_attack()
	if Input.is_action_just_pressed("speed_boost"):
		_try_speed_boost()
	if Input.is_action_just_pressed("special_compression"):
		_try_compression()


func _update_aim() -> void:
	var mouse_offset := get_global_mouse_position() - global_position
	if mouse_offset.length_squared() > 0.0001:
		aim_direction = mouse_offset.normalized()
		aim_pivot.rotation = aim_direction.angle()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_invulnerability_left = maxf(_invulnerability_left - delta, 0.0)

	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	# Ускорение задаёт фиксированную скорость независимо от бега/ходьбы.
	var speed_multiplier := 1.0
	if _speed_boost_state == SpeedBoostState.ACTIVE:
		speed_multiplier = speed_boost_multiplier
	elif _is_running:
		speed_multiplier = run_speed_multiplier
	velocity = direction * base_speed * speed_multiplier
	move_and_slide()
	# В полёте игрок проходит над врагами и не получает контактного урона.
	if not is_airborne():
		_check_enemy_contact()


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
	body_visual.modulate.a = 1.0
	body_visual.color = DEAD_COLOR
	if _flight_tween != null:
		_flight_tween.kill()
	body_visual.position = Vector2.ZERO
	shadow.visible = false
	aim_pivot.visible = false
	hurtbox.set_deferred("monitoring", false)
	died.emit()
	get_tree().create_timer(death_restart_delay).timeout.connect(
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
	projectile.call("launch", projectile_spawn.global_position, aim_direction)


func _try_wave_attack() -> void:
	if _wave_cooldown_left > 0.0:
		return
	var wave := _instantiate_attack(wave_scene, "ПКМ-волна")
	if wave == null:
		return
	_wave_cooldown_left = wave_cooldown
	_is_running = false
	var wave_origin := global_position + aim_direction * wave_spawn_distance
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
	compression.call("start_compression", target, global_position)


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
		var range_sq := global_position.distance_squared_to(enemy.global_position)
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
	shadow.scale = Vector2.ONE
	shadow.visible = true
	var tween := _restart_flight_tween().set_parallel(true)
	tween.tween_property(
		body_visual,
		"position:y",
		-flight_height,
		flight_lift_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		shadow,
		"scale",
		Vector2.ONE * flight_shadow_scale,
		flight_lift_duration
	)


func _play_landing() -> void:
	var tween := _restart_flight_tween().set_parallel(true)
	tween.tween_property(
		body_visual,
		"position:y",
		0.0,
		flight_lift_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(shadow, "scale", Vector2.ONE, flight_lift_duration)
	tween.chain().tween_callback(shadow.hide)


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
