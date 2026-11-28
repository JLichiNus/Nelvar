class_name NelvarPlayer
extends CharacterBody2D
## Элементаль ветра «Вихрь»: торс с парящими кулаками, вместо ног — смерч.
## Начало координат — точка на земле под смерчем: по ней идут Y-сортировка
## с деревьями и коллизия с миром. Прицел и атаки считаются от уровня
## кулаков (AimPivot).


signal health_changed(current: float, maximum: float)
signal died
## Health was lost; `from` is the world point of the source, INF when unknown.
signal damaged(amount: float, from: Vector2)
## Level or kills toward the next one changed.
signal level_changed(level: int, kills: int, kills_needed: int)
## An enemy died to the player (feeds the adaptation meter).
signal enemy_killed

enum SpeedBoostState { READY, ACTIVE, COOLDOWN }

# Радиус круга-«следа» под ногами; на него опираются проверки мира и спавн.
const BODY_RADIUS := 14.0
# Номер слоя мелких валунов (NelvarProp.LOW_OBSTACLE_LAYER) для set_collision_mask_value.
const LOW_OBSTACLE_LAYER_NUMBER := 6
const DEAD_COLOR := Color(0.45, 0.47, 0.5, 1.0)
## "Low health" for mutations that wake up near death: below this share.
const LOW_HEALTH_SHARE := 0.3
## Extra projectiles of one shot spread in a fan this many degrees apart.
const FAN_STEP_DEGREES := 9.0
## Standing still for mutations: slower than this counts as not moving.
const STILL_SPEED := 12.0
## The shot wind holds its strength this long past the time the next shot is
## due, so a held LMB never lets it dip between shots...
const SHOT_WIND_HOLD_SLACK := 0.05
## ...and never shorter than this, so even a single shot lets the wind swell
## to (almost) its full volume: a tap sounds as loud as a held burst.
const SHOT_WIND_MIN_HOLD := 0.25
## Below this level (about -46 dB under full) the shot wind is cut off.
const SHOT_WIND_SILENT := 0.005
## Time constants (s) of the flight rush easing in after take-off and out on
## landing.
const FLIGHT_AIR_RISE := 0.15
const FLIGHT_AIR_RELEASE := 0.12
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
@export var speed_boost_duration: float = 3.0
## Counted from landing, after the flight itself.
@export var speed_boost_cooldown: float = 7.0
@export var flight_height: float = 14.0
@export var flight_lift_duration: float = 0.12
# Покачивание корпуса над смерчем: на сколько текселей и с каким периодом.
@export var hover_bob_texels: float = 1.0
@export var hover_bob_period: float = 1.3
## Share of the usual steering left while thrown through the air (launch()).
@export var launch_control: float = 0.35

@export_category("Attacks")
@export var projectile_scene: PackedScene
@export var wave_scene: PackedScene
@export var compression_scene: PackedScene
@export var primary_cooldown: float = 0.20
## Each shot leaves up to this many degrees off the aim, either side.
@export var primary_spread_degrees: float = 4.0
@export var wave_cooldown: float = 3.0
@export var compression_cooldown: float = 8.0
@export var wave_spawn_distance: float = 53.0
@export var compression_max_range: float = 650.0
@export var compression_target_radius: float = 140.0
# Сколько персонаж ещё смотрит на курсор после атаки — без этого при зажатой
# ЛКМ спиной вперёд он дёргался бы между выстрелами.
@export var attack_facing_hold: float = 0.25
## LMB has no sound per shot: every shot keeps up a wind that dies down
## without them, so a tap is a short breath of wind and held LMB one steady
## wind (five separate sounds a second would wear the ear out). Every shot
## brings it to the same volume — firing faster only makes it last:
@export var shot_wind_volume_db: float = -24.0
## Seconds for the wind to die down without shots.
@export var shot_wind_fade: float = 0.12
## Time constants (s) of the heard level easing towards the strength: it
## swells in and drifts away instead of switching on and off.
@export var shot_wind_rise: float = 0.12
@export var shot_wind_release: float = 0.1
## Flight (Shift): the air rushing past while airborne. Volume at full speed;
## hovering in place it is this much quieter (dB).
@export var flight_air_volume_db: float = -29.0
@export var flight_air_still_db: float = 8.0

@export_category("Damage")
## Base damage at level 1; every level adds base_damage_per_level. Attacks deal
## a percentage of it (RoR2-style).
@export var base_damage_start: float = 5.0
@export var base_damage_per_level: float = 1.0
## Kills from level 1 to 2; every next level needs level_kills_growth times more
## (rounded up): 20, 30, 45, 68, 102...
@export var first_level_kills: int = 20
@export var level_kills_growth: float = 1.5
@export var primary_damage_percent: float = 200.0
@export var wave_damage_percent: float = 1000.0
@export var compression_impact_percent: float = 500.0
## Every compression tick_interval while the target is squeezed.
@export var compression_tick_percent: float = 300.0

@export_category("Health")
## Before mutations; the current maximum is get_max_health().
@export var max_health: float = 100.0:
	set(value):
		max_health = value
		if stats != null:
			stats.set_base(&"max_health", value)
@export var invulnerability_duration: float = 1.0
@export var death_restart_delay: float = 1.5

@export_category("Camera")
## Zoom out at most 2x from the starting camera zoom (1.15).
@export var zoom_min: float = 0.575
@export var zoom_max: float = 1.6

## The exports above are the base values; mutations change them through
## stats (see NelvarStats), and the code reads the current values from it.
var stats := NelvarStats.new()
## Console (/god): nothing can hurt the player.
var god_mode := false
## Console (/cooldowns off): abilities are ready again right after use.
var no_cooldowns := false
var aim_direction := Vector2.RIGHT
## Grip on the ground: 1 — ordinary ground, less — slippery (the ice valley's lakes).
## The map sets it every physics frame; it scales how fast the player speeds up and
## slows down.
var traction := 1.0
## Physics layers that block the player's sight (the ice cave's walls): the wind wave and
## the compression only reach enemies the player can see. 0 (every other map): no check.
## The location sets it on its own player.
var sight_mask := 0
## Shared modifiers (the ice valley's blizzard; mutations later): a multiplier of the
## movement speed, and of the rate of attacks (cooldowns, animations, projectiles).
var move_scale := 1.0
var attack_rate := 1.0
var _primary_cooldown_left := 0.0
# Shots in the current burst and time since the last one (for the sound).
# Shot wind: strength the shots give (0..1), the heard level that follows it
# and how long the strength holds before it starts to die down.
var _wind_strength := 0.0
var _wind_level := 0.0
var _wind_hold := 0.0
# Loudness of the flight rush, 0..1 (eased, see _update_flight_air).
var _flight_air_level := 0.0
var _wave_cooldown_left := 0.0
var _compression_cooldown_left := 0.0
var _speed_boost_state := SpeedBoostState.READY
# Ctrl переключает бег/ходьбу; любая атака или остановка сбрасывает бег.
var _is_running := false
## The run this player belongs to (NelvarRun.attach() in _ready): health, level and
## mutations live there and carry to the next location.
var run := NelvarRunState.new()
var health: float:
	get:
		return run.player.health
	set(value):
		run.player.health = value
var level: int:
	get:
		return run.player.level
	set(value):
		run.player.level = value
## Kills since the last level-up.
var level_kills: int:
	get:
		return run.player.level_kills
	set(value):
		run.player.level_kills = value
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
# Полёт кончился, но под смерчем мелкий камень: приземлимся, когда он останется позади.
var _landing_pending := false
# Пустота: тело проваливается в пропасть, управление отключено.
var _is_falling := false
# Бросок (гейзер вулкана): тело летит по дуге, управление ослаблено.
var _launch_time := 0.0
var _launch_duration := 0.0
var _launch_push := Vector2.ZERO
var _launch_height := 0.0
var _max_health_now := 0.0
# Health shown by the bar, so regeneration does not spam health_changed.
var _shown_health := 0

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
## LMB: a looped wind (tools/gen_sfx.py) that the shots feed.
@onready var shot_wind: AudioStreamPlayer = $ShotWind
## RMB: one gust that rushes ahead with the wave (wind_wave.tres: three
## variants, pitch nudged at random).
@onready var wave_sound: AudioStreamPlayer = $WaveSound
## Flight: a gust on take-off, a looped rush of air while airborne (louder
## the faster the player flies) and a soft settle on landing.
@onready var lift_sound: AudioStreamPlayer = $LiftSound
@onready var flight_air: AudioStreamPlayer = $FlightAir
@onready var land_sound: AudioStreamPlayer = $LandSound


func _ready() -> void:
	_init_stats()
	run = NelvarRun.attach()
	# The run's mutations go back onto the stats before health is read off them.
	var director := get_node_or_null(^"Mutations") as NelvarMutationDirector
	if director != null:
		director.attach(run.mutations)
	_max_health_now = get_max_health()
	if health < 0.0:
		health = _max_health_now
	health = minf(health, _max_health_now)
	stats.changed.connect(_on_stats_changed)
	# Enemies report kills to this group (register_kill).
	add_to_group(&"player")
	(collision_shape.shape as CircleShape2D).radius = BODY_RADIUS
	_body_scale = body_visual.scale.abs()
	_body_rest_position = body_visual.position
	torso_sprite.animation_finished.connect(_on_torso_animation_finished)
	boost_duration_timer.timeout.connect(_on_boost_duration_timeout)
	boost_cooldown_timer.timeout.connect(_on_boost_cooldown_timeout)


func _process(delta: float) -> void:
	_update_shot_wind(delta)
	_update_flight_air(delta)
	if _is_dead or _is_falling:
		return
	_update_hover(delta)
	_update_aim()
	_primary_cooldown_left = maxf(_primary_cooldown_left - delta * attack_rate, 0.0)
	_wave_cooldown_left = maxf(_wave_cooldown_left - delta * attack_rate, 0.0)
	_compression_cooldown_left = maxf(_compression_cooldown_left - delta * attack_rate, 0.0)
	torso_sprite.speed_scale = attack_rate
	if no_cooldowns:
		reset_cooldowns()

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
	if _is_dead or _is_falling:
		return
	_invulnerability_left = maxf(_invulnerability_left - delta, 0.0)
	_attack_facing_left = maxf(_attack_facing_left - delta, 0.0)
	_regenerate(delta)

	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	if is_launched():
		_update_launch(direction, delta)
		return
	# Бег возможен только в движении: остановка его сбрасывает.
	if direction == Vector2.ZERO:
		_is_running = false

	# Полёт умножает текущую скорость: бег в полёте быстрее ходьбы в полёте.
	var speed_multiplier := 1.0
	if _is_running:
		speed_multiplier *= run_speed_multiplier
	if _speed_boost_state == SpeedBoostState.ACTIVE:
		speed_multiplier *= stats.value(&"flight_speed")
	if is_low_health():
		speed_multiplier *= 1.0 + stats.value(&"low_health_speed") / 100.0
	var target_velocity := direction * stats.value(&"move_speed") * speed_multiplier * move_scale
	# Mutations change acceleration and braking together.
	var handling := stats.value(&"acceleration") / acceleration
	var rate := (acceleration if direction != Vector2.ZERO else deceleration) * traction
	rate *= handling
	velocity = velocity.move_toward(target_velocity, rate * delta)
	move_and_slide()
	if _landing_pending and not _is_over_low_obstacle():
		_land()
	_update_animation(direction)
	# В полёте игрок проходит над врагами и не получает контактного урона.
	if not is_flight_protected():
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


## Seconds of cooldown left (0 = none). The primary shot has no cooldown, only
## a fire rate, so it always reports 0. Flight reports 0 while it is going on
## (see is_ability_active): its cooldown starts on landing.
## Abilities: &"primary", &"wave", &"flight", &"compression".
func ability_cooldown_left(ability: StringName) -> float:
	match ability:
		&"wave":
			return _wave_cooldown_left
		&"compression":
			return _compression_cooldown_left
		&"flight":
			if _speed_boost_state == SpeedBoostState.COOLDOWN:
				return boost_cooldown_timer.time_left
	return 0.0


## True while the ability is in use and cannot be used again (flight in the air).
func is_ability_active(ability: StringName) -> bool:
	return ability == &"flight" and _speed_boost_state == SpeedBoostState.ACTIVE


func base_damage() -> float:
	return base_damage_start + base_damage_per_level * (level - 1)


func kills_to_next_level() -> int:
	return ceili(first_level_kills * pow(level_kills_growth, level - 1))


## Called by an enemy when it dies (through the "player" group).
func register_kill() -> void:
	if _is_dead:
		return
	heal(stats.value(&"kill_heal"))
	enemy_killed.emit()
	level_kills += 1
	while level_kills >= kills_to_next_level():
		level_kills -= kills_to_next_level()
		level += 1
	level_changed.emit(level, level_kills, kills_to_next_level())


# `attack_stat`: the attack's own damage multiplier (primary_damage...).
# Mutations multiply it with the common damage and the situational bonuses.
func _damage(percent: float, attack_stat: StringName) -> float:
	var situational := stats.value(&"air_damage") if is_airborne() else stats.value(&"ground_damage")
	if is_low_health():
		situational += stats.value(&"low_health_damage")
	var multiplier := stats.value(&"damage") * stats.value(attack_stat) * maxf(1.0 + situational / 100.0, 0.1)
	return base_damage() * percent / 100.0 * multiplier


func is_airborne() -> bool:
	return _speed_boost_state == SpeedBoostState.ACTIVE or is_launched()


## True while thrown through the air (launch()).
func is_launched() -> bool:
	return _launch_time < _launch_duration


## Throws the player up and along `push` (world units per second) for `duration`
## seconds, the body rising `height` above the ground and coming down again. In the air
## the player is airborne (lava, enemies and low stones do not touch them) and steers
## only a little (launch_control). The flight's cooldown is not touched.
func launch(push: Vector2, height: float, duration: float) -> void:
	if _is_dead or _is_falling or duration <= 0.0:
		return
	_launch_push = push
	_launch_height = height
	_launch_duration = duration
	_launch_time = 0.0
	_landing_pending = false
	velocity = push
	set_collision_mask_value(LOW_OBSTACLE_LAYER_NUMBER, false)
	if _flight_tween != null:
		_flight_tween.kill()


func _update_launch(direction: Vector2, delta: float) -> void:
	_launch_time += delta
	var progress := clampf(_launch_time / _launch_duration, 0.0, 1.0)
	velocity = _launch_push + direction * stats.value(&"move_speed") * move_scale * launch_control
	move_and_slide()
	var lift := flight_height if _speed_boost_state == SpeedBoostState.ACTIVE else 0.0
	body_visual.position.y = _body_rest_position.y - lift - sin(PI * progress) * _launch_height
	if progress >= 1.0:
		_launch_duration = 0.0
		_launch_time = 0.0
		# The landing takes most of the speed: no sliding on along the rock.
		velocity *= 0.3
		body_visual.position.y = _body_rest_position.y - lift
		if _speed_boost_state != SpeedBoostState.ACTIVE:
			set_collision_mask_value(LOW_OBSTACLE_LAYER_NUMBER, true)
	_update_animation(direction)


## In flight the player passes over enemies and hazards unharmed, unless a
## mutation (Полый вихрь) took that away.
func is_flight_protected() -> bool:
	return is_airborne() and not stats.flag(&"flight_unprotected")


func is_dead() -> bool:
	return _is_dead


func get_max_health() -> float:
	return stats.value(&"max_health")


func is_low_health() -> bool:
	return health < get_max_health() * LOW_HEALTH_SHARE


func is_standing_still() -> bool:
	return velocity.length() < STILL_SPEED and not _is_move_input_held()


func heal(amount: float) -> void:
	if _is_dead or amount <= 0.0 or health >= get_max_health():
		return
	health = minf(health + amount, get_max_health())
	_emit_health()


func is_falling() -> bool:
	return _is_falling


# Пустота: под ногами ничего нет. Тело уходит вниз, сжимается и тает в
# фиолетовой тьме; управление вернёт recover_at(). Огненная кузня зовёт то же
# самое, когда полёт кончился над лавой, — с оранжевым `tint`.
func fall_into_abyss(duration: float, tint := Color(0.45, 0.25, 0.85, 0.0)) -> void:
	if _is_dead or _is_falling:
		return
	_is_falling = true
	_is_running = false
	_launch_duration = 0.0
	_launch_time = 0.0
	velocity = Vector2.ZERO
	wind_trail.emitting = false
	aim_pivot.visible = false
	var tween := _restart_flight_tween().set_parallel()
	tween.tween_property(body_visual, "position:y", _body_rest_position.y + 90.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(body_visual, "scale", body_visual.scale * 0.25, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(body_visual, "modulate", tint, duration)


func recover_at(point: Vector2) -> void:
	if not _is_falling:
		return
	_is_falling = false
	if _flight_tween != null:
		_flight_tween.kill()
	global_position = point
	velocity = Vector2.ZERO
	body_visual.position = _body_rest_position
	body_visual.scale = Vector2(-_body_scale.x if _facing_left else _body_scale.x, _body_scale.y)
	body_visual.modulate = Color.WHITE
	aim_pivot.visible = true
	camera.reset_smoothing()


## `from`: world point the hit came from (for the damage vignette); INF if none.
func take_damage(amount: float, from: Vector2 = Vector2.INF) -> void:
	if _is_dead or god_mode or is_flight_protected() or _invulnerability_left > 0.0 \
			or amount <= 0.0:
		return
	amount *= _damage_taken_multiplier()
	health = maxf(health - amount, 0.0)
	_emit_health()
	damaged.emit(amount, from)
	if health <= 0.0:
		_die()
		return
	_invulnerability_left = stats.value(&"invulnerability")


## Console: health straight to `value` (kept within 0..maximum), past armor,
## invulnerability and god mode. A loss counts as damage (the vignette, the
## adaptation meter); reaching zero kills.
func set_health(value: float) -> void:
	if _is_dead:
		return
	var target := clampf(value, 0.0, get_max_health())
	var lost := health - target
	health = target
	_emit_health()
	if lost > 0.0:
		damaged.emit(lost, Vector2.INF)
	if health <= 0.0:
		_die()


## Console: jumps to `value` with no kills toward the next level.
func set_level(value: int) -> void:
	level = maxi(value, 1)
	level_kills = 0
	level_changed.emit(level, level_kills, kills_to_next_level())


## Console: every ability is ready at once (flight lands first if airborne).
func reset_cooldowns() -> void:
	_primary_cooldown_left = 0.0
	_wave_cooldown_left = 0.0
	_compression_cooldown_left = 0.0
	if _speed_boost_state == SpeedBoostState.COOLDOWN:
		boost_cooldown_timer.stop()
		_on_boost_cooldown_timeout()


## Console: moves the player to `point` without the camera sliding there.
func teleport(point: Vector2) -> void:
	if _is_dead or _is_falling:
		return
	global_position = point
	velocity = Vector2.ZERO
	camera.reset_smoothing()


func _damage_taken_multiplier() -> float:
	var situational := 0.0
	if is_standing_still():
		situational -= stats.value(&"still_armor")
	else:
		situational += stats.value(&"moving_vulnerability")
	return stats.value(&"damage_taken") * maxf(1.0 + situational / 100.0, 0.1)


func _regenerate(delta: float) -> void:
	var regen := stats.value(&"regen")
	if regen <= 0.0 or health >= get_max_health():
		return
	health = minf(health + regen * delta, get_max_health())
	if ceili(health) != _shown_health:
		_emit_health()


func _emit_health() -> void:
	_shown_health = ceili(health)
	health_changed.emit(health, get_max_health())


func _init_stats() -> void:
	var bases := {
		&"move_speed": speed,
		&"acceleration": acceleration,
		&"max_health": max_health,
		&"invulnerability": invulnerability_duration,
		&"primary_cooldown": primary_cooldown,
		&"primary_spread": primary_spread_degrees,
		&"wave_cooldown": wave_cooldown,
		&"compression_cooldown": compression_cooldown,
		&"flight_duration": speed_boost_duration,
		&"flight_cooldown": speed_boost_cooldown,
		&"flight_speed": speed_boost_multiplier,
	}
	for stat in bases:
		stats.set_base(stat, bases[stat])


# A larger maximum adds the difference to health, a smaller one cuts it.
func _on_stats_changed() -> void:
	var new_max := get_max_health()
	if is_equal_approx(new_max, _max_health_now):
		return
	if new_max > _max_health_now and not _is_dead:
		health += new_max - _max_health_now
	health = minf(health, new_max)
	_max_health_now = new_max
	_emit_health()


func _check_enemy_contact() -> void:
	# Опрос каждый кадр: стоящий внутри врага игрок получает урон раз в
	# invulnerability_duration, а не только при входе.
	if _invulnerability_left > 0.0:
		return
	for body in hurtbox.get_overlapping_bodies():
		# A harmless enemy (a dazed Runner has 0) must not hide a harmful one.
		if body.is_in_group("enemies") and "contact_damage" in body \
				and float(body.get("contact_damage")) > 0.0:
			take_damage(body.get("contact_damage"), body.global_position)
			return


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
	NelvarRun.restart(get_tree(), run)


func _try_primary_attack() -> void:
	if _primary_cooldown_left > 0.0:
		return
	# Split shot: extra projectiles fan out evenly around the aim.
	var count := maxi(roundi(stats.value(&"primary_projectiles")), 1)
	var spread_degrees := stats.value(&"primary_spread")
	var spread := deg_to_rad(randf_range(-spread_degrees, spread_degrees))
	for i in count:
		var projectile := _instantiate_attack(projectile_scene, "ЛКМ-снаряд")
		if projectile == null:
			return
		var fan := deg_to_rad(FAN_STEP_DEGREES * (i - (count - 1) / 2.0))
		projectile.set("damage", _damage(primary_damage_percent, &"primary_damage"))
		projectile.set("speed", float(projectile.get("speed")) * stats.value(&"projectile_speed") * attack_rate)
		projectile.set("pierce", roundi(stats.value(&"projectile_pierce")))
		projectile.call("launch", projectile_spawn.global_position, aim_direction.rotated(spread + fan))
	_primary_cooldown_left = stats.value(&"primary_cooldown")
	_is_running = false
	_play_attack_animation(&"attack_primary")
	_feed_shot_wind()


# A shot brings the wind to full strength — never more, however often it
# fires — and holds it until the next shot is due, so held LMB is an even
# wind rather than one pulsing five times a second.
func _feed_shot_wind() -> void:
	_wind_strength = 1.0
	_wind_hold = maxf(stats.value(&"primary_cooldown") + SHOT_WIND_HOLD_SLACK, SHOT_WIND_MIN_HOLD)


# The heard level eases towards the strength the shots gave (exponentially,
# so it has no corners): it swells in, and once no shot keeps the strength
# up, it drifts away. A stronger wind is also a touch higher, like air
# speeding up. Silent wind is stopped.
func _update_shot_wind(delta: float) -> void:
	if _is_dead or _is_falling:
		_wind_strength = 0.0
	_wind_hold -= delta
	if _wind_hold <= 0.0:
		_wind_strength = maxf(_wind_strength - delta / shot_wind_fade, 0.0)
	var ease_time := shot_wind_rise if _wind_strength > _wind_level else shot_wind_release
	_wind_level = lerpf(_wind_level, _wind_strength, 1.0 - exp(-delta / ease_time))
	if _wind_strength <= 0.0 and _wind_level < SHOT_WIND_SILENT:
		_wind_level = 0.0
		if shot_wind.playing:
			shot_wind.stop()
		return
	if not shot_wind.playing:
		# A random point of the loop, so puffs do not all sound alike.
		shot_wind.play(randf() * shot_wind.stream.get_length())
	shot_wind.volume_db = shot_wind_volume_db + linear_to_db(_wind_level)
	shot_wind.pitch_scale = lerpf(0.96, 1.04, _wind_level)


# The flight rush eases in after take-off, follows the flying speed (quiet
# when hovering, louder and a touch higher at full speed) and eases out on
# landing or death. Silent, it is stopped.
func _update_flight_air(delta: float) -> void:
	var target := 0.0
	if is_airborne() and not _is_dead and not _is_falling:
		var top_speed := stats.value(&"move_speed") * stats.value(&"flight_speed") * run_speed_multiplier
		var speed := clampf(velocity.length() / maxf(top_speed, 1.0), 0.0, 1.0)
		target = db_to_linear(-flight_air_still_db * (1.0 - speed))
	var ease_time := FLIGHT_AIR_RISE if target > _flight_air_level else FLIGHT_AIR_RELEASE
	_flight_air_level = lerpf(_flight_air_level, target, 1.0 - exp(-delta / ease_time))
	if target <= 0.0 and _flight_air_level < SHOT_WIND_SILENT:
		_flight_air_level = 0.0
		if flight_air.playing:
			flight_air.stop()
		return
	if not flight_air.playing:
		flight_air.play(randf() * flight_air.stream.get_length())
	flight_air.volume_db = flight_air_volume_db + linear_to_db(_flight_air_level)
	flight_air.pitch_scale = lerpf(0.95, 1.05, _flight_air_level)


func _try_wave_attack() -> void:
	if _wave_cooldown_left > 0.0:
		return
	var wave := _instantiate_attack(wave_scene, "ПКМ-волна")
	if wave == null:
		return
	_wave_cooldown_left = stats.value(&"wave_cooldown")
	_is_running = false
	_play_attack_animation(&"attack_wave")
	wave_sound.play()
	wave.set("damage", _damage(wave_damage_percent, &"wave_damage"))
	wave.set("travel_distance", float(wave.get("travel_distance")) * stats.value(&"wave_range"))
	wave.set("size_multiplier", stats.value(&"wave_size"))
	if attack_rate != 1.0:
		wave.set("duration", float(wave.get("duration")) / maxf(attack_rate, 0.05))
	var wave_origin := get_aim_origin() + aim_direction * wave_spawn_distance
	if sight_mask != 0:
		wave.set("sight_from", global_position)
		wave.set("sight_mask", sight_mask)
	wave.call("launch", wave_origin, aim_direction)


func _try_speed_boost() -> void:
	if _speed_boost_state != SpeedBoostState.READY:
		return
	_speed_boost_state = SpeedBoostState.ACTIVE
	# В полёте мелкие валуны остаются внизу.
	set_collision_mask_value(LOW_OBSTACLE_LAYER_NUMBER, false)
	boost_duration_timer.start(stats.value(&"flight_duration"))
	# Thrown by a geyser the body is already in the air; the throw places it.
	if not is_launched():
		_play_lift_off()
	lift_sound.play()


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
	_compression_cooldown_left = stats.value(&"compression_cooldown")
	_is_running = false
	_play_attack_animation(&"attack_compression")
	compression.set("impact_damage", _damage(compression_impact_percent, &"compression_damage"))
	compression.set("tick_damage", _damage(compression_tick_percent, &"compression_damage"))
	compression.call("start_compression", target, get_aim_origin())


# Ближайший к курсору враг в пределах compression_target_radius от курсора
# и compression_max_range от игрока.
func _find_compression_target() -> Node2D:
	var cursor := get_global_mouse_position()
	var max_range := compression_max_range * stats.value(&"compression_range")
	var max_range_sq := max_range * max_range
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
		if distance_sq <= best_distance_sq and can_see(enemy.global_position):
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
	# Над валуном не садимся — иначе смерч застрянет в камне.
	if not _is_dead and _is_over_low_obstacle():
		_landing_pending = true
		return
	_land()


func _land() -> void:
	_landing_pending = false
	_speed_boost_state = SpeedBoostState.COOLDOWN
	boost_cooldown_timer.start(stats.value(&"flight_cooldown"))
	# Still thrown by a geyser: the throw ends the landing itself.
	if is_launched():
		return
	set_collision_mask_value(LOW_OBSTACLE_LAYER_NUMBER, true)
	if not _is_dead:
		_play_landing()
		land_sound.play()


# Перекрывает ли след смерча мелкий валун (слой, который в полёте не мешает).
func _is_over_low_obstacle() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = NelvarProp.LOW_OBSTACLE_LAYER
	query.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _on_boost_cooldown_timeout() -> void:
	_speed_boost_state = SpeedBoostState.READY


## True when nothing on sight_mask stands between the player and `point` (always true
## without a sight_mask).
func can_see(point: Vector2) -> bool:
	return sight_clear(get_world_2d(), global_position, point, sight_mask)


## The same check from any point (the wind wave asks from where it was cast, with the
## caster's mask).
static func sight_clear(world: World2D, from: Vector2, to: Vector2, mask: int) -> bool:
	if mask == 0 or world == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to, mask)
	return world.direct_space_state.intersect_ray(query).is_empty()
