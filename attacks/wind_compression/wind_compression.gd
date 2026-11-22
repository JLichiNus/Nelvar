extends Node2D

# R-сжатие: наводимая способность. Две дуги-волны сходятся на выбранной цели
# с двух сторон, бьют, затем держат и сжимают её, нанося периодический урон.
# Узел каждый кадр ставится в позицию цели, поэтому промаха нет; урон идёт
# напрямую через take_damage, без коллизий.

enum Phase { IDLE, APPROACH, SQUEEZE, FADE }

@export_category("Motion")
@export var approach_distance: float = 220.0
@export var hold_distance: float = 26.0
@export var approach_duration: float = 0.3
@export var squeeze_duration: float = 3.0
@export var fade_duration: float = 0.2
@export var fade_spread: float = 14.0

@export_category("Damage")
@export var impact_damage: float = 10.0
@export var tick_damage: float = 5.0
@export var tick_interval: float = 0.25

@export_category("Visual")
@export var wave_scale: float = 2.0
@export var pulse_distance: float = 6.0
@export var pulse_scale: float = 0.06
@export var pulse_frequency: float = 4.0
@export var approach_start_alpha: float = 0.35

var _target: Node2D
var _phase := Phase.IDLE
var _phase_time := 0.0
var _ticks_done := 0
var _wave_distance := 0.0
var _fade_start_distance := 0.0
var _fade_start_alpha := 1.0

@onready var axis: Node2D = $Axis
@onready var wave_a: Node2D = $Axis/WaveA
@onready var wave_b: Node2D = $Axis/WaveB


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

	_set_waves(approach_distance, wave_scale, approach_start_alpha)
	visible = true
	_enter_phase(Phase.APPROACH)


func _physics_process(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	_phase_time += delta

	if _phase != Phase.FADE:
		if not _is_target_alive(_target):
			_start_fade()
		else:
			global_position = _target.global_position

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
		wave_scale,
		lerpf(approach_start_alpha, 1.0, t)
	)
	if t >= 1.0:
		_impact()


func _impact() -> void:
	_deal_damage(impact_damage)
	if not _is_target_alive(_target):
		_start_fade()
		return
	if _target.has_method("apply_hold"):
		_target.call("apply_hold", squeeze_duration)
	_ticks_done = 0
	_enter_phase(Phase.SQUEEZE)


func _update_squeeze() -> void:
	var pulse := sin(_phase_time * TAU * pulse_frequency)
	_set_waves(
		hold_distance + pulse_distance * pulse,
		wave_scale * (1.0 + pulse_scale * pulse),
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
			if not _is_target_alive(_target):
				_start_fade()
				return

	if _phase_time >= squeeze_duration:
		_start_fade()


func _start_fade() -> void:
	if _phase == Phase.FADE:
		return
	_fade_start_distance = _wave_distance
	_fade_start_alpha = modulate.a
	_enter_phase(Phase.FADE)


func _update_fade() -> void:
	var t := clampf(_phase_time / maxf(fade_duration, 0.01), 0.0, 1.0)
	_set_waves(
		_fade_start_distance + fade_spread * t,
		wave_scale,
		lerpf(_fade_start_alpha, 0.0, t)
	)
	if t >= 1.0:
		_phase = Phase.IDLE
		queue_free()


func _enter_phase(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


func _set_waves(distance: float, wave_size: float, alpha: float) -> void:
	_wave_distance = distance
	wave_a.position = Vector2(-distance, 0.0)
	wave_b.position = Vector2(distance, 0.0)
	wave_a.scale = Vector2.ONE * wave_size
	wave_b.scale = Vector2.ONE * wave_size
	modulate.a = alpha


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
