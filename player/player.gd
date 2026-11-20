extends CharacterBody2D


enum SpeedBoostState { READY, ACTIVE, COOLDOWN }

@export_category("Movement")
@export var base_speed: float = 300.0
@export var speed_boost_multiplier: float = 1.5
@export var speed_boost_duration: float = 5.0
@export var speed_boost_cooldown: float = 10.0

@export_category("Attacks")
@export var projectile_scene: PackedScene
@export var wave_scene: PackedScene
@export var compression_scene: PackedScene
@export var primary_cooldown: float = 0.20
@export var wave_cooldown: float = 0.80
@export var compression_cooldown: float = 8.0
@export var wave_spawn_distance: float = 53.0
@export var compression_distance: float = 300.0

var aim_direction := Vector2.RIGHT
var _primary_cooldown_left := 0.0
var _wave_cooldown_left := 0.0
var _compression_cooldown_left := 0.0
var _speed_boost_state := SpeedBoostState.READY

@onready var aim_pivot: Node2D = $AimPivot
@onready var projectile_spawn: Marker2D = $AimPivot/ProjectileSpawn
@onready var boost_duration_timer: Timer = $BoostDuration
@onready var boost_cooldown_timer: Timer = $BoostCooldown


func _ready() -> void:
	boost_duration_timer.timeout.connect(_on_boost_duration_timeout)
	boost_cooldown_timer.timeout.connect(_on_boost_cooldown_timeout)


func _process(delta: float) -> void:
	_update_aim()
	_primary_cooldown_left = maxf(_primary_cooldown_left - delta, 0.0)
	_wave_cooldown_left = maxf(_wave_cooldown_left - delta, 0.0)
	_compression_cooldown_left = maxf(_compression_cooldown_left - delta, 0.0)

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

func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	var speed_multiplier := (
		speed_boost_multiplier
		if _speed_boost_state == SpeedBoostState.ACTIVE
		else 1.0
	)
	velocity = direction * base_speed * speed_multiplier
	move_and_slide()


func _try_primary_attack() -> void:
	if _primary_cooldown_left > 0.0:
		return
	var projectile := _instantiate_attack(projectile_scene, "ЛКМ-снаряд")
	if projectile == null:
		return
	_primary_cooldown_left = primary_cooldown
	projectile.call("launch", projectile_spawn.global_position, aim_direction)


func _try_wave_attack() -> void:
	if _wave_cooldown_left > 0.0:
		return
	var wave := _instantiate_attack(wave_scene, "ПКМ-волна")
	if wave == null:
		return
	_wave_cooldown_left = wave_cooldown
	var wave_origin := global_position + aim_direction * wave_spawn_distance
	wave.call("launch", wave_origin, aim_direction)


func _try_speed_boost() -> void:
	if _speed_boost_state != SpeedBoostState.READY:
		return
	_speed_boost_state = SpeedBoostState.ACTIVE
	boost_duration_timer.start(speed_boost_duration)


func _try_compression() -> void:
	if _compression_cooldown_left > 0.0:
		return
	var compression := _instantiate_attack(compression_scene, "R-сжатие")
	if compression == null:
		return
	_compression_cooldown_left = compression_cooldown
	var effect_point := global_position + aim_direction * compression_distance
	compression.call("start_at", effect_point, aim_direction)


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


func _on_boost_duration_timeout() -> void:
	_speed_boost_state = SpeedBoostState.COOLDOWN
	boost_cooldown_timer.start(speed_boost_cooldown)


func _on_boost_cooldown_timeout() -> void:
	_speed_boost_state = SpeedBoostState.READY
