extends Node2D

# R-сжатие: наводимая способность. Две дуги-волны сходятся на выбранной цели
# с двух сторон, бьют, затем держат и сжимают её, нанося периодический урон.
# Узел каждый кадр ставится в позицию цели, поэтому промаха нет; урон идёт
# напрямую через take_damage, без коллизий.
#
# Серп волны — спрайтшит из tools/gen_attack_sprites.py: колонки — цикл кадров
# (блики сбегаются к оси, завитки-«пальцы» дышат), строки — направления
# 0..90°, прочие получаются отражением. Центр кадра — центр дуги, вершина
# серпа (позиция WaveA/WaveB) — на ARC_RADIUS впереди. Спрайт не вращается
# и не масштабируется вместе с узлами — пиксели как у игрока.

enum Phase { IDLE, APPROACH, SQUEEZE, FADE }

const SHEET_TEXEL := 3.0
const ARC_RADIUS := 69.0  # = COMPRESSION_RADIUS (46) * 1.5 из gen_attack_sprites.py
const ARC_HALF_ANGLE := deg_to_rad(64.0)  # как A в compression_frame()
const VORTEX_SCRIPT := preload("res://attacks/wind_compression/compression_vortex.gd")

@export_category("Motion")
@export var approach_distance: float = 220.0
@export var hold_distance: float = 26.0
@export var approach_duration: float = 0.3
@export var squeeze_duration: float = 3.0
@export var fade_duration: float = 0.2
@export var fade_spread: float = 14.0

@export_category("Damage")
## Both set by the player from its base damage (compression_*_percent).
@export var impact_damage: float = 10.0
@export var tick_damage: float = 5.0
@export var tick_interval: float = 0.25

@export_category("Visual")
@export var pulse_distance: float = 6.0
@export var pulse_frequency: float = 4.0
@export var approach_start_alpha: float = 0.35
## Кадров цикла серпа в секунду; при сжатии воздух бежит быстрее.
@export var frame_rate: float = 12.0
@export var squeeze_frame_rate: float = 18.0
## Воздух (сосед-узел CompressionVortex, штрихи ветра): линии скорости за
## серпами при сближении, брызги вбок при ударе, вихрь вокруг цели при сжатии.
@export var approach_air_rate: float = 70.0
@export var squeeze_air_rate: float = 60.0
@export var impact_air_burst: int = 14

@export_category("Sound")
## The hold loop rises from the first pitch to the second over the squeeze:
## the pressure builds (sounds: tools/gen_sfx.py, compression_*).
@export var hold_pitch_start: float = 0.94
@export var hold_pitch_end: float = 1.1
## Seconds for the sounds to fade out when the compression ends.
@export var sound_fade: float = 0.3

var _target: Node2D
var _phase := Phase.IDLE
var _phase_time := 0.0
var _ticks_done := 0
var _wave_distance := 0.0
var _fade_start_distance := 0.0
var _fade_start_alpha := 1.0
var _anim_time := 0.0
var _air: CompressionVortex
var _air_carry := 0.0

@onready var axis: Node2D = $Axis
@onready var wave_a: Node2D = $Axis/WaveA
@onready var wave_b: Node2D = $Axis/WaveB
## Air rushing in and striking; its strike lands on the impact (0.3 s).
@onready var start_sound: AudioStreamPlayer = $StartSound
## The squeeze: a looped tight wind, playing from the impact to the end.
@onready var hold_sound: AudioStreamPlayer = $HoldSound


func _ready() -> void:
	visible = false


func start_compression(target: Node2D, caster_position: Vector2) -> void:
	if not _is_target_alive(target):
		queue_free()
		return
	_target = target
	global_position = target.global_position

	# Ось волн перпендикулярна линии «игрок → цель»: волны заходят
	# слева и справа от цели, если смотреть со стороны игрока.
	var to_target := target.global_position - caster_position
	if to_target.length_squared() < 0.0001:
		to_target = Vector2.RIGHT
	axis.rotation = to_target.orthogonal().angle()
	_setup_sprite(wave_a.get_node("Sprite"), axis.rotation)
	_setup_sprite(wave_b.get_node("Sprite"), axis.rotation + PI)

	_set_waves(approach_distance, approach_start_alpha)
	_setup_air()
	visible = true
	start_sound.play()
	_enter_phase(Phase.APPROACH)


func _physics_process(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	_phase_time += delta
	_anim_time += delta * (squeeze_frame_rate if _phase == Phase.SQUEEZE else frame_rate)
	_animate_sprites()

	if _phase != Phase.FADE:
		if not _is_target_alive(_target):
			_start_fade()
		else:
			global_position = _target.global_position
			if _air != null and is_instance_valid(_air):
				_air.center = global_position

	match _phase:
		Phase.APPROACH:
			_update_approach()
		Phase.SQUEEZE:
			_update_squeeze()
		Phase.FADE:
			_update_fade()


func _update_approach() -> void:
	var t := clampf(_phase_time / maxf(approach_duration, 0.01), 0.0, 1.0)
	var eased := t * t
	_set_waves(
		lerpf(approach_distance, hold_distance, eased),
		lerpf(approach_start_alpha, 1.0, t)
	)
	_emit_air(approach_air_rate, _emit_arc_puff)
	if t >= 1.0:
		_impact()


func _impact() -> void:
	_deal_damage(impact_damage)
	_spurt(impact_air_burst, 1.0)
	if not _is_target_alive(_target):
		_start_fade()
		return
	if _target.has_method("apply_hold"):
		_target.call("apply_hold", squeeze_duration)
	_ticks_done = 0
	hold_sound.pitch_scale = hold_pitch_start
	hold_sound.play()
	_enter_phase(Phase.SQUEEZE)


func _update_squeeze() -> void:
	hold_sound.pitch_scale = lerpf(hold_pitch_start, hold_pitch_end,
		clampf(_phase_time / maxf(squeeze_duration, 0.01), 0.0, 1.0))
	var pulse := sin(_phase_time * TAU * pulse_frequency)
	_set_waves(
		hold_distance + pulse_distance * pulse,
		0.85 + 0.15 * pulse
	)

	if tick_interval > 0.0:
		var total_ticks := int(round(squeeze_duration / tick_interval))
		while (
			_ticks_done < total_ticks
			and _phase_time >= (_ticks_done + 1) * tick_interval - 0.0001
		):
			_ticks_done += 1
			_deal_damage(tick_damage)
			_spurt(5, 0.7)
			if not _is_target_alive(_target):
				_start_fade()
				return

	_emit_air(squeeze_air_rate, _emit_swirl_puff)
	if _phase_time >= squeeze_duration:
		_start_fade()


func _start_fade() -> void:
	if _phase == Phase.FADE:
		return
	_fade_start_distance = _wave_distance
	_fade_start_alpha = modulate.a
	_fade_sounds()
	if _air != null and is_instance_valid(_air):
		_air.release()
	_enter_phase(Phase.FADE)


func _update_fade() -> void:
	var t := clampf(_phase_time / maxf(fade_duration, 0.01), 0.0, 1.0)
	_set_waves(
		_fade_start_distance + fade_spread * t,
		lerpf(_fade_start_alpha, 0.0, t)
	)
	if t >= 1.0:
		_phase = Phase.IDLE
		visible = false
		# Freed only once the sounds have faded, or they would be cut off.
		var remaining := maxf(sound_fade - fade_duration, 0.0) + 0.05
		get_tree().create_timer(remaining, false).timeout.connect(queue_free)


# A finished compression fades out what is still sounding instead of
# cutting it: the hold loop, and the strike too if the target died before it.
func _fade_sounds() -> void:
	var tween := create_tween().set_parallel()
	for player: AudioStreamPlayer in [start_sound, hold_sound]:
		if player.playing:
			tween.tween_property(player, "volume_db", player.volume_db - 40.0, sound_fade) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(hold_sound.stop)


func _enter_phase(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


func _set_waves(distance: float, alpha: float) -> void:
	_wave_distance = distance
	wave_a.position = Vector2(-distance, 0.0)
	wave_b.position = Vector2(distance, 0.0)
	modulate.a = alpha


# facing — мировой угол, куда смотрит выпуклость серпа (на цель).
func _setup_sprite(sprite: Sprite2D, facing: float) -> void:
	var dir := Vector2.from_angle(facing)
	var row_count := sprite.vframes
	var base_angle := atan2(absf(dir.y), absf(dir.x))
	sprite.frame_coords = Vector2i(0, clampi(
		roundi(base_angle / (PI * 0.5) * (row_count - 1)), 0, row_count - 1
	))
	sprite.flip_h = dir.x < 0.0
	sprite.flip_v = dir.y < 0.0
	# Центр дуги позади вершины; волна-родитель смотрит выпуклостью по +x.
	sprite.position = Vector2(-ARC_RADIUS, 0.0)
	sprite.global_rotation = 0.0
	sprite.global_scale = Vector2(SHEET_TEXEL, SHEET_TEXEL)


func _animate_sprites() -> void:
	for wave: Node2D in [wave_a, wave_b]:
		var sprite: Sprite2D = wave.get_node("Sprite")
		sprite.frame_coords = Vector2i(int(_anim_time) % sprite.hframes, sprite.frame_coords.y)


# Воздух — сосед сжатия, а не ребёнок: штрихи живут в мире и дотаивают
# после него. Добавлен перед узлом, поэтому рисуется под серпами.
func _setup_air() -> void:
	var parent := get_parent()
	if parent == null or _air != null:
		return
	_air = VORTEX_SCRIPT.new()
	_air.center = global_position
	_air.swirl = 1.0 if randf() < 0.5 else -1.0
	parent.add_child(_air)
	parent.move_child(_air, get_index())


func _emit_air(rate: float, emit: Callable) -> void:
	if _air == null or not is_instance_valid(_air):
		return
	_air_carry += get_physics_process_delta_time() * rate
	while _air_carry >= 1.0:
		_air_carry -= 1.0
		emit.call()


# Сближение: линии скорости — штрихи срываются с задней кромки серпов
# и летят следом, отставая.
func _emit_arc_puff() -> void:
	var wave: Node2D = wave_a if randf() < 0.5 else wave_b
	var angle := ARC_HALF_ANGLE * randf_range(-0.9, 0.9)
	var local := Vector2.from_angle(angle) * ARC_RADIUS * randf_range(0.8, 0.92)
	var at := wave.to_global(local - Vector2(ARC_RADIUS, 0.0))
	var facing := wave.global_transform.x.normalized()
	_air.emit_line(at, facing * randf_range(180.0, 320.0), 0.25, 5.0)


# Сжатие: воздух кружит вокруг цели и по спирали втягивается в неё.
func _emit_swirl_puff() -> void:
	_air.emit_swirl(hold_distance + 16.0, hold_distance + 46.0)


# Сдавленный воздух брызгает туда, где серпов нет — поперёк их оси.
func _spurt(count: int, strength: float) -> void:
	if _air == null or not is_instance_valid(_air):
		return
	var across := axis.global_transform.y.normalized()
	for i in count:
		var side := 1.0 if i % 2 == 0 else -1.0
		var dir := (across * side).rotated(randf_range(-0.45, 0.45))
		var velocity := dir * randf_range(260.0, 420.0) * strength
		_air.emit_line(global_position + dir * randf_range(6.0, 14.0), velocity, 0.3, 4.5)


func _deal_damage(amount: float) -> void:
	if amount > 0.0 and _is_target_alive(_target) \
			and _target.has_method("take_damage"):
		_target.call("take_damage", amount)


func _is_target_alive(target) -> bool:
	return (
		is_instance_valid(target)
		and target.is_inside_tree()
		and target.is_in_group("enemies")
	)
